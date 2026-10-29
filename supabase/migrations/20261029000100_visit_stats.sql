create or replace function public.record_visit_stats(p_visitor_id uuid)
returns json
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
  return json_build_object(
    'visitors', (select count(*) from public.site_visitors),
    'users', (select count(*) from auth.users)
  );
end;
$$;

revoke all on function public.record_visit_stats(uuid) from public;
grant execute on function public.record_visit_stats(uuid) to anon, authenticated;
