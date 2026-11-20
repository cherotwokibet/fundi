-- Fundi — itemised quotes with one-tap approval (Phase 2).
--
-- After taking a request, the mechanic can send a quote: lines of labour,
-- parts and other costs. The owner sees it on My repair and taps Approve or
-- Decline. No sign-up: the owner's guest session is enough.
-- Rules (all here, not in the app):
--   * only the mechanic who has the accepted request can quote it;
--   * a new quote replaces one still waiting for the owner ('withdrawn');
--   * only the owner who sent the request can approve or decline;
--   * the total is worked out here from the lines.
-- The mechanic gets a text when the owner answers.

create type public.quote_status as enum ('sent', 'approved', 'declined', 'withdrawn');
create type public.quote_line_kind as enum ('labour', 'part', 'other');

create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.service_requests (id) on delete cascade,
  provider_id uuid not null references public.providers (id),
  status public.quote_status not null default 'sent',
  note text check (note is null or length(note) <= 500),
  total_kes integer not null check (total_kes >= 0),
  created_at timestamptz not null default now(),
  responded_at timestamptz
);
create index quotes_request_idx on public.quotes (request_id, created_at desc);
create unique index quotes_one_waiting on public.quotes (request_id) where status = 'sent';

create table public.quote_lines (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.quotes (id) on delete cascade,
  position integer not null,
  kind public.quote_line_kind not null,
  description text not null check (length(trim(description)) between 2 and 120),
  qty integer not null check (qty between 1 and 100),
  unit_price_kes integer not null check (unit_price_kes between 0 and 1000000)
);
create index quote_lines_quote_idx on public.quote_lines (quote_id, position);

-- Who may see a request's quotes: its owner, the mechanic who has it, admins.
create or replace function public.can_see_request(p_request uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_admin() or exists (
    select 1 from public.service_requests r
      left join public.providers p on p.id = r.provider_id
     where r.id = p_request
       and (r.user_id = auth.uid() or p.owner_user_id = auth.uid()));
$$;
revoke execute on function public.can_see_request(uuid) from public, anon;
grant execute on function public.can_see_request(uuid) to authenticated;

alter table public.quotes enable row level security;
alter table public.quote_lines enable row level security;

create policy quotes_read on public.quotes for select
  using (public.can_see_request(request_id));
create policy quote_lines_read on public.quote_lines for select
  using (exists (select 1 from public.quotes q where q.id = quote_id));

-- Reads only; every write goes through the functions below.
grant select on public.quotes, public.quote_lines to authenticated;

-- The mechanic sends a quote. p_lines:
--   [{"kind": "labour", "description": "Replace brake pads", "qty": 1, "unit_price_kes": 1500}, ...]
create or replace function public.send_quote(p_request uuid, p_lines jsonb, p_note text default null)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_provider uuid;
  v_quote uuid;
  v_total integer := 0;
  v_pos integer := 0;
  l jsonb;
begin
  select r.provider_id into v_provider
    from public.service_requests r
    join public.providers p on p.id = r.provider_id
   where r.id = p_request and r.status = 'accepted'
     and p.owner_user_id = auth.uid() and p.status = 'approved';
  if v_provider is null then
    raise exception 'Only the mechanic who took this request can quote it'
      using errcode = '42501';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) = 0 or jsonb_array_length(p_lines) > 20 then
    raise exception 'A quote needs between 1 and 20 lines';
  end if;

  update public.quotes set status = 'withdrawn'
   where request_id = p_request and status = 'sent';

  insert into public.quotes (request_id, provider_id, note, total_kes)
  values (p_request, v_provider, nullif(trim(coalesce(p_note, '')), ''), 0)
  returning id into v_quote;

  for l in select * from jsonb_array_elements(p_lines) loop
    v_pos := v_pos + 1;
    insert into public.quote_lines (quote_id, position, kind, description, qty, unit_price_kes)
    values (v_quote, v_pos,
            (l->>'kind')::public.quote_line_kind,
            trim(l->>'description'),
            coalesce((l->>'qty')::integer, 1),
            (l->>'unit_price_kes')::integer);
    v_total := v_total + coalesce((l->>'qty')::integer, 1) * (l->>'unit_price_kes')::integer;
  end loop;

  update public.quotes set total_kes = v_total where id = v_quote;
  return v_quote;
end;
$$;

-- The owner approves or declines the quote waiting for them.
create or replace function public.respond_to_quote(p_quote uuid, p_approve boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  q public.quotes;
  v_phone text;
begin
  select q2.* into q
    from public.quotes q2
    join public.service_requests r on r.id = q2.request_id
   where q2.id = p_quote and r.user_id = auth.uid() and r.status = 'accepted'
   for update of q2;
  if q.id is null then
    raise exception 'Quote not found' using errcode = '42501';
  end if;
  if q.status <> 'sent' then
    raise exception 'This quote was already answered or replaced';
  end if;

  update public.quotes
     set status = case when p_approve then 'approved'::public.quote_status
                       else 'declined'::public.quote_status end,
         responded_at = now()
   where id = p_quote;

  select business_phone into v_phone from public.providers where id = q.provider_id;
  perform public.queue_sms(
    v_phone,
    case when p_approve
      then 'The owner approved your quote of KES ' || to_char(q.total_kes, 'FM999,999,999') ||
           '. Go ahead with the work.'
      else 'The owner declined your quote of KES ' || to_char(q.total_kes, 'FM999,999,999') ||
           '. Call them to talk it through, or send a new quote.'
    end,
    'quote', q.id);
end;
$$;

revoke execute on function public.send_quote(uuid, jsonb, text) from public, anon;
revoke execute on function public.respond_to_quote(uuid, boolean) from public, anon;
grant execute on function public.send_quote(uuid, jsonb, text) to authenticated;
grant execute on function public.respond_to_quote(uuid, boolean) to authenticated;
