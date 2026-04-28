# kali-sandbox-trainer_backend — contexto para el agente

## Rol de este repo

Monorepo **Supabase CLI** + opcional **`web/`** (Next.js para demos/paneles). Aquí viven **datos, auth server-side, RLS, migraciones y Edge Functions** del aula.

## Repositorio hermano (front del aula)

| Repo | Ruta típica (hermano) | Contenido |
|------|------------------------|-----------|
| **Front** | `../kali-sandbox-trainer` | SPA Vite/React: terminal simulada, `catalog.ts`, perspectivas Red/Blue, UI del alumno. |

El **front del aula no es** `web/` de este repo. `web/` es Next opcional; no sustituye la SPA.

## Dónde tocar qué

| Tarea | Ubicación |
|-------|-----------|
| Esquema BD, RLS, triggers | `supabase/migrations/` |
| Edge Functions (Deno) | `supabase/functions/` |
| Auth local / enlaces email | `supabase/config.toml` (+ alinear con Dashboard en hosted) |
| Semilla dev invitaciones | `supabase/seed.sql` |
| Next interno del monorepo | `web/` (ver `web/AGENTS.md` si aplica) |

## Reglas

1. **No** añadir aquí el catálogo pedagógico de comandos del simulador (`CATALOG`); eso es responsabilidad del repo **kali-sandbox-trainer**.
2. Códigos de invitación: tabla `public.invite_codes`; no variables `VITE_*` en el backend (el front usa anon key; la validación fuerte es BD + trigger + opcional Edge `invite-validate`).
3. **Have I Been Pwned:** Edge `hibp-proxy` (JWT + rate limit); secreto **`HIBP_API_KEY`** solo en Supabase, no en el SPA.
4. Tras cambios en SQL: revisar flujo `supabase db push` / CI documentado en `README.md`.

Informe de separación front/back (en el repo del aula): en el front, archivo `docs/auditoria-separacion-front-back.md` (clonar ese repo o abrir workspace multi-raíz para leerlo).

## Workspace Cursor (dos raíces)

Con front y backend en el mismo workspace, referencia rutas como `kali-sandbox-trainer_backend/supabase/...` y `kali-sandbox-trainer/src/...`.
