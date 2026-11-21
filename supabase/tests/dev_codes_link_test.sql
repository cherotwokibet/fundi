-- dev_latest_codes() (migration 20261113000000): codes are readable only with
-- the secret key. Run with supabase/tests/run.sh.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

insert into public.dev_sms_outbox (phone, otp, created_at) values
  ('254711000001', '111111', now() - interval '1 minute'),
  ('254711000002', '222222', now() - interval '40 minutes');

-- No key set yet: nobody gets in, whatever they send.
set role anon;
do $$ begin
  begin
    perform * from public.dev_latest_codes('any-long-key-that-is-not-set-000');
    raise exception 'FAIL: codes readable while no key is set';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

insert into public.dev_settings (name, value)
values ('codes_key_sha256', encode(sha256(convert_to('test-key-0123456789-abcdefghij', 'utf8')), 'hex'));

set role anon;
do $$
declare n int;
begin
  -- Wrong, short and missing keys are refused.
  begin
    perform * from public.dev_latest_codes('wrong-key-0123456789-abcdefghij');
    raise exception 'FAIL: wrong key accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from public.dev_latest_codes('short');
    raise exception 'FAIL: short key accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from public.dev_latest_codes(null);
    raise exception 'FAIL: null key accepted';
  exception when insufficient_privilege then null;
  end;

  -- The right key shows recent codes only.
  select count(*) into n from public.dev_latest_codes('test-key-0123456789-abcdefghij')
   where otp = '111111';
  if n <> 1 then raise exception 'FAIL: recent code not shown'; end if;
  select count(*) into n from public.dev_latest_codes('test-key-0123456789-abcdefghij')
   where otp = '222222';
  if n <> 0 then raise exception 'FAIL: a 40-minute-old code is shown'; end if;

  -- The key hash and the codes table stay unreadable directly.
  begin
    perform 1 from public.dev_settings;
    raise exception 'FAIL: anon can read dev_settings';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Switching it off works.
delete from public.dev_settings where name = 'codes_key_sha256';
set role anon;
do $$ begin
  begin
    perform * from public.dev_latest_codes('test-key-0123456789-abcdefghij');
    raise exception 'FAIL: codes readable after the key was removed';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
delete from public.dev_sms_outbox where phone like '2547110000%';

\echo 'dev codes link: all checks passed'
