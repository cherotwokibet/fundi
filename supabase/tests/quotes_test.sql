-- Itemised quotes (migration 20261121000000). Run with supabase/tests/run.sh.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

insert into auth.users (id, phone, is_anonymous) values
  ('00000000-0000-0000-0000-000000000ca1', '254700000951', false), -- mechanic Q1, has the job
  ('00000000-0000-0000-0000-000000000ca2', '254700000952', false), -- mechanic Q2, does not
  ('00000000-0000-0000-0000-000000000cd1', null, true),            -- guest owner
  ('00000000-0000-0000-0000-000000000cd2', null, true);            -- another guest

-- Nyeri (36.95, -0.42): away from the other test files.
insert into public.providers (id, owner_user_id, type, display_name, business_phone, area, location, service_radius_km, status) values
  ('c0000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000ca1', 'mobile_mechanic', 'Q1', '+254700000951', 'Nyeri', 'SRID=4326;POINT(36.9500 -0.4200)', 5, 'approved'),
  ('c0000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000ca2', 'mobile_mechanic', 'Q2', '+254700000952', 'Nyeri', 'SRID=4326;POINT(36.9600 -0.4200)', 5, 'approved');

create function pg_temp.as_user(p uuid) returns void language sql as $$
  select set_config('test.uid', coalesce(p::text, ''), false);
