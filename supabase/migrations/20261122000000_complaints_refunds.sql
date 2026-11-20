-- Fundi — complaints and refunds (Phase 2).
--
-- The owner can say something went wrong with a job, in their own words, and
-- ask for their money back. No form to fill in beyond that, no sign-up.
-- Owners are guests with no phone number on file, so asking for money back
-- also asks for the M-Pesa number to send it to. Only admins see that number.
-- The mechanic can answer once. An admin decides: upheld or not, with a note
-- the owner reads, and a refund amount if upheld.
-- Payments are not in the app yet, so a refund is recorded as "due" and the
-- admin marks it paid with the M-Pesa code once the money is back with the
-- owner. When in-app payments come, job_payout_on_hold() keeps held money from
-- going to the mechanic while a complaint is open or a refund is due.
--
-- Rules (all here, not in the app):
--   * only the owner who sent the request can complain, once per job, while it
--     is under way or within 14 days of it being done;
--   * only that job's mechanic can reply, once, while the complaint is open;
--   * only admins decide, and a refund needs an upheld complaint and is capped
--     at what the job cost (approved quotes plus the call-out fee);
--   * nobody writes the table directly.

create type public.complaint_status as enum ('open', 'upheld', 'rejected');
create type public.refund_status as enum ('none', 'due', 'paid');

create table public.complaints (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.service_requests (id) on delete cascade,
  provider_id uuid not null references public.providers (id),
  user_id uuid not null references auth.users (id) on delete cascade,
  message text not null check (length(message) between 10 and 500),
  wants_refund boolean not null default false,
  refund_phone text check (refund_phone is null or refund_phone ~ '^254[17][0-9]{8}$'),
  provider_reply text check (provider_reply is null or length(provider_reply) <= 500),
  replied_at timestamptz,
  status public.complaint_status not null default 'open',
  admin_note text check (admin_note is null or length(admin_note) <= 500),
  resolved_at timestamptz,
  resolved_by uuid references auth.users (id),
  refund_kes integer not null default 0 check (refund_kes >= 0),
  refund_status public.refund_status not null default 'none',
  refund_reference text check (refund_reference is null or length(refund_reference) <= 40),
  refund_paid_at timestamptz,
  created_at timestamptz not null default now(),
  check ((refund_kes = 0) = (refund_status = 'none')),
  check (not wants_refund or refund_phone is not null)
);
create index complaints_open_idx on public.complaints (created_at) where status = 'open';
create index complaints_provider_idx on public.complaints (provider_id, created_at desc);

alter table public.complaints enable row level security;
-- The owner who complained, the mechanic it is about, and admins.
create policy complaints_read on public.complaints for select
  using (user_id = auth.uid() or public.is_admin()
         or exists (select 1 from public.providers p
                     where p.id = provider_id and p.owner_user_id = auth.uid()));
-- Every column but the owner's refund number, which only admins read (through
-- admin_complaints). The mechanic never gets the owner's number this way.
grant select (id, request_id, provider_id, user_id, message, wants_refund, provider_reply,
              replied_at, status, admin_note, resolved_at, resolved_by, refund_kes,
              refund_status, refund_reference, refund_paid_at, created_at)
  on public.complaints to authenticated;

-- The most a refund can be: what the job cost. Approved quotes plus the
-- mechanic's call-out fee.
create or replace function public.job_cost_kes(p_request uuid)
returns integer
language sql stable security definer set search_path = public
as $$
  select coalesce((select sum(q.total_kes) from public.quotes q
                    where q.request_id = p_request and q.status = 'approved'), 0)::integer
       + coalesce((select p.callout_fee_kes from public.service_requests r
                     join public.providers p on p.id = r.provider_id
                    where r.id = p_request), 0);
$$;
revoke execute on function public.job_cost_kes(uuid) from public, anon, authenticated;

-- The owner says something went wrong.
create or replace function public.raise_complaint(
  p_request uuid, p_message text, p_wants_refund boolean default false,
  p_refund_phone text default null)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  r public.service_requests;
  v_id uuid;
  v_phone text;
  v_message text := trim(coalesce(p_message, ''));
  v_refund_phone text;
