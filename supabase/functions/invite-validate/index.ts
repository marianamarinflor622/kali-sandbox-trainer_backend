/**
 * Valida que un código exista y no esté consumido en `public.invite_codes`.
 * Rate limit persistente: `public.rate_limits` + RPC `rate_limit_allow` (solo service_role).
 * El consumo definitivo del código ocurre en el trigger `auth_enforce_invite_code` al hacer signUp con metadata `invite_code`.
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const RATE_MAX = 30;
const RATE_WINDOW_SEC = 900;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ valid: false, error: "method_not_allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return new Response(JSON.stringify({ valid: false, error: "server_misconfigured" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ valid: false, error: "invalid_json" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const code =
    typeof body === "object" && body !== null && "code" in body && typeof (body as { code: unknown }).code === "string"
      ? (body as { code: string }).code.trim()
      : "";

  if (!code) {
    return new Response(JSON.stringify({ valid: false, error: "code_required" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const fwd = req.headers.get("x-forwarded-for") ?? "";
  const ip = fwd.split(",")[0]?.trim() || req.headers.get("cf-connecting-ip") || "unknown";
  const rateKey = `invite-validate:${ip}`;

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: allowed, error: rlErr } = await supabase.rpc("rate_limit_allow", {
    p_key: rateKey,
    p_max: RATE_MAX,
    p_window_seconds: RATE_WINDOW_SEC,
  });

  if (rlErr) {
    console.error("rate_limit_allow", rlErr);
    return new Response(JSON.stringify({ valid: false, error: "rate_limit_error" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  if (!allowed) {
    return new Response(JSON.stringify({ valid: false, error: "too_many_requests" }), {
      status: 429,
      headers: {
        ...cors,
        "Content-Type": "application/json",
        "Retry-After": String(RATE_WINDOW_SEC),
      },
    });
  }

  const normalized = code.toLowerCase();
  const { data: rows, error: qErr } = await supabase
    .from("invite_codes")
    .select("used")
    .eq("code", normalized)
    .limit(1);

  if (qErr) {
    console.error("invite_codes", qErr);
    return new Response(JSON.stringify({ valid: false, error: "lookup_failed" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const row = rows?.[0];
  const valid = Boolean(row && row.used === false);

  // `ok` mantiene compatibilidad con clientes que esperaban `{ ok: true }`.
  return new Response(JSON.stringify({ valid, ok: valid }), {
    status: 200,
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
