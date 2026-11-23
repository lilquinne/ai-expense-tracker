-- Applied with Supabase migration unique_normalized_profile_email.
create unique index if not exists app_users_normalized_email_key on public.app_users (lower(btrim(email))) where nullif(btrim(email), '') is not null;
