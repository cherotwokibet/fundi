-- Fundi — mechanic inbox: a provider sees the "Find me a mechanic" requests
-- sent to them, with the note, photo and voice note, and takes or passes on each.

alter table public.service_requests
  add column responded_at timestamptz,
  -- Providers who passed on this request, so it is never sent to them again.
  add column declined_provider_ids uuid[] not null default '{}';

create index service_requests_provider_idx
  on public.service_requests (provider_id, created_at desc);

-- An owner may only cancel their own request, through cancel_my_request().
-- Before this, the update policy let the owner change other columns too
-- (for example provider_id). Admins keep their own policy. The old rule is
-- switched off rather than dropped (same effect, no destructive statement).
alter policy requests_owner_cancel on public.service_requests
  using (false) with check (false);

create or replace function public.cancel_my_request(p_request uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.service_requests
     set status = 'cancelled'
   where id = p_request
     and user_id = auth.uid()
     and status in ('requested', 'accepted');
  if not found then
    raise exception 'Request not found or already under way';
  end if;
end;
$$;

-- A new request cannot be sent to a provider who already passed on it,
-- and only goes to approved providers.
create or replace function public.check_request_provider()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.provider_id is not null then
    if new.provider_id = any (new.declined_provider_ids) then
      raise exception 'This provider already passed on the request';
    end if;
    if not exists (select 1 from public.providers p
                    where p.id = new.provider_id and p.status = 'approved') then
      raise exception 'Requests can only go to approved providers';
    end if;
  end if;
  return new;
end;
$$;

create trigger service_requests_provider_check
  before insert or update of provider_id on public.service_requests
  for each row execute function public.check_request_provider();

-- The signed-in provider's inbox: requests assigned to them, newest first.
-- Cancelled requests and anything older than 14 days are left out.
create or replace function public.my_requests()
returns table (
  id uuid,
  mode public.request_mode,
  area text,
  note text,
  car_make text,
  contact_phone text,
  photo_path text,
  voice_path text,
  status public.request_status,
  created_at timestamptz,
  distance_km double precision
)
language sql stable security definer set search_path = public, extensions
as $$
  select r.id, r.mode, r.area, r.note, r.car_make, r.contact_phone,
         r.photo_path, r.voice_path, r.status, r.created_at,
         case when r.location is null then null
              else round((st_distance(r.location, p.location) / 1000.0)::numeric, 1)::double precision
         end
    from public.service_requests r
    join public.providers p on p.id = r.provider_id
   where p.owner_user_id = auth.uid()
     and p.status = 'approved'
     and r.status <> 'cancelled'
     and r.created_at > now() - interval '14 days'
   order by r.created_at desc
   limit 50;
$$;

-- Take a request ("I'll take it") or pass on it ("I can't take it").
-- Passing frees the request so it can go to someone else, and the provider
-- loses access to it and its photo and voice note.
create or replace function public.respond_to_request(p_request uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_provider uuid;
begin
  select id into v_provider
    from public.providers
   where owner_user_id = auth.uid() and status = 'approved';
  if v_provider is null then
    raise exception 'Only an approved provider can answer requests';
  end if;

  if p_accept then
    update public.service_requests
       set status = 'accepted', responded_at = now()
     where id = p_request and provider_id = v_provider and status = 'requested';
  else
    update public.service_requests
       set provider_id = null,
           responded_at = now(),
           declined_provider_ids = array_append(declined_provider_ids, v_provider)
     where id = p_request and provider_id = v_provider and status = 'requested';
  end if;
  if not found then
    raise exception 'This request is no longer waiting for you';
  end if;
end;
$$;

revoke execute on function public.cancel_my_request(uuid) from public, anon;
revoke execute on function public.my_requests() from public, anon;
revoke execute on function public.respond_to_request(uuid, boolean) from public, anon;
revoke execute on function public.check_request_provider() from public, anon, authenticated;
grant execute on function public.cancel_my_request(uuid) to authenticated;
grant execute on function public.my_requests() to authenticated;
grant execute on function public.respond_to_request(uuid, boolean) to authenticated;
