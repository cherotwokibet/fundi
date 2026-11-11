-- Fundi — Phase 1 core schema: find and call a verified mechanic.
-- Run with the Supabase CLI (`supabase db push`) or paste into the SQL editor.

create extension if not exists postgis with schema extensions;

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.user_role as enum ('owner', 'mechanic', 'garage_staff', 'admin');
create type public.provider_type as enum ('mobile_mechanic', 'garage');
create type public.provider_status as enum ('pending', 'approved', 'suspended');
create type public.check_kind as enum ('identity', 'location', 'experience', 'business');
create type public.check_status as enum ('pending', 'passed', 'failed');
create type public.availability_status as enum ('available', 'busy', 'offline');
create type public.contact_kind as enum ('profile_view', 'call_tap', 'call_helped', 'call_not_helped');
create type public.request_mode as enum ('come_to_me', 'visit_garage');
create type public.request_status as enum
  ('requested', 'accepted', 'inspecting', 'quoted', 'approved', 'in_progress', 'done', 'cancelled', 'disputed');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- One row per signed-in person. Guests (anonymous sessions) have no profile.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  phone text,
  full_name text,
  role public.user_role not null default 'owner',
  created_at timestamptz not null default now()
);

-- A mobile mechanic or a garage. Only 'approved' rows are ever shown to owners.
create table public.providers (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users (id) on delete set null,
  garage_id uuid references public.providers (id) on delete set null, -- mechanic affiliated to a garage
  type public.provider_type not null,
  display_name text not null,
  business_phone text not null,
  photo_url text,
  area text not null,                                  -- e.g. 'Kasarani'
  location extensions.geography(Point, 4326) not null,
  service_radius_km numeric(5, 1) not null default 5,
  callout_fee_kes integer,                             -- inspection / call-out fee shown upfront
  makes text[] not null default '{}',                  -- car makes handled; empty = all
  rating_avg numeric(2, 1) not null default 0,
  rating_count integer not null default 0,
  status public.provider_status not null default 'pending',
  created_at timestamptz not null default now()
);
create index providers_location_idx on public.providers using gist (location);
create index providers_status_idx on public.providers (status);

-- What "Verified" actually means: one row per thing checked.
create table public.verification_checks (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.providers (id) on delete cascade,
  kind public.check_kind not null,
  status public.check_status not null default 'pending',
  checked_at timestamptz,
  expires_at timestamptz,
  checked_by uuid references auth.users (id),
  unique (provider_id, kind)
);

-- Availability the mechanic sets. It expires, so a stale "Available" is never shown.
create table public.availability (
  provider_id uuid primary key references public.providers (id) on delete cascade,
  status public.availability_status not null default 'offline',
  set_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '4 hours'
);

-- A tap in the app (never the content of a call).
create table public.contact_events (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.providers (id) on delete cascade,
  user_id uuid references auth.users (id) on delete set null,
  kind public.contact_kind not null,
  area text,
  created_at timestamptz not null default now()
);
create index contact_events_provider_idx on public.contact_events (provider_id, created_at desc);

-- "Find Me a Mechanic". Becomes the job, quote and payment in Phase 2.
create table public.service_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  provider_id uuid references public.providers (id) on delete set null,
  mode public.request_mode not null,
  location extensions.geography(Point, 4326),
  area text,
  note text,                 -- optional, in the owner's own words
  car_make text,             -- optional
  contact_phone text,
  status public.request_status not null default 'requested',
  created_at timestamptz not null default now()
);
create index service_requests_user_idx on public.service_requests (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- The one query behind both home-screen buttons:
-- verified, approved providers near a point, with their real availability.
create or replace function public.nearby_providers(
  p_lat double precision,
  p_lng double precision,
  p_radius_km double precision default 10,
  p_type public.provider_type default null
)
returns table (
  id uuid,
  type public.provider_type,
  display_name text,
  business_phone text,
  photo_url text,
  area text,
  lat double precision,
  lng double precision,
  distance_km double precision,
  service_radius_km numeric,
  callout_fee_kes integer,
  makes text[],
  rating_avg numeric,
  rating_count integer,
  availability text,            -- available | busy | offline | unconfirmed
  availability_set_at timestamptz,
  checks_passed public.check_kind[]
)
language sql stable security definer set search_path = public, extensions
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  )
  select
    p.id, p.type, p.display_name, p.business_phone, p.photo_url, p.area,
    st_y(p.location::geometry) as lat,
    st_x(p.location::geometry) as lng,
    round((st_distance(p.location, o.g) / 1000.0)::numeric, 1)::double precision as distance_km,
    p.service_radius_km, p.callout_fee_kes, p.makes, p.rating_avg, p.rating_count,
    case
      when a.provider_id is null then 'offline'
      when a.status = 'available' and a.expires_at < now() then 'unconfirmed'
      else a.status::text
    end as availability,
    a.set_at as availability_set_at,
    coalesce(
      (select array_agg(v.kind order by v.kind)
         from public.verification_checks v
        where v.provider_id = p.id
          and v.status = 'passed'
          and (v.expires_at is null or v.expires_at > now())),
      '{}'
    ) as checks_passed
  from public.providers p
  cross join origin o
  left join public.availability a on a.provider_id = p.id
  where p.status = 'approved'
    and (p_type is null or p.type = p_type)
    and st_dwithin(p.location, o.g, p_radius_km * 1000)
    -- identity must be verified before anyone is shown to owners
    and exists (
      select 1 from public.verification_checks v
       where v.provider_id = p.id and v.kind = 'identity' and v.status = 'passed'
         and (v.expires_at is null or v.expires_at > now())
    )
  order by
    case
      when a.status = 'available' and a.expires_at >= now() then 0
      when a.status = 'available' then 1
      when a.status = 'busy' then 2
      else 3
    end,
    st_distance(p.location, o.g);