begin
  select * into r from public.service_requests
   where id = p_request and user_id = auth.uid();
  if r.id is null then
    raise exception 'Request not found' using errcode = '42501';
  end if;
  if r.provider_id is null or r.status not in ('accepted', 'done') then
    raise exception 'You can report a problem once a mechanic has taken the job';
  end if;
  if r.status = 'done' and r.done_at < now() - interval '14 days' then
    raise exception 'This job ended more than 14 days ago. Call us instead.';
  end if;
  if length(v_message) < 10 then
    raise exception 'Say in a few words what went wrong';
  end if;
  if length(v_message) > 500 then
    raise exception 'Keep it under 500 characters';
  end if;

  if coalesce(p_wants_refund, false) then
    if nullif(trim(coalesce(p_refund_phone, '')), '') is null then
      raise exception 'Give the M-Pesa number the refund should go to';
    end if;
    v_refund_phone := public._check_phone(p_refund_phone);
  end if;

  insert into public.complaints (request_id, provider_id, user_id, message, wants_refund, refund_phone)
  values (p_request, r.provider_id, auth.uid(), v_message, coalesce(p_wants_refund, false), v_refund_phone)
  on conflict (request_id) do nothing
  returning id into v_id;
  if v_id is null then
    raise exception 'You already reported a problem with this job';
  end if;

  select business_phone into v_phone from public.providers where id = r.provider_id;
  perform public.queue_sms(
    v_phone,
    'A car owner reported a problem with a job you did. Open your inbox in the app to reply. '
      || 'Fundi will look at it and tell you the outcome.',
    'complaint', v_id);
  return v_id;
end;
$$;

