-- Run this once in Supabase Dashboard → SQL Editor.
-- Customer contact information is stored separately from public ticket-status data.

create table if not exists public.service_requests (
  id uuid primary key default gen_random_uuid(),
  ticket_number text unique not null check (ticket_number ~ '^LES-[A-Z0-9]+-[0-9]{3}$'),
  name text not null,
  email text not null,
  company text,
  phone text,
  preferred_contact_time text not null,
  service text not null,
  description text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.ticket_statuses (
  ticket_number text primary key references public.service_requests(ticket_number) on delete cascade,
  status text not null default 'Request received' check (status in ('Request received', 'In progress', 'Waiting for client', 'Resolved', 'Closed')),
  service text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.service_requests enable row level security;
alter table public.ticket_statuses enable row level security;

grant insert on public.service_requests to anon;
grant insert, select on public.ticket_statuses to anon;

drop policy if exists "Visitors can submit service requests" on public.service_requests;
create policy "Visitors can submit service requests"
  on public.service_requests for insert to anon with check (true);

drop policy if exists "Visitors can create initial ticket status" on public.ticket_statuses;
create policy "Visito rs can create initial ticket status"
  on public.ticket_statuses for insert to anon
  with check (status = 'Request received');

drop policy if exists "Visitors can read non-sensitive ticket statuses" on public.ticket_statuses;
create policy "Visitors can read non-sensitive ticket statuses"
  on public.ticket_statuses for select to anon using (true);

-- Staff can update ticket_statuses in the Supabase Table Editor.
-- Do not create an anon UPDATE policy: only dashboard administrators should change a status.

create table if not exists public.ticket_replies (
  id bigint generated always as identity primary key,
  ticket_number text not null references public.service_requests(ticket_number) on delete cascade,
  message text not null check (char_length(message) between 1 and 2000),
  created_at timestamptz not null default now()
);
alter table public.ticket_replies enable row level security;

-- Technician accounts can sign up, but require approval before accessing requests.
create table if not exists public.technician_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  phone text,
  approved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.technician_profiles add column if not exists email text;
alter table public.technician_profiles add column if not exists full_name text;
alter table public.technician_profiles add column if not exists phone text;
alter table public.technician_profiles add column if not exists approved boolean;
alter table public.technician_profiles add column if not exists updated_at timestamptz;
alter table public.technician_profiles enable row level security;

create or replace function public.create_technician_profile()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.technician_profiles (
    user_id,
    email,
    full_name,
    phone,
    approved,
    updated_at
  )
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), nullif(new.raw_user_meta_data->>'name', '')),
    nullif(new.raw_user_meta_data->>'phone', ''),
    true,
    now()
  )
  on conflict (user_id) do update set
    email = excluded.email,
    full_name = coalesce(excluded.full_name, public.technician_profiles.full_name),
    phone = coalesce(excluded.phone, public.technician_profiles.phone),
    approved = coalesce(public.technician_profiles.approved, excluded.approved),
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_technician_signup on auth.users;
create trigger on_technician_signup after insert on auth.users
for each row execute procedure public.create_technician_profile();

-- Optional alternative: restrict auto-approval to a trusted email domain
-- (replace example.gov.za with your domain and uncomment to use)
-- create or replace function public.create_technician_profile()
-- returns trigger
-- language plpgsql
-- security definer set search_path = public
-- as $$
-- begin
--   if new.email like '%@example.gov.za' then
--     insert into public.technician_profiles (user_id, approved) values (new.id, true) on conflict (user_id) do nothing;
--   else
--     insert into public.technician_profiles (user_id, approved) values (new.id, false) on conflict (user_id) do nothing;
--   end if;
--   return new;
-- end;
-- $$;

insert into public.technician_profiles (user_id, email, full_name, phone, approved, updated_at)
select id, email, coalesce(nullif(raw_user_meta_data->>'full_name', ''), nullif(raw_user_meta_data->>'name', '')), nullif(raw_user_meta_data->>'phone', ''), true, now()
from auth.users
on conflict (user_id) do update set
  email = excluded.email,
  full_name = coalesce(excluded.full_name, public.technician_profiles.full_name),
  phone = coalesce(excluded.phone, public.technician_profiles.phone),
  approved = coalesce(public.technician_profiles.approved, excluded.approved),
  updated_at = now();

grant select, insert, update on public.technician_profiles to authenticated;

drop policy if exists "Technicians can manage their own profile" on public.technician_profiles;
create policy "Technicians can manage their own profile" on public.technician_profiles
  for select to authenticated using (user_id = auth.uid());
create policy "Technicians can create their own profile" on public.technician_profiles
  for insert to authenticated with check (user_id = auth.uid() and (approved = false or approved is null));
create policy "Technicians can update their own profile" on public.technician_profiles
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid() and approved = public.technician_profiles.approved);

create or replace function public.is_approved_technician()
returns boolean
language sql
security definer set search_path = public
stable
as $$ select exists (select 1 from public.technician_profiles where user_id = auth.uid() and approved) $$;
grant execute on function public.is_approved_technician() to authenticated;

create or replace function public.update_ticket_status(p_ticket_number text, p_status text)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_approved_technician() then
    raise exception 'Your technician account is not approved.';
  end if;
  if p_status not in ('Request received', 'In progress', 'Waiting for client', 'Resolved', 'Closed') then
    raise exception 'Invalid ticket status.';
  end if;
  update public.ticket_statuses
  set status = p_status, updated_at = now()
  where ticket_number = p_ticket_number;
  if not found then
    raise exception 'Ticket not found.';
  end if;
end;
$$;
grant execute on function public.update_ticket_status(text, text) to authenticated;
grant select on public.service_requests to authenticated;
grant select, update on public.ticket_statuses to authenticated;
grant select, insert on public.ticket_replies to authenticated, anon;
drop policy if exists "Technicians can read service requests" on public.service_requests;
create policy "Technicians can read service requests" on public.service_requests for select to authenticated using (public.is_approved_technician());
drop policy if exists "Technicians can update ticket statuses" on public.ticket_statuses;
create policy "Technicians can update ticket statuses" on public.ticket_statuses for update to authenticated using (public.is_approved_technician()) with check (public.is_approved_technician());
drop policy if exists "Technicians can read replies" on public.ticket_replies;
create policy "Technicians can read replies" on public.ticket_replies for select to authenticated using (public.is_approved_technician());
drop policy if exists "Technicians can add replies" on public.ticket_replies;
create policy "Technicians can add replies" on public.ticket_replies for insert to authenticated with check (public.is_approved_technician());
drop policy if exists "Visitors can read replies for their ticket" on public.ticket_replies;
create policy "Visitors can read replies for their ticket" on public.ticket_replies for select to anon using (true);
