-- Request limits and re-sending a request nobody answered
-- (migration 20261120020000). Run with supabase/tests/run.sh.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

insert into auth.users (id, phone, is_anonymous) values
  ('00000000-0000-0000-0000-0000000008a1', '254700000801', false), -- mechanic N1, nearest
  ('00000000-0000-0000-0000-0000000008a2', '254700000802', false), -- mechanic N2
  ('00000000-0000-0000-0000-0000000008d1', null, true),            -- guest owner
  ('00000000-0000-0000-0000-0000000008d2', null, true),            -- second guest
  ('00000000-0000-0000-0000-0000000008d3', null, true);            -- many guests below

-- Somewhere with nobody else from the other test files: Karen (36.70, -1.32).
insert into public.providers (id, owner_user_id, type, display_name, business_phone, area, location, service_radius_km, status) values
  ('80000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000008a1', 'mobile_mechanic', 'N1', '+254700000801', 'Karen', 'SRID=4326;POINT(36.7010 -1.3200)', 5, 'approved'),
  ('80000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000008a2', 'mobile_mechanic', 'N2', '+254700000802', 'Karen', 'SRID=4326;POINT(36.7100 -1.3200)', 5, 'approved');
insert into public.verification_checks (provider_id, kind, status) values
  ('80000000-0000-0000-0000-0000000000a1', 'identity', 'passed'),
  ('80000000-0000-0000-0000-0000000000a2', 'identity', 'passed');
insert into public.availability (provider_id, status, expires_at) values
  ('80000000-0000-0000-0000-0000000000a1', 'available', now() + interval '1 hour'),
  ('80000000-0000-0000-0000-0000000000a2', 'available', now() + interval '1 hour');

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
    if sqlerrm like 'LIMIT:%' then return; end if;
    raise exception 'FAIL: % (wrong error: %)', what, sqlerrm;
  end;
  raise exception 'FAIL: %', what;
end $$;
create function pg_temp.send(owner uuid, id uuid, provider uuid) returns void language sql as $$
  insert into public.service_requests (id, user_id, provider_id, mode, location, area)
  values (id, owner, provider, 'come_to_me', 'SRID=4326;POINT(36.7000 -1.3200)', 'Karen');
$$;

-- 1. A guest can have two requests open, not three.
select pg_temp.as_user('00000000-0000-0000-0000-0000000008d1');
set role authenticated;
select pg_temp.send('00000000-0000-0000-0000-0000000008d1', '90000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-0000000000a1');
select pg_temp.send('00000000-0000-0000-0000-0000000008d1', '90000000-0000-0000-0000-000000000002', null);
select pg_temp.refused($$ select pg_temp.send('00000000-0000-0000-0000-0000000008d1', gen_random_uuid(), null) $$,
  'a third open request was accepted');
-- Cancelling one frees a place.
select public.cancel_my_request('90000000-0000-0000-0000-000000000002');
select pg_temp.send('00000000-0000-0000-0000-0000000008d1', '90000000-0000-0000-0000-000000000003', null);
select public.cancel_my_request('90000000-0000-0000-0000-000000000003');
-- 6 in 24 hours, cancelled ones included.
select pg_temp.send('00000000-0000-0000-0000-0000000008d1', '90000000-0000-0000-0000-000000000004', null);
select public.cancel_my_request('90000000-0000-0000-0000-000000000004');
select pg_temp.send('00000000-0000-0000-0000-0000000008d1', '90000000-0000-0000-0000-000000000005', null);
select public.cancel_my_request('90000000-0000-0000-0000-000000000005');
select pg_temp.send('00000000-0000-0000-0000-0000000008d1', '90000000-0000-0000-0000-000000000006', null);
select public.cancel_my_request('90000000-0000-0000-0000-000000000006');
select pg_temp.refused($$ select pg_temp.send('00000000-0000-0000-0000-0000000008d1', gen_random_uuid(), null) $$,
  'a seventh request in a day was accepted');
-- An owner cannot fake the hand-off reason.
reset role;

-- 2. No answer for 5 minutes: the request moves to N2.
select pg_temp.as_user('00000000-0000-0000-0000-0000000008d2');
set role authenticated;
select pg_temp.send('00000000-0000-0000-0000-0000000008d2', '90000000-0000-0000-0000-000000000010', '80000000-0000-0000-0000-0000000000a1');
-- Too early: nothing happens.
select pg_temp.check(not public.nudge_my_request('90000000-0000-0000-0000-000000000010'), 'moved before 5 minutes');
reset role;
update public.service_requests set assigned_at = now() - interval '6 minutes'
 where id = '90000000-0000-0000-0000-000000000010';
