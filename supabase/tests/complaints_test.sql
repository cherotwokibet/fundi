-- Complaints and refunds (migration 20261122000000). Run with supabase/tests/run.sh.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

insert into auth.users (id, phone, is_anonymous) values
  ('00000000-0000-0000-0000-0000000007a1', '254700000971', false), -- mechanic W1
  ('00000000-0000-0000-0000-0000000007a2', '254700000972', false), -- mechanic W2
  ('00000000-0000-0000-0000-0000000007d1', null, true),            -- owner 1
  ('00000000-0000-0000-0000-0000000007d2', null, true),            -- owner 2
  ('00000000-0000-0000-0000-0000000007f1', '254700000979', false); -- admin
insert into public.profiles (id, role) values ('00000000-0000-0000-0000-0000000007f1', 'admin');

-- Eldoret (35.27, 0.51): away from the other test files. W1 charges KES 500 to come out.
insert into public.providers (id, owner_user_id, type, display_name, business_phone, area, location, service_radius_km, callout_fee_kes, status) values
  ('e7000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000007a1', 'mobile_mechanic', 'W1', '+254700000971', 'Eldoret', 'SRID=4326;POINT(35.2700 0.5100)', 5, 500, 'approved'),
  ('e7000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000007a2', 'mobile_mechanic', 'W2', '+254700000972', 'Eldoret', 'SRID=4326;POINT(35.2800 0.5100)', 5, null, 'approved');

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
  insert into public.service_requests (id, user_id, provider_id, mode, location, area)
  values (id, owner, provider, 'come_to_me', 'SRID=4326;POINT(35.2700 0.5100)', 'Eldoret');
$$;

-- Owner 1 sends W1 a request; owner 2 sends W2 one.
select pg_temp.as_user('00000000-0000-0000-0000-0000000007d1');
set role authenticated;
select pg_temp.send('00000000-0000-0000-0000-0000000007d1', 'e7300000-0000-0000-0000-000000000001',
                    'e7000000-0000-0000-0000-0000000000a1');
-- 1. No complaint before a mechanic takes the job.
select pg_temp.refused($$ select public.raise_complaint('e7300000-0000-0000-0000-000000000001',
                          'They never came to fix the car') $$, 'complained before the job was taken');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000007d2');
set role authenticated;
select pg_temp.send('00000000-0000-0000-0000-0000000007d2', 'e7300000-0000-0000-0000-000000000002',
                    'e7000000-0000-0000-0000-0000000000a2');
reset role;

-- W1 takes it, quotes KES 2,000; owner 1 approves; W1 finishes the job.
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a1');
set role authenticated;
select public.respond_to_request('e7300000-0000-0000-0000-000000000001', true);
select public.send_quote('e7300000-0000-0000-0000-000000000001',
  '[{"kind": "labour", "description": "Replace brake pads", "qty": 1, "unit_price_kes": 1200},
    {"kind": "part", "description": "Brake pads", "qty": 1, "unit_price_kes": 800}]');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000007d1');
set role authenticated;
select public.respond_to_quote((select id from public.quotes
                                 where request_id = 'e7300000-0000-0000-0000-000000000001'), true);
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a1');
set role authenticated;
select public.mark_job_done('e7300000-0000-0000-0000-000000000001');
reset role;

-- 2. Someone else cannot complain about owner 1's job; a mechanic cannot either.
select pg_temp.as_user('00000000-0000-0000-0000-0000000007d2');
set role authenticated;
select pg_temp.refused($$ select public.raise_complaint('e7300000-0000-0000-0000-000000000001',
                          'Complaining about someone else') $$, 'another owner complained');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a1');
set role authenticated;
select pg_temp.refused($$ select public.raise_complaint('e7300000-0000-0000-0000-000000000001',
                          'The mechanic complaining') $$, 'the mechanic complained');
reset role;

-- 3. Owner 1 complains once, in their own words, and asks for a refund.
select pg_temp.as_user('00000000-0000-0000-0000-0000000007d1');
set role authenticated;
select pg_temp.check((select provider_name = 'W1' from public.my_last_job()), 'last job not found');
select pg_temp.refused($$ select public.raise_complaint('e7300000-0000-0000-0000-000000000001', 'bad') $$,
  'empty complaint accepted');
