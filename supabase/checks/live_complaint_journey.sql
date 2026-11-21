-- The whole complaint and refund journey, run against the LIVE database.
-- Everything happens in one block that always ends with an exception, so it is
-- rolled back and leaves nothing behind (no users, jobs, complaints or texts).
-- Success shows as: ERROR: E2E PASSED (rolled back): owner sent request -> ...
-- Any other error names the step that failed.
-- Run it in the Supabase SQL editor, or through the Supabase MCP execute_sql.
-- Last run on the live project: 21 Nov 2026, passed.
do $e2e$
declare
  m1 uuid := 'e2e00000-0000-4000-8000-0000000000a1';
  m2 uuid := 'e2e00000-0000-4000-8000-0000000000a2';
  o1 uuid := 'e2e00000-0000-4000-8000-0000000000d1';
  ad uuid := 'e2e00000-0000-4000-8000-0000000000f1';
  p1 uuid := 'e2e00000-0000-4000-8000-0000000001a1';
  p2 uuid := 'e2e00000-0000-4000-8000-0000000001a2';
  r1 uuid := 'e2e00000-0000-4000-8000-000000000301';
  cid uuid;
  steps text[] := '{}';
begin
  execute $f$create function pg_temp.as_user(p uuid) returns void language sql as $b$
    select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  $b$$f$;
  execute $f$create function pg_temp.chk(ok boolean, what text) returns void language plpgsql as $b$
  begin if ok is not true then raise exception 'FAIL: %', what; end if; end $b$$f$;
  execute $f$create function pg_temp.refused(stmt text, what text) returns void language plpgsql as $b$
  begin
    begin execute stmt; exception when others then return; end;
    raise exception 'FAIL (was allowed): %', what;
  end $b$$f$;

  insert into auth.users (id, phone, is_anonymous) values
    (m1, '254700990971', false), (m2, '254700990972', false), (o1, null, true), (ad, '254700990979', false);
  insert into public.profiles (id, role) values (ad, 'admin') on conflict (id) do update set role = 'admin';
  insert into public.providers (id, owner_user_id, type, display_name, business_phone, area, location, service_radius_km, callout_fee_kes, status) values
    (p1, m1, 'mobile_mechanic', 'E2E W1', '+254700990971', 'Eldoret', 'SRID=4326;POINT(35.2700 0.5100)', 5, 500, 'approved'),
    (p2, m2, 'mobile_mechanic', 'E2E W2', '+254700990972', 'Eldoret', 'SRID=4326;POINT(35.2800 0.5100)', 5, null, 'approved');

  -- Owner sends the request.
  perform pg_temp.as_user(o1); set local role authenticated;
  insert into public.service_requests (id, user_id, provider_id, mode, location, area)
    values (r1, o1, p1, 'come_to_me', 'SRID=4326;POINT(35.2700 0.5100)', 'Eldoret');
  perform pg_temp.refused($s$ select public.raise_complaint('e2e00000-0000-4000-8000-000000000301', 'They never came to fix the car') $s$, 'complaint before job taken');
  reset role; steps := steps || 'owner sent request'::text;

  -- Mechanic takes it and quotes KES 2,000.
  perform pg_temp.as_user(m1); set local role authenticated;
  perform public.respond_to_request(r1, true);
  perform public.send_quote(r1, '[{"kind": "labour", "description": "Replace brake pads", "qty": 1, "unit_price_kes": 1200}, {"kind": "part", "description": "Brake pads", "qty": 1, "unit_price_kes": 800}]');
  reset role; steps := steps || 'mechanic took it and quoted'::text;

  -- Owner approves; mechanic marks it done.
  perform pg_temp.as_user(o1); set local role authenticated;
  perform public.respond_to_quote((select id from public.quotes where request_id = r1), true);
  reset role;
  perform pg_temp.as_user(m1); set local role authenticated;
  perform public.mark_job_done(r1);
  reset role; steps := steps || 'owner approved, job done'::text;

  -- Owner complains and asks for money back.
  perform pg_temp.as_user(o1); set local role authenticated;
  perform pg_temp.chk((select provider_name = 'E2E W1' from public.my_last_job()), 'home screen last job');
  perform public.raise_complaint(r1, 'The brakes still squeal and the car pulls to the left', true, '0712 345 678');
  perform pg_temp.refused($s$ select refund_phone from public.complaints $s$, 'owner read refund number');
  perform pg_temp.refused($s$ select public.raise_complaint('e2e00000-0000-4000-8000-000000000301', 'Second complaint about the same job') $s$, 'second complaint');
  perform pg_temp.refused($s$ update public.complaints set status = 'upheld' $s$, 'owner edited complaint');
  perform pg_temp.chk((select count(*) = 1 from public.complaints), 'owner sees own complaint');
  reset role;
  perform pg_temp.chk((select count(*) = 1 from public.sms_outbox where kind = 'complaint' and to_phone = '+254700990971'), 'mechanic texted');
  perform pg_temp.chk(public.job_payout_on_hold(r1), 'payout held while open');
  steps := steps || 'owner complained, mechanic texted, payout held'::text;

  -- Another mechanic cannot see it; the right one replies once.
  perform pg_temp.as_user(m2); set local role authenticated;
  perform pg_temp.chk((select count(*) = 0 from public.complaints), 'other mechanic sees nothing');
  reset role;
  perform pg_temp.as_user(m1); set local role authenticated;
  perform pg_temp.refused($s$ select refund_phone from public.complaints $s$, 'mechanic read refund number');
  select id into cid from public.complaints where request_id = r1;
  perform public.reply_to_complaint(cid, 'I can come back tomorrow and adjust the calipers for free');
  perform pg_temp.refused(format($s$ select public.reply_to_complaint(%L, 'Again') $s$, cid), 'second reply');
  perform pg_temp.refused($s$ select public.admin_complaints() $s$, 'mechanic read admin list');
  reset role; steps := steps || 'mechanic replied once'::text;

  -- Admin decides: refund capped at job cost (2,000 + 500 call-out).
  perform pg_temp.as_user(ad); set local role authenticated;
  perform pg_temp.chk((select job_cost_kes = 2500 and wants_refund and provider_reply is not null and refund_phone = '254712345678'
                         from public.admin_complaints() where request_id = r1), 'admin list');
  perform pg_temp.refused(format($s$ select public.admin_resolve_complaint(%L, true, 'Upheld', 2501) $s$, cid), 'refund above cost');
  perform pg_temp.refused(format($s$ select public.admin_mark_refund_paid(%L, 'QX12AB34') $s$, cid), 'paid before due');
  perform public.admin_resolve_complaint(cid, true, 'The pads were fitted badly. W1 refunds the parts and labour.', 2000);
  reset role;
  perform pg_temp.chk(public.job_payout_on_hold(r1), 'payout held while refund due');
  steps := steps || 'admin upheld with KES 2,000 refund'::text;

  -- Owner sees the outcome; admin records the M-Pesa code.
  perform pg_temp.as_user(o1); set local role authenticated;
  perform pg_temp.chk((select status = 'upheld' and refund_kes = 2000 and refund_status = 'due' from public.complaints), 'owner sees outcome');
  reset role;
  perform pg_temp.as_user(ad); set local role authenticated;
  perform public.admin_mark_refund_paid(cid, 'qx12ab34');
  perform pg_temp.refused(format($s$ select public.admin_mark_refund_paid(%L, 'QX12AB34') $s$, cid), 'paid twice');
  reset role;
  perform pg_temp.chk((select refund_status = 'paid' and refund_reference = 'QX12AB34' from public.complaints where id = cid), 'marked paid');
  perform pg_temp.chk(not public.job_payout_on_hold(r1), 'payout released after refund');
  perform pg_temp.chk((select count(*) = 2 from public.sms_outbox where kind = 'complaint' and to_phone = '+254712345678'), 'owner texted twice');
  steps := steps || 'refund marked paid, owner texted, payout released'::text;

  raise exception 'E2E PASSED (rolled back): %', array_to_string(steps, ' -> ');
end
$e2e$;
