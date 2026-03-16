import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

type DispatchBody = {
  recipientId?: string;
  recipientIds?: string[];
  token?: string;
  title?: string;
  body?: string;
  pushSecret?: string;
  data?: Record<string, string>;
};

type GoogleAccessTokenResponse = {
  access_token: string;
  expires_in: number;
  token_type: string;
};

type SecretConfig = {
  firebaseProjectId?: string;
  firebaseClientEmail?: string;
  firebasePrivateKey?: string;
  pushDispatchSecret?: string;
};

function loadSecretConfig(): SecretConfig {
  try {
    const raw = Deno.readTextFileSync(new URL("./.secrets.json", import.meta.url));
    return JSON.parse(raw) as SecretConfig;
  } catch {
    try {
      const raw = Deno.readTextFileSync("/home/deno/functions/push-dispatch/.secrets.json");
      return JSON.parse(raw) as SecretConfig;
    } catch {
      return {};
    }
  }
}

const secretConfig = loadSecretConfig();
const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim();
const anonKey = (Deno.env.get("SUPABASE_ANON_KEY") ?? "").trim();
const serviceRoleKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
const firebaseProjectId =
  (Deno.env.get("FIREBASE_PROJECT_ID") ?? secretConfig.firebaseProjectId ?? "").trim();
const firebaseClientEmail =
  (Deno.env.get("FIREBASE_CLIENT_EMAIL") ?? secretConfig.firebaseClientEmail ?? "").trim();
const firebasePrivateKey = (
  Deno.env.get("FIREBASE_PRIVATE_KEY") ?? secretConfig.firebasePrivateKey ?? ""
).trim().replaceAll("\\n", "\n");
const pushDispatchSecret =
  (Deno.env.get("PUSH_DISPATCH_SECRET") ?? secretConfig.pushDispatchSecret ?? "").trim();

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-push-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function ensureAuthorized(req: Request, body?: DispatchBody) {
  const providedSecret = req.headers.get("x-push-secret")?.trim() ?? "";
  const providedBodySecret = body?.pushSecret?.trim() ?? "";
  if (
    pushDispatchSecret &&
    (providedSecret === pushDispatchSecret || providedBodySecret === pushDispatchSecret)
  ) {
    return;
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    throw new Error("Unauthorized");
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const {
    data: { user },
    error: userError,
  } = await adminClient.auth.getUser(jwt);

  if (userError != null || user == null) {
    throw new Error("Unauthorized");
  }

  const { data: profile, error: profileError } = await adminClient
    .from("profiles")
    .select("is_admin")
    .eq("id", user.id)
    .maybeSingle();

  if (profileError != null || profile?.is_admin !== true) {
    throw new Error("Admin access required");
  }
}

async function getGoogleAccessToken() {
  if (!firebaseProjectId || !firebaseClientEmail || !firebasePrivateKey) {
    throw new Error("Missing Firebase service account configuration");
  }

  const now = Math.floor(Date.now() / 1000);
  const alg = "RS256";
  const audience = "https://oauth2.googleapis.com/token";

  const privateKey = await importPKCS8(firebasePrivateKey, alg);
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg, typ: "JWT" })
    .setIssuer(firebaseClientEmail)
    .setSubject(firebaseClientEmail)
    .setAudience(audience)
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(privateKey);

  const response = await fetch(audience, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    throw new Error(`Failed to get Google access token: ${await response.text()}`);
  }

  const json = await response.json() as GoogleAccessTokenResponse;
  return json.access_token;
}

async function loadRecipientTokens(recipientId: string) {
  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const { data, error } = await adminClient
    .from("device_push_tokens")
    .select("token")
    .eq("user_id", recipientId);

  if (error != null) {
    throw new Error(error.message);
  }

  return (data ?? [])
    .map((row) => row.token as string)
    .filter((token) => token.length > 0);
}

async function loadRecipientTokensForUsers(recipientIds: string[]) {
  const uniqueIds = [...new Set(recipientIds.map((id) => id.trim()).filter((id) => id.length > 0))];
  if (uniqueIds.length === 0) {
    return [];
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const { data, error } = await adminClient
    .from("device_push_tokens")
    .select("token")
    .in("user_id", uniqueIds);

  if (error != null) {
    throw new Error(error.message);
  }

  return [...new Set(
    (data ?? [])
      .map((row) => row.token as string)
      .filter((token) => token.length > 0),
  )];
}

async function removeInvalidToken(token: string) {
  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  await adminClient.from("device_push_tokens").delete().eq("token", token);
}

async function sendToToken(
  accessToken: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
) {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: {
            priority: "high",
            notification: {
              channel_id: "default",
            },
          },
          webpush: {
            notification: {
              title,
              body,
              icon: "/icons/Icon-192.png",
            },
          },
        },
      }),
    },
  );

  if (response.ok) {
    return { ok: true as const };
  }

  const text = await response.text();
  if (text.includes("UNREGISTERED") || text.includes("registration-token-not-registered")) {
    await removeInvalidToken(token);
  }

  return {
    ok: false as const,
    error: text,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405, headers: corsHeaders });
  }

  try {
    const body = await req.json() as DispatchBody;
    await ensureAuthorized(req, body);
    const title = body.title?.trim() ?? "";
    const messageBody = body.body?.trim() ?? "";
    const directToken = body.token?.trim() ?? "";
    const recipientId = body.recipientId?.trim() ?? "";
    const recipientIds = Array.isArray(body.recipientIds)
      ? body.recipientIds.map((id) => String(id).trim()).filter((id) => id.length > 0)
      : [];

    if (!title || !messageBody) {
      return Response.json(
        { error: "title and body are required" },
        { status: 400, headers: corsHeaders },
      );
    }

    const tokens = directToken
      ? [directToken]
      : recipientId
      ? await loadRecipientTokens(recipientId)
      : recipientIds.length > 0
      ? await loadRecipientTokensForUsers(recipientIds)
      : [];

    if (tokens.length === 0) {
      return Response.json(
        { ok: true, sent: 0, results: [] },
        { headers: corsHeaders },
      );
    }

    const accessToken = await getGoogleAccessToken();
    const data = Object.fromEntries(
      Object.entries(body.data ?? {}).map(([key, value]) => [key, String(value)]),
    );

    const results = await Promise.all(tokens.map(async (token) => ({
      token,
      ...(await sendToToken(accessToken, token, title, messageBody, data)),
    })));

    return Response.json(
      {
        ok: true,
        sent: results.filter((result) => result.ok).length,
        failed: results.filter((result) => !result.ok).length,
        results,
      },
      { headers: corsHeaders },
    );
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : String(error) },
      { status: 500, headers: corsHeaders },
    );
  }
});
