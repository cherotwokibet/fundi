-- Re-matching when a mechanic passes (migration 20261120000000).
-- Run with supabase/tests/run.sh.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

insert into auth.users (id, phone, is_anonymous) values
  ('00000000-0000-0000-0000-0000000005a1', '254700000501', false), -- mechanic 1, nearest
  ('00000000-0000-0000-0000-0000000005a2', '254700000502', false), -- mechanic 2, a bit further
  ('00000000-0000-0000-0000-0000000005a3', '254700000503', false), -- mechanic 3, busy
  ('00000000-0000-0000-0000-0000000005a4', '254700000504', false), -- mechanic 4, no identity check
  ('00000000-0000-0000-0000-0000000005a5', '254700000505', false), -- mechanic 5, too far for their radius
  ('00000000-0000-0000-0000-0000000005a6', '254700000506', false), -- mechanic 6, status not refreshed
  ('00000000-0000-0000-0000-0000000005b1', '254700000507', false), -- garage
  ('00000000-0000-0000-0000-0000000005d1', null, true);            -- guest owner

-- The owner is at Kasarani (36.9000, -1.2200).
insert into public.providers (id, owner_user_id, type, display_name, business_phone, area, location, service_radius_km, status) values
  ('50000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000005a1', 'mobile_mechanic', 'R1', '+254700000501', 'Kasarani', 'SRID=4326;POINT(36.9010 -1.2200)', 5, 'approved'),
  ('50000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000005a2', 'mobile_mechanic', 'R2', '+254700000502', 'Kasarani', 'SRID=4326;POINT(36.9100 -1.2200)', 5, 'approved'),
  ('50000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000005a3', 'mobile_mechanic', 'R3', '+254700000503', 'Kasarani', 'SRID=4326;POINT(36.9005 -1.2200)', 5, 'approved'),
  ('50000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000005a4', 'mobile_mechanic', 'R4', '+254700000504', 'Kasarani', 'SRID=4326;POINT(36.9002 -1.2200)', 5, 'approved'),
  ('50000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000005a5', 'mobile_mechanic', 'R5', '+254700000505', 'Ruiru', 'SRID=4326;POINT(36.9600 -1.1500)', 3, 'approved'),
  ('50000000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-0000000005a6', 'mobile_mechanic', 'R6', '+254700000506', 'Kasarani', 'SRID=4326;POINT(36.9003 -1.2200)', 5, 'approved'),
  ('50000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000005b1', 'garage', 'RG', '+254700000507', 'Kasarani', 'SRID=4326;POINT(36.9001 -1.2200)', 0, 'approved');

insert into public.verification_checks (provider_id, kind, status)
select id, 'identity', 'passed' from public.providers
 where id in ('50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-0000000000a2',
              '50000000-0000-0000-0000-0000000000a3', '50000000-0000-0000-0000-0000000000a5',
              '50000000-0000-0000-0000-0000000000a6', '50000000-0000-0000-0000-0000000000b1');

insert into public.availability (provider_id, status, expires_at) values
  ('50000000-0000-0000-0000-0000000000a1', 'available', now() + interval '1 hour'),
  ('50000000-0000-0000-0000-0000000000a2', 'available', now() + interval '1 hour'),
  ('50000000-0000-0000-0000-0000000000a3', 'busy', now() + interval '1 hour'),
  ('50000000-0000-0000-0000-0000000000a4', 'available', now() + interval '1 hour'),
  ('50000000-0000-0000-0000-0000000000a5', 'available', now() + interval '1 hour'),
  -- "Available" set more than 4 hours ago: still offered, but after fresh ones.
  ('50000000-0000-0000-0000-0000000000a6', 'available', now() - interval '1 hour'),
  ('50000000-0000-0000-0000-0000000000b1', 'available', now() + interval '1 hour');

create function pg_temp.as_user(p uuid) returns void language sql as $$
  select set_config('test.uid', coalesce(p::text, ''), false);
