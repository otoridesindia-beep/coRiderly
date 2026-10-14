create table if not exists public.driver_reviews (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides (id) on delete cascade,
  driver_id uuid not null references public.profiles (id) on delete cascade,
  rider_id uuid not null references public.profiles (id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  feedback text not null check (char_length(trim(feedback)) between 1 and 500),
  created_at timestamptz not null default now(),
  constraint one_review_per_rider_per_ride unique (ride_id, rider_id),
  constraint rider_cannot_review_self check (rider_id <> driver_id)
);

create index if not exists driver_reviews_driver_created_idx
  on public.driver_reviews (driver_id, created_at desc);

create or replace function public.is_booked_rider(p_ride_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.bookings
    where bookings.ride_id = p_ride_id
      and bookings.rider_id = (select auth.uid())
      and bookings.status in ('confirmed', 'completed')
  );
$$;

create or replace function public.can_review_ride(
  p_ride_id uuid,
  p_driver_id uuid,
  p_rider_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_rider_id = (select auth.uid())
    and exists (
      select 1
      from public.rides
      join public.bookings on bookings.ride_id = rides.id
      where rides.id = p_ride_id
        and rides.driver_id = p_driver_id
        and bookings.rider_id = p_rider_id
        and bookings.status in ('confirmed', 'completed')
        and rides.status in ('open', 'completed')
        and (rides.travel_date < current_date or bookings.status = 'completed')
    );
$$;

revoke all on function public.is_booked_rider(uuid) from public;
revoke all on function public.can_review_ride(uuid, uuid, uuid) from public;
grant execute on function public.is_booked_rider(uuid) to authenticated;
grant execute on function public.can_review_ride(uuid, uuid, uuid) to authenticated;

drop policy if exists "Authenticated users can view open rides" on public.rides;
drop policy if exists "Authenticated users can view open and booked rides" on public.rides;
create policy "Authenticated users can view open and booked rides"
on public.rides for select to authenticated
using (
  status = 'open'
  or driver_id = (select auth.uid())
  or public.is_booked_rider(id)
);

alter table public.driver_reviews enable row level security;
grant select, insert, update on public.driver_reviews to authenticated;
revoke all on public.driver_reviews from anon;

drop policy if exists "Authenticated users can read driver reviews" on public.driver_reviews;
create policy "Authenticated users can read driver reviews"
on public.driver_reviews for select to authenticated
using (true);

drop policy if exists "Booked riders can write their own driver reviews" on public.driver_reviews;
create policy "Booked riders can write their own driver reviews"
on public.driver_reviews for insert to authenticated
with check (public.can_review_ride(ride_id, driver_id, rider_id));

drop policy if exists "Booked riders can update their own driver reviews" on public.driver_reviews;
create policy "Booked riders can update their own driver reviews"
on public.driver_reviews for update to authenticated
using (
  rider_id = (select auth.uid())
  and public.can_review_ride(ride_id, driver_id, rider_id)
)
with check (public.can_review_ride(ride_id, driver_id, rider_id));
