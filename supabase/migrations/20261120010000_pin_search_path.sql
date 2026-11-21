-- Fundi — pin the search path of three small helpers added on 19 Nov,
-- as the Supabase security advisor asks (lint 0011). No behaviour change.
alter function public.phone_digits(text) set search_path = public;
alter function public._check_phone(text) set search_path = public;
alter function public.touch_updated_at() set search_path = public;