$$;
create function pg_temp.check(ok boolean, what text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', what; end if;
end $$;
create function pg_temp.holder() returns uuid language sql as $$
  select provider_id from public.service_requests where id = '60000000-0000-0000-0000-000000000001';
$$;
create function pg_temp.pass(who uuid) returns void language plpgsql as $$
begin
  perform pg_temp.as_user(who);
  set role authenticated;
  perform public.respond_to_request('60000000-0000-0000-0000-000000000001', false);
  reset role;
end $$;

-- The owner sends a "come to me" request to R1. They cannot fake the counters.
select pg_temp.as_user('00000000-0000-0000-0000-0000000005d1');
set role authenticated;
insert into public.service_requests (id, user_id, provider_id, mode, location, area, rematch_count, assigned_at)
values ('60000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000005d1',
        '50000000-0000-0000-0000-0000000000a1', 'come_to_me', 'SRID=4326;POINT(36.9000 -1.2200)',
        'Kasarani', 3, now() - interval '1 day');
do $$
declare r record;
begin
  select * into strict r from public.my_open_request();
  perform pg_temp.check(r.rematch_count = 0 and r.assigned_at > now() - interval '1 minute',
                        'owner set the re-send counters');
  perform pg_temp.check(r.provider_name = 'R1', 'request not with R1');
end $$;
reset role;

-- R1 passes. Busy R3, unchecked R4, out-of-range R5 and the garage are
-- skipped; fresh R2 comes before R6, whose status was not refreshed.
select pg_temp.pass('00000000-0000-0000-0000-0000000005a1');
select pg_temp.check(pg_temp.holder() = '50000000-0000-0000-0000-0000000000a2', 'not re-sent to R2');

-- The owner sees who has it now and that it was re-sent.
select pg_temp.as_user('00000000-0000-0000-0000-0000000005d1');
set role authenticated;
do $$
declare r record;
begin
  select * into strict r from public.my_open_request();
  perform pg_temp.check(r.provider_name = 'R2' and r.rematch_count = 1 and r.responded_at is null,
                        'owner view after re-send wrong: ' || r::text);
end $$;
reset role;

-- R1 no longer sees the request; R2 does.
select pg_temp.as_user('00000000-0000-0000-0000-0000000005a1');
set role authenticated;
select pg_temp.check((select count(*) = 0 from public.my_requests()), 'R1 still sees the request');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000005a2');
set role authenticated;
select pg_temp.check((select count(*) = 1 from public.my_requests()), 'R2 does not see the request');
reset role;

-- R2 passes: R6 (not refreshed) is the only one left.
select pg_temp.pass('00000000-0000-0000-0000-0000000005a2');
select pg_temp.check(pg_temp.holder() = '50000000-0000-0000-0000-0000000000a6', 'not re-sent to R6');

-- R6 passes: nobody fits, the request waits with no mechanic.
select pg_temp.pass('00000000-0000-0000-0000-0000000005a6');
select pg_temp.check(pg_temp.holder() is null, 'sent to someone who should not get it');
select pg_temp.check((select rematch_count = 2 from public.service_requests
                       where id = '60000000-0000-0000-0000-000000000001'), 'wrong re-send count');

-- A garage request goes to a garage only, and stops after 3 re-sends.
insert into auth.users (id, phone, is_anonymous)
select ('00000000-0000-0000-0000-0000000006' || lpad(g::text, 2, '0'))::uuid, '2547000006' || lpad(g::text, 2, '0'), false
  from generate_series(1, 5) g;
insert into public.providers (id, owner_user_id, type, display_name, business_phone, area, location, service_radius_km, status)
select ('70000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
       ('00000000-0000-0000-0000-0000000006' || lpad(g::text, 2, '0'))::uuid,
       'garage', 'G' || g, '+2547000006' || lpad(g::text, 2, '0'), 'Kasarani',
       ('SRID=4326;POINT(' || (36.9000 + g * 0.001) || ' -1.2200)')::extensions.geography, 0, 'approved'
  from generate_series(1, 5) g;
insert into public.verification_checks (provider_id, kind, status)
select ('70000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid, 'identity', 'passed'
  from generate_series(1, 5) g;
insert into public.availability (provider_id, status, expires_at)
select ('70000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid, 'available', now() + interval '1 hour'
  from generate_series(1, 5) g;

select pg_temp.as_user('00000000-0000-0000-0000-0000000005d1');
set role authenticated;
insert into public.service_requests (id, user_id, provider_id, mode, location, area)
values ('60000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000005d1',
        '50000000-0000-0000-0000-0000000000b1', 'visit_garage', 'SRID=4326;POINT(36.9000 -1.2200)', 'Kasarani');
reset role;

create function pg_temp.garage_holder() returns uuid language sql as $$
  select provider_id from public.service_requests where id = '60000000-0000-0000-0000-000000000002';
$$;
do $$
declare
  who uuid;
  i int;
begin
  for i in 1..4 loop
    who := (select owner_user_id from public.providers where id = pg_temp.garage_holder());
    perform pg_temp.check(who is not null, 'garage request lost its garage too early, step ' || i);
    perform pg_temp.check((select type = 'garage' from public.providers where id = pg_temp.garage_holder()),
                          'garage request went to a mobile mechanic');
    perform pg_temp.as_user(who);
    set local role authenticated;
    perform public.respond_to_request('60000000-0000-0000-0000-000000000002', false);
    reset role;
  end loop;
end $$;
-- RG + three re-sends = four garages tried; the fifth is never asked.
select pg_temp.check(pg_temp.garage_holder() is null, 'more than 3 re-sends');
select pg_temp.check((select rematch_count = 3 and cardinality(declined_provider_ids) = 4
                        from public.service_requests where id = '60000000-0000-0000-0000-000000000002'),
                     'garage re-send count wrong');

-- Accepting still works on a re-sent request.
select pg_temp.as_user('00000000-0000-0000-0000-0000000005d1');
set role authenticated;
-- (An owner can have two requests open; the first one is done with.)
select public.cancel_my_request('60000000-0000-0000-0000-000000000001');
insert into public.service_requests (id, user_id, provider_id, mode, location, area)
values ('60000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000005d1',
        '70000000-0000-0000-0000-000000000005', 'visit_garage', 'SRID=4326;POINT(36.9000 -1.2200)', 'Kasarani');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-000000000605');
set role authenticated;
select public.respond_to_request('60000000-0000-0000-0000-000000000003', false);
reset role;
select pg_temp.check((select provider_id = '50000000-0000-0000-0000-0000000000b1'
                        from public.service_requests where id = '60000000-0000-0000-0000-000000000003'),
                     'not re-sent to the nearest free garage');
select pg_temp.as_user('00000000-0000-0000-0000-0000000005b1');
set role authenticated;
select public.respond_to_request('60000000-0000-0000-0000-000000000003', true);
reset role;
select pg_temp.check((select status = 'accepted' from public.service_requests
                       where id = '60000000-0000-0000-0000-000000000003'), 're-sent request not accepted');

-- Nobody can call the matcher directly.
set role authenticated;
do $$ begin
  begin
    perform public.next_best_provider('60000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: matcher callable';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

\o
\echo 're-match on pass: all checks passed'