$$;

grant execute on function public.nearby_providers(double precision, double precision, double precision, public.provider_type)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.providers enable row level security;
alter table public.verification_checks enable row level security;
alter table public.availability enable row level security;
alter table public.contact_events enable row level security;
alter table public.service_requests enable row level security;

-- profiles: you see and edit your own; admins see all. Nobody can make themselves admin.
create policy profiles_select on public.profiles for select
  using (id = auth.uid() or public.is_admin());
create policy profiles_insert on public.profiles for insert
  with check (id = auth.uid() and role <> 'admin');
create policy profiles_update on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid() and role <> 'admin');
create policy profiles_admin on public.profiles for all
  using (public.is_admin()) with check (public.is_admin());

-- providers: approved ones are public; owners manage their own row but cannot approve it.
create policy providers_public_read on public.providers for select
  using (status = 'approved' or owner_user_id = auth.uid() or public.is_admin());
create policy providers_owner_insert on public.providers for insert
  with check (owner_user_id = auth.uid() and status = 'pending');
create policy providers_owner_update on public.providers for update
  using (owner_user_id = auth.uid())
  with check (owner_user_id = auth.uid()
              and status = (select p.status from public.providers p where p.id = providers.id));
create policy providers_admin on public.providers for all
  using (public.is_admin()) with check (public.is_admin());

-- verification checks: readable for approved providers; only admins write.
create policy checks_read on public.verification_checks for select
  using (exists (select 1 from public.providers p
                  where p.id = provider_id
                    and (p.status = 'approved' or p.owner_user_id = auth.uid()))
         or public.is_admin());
create policy checks_admin on public.verification_checks for all
  using (public.is_admin()) with check (public.is_admin());

-- availability: public read; the provider's owner sets it.
create policy availability_read on public.availability for select using (true);
create policy availability_owner_write on public.availability for all
  using (exists (select 1 from public.providers p where p.id = provider_id and p.owner_user_id = auth.uid()))
  with check (exists (select 1 from public.providers p where p.id = provider_id and p.owner_user_id = auth.uid()));
create policy availability_admin on public.availability for all
  using (public.is_admin()) with check (public.is_admin());

-- contact events: anyone (including guests) can log a tap; only admins and the provider read them.
create policy contact_insert on public.contact_events for insert
  with check (user_id is null or user_id = auth.uid());
create policy contact_read on public.contact_events for select
  using (public.is_admin()
         or exists (select 1 from public.providers p where p.id = provider_id and p.owner_user_id = auth.uid()));

-- service requests: the owner who made it, the provider it is assigned to, and admins.
create policy requests_insert on public.service_requests for insert
  with check (user_id = auth.uid());
create policy requests_read on public.service_requests for select
  using (user_id = auth.uid()
         or public.is_admin()
         or exists (select 1 from public.providers p where p.id = provider_id and p.owner_user_id = auth.uid()));
create policy requests_owner_cancel on public.service_requests for update
  using (user_id = auth.uid()) with check (user_id = auth.uid() and status in ('requested', 'cancelled'));
create policy requests_admin on public.service_requests for all
  using (public.is_admin()) with check (public.is_admin());

-- Table privileges (RLS above still applies).
grant usage on schema public to anon, authenticated;
grant select on public.providers, public.verification_checks, public.availability to anon, authenticated;
grant insert on public.contact_events to anon, authenticated;
grant select, insert, update on public.profiles, public.service_requests to authenticated;
grant insert, update on public.providers, public.availability to authenticated;
grant select on public.contact_events to authenticated;
