-- ShareMyRide starter schema
-- Run this in the Supabase SQL Editor for your project.
-- Users must sign in through Supabase Auth before creating profiles, rides, or bookings.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null check (char_length(trim(full_name)) between 1 and 120),
  phone text,
  role text not null default 'rider' check (role in ('rider', 'driver')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Create a profile automatically whenever a user signs up through Supabase Auth.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'New user'
    ),
    nullif(trim(new.raw_user_meta_data ->> 'phone'), ''),
    case when new.raw_user_meta_data ->> 'role' = 'driver' then 'driver' else 'rider' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create table if not exists public.rides (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles (id) on delete cascade,
  origin text not null check (char_length(trim(origin)) > 0),
  destination text not null check (char_length(trim(destination)) > 0),
  pickup_point text,
  travel_date date not null,
  departure_time time not null,
  car_model text not null,
  car_registration text not null,
  car_capacity integer not null check (car_capacity in (5, 7)),
  available_seats integer not null check (available_seats between 0 and car_capacity - 1),
  bags integer not null default 0 check (bags between 0 and 10),
  price_per_seat numeric(10, 2) not null check (price_per_seat > 0),
  status text not null default 'open'
    check (status in ('pending_payment', 'open', 'completed', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides (id) on delete cascade,
  rider_id uuid not null references public.profiles (id) on delete cascade,
  seats integer not null default 1 check (seats between 1 and 6),
  status text not null default 'confirmed' check (status in ('confirmed', 'cancelled', 'completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint one_booking_per_rider_per_ride unique (ride_id, rider_id)
);

create index if not exists rides_search_idx
  on public.rides (travel_date, origin, destination)
  where status = 'open';
create index if not exists rides_driver_idx on public.rides (driver_id, created_at desc);
create index if not exists bookings_rider_idx on public.bookings (rider_id, created_at desc);
create index if not exists bookings_ride_idx on public.bookings (ride_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists rides_set_updated_at on public.rides;
create trigger rides_set_updated_at
before update on public.rides
for each row execute function public.set_updated_at();

drop trigger if exists bookings_set_updated_at on public.bookings;
create trigger bookings_set_updated_at
before update on public.bookings
for each row execute function public.set_updated_at();

-- Reserve seats atomically and restore them when a booking is cancelled.
create or replace function public.manage_booking_seats()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  seats_left integer;
begin
  if tg_op = 'INSERT' then
    select rides.available_seats into seats_left
    from public.rides
    where rides.id = new.ride_id and rides.status = 'open'
    for update;

    if not found then
      raise exception 'This ride is no longer available.';
    end if;
    if new.seats > seats_left then
      raise exception 'Not enough seats remain on this ride.';
    end if;

    update public.rides
    set available_seats = available_seats - new.seats
    where id = new.ride_id;
    return new;
  end if;

  if new.ride_id <> old.ride_id or new.rider_id <> old.rider_id or new.seats <> old.seats then
    raise exception 'A booking ride, rider, and seat count cannot be changed.';
  end if;
  if old.status = 'confirmed' and new.status = 'cancelled' then
    update public.rides
    set available_seats = least(car_capacity - 1, available_seats + old.seats)
    where id = old.ride_id;
    return new;
  end if;
  if new.status <> old.status then
    raise exception 'The requested booking status change is not allowed.';
  end if;
  return new;
end;
$$;

drop trigger if exists bookings_manage_seats on public.bookings;
create trigger bookings_manage_seats
before insert or update on public.bookings
for each row execute function public.manage_booking_seats();

alter table public.profiles enable row level security;
alter table public.rides enable row level security;
alter table public.bookings enable row level security;

-- Profiles are readable to signed-in users so ride listings can show driver names.
drop policy if exists "Profiles are visible to authenticated users" on public.profiles;
create policy "Profiles are visible to authenticated users"
on public.profiles for select to authenticated
using (true);

drop policy if exists "Users create their own profile" on public.profiles;
create policy "Users create their own profile"
on public.profiles for insert to authenticated
with check (id = (select auth.uid()));

drop policy if exists "Users update their own profile" on public.profiles;
create policy "Users update their own profile"
on public.profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

-- Signed-in users can browse open rides. Ride publication is service-only and payment-gated.
drop policy if exists "Authenticated users can view open rides" on public.rides;
create policy "Authenticated users can view open rides"
on public.rides for select to authenticated
using (status = 'open' or driver_id = (select auth.uid()));

drop policy if exists "Drivers create their own rides" on public.rides;
drop policy if exists "Authenticated users create their own rides" on public.rides;
drop policy if exists "Drivers update their own rides" on public.rides;

revoke insert, update on public.rides from anon, authenticated;
grant select, delete on public.rides to authenticated;

drop policy if exists "Drivers delete their own rides" on public.rides;
create policy "Drivers delete their own rides"
on public.rides for delete to authenticated
using (driver_id = (select auth.uid()));

-- Riders can view and cancel their own bookings; drivers can view bookings for their rides.
drop policy if exists "Riders and ride drivers can view bookings" on public.bookings;
create policy "Riders and ride drivers can view bookings"
on public.bookings for select to authenticated
using (
  rider_id = (select auth.uid())
  or exists (
    select 1 from public.rides
    where rides.id = bookings.ride_id and rides.driver_id = (select auth.uid())
  )
);

drop policy if exists "Riders create their own bookings" on public.bookings;
create policy "Riders create their own bookings"
on public.bookings for insert to authenticated
with check (
  rider_id = (select auth.uid())
  and exists (
    select 1 from public.rides
    where rides.id = bookings.ride_id
      and rides.status = 'open'
      and rides.driver_id <> (select auth.uid())
  )
);

drop policy if exists "Riders cancel their own bookings" on public.bookings;
create policy "Riders cancel their own bookings"
on public.bookings for update to authenticated
using (rider_id = (select auth.uid()))
with check (rider_id = (select auth.uid()));

-- Optional profile image and private driver document metadata.
alter table public.profiles
  add column if not exists avatar_path text;

create table if not exists public.driver_documents (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  document_type text not null check (
    document_type in (
      'profile_photo',
      'aadhaar_front',
      'aadhaar_back',
      'rc_front',
      'rc_back',
      'insurance'
    )
  ),
  storage_path text not null unique,
  review_status text not null default 'pending' check (
    review_status in ('pending', 'approved', 'rejected')
  ),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint driver_documents_path_belongs_to_owner
    check (storage_path like owner_id::text || '/%')
);

create index if not exists driver_documents_owner_idx
  on public.driver_documents (owner_id, created_at desc);

alter table public.driver_documents enable row level security;
revoke all on public.driver_documents from anon, authenticated;
grant select, insert, delete on public.driver_documents to authenticated;

drop policy if exists "Owners view their own driver documents"
  on public.driver_documents;
create policy "Owners view their own driver documents"
on public.driver_documents for select to authenticated
using (owner_id = (select auth.uid()));

drop policy if exists "Owners register pending driver documents"
  on public.driver_documents;
create policy "Owners register pending driver documents"
on public.driver_documents for insert to authenticated
with check (
  owner_id = (select auth.uid())
  and review_status = 'pending'
  and reviewed_at is null
  and reviewed_by is null
);

drop policy if exists "Owners delete their own driver documents"
  on public.driver_documents;
create policy "Owners delete their own driver documents"
on public.driver_documents for delete to authenticated
using (
  owner_id = (select auth.uid())
  and review_status <> 'approved'
);

-- Identity files stay in a private Storage bucket; only the owning user can access them.
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'sharemyride-private-documents',
  'sharemyride-private-documents',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'application/pdf']
)
on conflict (id) do nothing;

drop policy if exists "Owners view their private driver files"
  on storage.objects;
create policy "Owners view their private driver files"
on storage.objects for select to authenticated
using (
  bucket_id = 'sharemyride-private-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Owners upload their private driver files"
  on storage.objects;
create policy "Owners upload their private driver files"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'sharemyride-private-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Owners delete their unapproved driver files"
  on storage.objects;
create policy "Owners delete their unapproved driver files"
on storage.objects for delete to authenticated
using (
  bucket_id = 'sharemyride-private-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and not exists (
    select 1
    from public.driver_documents
    where driver_documents.storage_path = name
      and driver_documents.review_status = 'approved'
  )
);

-- One server-verified ₹39 publishing payment per ride.
create table if not exists public.ride_payments (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides (id) on delete restrict,
  payer_id uuid not null references public.profiles (id) on delete restrict,
  purpose text not null default 'platform_fee'
    check (purpose = 'platform_fee'),
  amount_paise bigint not null check (amount_paise > 0),
  currency text not null default 'INR' check (currency = 'INR'),
  provider text not null default 'razorpay'
    check (provider = 'razorpay'),
  provider_order_id text unique,
  provider_payment_id text unique,
  status text not null default 'pending'
    check (status in ('pending', 'created', 'paid', 'failed', 'refunded')),
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint one_platform_fee_per_ride unique (ride_id, purpose)
);

create index if not exists ride_payments_payer_idx
  on public.ride_payments (payer_id, created_at desc);

alter table public.ride_payments enable row level security;
revoke all on public.ride_payments from anon, authenticated;
grant select on public.ride_payments to authenticated;

drop policy if exists "Payers view their own ride payments"
  on public.ride_payments;
create policy "Payers view their own ride payments"
on public.ride_payments for select to authenticated
using (payer_id = (select auth.uid()));

drop trigger if exists ride_payments_set_updated_at
  on public.ride_payments;
create trigger ride_payments_set_updated_at
before update on public.ride_payments
for each row execute function public.set_updated_at();

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
