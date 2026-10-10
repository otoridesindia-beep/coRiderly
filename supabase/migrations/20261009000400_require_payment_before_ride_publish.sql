alter table public.rides
  drop constraint if exists rides_status_check;

alter table public.rides
  add constraint rides_status_check
  check (status in ('pending_payment', 'open', 'completed', 'cancelled'));

revoke insert, update on public.rides from anon, authenticated;
grant select, delete on public.rides to authenticated;

drop policy if exists "Drivers create their own rides" on public.rides;
drop policy if exists "Authenticated users create their own rides" on public.rides;
drop policy if exists "Drivers update their own rides" on public.rides;

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
    new_ride_id, p_driver_id, 3900, 'INR', 'razorpay',
    p_provider_order_id, 'created'
  );

  return new_ride_id;
end;
$$;

create or replace function public.publish_paid_ride(
  p_ride_id uuid,
  p_driver_id uuid,
  p_provider_order_id text,
  p_provider_payment_id text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  payment_row public.ride_payments%rowtype;
begin
  select *
  into payment_row
  from public.ride_payments
  where ride_id = p_ride_id
    and payer_id = p_driver_id
    and provider_order_id = p_provider_order_id
  for update;

  if not found then
    raise exception 'Matching ride payment was not found';
  end if;

  if payment_row.status = 'paid' then
    if payment_row.provider_payment_id <> p_provider_payment_id then
      raise exception 'Ride was already paid with a different payment';
    end if;
    return p_ride_id;
  end if;

  if payment_row.status <> 'created' then
    raise exception 'Ride payment is not payable';
  end if;

  update public.ride_payments
  set status = 'paid',
      provider_payment_id = p_provider_payment_id,
      paid_at = now()
  where id = payment_row.id;

  update public.rides
  set status = 'open'
  where id = p_ride_id
    and driver_id = p_driver_id
    and status = 'pending_payment';

  if not found then
    raise exception 'Unpaid ride draft was not found';
  end if;

  return p_ride_id;
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

revoke all on function public.publish_paid_ride(
  uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.publish_paid_ride(
  uuid, uuid, text, text
) to service_role;
