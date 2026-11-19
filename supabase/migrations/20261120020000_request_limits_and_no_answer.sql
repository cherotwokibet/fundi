-- Fundi — limits on requests, and re-sending a request nobody answered.
--
-- 1. Limits (the known gap "nothing limits how many requests a guest can
--    send"). Per account: at most 2 open requests at once and 6 in 24 hours.
--    Per mechanic: at most 5 requests waiting for them; past that, new
--    requests go to someone else. Supabase also limits how many guest
--    accounts one network address can open, which covers starting over as a
--    new guest.
-- 2. No answer. After 5 minutes with no answer, the owner's waiting screen
--    asks for the request to be sent on (nudge_my_request). The 5 minutes are
--    checked here, on the server clock. If another free mechanic fits, the
--    request moves to them; if not, it stays where it is. It counts toward
--    the same 3 re-sends as a pass.

-- Why the current mechanic has the request: 'first', 'passed' (the last
-- mechanic said they can't), or 'no_answer'.
alter table public.service_requests
  add column handoff text not null default 'first'
    check (handoff in ('first', 'passed', 'no_answer'));

create or replace function public.check_request_limits()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if (select count(*) from public.service_requests r
       where r.user_id = new.user_id and r.status in ('requested', 'accepted')
         and r.created_at > now() - interval '24 hours') >= 2 then
    raise exception 'LIMIT: You already have repair requests open. Open My repair to follow them, or cancel one first.';
  end if;
  if (select count(*) from public.service_requests r
       where r.user_id = new.user_id and r.created_at > now() - interval '24 hours') >= 6 then
    raise exception 'LIMIT: You have sent many requests today. You can still call a mechanic from Browse and call.';
  end if;
  if new.provider_id is not null and
     (select count(*) from public.service_requests r
       where r.provider_id = new.provider_id and r.status = 'requested'
         and r.created_at > now() - interval '24 hours') >= 5 then
    raise exception 'LIMIT: This mechanic has many requests waiting. Pick someone else, or call them.';
  end if;
  new.handoff := 'first';
  return new;
end;
$$;
revoke execute on function public.check_request_limits() from public, anon, authenticated;

create trigger service_requests_limits
  before insert on public.service_requests
  for each row execute function public.check_request_limits();

-- Same as before, and now skips mechanics with 5 requests already waiting.
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
     and (select count(*) from public.service_requests x
           where x.provider_id = p.id and x.status = 'requested'
             and x.created_at > now() - interval '24 hours') < 5
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

-- A pass records why the next mechanic has it.
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
             rematch_count = rematch_count + 1,
             handoff = 'passed'
       where id = p_request;
    end if;
  end if;
end;
$$;

-- The owner's waiting screen calls this once 5 minutes have passed with no
-- answer. Returns true when the request moved to another mechanic.
create or replace function public.nudge_my_request(p_request uuid)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  r public.service_requests;
  v_next uuid;
begin
  select * into r from public.service_requests
   where id = p_request and user_id = auth.uid()
   for update;
  if r.id is null then
    raise exception 'Request not found';
  end if;
  if r.status <> 'requested' or r.provider_id is null or r.rematch_count >= 3
     or coalesce(r.assigned_at, r.created_at) > now() - interval '5 minutes' then
    return false;
  end if;

  -- Look for someone else, as if the current mechanic had passed.
  update public.service_requests
     set declined_provider_ids = array_append(declined_provider_ids, r.provider_id)
   where id = p_request;
  v_next := public.next_best_provider(p_request);
  if v_next is null then
    -- Nobody else fits: leave it with the current mechanic.
    update public.service_requests
       set declined_provider_ids = r.declined_provider_ids
     where id = p_request;
    return false;
  end if;

  update public.service_requests
     set provider_id = v_next,
         assigned_at = now(),
         responded_at = null,
         rematch_count = rematch_count + 1,
         handoff = 'no_answer'
   where id = p_request;
  return true;
end;
$$;
revoke execute on function public.nudge_my_request(uuid) from public, anon;
grant execute on function public.nudge_my_request(uuid) to authenticated;

-- The owner's view now also says why the current mechanic has it.
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
  rematch_count integer,
  handoff text
)
language sql stable security definer set search_path = public
as $$
  select r.id, r.mode, r.status, r.created_at, r.responded_at,
         r.note is not null, r.photo_path is not null, r.voice_path is not null,
         p.id, p.display_name, p.business_phone, p.type, p.callout_fee_kes,
         coalesce(r.assigned_at, r.created_at), r.rematch_count, r.handoff
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
