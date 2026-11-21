-- Access rules for admin-only onboarding and the parts marketplace
-- (migration 20261119000000). Run with supabase/tests/run.sh.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

-- Supabase stores phones without the plus sign; the stand-in does the same here.
insert into auth.users (id, phone, phone_confirmed_at, is_anonymous) values
  ('00000000-0000-0000-0000-00000000a0f2', '254700000900', now(), false), -- admin
  ('00000000-0000-0000-0000-00000000a0a1', '254711100001', now(), false), -- mechanic, listing owner
  ('00000000-0000-0000-0000-00000000a0a2', '254711100002', now(), false), -- the mechanic's helper
  ('00000000-0000-0000-0000-00000000a0b1', '254711100003', now(), false), -- shop 1 owner
  ('00000000-0000-0000-0000-00000000a0b2', '254711100004', now(), false), -- shop 1 worker
  ('00000000-0000-0000-0000-00000000a0b3', '254711100007', now(), false), -- shop 2 owner
  ('00000000-0000-0000-0000-00000000a0c1', '254711100005', now(), false), -- stranger, signed in
  ('00000000-0000-0000-0000-00000000a0c2', '254711100006', null,  false), -- invited, phone not confirmed
  ('00000000-0000-0000-0000-00000000a0c3', '254711100008', now(), false), -- already signed in before invite
  ('00000000-0000-0000-0000-00000000a0d1', null, null, true);            -- guest car owner
insert into public.profiles (id, role) values ('00000000-0000-0000-0000-00000000a0f2', 'admin');

create function pg_temp.as_user(p uuid) returns void language sql as $$
  select set_config('test.uid', coalesce(p::text, ''), false);
$$;

