create table if not exists public.phone_pin_rate_limits (
  bucket_hash text primary key,
  window_started_at timestamptz not null,
  attempts integer not null check (attempts > 0)
);

create index if not exists phone_pin_rate_limits_window_idx
  on public.phone_pin_rate_limits (window_started_at);

create or replace function public.consume_phone_pin_attempt(
  p_bucket_hash text,
  p_max_attempts integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_window_started_at timestamptz;
  v_attempts integer;
  v_now timestamptz := clock_timestamp();
begin
  if p_bucket_hash is null
    or p_bucket_hash = ''
    or p_max_attempts < 1
    or p_window_seconds < 1 then
    raise exception 'Invalid rate limit parameters.';
  end if;

  insert into public.phone_pin_rate_limits as limits (
    bucket_hash,
    window_started_at,
    attempts
  )
  values (p_bucket_hash, v_now, 1)
  on conflict (bucket_hash) do update
  set
    window_started_at = case
      when limits.window_started_at <= v_now - make_interval(secs => p_window_seconds)
        then v_now
      else limits.window_started_at
    end,
    attempts = case
      when limits.window_started_at <= v_now - make_interval(secs => p_window_seconds)
        then 1
      else limits.attempts + 1
    end
  returning window_started_at, attempts
  into v_window_started_at, v_attempts;

  return v_attempts <= p_max_attempts
    and v_window_started_at > v_now - make_interval(secs => p_window_seconds);
end;
$$;

revoke all on table public.phone_pin_rate_limits from public, anon, authenticated;
revoke all on function public.consume_phone_pin_attempt(text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_phone_pin_attempt(text, integer, integer)
  to service_role;
