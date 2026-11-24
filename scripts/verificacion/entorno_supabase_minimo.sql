-- Entorno mínimo que imita Supabase (roles anon/authenticated, auth.uid(), Vault, cron) SOLO para una base local de prueba.
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin bypassrls; exception when duplicate_object then null; end $$;


create schema extensions;
create extension pgcrypto schema extensions;

create schema auth;
create table auth.users (
  instance_id uuid, id uuid primary key, aud text, role text, email text, encrypted_password text,
  email_confirmed_at timestamptz, raw_app_meta_data jsonb, raw_user_meta_data jsonb,
  created_at timestamptz, updated_at timestamptz, confirmation_token text, recovery_token text,
  email_change_token_new text, email_change text, email_change_token_current text, phone_change text,
  phone_change_token text, reauthentication_token text, banned_until timestamptz);
create table auth.identities (
  provider_id text, user_id uuid, identity_data jsonb, provider text, last_sign_in_at timestamptz,
  created_at timestamptz, updated_at timestamptz, unique (provider_id, provider));
create table auth.sessions (
  id uuid primary key default gen_random_uuid(), user_id uuid, created_at timestamptz default now(),
  updated_at timestamptz default now(), refreshed_at timestamp, not_after timestamptz, user_agent text, ip inet);
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as
  $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;
grant usage on schema extensions to anon, authenticated, service_role;

create schema vault;
create table vault.secrets (id uuid primary key default gen_random_uuid(), name text unique, secret text, description text);
create function vault.create_secret(s text, n text, d text) returns uuid language sql as
  $$ insert into vault.secrets (secret, name, description) values (s, n, d) returning id $$;
create function vault.update_secret(i uuid, s text) returns void language sql as
  $$ update vault.secrets set secret = s where id = i $$;
create view vault.decrypted_secrets as select id, name, secret as decrypted_secret from vault.secrets;

create schema realtime;
create function realtime.send(p jsonb, e text, t text, priv boolean) returns void language sql as $$ select $$;
create publication supabase_realtime;

create schema cron;
create table cron.job (jobname text);
create function cron.schedule(n text, s text, c text) returns bigint language sql as
  $$ insert into cron.job values (n); select 1::bigint $$;
create function cron.unschedule(n text) returns boolean language sql as $$ delete from cron.job where jobname = n; select true $$;

create schema net;
create function net.http_post(url text, headers jsonb, body jsonb, timeout_milliseconds int) returns bigint
  language sql as $$ select 1::bigint $$;

-- Privilegios por omisión de Supabase en el esquema public
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
