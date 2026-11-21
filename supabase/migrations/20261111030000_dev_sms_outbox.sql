-- Fundi — DEVELOPMENT ONLY: a mock SMS provider for phone sign-in.
--
-- Supabase's "Send SMS" auth hook calls mock_send_sms() instead of a real SMS
-- provider. The code is stored in dev_sms_outbox and never sent. Read the
-- latest code in the SQL editor:
--   select phone, otp, created_at from public.dev_sms_outbox order by created_at desc limit 5;
--
-- Turn it on in the dashboard: Authentication → Auth Hooks → Add hook →
-- Send SMS → Postgres → schema public, function mock_send_sms.
-- BEFORE LAUNCH: switch the hook off and connect a real SMS provider.
-- While it is on, no real person can receive a sign-in code.

create table public.dev_sms_outbox (
  id bigint generated always as identity primary key,
  phone text not null,
  otp text not null,
  created_at timestamptz not null default now()
);

-- Nobody reads or writes this through the app. RLS on with no policies, and
-- no grants to app roles. Only the auth service writes it.
alter table public.dev_sms_outbox enable row level security;
revoke all on public.dev_sms_outbox from public, anon, authenticated;

create or replace function public.mock_send_sms(event jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
begin
  -- Keep only the last day of codes.
  delete from public.dev_sms_outbox where created_at < now() - interval '1 day';
  insert into public.dev_sms_outbox (phone, otp)
  values (event->'user'->>'phone', event->'sms'->>'otp');
  return '{}'::jsonb;
end;
$$;

revoke execute on function public.mock_send_sms(jsonb) from public, anon, authenticated;
grant execute on function public.mock_send_sms(jsonb) to supabase_auth_admin;
grant select, insert, delete on public.dev_sms_outbox to supabase_auth_admin;

-- The auth service is not subject to RLS on this table.
create policy dev_sms_outbox_auth_service on public.dev_sms_outbox
  for all to supabase_auth_admin using (true) with check (true);