$$;
create function pg_temp.check(ok boolean, what text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', what; end if;
end $$;
create function pg_temp.refused(stmt text, what text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    return;
  end;
  raise exception 'FAIL: %', what;
end $$;

create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated;

-- The owner's request goes to Q1.
select pg_temp.as_user('00000000-0000-0000-0000-000000000cd1');
set role authenticated;
insert into public.service_requests (id, user_id, provider_id, mode, location, area)
values ('c3000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000cd1',
        'c0000000-0000-0000-0000-0000000000a1', 'come_to_me', 'SRID=4326;POINT(36.9500 -0.4200)', 'Nyeri');
reset role;

-- 1. No quote before the mechanic takes the job.
select pg_temp.as_user('00000000-0000-0000-0000-000000000ca1');
set role authenticated;
select pg_temp.refused($$
  select public.send_quote('c3000000-0000-0000-0000-000000000001',
    '[{"kind": "labour", "description": "Look at the car", "qty": 1, "unit_price_kes": 500}]') $$,
  'quoted before taking the job');
select public.respond_to_request('c3000000-0000-0000-0000-000000000001', true);

-- 2. Q1 quotes. Bad lines are refused.
select pg_temp.refused($$ select public.send_quote('c3000000-0000-0000-0000-000000000001', '[]') $$,
  'empty quote accepted');
select pg_temp.refused($$
  select public.send_quote('c3000000-0000-0000-0000-000000000001',
    '[{"kind": "labour", "description": "x", "qty": 1, "unit_price_kes": 500}]') $$,
  'one-letter description accepted');
select pg_temp.refused($$
  select public.send_quote('c3000000-0000-0000-0000-000000000001',
    '[{"kind": "labour", "description": "Fix it", "qty": 1, "unit_price_kes": -5}]') $$,
  'negative price accepted');
insert into ids select 'q1', public.send_quote('c3000000-0000-0000-0000-000000000001',
  '[{"kind": "labour", "description": "Replace front brake pads", "qty": 1, "unit_price_kes": 1500},
    {"kind": "part", "description": "Front brake pads", "qty": 2, "unit_price_kes": 1700}]',
  'Pads are worn to the metal');
select pg_temp.check((select total_kes = 4900 and status = 'sent' from public.quotes
                       where id = (select id from ids where name = 'q1')), 'total wrong');
-- No direct writes.
select pg_temp.refused($$ update public.quotes set total_kes = 1 $$, 'quote edited directly');
select pg_temp.refused($$ insert into public.quote_lines (quote_id, position, kind, description, qty, unit_price_kes)
                          values ((select id from ids where name = 'q1'), 9, 'other', 'Extra', 1, 99999) $$,
  'line added directly');
reset role;

-- 3. Q2 cannot quote or see it.
select pg_temp.as_user('00000000-0000-0000-0000-000000000ca2');
set role authenticated;
select pg_temp.refused($$
  select public.send_quote('c3000000-0000-0000-0000-000000000001',
    '[{"kind": "labour", "description": "Cheaper job", "qty": 1, "unit_price_kes": 100}]') $$,
  'another mechanic quoted');
select pg_temp.check((select count(*) = 0 from public.quotes), 'another mechanic saw the quote');
reset role;

-- 4. Another guest cannot see or answer it.
select pg_temp.as_user('00000000-0000-0000-0000-000000000cd2');
set role authenticated;
select pg_temp.check((select count(*) = 0 from public.quotes), 'another guest saw the quote');
select pg_temp.check((select count(*) = 0 from public.quote_lines), 'another guest saw the lines');
select pg_temp.refused($$ select public.respond_to_quote((select id from ids where name = 'q1'), true) $$,
  'another guest approved the quote');
reset role;

-- 5. A revised quote replaces the waiting one.
select pg_temp.as_user('00000000-0000-0000-0000-000000000ca1');
set role authenticated;
insert into ids select 'q2', public.send_quote('c3000000-0000-0000-0000-000000000001',
  '[{"kind": "labour", "description": "Replace front brake pads", "qty": 1, "unit_price_kes": 1200},
    {"kind": "part", "description": "Front brake pads", "qty": 2, "unit_price_kes": 1700}]');
reset role;
select pg_temp.check((select status = 'withdrawn' from public.quotes where id = (select id from ids where name = 'q1')),
                     'old quote not withdrawn');

-- 6. The owner sees the latest quote with its lines, and approves it.
select pg_temp.as_user('00000000-0000-0000-0000-000000000cd1');
set role authenticated;
select pg_temp.check((select count(*) = 2 from public.quotes), 'owner does not see the quotes');
select pg_temp.check((select count(*) = 2 from public.quote_lines
                       where quote_id = (select id from ids where name = 'q2')), 'owner does not see the lines');
select pg_temp.refused($$ select public.respond_to_quote((select id from ids where name = 'q1'), true) $$,
  'owner approved a replaced quote');
select public.respond_to_quote((select id from ids where name = 'q2'), true);
select pg_temp.refused($$ select public.respond_to_quote((select id from ids where name = 'q2'), false) $$,
  'owner answered twice');
reset role;
select pg_temp.check((select status = 'approved' and responded_at is not null from public.quotes
                       where id = (select id from ids where name = 'q2')), 'not approved');
select pg_temp.check((select count(*) = 1 from public.sms_outbox
                       where to_phone = '+254700000951' and body like 'The owner approved your quote of KES 4,600%'),
                     'mechanic not texted');

-- 7. Extra work after approval is a new quote for the owner to answer.
select pg_temp.as_user('00000000-0000-0000-0000-000000000ca1');
set role authenticated;
insert into ids select 'q3', public.send_quote('c3000000-0000-0000-0000-000000000001',
  '[{"kind": "other", "description": "Brake fluid top-up", "qty": 1, "unit_price_kes": 600}]');
reset role;
select pg_temp.check((select status = 'approved' from public.quotes where id = (select id from ids where name = 'q2')),
                     'approved quote was withdrawn');
select pg_temp.as_user('00000000-0000-0000-0000-000000000cd1');
set role authenticated;
select public.respond_to_quote((select id from ids where name = 'q3'), false);
reset role;
select pg_temp.check((select count(*) = 1 from public.sms_outbox
                       where to_phone = '+254700000951' and body like 'The owner declined your quote of KES 600%'),
                     'decline not texted');

\o
\echo 'quotes: all checks passed'
