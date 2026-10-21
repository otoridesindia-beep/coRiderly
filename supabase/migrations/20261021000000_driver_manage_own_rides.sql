create or replace function public.update_own_ride(
  p_ride_id uuid,
  p_origin text,
  p_destination text,
  p_pickup_point text,
  p_travel_date date,
  p_departure_time time,
  p_available_seats integer,
  p_bags integer,
  p_price_per_seat numeric
)
returns public.rides
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_ride public.rides;
begin
  if auth.uid() is null then
    raise exception 'Please log in again.';
  end if;

  update public.rides
  set origin = trim(p_origin),
      destination = trim(p_destination),
      pickup_point = nullif(trim(coalesce(p_pickup_point, '')), ''),
      travel_date = p_travel_date,
      departure_time = p_departure_time,
      available_seats = p_available_seats,
      bags = p_bags,
      price_per_seat = p_price_per_seat
  where id = p_ride_id
    and driver_id = auth.uid()
    and status = 'open'
  returning * into updated_ride;

  if updated_ride.id is null then
    raise exception 'Ride not found or can no longer be edited.';
  end if;

  return updated_ride;
end;
$$;

create or replace function public.delete_own_ride(p_ride_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Please log in again.';
  end if;

  update public.rides
  set status = 'cancelled'
  where id = p_ride_id
    and driver_id = auth.uid()
    and status in ('open', 'pending_payment');

  if not found then
    raise exception 'Ride not found or already removed.';
  end if;

  update public.bookings
  set status = 'cancelled'
  where ride_id = p_ride_id
    and status = 'confirmed';
end;
$$;

revoke all on function public.update_own_ride(uuid, text, text, text, date, time, integer, integer, numeric) from public, anon;
revoke all on function public.delete_own_ride(uuid) from public, anon;
grant execute on function public.update_own_ride(uuid, text, text, text, date, time, integer, integer, numeric) to authenticated;
grant execute on function public.delete_own_ride(uuid) to authenticated;
