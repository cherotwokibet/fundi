-- Fundi — the owner's view of their own request: "My repair" and the
-- waiting screen. Read-only. Only the person who sent a request can see it.

-- The latest request this person sent in the last 24 hours that is still
-- waiting or was accepted, with the mechanic it went to. If the mechanic
-- passed on it, the provider columns are null.
create or replace function public.my_open_request()
returns table (
  id uuid,
  mode public.request_mode,
  status public.request_status,
  created_at timestamptz,
  responded_at timestamptz,
  has_note boolean,
  has_photo boolean,
  has_voice boolean,
  provider_id uuid,
  provider_name text,
  provider_phone text,
  provider_type public.provider_type,
  callout_fee_kes integer
)
language sql stable security definer set search_path = public
as $$
  select r.id, r.mode, r.status, r.created_at, r.responded_at,
         r.note is not null, r.photo_path is not null, r.voice_path is not null,
         p.id, p.display_name, p.business_phone, p.type, p.callout_fee_kes
    from public.service_requests r
    left join public.providers p on p.id = r.provider_id and p.status = 'approved'
   where r.user_id = auth.uid()
     and r.status in ('requested', 'accepted')
     and r.created_at > now() - interval '24 hours'
   order by r.created_at desc
   limit 1;
$$;

revoke execute on function public.my_open_request() from public, anon;
grant execute on function public.my_open_request() to authenticated;
