-- Fundi — optional photo and voice note on a "Find me a mechanic" request.

alter table public.service_requests
  add column photo_path text,
  add column voice_path text;

-- Private bucket. Files live under <owner user id>/<request stamp>/...
insert into storage.buckets (id, name, public)
values ('requests', 'requests', false)
on conflict (id) do nothing;

create policy requests_files_owner_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'requests' and (storage.foldername(name))[1] = auth.uid()::text);

-- Readable by the owner who sent it, the provider the request is assigned to,
-- and admins. Nobody else.
create policy requests_files_read on storage.objects for select to authenticated
  using (
    bucket_id = 'requests'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
      or exists (
        select 1
          from public.service_requests r
          join public.providers p on p.id = r.provider_id
         where p.owner_user_id = auth.uid()
           and (r.photo_path = name or r.voice_path = name)
      )
    )
  );

-- A request may only point at files in its sender's own folder.
alter table public.service_requests
  add constraint service_requests_paths_in_own_folder check (
    (photo_path is null or photo_path like user_id::text || '/%')
    and (voice_path is null or voice_path like user_id::text || '/%')
  );
