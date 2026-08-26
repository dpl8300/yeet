import { createClient } from "jsr:@supabase/supabase-js@2";
import { decodeJwt, importPKCS8, SignJWT } from "npm:jose@5.9.6";

const jsonHeaders = { "content-type": "application/json; charset=utf-8" };

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function requiredSecret(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

async function makeAppleClientSecret(): Promise<string> {
  const teamID = requiredSecret("APPLE_TEAM_ID");
  const keyID = requiredSecret("APPLE_KEY_ID");
  const clientID = requiredSecret("APPLE_CLIENT_ID");
  const privateKeyBase64 = requiredSecret("APPLE_PRIVATE_KEY_BASE64");
  const privateKeyPEM = new TextDecoder().decode(
    Uint8Array.from(atob(privateKeyBase64), (character) => character.charCodeAt(0)),
  );
  const privateKey = await importPKCS8(privateKeyPEM, "ES256");

  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyID })
    .setIssuer(teamID)
    .setAudience("https://appleid.apple.com")
    .setSubject(clientID)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(privateKey);
}

async function exchangeAppleCode(code: string, clientSecret: string) {
  const clientID = requiredSecret("APPLE_CLIENT_ID");
  const body = new URLSearchParams({
    client_id: clientID,
    client_secret: clientSecret,
    code,
    grant_type: "authorization_code",
  });
  const response = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(`Apple token exchange failed: ${payload.error ?? response.status}`);
  return payload as {
    access_token: string;
    refresh_token?: string;
    id_token: string;
  };
}

async function revokeAppleToken(
  token: string,
  tokenType: "refresh_token" | "access_token",
  clientSecret: string,
) {
  const body = new URLSearchParams({
    client_id: requiredSecret("APPLE_CLIENT_ID"),
    client_secret: clientSecret,
    token,
    token_type_hint: tokenType,
  });
  const response = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!response.ok) throw new Error(`Apple token revocation failed: ${response.status}`);
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });

  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json(401, { error: "authentication_required" });
  }

  try {
    const supabase = createClient(
      requiredSecret("SUPABASE_URL"),
      requiredSecret("SUPABASE_SERVICE_ROLE_KEY"),
      { auth: { autoRefreshToken: false, persistSession: false } },
    );
    const jwt = authorization.slice("Bearer ".length);
    const { data: userData, error: userError } = await supabase.auth.getUser(jwt);
    if (userError || !userData.user) return json(401, { error: "invalid_session" });

    const body = await request.json() as { authorization_code?: string };
    if (!body.authorization_code) return json(400, { error: "authorization_code_required" });

    const clientSecret = await makeAppleClientSecret();
    const appleTokens = await exchangeAppleCode(body.authorization_code, clientSecret);
    const appleClaims = decodeJwt(appleTokens.id_token);
    const { data: adminUser, error: adminUserError } = await supabase.auth.admin.getUserById(
      userData.user.id,
    );
    if (adminUserError || !adminUser.user) throw adminUserError ?? new Error("User not found");

    const appleIdentity = adminUser.user.identities?.find((identity) => identity.provider === "apple");
    const identityData = appleIdentity?.identity_data as Record<string, unknown> | undefined;
    const appleSubject = typeof identityData?.sub === "string" ? identityData.sub : undefined;
    if (!appleSubject || appleClaims.sub !== appleSubject) {
      return json(403, { error: "apple_identity_mismatch" });
    }

    const token = appleTokens.refresh_token ?? appleTokens.access_token;
    const tokenType = appleTokens.refresh_token ? "refresh_token" : "access_token";
    await revokeAppleToken(token, tokenType, clientSecret);

    const { error: deleteError } = await supabase.auth.admin.deleteUser(userData.user.id);
    if (deleteError) throw deleteError;

    return json(200, { deleted: true });
  } catch (error) {
    console.error("delete-account failed", error instanceof Error ? error.message : "unknown_error");
    return json(502, { error: "account_deletion_failed" });
  }
});
