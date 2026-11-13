-- Fundi — DEVELOPMENT ONLY: read the mock sign-in codes through a secret link,
-- so the app can be tested from any phone or computer.
--
-- Whoever has the key can read every recent code, and so can sign in as any
-- number, including an admin. Share the link only with testers you trust.
--
-- The key itself is never stored here or in the repository, only its
-- SHA-256 hash, in dev_settings. To set or change the key (SQL editor):
--   insert into public.dev_settings (name, value)
--   values ('codes_key_sha256', encode(sha256(convert_to('<your key>', 'utf8')), 'hex'))
--   on conflict (name) do update set value = excluded.value;
-- To switch the link off:
--   delete from public.dev_settings where name = 'codes_key_sha256';
-- BEFORE LAUNCH: switch it off, together with the mock SMS hook.

create table public.dev_settings (
  name text primary key,
  value text not null
);

-- Nobody reads or writes this through the app.
alter table public.dev_settings enable row level security;
revoke all on public.dev_settings from public, anon, authenticated;

-- Codes from the last 15 minutes, newest first. Refused without the key,
-- and refused for everyone while no key is set.
create or replace function public.dev_latest_codes(p_key text)
returns table (phone text, otp text, created_at timestamptz)
language plpgsql stable security definer set search_path = public
as $$
begin
  if p_key is null or length(p_key) < 20 or not exists (
       select 1 from public.dev_settings s
        where s.name = 'codes_key_sha256'
          and s.value = encode(sha256(convert_to(p_key, 'utf8')), 'hex')) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  return query
    select o.phone, o.otp, o.created_at
      from public.dev_sms_outbox o
     where o.created_at > now() - interval '15 minutes'
     order by o.created_at desc
     limit 10;
end;
$$;

-- Callable without signing in: the key is the lock.
revoke execute on function public.dev_latest_codes(text) from public;
grant execute on function public.dev_latest_codes(text) to anon, authenticated;
