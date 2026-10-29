import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
};

const PAYMENT_AMOUNT_PAISE = 3900;
const PROVIDER = "pinelabs";
const DEFAULT_CALLBACK_URL = "https://otoridesindia-beep.github.io/coRiderly/";
const PINELABS_ENDPOINTS = {
  uat: "https://pluraluat.v2.pinepg.in",
  production: "https://api.pluralpay.in",
};

type PineLabsConfig = {
  merchantId: string;
  clientId: string;
  clientSecret: string;
  callbackUrl: string;
  apiBaseUrl: string;
};

type RideDetails = {
  origin: string;
  destination: string;
  pickup_point: string | null;
  travel_date: string;
  departure_time: string;
  car_model: string;
  car_registration: string;
  car_capacity: number;
  available_seats: number;
  bags: number;
  price_per_seat: number;
};

type PineLabsStatus = {
  state: string;
  amount: number | null;
  transactionId: string | null;
  merchantId: string | null;
};

let cachedToken: { value: string; expiresAt: number } | null = null;

function respond(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readRide(value: unknown): RideDetails | null {
  if (!isRecord(value)) return null;
  const {
    origin,
    destination,
    pickup_point,
    travel_date,
    departure_time,
    car_model,
    car_registration,
    car_capacity,
    available_seats,
    bags,
    price_per_seat,
  } = value;
  if (
    typeof origin !== "string" || !origin.trim() ||
    typeof destination !== "string" || !destination.trim() ||
    (pickup_point !== null && typeof pickup_point !== "string") ||
    typeof travel_date !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(travel_date) ||
    typeof departure_time !== "string" ||
    !/^\d{2}:\d{2}$/.test(departure_time) ||
    typeof car_model !== "string" || !car_model.trim() ||
    typeof car_registration !== "string" || !car_registration.trim() ||
    (car_capacity !== 5 && car_capacity !== 7) ||
    typeof available_seats !== "number" ||
    !Number.isInteger(available_seats) ||
    available_seats < 1 || available_seats >= car_capacity ||
    typeof bags !== "number" ||
    !Number.isInteger(bags) || bags < 0 || bags > 10 ||
    typeof price_per_seat !== "number" ||
    !Number.isFinite(price_per_seat) || price_per_seat <= 0
  ) {
    return null;
  }
  return {
    origin: origin.trim(),
    destination: destination.trim(),
    pickup_point: typeof pickup_point === "string" && pickup_point.trim()
      ? pickup_point.trim()
      : null,
    travel_date,
    departure_time,
    car_model: car_model.trim(),
    car_registration: car_registration.trim(),
    car_capacity,
    available_seats,
    bags,
    price_per_seat,
  };
}

function readPineLabsConfig(): PineLabsConfig | null {
  const merchantId = Deno.env.get("PINELABS_MID");
  const clientId = Deno.env.get("PINELABS_CLIENT_ID");
  const clientSecret = Deno.env.get("PINELABS_CLIENT_SECRET");
  if (!merchantId || !clientId || !clientSecret) return null;
  const environment = Deno.env.get("PINELABS_ENV") === "production"
    ? "production"
    : "uat";
  return {
    merchantId,
    clientId,
    clientSecret,
    callbackUrl: Deno.env.get("PINELABS_CALLBACK_URL") || DEFAULT_CALLBACK_URL,
    apiBaseUrl: PINELABS_ENDPOINTS[environment],
  };
}

function requestHeaders(): Record<string, string> {
  return {
    "Content-Type": "application/json",
    "Request-ID": crypto.randomUUID(),
    "Request-Timestamp": new Date().toISOString(),
  };
}

async function getPineLabsToken(config: PineLabsConfig): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) return cachedToken.value;

  const response = await fetch(`${config.apiBaseUrl}/api/auth/v1/token`, {
    method: "POST",
    headers: requestHeaders(),
    body: JSON.stringify({
      client_id: config.clientId,
      client_secret: config.clientSecret,
      grant_type: "client_credentials",
    }),
  });
  const result: unknown = await response.json().catch(() => null);
  if (!response.ok || !isRecord(result) || typeof result.access_token !== "string") {
    console.error("Pine Labs token request failed:", { status: response.status });
    throw new Error(
      `Payment provider authorization failed (HTTP ${response.status}).`,
    );
  }
  const parsedExpiry = typeof result.expires_at === "string"
    ? Math.floor(Date.parse(result.expires_at) / 1000)
    : Number.NaN;
  cachedToken = {
    value: result.access_token,
    expiresAt: Number.isFinite(parsedExpiry) ? parsedExpiry : now + 300,
  };
  return cachedToken.value;
}

