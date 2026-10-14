# CoRiderly

Flutter ride-sharing app with Supabase authentication.

## Phone and 4-digit MPIN setup

The app uses the `phone-pin-auth` Supabase Edge Function because Supabase Auth
does not accept a 4-digit password directly. The function derives a server-only
password from the phone and MPIN, creates confirmed phone accounts without SMS,
and applies phone/IP attempt limits. Never put the service-role key or
`PHONE_PIN_SECRET` in the Flutter app.

1. Apply `supabase/migrations/20261009000000_phone_pin_rate_limits.sql` in the
   Supabase SQL Editor.
2. Ensure the Phone provider is enabled in Supabase Auth. The Edge Function
   confirms the phone during account creation, so Supabase will not send an SMS.
3. Install the Supabase CLI and link this project to the Supabase project.
4. Set the function secrets:

   ```powershell
   supabase secrets set --project-ref ecefjyoaqyxdjyjsmpyd `
     SUPABASE_SERVICE_ROLE_KEY=<service-role-key> `
     PHONE_PIN_SECRET=<random-secret-at-least-32-bytes>
   ```

   Keep the service-role key and random PIN secret private. Do not commit either.
5. Deploy the function:

   ```powershell
   supabase functions deploy phone-pin-auth --project-ref ecefjyoaqyxdjyjsmpyd
   ```

6. Create and keep a private Android upload key. Do this once, back up the
   keystore securely, and never commit either file:

   ```powershell
   keytool -genkey -v -keystore android\app\upload-keystore.jks `
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

   Create `android\key.properties` with the values for that key. The path in
   `storeFile` is relative to `android\app`:

   ```properties
   storePassword=<keystore-password>
   keyPassword=<key-password>
   keyAlias=upload
   storeFile=upload-keystore.jks
   ```

   `android\.gitignore` excludes `key.properties` and Java keystores. Keep an
   encrypted backup of the keystore and passwords; you need the upload key for
   future updates.

7. Build a signed Android App Bundle with the project URL and anon key:

   ```powershell
   flutter build appbundle --release `
     --dart-define=SUPABASE_URL=https://ecefjyoaqyxdjyjsmpyd.supabase.co `
     --dart-define=SUPABASE_ANON_KEY=<anon-key>
   ```

   Use `assets\play-store\app-icon-512.png` as the Play Console app icon.
   Upload `build\app\outputs\bundle\release\app-release.aab` to a Play Console
   internal or closed testing track before requesting production release.

The four-digit PIN has only 10,000 possible values. The function limits attempts
to five per phone per 15 minutes and 30 per source IP per 15 minutes; use a
longer credential for accounts requiring stronger protection.

## Pay to publish a ride

Each ride requires a separate ₹39 Razorpay payment. The ride is first kept in
`pending_payment` and becomes visible only after the Edge Function verifies the
Razorpay signature and confirms the payment is captured. The app cannot insert
or promote rides directly.

After applying `supabase/migrations/20261009000400_require_payment_before_ride_publish.sql`,
configure the Razorpay **test** credentials as Supabase Edge Function secrets:

```powershell
supabase secrets set --project-ref ecefjyoaqyxdjyjsmpyd `
  RAZORPAY_KEY_ID=<razorpay-test-key-id> `
  RAZORPAY_KEY_SECRET=<razorpay-test-key-secret>
supabase functions deploy ride-payment --project-ref ecefjyoaqyxdjyjsmpyd
```

Never put the Razorpay secret in the app or commit it. First complete a test
payment and verify the corresponding `ride_payments` row is `paid` and its ride
is `open`. Switch to live Razorpay credentials only after your merchant account
is approved and end-to-end testing succeeds.

## Ride search and driver documents

After login, the ride-search panel includes route, travel date, and passenger
filters. The publish-ride form asks for vehicle and trip details plus local
selections for a profile photo, Aadhaar, vehicle registration, and insurance.
Selected files are not uploaded or persisted; this is demo-only and must not be
used as real identity verification. Ride and profile changes are also kept in
memory only.

## Backend data schema

The starter schema already defines `profiles`, `rides`, and `bookings`.
`profiles` is created from Supabase Auth users; `rides` stores route, vehicle,
seat, and price details; `bookings` stores rider reservations.

For existing projects, apply these migrations in order after the core
`supabase-schema.sql` and the MPIN rate-limit migration:

1. `supabase/migrations/20261009000100_documents_and_payments.sql` adds
   private document metadata in
`driver_documents`, a private Storage bucket for files, an optional
`profiles.avatar_path`, and `ride_payments` for the server-verified Razorpay
platform fee.
2. `supabase/migrations/20261009000200_authenticated_ride_publishing.sql`
   adds authenticated ride creation; the payment-required migration below
   supersedes its direct-insert policy.
3. `supabase/migrations/20261009000300_fix_auth_profile_trigger.sql` repairs
   profile creation when a Supabase Auth user registers.
4. `supabase/migrations/20261009000400_require_payment_before_ride_publish.sql`
   blocks direct ride inserts and adds server-only payment/publish operations.
5. `supabase/migrations/20261014000000_driver_reviews.sql` adds shared rider
   reviews, booking-backed review permissions, and access to booked rides.

Apply the new driver-review migration after the four existing migrations in
the Supabase SQL Editor (or through the project's linked Supabase CLI) before
using seat bookings or rider feedback in the app.

The new tables use row-level security. Document review status and payment
records must be written by trusted backend code, not directly by the app.
Never store an MPIN or raw Aadhaar number in these tables.

The HTML ride screen loads open rides for authenticated users. Ride publication
uses the `ride-payment` Edge Function and requires the verified per-ride
payment described above. Seat bookings and driver reviews use Supabase. Riders
can review a driver after the trip date only if they have a confirmed or
completed booking; reviews are visible to authenticated users on each ride
card. Selected documents remain local and are not uploaded or verified.

## Local HTML experience

The source HTML experience is packaged in `assets/web/` and can be opened from
the ride screen's profile menu with **Open HTML version**. Its CSS and
JavaScript are separate local assets, and JavaScript is enabled in the WebView.
The prototype includes its own sign-in screen, which uses the
`phone-pin-auth` Edge Function for 4-digit MPIN registration and login. The
Android app therefore requests Internet access.
