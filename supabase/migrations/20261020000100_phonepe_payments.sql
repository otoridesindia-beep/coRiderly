-- Switch the ride publishing fee provider to PhonePe.
-- Older provider values stay allowed only so historical payment rows remain valid.
alter table public.ride_payments
  drop constraint if exists ride_payments_provider_check;

alter table public.ride_payments
  alter column provider set default 'phonepe',
  add constraint ride_payments_provider_check
    check (provider in ('phonepe', 'razorpay', 'cashfree'));

create or replace function public.create_pending_paid_ride(
  p_driver_id uuid,
  p_origin text,
  p_destination text,
  p_pickup_point text,
  p_travel_date date,
  p_departure_time time,
  p_car_model text,
  p_car_registration text,
  p_car_capacity integer,
  p_available_seats integer,
  p_bags integer,
  p_price_per_seat numeric,
  p_provider_order_id text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_ride_id uuid;
begin
  insert into public.rides (
    driver_id, origin, destination, pickup_point, travel_date,
    departure_time, car_model, car_registration, car_capacity,
    available_seats, bags, price_per_seat, status
  )
  values (
    p_driver_id, p_origin, p_destination, p_pickup_point, p_travel_date,
    p_departure_time, p_car_model, p_car_registration, p_car_capacity,
    p_available_seats, p_bags, p_price_per_seat, 'pending_payment'
  )
  returning id into new_ride_id;

  insert into public.ride_payments (
    ride_id, payer_id, amount_paise, currency, provider,
    provider_order_id, status
  )
  values (
    new_ride_id, p_driver_id, 3900, 'INR', 'phonepe',
    p_provider_order_id, 'created'
  );

  return new_ride_id;
end;
$$;

revoke all on function public.create_pending_paid_ride(
  uuid, text, text, text, date, time, text, text, integer, integer,
  integer, numeric, text
) from public, anon, authenticated;
grant execute on function public.create_pending_paid_ride(
  uuid, text, text, text, date, time, text, text, integer, integer,
  integer, numeric, text
) to service_role;