-- Money back needs an M-Pesa number to send it to.
select pg_temp.refused($$ select public.raise_complaint('e7300000-0000-0000-0000-000000000001',
                          'The brakes still squeal and the car pulls to the left', true) $$,
  'refund asked with no number');
select pg_temp.refused($$ select public.raise_complaint('e7300000-0000-0000-0000-000000000001',
                          'The brakes still squeal and the car pulls to the left', true, '12345') $$,
  'refund asked with a bad number');
select public.raise_complaint('e7300000-0000-0000-0000-000000000001',
  'The brakes still squeal and the car pulls to the left', true, '0712 345 678');
-- The owner cannot read the number back either: only admins can.
select pg_temp.refused($$ select refund_phone from public.complaints $$, 'owner read the refund number');
select pg_temp.refused($$ select public.raise_complaint('e7300000-0000-0000-0000-000000000001',
                          'Second complaint about the same job') $$, 'complained twice');
-- No direct writes.
select pg_temp.refused($$ insert into public.complaints (request_id, provider_id, user_id, message)
                          values ('e7300000-0000-0000-0000-000000000002', 'e7000000-0000-0000-0000-0000000000a2',
                                  '00000000-0000-0000-0000-0000000007d1', 'Written directly to the table') $$,
  'complaint written directly');
select pg_temp.refused($$ update public.complaints set status = 'upheld', refund_kes = 2500, refund_status = 'due' $$,
  'owner decided their own complaint');
select pg_temp.refused($$ delete from public.complaints $$, 'owner deleted their complaint');
-- The owner cannot decide it either.
select pg_temp.refused($$ select public.admin_resolve_complaint(
                          (select id from public.complaints), true, 'Upheld by me', 100) $$,
  'owner used the admin function');
select pg_temp.check((select count(*) = 1 from public.complaints), 'owner cannot see their complaint');
reset role;
-- The mechanic got a text.
select pg_temp.check((select count(*) = 1 from public.sms_outbox
                       where kind = 'complaint' and to_phone = '+254700000971'), 'mechanic not texted');

-- 4. Only W1 can reply, and only once. W2 cannot see it.
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a2');
set role authenticated;
select pg_temp.check((select count(*) = 0 from public.complaints), 'other mechanic sees the complaint');
select pg_temp.refused($$ select public.reply_to_complaint((select id from public.complaints
                          where request_id = 'e7300000-0000-0000-0000-000000000001'), 'Not my job') $$,
  'other mechanic replied');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a1');
set role authenticated;
select pg_temp.check((select count(*) = 1 from public.complaints), 'mechanic cannot see the complaint');
select pg_temp.refused($$ select refund_phone from public.complaints $$, 'mechanic read the owner''s number');
select public.reply_to_complaint((select id from public.complaints),
  'I can come back tomorrow and adjust the calipers for free');
select pg_temp.refused($$ select public.reply_to_complaint((select id from public.complaints), 'Again') $$,
  'mechanic replied twice');
select pg_temp.refused($$ select public.admin_complaints() $$, 'mechanic read the admin list');
reset role;

-- 5. The admin decides. Refund only when upheld, capped at the job cost
--    (KES 2,000 approved quote + KES 500 call-out = KES 2,500).
select pg_temp.as_user('00000000-0000-0000-0000-0000000007f1');
set role authenticated;
select pg_temp.check((select job_cost_kes = 2500 and wants_refund and provider_reply is not null
                             and refund_phone = '254712345678'
                        from public.admin_complaints()
                       where request_id = 'e7300000-0000-0000-0000-000000000001'), 'admin list wrong');
select pg_temp.refused($$ select public.admin_resolve_complaint((select id from public.complaints), false,
                          'Not upheld', 500) $$, 'refund on a rejected complaint');
select pg_temp.refused($$ select public.admin_resolve_complaint((select id from public.complaints), true,
                          'Upheld', 2501) $$, 'refund above the job cost');
