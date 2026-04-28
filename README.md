# kali-sandbox-trainer — backend (Supabase + Next)

Este repositorio contiene **dos piezas distintas**:

| Ruta | Qué es |
|------|--------|
| **`supabase/`** | Proyecto **Supabase CLI**: migraciones SQL, políticas RLS, **Edge Functions** (Deno), `config.toml`. Es la fuente de verdad de datos y auth del aula. |
| **`web/`** | Aplicación **Next.js** (App Router) en este monorepo: demos, paneles internos o pruebas SSR. **No sustituye** al front del aula. |

El front del aula (**React + Vite**, SPA) está en el repositorio independiente **`kali-sandbox-trainer`** (nombre parecido, **otro árbol Git**). Ese cliente usa `VITE_SUPABASE_URL` y la clave **anon / publishable**; **no** debe depender de `VITE_*` para códigos de invitación (la fuente de verdad es la BD + Edge Function aquí).

### Workspace en Cursor (dos raíces)

Si añades **ambos** repos al mismo workspace, separa bien: catálogo de comandos y terminal simulada → **solo** `kali-sandbox-trainer`. Este repo → SQL, RLS, Edge Functions, `web/` Next opcional. Resumen para agentes: [`AGENTS.md`](./AGENTS.md).

## Invitaciones (solo backend; nunca listas en `VITE_*`)

- Tabla **`public.invite_codes`**: `code` (único, forzado a minúsculas), `used`, `used_by`, `created_at` (más `id` uuid interno).
- **Trigger en `auth.users` (BEFORE INSERT)**: cada `signUp` debe enviar `options.data.invite_code` en metadata. Si el código no existe o ya está usado, el alta **falla** en base de datos (no basta con ocultarlo en el front).
- **Edge Function `invite-validate`**: pre-chequeo desde el cliente + **rate limiting real** en BD: tabla `public.rate_limits`, RPC **`rate_limit_allow`** (ejecutable solo con `service_role`). `POST` JSON `{ "code": "..." }` → `{ "valid": true|false, "ok": … }` (compat.). Respuesta **429** con `Retry-After` si se supera el cupo por IP.
- La antigua función basada en variable de entorno **`INVITE_CODES`** fue eliminada; los códigos viven **solo** en `invite_codes`.

Despliegue: `supabase functions deploy invite-validate`. En hosted, el runtime expone `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` automáticamente.

**Edge Function `hibp-proxy`** (Password Lab en el SPA): `POST` JSON `{ "email": "..." }` con **JWT de usuario** (`verify_jwt = true`). Usa la API de Have I Been Pwned y el rango k-anon de **Pwned Passwords**; configura el secreto **`HIBP_API_KEY`** en el proyecto (Dashboard → Edge Functions → Secrets). Rate limit: **10 llamadas / hora / usuario** vía `rate_limits` + `rate_limit_allow`. Despliegue: `supabase functions deploy hibp-proxy`.

Además, **`[auth.rate_limit]`** en `config.toml` refleja los límites **nativos** de Supabase Auth (sign-in/sign-up por IP en el proyecto remoto cuando lo aplicas desde el Dashboard / API).

## Requisitos

