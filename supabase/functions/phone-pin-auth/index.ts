import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
};

function respond(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function normalizePhoneNumber(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  const digits = trimmed.replace(/\D/g, "");
  if (digits.length === 10) return `+91${digits}`;
  if (digits.length === 12 && digits.startsWith("91")) return `+${digits}`;
  if (trimmed.startsWith("+") && digits.length >= 8 && digits.length <= 15) {
    return `+${digits}`;
  }
  return null;
}

function isPublicApiKey(value: string): boolean {
  if (value.startsWith("sb_publishable_")) return true;
  const segments = value.split(".");
  if (segments.length !== 3) return false;
  try {
    const payload = segments[1].replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(payload)) as { role?: unknown };
    return claims.role === "anon";
  } catch {
    return false;
  }
}

function toHex(value: ArrayBuffer): string {
  return Array.from(new Uint8Array(value), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

async function hmac(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return toHex(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value)),
  );
}

async function consumeLimit(
  admin: ReturnType<typeof createClient>,
  bucketHash: string,
  maxAttempts: number,
): Promise<boolean> {
  const { data, error } = await admin.rpc("consume_phone_pin_attempt", {
    p_bucket_hash: bucketHash,
    p_max_attempts: maxAttempts,
    p_window_seconds: 900,
  });
  if (error) {
    console.error("Could not check phone PIN rate limit:", error.message);
    throw new Error("Sign-in is temporarily unavailable. Please try again.");
  }
  return data === true;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return respond(405, { message: "Method not allowed." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const pinSecret = Deno.env.get("PHONE_PIN_SECRET");
  const clientApiKey = request.headers.get("apikey");
  if (!supabaseUrl || !serviceRoleKey || !pinSecret || !clientApiKey) {
    console.error("Phone PIN auth function is missing required secrets.");
    return respond(500, { message: "Sign-in is temporarily unavailable." });
  }

  if (!isPublicApiKey(clientApiKey)) {
    return respond(401, { message: "Invalid API key." });
  }

  let payload: Record<string, unknown>;
  try {
    const decoded: unknown = await request.json();
    if (typeof decoded !== "object" || decoded === null || Array.isArray(decoded)) {
      return respond(400, { message: "Invalid request." });
    }
    payload = decoded as Record<string, unknown>;
  } catch {
    return respond(400, { message: "Invalid request." });
  }

  const action = payload.action;
  const phone = normalizePhoneNumber(payload.phone);
  const pin = payload.pin;
  if (
    (action !== "register" && action !== "login") ||
    !phone ||
    typeof pin !== "string" ||
    !/^\d{4}$/.test(pin)
  ) {
    return respond(400, { message: "Enter a valid mobile number and 4-digit MPIN." });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    const phoneHash = await hmac(pinSecret, `phone:${phone}`);
    const ip =
      request.headers.get("cf-connecting-ip") ??
      request.headers.get("x-real-ip") ??
      request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      "unknown";
    const ipHash = await hmac(pinSecret, `ip:${ip}`);

    if (
      !(await consumeLimit(admin, `phone:${phoneHash}`, 5)) ||
      !(await consumeLimit(admin, `ip:${ipHash}`, 30))
    ) {
      return respond(429, {
        message: "Too many attempts. Please wait 15 minutes before trying again.",
      });
    }

    const derivedPassword = await hmac(
      pinSecret,
      `password:v1:${phone}:${pin}`,
    );

    if (action === "register") {
      const { error } = await admin.auth.admin.createUser({
        phone,
        password: derivedPassword,
        phone_confirm: true,
        user_metadata: {
          full_name: `Member ${phone.slice(-4)}`,
          phone,
          role: "rider",
        },
      });
      if (error) {
        if (
          error.code === "user_already_exists" ||
          error.code === "phone_exists"
        ) {
          return respond(409, {
            message: "An account with this mobile number already exists. Log in instead.",
          });
        }
        console.error("Phone PIN account creation failed:", error.message);
        return respond(400, { message: "Account creation failed. Check the details and retry." });
      }

      return respond(201, {
        message: "Account created.",
      });
    }

    const auth = createClient(supabaseUrl, clientApiKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data, error } = await auth.auth.signInWithPassword({
      phone,
      password: derivedPassword,
    });
    if (error || !data.session) {
      return respond(401, { message: "Mobile number or MPIN is incorrect." });
    }

    return respond(200, {
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
      token_type: data.session.token_type,
      expires_in: data.session.expires_in,
      userId: data.user.id,
    });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Sign-in is temporarily unavailable.";
    return respond(503, { message });
  }
});
