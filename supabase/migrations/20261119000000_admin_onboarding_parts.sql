-- Fundi — admin-only onboarding and the trade-only spare parts marketplace.
--
-- 1. Nobody onboards themselves. An admin adds every garage, mobile mechanic
--    and parts shop, with the phone numbers of the people who work there.
--    Each number gets a membership. When that person signs in with the
--    number (phone code), claim_my_access() links them to it.
--    Sign-in itself stays open, because car owners need it. Signing in gives
--    a stranger nothing: every trade rule below checks for an active
--    membership. This avoids shouldCreateUser=false, which only lives in the
--    app and tells anyone which numbers are registered.
-- 2. Spare parts are sold by parts shops and seen only by members of
--    approved garages and mechanics, members of active parts shops, and
--    admins. Car owners and guests see nothing.

-- ---------------------------------------------------------------------------
-- Phone numbers. Supabase stores 2547XXXXXXXX; the app sends +2547XXXXXXXX.
-- Memberships store digits only, in the 254 form.
-- ---------------------------------------------------------------------------
create or replace function public.phone_digits(p text)
returns text
language sql immutable
as $$
  select case
    when d ~ '^0[17][0-9]{8}$' then '254' || substr(d, 2)
    when d ~ '^[17][0-9]{8}$' then '254' || d
    else d
  end
  from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') as d) x;
$$;

-- The signed-in person's phone, only once Supabase has confirmed it with a code.
create or replace function public.my_phone()
returns text
language sql stable security definer set search_path = public
as $$
  select public.phone_digits(u.phone)
    from auth.users u
   where u.id = auth.uid()
     and u.phone is not null and u.phone <> ''
     and u.phone_confirmed_at is not null;
$$;
revoke execute on function public.my_phone() from public, anon;

-- ---------------------------------------------------------------------------
-- Self-onboarding is switched off. (Rules are switched off rather than
-- dropped, as in earlier migrations: same effect, no destructive statement.)
-- ---------------------------------------------------------------------------
alter policy providers_owner_insert on public.providers
  with check (false);
-- Listing details were checked by an admin; only an admin changes them.
-- Availability still goes through set_my_availability().
alter policy providers_owner_update on public.providers
  using (false) with check (false);

-- A person can only ever give themselves the 'owner' (car owner) role.
alter policy profiles_insert on public.profiles
  with check (id = auth.uid() and role = 'owner');

create or replace function public.guard_profile_role()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.role is distinct from old.role and not public.is_admin() then
    raise exception 'Only an admin can change a role' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke execute on function public.guard_profile_role() from public, anon, authenticated;

create trigger profiles_role_guard
  before update of role on public.profiles
  for each row execute function public.guard_profile_role();

-- ---------------------------------------------------------------------------
-- Parts shops and memberships
-- ---------------------------------------------------------------------------
create type public.shop_status as enum ('active', 'suspended');
create type public.member_role as enum ('owner', 'worker');

create table public.parts_shops (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) >= 3),
  business_phone text not null,
  area text not null,
  location extensions.geography(Point, 4326),
  status public.shop_status not null default 'active',
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

-- One row per person per business. A person may belong to several.
create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid references public.providers (id) on delete cascade,
  shop_id uuid references public.parts_shops (id) on delete cascade,
  phone text not null check (phone ~ '^254[17][0-9]{8}$'),
  full_name text,
  role public.member_role not null default 'worker',
  user_id uuid references auth.users (id) on delete set null,
  active boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  check (num_nonnulls(provider_id, shop_id) = 1),
  unique (provider_id, phone),
  unique (shop_id, phone)
);
create unique index memberships_one_provider_owner
  on public.memberships (provider_id) where role = 'owner' and provider_id is not null;
create unique index memberships_one_shop_owner
  on public.memberships (shop_id) where role = 'owner' and shop_id is not null;
create index memberships_phone_idx on public.memberships (phone) where user_id is null;
create index memberships_user_idx on public.memberships (user_id) where user_id is not null;