- [Supabase CLI](https://supabase.com/docs/guides/cli) (versión **fijada** en CI; alinea la tuya localmente).
- Cuenta en [Supabase](https://supabase.com/dashboard) y proyecto creado.
- Para `web/`: Node.js compatible con Next 16 (ver `web/package.json`).

## Secret scanning (pre-commit)

```bash
pip install pre-commit
pre-commit install
```

En cada commit se ejecuta **gitleaks** (config `.gitleaks.toml`, exclusiones para `web/.next` y `node_modules`). Comprobación manual: `python3 -m pre_commit run --all-files`.

Instalación del hook (ya ejecutada si tienes `.git/hooks/pre-commit`):

```bash
python3 -m pip install --user pre-commit   # si no lo tienes
python3 -m pre_commit install
```

### Sincronizar remoto (migraciones + Edge Function)

Con `.env` relleno en la raíz (`SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`):

```bash
./scripts/supabase-sync.sh
```

Equivale a `link` + `db push` + `functions deploy invite-validate` + `functions deploy hibp-proxy` con la misma versión de CLI que en CI (`2.95.0` por defecto; sobreescribe con `SUPABASE_CLI_VERSION` si lo necesitas).

### Cliente Supabase en Node (snippets tipo `createClient`)

En el **navegador** (Vite/React) usa `import.meta.env.VITE_SUPABASE_*`, no `process.env`.

En **scripts Node**, usa `scripts/supabase-node-client.mjs`: carga `.env` con `SUPABASE_URL` (o solo `SUPABASE_PROJECT_REF`) y **`SUPABASE_ANON_KEY`** (nombre claro; evita `SUPABASE_KEY` genérico). Instala dependencias: `cd scripts && npm ci`.

## Puesta en marcha (Supabase)

1. **Clonar** y `cd kali-sandbox-trainer_backend`.
2. **`supabase login`** con token de [Access Tokens](https://supabase.com/dashboard/account/tokens).
3. **`supabase link --project-ref <TU_PROJECT_REF> --password '<BD_PASSWORD>'`**
4. **`supabase db push`** para aplicar migraciones.
5. Semilla local: tras **`supabase db reset`**, `seed.sql` inserta el código `kst-local-dev-invite` (solo desarrollo).

## Puesta en marcha (`web/` — Next.js)

```bash
cd web
cp .env.example .env.local
# Rellena NEXT_PUBLIC_SUPABASE_URL y NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
npm install
npm run dev
```

La app Next corre en **http://localhost:3000** por defecto; el `site_url` de ejemplo en `supabase/config.toml` apunta ahí para desarrollo local de este monorepo.

## Enlaces útiles (dashboard)

- [Authentication → URL Configuration](https://supabase.com/dashboard/project/<project-ref>/auth/url-configuration): **Site URL** y **Redirect URLs** del front **desplegado** (Vite/GitHub Pages, etc.).
- [SQL Editor](https://supabase.com/dashboard/project/<project-ref>/sql/new): insertar filas en `invite_codes` para producción.

## Migraciones destacadas

- `supabase/migrations/20260424120000_profiles.sql` — `public.profiles` + RLS + trigger `handle_new_user`.
- `supabase/migrations/20260425120000_invite_codes_rate_limits_auth.sql` — `invite_codes`, `rate_limits`, `rate_limit_allow`, trigger **`profiles_set_updated_at`**, trigger de invitación en **`auth.users`**, eliminación de columnas legacy `recovery_*` en `profiles` (la recuperación la gestiona **Supabase Auth** por correo).

## `config.toml` y producción

Los valores bajo **`[auth]`** y **`[auth.email]`** del `config.toml` rigen **`supabase start` local**. El proyecto **hosted** se gobierna en el **Dashboard** (confirmación por email, longitud mínima de contraseña, Site URL, etc.). Mantén alineados comentarios y valores locales con lo que tengas en producción; en particular:

- **`site_url`** y **`additional_redirect_urls`**
- **`enable_confirmations`** (`[auth.email]`)
- **`minimum_password_length`**
- **`[auth.rate_limit]`** (nativo Supabase)

## CI: `supabase db push` en `main`

Workflow `.github/workflows/supabase-db-push.yml`:

| Secreto | Descripción |
|--------|----------------|
| `SUPABASE_ACCESS_TOKEN` | Token personal |
| `SUPABASE_PROJECT_REF` | Ref del proyecto |
| `SUPABASE_DB_PASSWORD` | Contraseña Postgres del proyecto |

La versión del CLI de Supabase está **pinned** (no `latest`); súbela cuando probéis una versión nueva en local.

## Variables locales (raíz, no versionadas)

Ver README anterior: `.env` con token + ref + password para `supabase link` / `db push`. **No** subas `service_role` al remoto público del front; en Edge Functions el runtime hosted inyecta el secreto de servicio de forma segura.

## Front (otro repo)

Allí el `.env` lleva `VITE_SUPABASE_*` (anon). Tras este backend, el registro debe:

1. Opcional: `POST` a la Edge Function `invite-validate` con el código.
2. Obligatorio: `signUp` con `options: { data: { invite_code: '<mismo código en minúsculas>' } }` para que el trigger en `auth.users` consuma una fila de `invite_codes`.

---

Documentación cruzada del front: `docs/fullstack-auth.md` y `docs/supabase-backend-repo.md` en el repo **kali-sandbox-trainer**.
