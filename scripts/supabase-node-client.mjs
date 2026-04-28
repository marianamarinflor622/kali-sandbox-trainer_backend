/**
 * Cliente Supabase para scripts Node (no navegador).
 *
 * En `.env` (raíz del repo): SUPABASE_URL + SUPABASE_ANON_KEY
 * (Settings → API). No uses `service_role` salvo scripts admin locales.
 *
 * Uso:
 *   cd scripts && npm ci && node supabase-node-client.mjs
 */
import { createClient } from "@supabase/supabase-js";
import dotenv from "dotenv";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: join(__dirname, "..", ".env") });

const supabaseUrl =
  process.env.SUPABASE_URL?.trim() ||
  (process.env.SUPABASE_PROJECT_REF?.trim()
    ? `https://${process.env.SUPABASE_PROJECT_REF.trim()}.supabase.co`
    : "");

/** Preferimos nombre explícito; `SUPABASE_KEY` solo por compatibilidad con snippets viejos. */
const supabaseKey =
  process.env.SUPABASE_ANON_KEY?.trim() ||
  process.env.SUPABASE_PUBLISHABLE_KEY?.trim() ||
  process.env.SUPABASE_KEY?.trim();

if (!supabaseUrl || !supabaseKey) {
  console.error(
    "Faltan SUPABASE_URL (o SUPABASE_PROJECT_REF) y SUPABASE_ANON_KEY en .env"
  );
  process.exit(1);
}

export const supabase = createClient(supabaseUrl, supabaseKey);

// Demostración mínima (quita o sustituye por tu consulta)
const { data, error } = await supabase.from("profiles").select("id").limit(1);
if (error) console.error("Error:", error.message);
else console.log("OK, filas de ejemplo:", data?.length ?? 0);