select pg_temp.refused($$ select public.admin_resolve_complaint((select id from public.complaints), true,
                          '', 100) $$, 'decided without a note');
select pg_temp.refused($$ select public.admin_mark_refund_paid((select id from public.complaints), 'QX12AB34') $$,
  'refund paid before it was due');
select public.admin_resolve_complaint((select id from public.complaints), true,
  'The pads were fitted badly. W1 refunds the parts and labour.', 2000);
select pg_temp.refused($$ select public.admin_resolve_complaint((select id from public.complaints), false,
                          'Changed my mind') $$, 'decided twice');
reset role;
-- Money stays held while the refund is due.
select pg_temp.check(public.job_payout_on_hold('e7300000-0000-0000-0000-000000000001'), 'payout not held');

-- 6. The owner sees the outcome. The admin marks the refund paid.
select pg_temp.as_user('00000000-0000-0000-0000-0000000007d1');
set role authenticated;
select pg_temp.check((select status = 'upheld' and refund_kes = 2000 and refund_status = 'due'
                        and admin_note is not null from public.complaints), 'owner cannot see the outcome');
select pg_temp.refused($$ select public.admin_mark_refund_paid((select id from public.complaints), 'QX12AB34') $$,
  'owner marked the refund paid');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000007f1');
set role authenticated;
select public.admin_mark_refund_paid((select id from public.complaints), 'qx12ab34');
select pg_temp.refused($$ select public.admin_mark_refund_paid((select id from public.complaints), 'QX12AB34') $$,
  'refund paid twice');
reset role;
select pg_temp.check((select refund_status = 'paid' and refund_reference = 'QX12AB34' from public.complaints),
  'refund not marked paid');
select pg_temp.check(not public.job_payout_on_hold('e7300000-0000-0000-0000-000000000001'),
  'payout still held after the refund');
-- The owner was texted the decision and the payment on their refund number.
select pg_temp.check((select count(*) = 2 from public.sms_outbox
                       where kind = 'complaint' and to_phone = '+254712345678'), 'owner not texted');

-- 7. While a job is under way the owner can complain; the payout is held while open.
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a2');
set role authenticated;
select public.respond_to_request('e7300000-0000-0000-0000-000000000002', true);
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-0000000007d2');
set role authenticated;
select public.raise_complaint('e7300000-0000-0000-0000-000000000002', 'They asked for cash before starting');
reset role;
select pg_temp.check(public.job_payout_on_hold('e7300000-0000-0000-0000-000000000002'), 'open complaint not held');
-- Rejected with no refund: nothing held, nothing due.
select pg_temp.as_user('00000000-0000-0000-0000-0000000007f1');
set role authenticated;
select public.admin_resolve_complaint((select id from public.complaints
                                        where request_id = 'e7300000-0000-0000-0000-000000000002'),
  false, 'Asking for a deposit on parts is allowed. Call us if you were overcharged.');
reset role;
select pg_temp.check((select status = 'rejected' and refund_status = 'none' from public.complaints
                       where request_id = 'e7300000-0000-0000-0000-000000000002'), 'rejection not saved');
select pg_temp.check(not public.job_payout_on_hold('e7300000-0000-0000-0000-000000000002'), 'rejected still held');

-- 8. Too late after 14 days.
select pg_temp.as_user('00000000-0000-0000-0000-0000000007d2');
set role authenticated;
select pg_temp.send('00000000-0000-0000-0000-0000000007d2', 'e7300000-0000-0000-0000-000000000003',
                    'e7000000-0000-0000-0000-0000000000a2');
reset role;
update public.service_requests set status = 'done', done_at = now() - interval '15 days'
 where id = 'e7300000-0000-0000-0000-000000000003';
select pg_temp.as_user('00000000-0000-0000-0000-0000000007d2');
set role authenticated;
select pg_temp.refused($$ select public.raise_complaint('e7300000-0000-0000-0000-000000000003',
                          'Complaining far too late about this') $$, 'complained after 14 days');
reset role;

\o
\echo 'complaints and refunds: all checks passed'
