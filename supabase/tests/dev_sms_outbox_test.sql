-- The mock SMS hook (migration 20261111030000): only the auth service can
-- call it or see the codes. Run with supabase/tests/run.sh.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

-- The auth service stores the code.
set role supabase_auth_admin;
select public.mock_send_sms('{"user": {"phone": "254712345678"}, "sms": {"otp": "123456"}}');
do $$ begin
  if (select otp from public.dev_sms_outbox where phone = '254712345678') <> '123456' then
    raise exception 'FAIL: code not stored';
  end if;
end $$;
reset role;

-- Signed-in users and guests can neither read the codes nor call the hook.
set role authenticated;
do $$ begin
  begin
    perform 1 from public.dev_sms_outbox;
    raise exception 'FAIL: a signed-in user can read sign-in codes';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.mock_send_sms('{}');
    raise exception 'FAIL: a signed-in user can call the SMS hook';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set role anon;
do $$ begin
  begin
    perform 1 from public.dev_sms_outbox;
    raise exception 'FAIL: a guest can read sign-in codes';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

\echo 'dev sms outbox: all checks passed'
