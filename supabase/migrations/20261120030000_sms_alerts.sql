-- Fundi — SMS alerts, queued in an outbox.
--
-- Mechanics and shops will not keep the app open, so the important moments
-- send a text:
--   * a mechanic gets a request (first, or sent on after a pass or no answer)
--   * a parts shop gets a new order
--   * the buyer's order is confirmed, ready to collect, or cancelled
-- Messages go into sms_outbox. Nothing sends them yet: while SMS is mocked,
-- testers read them on the test codes page (dev_latest_messages, same key).
-- BEFORE LAUNCH: a sender (an Edge Function with an SMS provider such as
-- Africa's Talking, run every minute) reads unsent rows and sets sent_at.

create table public.sms_outbox (
  id bigint generated always as identity primary key,
  to_phone text not null,
  body text not null check (length(body) <= 320),
  kind text not null,       -- request | parts_order | parts_status
  ref_id uuid,              -- the request or order it is about
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  attempts integer not null default 0
);
create index sms_outbox_unsent_idx on public.sms_outbox (created_at) where sent_at is null;

-- Never read or written by the app. Only the functions below write it.
alter table public.sms_outbox enable row level security;
revoke all on public.sms_outbox from public, anon, authenticated;

create or replace function public.queue_sms(p_to text, p_body text, p_kind text, p_ref uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if p_to is null or p_to = '' then
    return;
  end if;
  insert into public.sms_outbox (to_phone, body, kind, ref_id)
  values (p_to, left(p_body, 320), p_kind, p_ref);
end;
$$;
revoke execute on function public.queue_sms(text, text, text, uuid) from public, anon, authenticated;

-- A request reaches a mechanic.
create or replace function public.alert_request_assigned()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_phone text;
begin
  if new.provider_id is null or new.status <> 'requested' then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.provider_id is not distinct from old.provider_id then
    return new;
  end if;
  select business_phone into v_phone from public.providers where id = new.provider_id;
  perform public.queue_sms(
    v_phone,
    'New repair request' ||
      case when new.area is not null then ' near ' || new.area else '' end ||
      case when new.mode = 'come_to_me' then ': the owner wants you to come to them.'
           else ': the owner wants to bring the car to your garage.' end ||
      ' Open your inbox in the app to take it or pass.',
    'request', new.id);
  return new;
end;
$$;
revoke execute on function public.alert_request_assigned() from public, anon, authenticated;

create trigger service_requests_alert
  after insert or update of provider_id on public.service_requests
  for each row execute function public.alert_request_assigned();

-- A new parts order. place_parts_order() sets the total as its last step,
-- after every item is saved, so the alert waits for that.
create or replace function public.alert_parts_order_placed()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_shop_phone text;
  v_buyer text;
  v_items integer;
begin
  if not (old.total_kes = 0 and new.total_kes > 0 and new.status = 'placed') then
    return new;
  end if;
  select business_phone into v_shop_phone from public.parts_shops where id = new.shop_id;
  select display_name into v_buyer from public.providers where id = new.provider_id;
  select coalesce(sum(qty), 0) into v_items from public.parts_order_items where order_id = new.id;
  perform public.queue_sms(
    v_shop_phone,
    'New parts order from ' || coalesce(v_buyer, 'a mechanic') || ': ' || v_items ||
      case when v_items = 1 then ' part' else ' parts' end ||
      ', KES ' || to_char(new.total_kes, 'FM999,999,999') || '. Open the app to confirm it.',
    'parts_order', new.id);
  return new;
end;
$$;
revoke execute on function public.alert_parts_order_placed() from public, anon, authenticated;

create trigger parts_orders_alert_placed
  after update of total_kes on public.parts_orders
  for each row execute function public.alert_parts_order_placed();

-- The shop moves the order on.
create or replace function public.alert_parts_order_status()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_buyer_phone text;
  v_shop text;
begin
  if new.status is not distinct from old.status
     or new.status not in ('confirmed', 'ready', 'cancelled') then
    return new;
  end if;
  -- A buyer who cancels does not need a text about it.
  if new.status = 'cancelled' and public.is_provider_member(new.provider_id) then
    return new;
  end if;
  select business_phone into v_buyer_phone from public.providers where id = new.provider_id;
  select name into v_shop from public.parts_shops where id = new.shop_id;
  perform public.queue_sms(
    v_buyer_phone,
    'Your parts order from ' || coalesce(v_shop, 'the shop') || ' ' ||
      case new.status
        when 'confirmed' then 'is confirmed.'
        when 'ready' then 'is ready to collect. Pay the shop when you collect.'
        else 'was cancelled by the shop. Call them if you need to.'
      end,
    'parts_status', new.id);
  return new;
end;
$$;
revoke execute on function public.alert_parts_order_status() from public, anon, authenticated;

create trigger parts_orders_alert_status
  after update of status on public.parts_orders
  for each row execute function public.alert_parts_order_status();

-- DEVELOPMENT ONLY: the latest queued messages, with the same key as the test
-- codes page. Switch off before launch together with the test codes link.
create or replace function public.dev_latest_messages(p_key text)
returns table (to_phone text, body text, created_at timestamptz)
language plpgsql stable security definer set search_path = public
as $$
begin
  if p_key is null or length(p_key) < 20 or not exists (
       select 1 from public.dev_settings s
        where s.name = 'codes_key_sha256'
          and s.value = encode(sha256(convert_to(p_key, 'utf8')), 'hex')) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  return query
    select o.to_phone, o.body, o.created_at
      from public.sms_outbox o
     where o.created_at > now() - interval '24 hours'
     order by o.created_at desc
     limit 20;
end;
$$;
revoke execute on function public.dev_latest_messages(text) from public;
grant execute on function public.dev_latest_messages(text) to anon, authenticated;