-- Existing listings (made before this change) keep their account holder.
insert into public.memberships (provider_id, phone, full_name, role, user_id, claimed_at)
select p.id,
       public.phone_digits(coalesce(nullif(u.phone, ''), p.business_phone)),
       p.display_name, 'owner', p.owner_user_id, now()
  from public.providers p
  join auth.users u on u.id = p.owner_user_id
 where public.phone_digits(coalesce(nullif(u.phone, ''), p.business_phone)) ~ '^254[17][0-9]{8}$'
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Who may do what
-- ---------------------------------------------------------------------------
create or replace function public.is_provider_member(p_provider uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.memberships m
      join public.providers p on p.id = m.provider_id
     where m.provider_id = p_provider and m.user_id = auth.uid()
       and m.active and p.status = 'approved');
$$;

create or replace function public.is_shop_member(p_shop uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.memberships m
      join public.parts_shops s on s.id = m.shop_id
     where m.shop_id = p_shop and m.user_id = auth.uid()
       and m.active and s.status = 'active');
$$;

-- Anyone allowed into the parts marketplace.
create or replace function public.is_trade_member()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_admin() or exists (
    select 1 from public.memberships m
      left join public.providers p on p.id = m.provider_id
      left join public.parts_shops s on s.id = m.shop_id
     where m.user_id = auth.uid() and m.active
       and (p.status = 'approved' or s.status = 'active'));
$$;

revoke execute on function public.is_provider_member(uuid) from public, anon;
revoke execute on function public.is_shop_member(uuid) from public, anon;
revoke execute on function public.is_trade_member() from public, anon;
grant execute on function public.is_provider_member(uuid) to authenticated;
grant execute on function public.is_shop_member(uuid) to authenticated;
grant execute on function public.is_trade_member() to authenticated;

-- What the signed-in person belongs to (active memberships only).
create or replace function public.my_access()
returns table (
  membership_id uuid,
  kind text,              -- 'provider' | 'shop'
  org_id uuid,
  org_name text,
  org_status text,        -- provider: pending|approved|suspended; shop: active|suspended
  role public.member_role
)
language sql stable security definer set search_path = public
as $$
  select m.id,
         case when m.provider_id is not null then 'provider' else 'shop' end,
         coalesce(m.provider_id, m.shop_id),
         coalesce(p.display_name, s.name),
         coalesce(p.status::text, s.status::text),
         m.role
    from public.memberships m
    left join public.providers p on p.id = m.provider_id
    left join public.parts_shops s on s.id = m.shop_id
   where m.user_id = auth.uid() and m.active
   order by m.created_at;
$$;

-- Links the signed-in person to every business an admin added their
-- (confirmed) phone number to, then returns what they belong to.
-- Safe to call on every sign-in.
create or replace function public.claim_my_access()
returns table (
  membership_id uuid,
  kind text,
  org_id uuid,
  org_name text,
  org_status text,
  role public.member_role
)
language plpgsql security definer set search_path = public
as $$
declare
  v_phone text := public.my_phone();
begin
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  if v_phone is not null then
    update public.memberships
       set user_id = auth.uid(), claimed_at = now()
     where user_id is null and active and phone = v_phone;
    -- The owner of a garage or mechanic listing runs its inbox and availability.
    update public.providers p
       set owner_user_id = auth.uid()
      from public.memberships m
     where m.provider_id = p.id and m.role = 'owner' and m.active
       and m.user_id = auth.uid() and p.owner_user_id is null
       and not exists (select 1 from public.providers o where o.owner_user_id = auth.uid());
  end if;
  return query select * from public.my_access();
end;
$$;

revoke execute on function public.my_access() from public, anon;
revoke execute on function public.claim_my_access() from public, anon;
grant execute on function public.my_access() to authenticated;
grant execute on function public.claim_my_access() to authenticated;

