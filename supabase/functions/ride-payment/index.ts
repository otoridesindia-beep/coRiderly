import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
};

const PAYMENT_AMOUNT_PAISE = 3900;

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

function toHex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return toHex(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)),
  );
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

async function razorpayRequest(
  url: string,
  method: "GET" | "POST",
  keyId: string,
  keySecret: string,
  body?: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`,
      "Content-Type": "application/json",
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const result: unknown = await response.json();
  if (!response.ok || !isRecord(result)) {
    const providerError =
      isRecord(result) && isRecord(result.error) ? result.error : null;
    const errorCode = providerError && typeof providerError.code === "string"
      ? providerError.code
      : "unknown";
    const description = providerError &&
        typeof providerError.description === "string"
      ? providerError.description
      : "No provider description";
    console.error("Razorpay API request failed:", {
      status: response.status,
      code: errorCode,
      description,
    });
    throw new Error(
      `Payment provider request failed (HTTP ${response.status}, ${errorCode}).`,
    );
  }
  return result;
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
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!supabaseUrl || !serviceRoleKey || !keyId || !keySecret) {
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
          .select("ride_id, provider_order_id, provider_payment_id, status")
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
        return respond(200, {
          key_id: keyId,
          order_id: existing.provider_order_id,
          ride_id: existing.ride_id,
          amount: PAYMENT_AMOUNT_PAISE,
          currency: "INR",
        });
      }

      const ride = readRide(payload.ride);
      if (!ride) return respond(400, { message: "Check the ride details and try again." });

      const order = await razorpayRequest(
        "https://api.razorpay.com/v1/orders",
        "POST",
        keyId,
        keySecret,
        {
          amount: PAYMENT_AMOUNT_PAISE,
          currency: "INR",
          receipt: `smr_${crypto.randomUUID().replaceAll("-", "").slice(0, 20)}`,
          notes: { driver_id: userData.user.id },
        },
      );
      if (typeof order.id !== "string") {
        throw new Error("Payment provider did not return a usable order.");
      }

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
        p_provider_order_id: order.id,
      });
      if (error || typeof rideId !== "string") {
        console.error("Could not create paid ride draft:", error?.message);
        throw new Error("Could not prepare the ride payment. Please try again.");
      }
      return respond(200, {
        key_id: keyId,
        order_id: order.id,
        ride_id: rideId,
        amount: PAYMENT_AMOUNT_PAISE,
        currency: "INR",
      });
    }

    if (payload.action === "verify_payment") {
      const {
        ride_id: rideId,
        razorpay_order_id: orderId,
        razorpay_payment_id: paymentId,
        razorpay_signature: signature,
      } = payload;
      if (
        typeof rideId !== "string" ||
        typeof orderId !== "string" ||
        typeof paymentId !== "string" ||
        typeof signature !== "string"
      ) {
        return respond(400, { message: "Payment confirmation is incomplete." });
      }

      const { data: payment, error: paymentError } = await admin
        .from("ride_payments")
        .select("ride_id, payer_id, provider_order_id, status, provider_payment_id")
        .eq("ride_id", rideId)
        .eq("payer_id", userData.user.id)
        .maybeSingle();
      if (paymentError) throw new Error("Could not verify the ride payment.");
      if (!payment || payment.provider_order_id !== orderId) {
        return respond(403, { message: "This payment does not match your ride." });
      }

      const expectedSignature = await hmacHex(
        keySecret,
        `${orderId}|${paymentId}`,
      );
      if (!constantTimeEqual(expectedSignature, signature)) {
        return respond(400, { message: "Payment verification failed. The ride was not published." });
      }

      let providerPayment = await razorpayRequest(
        `https://api.razorpay.com/v1/payments/${encodeURIComponent(paymentId)}`,
        "GET",
        keyId,
        keySecret,
      );
      if (
        providerPayment.order_id !== orderId ||
        providerPayment.amount !== PAYMENT_AMOUNT_PAISE ||
        providerPayment.currency !== "INR"
      ) {
        return respond(400, { message: "Payment details do not match this ride fee." });
      }
      if (providerPayment.status === "authorized") {
        providerPayment = await razorpayRequest(
          `https://api.razorpay.com/v1/payments/${encodeURIComponent(paymentId)}/capture`,
          "POST",
          keyId,
          keySecret,
          { amount: PAYMENT_AMOUNT_PAISE, currency: "INR" },
        );
      }
      if (providerPayment.status !== "captured") {
        return respond(402, { message: "Payment has not been captured. The ride is not published." });
      }

      const { data: publishedRideId, error: publishError } = await admin.rpc(
        "publish_paid_ride",
        {
          p_ride_id: rideId,
          p_driver_id: userData.user.id,
          p_provider_order_id: orderId,
          p_provider_payment_id: paymentId,
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
