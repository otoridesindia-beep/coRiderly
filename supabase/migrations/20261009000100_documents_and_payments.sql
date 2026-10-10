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
on conflict (id) do update
set
  name = excluded.name,
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

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
