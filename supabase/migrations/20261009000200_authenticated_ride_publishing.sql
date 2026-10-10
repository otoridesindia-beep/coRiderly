revoke all on public.rides from anon;
grant select, insert, update, delete on public.rides to authenticated;

drop policy if exists "Drivers create their own rides" on public.rides;
drop policy if exists "Authenticated users create their own rides" on public.rides;
create policy "Authenticated users create their own rides"
on public.rides for insert to authenticated
with check (
  driver_id = (select auth.uid())
  and status = 'open'
);
