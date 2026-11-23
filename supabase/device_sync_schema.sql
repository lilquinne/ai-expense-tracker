create table public.device_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null check (revision > 0),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  updated_at timestamptz not null default now()
);
alter table public.device_snapshots enable row level security;
create policy owner_access on public.device_snapshots for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
revoke all on public.device_snapshots from anon, public;
grant select, insert, update on public.device_snapshots to authenticated;

create table public.device_snapshot_history (
  user_id uuid not null references auth.users(id) on delete cascade,
  revision bigint not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  primary key(user_id, revision)
);
alter table public.device_snapshot_history enable row level security;
create policy owner_access on public.device_snapshot_history for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
revoke all on public.device_snapshot_history from anon, public;
grant select, insert, delete on public.device_snapshot_history to authenticated;

create or replace function public.commit_device_snapshot(expected_revision bigint, new_payload jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare owner uuid := auth.uid(); saved public.device_snapshots; accepted boolean := false;
begin
  if owner is null then raise exception 'Sign in to sync' using errcode = '42501'; end if;
  if expected_revision < 0 or new_payload is null or jsonb_typeof(new_payload) <> 'object'
    or octet_length(new_payload::text) > 20000000
    or not (new_payload ?& array['accounts','categories','budgets','transactions','treasure_jars','jar_activity','split_people','split_payments','account_transfers'])
    then raise exception 'Invalid snapshot'; end if;
  if exists (select 1 from jsonb_each(new_payload) e where jsonb_typeof(e.value) <> 'array'
    or e.key <> all(array['accounts','categories','budgets','transactions','treasure_jars','jar_activity','split_people','split_payments','account_transfers']))
    then raise exception 'Invalid snapshot tables'; end if;
  if expected_revision = 0 then
    insert into public.device_snapshots(user_id,revision,payload) values(owner,1,new_payload)
      on conflict(user_id) do nothing returning * into saved;
    accepted := found;
  end if;
  if not accepted then
    select * into saved from public.device_snapshots where user_id = owner for update;
    if found and saved.revision = expected_revision then
      insert into public.device_snapshot_history(user_id,revision,payload)
        values(owner,saved.revision,saved.payload) on conflict do nothing;
      update public.device_snapshots set payload=new_payload, revision=revision+1, updated_at=now()
        where user_id=owner returning * into saved;
      accepted := true;
      delete from public.device_snapshot_history where user_id=owner and revision < saved.revision-5;
    end if;
  end if;
  return jsonb_build_object('accepted',accepted,'revision',coalesce(saved.revision,0),'payload',saved.payload);
end $$;
revoke all on function public.commit_device_snapshot(bigint,jsonb) from public, anon;
grant execute on function public.commit_device_snapshot(bigint,jsonb) to authenticated;
