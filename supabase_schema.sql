-- Spendly Supabase schema
-- Run this once in Supabase Dashboard > SQL Editor before using cloud sync.

create table if not exists public.app_users (
  id text primary key,
  name text not null,
  email text not null unique,
  created_at timestamptz not null,
  last_login_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.accounts (
  id text primary key,
  user_id text not null references public.app_users(id) on delete cascade,
  name text not null,
  kind integer not null,
  subtype integer not null,
  opening_balance numeric not null,
  current_balance numeric not null,
  icon text not null,
  color_value bigint not null,
  is_default boolean not null default false,
  include_in_net_worth boolean not null default true,
  include_in_balance boolean not null default true,
  counterparty_name text,
  linked_account_id text,
  updated_at timestamptz not null default now()
);

create table if not exists public.categories (
  id text primary key,
  user_id text not null references public.app_users(id) on delete cascade,
  name text not null,
  type integer not null,
  parent_category integer not null,
  icon text not null,
  color_value bigint not null,
  parent_id text,
  is_default boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.budgets (
  id text primary key,
  user_id text not null references public.app_users(id) on delete cascade,
  category integer not null,
  limit_amount numeric not null,
  month timestamptz not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.transactions (
  id text primary key,
  user_id text not null references public.app_users(id) on delete cascade,
  title text not null,
  amount numeric not null,
  type integer not null,
  category integer not null,
  category_id text,
  account_id text,
  date timestamptz not null,
  note text,
  receipt_image_path text,
  is_recurring boolean not null default false,
  recurring_frequency text,
  updated_at timestamptz not null default now()
);

create table if not exists public.receipts (
  id text primary key,
  user_id text not null references public.app_users(id) on delete cascade,
  transaction_id text references public.transactions(id) on delete set null,
  file_path text not null,
  public_url text,
  extracted_text text,
  created_at timestamptz not null default now()
);

alter table public.app_users enable row level security;
alter table public.accounts enable row level security;
alter table public.categories enable row level security;
alter table public.budgets enable row level security;
alter table public.transactions enable row level security;
alter table public.receipts enable row level security;

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



-- Case-insensitive email uniqueness for profiles; Auth also enforces account uniqueness.
create unique index if not exists app_users_normalized_email_key on public.app_users (lower(btrim(email))) where nullif(btrim(email), '') is not null;
