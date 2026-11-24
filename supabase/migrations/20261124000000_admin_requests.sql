-- Fundi — live requests for the admin console.
--
-- One read for the admin's "Live requests" table: every request still open,
-- plus the ones from the last few days, with where each one stands in plain
-- stages, who has it, the latest price and any complaint.
-- Rules (here, not in the app):
--   * admins only; anyone else gets an error, not an empty list;
--   * nothing is changed by reading it.
--
-- Stages:
--   cancelled       the owner cancelled
--   done            the job is marked done
--   unassigned      no mechanic has it (nobody fitted, or re-sent 3 times)
--   no_answer       a mechanic has it but has not answered in 5 minutes
--   waiting         a mechanic has it, under 5 minutes
--   taken           taken, no price sent yet
--   price_sent      a price is waiting for the owner
--   price_declined  the owner declined the last price
--   working         the owner approved the price

create or replace function public.admin_requests(p_days integer default 7)
returns table (
  id uuid,
  created_at timestamptz,
  area text,
  note text,
  car_make text,
  mode public.request_mode,
  stage text,
  provider_id uuid,
  provider_name text,
  provider_phone text,
  owner_phone text,
  handoff text,
  rematch_count integer,
  waiting_since timestamptz,
  done_at timestamptz,
  quote_total_kes integer,
  has_photo boolean,
  has_voice boolean,
  complaint_status public.complaint_status,
  refund_status public.refund_status
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  return query
  select r.id, r.created_at, r.area, r.note, r.car_make, r.mode,
         case
           when r.status = 'cancelled' then 'cancelled'
           when r.status = 'done' or r.done_at is not null then 'done'
           when r.provider_id is null then 'unassigned'
           when r.status = 'requested'
                and coalesce(r.assigned_at, r.created_at) <= now() - interval '5 minutes'
             then 'no_answer'
           when r.status = 'requested' then 'waiting'
           when q.status = 'sent' then 'price_sent'
           when q.status = 'approved' then 'working'
           when q.status = 'declined' then 'price_declined'
           else 'taken'
         end,
         r.provider_id, p.display_name, p.business_phone, r.contact_phone,
         r.handoff, r.rematch_count,
         coalesce(r.assigned_at, r.created_at), r.done_at,
         q.total_kes,
         r.photo_path is not null, r.voice_path is not null,
         c.status, c.refund_status
    from public.service_requests r
    left join public.providers p on p.id = r.provider_id
    left join lateral (
      select q1.status, q1.total_kes
        from public.quotes q1
       where q1.request_id = r.id and q1.status <> 'withdrawn'
       order by q1.created_at desc
       limit 1) q on true
    left join public.complaints c on c.request_id = r.id
   where r.status not in ('done', 'cancelled')
      or r.created_at > now() - make_interval(days => greatest(coalesce(p_days, 7), 1))
   order by r.created_at desc
   limit 500;
end;
$$;
revoke execute on function public.admin_requests(integer) from public, anon;
grant execute on function public.admin_requests(integer) to authenticated;