-- The mechanic answers, once, while the complaint is open.
create or replace function public.reply_to_complaint(p_complaint uuid, p_reply text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_reply text := trim(coalesce(p_reply, ''));
begin
  if length(v_reply) < 2 or length(v_reply) > 500 then
    raise exception 'Write a reply of up to 500 characters';
  end if;
  update public.complaints c
     set provider_reply = v_reply, replied_at = now()
    from public.providers p
   where c.id = p_complaint and p.id = c.provider_id
     and p.owner_user_id = auth.uid()
     and c.status = 'open' and c.provider_reply is null;
  if not found then
    raise exception 'Only the mechanic on this job can reply, once, while it is open'
      using errcode = '42501';
  end if;
end;
$$;

-- An admin decides. A refund needs an upheld complaint and is capped at
-- what the job cost.
create or replace function public.admin_resolve_complaint(
  p_complaint uuid, p_uphold boolean, p_note text, p_refund_kes integer default 0)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  c public.complaints;
  v_note text := trim(coalesce(p_note, ''));
  v_refund integer := coalesce(p_refund_kes, 0);
  v_cap integer;
  v_phone text;
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  select * into c from public.complaints where id = p_complaint for update;
  if c.id is null then
    raise exception 'Complaint not found';
  end if;
  if c.status <> 'open' then
    raise exception 'This complaint was already decided';
  end if;
  if length(v_note) < 2 or length(v_note) > 500 then
    raise exception 'Write a note for the owner, up to 500 characters';
  end if;
  if v_refund < 0 then
    raise exception 'A refund cannot be negative';
  end if;
  if v_refund > 0 and not coalesce(p_uphold, false) then
    raise exception 'Only an upheld complaint can have a refund';
  end if;
  v_cap := public.job_cost_kes(c.request_id);
  if v_refund > v_cap then
    raise exception 'The refund cannot be more than the job cost (KES %)', v_cap;
  end if;

  update public.complaints
     set status = case when p_uphold then 'upheld'::public.complaint_status
                       else 'rejected'::public.complaint_status end,
         admin_note = v_note,
         resolved_at = now(),
         resolved_by = auth.uid(),
         refund_kes = v_refund,
         refund_status = case when v_refund > 0 then 'due'::public.refund_status
                              else 'none'::public.refund_status end
   where id = p_complaint;

  select business_phone into v_phone from public.providers where id = c.provider_id;
  perform public.queue_sms(
    v_phone,
    case
      when p_uphold and v_refund > 0 then
        'Fundi upheld a complaint about your job. The owner gets a refund of KES '
          || to_char(v_refund, 'FM999,999,999') || '. Open the app for details.'
      when p_uphold then
        'Fundi upheld a complaint about your job. Open the app for details.'
      else
        'Fundi looked at a complaint about your job and did not uphold it. Open the app for details.'
    end,
    'complaint', c.id);
  if c.refund_phone is not null then
    perform public.queue_sms(
      '+' || c.refund_phone,
      case when v_refund > 0 then
        'Fundi agreed with your complaint. You will get KES ' || to_char(v_refund, 'FM999,999,999')
          || ' back by M-Pesa on this number.'
      else
        'Fundi has looked at your complaint. Open the app to see the outcome.'
      end,
      'complaint', c.id);
  end if;
end;
$$;

-- An admin records that the refund reached the owner (the M-Pesa code).
create or replace function public.admin_mark_refund_paid(p_complaint uuid, p_reference text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_ref text := upper(trim(coalesce(p_reference, '')));
  c public.complaints;
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  if length(v_ref) < 2 or length(v_ref) > 40 then
    raise exception 'Enter the M-Pesa code of the refund';
  end if;
  update public.complaints
     set refund_status = 'paid', refund_reference = v_ref, refund_paid_at = now()
   where id = p_complaint and refund_status = 'due'
  returning * into c;
  if c.id is null then
    raise exception 'No refund is due on this complaint';
  end if;
  perform public.queue_sms(
    '+' || c.refund_phone,
    'Fundi sent your refund of KES ' || to_char(c.refund_kes, 'FM999,999,999')
      || ' by M-Pesa. Code: ' || v_ref || '.',
    'complaint', c.id);
end;
$$;

-- For the payments step: money held for this job must not go to the mechanic
-- while a complaint is open or a refund is still due.
create or replace function public.job_payout_on_hold(p_request uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.complaints c
                  where c.request_id = p_request
                    and (c.status = 'open' or c.refund_status = 'due'));
$$;
revoke execute on function public.job_payout_on_hold(uuid) from public, anon, authenticated;

-- The owner's latest finished job in the last 30 days, so the home screen can
-- offer "Report a problem" and show what happened to a complaint.
create or replace function public.my_last_job()
returns table (request_id uuid, provider_name text, done_at timestamptz)
language sql stable security definer set search_path = public
as $$
  select r.id, p.display_name, r.done_at
    from public.service_requests r
    join public.providers p on p.id = r.provider_id
   where r.user_id = auth.uid() and r.status = 'done'
     and r.done_at > now() - interval '30 days'
   order by r.done_at desc
   limit 1;
$$;

-- The admin's list: complaints still to decide, and refunds still to pay,
-- first; then the rest of the last 60 days. With what the job cost.
create or replace function public.admin_complaints()
returns table (
  id uuid,
  request_id uuid,
  provider_name text,
  provider_phone text,
  message text,
  wants_refund boolean,
  refund_phone text,
  provider_reply text,
  status public.complaint_status,
  admin_note text,
  refund_kes integer,
  refund_status public.refund_status,
  refund_reference text,
  job_cost_kes integer,
  created_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  return query
  select c.id, c.request_id, p.display_name, p.business_phone, c.message, c.wants_refund,
         c.refund_phone, c.provider_reply, c.status, c.admin_note, c.refund_kes, c.refund_status,
         c.refund_reference, public.job_cost_kes(c.request_id), c.created_at
    from public.complaints c
    join public.providers p on p.id = c.provider_id
   where c.status = 'open' or c.refund_status = 'due'
      or c.created_at > now() - interval '60 days'
   order by (c.status = 'open' or c.refund_status = 'due') desc, c.created_at;
end;
$$;

revoke execute on function public.admin_complaints() from public, anon;
grant execute on function public.admin_complaints() to authenticated;
revoke execute on function public.raise_complaint(uuid, text, boolean, text) from public, anon;
revoke execute on function public.reply_to_complaint(uuid, text) from public, anon;
revoke execute on function public.admin_resolve_complaint(uuid, boolean, text, integer) from public, anon;
revoke execute on function public.admin_mark_refund_paid(uuid, text) from public, anon;
revoke execute on function public.my_last_job() from public, anon;
grant execute on function public.raise_complaint(uuid, text, boolean, text) to authenticated;
grant execute on function public.reply_to_complaint(uuid, text) to authenticated;
grant execute on function public.admin_resolve_complaint(uuid, boolean, text, integer) to authenticated;
grant execute on function public.admin_mark_refund_paid(uuid, text) to authenticated;
grant execute on function public.my_last_job() to authenticated;
