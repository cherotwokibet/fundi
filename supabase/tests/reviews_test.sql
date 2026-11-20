-- Job done and reviews (migration 20261121010000). Run with supabase/tests/run.sh.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

insert into auth.users (id, phone, is_anonymous) values
  ('00000000-0000-0000-0000-000000000da1', '254700000961', false), -- mechanic V1
  ('00000000-0000-0000-0000-000000000da2', '254700000962', false), -- mechanic V2
  ('00000000-0000-0000-0000-000000000dd1', null, true),            -- owner 1
  ('00000000-0000-0000-0000-000000000dd2', null, true);            -- owner 2

-- Nakuru (36.07, -0.30): away from the other test files.
insert into public.providers (id, owner_user_id, type, display_name, business_phone, area, location, service_radius_km, status) values
  ('d0000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000da1', 'mobile_mechanic', 'V1', '+254700000961', 'Nakuru', 'SRID=4326;POINT(36.0700 -0.3000)', 5, 'approved'),
  ('d0000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000da2', 'mobile_mechanic', 'V2', '+254700000962', 'Nakuru', 'SRID=4326;POINT(36.0800 -0.3000)', 5, 'approved');

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
create function pg_temp.send(owner uuid, id uuid) returns void language sql as $$
  insert into public.service_requests (id, user_id, provider_id, mode, location, area)
  values (id, owner, 'd0000000-0000-0000-0000-0000000000a1', 'come_to_me', 'SRID=4326;POINT(36.0700 -0.3000)', 'Nakuru');
$$;

-- Two owners send V1 a request each.
select pg_temp.as_user('00000000-0000-0000-0000-000000000dd1');
set role authenticated;
select pg_temp.send('00000000-0000-0000-0000-000000000dd1', 'd3000000-0000-0000-0000-000000000001');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-000000000dd2');
set role authenticated;
select pg_temp.send('00000000-0000-0000-0000-000000000dd2', 'd3000000-0000-0000-0000-000000000002');
reset role;

-- 1. Nothing can be marked done or rated before V1 takes it.
select pg_temp.as_user('00000000-0000-0000-0000-000000000da1');
set role authenticated;
select pg_temp.refused($$ select public.mark_job_done('d3000000-0000-0000-0000-000000000001') $$,
  'marked done before it was accepted');
select public.respond_to_request('d3000000-0000-0000-0000-000000000001', true);
select public.respond_to_request('d3000000-0000-0000-0000-000000000002', true);
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-000000000dd1');
set role authenticated;
select pg_temp.refused($$ select public.leave_review('d3000000-0000-0000-0000-000000000001', 5) $$,
  'rated before the job was done');
select pg_temp.check((select count(*) = 0 from public.my_review_due()), 'review asked for too early');
reset role;

-- 2. Another mechanic cannot finish V1's job; V1 can.
select pg_temp.as_user('00000000-0000-0000-0000-000000000da2');
set role authenticated;
select pg_temp.refused($$ select public.mark_job_done('d3000000-0000-0000-0000-000000000001') $$,
  'another mechanic marked the job done');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-000000000da1');
set role authenticated;
select public.mark_job_done('d3000000-0000-0000-0000-000000000001');
reset role;

-- 3. Owner 1 is asked, rates once, and cannot rate twice.
select pg_temp.as_user('00000000-0000-0000-0000-000000000dd1');
set role authenticated;
select pg_temp.check((select provider_name = 'V1' from public.my_review_due()), 'owner not asked to rate');
select pg_temp.refused($$ select public.leave_review('d3000000-0000-0000-0000-000000000001', 6) $$, '6 stars accepted');
select public.leave_review('d3000000-0000-0000-0000-000000000001', 4, 'Came quickly, fixed the brakes');
select pg_temp.refused($$ select public.leave_review('d3000000-0000-0000-0000-000000000001', 1) $$, 'rated twice');
select pg_temp.check((select count(*) = 0 from public.my_review_due()), 'still asked after rating');
-- No direct writes to reviews or ratings.
select pg_temp.refused($$ insert into public.reviews (request_id, provider_id, user_id, stars)
                          values ('d3000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-0000000000a1',
                                  '00000000-0000-0000-0000-000000000dd1', 5) $$, 'review written directly');
do $$
declare n int;
begin
  with u as (update public.providers set rating_avg = 5, rating_count = 100 returning 1)
  select count(*) into n from u;
  perform pg_temp.check(n = 0, 'owner changed a rating');
end $$;
reset role;

-- 4. Owner 2 cannot rate owner 1's job; finishes their own and rates it.
select pg_temp.as_user('00000000-0000-0000-0000-000000000dd2');
set role authenticated;
select pg_temp.refused($$ select public.leave_review('d3000000-0000-0000-0000-000000000001', 1) $$,
  'rated someone else''s job');
select pg_temp.check((select count(*) = 0 from public.reviews), 'owner 2 sees owner 1''s review');
select public.mark_job_done('d3000000-0000-0000-0000-000000000002');
select public.leave_review('d3000000-0000-0000-0000-000000000002', 5);
reset role;

-- 5. The listing's rating comes only from these reviews.
select pg_temp.check((select rating_avg = 4.5 and rating_count = 2 from public.providers
                       where id = 'd0000000-0000-0000-0000-0000000000a1'), 'rating not worked out');
-- V1 can read their reviews; V2 cannot.
select pg_temp.as_user('00000000-0000-0000-0000-000000000da1');
set role authenticated;
select pg_temp.check((select count(*) = 2 from public.reviews), 'mechanic cannot read their reviews');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-000000000da2');
set role authenticated;
select pg_temp.check((select count(*) = 0 from public.reviews), 'other mechanic read the reviews');
reset role;

-- 6. Too late to rate after 14 days.
select pg_temp.as_user('00000000-0000-0000-0000-000000000dd2');
set role authenticated;
insert into public.service_requests (id, user_id, provider_id, mode, location, area)
values ('d3000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000dd2',
        'd0000000-0000-0000-0000-0000000000a2', 'come_to_me', 'SRID=4326;POINT(36.0700 -0.3000)', 'Nakuru');
reset role;
update public.service_requests set status = 'done', done_at = now() - interval '15 days'
 where id = 'd3000000-0000-0000-0000-000000000003';
select pg_temp.as_user('00000000-0000-0000-0000-000000000dd2');
set role authenticated;
select pg_temp.refused($$ select public.leave_review('d3000000-0000-0000-0000-000000000003', 5) $$,
  'rated after 14 days');
reset role;

\o
\echo 'job done and reviews: all checks passed'
