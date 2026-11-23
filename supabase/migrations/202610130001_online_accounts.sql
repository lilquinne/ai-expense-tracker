-- Secure existing Spendly tables while retaining legacy expense rows.
alter table public.app_users drop constraint if exists app_users_email_key;
-- Offline PINs are not cloud credentials and must not be stored online.
alter table public.app_users drop column if exists pin;

do $$
declare t text; p record; owner_column text;
begin
  foreach t in array array['app_users','accounts','categories','budgets','transactions','receipts'] loop
    execute format('alter table public.%I enable row level security', t);
    for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    owner_column := case when t='app_users' then 'id' else 'user_id' end;
    execute format('create policy owner_access on public.%I for all to authenticated using ((select auth.uid())::text = %I) with check ((select auth.uid())::text = %I)', t, owner_column, owner_column);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

create or replace function public.create_spendly_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.app_users(id, name, email, created_at, updated_at)
  values (new.id::text,
    coalesce(nullif(new.raw_user_meta_data->>'name',''),
             nullif(new.raw_user_meta_data->>'full_name',''), 'User'),
    coalesce(new.email,''), new.created_at, now())
  on conflict (id) do nothing;
  return new;
end $$;
revoke all on function public.create_spendly_profile() from public, anon, authenticated;
drop trigger if exists on_spendly_user_created on auth.users;
create trigger on_spendly_user_created after insert on auth.users
for each row execute function public.create_spendly_profile();

insert into public.app_users(id,name,email,created_at,updated_at)
select id::text,
  coalesce(nullif(raw_user_meta_data->>'name',''),
           nullif(raw_user_meta_data->>'full_name',''),'User'),
  coalesce(email,''),created_at,now() from auth.users
on conflict (id) do nothing;

create index if not exists accounts_owner_idx on public.accounts(user_id);
create index if not exists categories_owner_idx on public.categories(user_id);
create index if not exists budgets_owner_idx on public.budgets(user_id);
create index if not exists transactions_owner_idx on public.transactions(user_id);
create index if not exists receipts_owner_idx on public.receipts(user_id);
