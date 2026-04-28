#!/usr/bin/env bash
# Aplica migraciones y despliega Edge Functions invite-validate + hibp-proxy (requiere .env en la raíz del repo).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Falta el fichero .env en la raíz del repo. Copia las variables desde el README."
  exit 1
fi

set -a
# shellcheck source=/dev/null
source .env
set +a

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" || -z "${SUPABASE_PROJECT_REF:-}" || -z "${SUPABASE_DB_PASSWORD:-}" ]]; then
  echo "Rellena en .env: SUPABASE_ACCESS_TOKEN, SUPABASE_PROJECT_REF, SUPABASE_DB_PASSWORD"
  exit 1
fi

export SUPABASE_ACCESS_TOKEN

CLI_VER="${SUPABASE_CLI_VERSION:-2.95.0}"
echo "→ supabase link (CLI ${CLI_VER})"
npx --yes "supabase@${CLI_VER}" link --project-ref "$SUPABASE_PROJECT_REF" --password "$SUPABASE_DB_PASSWORD"

echo "→ supabase db push"
npx --yes "supabase@${CLI_VER}" db push

echo "→ supabase functions deploy invite-validate"
npx --yes "supabase@${CLI_VER}" functions deploy invite-validate

echo "→ supabase functions deploy hibp-proxy"
npx --yes "supabase@${CLI_VER}" functions deploy hibp-proxy

echo "Listo: migraciones aplicadas; funciones invite-validate y hibp-proxy desplegadas."
echo "Recuerda: secreto HIBP_API_KEY en el proyecto (Dashboard → Edge Functions → Secrets) para hibp-proxy."