-- ---------------------------------------------------------------------------
-- Admin onboarding. Each checks is_admin().
-- ---------------------------------------------------------------------------
create or replace function public._bind_existing_user(p_member uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid;
begin
  -- If the person already has a confirmed account, link it now.
  select u.id into v_user
    from auth.users u, public.memberships m
   where m.id = p_member and u.phone_confirmed_at is not null
     and public.phone_digits(u.phone) = m.phone
   limit 1;
  if v_user is not null then
    update public.memberships set user_id = v_user, claimed_at = now()
     where id = p_member and user_id is null;
    update public.providers p set owner_user_id = v_user
      from public.memberships m
     where m.id = p_member and m.role = 'owner' and p.id = m.provider_id
       and p.owner_user_id is null
       and not exists (select 1 from public.providers o where o.owner_user_id = v_user);
  end if;
end;
$$;
revoke execute on function public._bind_existing_user(uuid) from public, anon, authenticated;

create or replace function public._check_phone(p_phone text)
returns text
language plpgsql immutable
as $$
declare
  v text := public.phone_digits(p_phone);
begin
  if v !~ '^254[17][0-9]{8}$' then
    raise exception 'Enter a Kenyan mobile number, for example 0712 345 678';
  end if;
  return v;
end;
$$;

-- Adds a garage or mobile mechanic. It starts as 'pending': the admin then
-- records the checks and approves it, as before.
create or replace function public.admin_create_provider(
  p_type public.provider_type,
  p_name text,
  p_business_phone text,
  p_area text,
  p_lat double precision,
  p_lng double precision,
  p_owner_phone text,
  p_owner_name text default null,
  p_service_radius_km numeric default 5,
  p_callout_fee_kes integer default null,
  p_makes text[] default '{}'
)
returns uuid
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_owner text := public._check_phone(p_owner_phone);
  v_provider uuid;
  v_member uuid;
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  perform public._check_phone(p_business_phone);
  if length(trim(coalesce(p_name, ''))) < 3 then
    raise exception 'Enter the name owners will see';
  end if;
  -- One listing per account holder (see providers_one_per_owner).
  if exists (select 1 from public.memberships m
              where m.provider_id is not null and m.role = 'owner' and m.active and m.phone = v_owner) then
    raise exception 'This number already runs a listing';
  end if;

  insert into public.providers (type, display_name, business_phone, area, location,
                                service_radius_km, callout_fee_kes, makes, status)
  values (p_type, trim(p_name), '+' || public.phone_digits(p_business_phone), p_area,
          st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
          case when p_type = 'garage' then 0 else coalesce(p_service_radius_km, 5) end,
          p_callout_fee_kes, coalesce(p_makes, '{}'), 'pending')
  returning id into v_provider;

  insert into public.memberships (provider_id, phone, full_name, role, created_by)
  values (v_provider, v_owner, nullif(trim(coalesce(p_owner_name, '')), ''), 'owner', auth.uid())
  returning id into v_member;
  perform public._bind_existing_user(v_member);
  return v_provider;
end;
$$;

-- Adds a parts shop. Shops are checked in person before they are added,
-- so they start active.
create or replace function public.admin_create_shop(
  p_name text,
  p_business_phone text,
  p_area text,
  p_lat double precision,
  p_lng double precision,
  p_owner_phone text,
  p_owner_name text default null
)
returns uuid
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_owner text := public._check_phone(p_owner_phone);
  v_shop uuid;
  v_member uuid;
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  perform public._check_phone(p_business_phone);
  insert into public.parts_shops (name, business_phone, area, location, created_by)
  values (trim(p_name), '+' || public.phone_digits(p_business_phone), p_area,
          case when p_lat is null or p_lng is null then null
               else st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography end,
          auth.uid())
  returning id into v_shop;
  insert into public.memberships (shop_id, phone, full_name, role, created_by)
  values (v_shop, v_owner, nullif(trim(coalesce(p_owner_name, '')), ''), 'owner', auth.uid())
  returning id into v_member;
  perform public._bind_existing_user(v_member);
  return v_shop;
end;
$$;

-- Adds a worker to a garage, mechanic listing or parts shop.
create or replace function public.admin_add_member(
  p_provider uuid,
  p_shop uuid,
  p_phone text,
  p_name text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_phone text := public._check_phone(p_phone);
  v_member uuid;
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  insert into public.memberships (provider_id, shop_id, phone, full_name, role, created_by)
  values (p_provider, p_shop, v_phone, nullif(trim(coalesce(p_name, '')), ''), 'worker', auth.uid())
  on conflict do nothing
  returning id into v_member;
  if v_member is null then
    -- Already on the list: switch them back on.
    update public.memberships set active = true
     where phone = v_phone
       and (provider_id = p_provider or shop_id = p_shop)
    returning id into v_member;
  end if;
  perform public._bind_existing_user(v_member);
  return v_member;
end;
$$;

-- Switches a person's access on or off. Switching off the owner of a
-- garage or mechanic listing also takes away its inbox and availability.
create or replace function public.admin_set_member_active(p_member uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  m public.memberships;
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  update public.memberships set active = p_active where id = p_member returning * into m;
  if m.id is null then
    raise exception 'Person not found';
  end if;
  if m.provider_id is not null and m.role = 'owner' then
    if not p_active then
      update public.providers set owner_user_id = null
       where id = m.provider_id and owner_user_id = m.user_id;
    else
      perform public._bind_existing_user(m.id);
      update public.providers p set owner_user_id = m.user_id
       where p.id = m.provider_id and p.owner_user_id is null and m.user_id is not null
         and not exists (select 1 from public.providers o where o.owner_user_id = m.user_id);
    end if;
  end if;
end;
$$;

create or replace function public.admin_set_shop_status(p_shop uuid, p_status public.shop_status)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  update public.parts_shops set status = p_status where id = p_shop;
  if not found then
    raise exception 'Shop not found';
  end if;
end;
$$;

revoke execute on function public.admin_create_provider(public.provider_type, text, text, text, double precision, double precision, text, text, numeric, integer, text[]) from public, anon;
revoke execute on function public.admin_create_shop(text, text, text, double precision, double precision, text, text) from public, anon;
revoke execute on function public.admin_add_member(uuid, uuid, text, text) from public, anon;
revoke execute on function public.admin_set_member_active(uuid, boolean) from public, anon;
revoke execute on function public.admin_set_shop_status(uuid, public.shop_status) from public, anon;
grant execute on function public.admin_create_provider(public.provider_type, text, text, text, double precision, double precision, text, text, numeric, integer, text[]) to authenticated;
grant execute on function public.admin_create_shop(text, text, text, double precision, double precision, text, text) to authenticated;
grant execute on function public.admin_add_member(uuid, uuid, text, text) to authenticated;
grant execute on function public.admin_set_member_active(uuid, boolean) to authenticated;
grant execute on function public.admin_set_shop_status(uuid, public.shop_status) to authenticated;

-- Admins upload verification documents they collect in person.
-- Their files go under admin/<provider id>/<kind> in the private 'kyc' bucket.
create policy kyc_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'kyc' and public.is_admin());
create policy kyc_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'kyc' and public.is_admin())
  with check (bucket_id = 'kyc' and public.is_admin());

-- ---------------------------------------------------------------------------
-- Parts listings
-- ---------------------------------------------------------------------------
create type public.part_condition as enum ('new', 'used', 'refurbished');

create table public.parts_listings (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.parts_shops (id) on delete cascade,
  title text not null check (length(trim(title)) >= 3),
  part_number text,
  makes text[] not null default '{}',     -- empty = fits all makes
  models text,                            -- free text, e.g. 'Probox, Succeed'
  year_from integer check (year_from between 1970 and 2100),
  year_to integer check (year_to between 1970 and 2100),
  condition public.part_condition not null default 'new',
  price_kes integer not null check (price_kes > 0),
  stock_qty integer not null default 1 check (stock_qty >= 0),
  photo_path text,
  active boolean not null default true,
  created_by uuid references auth.users (id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (year_from is null or year_to is null or year_from <= year_to)
);
create index parts_listings_shop_idx on public.parts_listings (shop_id);
create index parts_listings_active_idx on public.parts_listings (active) where active;

-- ---------------------------------------------------------------------------
-- Parts orders. Placed and moved on only through the functions below.
-- Payment is between the buyer and the shop for now (cash or M-Pesa on
-- collection); in-app payment comes with Phase 2 payments.
-- ---------------------------------------------------------------------------
create type public.parts_order_status as enum ('placed', 'confirmed', 'ready', 'collected', 'cancelled');

create table public.parts_orders (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.providers (id),
  shop_id uuid not null references public.parts_shops (id),
  placed_by uuid not null references auth.users (id),
  status public.parts_order_status not null default 'placed',
  note text,
  total_kes integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index parts_orders_provider_idx on public.parts_orders (provider_id, created_at desc);
create index parts_orders_shop_idx on public.parts_orders (shop_id, created_at desc);

create table public.parts_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.parts_orders (id) on delete cascade,
  listing_id uuid not null references public.parts_listings (id),
  title text not null,                 -- as it was when ordered
  unit_price_kes integer not null,     -- as it was when ordered
  qty integer not null check (qty between 1 and 100)
);
create index parts_order_items_order_idx on public.parts_order_items (order_id);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table public.parts_shops enable row level security;
alter table public.memberships enable row level security;
alter table public.parts_listings enable row level security;
alter table public.parts_orders enable row level security;
alter table public.parts_order_items enable row level security;

-- Shops: trade members see active shops; a shop's own people see it; admins see all.
create policy shops_read on public.parts_shops for select
  using (public.is_admin() or public.is_shop_member(id)
         or (status = 'active' and public.is_trade_member()));
create policy shops_admin on public.parts_shops for all
  using (public.is_admin()) with check (public.is_admin());

-- Memberships: you see your own; admins manage all. Written only by admin functions.
create policy memberships_read on public.memberships for select
  using (user_id = auth.uid() or public.is_admin());
create policy memberships_admin on public.memberships for all
  using (public.is_admin()) with check (public.is_admin());

-- Listings: trade members see active listings of active shops. A shop's
-- people see and edit their own shop's listings (owners and workers).
create policy listings_read on public.parts_listings for select
  using (public.is_admin() or public.is_shop_member(shop_id)
         or (active and public.is_trade_member()
             and exists (select 1 from public.parts_shops s
                          where s.id = shop_id and s.status = 'active')));
create policy listings_shop_insert on public.parts_listings for insert
  with check (public.is_shop_member(shop_id)
              and (photo_path is null or photo_path like 'shops/' || shop_id::text || '/%'));
create policy listings_shop_update on public.parts_listings for update
  using (public.is_shop_member(shop_id))
  with check (public.is_shop_member(shop_id)
              and (photo_path is null or photo_path like 'shops/' || shop_id::text || '/%'));
create policy listings_admin on public.parts_listings for all
  using (public.is_admin()) with check (public.is_admin());

-- Orders: the buying garage or mechanic, the selling shop, and admins.
create policy orders_read on public.parts_orders for select
  using (public.is_admin() or public.is_provider_member(provider_id) or public.is_shop_member(shop_id));
create policy order_items_read on public.parts_order_items for select
  using (exists (select 1 from public.parts_orders o where o.id = order_id));

-- Bumps updated_at on listings.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger parts_listings_touch before update on public.parts_listings
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Marketplace functions
-- ---------------------------------------------------------------------------

-- Search for parts. Trade members only. Nearest shop first when the caller
-- runs an approved garage or mechanic listing.
create or replace function public.search_parts(
  p_query text default null,
  p_make text default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  title text,
  part_number text,
  makes text[],
  models text,
  year_from integer,
  year_to integer,
  condition public.part_condition,
  price_kes integer,
  stock_qty integer,
  photo_path text,
  shop_id uuid,
  shop_name text,
  shop_phone text,
  shop_area text,
  distance_km double precision
)
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_here extensions.geography;
  q text := nullif(trim(coalesce(p_query, '')), '');
begin
  if not public.is_trade_member() then
    raise exception 'The parts marketplace is for registered garages, mechanics and parts shops'
      using errcode = '42501';
  end if;
  select p.location into v_here
    from public.memberships m join public.providers p on p.id = m.provider_id
   where m.user_id = auth.uid() and m.active and p.status = 'approved'
   order by m.role, m.created_at limit 1;
  return query
    select l.id, l.title, l.part_number, l.makes, l.models, l.year_from, l.year_to,
           l.condition, l.price_kes, l.stock_qty, l.photo_path,
           s.id, s.name, s.business_phone, s.area,
           case when v_here is null or s.location is null then null
                else round((st_distance(s.location, v_here) / 1000.0)::numeric, 1)::double precision end
      from public.parts_listings l
      join public.parts_shops s on s.id = l.shop_id
     where l.active and l.stock_qty > 0 and s.status = 'active'
       and (q is null
            or l.title ilike '%' || q || '%'
            or l.part_number ilike '%' || q || '%'
            or l.models ilike '%' || q || '%')
       and (nullif(trim(coalesce(p_make, '')), '') is null
            or cardinality(l.makes) = 0
            or exists (select 1 from unnest(l.makes) mk where lower(mk) = lower(trim(p_make))))
     order by case when v_here is null or s.location is null then 1 else 0 end,
              st_distance(s.location, v_here) nulls last, l.price_kes
     limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;

-- Places an order for one garage or mechanic listing, with one shop.
-- p_items: [{"listing_id": "...", "qty": 2}, ...]. Prices are copied from
-- the listing and stock is held until the order is collected or cancelled.
create or replace function public.place_parts_order(
  p_provider uuid,
  p_items jsonb,
  p_note text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_order uuid;
  v_shop uuid;
  v_total integer := 0;
  it record;
  v_l public.parts_listings;
begin
  if not public.is_provider_member(p_provider) then
    raise exception 'Only people at an approved garage or mechanic listing can order parts'
      using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Add at least one part';
  end if;

  select min(pl.shop_id::text)::uuid, count(distinct pl.shop_id)
    into v_shop, v_total
    from jsonb_array_elements(p_items) e
    join public.parts_listings pl on pl.id = (e->>'listing_id')::uuid;
  if v_total > 1 then
    raise exception 'One order is for one shop';
  end if;
  if v_shop is null then
    raise exception 'A part in this order is no longer listed';
  end if;
  v_total := 0;

  insert into public.parts_orders (provider_id, shop_id, placed_by, note, total_kes)
  values (p_provider, v_shop, auth.uid(), nullif(trim(coalesce(p_note, '')), ''), 0)
  returning id into v_order;

  for it in
    select (e->>'listing_id')::uuid as listing_id, (e->>'qty')::integer as qty
      from jsonb_array_elements(p_items) e
  loop
    select * into v_l from public.parts_listings where id = it.listing_id for update;
    if v_l.id is null or not v_l.active then
      raise exception 'A part in this order is no longer listed';
    end if;
    if not exists (select 1 from public.parts_shops s where s.id = v_l.shop_id and s.status = 'active') then
      raise exception 'This shop is not taking orders';
    end if;
    if v_l.shop_id <> v_shop then
      raise exception 'One order is for one shop';
    end if;
    if it.qty is null or it.qty < 1 or it.qty > 100 then
      raise exception 'Quantity must be between 1 and 100';
    end if;
    if v_l.stock_qty < it.qty then
      raise exception 'Only % left of %', v_l.stock_qty, v_l.title;
    end if;
    update public.parts_listings set stock_qty = stock_qty - it.qty where id = v_l.id;
    insert into public.parts_order_items (order_id, listing_id, title, unit_price_kes, qty)
    values (v_order, v_l.id, v_l.title, v_l.price_kes, it.qty);
    v_total := v_total + v_l.price_kes * it.qty;
  end loop;

  update public.parts_orders set total_kes = v_total where id = v_order;
  return v_order;
end;
$$;

-- Moves an order on.
--   Shop:  placed → confirmed → ready → collected; cancel before collection.
--   Buyer: cancel while the order is still 'placed'.
-- Cancelling puts the stock back.
create or replace function public.update_parts_order(p_order uuid, p_status public.parts_order_status)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  o public.parts_orders;
  v_shop boolean;
  v_buyer boolean;
begin
  select * into o from public.parts_orders where id = p_order for update;
  if o.id is null then
    raise exception 'Order not found';
  end if;
  v_shop := public.is_shop_member(o.shop_id) or public.is_admin();
  v_buyer := public.is_provider_member(o.provider_id);
  if not (
       (v_shop and (o.status, p_status) in (('placed', 'confirmed'), ('confirmed', 'ready'),
                                            ('ready', 'collected'), ('placed', 'cancelled'),
                                            ('confirmed', 'cancelled'), ('ready', 'cancelled')))
    or (v_buyer and o.status = 'placed' and p_status = 'cancelled')) then
    raise exception 'This order cannot move from % to %', o.status, p_status
      using errcode = '42501';
  end if;
  update public.parts_orders set status = p_status, updated_at = now() where id = p_order;
  if p_status = 'cancelled' then
    update public.parts_listings l set stock_qty = l.stock_qty + i.qty
      from public.parts_order_items i
     where i.order_id = p_order and i.listing_id = l.id;
  end if;
end;
$$;

revoke execute on function public.search_parts(text, text, integer) from public, anon;
revoke execute on function public.place_parts_order(uuid, jsonb, text) from public, anon;
revoke execute on function public.update_parts_order(uuid, public.parts_order_status) from public, anon;
grant execute on function public.search_parts(text, text, integer) to authenticated;
grant execute on function public.place_parts_order(uuid, jsonb, text) to authenticated;
grant execute on function public.update_parts_order(uuid, public.parts_order_status) to authenticated;

-- ---------------------------------------------------------------------------
-- Part photos: private bucket. Shop people upload under shops/<shop id>/;
-- trade members can view.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('parts', 'parts', false)
on conflict (id) do nothing;

create or replace function public.is_shop_member_path(p_name text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select (storage.foldername(p_name))[1] = 'shops'
     and exists (select 1 from public.memberships m
                   join public.parts_shops s on s.id = m.shop_id
                  where s.id::text = (storage.foldername(p_name))[2]
                    and m.user_id = auth.uid() and m.active and s.status = 'active');
$$;
revoke execute on function public.is_shop_member_path(text) from public, anon;
grant execute on function public.is_shop_member_path(text) to authenticated;

create policy parts_photo_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'parts' and (public.is_shop_member_path(name) or public.is_admin()));
create policy parts_photo_update on storage.objects for update to authenticated
  using (bucket_id = 'parts' and (public.is_shop_member_path(name) or public.is_admin()))
  with check (bucket_id = 'parts' and (public.is_shop_member_path(name) or public.is_admin()));
create policy parts_photo_read on storage.objects for select to authenticated
  using (bucket_id = 'parts' and public.is_trade_member());

-- ---------------------------------------------------------------------------
-- Table privileges (RLS above still applies). Nothing for anon.
-- ---------------------------------------------------------------------------
grant select on public.parts_shops, public.memberships, public.parts_listings,
                public.parts_orders, public.parts_order_items to authenticated;
grant insert, update on public.parts_listings to authenticated;
-- Admin console writes shops and memberships through the functions above,
-- and reads them through the policies.
grant update on public.parts_shops to authenticated;
