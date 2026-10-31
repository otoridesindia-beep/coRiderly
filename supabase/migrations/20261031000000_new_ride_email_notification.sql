-- Emails the CoRiderly inbox whenever a ride becomes open (new post).
-- After deploying the new-ride-notification function, configure:
--   insert into public.app_settings (key, value) values
--     ('notify_function_url', 'https://<project-ref>.supabase.co/functions/v1/new-ride-notification'),
--     ('notify_webhook_secret', '<same value as the NOTIFY_WEBHOOK_SECRET function secret>')
--   on conflict (key) do update set value = excluded.value;
create extension if not exists pg_net with schema extensions;

create or replace function public.notify_new_ride()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  function_url text;
  webhook_secret text;
  driver record;
begin
  if new.status <> 'open' or (tg_op = 'UPDATE' and old.status = 'open') then
    return new;
  end if;

  select value into function_url from public.app_settings where key = 'notify_function_url';
  select value into webhook_secret from public.app_settings where key = 'notify_webhook_secret';
  if function_url is null or webhook_secret is null then
    return new;
  end if;

  select full_name, phone into driver from public.profiles where id = new.driver_id;

  -- A notification failure must never block posting a ride.
  begin
    perform net.http_post(
      url := function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', webhook_secret
      ),
      body := jsonb_build_object(
        'origin', new.origin,
        'destination', new.destination,
        'pickup_point', new.pickup_point,
        'travel_date', new.travel_date,
        'departure_time', new.departure_time,
        'car_model', new.car_model,
        'car_registration', new.car_registration,
        'available_seats', new.available_seats,
        'price_per_seat', new.price_per_seat,
        'driver_name', driver.full_name,
        'driver_phone', driver.phone
      )
    );
  exception when others then
    raise warning 'New ride notification failed: %', sqlerrm;
  end;

  return new;
end;
$$;

revoke all on function public.notify_new_ride() from public, anon, authenticated;

drop trigger if exists notify_new_ride_trigger on public.rides;
create trigger notify_new_ride_trigger
after insert or update of status on public.rides
for each row execute function public.notify_new_ride();
