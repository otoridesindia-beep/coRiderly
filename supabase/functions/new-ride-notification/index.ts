import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const NOTIFY_TO = "coriderlyindia@gmail.com";

type RidePayload = {
  origin: string;
  destination: string;
  pickup_point: string | null;
  travel_date: string;
  departure_time: string;
  car_model: string;
  car_registration: string;
  available_seats: number;
  price_per_seat: number;
  driver_name: string | null;
  driver_phone: string | null;
};

function escapeHtml(value: unknown): string {
  return String(value ?? "").replace(/[&<>"']/g, (char) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]!
  );
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { message: "Method not allowed." });

  const webhookSecret = Deno.env.get("NOTIFY_WEBHOOK_SECRET");
  const gmailUser = Deno.env.get("GMAIL_USER");
  const gmailPassword = Deno.env.get("GMAIL_APP_PASSWORD");
  if (!webhookSecret || !gmailUser || !gmailPassword) {
    return json(500, { message: "Email notifications are not configured." });
  }
  if (request.headers.get("x-webhook-secret") !== webhookSecret) {
    return json(401, { message: "Unauthorized." });
  }

  let ride: RidePayload;
  try {
    ride = await request.json();
  } catch {
    return json(400, { message: "Invalid request body." });
  }

  const rows: [string, unknown][] = [
    ["Route", `${ride.origin} → ${ride.destination}`],
    ["Pickup point", ride.pickup_point || "Not specified"],
    ["Date", ride.travel_date],
    ["Departure", String(ride.departure_time).slice(0, 5)],
    ["Vehicle", `${ride.car_model} (${ride.car_registration})`],
    ["Seats available", ride.available_seats],
    ["Price per seat", `₹${ride.price_per_seat}`],
    ["Driver", ride.driver_name || "Unknown"],
    ["Driver phone", ride.driver_phone || "Not provided"],
  ];
  const html = `<h2>New ride posted on CoRiderly</h2><table cellpadding="6">${
    rows.map(([label, value]) =>
      `<tr><td><strong>${escapeHtml(label)}</strong></td><td>${escapeHtml(value)}</td></tr>`
    ).join("")
  }</table>`;
  const text = rows.map(([label, value]) => `${label}: ${value}`).join("\n");

  const client = new SMTPClient({
    connection: {
      hostname: "smtp.gmail.com",
      port: 465,
      tls: true,
      auth: { username: gmailUser, password: gmailPassword },
    },
  });
  try {
    await client.send({
      from: gmailUser,
      to: NOTIFY_TO,
      subject: `New ride: ${ride.origin} → ${ride.destination}`,
      content: text,
      html,
    });
  } catch (error) {
    console.error("Could not send new ride email", error);
    return json(502, { message: "Could not send the email." });
  } finally {
    await client.close();
  }
  return json(200, { sent: true });
});
