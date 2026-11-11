-- Fundi — provider account: a mechanic or garage manages their own listing.

-- One listing per account for now (a garage owner who is also a mechanic
-- gets a second listing through the admin console later).
create unique index providers_one_per_owner
  on public.providers (owner_user_id) where owner_user_id is not null;

-- Availability is set through this function only, so the expiry always
-- comes from the server clock and cannot be set far into the future.
drop policy availability_owner_write on public.availability;
revoke insert, update on public.availability from authenticated;

create or replace function public.set_my_availability(p_status public.availability_status)
returns timestamptz
language plpgsql security definer set search_path = public
as $$
declare
  v_provider uuid;
  v_expires timestamptz := now() + interval '4 hours';
begin
  select id into v_provider
    from public.providers
   where owner_user_id = auth.uid() and status = 'approved';
  if v_provider is null then
    raise exception 'Only an approved provider can set availability';
  end if;
  insert into public.availability (provider_id, status, set_at, expires_at)
  values (v_provider, p_status, now(), v_expires)
  on conflict (provider_id) do update
     set status = excluded.status, set_at = excluded.set_at, expires_at = excluded.expires_at;
  return v_expires;
end;
$$;

revoke execute on function public.set_my_availability(public.availability_status) from public, anon;
grant execute on function public.set_my_availability(public.availability_status) to authenticated;

-- The signed-in provider's own listing, with live availability.
create or replace function public.my_provider()
returns table (
  id uuid,
  type public.provider_type,
  display_name text,
  business_phone text,
  area text,
  status public.provider_status,
  availability text,
  availability_expires_at timestamptz
)
language sql stable security definer set search_path = public
as $$
  select p.id, p.type, p.display_name, p.business_phone, p.area, p.status,
         case
           when a.provider_id is null then 'offline'
           when a.status = 'available' and a.expires_at < now() then 'unconfirmed'
           else a.status::text
         end,
         a.expires_at
    from public.providers p
    left join public.availability a on a.provider_id = p.id
   where p.owner_user_id = auth.uid();
$$;

revoke execute on function public.my_provider() from public, anon;
grant execute on function public.my_provider() to authenticated;
