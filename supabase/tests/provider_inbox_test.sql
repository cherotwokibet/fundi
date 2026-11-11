-- Access rules for the mechanic inbox (migration 20261111020000).
-- Run with supabase/tests/run.sh. Any failed check stops the run with an error.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

-- People. Fixed ids keep the checks readable.
insert into auth.users (id, phone, is_anonymous) values
  ('00000000-0000-0000-0000-0000000000a1', '+254700000101', false), -- mechanic A (approved)
  ('00000000-0000-0000-0000-0000000000b1', '+254700000102', false), -- mechanic B (approved)
  ('00000000-0000-0000-0000-0000000000c1', '+254700000103', false), -- mechanic C (pending)
  ('00000000-0000-0000-0000-0000000000d1', null, true),             -- guest owner
  ('00000000-0000-0000-0000-0000000000e1', null, true),             -- another guest
  ('00000000-0000-0000-0000-0000000000f1', '+254700000000', false); -- admin
insert into public.profiles (id, role) values ('00000000-0000-0000-0000-0000000000f1', 'admin');

insert into public.providers (id, owner_user_id, type, display_name, business_phone, area, location, status) values
  ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1', 'mobile_mechanic', 'Test A', '+254700000101', 'Kasarani', 'SRID=4326;POINT(36.8980 -1.2210)', 'approved'),
  ('10000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b1', 'mobile_mechanic', 'Test B', '+254700000102', 'Roysambu', 'SRID=4326;POINT(36.8890 -1.2180)', 'approved'),
  ('10000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000c1', 'mobile_mechanic', 'Test C', '+254700000103', 'Kasarani', 'SRID=4326;POINT(36.8980 -1.2210)', 'pending');

insert into storage.objects (bucket_id, name) values
  ('requests', '00000000-0000-0000-0000-0000000000d1/1/photo'),
  ('requests', '00000000-0000-0000-0000-0000000000d1/1/voice');

create function pg_temp.as_user(p uuid) returns void language sql as $$
  select set_config('test.uid', coalesce(p::text, ''), false);
$$;

-- 1. The guest sends a request with a photo and voice note to mechanic A.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
set role authenticated;
insert into public.service_requests (id, user_id, provider_id, mode, location, area, note, photo_path, voice_path)
values ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000d1',
        '10000000-0000-0000-0000-0000000000a1', 'come_to_me', 'SRID=4326;POINT(36.9000 -1.2200)',
        'Kasarani', 'Car will not start', '00000000-0000-0000-0000-0000000000d1/1/photo',
        '00000000-0000-0000-0000-0000000000d1/1/voice');

do $$ begin
  begin
    insert into public.service_requests (user_id, provider_id, mode)
    values ('00000000-0000-0000-0000-0000000000d1', '10000000-0000-0000-0000-0000000000c1', 'come_to_me');
    raise exception 'FAIL: a request went to a pending provider';
  exception when raise_exception then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

-- 2. The owner cannot move their request to another provider any more.
do $$
declare n int;
begin
  with u as (
    update public.service_requests set provider_id = '10000000-0000-0000-0000-0000000000b1'
     where id = '20000000-0000-0000-0000-000000000001' returning 1)
  select count(*) into n from u;
  if n <> 0 then raise exception 'FAIL: owner changed provider_id directly'; end if;
end $$;
reset role;

-- 3. Mechanic A sees it, with distance, and can open its files.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
set role authenticated;
do $$
declare r record;
begin
  select * into strict r from public.my_requests();
  if r.note <> 'Car will not start' or r.voice_path is null or r.distance_km is null then
    raise exception 'FAIL: inbox row incomplete: %', r;
  end if;
  if (select count(*) from storage.objects where bucket_id = 'requests') <> 2 then
    raise exception 'FAIL: assigned mechanic cannot open the photo and voice note';
  end if;
end $$;
reset role;

-- 4. Mechanic B and pending mechanic C see nothing and cannot answer it.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
set role authenticated;
do $$ begin
  if exists (select 1 from public.my_requests()) then raise exception 'FAIL: B sees A''s request'; end if;
  if exists (select 1 from storage.objects where bucket_id = 'requests') then
    raise exception 'FAIL: B can open A''s request files';
  end if;
  begin
    perform public.respond_to_request('20000000-0000-0000-0000-000000000001', true);
    raise exception 'FAIL: B accepted A''s request';
  exception when raise_exception then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
set role authenticated;
do $$ begin
  if exists (select 1 from public.my_requests()) then raise exception 'FAIL: pending C sees requests'; end if;
end $$;
reset role;

-- 5. A passes on it: it leaves A's inbox, A loses the files, and it cannot be
--    sent back to A.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
set role authenticated;
select public.respond_to_request('20000000-0000-0000-0000-000000000001', false);
do $$ begin
  if exists (select 1 from public.my_requests()) then raise exception 'FAIL: declined request still in inbox'; end if;
  if exists (select 1 from storage.objects where bucket_id = 'requests') then
    raise exception 'FAIL: A still opens files after passing';
  end if;
end $$;
reset role;

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
set role authenticated;
do $$ begin
  begin
    update public.service_requests set provider_id = '10000000-0000-0000-0000-0000000000a1'
     where id = '20000000-0000-0000-0000-000000000001';
    raise exception 'FAIL: request re-sent to a provider who passed';
  exception when raise_exception then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  -- Re-sending to someone else (B) is allowed.
  update public.service_requests set provider_id = '10000000-0000-0000-0000-0000000000b1'
   where id = '20000000-0000-0000-0000-000000000001';
end $$;
reset role;

-- 6. A takes a new request; it cannot be taken twice.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
set role authenticated;
insert into public.service_requests (id, user_id, provider_id, mode)
values ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000d1',
        '10000000-0000-0000-0000-0000000000a1', 'visit_garage');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
set role authenticated;
select public.respond_to_request('20000000-0000-0000-0000-000000000002', true);
do $$ begin
  if (select status from public.my_requests() where id = '20000000-0000-0000-0000-000000000002') <> 'accepted' then
    raise exception 'FAIL: accepted request not shown as accepted';
  end if;
  -- Having one request does not open the files of another.
  if exists (select 1 from storage.objects where bucket_id = 'requests') then
    raise exception 'FAIL: A opens files of a request that is not theirs';
  end if;
  begin
    perform public.respond_to_request('20000000-0000-0000-0000-000000000002', false);
    raise exception 'FAIL: answered the same request twice';
  exception when raise_exception then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;
reset role;

-- 7. Only the sender can cancel; a cancelled request leaves the inbox.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
set role authenticated;
do $$ begin
  begin
    perform public.cancel_my_request('20000000-0000-0000-0000-000000000002');
    raise exception 'FAIL: a stranger cancelled the request';
  exception when raise_exception then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
set role authenticated;
select public.cancel_my_request('20000000-0000-0000-0000-000000000002');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
set role authenticated;
do $$ begin
  if exists (select 1 from public.my_requests()) then raise exception 'FAIL: cancelled request still in inbox'; end if;
end $$;
reset role;

-- 8. Guests without a session cannot read any inbox.
set role anon;
do $$ begin
  begin
    perform public.my_requests();
    raise exception 'FAIL: anon called my_requests';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

\echo 'provider inbox: all checks passed'
