-- Permitir códigos de invitación con usos ilimitados.
-- Mantiene `invite_code` obligatorio en metadata, pero ya no consume/marca el código.
-- Nota: por constraint histórico, los códigos se almacenan en minúsculas.

create or replace function public.auth_enforce_invite_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  inv text;
  exists_code boolean;
begin
  inv := nullif(trim(both from coalesce(NEW.raw_user_meta_data ->> 'invite_code', '')), '');
  if inv is null then
    raise exception 'invite_code_required'
      using errcode = '23514',
        message = 'Invite code is required in user metadata (options.data.invite_code).';
  end if;

  select exists (
    select 1
    from public.invite_codes
    where lower(code) = lower(inv)
  )
  into exists_code;

  if not exists_code then
    raise exception 'invalid_invite'
      using errcode = '23514',
        message = 'Invalid invite code.';
  end if;

  return NEW;
end;
$$;

-- Código oficial del aula (sin límite de usos).
insert into public.invite_codes (code, used, used_by)
values ('evolveciber2026!', false, null)
on conflict (lower(code))
do update set used = false, used_by = null;
