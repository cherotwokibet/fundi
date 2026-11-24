-- Live requests for the admin console (migration 20261124000000). Run with supabase/tests/run.sh.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

insert into auth.users (id, phone, is_anonymous) values
  ('00000000-0000-0000-0000-000000001ba1', '254700000981', false), -- mechanic K1
  ('00000000-0000-0000-0000-000000001bd1', null, true),            -- owner 1
  ('00000000-0000-0000-0000-000000001bd2', null, true),            -- owner 2
  ('00000000-0000-0000-0000-000000001bd3', null, true),            -- owner 3
  ('00000000-0000-0000-0000-000000001bf1', '254700000989', false); -- admin
insert into public.profiles (id, role) values ('00000000-0000-0000-0000-000000001bf1', 'admin');

-- Kisumu (34.76, -0.09): away from the other test files.
insert into public.providers (id, owner_user_id, type, display_name, business_phone, area, location, service_radius_km, status) values
  ('eb000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000001ba1', 'mobile_mechanic', 'K1', '+254700000981', 'Kisumu', 'SRID=4326;POINT(34.7600 -0.0900)', 5, 'approved');

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
create function pg_temp.send(owner uuid, id uuid, provider uuid) returns void language sql as $$
  insert into public.service_requests (id, user_id, provider_id, mode, location, area, note)
  values (id, owner, provider, 'come_to_me', 'SRID=4326;POINT(34.7600 -0.0900)', 'Kisumu', 'Car will not start');
$$;
create function pg_temp.stage(id uuid) returns text language sql as $$
  select stage from public.admin_requests() where admin_requests.id = $1;
$$;

-- Owner 1: two requests to K1. Owner 2: one with nobody. Owner 3: one to K1.
select pg_temp.as_user('00000000-0000-0000-0000-000000001bd1');
set role authenticated;
select pg_temp.send('00000000-0000-0000-0000-000000001bd1', 'eb300000-0000-0000-0000-000000000001',
                    'eb000000-0000-0000-0000-0000000000a1');
select pg_temp.send('00000000-0000-0000-0000-000000001bd1', 'eb300000-0000-0000-0000-000000000002',
                    'eb000000-0000-0000-0000-0000000000a1');
-- 1. Owners cannot read the admin list.
select pg_temp.refused($$ select * from public.admin_requests() $$, 'owner read the admin list');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-000000001bd2');
set role authenticated;
select pg_temp.send('00000000-0000-0000-0000-000000001bd2', 'eb300000-0000-0000-0000-000000000003', null);
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-000000001bd3');
set role authenticated;
select pg_temp.send('00000000-0000-0000-0000-000000001bd3', 'eb300000-0000-0000-0000-000000000004',
                    'eb000000-0000-0000-0000-0000000000a1');
reset role;

-- 2. Mechanics cannot read it either, and nobody signed out can.
select pg_temp.as_user('00000000-0000-0000-0000-000000001ba1');
set role authenticated;
select pg_temp.refused($$ select * from public.admin_requests() $$, 'mechanic read the admin list');
-- K1 takes request 1 and sends a price; takes request 4, prices it, the owner approves.
select public.respond_to_request('eb300000-0000-0000-0000-000000000001', true);
select public.send_quote('eb300000-0000-0000-0000-000000000001',
  '[{"kind": "labour", "description": "Starter motor", "qty": 1, "unit_price_kes": 3000}]');
select public.respond_to_request('eb300000-0000-0000-0000-000000000004', true);
select public.send_quote('eb300000-0000-0000-0000-000000000004',
  '[{"kind": "labour", "description": "New battery fitted", "qty": 1, "unit_price_kes": 1500}]');
reset role;
set role anon;
select pg_temp.as_user(null);
select pg_temp.refused($$ select * from public.admin_requests() $$, 'signed-out read the admin list');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-000000001bd3');
set role authenticated;
select public.respond_to_quote((select id from public.quotes
                                 where request_id = 'eb300000-0000-0000-0000-000000000004'), true);
reset role;
-- Request 2 has been with K1 for 6 minutes with no answer.
update public.service_requests set assigned_at = now() - interval '6 minutes'
 where id = 'eb300000-0000-0000-0000-000000000002';

-- 3. The admin sees each one at the right stage, with the mechanic and the price.
select pg_temp.as_user('00000000-0000-0000-0000-000000001bf1');
set role authenticated;
select pg_temp.check(pg_temp.stage('eb300000-0000-0000-0000-000000000001') = 'price_sent', 'price sent stage');
select pg_temp.check(pg_temp.stage('eb300000-0000-0000-0000-000000000002') = 'no_answer', 'no answer stage');
select pg_temp.check(pg_temp.stage('eb300000-0000-0000-0000-000000000003') = 'unassigned', 'nobody stage');
select pg_temp.check(pg_temp.stage('eb300000-0000-0000-0000-000000000004') = 'working', 'working stage');
select pg_temp.check((select provider_name = 'K1' and quote_total_kes = 3000 and note = 'Car will not start'
                        from public.admin_requests() where id = 'eb300000-0000-0000-0000-000000000001'),
  'mechanic, price or note missing');
reset role;

-- 4. Done, cancelled and waiting.
select pg_temp.as_user('00000000-0000-0000-0000-000000001ba1');
set role authenticated;
select public.mark_job_done('eb300000-0000-0000-0000-000000000004');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-000000001bd1');
set role authenticated;
select public.cancel_my_request('eb300000-0000-0000-0000-000000000002');
reset role;
update public.service_requests set assigned_at = now()
 where id = 'eb300000-0000-0000-0000-000000000001';
select pg_temp.as_user('00000000-0000-0000-0000-000000001bf1');
set role authenticated;
select pg_temp.check(pg_temp.stage('eb300000-0000-0000-0000-000000000004') = 'done', 'done stage');
select pg_temp.check(pg_temp.stage('eb300000-0000-0000-0000-000000000002') = 'cancelled', 'cancelled stage');
reset role;

-- 5. Old finished requests drop off; old open ones stay.
update public.service_requests set created_at = now() - interval '30 days'
 where id in ('eb300000-0000-0000-0000-000000000004', 'eb300000-0000-0000-0000-000000000003');
select pg_temp.as_user('00000000-0000-0000-0000-000000001bf1');
set role authenticated;
select pg_temp.check(pg_temp.stage('eb300000-0000-0000-0000-000000000004') is null, 'old done job still listed');
select pg_temp.check(pg_temp.stage('eb300000-0000-0000-0000-000000000003') = 'unassigned', 'old open request dropped');
select pg_temp.check((select count(*) = 1 from public.admin_requests(60)
                       where id = 'eb300000-0000-0000-0000-000000000004'), 'longer window misses the old job');
-- 6. Reading changes nothing.
select pg_temp.check((select status = 'cancelled' from public.service_requests
                       where id = 'eb300000-0000-0000-0000-000000000002'), 'read changed a request');
reset role;

\o
\echo 'admin live requests: all checks passed'
