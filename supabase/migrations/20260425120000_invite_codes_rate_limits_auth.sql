-- Códigos de invitación (fuente de verdad en BD, no VITE_*).
-- Rate limiting persistente para la Edge Function invite-validate.
-- Trigger updated_at en profiles.
-- Obliga invite_code en raw_user_meta_data en cada alta (signUp con options.data).

-- Quitar columnas legacy de recuperación por frase (Auth gestiona reset por email).
alter table public.profiles drop column if exists recovery_salt;
alter table public.profiles drop column if exists recovery_hash;
alter table public.profiles drop column if exists recovery_iterations;

-- --- invite_codes ---
create table if not exists public.invite_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  used boolean not null default false,
  -- Sin FK a auth.users: el consumo ocurre en BEFORE INSERT y el id aún no existe en auth.
  used_by uuid,
  created_at timestamptz not null default now()
);

alter table public.invite_codes drop constraint if exists invite_codes_must_be_lower;
alter table public.invite_codes
  add constraint invite_codes_must_be_lower check (code = lower(code));

create unique index if not exists invite_codes_code_lower_key
  on public.invite_codes (lower(code));

alter table public.invite_codes enable row level security;

revoke all on table public.invite_codes from anon, authenticated;

-- --- rate_limits (eventos por ventana; la RPC limpia y cuenta) ---
create table if not exists public.rate_limits (
  id bigserial primary key,
  key text not null,
  created_at timestamptz not null default now()
);

create index if not exists rate_limits_key_created_idx
  on public.rate_limits (key, created_at desc);

alter table public.rate_limits enable row level security;

revoke all on table public.rate_limits from anon, authenticated;

create or replace function public.rate_limit_allow(
  p_key text,
  p_max integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  cnt integer;
begin
  if p_max < 1 or p_window_seconds < 1 then
    return false;
  end if;

  delete from public.rate_limits
  where created_at < now() - (p_window_seconds * interval '1 second');

  select count(*)::integer into cnt
  from public.rate_limits
  where key = p_key
    and created_at >= now() - (p_window_seconds * interval '1 second');

  if cnt >= p_max then
    return false;
  end if;

  insert into public.rate_limits (key) values (p_key);
  return true;
end;
$$;

revoke all on function public.rate_limit_allow(text, integer, integer) from public;
grant execute on function public.rate_limit_allow(text, integer, integer) to service_role;

-- --- profiles updated_at ---
create or replace function public.set_profiles_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function public.set_profiles_updated_at();

-- --- Auth: consumir código en metadata (obligatorio en altas vía API) ---
create or replace function public.auth_enforce_invite_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  inv text;
  updated_count integer;
begin
  inv := nullif(trim(both from coalesce(NEW.raw_user_meta_data ->> 'invite_code', '')), '');
  if inv is null then
    raise exception 'invite_code_required'
      using errcode = '23514',
        message = 'Invite code is required in user metadata (options.data.invite_code).';
  end if;

  update public.invite_codes
  set
    used = true,
    used_by = NEW.id
  where lower(code) = lower(inv)
    and used = false;

  get diagnostics updated_count = row_count;
  if updated_count <> 1 then
    raise exception 'invalid_or_used_invite'
      using errcode = '23514',
        message = 'Invalid or already used invite code.';
  end if;

  return NEW;
end;
$$;

drop trigger if exists auth_enforce_invite_before_insert on auth.users;
create trigger auth_enforce_invite_before_insert
  before insert on auth.users
  for each row
  execute function public.auth_enforce_invite_code();
