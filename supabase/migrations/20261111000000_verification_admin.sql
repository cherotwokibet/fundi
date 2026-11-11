-- Fundi — verification documents and the admin console.
--
-- To make someone an admin, run this once in the SQL editor after they have
-- signed in (replace the phone number):
--   update public.profiles set role = 'admin' where phone = '254712345678';
-- If they have no profile row yet:
--   insert into public.profiles (id, phone, role)
--   select id, phone, 'admin' from auth.users where phone = '254712345678';

create type public.document_kind as enum
  ('national_id', 'selfie', 'certificate', 'business_registration', 'county_permit');

-- One row per uploaded document. The file itself lives in the private
-- 'kyc' storage bucket under <owner user id>/<kind>.
create table public.provider_documents (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.providers (id) on delete cascade,
  kind public.document_kind not null,
  storage_path text not null,
  uploaded_at timestamptz not null default now(),
  unique (provider_id, kind)
);

alter table public.provider_documents enable row level security;

create policy documents_owner_read on public.provider_documents for select
  using (public.is_admin()
         or exists (select 1 from public.providers p
                     where p.id = provider_id and p.owner_user_id = auth.uid()));
create policy documents_owner_insert on public.provider_documents for insert
  with check (exists (select 1 from public.providers p
                       where p.id = provider_id and p.owner_user_id = auth.uid())
              and storage_path like auth.uid()::text || '/%');
create policy documents_owner_update on public.provider_documents for update
  using (exists (select 1 from public.providers p
                  where p.id = provider_id and p.owner_user_id = auth.uid()))
  with check (storage_path like auth.uid()::text || '/%');
create policy documents_admin on public.provider_documents for all
  using (public.is_admin()) with check (public.is_admin());

grant select, insert, update on public.provider_documents to authenticated;

-- Private bucket: ID documents are never public.
insert into storage.buckets (id, name, public)
values ('kyc', 'kyc', false)
on conflict (id) do nothing;

create policy kyc_owner_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'kyc' and (storage.foldername(name))[1] = auth.uid()::text);
create policy kyc_owner_update on storage.objects for update to authenticated
  using (bucket_id = 'kyc' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'kyc' and (storage.foldername(name))[1] = auth.uid()::text);
create policy kyc_read on storage.objects for select to authenticated
  using (bucket_id = 'kyc'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

-- ---------------------------------------------------------------------------
-- Admin actions. Each checks is_admin() and records who did it.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_check(
  p_provider uuid,
  p_kind public.check_kind,
  p_passed boolean
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  insert into public.verification_checks (provider_id, kind, status, checked_at, checked_by)
  values (p_provider, p_kind,
          case when p_passed then 'passed' else 'pending' end::public.check_status,
          now(), auth.uid())
  on conflict (provider_id, kind) do update
     set status = excluded.status, checked_at = excluded.checked_at, checked_by = excluded.checked_by;
end;
$$;

create or replace function public.admin_set_status(
  p_provider uuid,
  p_status public.provider_status
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  -- Nobody goes live without a passed identity check.
  if p_status = 'approved' and not exists (
       select 1 from public.verification_checks v
        where v.provider_id = p_provider and v.kind = 'identity' and v.status = 'passed') then
    raise exception 'Pass the identity check before approving';
  end if;
  update public.providers set status = p_status where id = p_provider;
  if not found then
    raise exception 'Provider not found';
  end if;
end;
$$;

revoke execute on function public.admin_set_check(uuid, public.check_kind, boolean) from public, anon;
revoke execute on function public.admin_set_status(uuid, public.provider_status) from public, anon;
grant execute on function public.admin_set_check(uuid, public.check_kind, boolean) to authenticated;
grant execute on function public.admin_set_status(uuid, public.provider_status) to authenticated;
grant execute on function public.is_admin() to authenticated;
