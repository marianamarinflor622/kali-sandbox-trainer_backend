/**
 * Proxy Have I Been Pwned + Pwned Passwords (k-anon SHA-1 del correo como cadena).
 * Requiere JWT de usuario (verify_jwt en config). Rate limit: 10/h por usuario vía `rate_limit_allow`.
 * Secreto: HIBP_API_KEY (Dashboard → Edge Functions secrets), nunca en el cliente.
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const RATE_MAX = 10;
const RATE_WINDOW_SEC = 3600;

async function sha1HexUtf8(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("").toUpperCase();
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const hibpKey = Deno.env.get("HIBP_API_KEY")?.trim();
  if (!supabaseUrl || !serviceKey || !hibpKey) {
    return new Response(JSON.stringify({ error: "server_misconfigured" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const {
    data: { user },
    error: userErr,
  } = await admin.auth.getUser(jwt);
  if (userErr || !user?.id) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const rateKey = `hibp-proxy:${user.id}`;
  const { data: allowed, error: rlErr } = await admin.rpc("rate_limit_allow", {
    p_key: rateKey,
    p_max: RATE_MAX,
    p_window_seconds: RATE_WINDOW_SEC,
  });
  if (rlErr) {
    console.error("rate_limit_allow", rlErr);
    return new Response(JSON.stringify({ error: "rate_limit_error" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  if (!allowed) {
    return new Response(JSON.stringify({ error: "too_many_requests" }), {
      status: 429,
      headers: {
        ...cors,
        "Content-Type": "application/json",
        "Retry-After": String(RATE_WINDOW_SEC),
      },
    });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const email =
    typeof body === "object" && body !== null && "email" in body && typeof (body as { email: unknown }).email === "string"
      ? (body as { email: string }).email.trim().toLowerCase()
      : "";
  if (!email || !email.includes("@")) {
    return new Response(JSON.stringify({ error: "email_required" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const sites: string[] = [];
  let breaches = 0;
  let pwnedPwdHit = false;

  const breachRes = await fetch(
    `https://haveibeenpwned.com/api/v3/breachedaccount/${encodeURIComponent(email)}?truncateResponse=false`,
    {
      headers: {
        "hibp-api-key": hibpKey,
        "user-agent": "KaliSandboxTrainer-Edge/1",
      },
    }
  );

  if (breachRes.status === 404) {
    breaches = 0;
  } else if (!breachRes.ok) {
    console.error("hibp breachedaccount", breachRes.status, await breachRes.text());
    return new Response(JSON.stringify({ error: "hibp_upstream", status: breachRes.status }), {
      status: 502,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } else {
    const list = (await breachRes.json()) as { Name?: string; Title?: string }[];
    breaches = Array.isArray(list) ? list.length : 0;
    for (const b of Array.isArray(list) ? list : []) {
      const label = b.Title ?? b.Name;
      if (label) sites.push(label);
    }
  }

  const hash = await sha1HexUtf8(email);
  const prefix = hash.slice(0, 5);
  const suffix = hash.slice(5);
  const rangeRes = await fetch(`https://api.pwnedpasswords.com/range/${prefix}`, {
    headers: { "user-agent": "KaliSandboxTrainer-Edge-PwnedPasswords/1" },
  });
  if (rangeRes.ok) {
    const text = await rangeRes.text();
    for (const line of text.split("\n")) {
      const [hx, cnt] = line.split(":");
      if (hx && hx.toUpperCase() === suffix) {
        pwnedPwdHit = true;
        sites.push(`Pwned Passwords: la cadena del correo (SHA-1) aparece ${cnt?.trim() ?? ""} veces en el corpus público.`);
        break;
      }
    }
  }

  const found = breaches > 0 || pwnedPwdHit;

  return new Response(JSON.stringify({ breaches, sites, found }), {
    status: 200,
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
