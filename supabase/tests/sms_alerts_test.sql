-- SMS alerts outbox (migration 20261120030000). Run with supabase/tests/run.sh.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

insert into auth.users (id, phone, phone_confirmed_at, is_anonymous) values
  ('00000000-0000-0000-0000-000000000ba1', '254700000901', now(), false), -- mechanic S1
  ('00000000-0000-0000-0000-000000000ba2', '254700000902', now(), false), -- mechanic S2
  ('00000000-0000-0000-0000-000000000bb1', '254700000903', now(), false), -- shop owner
  ('00000000-0000-0000-0000-000000000bd1', null, null, true),             -- guest owner
  ('00000000-0000-0000-0000-000000000bf1', '254700000904', now(), false); -- admin
insert into public.profiles (id, role) values ('00000000-0000-0000-0000-000000000bf1', 'admin');

-- Thika (37.07, -1.03): away from the other test files.
insert into public.providers (id, owner_user_id, type, display_name, business_phone, area, location, service_radius_km, status) values
  ('b0000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000ba1', 'mobile_mechanic', 'S1', '+254700000901', 'Thika', 'SRID=4326;POINT(37.0710 -1.0300)', 5, 'approved'),
  ('b0000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000ba2', 'mobile_mechanic', 'S2', '+254700000902', 'Thika', 'SRID=4326;POINT(37.0800 -1.0300)', 5, 'approved');
insert into public.verification_checks (provider_id, kind, status) values
  ('b0000000-0000-0000-0000-0000000000a1', 'identity', 'passed'),
  ('b0000000-0000-0000-0000-0000000000a2', 'identity', 'passed');
insert into public.availability (provider_id, status, expires_at) values
  ('b0000000-0000-0000-0000-0000000000a1', 'available', now() + interval '1 hour'),
  ('b0000000-0000-0000-0000-0000000000a2', 'available', now() + interval '1 hour');
insert into public.memberships (provider_id, phone, role, user_id) values
  ('b0000000-0000-0000-0000-0000000000a1', '254700000901', 'owner', '00000000-0000-0000-0000-000000000ba1');
insert into public.parts_shops (id, name, business_phone, area, location) values
  ('b1000000-0000-0000-0000-000000000001', 'Thika Spares', '+254700000903', 'Thika', 'SRID=4326;POINT(37.0700 -1.0310)');
insert into public.memberships (shop_id, phone, role, user_id) values
  ('b1000000-0000-0000-0000-000000000001', '254700000903', 'owner', '00000000-0000-0000-0000-000000000bb1');
insert into public.parts_listings (id, shop_id, title, price_kes, stock_qty) values
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'Fan belt', 800, 10);

create function pg_temp.as_user(p uuid) returns void language sql as $$
  select set_config('test.uid', coalesce(p::text, ''), false);
$$;
create function pg_temp.check(ok boolean, what text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', what; end if;
end $$;
create function pg_temp.texts(p_to text) returns setof text language sql as $$
  select body from public.sms_outbox where to_phone = p_to order by id;
$$;

-- 1. A request reaches S1: S1 gets a text.
select pg_temp.as_user('00000000-0000-0000-0000-000000000bd1');
set role authenticated;
insert into public.service_requests (id, user_id, provider_id, mode, location, area)
values ('b3000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000bd1',
        'b0000000-0000-0000-0000-0000000000a1', 'come_to_me', 'SRID=4326;POINT(37.0700 -1.0300)', 'Thika');
-- The app cannot read the outbox.
do $$ begin
  begin
    perform 1 from public.sms_outbox;
    raise exception 'FAIL: app read the outbox';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
select pg_temp.check((select count(*) = 1 from pg_temp.texts('+254700000901') b
                       where b like 'New repair request near Thika%come to them%'),
                     'S1 not alerted');

-- 2. S1 passes: S2 gets a text, S1 gets nothing more.
select pg_temp.as_user('00000000-0000-0000-0000-000000000ba1');
set role authenticated;
select public.respond_to_request('b3000000-0000-0000-0000-000000000001', false);
reset role;
select pg_temp.check((select count(*) = 1 from pg_temp.texts('+254700000902')), 'S2 not alerted after the pass');
select pg_temp.check((select count(*) = 1 from pg_temp.texts('+254700000901')), 'S1 alerted twice');
-- Accepting sends nothing.
select pg_temp.as_user('00000000-0000-0000-0000-000000000ba2');
set role authenticated;
select public.respond_to_request('b3000000-0000-0000-0000-000000000001', true);
reset role;
select pg_temp.check((select count(*) = 1 from pg_temp.texts('+254700000902')), 'accepting sent a text');

-- 3. S1 orders parts: the shop gets one text, with the total.
select pg_temp.as_user('00000000-0000-0000-0000-000000000ba1');
set role authenticated;
create temp table ids (id uuid);
grant all on ids to authenticated;
insert into ids select public.place_parts_order('b0000000-0000-0000-0000-0000000000a1',
  '[{"listing_id": "b2000000-0000-0000-0000-000000000001", "qty": 3}]');
reset role;
select pg_temp.check((select count(*) = 1 from pg_temp.texts('+254700000903')), 'shop not alerted once');
select pg_temp.check((select bool_and(b = 'New parts order from S1: 3 parts, KES 2,400. Open the app to confirm it.')
                        from pg_temp.texts('+254700000903') b),
                     'shop text wrong: ' || (select string_agg(b, ' | ') from pg_temp.texts('+254700000903') b));

-- 4. The shop confirms and marks it ready: S1 gets two texts.
select pg_temp.as_user('00000000-0000-0000-0000-000000000bb1');
set role authenticated;
select public.update_parts_order((select id from ids), 'confirmed');
select public.update_parts_order((select id from ids), 'ready');
reset role;
select pg_temp.check((select count(*) = 3 from pg_temp.texts('+254700000901')), 'buyer not alerted twice');
select pg_temp.check((select count(*) = 1 from pg_temp.texts('+254700000901') b
                       where b like '%Thika Spares is ready to collect%'), 'no ready text');

-- 5. The buyer cancels a new order: no text to anyone about the cancel.
select pg_temp.as_user('00000000-0000-0000-0000-000000000ba1');
set role authenticated;
delete from ids;
insert into ids select public.place_parts_order('b0000000-0000-0000-0000-0000000000a1',
  '[{"listing_id": "b2000000-0000-0000-0000-000000000001", "qty": 1}]');
select public.update_parts_order((select id from ids), 'cancelled');
reset role;
select pg_temp.check((select count(*) = 3 from pg_temp.texts('+254700000901')), 'buyer texted about their own cancel');
select pg_temp.check((select count(*) = 2 from pg_temp.texts('+254700000903')), 'shop not alerted about the second order');

-- 6. The test page needs the key.
set role anon;
do $$ begin
  begin
    perform * from public.dev_latest_messages('wrong-key-wrong-key-wrong');
    raise exception 'FAIL: messages read without the key';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

\o
\echo 'sms alerts: all checks passed'
