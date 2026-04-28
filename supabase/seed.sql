-- Código de invitación local (solo `supabase db reset` / entorno dev).
-- Producción: inserta códigos vía SQL Editor o migración dedicada, nunca en variables VITE_*.
insert into public.invite_codes (code)
select 'kst-local-dev-invite'
where not exists (
  select 1 from public.invite_codes where lower(code) = 'kst-local-dev-invite'
);
