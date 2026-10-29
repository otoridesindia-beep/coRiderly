-- Temporary free ride posting while ride payments are paused.
-- Each user may have only one active ride (open, posted within the last 24 hours).
-- To resume payments: update public.app_settings set value = 'true' where key = 'payments_enabled'.
create table if not exists public.app_settings (
  key text primary key,
  value text not null
);
alter table public.app_settings enable row level security;

insert into public.app_settings (key, value)
values ('payments_enabled', 'false')
on conflict (key) do nothing;

create or replace function public.publish_free_ride(
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
  p_price_per_seat numeric
)
returns public.rides
language plpgsql
security definer
set search_path = public
as $$
declare
  new_ride public.rides;
begin
  if auth.uid() is null then
    raise exception 'Please log in again.';
  end if;

  if exists (select 1 from public.app_settings where key = 'payments_enabled' and value = 'true') then
    raise exception 'Free posting is no longer available.';
  end if;

  if exists (
    select 1 from public.rides
    where driver_id = auth.uid()
      and status = 'open'
      and created_at > now() - interval '24 hours'
  ) then
    raise exception 'You can post only one ride at a time. Delete your current ride or wait until it expires.';
  end if;

  insert into public.rides (
    driver_id, origin, destination, pickup_point, travel_date,
    departure_time, car_model, car_registration, car_capacity,
    available_seats, bags, price_per_seat, status
  )
  values (
    auth.uid(), trim(p_origin), trim(p_destination),
    nullif(trim(coalesce(p_pickup_point, '')), ''), p_travel_date,
    p_departure_time, p_car_model, p_car_registration, p_car_capacity,
    p_available_seats, p_bags, p_price_per_seat, 'open'
  )
  returning * into new_ride;

  return new_ride;
end;
$$;

revoke all on function public.publish_free_ride(
  text, text, text, date, time, text, text, integer, integer, integer, numeric
) from public, anon;
grant execute on function public.publish_free_ride(
  text, text, text, date, time, text, text, integer, integer, integer, numeric
) to authenticated;
