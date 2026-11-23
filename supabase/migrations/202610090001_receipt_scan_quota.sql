-- Only a daily counter is stored; no receipt content is stored by this function.
create table if not exists public.receipt_scan_usage (
  user_id uuid primary key references auth.users(id) on delete cascade,
  scan_day date not null,
  scans integer not null check (scans >= 0)
);
alter table public.receipt_scan_usage enable row level security;
revoke all on public.receipt_scan_usage from anon, authenticated;

create or replace function public.consume_receipt_scan()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  today date := (now() at time zone 'UTC')::date;
  granted integer;
begin
  if caller is null then return false; end if;
  insert into public.receipt_scan_usage as usage (user_id, scan_day, scans)
  values (caller, today, 1)
  on conflict (user_id) do update
    set scan_day = today,
        scans = case when usage.scan_day = today then usage.scans + 1 else 1 end
    where usage.scan_day <> today or usage.scans < 30
  returning scans into granted;
  return granted is not null;
end;
$$;
revoke all on function public.consume_receipt_scan() from public, anon;
grant execute on function public.consume_receipt_scan() to authenticated;
