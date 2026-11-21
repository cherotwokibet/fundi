-- Fundi — finishing a job, and reviews from finished jobs only (Phase 2).
--
-- The mechanic (or the owner) marks an accepted job as done. Then the owner
-- can rate it once, 1 to 5 stars with an optional comment, within 14 days.
-- The listing's rating (rating_avg, rating_count, shown to owners) is worked
-- out here from those reviews and nothing else, so it cannot be padded.

alter table public.service_requests add column done_at timestamptz;

-- Either side says the work is done.
create or replace function public.mark_job_done(p_request uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.service_requests r
     set status = 'done', done_at = now()
    from public.providers p
   where r.id = p_request and r.status = 'accepted'
     and p.id = r.provider_id
     and (r.user_id = auth.uid() or p.owner_user_id = auth.uid());
  if not found then
    raise exception 'Only an accepted job can be marked done, by its owner or its mechanic'
      using errcode = '42501';
  end if;
end;
$$;
revoke execute on function public.mark_job_done(uuid) from public, anon;
grant execute on function public.mark_job_done(uuid) to authenticated;

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.service_requests (id) on delete cascade,
  provider_id uuid not null references public.providers (id),
  user_id uuid not null references auth.users (id) on delete cascade,
  stars integer not null check (stars between 1 and 5),
  comment text check (comment is null or length(comment) <= 300),
  created_at timestamptz not null default now()
);
create index reviews_provider_idx on public.reviews (provider_id, created_at desc);

alter table public.reviews enable row level security;
-- The reviewer, the reviewed mechanic and admins can read a review.
create policy reviews_read on public.reviews for select
  using (user_id = auth.uid() or public.is_admin()
         or exists (select 1 from public.providers p
                     where p.id = provider_id and p.owner_user_id = auth.uid()));
grant select on public.reviews to authenticated;

-- The owner rates a finished job. Once per job, within 14 days of it ending.
create or replace function public.leave_review(p_request uuid, p_stars integer, p_comment text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.service_requests;
begin
  select * into r from public.service_requests
   where id = p_request and user_id = auth.uid();
  if r.id is null then
    raise exception 'Request not found' using errcode = '42501';
  end if;
  if r.status <> 'done' or r.provider_id is null then
    raise exception 'You can rate a job once it is done';
  end if;
  if r.done_at < now() - interval '14 days' then
    raise exception 'This job ended too long ago to rate';
  end if;
  if p_stars is null or p_stars not between 1 and 5 then
    raise exception 'Pick from 1 to 5 stars';
  end if;
  insert into public.reviews (request_id, provider_id, user_id, stars, comment)
  values (p_request, r.provider_id, auth.uid(), p_stars,
          nullif(trim(coalesce(p_comment, '')), ''))
  on conflict (request_id) do nothing;
  if not found then
    raise exception 'You already rated this job';
  end if;

  update public.providers p
     set rating_avg = s.avg, rating_count = s.n
    from (select round(avg(stars)::numeric, 1) as avg, count(*)::integer as n
            from public.reviews where provider_id = r.provider_id) s
   where p.id = r.provider_id;
end;
$$;
revoke execute on function public.leave_review(uuid, integer, text) from public, anon;
grant execute on function public.leave_review(uuid, integer, text) to authenticated;

-- The owner's latest finished job not yet rated (done in the last 14 days),
-- so the home screen can ask "How did they do?". Empty when there is none.
create or replace function public.my_review_due()
returns table (request_id uuid, provider_name text, done_at timestamptz)
language sql stable security definer set search_path = public
as $$
  select r.id, p.display_name, r.done_at
    from public.service_requests r
    join public.providers p on p.id = r.provider_id
   where r.user_id = auth.uid() and r.status = 'done'
     and r.done_at > now() - interval '14 days'
     and not exists (select 1 from public.reviews v where v.request_id = r.id)
   order by r.done_at desc
   limit 1;
$$;
revoke execute on function public.my_review_due() from public, anon;
grant execute on function public.my_review_due() to authenticated;

-- Owners can no longer change a listing's rating by any other route:
-- the providers table already only lets admins write it.
