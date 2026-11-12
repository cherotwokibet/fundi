-- my_open_request() (migration 20261112000000): an owner sees only their own
-- request, and sees when the mechanic accepts or passes.
-- Run with supabase/tests/run.sh.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

create function pg_temp.as_user(p uuid) returns void language sql as $$
  select set_config('test.uid', coalesce(p::text, ''), false);
$$;

-- This file's own people: mechanic A2 (approved), guest d2, guest e2.
insert into auth.users (id, phone, is_anonymous) values
  ('00000000-0000-0000-0000-0000000000a2', '+254700000201', false),
  ('00000000-0000-0000-0000-0000000000d2', null, true),
  ('00000000-0000-0000-0000-0000000000e2', null, true);
insert into public.providers (id, owner_user_id, type, display_name, business_phone, area, location, status, callout_fee_kes) values
  ('10000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a2', 'mobile_mechanic',
   'Test A', '+254700000201', 'Kasarani', 'SRID=4326;POINT(36.8980 -1.2210)', 'approved', 500);

-- Guest d2 sends a request to mechanic A.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
set role authenticated;
insert into public.service_requests (id, user_id, provider_id, mode, note)
values ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000d2',
        '10000000-0000-0000-0000-0000000000a2', 'come_to_me', 'It will not start');
do $$
declare r record;
begin
  select * into strict r from public.my_open_request();
  if r.status <> 'requested' or r.provider_name <> 'Test A' or r.provider_phone is null
     or not r.has_note or r.has_photo then
    raise exception 'FAIL: owner does not see their waiting request correctly: %', r;
  end if;
end $$;
reset role;

-- Another guest sees nothing.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
set role authenticated;
do $$ begin
  if exists (select 1 from public.my_open_request()) then
    raise exception 'FAIL: a guest sees someone else''s request';
  end if;
end $$;
reset role;

-- Mechanic A accepts; the owner sees it.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
set role authenticated;
select public.respond_to_request('30000000-0000-0000-0000-000000000001', true);
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
set role authenticated;
do $$
declare r record;
begin
  select * into strict r from public.my_open_request();
  if r.status <> 'accepted' or r.responded_at is null then
    raise exception 'FAIL: owner does not see the acceptance: %', r;
  end if;
end $$;

-- The owner cancels; nothing is open any more.
select public.cancel_my_request('30000000-0000-0000-0000-000000000001');
do $$ begin
  if exists (select 1 from public.my_open_request()) then
    raise exception 'FAIL: a cancelled request still shows as open';
  end if;
end $$;

-- A new request that the mechanic passes on: still open, but no mechanic.
insert into public.service_requests (id, user_id, provider_id, mode)
values ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000d2',
        '10000000-0000-0000-0000-0000000000a2', 'come_to_me');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
set role authenticated;
select public.respond_to_request('30000000-0000-0000-0000-000000000002', false);
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
set role authenticated;
do $$
declare r record;
begin
  select * into strict r from public.my_open_request();
  if r.provider_id is not null or r.provider_phone is not null then
    raise exception 'FAIL: a passed request still shows the mechanic: %', r;
  end if;
end $$;
reset role;

-- No session at all: not allowed.
set role anon;
do $$ begin
  begin
    perform public.my_open_request();
    raise exception 'FAIL: anon called my_open_request';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

\echo 'owner request status: all checks passed'
