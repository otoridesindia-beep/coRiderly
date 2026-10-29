create table if not exists public.site_visitors (
  visitor_id uuid primary key,
  first_seen_at timestamptz not null default now()
);

alter table public.site_visitors enable row level security;

create or replace function public.record_visit(p_visitor_id uuid)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_visitor_id is not null then
    insert into public.site_visitors (visitor_id)
    values (p_visitor_id)
    on conflict (visitor_id) do nothing;
  end if;
  return (select count(*) from public.site_visitors);
end;
$$;

revoke all on function public.record_visit(uuid) from public;
grant execute on function public.record_visit(uuid) to anon, authenticated;
