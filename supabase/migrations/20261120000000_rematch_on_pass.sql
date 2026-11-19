-- Fundi — when a mechanic passes on a request, send it on to the next best
-- free mechanic automatically, so the owner does not have to start again.
--
-- "Next best" uses the same rules as the app's best match: approved, identity
-- checked, not busy or offline, never someone who already passed; for "come to
-- me" a mobile mechanic whose travel radius reaches the owner, for "visit a
-- garage" a garage within 10 km; available first, then nearest.
-- A request is re-sent at most 3 times. After that, or when nobody fits, it
-- waits with no mechanic and the owner sees the mechanics nearby, as before.

alter table public.service_requests
  -- When the current mechanic got the request (restarts the owner's timer).
  add column assigned_at timestamptz default now(),
  -- How many times it was re-sent after a pass.
  add column rematch_count integer not null default 0 check (rematch_count >= 0);

update public.service_requests
   set assigned_at = created_at
 where assigned_at is null or assigned_at > created_at;

create or replace function public.next_best_provider(p_request uuid)
returns uuid
language sql stable security definer set search_path = public, extensions
as $$
  select p.id
    from public.service_requests r
    join public.providers p on p.status = 'approved'
    join public.availability a on a.provider_id = p.id and a.status = 'available'
   where r.id = p_request
     and r.location is not null
     and not (p.id = any (r.declined_provider_ids))
     and p.owner_user_id is not null
     and p.owner_user_id <> r.user_id
     and exists (
       select 1 from public.verification_checks v
        where v.provider_id = p.id and v.kind = 'identity' and v.status = 'passed'
          and (v.expires_at is null or v.expires_at > now()))
     and case
           when r.mode = 'come_to_me' then
             p.type = 'mobile_mechanic'
             and st_dwithin(p.location, r.location, p.service_radius_km * 1000)
           else
             p.type = 'garage' and st_dwithin(p.location, r.location, 10000)
         end
   order by case when a.expires_at >= now() then 0 else 1 end,
            st_distance(p.location, r.location)
   limit 1;
$$;
revoke execute on function public.next_best_provider(uuid) from public, anon, authenticated;

-- Take a request ("I'll take it") or pass on it ("I can't take it").
-- Passing frees the request, the provider loses access to it and its files,
-- and it goes on to the next best mechanic if there is one.
create or replace function public.respond_to_request(p_request uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_provider uuid;
  v_next uuid;
  v_count integer;
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
    if not found then
      raise exception 'This request is no longer waiting for you';
    end if;
    return;
  end if;

  update public.service_requests
     set provider_id = null,
         responded_at = now(),
         declined_provider_ids = array_append(declined_provider_ids, v_provider)
   where id = p_request and provider_id = v_provider and status = 'requested'
  returning rematch_count into v_count;
  if not found then
    raise exception 'This request is no longer waiting for you';
  end if;

  if v_count < 3 then
    v_next := public.next_best_provider(p_request);
    if v_next is not null then
      update public.service_requests
         set provider_id = v_next,
             assigned_at = now(),
             responded_at = null,
             rematch_count = rematch_count + 1
       where id = p_request;
    end if;
  end if;
end;
$$;

-- The owner's open request, now with when the current mechanic got it and
-- how many times it was re-sent. The return type changes, so the function is
-- replaced (it holds no data).
drop function public.my_open_request();
create function public.my_open_request()
returns table (
  id uuid,
  mode public.request_mode,
  status public.request_status,
  created_at timestamptz,
  responded_at timestamptz,
  has_note boolean,
  has_photo boolean,
  has_voice boolean,
  provider_id uuid,
  provider_name text,
  provider_phone text,
  provider_type public.provider_type,
  callout_fee_kes integer,
  assigned_at timestamptz,
  rematch_count integer
)
language sql stable security definer set search_path = public
as $$
  select r.id, r.mode, r.status, r.created_at, r.responded_at,
         r.note is not null, r.photo_path is not null, r.voice_path is not null,
         p.id, p.display_name, p.business_phone, p.type, p.callout_fee_kes,
         coalesce(r.assigned_at, r.created_at), r.rematch_count
    from public.service_requests r
    left join public.providers p on p.id = r.provider_id and p.status = 'approved'
   where r.user_id = auth.uid()
     and r.status in ('requested', 'accepted')
     and r.created_at > now() - interval '24 hours'
   order by r.created_at desc
   limit 1;
$$;
revoke execute on function public.my_open_request() from public, anon;
grant execute on function public.my_open_request() to authenticated;

-- Owners cannot set these themselves: the insert policy already pins
-- user_id; this keeps a fresh request at zero re-sends with the server time.
create or replace function public.reset_request_assignment()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  new.rematch_count := 0;
  new.assigned_at := now();
  return new;
end;
$$;
revoke execute on function public.reset_request_assignment() from public, anon, authenticated;

create trigger service_requests_assignment_reset
  before insert on public.service_requests
  for each row execute function public.reset_request_assignment();