-- Another owner cannot move it.
select pg_temp.as_user('00000000-0000-0000-0000-0000000008d1');
set role authenticated;
do $$ begin
  begin
    perform public.nudge_my_request('90000000-0000-0000-0000-000000000010');
    raise exception 'FAIL: another owner moved the request';
  exception when raise_exception then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000008d2');
set role authenticated;
select pg_temp.check(public.nudge_my_request('90000000-0000-0000-0000-000000000010'), 'not moved after 5 minutes');
do $$
declare r record;
begin
  select * into strict r from public.my_open_request();
  perform pg_temp.check(r.provider_name = 'N2' and r.handoff = 'no_answer' and r.rematch_count = 1,
                        'owner view after no answer: ' || r::text);
end $$;
reset role;
-- N1 lost it; N2 has it.
select pg_temp.as_user('00000000-0000-0000-0000-0000000008a1');
set role authenticated;
select pg_temp.check((select count(*) = 0 from public.my_requests()
                       where id = '90000000-0000-0000-0000-000000000010'), 'N1 still sees it');
reset role;

-- 3. Nobody else free: it stays with N2, and N1 is not barred by the try.
update public.service_requests set assigned_at = now() - interval '6 minutes'
 where id = '90000000-0000-0000-0000-000000000010';
select pg_temp.as_user('00000000-0000-0000-0000-0000000008d2');
set role authenticated;
select pg_temp.check(not public.nudge_my_request('90000000-0000-0000-0000-000000000010'), 'moved with nobody to take it');
reset role;
select pg_temp.check((select provider_id = '80000000-0000-0000-0000-0000000000a2'
                          and not ('80000000-0000-0000-0000-0000000000a2' = any (declined_provider_ids))
                        from public.service_requests where id = '90000000-0000-0000-0000-000000000010'),
                     'failed nudge changed the request');

-- 4. A pass records why the next mechanic has it.
select pg_temp.as_user('00000000-0000-0000-0000-0000000008d2');
set role authenticated;
select pg_temp.send('00000000-0000-0000-0000-0000000008d2', '90000000-0000-0000-0000-000000000011', '80000000-0000-0000-0000-0000000000a2');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000008a2');
set role authenticated;
select public.respond_to_request('90000000-0000-0000-0000-000000000011', false);
reset role;
select pg_temp.check((select provider_id = '80000000-0000-0000-0000-0000000000a1' and handoff = 'passed'
                        from public.service_requests where id = '90000000-0000-0000-0000-000000000011'),
                     'pass not recorded as passed');

-- 5. A mechanic with 5 waiting requests gets no more; re-matching skips them.
do $$
declare i int;
begin
  for i in 1..3 loop
    perform pg_temp.as_user(('00000000-0000-0000-0000-0000000009' || lpad(i::text, 2, '0'))::uuid);
    insert into auth.users (id, is_anonymous)
    values (('00000000-0000-0000-0000-0000000009' || lpad(i::text, 2, '0'))::uuid, true);
    set local role authenticated;
    perform pg_temp.send(('00000000-0000-0000-0000-0000000009' || lpad(i::text, 2, '0'))::uuid,
                         gen_random_uuid(), '80000000-0000-0000-0000-0000000000a1');
    reset role;
  end loop;
end $$;
-- N1 now has 5 waiting: 3 above, the pass in step 4, and the first request.
select pg_temp.check((select count(*) = 5 from public.service_requests
                       where provider_id = '80000000-0000-0000-0000-0000000000a1' and status = 'requested'),
                     'setup: N1 should have 5 waiting');
select pg_temp.as_user('00000000-0000-0000-0000-0000000008d3');
set role authenticated;
select pg_temp.refused($$ select pg_temp.send('00000000-0000-0000-0000-0000000008d3', gen_random_uuid(),
                                             '80000000-0000-0000-0000-0000000000a1') $$,
  'a sixth waiting request went to N1');
select pg_temp.send('00000000-0000-0000-0000-0000000008d3', '90000000-0000-0000-0000-000000000020', '80000000-0000-0000-0000-0000000000a2');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000008a2');
set role authenticated;
select public.respond_to_request('90000000-0000-0000-0000-000000000020', false);
reset role;
select pg_temp.check((select provider_id is null from public.service_requests
                       where id = '90000000-0000-0000-0000-000000000020'),
                     're-matched to a mechanic who already has 5 waiting');

\o
\echo 'request limits and no answer: all checks passed'
