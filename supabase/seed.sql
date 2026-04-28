-- Código de invitación por defecto (solo `supabase db reset` / entorno dev).
-- Producción: inserta códigos vía SQL Editor o migración dedicada, nunca en variables VITE_*.
insert into public.invite_codes (code)
select 'evolveciber2026!'
where not exists (
  select 1 from public.invite_codes where lower(code) = 'evolveciber2026!'
);
