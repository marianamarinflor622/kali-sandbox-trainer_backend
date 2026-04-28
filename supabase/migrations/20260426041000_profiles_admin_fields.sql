-- Perfiles: email + role para panel admin, con políticas seguras.
-- Mantiene lectura propia y añade permisos de lectura/escritura para admins.

alter table public.profiles
  add column if not exists email text,
  add column if not exists role text not null default 'student';

alter table public.profiles
  drop constraint if exists profiles_role_check;

alter table public.profiles
  add constraint profiles_role_check check (role in ('student', 'teacher', 'admin'));

create unique index if not exists profiles_email_lower_key
  on public.profiles (lower(email))
  where email is not null;

-- Backfill inicial desde auth.users.
update public.profiles p
set email = u.email
from auth.users u
where u.id = p.id
  and (p.email is distinct from u.email);

update public.profiles
set role = 'student'
where role is null;

-- Crear/sincronizar perfil al crear usuario auth.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, role)
  values (new.id, new.email, 'student')
  on conflict (id) do update
    set email = excluded.email;
  return new;
end;
$$;

-- Mantener email sincronizado si cambia en auth.users.
create or replace function public.sync_profile_email_from_auth()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
  set email = new.email
  where id = new.id;
  return new;
end;
$$;

drop trigger if exists sync_profile_email_from_auth on auth.users;
create trigger sync_profile_email_from_auth
  after update of email on auth.users
  for each row
  execute function public.sync_profile_email_from_auth();

-- Helper para RLS admin (security definer para no depender de RLS recursiva).
create or replace function public.is_current_user_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  );
$$;

revoke all on function public.is_current_user_admin() from public;
grant execute on function public.is_current_user_admin() to authenticated;

drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
drop policy if exists "profiles_update_admin_only" on public.profiles;

create policy "profiles_select_own_or_admin"
  on public.profiles for select
  to authenticated
  using (id = auth.uid() or public.is_current_user_admin());

create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

create policy "profiles_update_admin_only"
  on public.profiles for update
  to authenticated
  using (public.is_current_user_admin())
  with check (public.is_current_user_admin());
