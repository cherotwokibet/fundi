-- SAMPLE DATA for development only. These are invented providers with
-- placeholder phone numbers. Do not load into a production project.

with new_providers as (
  insert into public.providers
    (type, display_name, business_phone, area, location, service_radius_km, callout_fee_kes, makes, rating_avg, rating_count, status)
  values
    ('mobile_mechanic', 'Sample: Otieno Mobile Mechanic', '+254700000001', 'Kasarani',
      extensions.st_setsrid(extensions.st_makepoint(36.8981, -1.2203), 4326), 8, 500, '{Toyota,Nissan,Mazda}', 4.7, 38, 'approved'),
    ('garage', 'Sample: Roysambu Auto Garage', '+254700000002', 'Roysambu',
      extensions.st_setsrid(extensions.st_makepoint(36.8866, -1.2186), 4326), 0, 300, '{}', 4.5, 112, 'approved'),
    ('mobile_mechanic', 'Sample: Wanjiru Auto Electrics', '+254700000003', 'Zimmerman',
      extensions.st_setsrid(extensions.st_makepoint(36.8930, -1.2098), 4326), 10, 600, '{Toyota,Subaru,Honda}', 4.8, 54, 'approved'),
    ('garage', 'Sample: Thika Road Motor Works', '+254700000004', 'Garden Estate',
      extensions.st_setsrid(extensions.st_makepoint(36.8743, -1.2301), 4326), 0, 0, '{}', 4.3, 76, 'approved'),
    ('mobile_mechanic', 'Sample: Kamau Roadside Rescue', '+254700000005', 'Westlands',
      extensions.st_setsrid(extensions.st_makepoint(36.8110, -1.2676), 4326), 12, 800, '{}', 4.6, 29, 'approved'),
    ('garage', 'Sample: Parklands Service Centre', '+254700000006', 'Parklands',
      extensions.st_setsrid(extensions.st_makepoint(36.8177, -1.2606), 4326), 0, 500, '{Toyota,Mercedes,BMW,Volkswagen}', 4.4, 91, 'approved'),
    ('mobile_mechanic', 'Sample: Achieng Quick Fix', '+254700000007', 'Kilimani',
      extensions.st_setsrid(extensions.st_makepoint(36.7843, -1.2921), 4326), 7, 500, '{Toyota,Nissan,Mitsubishi}', 4.9, 17, 'approved'),
    ('garage', 'Sample: Ngong Road Garage', '+254700000008', 'Ngong Road',
      extensions.st_setsrid(extensions.st_makepoint(36.7750, -1.3009), 4326), 0, 400, '{}', 4.2, 140, 'approved'),
    ('mobile_mechanic', 'Sample: Unapproved Mechanic', '+254700000009', 'Kasarani',
      extensions.st_setsrid(extensions.st_makepoint(36.8990, -1.2210), 4326), 5, 300, '{}', 0, 0, 'pending')
  returning id, display_name, type
)
, checks as (
  insert into public.verification_checks (provider_id, kind, status, checked_at)
  select p.id, k.kind, 'passed', now()
    from new_providers p
    cross join (values ('identity'::public.check_kind), ('location'), ('experience'), ('business')) as k(kind)
   where p.display_name not like '%Unapproved%'
     and (k.kind <> 'business' or p.type = 'garage')
  returning 1
)
insert into public.availability (provider_id, status, set_at, expires_at)
select p.id,
       case
         when p.display_name like '%Thika Road%' or p.display_name like '%Kamau%' then 'busy'
         when p.display_name like '%Ngong Road%' then 'offline'
         else 'available'
       end::public.availability_status,
       case when p.display_name like '%Wanjiru%' then now() - interval '9 hours' else now() end,
       case when p.display_name like '%Wanjiru%' then now() - interval '5 hours' else now() + interval '4 hours' end
  from new_providers p;