async function pineLabsRequest(
  config: PineLabsConfig,
  path: string,
  method: "GET" | "POST",
  body?: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const token = await getPineLabsToken(config);
  const response = await fetch(`${config.apiBaseUrl}${path}`, {
    method,
    headers: {
      ...requestHeaders(),
      Authorization: `Bearer ${token}`,
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const result: unknown = await response.json().catch(() => null);
  if (!response.ok || !isRecord(result)) {
    const code = isRecord(result) && typeof result.response_code === "number"
      ? String(result.response_code)
      : "unknown";
    const detail = isRecord(result)
      ? [result.response_message, result.message, result.error_message]
        .find((item) => typeof item === "string") as string | undefined
      : undefined;
    console.error("Pine Labs API request failed:", {
      status: response.status,
      code,
      path,
      body: result,
    });
    throw new Error(
      `Payment provider request failed (HTTP ${response.status}, ${code})${
        detail ? `: ${detail.slice(0, 160)}` : ""
      }.`,
    );
  }
  return result;
}

async function createPineLabsOrder(
  config: PineLabsConfig,
  merchantOrderReference: string,
  userId: string,
  phone: string,
): Promise<{ orderId: string; redirectUrl: string }> {
  const result = await pineLabsRequest(config, "/api/checkout/v1/orders", "POST", {
    merchant_order_reference: merchantOrderReference,
    order_amount: { value: PAYMENT_AMOUNT_PAISE, currency: "INR" },
    integration_mode: "IFRAME",
    notes: "CoRiderly ride publishing fee",
    callback_url: config.callbackUrl,
    failure_callback_url: config.callbackUrl,
    purchase_details: {
      customer: {
        customer_id: userId.slice(0, 19),
        mobile_number: phone,
        country_code: "91",
      },
    },
  });
  const response = isRecord(result.data) ? result.data : result;
  const orderId = typeof response.order_id === "string"
    ? response.order_id
    : null;
  const redirectUrl = typeof response.redirect_url === "string"
    ? response.redirect_url
    : null;
  if (!orderId || !redirectUrl || !redirectUrl.startsWith("https://")) {
    throw new Error("Payment provider did not return a usable order.");
  }
  return { orderId, redirectUrl };
}

async function getPineLabsStatus(
  config: PineLabsConfig,
  orderId: string,
): Promise<PineLabsStatus> {
  const response = await pineLabsRequest(
    config,
    `/api/pay/v1/orders/${encodeURIComponent(orderId)}`,
    "GET",
  );
  const result = isRecord(response.data) ? response.data : response;
  const payment = Array.isArray(result.payments)
    ? result.payments.filter(isRecord).find((item) => item.status === "PROCESSED")
    : undefined;
  const orderAmount = isRecord(result.order_amount) &&
      typeof result.order_amount.value === "number" &&
      result.order_amount.currency === "INR"
    ? result.order_amount.value
    : null;
  const paymentAmount = payment && isRecord(payment.payment_amount) &&
      typeof payment.payment_amount.value === "number" &&
      payment.payment_amount.currency === "INR"
    ? payment.payment_amount.value
    : null;
  return {
    state: typeof result.status === "string" ? result.status : "UNKNOWN",
    amount: orderAmount === PAYMENT_AMOUNT_PAISE &&
        paymentAmount === PAYMENT_AMOUNT_PAISE
      ? PAYMENT_AMOUNT_PAISE
      : null,
    transactionId: payment && typeof payment.id === "string"
      ? payment.id
      : null,
    merchantId: typeof result.merchant_id === "string"
      ? result.merchant_id
      : null,
  };
}

async function publishPaidRide(
  admin: ReturnType<typeof createClient>,
  rideId: string,
  userId: string,
  orderId: string,
  transactionId: string,
) {
  const { data: publishedRideId, error: publishError } = await admin.rpc(
    "publish_paid_ride",
    {
      p_ride_id: rideId,
      p_driver_id: userId,
      p_provider_order_id: orderId,
      p_provider_payment_id: transactionId,
    },
  );
  if (publishError || publishedRideId !== rideId) {
    console.error("Could not publish verified paid ride:", publishError?.message);
    throw new Error("Payment is confirmed, but the ride could not be published. Contact support.");
  }
  const { data: ride, error: rideError } = await admin
    .from("rides")
    .select("*")
    .eq("id", rideId)
    .single();
  if (rideError || !ride) {
    throw new Error("Payment succeeded, but the ride could not be loaded. Refresh your rides.");
  }
  return ride;
}

function readPhone(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const digits = value.replace(/\D/g, "").slice(-10);
  return /^[6-9]\d{9}$/.test(digits) ? digits : null;
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
  const config = readPineLabsConfig();
  if (!supabaseUrl || !serviceRoleKey || !config) {
    console.error("Ride payment function is missing required secrets.");
    return respond(503, { message: "Payments are not configured yet." });
  }

  const authorization = request.headers.get("authorization") ?? "";
  const accessToken = authorization.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length)
    : "";
  if (!accessToken) {
    return respond(401, { message: "Please log in before paying to publish a ride." });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(accessToken);
  if (userError || !userData.user) {
    return respond(401, { message: "Your session expired. Please log in again." });
  }

  let payload: Record<string, unknown>;
  try {
    const decoded: unknown = await request.json();
    if (!isRecord(decoded)) return respond(400, { message: "Invalid payment request." });
    payload = decoded;
  } catch {
    return respond(400, { message: "Invalid payment request." });
  }

  try {
    if (payload.action === "create_order") {
      if (typeof payload.ride_id === "string" && payload.ride_id) {
        const { data: existing, error } = await admin
          .from("ride_payments")
          .select("ride_id, provider, provider_order_id, provider_payment_id, status")
          .eq("ride_id", payload.ride_id)
          .eq("payer_id", userData.user.id)
          .maybeSingle();
        if (error) throw new Error("Could not check the pending ride payment.");
        if (existing?.status === "paid") {
          return respond(200, {
            already_paid: true,
            ride_id: existing.ride_id,
          });
        }
        if (!existing || existing.status !== "created") {
          return respond(409, { message: "This ride payment can no longer be resumed. Start a new ride offer." });
        }
        if (existing.provider !== PROVIDER) {
          return respond(409, {
            message: "This pending ride uses a different payment provider. Retry to create a new Pine Labs order.",
          });
        }
        const previousOrderId = String(existing.provider_order_id);
        const previous = await getPineLabsStatus(config, previousOrderId);
        if (
          previous?.state === "PROCESSED" &&
          previous.amount === PAYMENT_AMOUNT_PAISE &&
          previous.merchantId === config.merchantId &&
          previous.transactionId
        ) {
          await publishPaidRide(
            admin,
            String(existing.ride_id),
            userData.user.id,
            previousOrderId,
            previous.transactionId,
          );
          return respond(200, { already_paid: true, ride_id: existing.ride_id });
        }
        const resumedOrderReference = `cr_${crypto.randomUUID().replaceAll("-", "")}`;
        const phone = readPhone(payload.phone);
        if (!phone) return respond(400, { message: "Enter a valid 10-digit Indian mobile number." });
        const resumedOrder = await createPineLabsOrder(
          config,
          resumedOrderReference,
          userData.user.id,
          phone,
        );
        const { error: resumeError } = await admin
          .from("ride_payments")
          .update({ provider_order_id: resumedOrder.orderId })
          .eq("ride_id", existing.ride_id)
          .eq("payer_id", userData.user.id)
          .eq("status", "created");
        if (resumeError) throw new Error("Could not resume the ride payment. Start a new ride offer.");
        return respond(200, {
          provider_order_id: resumedOrder.orderId,
          redirect_url: resumedOrder.redirectUrl,
          ride_id: existing.ride_id,
          amount: PAYMENT_AMOUNT_PAISE,
          currency: "INR",
        });
      }

      const ride = readRide(payload.ride);
      if (!ride) return respond(400, { message: "Check the ride details and try again." });
      const phone = readPhone(payload.phone);
      if (!phone) return respond(400, { message: "Enter a valid 10-digit Indian mobile number." });

      const merchantOrderReference = `cr_${crypto.randomUUID().replaceAll("-", "")}`;
      const order = await createPineLabsOrder(
        config,
        merchantOrderReference,
        userData.user.id,
        phone,
      );

      const { data: rideId, error } = await admin.rpc("create_pending_paid_ride", {
        p_driver_id: userData.user.id,
        p_origin: ride.origin,
        p_destination: ride.destination,
        p_pickup_point: ride.pickup_point,
        p_travel_date: ride.travel_date,
        p_departure_time: ride.departure_time,
        p_car_model: ride.car_model,
        p_car_registration: ride.car_registration,
        p_car_capacity: ride.car_capacity,
        p_available_seats: ride.available_seats,
        p_bags: ride.bags,
        p_price_per_seat: ride.price_per_seat,
        p_provider_order_id: order.orderId,
      });
      if (error || typeof rideId !== "string") {
        console.error("Could not create paid ride draft:", error?.message);
        throw new Error("Could not prepare the ride payment. Please try again.");
      }
      return respond(200, {
        provider_order_id: order.orderId,
        redirect_url: order.redirectUrl,
        ride_id: rideId,
        amount: PAYMENT_AMOUNT_PAISE,
        currency: "INR",
      });
    }

    if (payload.action === "verify_payment") {
      const { ride_id: rideId, provider_order_id: orderId } = payload;
      if (typeof rideId !== "string" || typeof orderId !== "string") {
        return respond(400, { message: "Payment confirmation is incomplete." });
      }

      const { data: payment, error: paymentError } = await admin
        .from("ride_payments")
        .select("ride_id, payer_id, provider, provider_order_id, status, provider_payment_id")
        .eq("ride_id", rideId)
        .eq("payer_id", userData.user.id)
        .maybeSingle();
      if (paymentError) throw new Error("Could not verify the ride payment.");
      if (!payment || payment.provider !== PROVIDER ||
        payment.provider_order_id !== orderId) {
        return respond(403, { message: "This payment does not match your ride." });
      }

      const status = await getPineLabsStatus(config, orderId);
      if (status.merchantId !== config.merchantId) {
        return respond(403, { message: "This payment does not belong to this merchant." });
      }
      if (status.amount !== PAYMENT_AMOUNT_PAISE) {
        return respond(400, { message: "Payment details do not match this ride fee." });
      }
      if (status.state !== "PROCESSED" || !status.transactionId) {
        return respond(402, { message: "Payment has not been completed. The ride is not published." });
      }

      const ride = await publishPaidRide(
        admin,
        rideId,
        userData.user.id,
        orderId,
        status.transactionId,
      );
      return respond(200, { message: "Payment verified and ride published.", ride });
    }

    return respond(400, { message: "Unsupported payment action." });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Payment could not be completed. Please try again.";
    return respond(502, { message });
  }
});
