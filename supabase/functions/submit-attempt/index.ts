import { createClient } from "jsr:@supabase/supabase-js@2";
import { validateAndDetectTrace, type RawTraceSample } from "../../../packages/airtime-core/src/index.ts";

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

function json(request: Request, status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(request), "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }
  });
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
    const { data: userData, error: userError } = await service.auth.getUser(jwt);
    if (userError || !userData.user) return json(request, 401, { error: "invalid_session" });

    const body = await request.json() as { attempt_id?: unknown; samples?: unknown };
    if (typeof body.attempt_id !== "string" || !Array.isArray(body.samples)) return json(request, 400, { error: "invalid_request" });
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(body.attempt_id)) {
      return json(request, 400, { error: "invalid_attempt_id" });
    }

    let result;
    try {
      result = validateAndDetectTrace(body.samples as RawTraceSample[]);
    } catch (error) {
      return json(request, 422, { error: error instanceof Error ? error.message : "invalid_trace" });
    }

    const { data, error } = await service.rpc("submit_validated_attempt", {
      p_user_id: userData.user.id,
      p_client_attempt_id: body.attempt_id,
      p_airtime_ms: Math.round(result.airtime * 1000),
      p_preflight_peak_g: result.preflightPeakAcceleration,
      p_impact_peak_g: result.impactPeakAcceleration,
      p_airborne_sample_count: result.airborneSampleCount
    });
    if (error) {
      const status = error.message.includes("submission_rate_limited") ? 429 : error.message.includes("profile_required") ? 409 : 400;
      return json(request, status, { error: error.message });
    }
    return json(request, 200, data as Record<string, unknown>);
  } catch (error) {
    console.error("submit-attempt failed", error instanceof Error ? error.message : "unknown_error");
    return json(request, 500, { error: "attempt_submission_failed" });
  }
});