-- Runs a statement that must be refused (any error counts as refused).
create function pg_temp.refused(stmt text, what text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    return;
  end;
  raise exception 'FAIL: %', what;
end $$;

create function pg_temp.check(ok boolean, what text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', what; end if;
end $$;

-- 1. A signed-in stranger cannot onboard themselves in any way.
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0c1');
set role authenticated;
select pg_temp.refused($$
  insert into public.providers (owner_user_id, type, display_name, business_phone, area, location)
  values ('00000000-0000-0000-0000-00000000a0c1', 'mobile_mechanic', 'Self Made', '+254711100005',
          'Kasarani', 'SRID=4326;POINT(36.89 -1.22)') $$, 'stranger created their own listing');
select pg_temp.refused($$
  insert into public.profiles (id, role) values ('00000000-0000-0000-0000-00000000a0c1', 'mechanic') $$,
  'stranger gave themselves the mechanic role');
insert into public.profiles (id, role) values ('00000000-0000-0000-0000-00000000a0c1', 'owner');
select pg_temp.refused($$
  update public.profiles set role = 'garage_staff' where id = '00000000-0000-0000-0000-00000000a0c1' $$,
  'stranger changed their own role');
select pg_temp.refused($$
  select public.admin_create_provider('mobile_mechanic', 'Sneaky', '0711100005', 'Kasarani',
                                      -1.22, 36.89, '0711100005') $$,
  'stranger used an admin function');
select pg_temp.refused($$
  select public.admin_create_shop('Sneaky Spares', '0711100005', 'Kirinyaga Rd', -1.28, 36.83, '0711100005') $$,
  'stranger created a parts shop');
select pg_temp.refused($$ insert into public.memberships (shop_id, phone) values (null, '254711100005') $$,
  'stranger wrote a membership');
reset role;

-- 2. The admin onboards a mechanic, a helper, two shops and their people.
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0f2');
set role authenticated;
create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated;
insert into ids select 'mech', public.admin_create_provider(
  'mobile_mechanic', 'Juma Mobile Mechanic', '0722 100 001', 'Kasarani',
  -1.2210, 36.8980, '0711 100 001', 'Juma', 5, 300, array['Toyota']);
insert into ids select 'shop1', public.admin_create_shop(
  'Roysambu Spares', '0722100003', 'Roysambu', -1.2180, 36.8890, '+254 711 100 003', 'Wanjiru');
insert into ids select 'shop2', public.admin_create_shop(
  'Industrial Area Parts', '0722100007', 'Industrial Area', -1.3080, 36.8500, '0711100007');
select public.admin_add_member((select id from ids where name = 'mech'), null, '0711100002', 'Helper');
select public.admin_add_member((select id from ids where name = 'mech'), null, '0711100006');
select public.admin_add_member(null, (select id from ids where name = 'shop1'), '0711100004', 'Shop worker');
insert into ids select 'early', public.admin_add_member(null, (select id from ids where name = 'shop2'), '0711100008');

select pg_temp.check((select status = 'pending' from public.providers where id = (select id from ids where name = 'mech')),
  'a new listing must start as pending');
select pg_temp.check((select business_phone = '+254722100001' from public.providers where id = (select id from ids where name = 'mech')),
  'business phone not normalised');
select pg_temp.refused($$
  select public.admin_create_provider('garage', 'Second Listing', '0722100009', 'Kasarani',
                                      -1.22, 36.89, '0711100001') $$,
  'one number ran two listings');
select pg_temp.refused($$
  select public.admin_create_provider('garage', 'Bad Number', '0722100009', 'Kasarani', -1.22, 36.89, '12345') $$,
  'an invalid owner number was accepted');
-- Someone who signed in before they were added is linked at once.
select pg_temp.check((select user_id = '00000000-0000-0000-0000-00000000a0c3' from public.memberships
                       where id = (select id from ids where name = 'early')),
  'an existing account was not linked when added');
reset role;

-- 3. The mechanic signs in and is linked to their listing.
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0a1');
set role authenticated;
do $$
declare r record;
begin
  select * into strict r from public.claim_my_access();
  perform pg_temp.check(r.kind = 'provider' and r.role = 'owner' and r.org_status = 'pending', 'mechanic access wrong');
  perform pg_temp.check((select count(*) = 1 from public.my_provider()), 'mechanic does not own the listing');
  -- Calling it again changes nothing.
  perform pg_temp.check((select count(*) = 1 from public.claim_my_access()), 'claim is not repeatable');
  -- They see only their own membership.
  perform pg_temp.check((select count(*) = 1 from public.memberships), 'mechanic sees other memberships');
  -- A pending listing does not open the parts marketplace.
  perform pg_temp.check(not public.is_trade_member(), 'pending listing opened the marketplace');
end $$;
-- The owner cannot edit admin-checked details or approve themselves.
do $$
declare n int;
begin
  with u as (update public.providers set display_name = 'Changed', status = 'approved' returning 1)
  select count(*) into n from u;
  perform pg_temp.check(n = 0, 'owner edited their checked listing');
end $$;
reset role;

-- 4. A stranger and an unconfirmed phone get nothing.
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0c1');
set role authenticated;
select pg_temp.check((select count(*) = 0 from public.claim_my_access()), 'stranger got access');
select pg_temp.check(not public.is_trade_member(), 'stranger is a trade member');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0c2');
set role authenticated;
select pg_temp.check((select count(*) = 0 from public.claim_my_access()), 'unconfirmed phone claimed access');
reset role;

-- 5. Shop people list parts for their own shop only.
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0b1');
set role authenticated;
select pg_temp.check((select count(*) = 1 from public.claim_my_access()), 'shop owner not linked');
with x as (
  insert into public.parts_listings (shop_id, title, part_number, makes, models, year_from, year_to,
                                     condition, price_kes, stock_qty)
  values ((select id from ids where name = 'shop1'), 'Front brake pads', '04465-52180', array['Toyota'],
          'Probox, Succeed', 2014, 2022, 'new', 3500, 4)
  returning id)
insert into ids select 'pads', id from x;
insert into public.parts_listings (shop_id, title, makes, price_kes, stock_qty)
values ((select id from ids where name = 'shop1'), 'Wiper blades 22 inch', '{}', 900, 10);
select pg_temp.refused($$
  insert into public.parts_listings (shop_id, title, price_kes, photo_path)
  values ((select id from ids where name = 'shop1'), 'Bad path', 100, 'shops/someone-else/x.jpg') $$,
  'photo saved outside the shop folder');
reset role;

select pg_temp.as_user('00000000-0000-0000-0000-00000000a0b2');
set role authenticated;
select public.claim_my_access();
update public.parts_listings set price_kes = 3400 where id = (select id from ids where name = 'pads');
select pg_temp.check((select price_kes = 3400 from public.parts_listings where id = (select id from ids where name = 'pads')),
  'shop worker could not update a listing');
reset role;

select pg_temp.as_user('00000000-0000-0000-0000-00000000a0b3');
set role authenticated;
select public.claim_my_access();
select pg_temp.refused($$
  insert into public.parts_listings (shop_id, title, price_kes)
  values ((select id from ids where name = 'shop1'), 'Fake listing', 100) $$,
  'another shop listed parts for shop 1');
do $$
declare n int;
begin
  with u as (update public.parts_listings set price_kes = 1
              where id = (select id from ids where name = 'pads') returning 1)
  select count(*) into n from u;
  perform pg_temp.check(n = 0, 'another shop changed shop 1''s price');
end $$;
reset role;

-- 6. Car owners, guests and strangers never see parts.
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0d1');
set role authenticated;
select pg_temp.check((select count(*) = 0 from public.parts_listings), 'guest saw parts');
select pg_temp.check((select count(*) = 0 from public.parts_shops), 'guest saw shops');
select pg_temp.refused($$ select * from public.search_parts('brake') $$, 'guest searched parts');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0c1');
set role authenticated;
select pg_temp.check((select count(*) = 0 from public.parts_listings), 'stranger saw parts');
select pg_temp.refused($$ select * from public.search_parts('brake') $$, 'stranger searched parts');
reset role;
set role anon;
select pg_temp.refused($$ select * from public.parts_listings $$, 'anon read parts');
select pg_temp.refused($$ select * from public.search_parts('brake') $$, 'anon searched parts');
reset role;

-- 7. Once approved, the mechanic and their helper can search and order.
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0f2');
set role authenticated;
select public.admin_set_check((select id from ids where name = 'mech'), 'identity', true);
select public.admin_set_status((select id from ids where name = 'mech'), 'approved');
reset role;

select pg_temp.as_user('00000000-0000-0000-0000-00000000a0a1');
set role authenticated;
do $$
declare r record;
begin
  perform pg_temp.check(public.is_trade_member(), 'approved mechanic is not a trade member');
  select * into strict r from public.search_parts('brake', 'toyota');
  perform pg_temp.check(r.shop_name = 'Roysambu Spares' and r.price_kes = 3400 and r.distance_km < 2,
                        'search result wrong: ' || r::text);
  -- Fits-all parts show for any make; the other shop has nothing.
  perform pg_temp.check((select count(*) = 1 from public.search_parts('wiper', 'Nissan')), 'fits-all part missing');
  perform pg_temp.check((select count(*) = 0 from public.search_parts('brake', 'Nissan')), 'Toyota part shown for Nissan');
end $$;
reset role;

select pg_temp.as_user('00000000-0000-0000-0000-00000000a0a2');
set role authenticated;
select public.claim_my_access();
insert into ids select 'order1', public.place_parts_order(
  (select id from ids where name = 'mech'),
  jsonb_build_array(jsonb_build_object('listing_id', (select id from ids where name = 'pads'), 'qty', 3)),
  'Collect at 4pm');
select pg_temp.check((select total_kes = 10200 and status = 'placed' from public.parts_orders
                       where id = (select id from ids where name = 'order1')), 'order total wrong');
select pg_temp.check((select stock_qty = 1 from public.parts_listings where id = (select id from ids where name = 'pads')),
  'stock not held');
select pg_temp.refused($$
  select public.place_parts_order((select id from ids where name = 'mech'),
    jsonb_build_array(jsonb_build_object('listing_id', (select id from ids where name = 'pads'), 'qty', 2))) $$,
  'ordered more than the stock');
-- The helper cannot write orders or items directly.
select pg_temp.refused($$
  insert into public.parts_orders (provider_id, shop_id, placed_by, total_kes)
  values ((select id from ids where name = 'mech'), (select id from ids where name = 'shop1'),
          '00000000-0000-0000-0000-00000000a0a2', 1) $$, 'order written directly');
-- The buyer cannot confirm their own order.
select pg_temp.refused($$
  select public.update_parts_order((select id from ids where name = 'order1'), 'confirmed') $$,
  'buyer confirmed their own order');
reset role;

-- A stranger cannot order for the listing.
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0c1');
set role authenticated;
select pg_temp.refused($$
  select public.place_parts_order((select id from ids where name = 'mech'),
    jsonb_build_array(jsonb_build_object('listing_id', (select id from ids where name = 'pads'), 'qty', 1))) $$,
  'stranger placed an order');
select pg_temp.check((select count(*) = 0 from public.parts_orders), 'stranger saw orders');
reset role;

-- 8. The selling shop sees and moves the order on; the other shop sees nothing.
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0b3');
set role authenticated;
select pg_temp.check((select count(*) = 0 from public.parts_orders), 'another shop saw the order');
select pg_temp.check((select count(*) = 0 from public.parts_order_items), 'another shop saw order items');
select pg_temp.refused($$
  select public.update_parts_order((select id from ids where name = 'order1'), 'confirmed') $$,
  'another shop confirmed the order');
reset role;

select pg_temp.as_user('00000000-0000-0000-0000-00000000a0b2');
set role authenticated;
select pg_temp.check((select count(*) = 1 from public.parts_order_items), 'shop cannot see order items');
select public.update_parts_order((select id from ids where name = 'order1'), 'confirmed');
select pg_temp.refused($$
  select public.update_parts_order((select id from ids where name = 'order1'), 'collected') $$,
  'order skipped the ready step');
select public.update_parts_order((select id from ids where name = 'order1'), 'ready');
reset role;

select pg_temp.as_user('00000000-0000-0000-0000-00000000a0a1');
set role authenticated;
select pg_temp.check((select status = 'ready' from public.parts_orders where id = (select id from ids where name = 'order1')),
  'mechanic cannot see the order status');
select pg_temp.refused($$
  select public.update_parts_order((select id from ids where name = 'order1'), 'cancelled') $$,
  'buyer cancelled after the shop confirmed');
-- A second order, cancelled by the buyer, gives the stock back.
insert into ids select 'order2', public.place_parts_order(
  (select id from ids where name = 'mech'),
  jsonb_build_array(jsonb_build_object('listing_id', (select id from ids where name = 'pads'), 'qty', 1)));
select pg_temp.check((select stock_qty = 0 from public.parts_listings where id = (select id from ids where name = 'pads')),
  'second order did not hold stock');
select pg_temp.check((select count(*) = 0 from public.search_parts('brake')), 'out-of-stock part still shown');
select public.update_parts_order((select id from ids where name = 'order2'), 'cancelled');
select pg_temp.check((select stock_qty = 1 from public.parts_listings where id = (select id from ids where name = 'pads')),
  'cancelling did not give the stock back');
reset role;

-- 9. Switching people off takes access away at once.
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0f2');
set role authenticated;
select public.admin_set_member_active(
  (select id from public.memberships where phone = '254711100002'), false);
select public.admin_set_member_active(
  (select id from public.memberships where phone = '254711100001'), false);
select pg_temp.check((select owner_user_id is null from public.providers where id = (select id from ids where name = 'mech')),
  'switched-off owner still runs the listing');
select public.admin_set_shop_status((select id from ids where name = 'shop1'), 'suspended');
reset role;

select pg_temp.as_user('00000000-0000-0000-0000-00000000a0a2');
set role authenticated;
select pg_temp.check(not public.is_trade_member(), 'switched-off helper still in the marketplace');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0a1');
set role authenticated;
select pg_temp.check((select count(*) = 0 from public.my_provider()), 'switched-off owner still sees the listing');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0b2');
set role authenticated;
select pg_temp.check(not public.is_shop_member((select id from ids where name = 'shop1')), 'suspended shop still open');
reset role;

-- 10. Switched back on, the owner gets their listing back.
select pg_temp.as_user('00000000-0000-0000-0000-00000000a0f2');
set role authenticated;
select public.admin_set_member_active(
  (select id from public.memberships where phone = '254711100001'), true);
select pg_temp.check((select owner_user_id = '00000000-0000-0000-0000-00000000a0a1' from public.providers
                       where id = (select id from ids where name = 'mech')), 'owner not restored');
reset role;

\o
\echo 'admin onboarding and parts: all checks passed'
