-- A minimal stand-in for the parts of Supabase the migrations rely on, so they
-- can be tested on a plain local Postgres with PostGIS. Never run this on a
-- real Supabase project.
--
-- auth.uid() reads the setting 'test.uid'; tests switch user with
--   select set_config('test.uid', '<uuid>', false); set role authenticated;

create schema extensions;
grant usage on schema extensions to public;

do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role supabase_auth_admin nologin; exception when duplicate_object then null; end $$;

create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  phone text,
  is_anonymous boolean not null default false
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('test.uid', true), '')::uuid
$$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;

create schema storage;
create table storage.buckets (id text primary key, name text, public boolean);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text not null,
  owner uuid
);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;
grant usage on schema storage to anon, authenticated;
grant select, insert, update on storage.objects to authenticated;
grant execute on function storage.foldername(text) to anon, authenticated;
