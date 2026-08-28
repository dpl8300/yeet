import { createClient } from "jsr:@supabase/supabase-js@2";

function corsHeaders(request: Request) {
  const origin = request.headers.get("origin") ?? "";
  const allowed = (Deno.env.get("WEB_ALLOWED_ORIGINS") ?? "http://localhost:5173").split(",").map((value) => value.trim());
  return {
    "access-control-allow-origin": allowed.some((pattern) => matchesOrigin(origin, pattern)) ? origin : "",
    "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
    "access-control-allow-methods": "POST, OPTIONS",
    "vary": "Origin"
  };
}

function matchesOrigin(origin: string, pattern: string) {
  const escaped = pattern.split("*").map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*");
  return Boolean(origin) && new RegExp(`^${escaped}$`).test(origin);
}

const json = (request: Request, status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders(request), "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }
});

function requiredSecret(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function supabaseServerKey() {
  const current = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (current) {
    const keys = JSON.parse(current) as Record<string, unknown>;
    const preferred = keys.default ?? Object.values(keys)[0];
    if (typeof preferred === "string" && preferred) return preferred;
  }
  return requiredSecret("SUPABASE_SERVICE_ROLE_KEY");
}

function jwtPayload(token: string) {
  const encoded = token.split(".")[1];
  if (!encoded) throw new Error("invalid_jwt");
  const padded = encoded.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(encoded.length / 4) * 4, "=");
  return JSON.parse(atob(padded)) as { session_id?: string };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(request) });
  if (request.method !== "POST") return json(request, 405, { error: "method_not_allowed" });
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return json(request, 401, { error: "authentication_required" });

  try {
    const service = createClient(requiredSecret("SUPABASE_URL"), supabaseServerKey(), {
      auth: { autoRefreshToken: false, persistSession: false }
    });
    const jwt = authorization.slice("Bearer ".length);
    const { data, error } = await service.auth.getUser(jwt);
    if (error || !data.user) return json(request, 401, { error: "invalid_session" });
    const sessionID = jwtPayload(jwt).session_id;
    if (!sessionID) return json(request, 401, { error: "session_id_missing" });

    const { data: fresh, error: freshnessError } = await service.rpc("delete_account_session_is_fresh", {
      p_user_id: data.user.id,
      p_session_id: sessionID
    });
    if (freshnessError) throw freshnessError;
    if (!fresh) return json(request, 403, { error: "fresh_email_verification_required" });

    const { error: deleteError } = await service.auth.admin.deleteUser(data.user.id);
    if (deleteError) throw deleteError;
    return json(request, 200, { deleted: true });
  } catch (error) {
    console.error("delete-account failed", error instanceof Error ? error.message : "unknown_error");
    return json(request, 500, { error: "account_deletion_failed" });
  }
});
