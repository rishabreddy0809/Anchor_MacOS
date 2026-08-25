/**
 * Server-side Meeting SDK token signing.
 *
 * ── Why this exists ─────────────────────────────────────────────────────────
 *
 * The Zoom Meeting SDK authenticates the *app* with an HS256 JWT signed by the
 * SDK Key/Secret. Anchor has always signed that token on the Mac
 * (`MeetingSDKTokenProvider.token()`), which means the secret has to be on the
 * machine — and `ship-checklist.md:136` is right that shipping it is
 * unacceptable:
 *
 *   > the secret is a signing key, not an identifier: anyone who extracts it
 *   > from a shipped binary can mint Meeting SDK tokens as Anchor.
 *
 * That left per-school (an admin provisions the secret once, in Terminal) as
 * the only account model with a working bot, and the bot is the only live
 * signal an individual teacher could ever have — participant REST scopes are
 * gated on the *installing user's* Business/Education plan, which a lone
 * teacher does not have.
 *
 * So this endpoint is the third option `ship-checklist.md:138` was missing when
 * it framed the choice as "ship an extractable signing key or ship no bot".
 * `ZOOM_INTEGRATION.md:145` already named it: a server-side signing endpoint,
 * the standard Meeting SDK architecture. The secret lives in Vercel's
 * environment, never in the app.
 *
 * ── What this endpoint does NOT receive ─────────────────────────────────────
 *
 * No student data. No roster, no scores, no transcript, not even a meeting
 * number — the native macOS SDK token authenticates the app rather than a
 * meeting, so the claim set is `appKey`/`iat`/`exp`/`tokenExp` and nothing
 * else. The only thing crossing the wire is a Zoom access token belonging to
 * the teacher, used to prove they are entitled to ask, and it is never stored.
 *
 * ── Why a Zoom token is the right gate ──────────────────────────────────────
 *
 * Anyone holding a signed SDK token can authenticate to the Meeting SDK as
 * Anchor, so this must not be an open minting service. The natural boundary is
 * already available: every teacher who can use the bot has necessarily
 * authorized Anchor's Zoom app, so they hold a Zoom access token. Verifying it
 * against Zoom costs one request and proves exactly the right thing.
 *
 * Deliberately NOT gated on a Firebase account instead. That would work too,
 * but it would make the bot depend on account setup that is optional today, and
 * it proves a weaker fact — that someone signed into Anchor, not that they hold
 * a live Zoom grant. Layering Firebase on top later is additive.
 */

const ZOOM_USER_ENDPOINT = "https://api.zoom.us/v2/users/me";

/** Zoom requires `exp` between 30 minutes and 48 hours out; `tokenExp` >= `exp`. */
const TOKEN_LIFETIME_SECONDS = 2 * 60 * 60;

export type SdkTokenResult =
  | { ok: true; token: string; expiresAt: number }
  | { ok: false; status: number; error: string };

/**
 * Per-teacher throttle, keyed by Zoom user id.
 *
 * Keyed by user rather than IP on purpose: teachers at one school share an
 * outbound address, and rate limiting them as a group would punish exactly the
 * per-school deployments that already work. Tokens last two hours, so a
 * legitimate client asks for one a handful of times a day at most.
 *
 * In-memory, and therefore per-instance — the same honest limitation
 * `rate-limit.ts` documents for the pilot form. It stops a stuck client
 * hammering the endpoint; it is not a defence against a distributed attacker,
 * and the Zoom-token check above is what actually guards the secret.
 */
const MINTS_PER_USER_PER_HOUR = 10;
const WINDOW_MS = 60 * 60 * 1000;
const mints = new Map<string, number[]>();

function withinRateLimit(userId: string, now: number): boolean {
  const cutoff = now - WINDOW_MS;
  const recent = (mints.get(userId) ?? []).filter((t) => t > cutoff);
  if (recent.length >= MINTS_PER_USER_PER_HOUR) {
    mints.set(userId, recent);
    return false;
  }
  recent.push(now);
  mints.set(userId, recent);

  // Bound the map so a long-lived instance cannot grow without limit.
  if (mints.size > 5_000) {
    for (const [key, times] of mints) {
      if (times.every((t) => t <= cutoff)) mints.delete(key);
    }
  }
  return true;
}

/** Test seam — module-scope counters otherwise persist across cases. */
export function resetSdkTokenRateLimit(): void {
  mints.clear();
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlEncodeJson(value: Record<string, unknown>): string {
  // Sorted keys keep the output deterministic, so a test can check the token
  // against an independently computed signature — the same reason
  // MeetingSDKTokenProvider passes `.sortedKeys`.
  const sorted = Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)));
  return base64UrlEncode(new TextEncoder().encode(JSON.stringify(sorted)));
}

/**
 * Signs the Meeting SDK JWT.
 *
 * The claim set mirrors `MeetingSDKTokenProvider.token()` exactly, including
 * what it leaves out. `mn` and `role` belong to the *Web* SDK signature; the
 * native macOS SDK rejects a token carrying them, and `sdkKey` is a deprecated
 * alias for `appKey`. Getting this wrong fails inside `sdkAuth` with an error
 * that names the credential, which is indistinguishable from a wrong secret.
 */
export async function signMeetingSdkToken(
  sdkKey: string,
  sdkSecret: string,
  issuedAtSeconds: number = Math.floor(Date.now() / 1000),
): Promise<{ token: string; expiresAt: number }> {
  const exp = issuedAtSeconds + TOKEN_LIFETIME_SECONDS;

  const header = base64UrlEncodeJson({ alg: "HS256", typ: "JWT" });
  const payload = base64UrlEncodeJson({
    appKey: sdkKey,
    iat: issuedAtSeconds,
    exp,
    tokenExp: exp,
  });
  const signingInput = `${header}.${payload}`;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(sdkSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signingInput));

  return {
    token: `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`,
    expiresAt: exp,
  };
}

/**
 * Confirms the bearer token is a live Zoom grant and returns the user's id.
 *
 * Returns the id only. The response also carries the teacher's name and email
 * address, and neither is read, logged or returned — this endpoint has no use
 * for them, and the privacy policy's claim about what leaves a Mac should stay
 * true of the server too.
 */
async function verifyZoomToken(accessToken: string): Promise<string | null> {
  let response: Response;
  try {
    response = await fetch(ZOOM_USER_ENDPOINT, {
      headers: { authorization: `Bearer ${accessToken}` },
    });
  } catch {
    return null;
  }
  if (!response.ok) return null;

  const body = (await response.json().catch(() => null)) as { id?: unknown } | null;
  return typeof body?.id === "string" && body.id.length > 0 ? body.id : null;
}

/**
 * Handles `POST /api/zoom/sdk-token`.
 *
 * Fails closed. With no `ZOOM_MEETING_SDK_KEY`/`_SECRET` in the environment it
 * returns 503 rather than a token — a deployment that forgot to provision them
 * must not look like one that is working.
 */
export async function handleSdkTokenRequest(request: Request): Promise<Response> {
  if (request.method !== "POST") {
    return json({ error: "Use POST." }, 405, { allow: "POST" });
  }

  const sdkKey = readEnv("ZOOM_MEETING_SDK_KEY");
  const sdkSecret = readEnv("ZOOM_MEETING_SDK_SECRET");
  if (!sdkKey || !sdkSecret) {
    console.error("ZOOM_MEETING_SDK_KEY/SECRET are not set — SDK token signing is disabled.");
    return json({ error: "Anchor's meeting bot is not configured on this server." }, 503);
  }

  const header = request.headers.get("authorization") ?? "";
  const bearer = /^Bearer\s+(.+)$/i.exec(header.trim())?.[1];
  if (!bearer) {
    return json({ error: "Missing Zoom authorization." }, 401);
  }

  const zoomUserId = await verifyZoomToken(bearer);
  if (!zoomUserId) {
    return json({ error: "That Zoom sign-in is no longer valid. Reconnect Zoom and try again." }, 401);
  }

  if (!withinRateLimit(zoomUserId, Date.now())) {
    return json({ error: "Too many token requests. Try again in an hour." }, 429, {
      "retry-after": "3600",
    });
  }

  const { token, expiresAt } = await signMeetingSdkToken(sdkKey, sdkSecret);
  return json({ token, expiresAt }, 200);
}

function readEnv(name: string): string | undefined {
  const value = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process
    ?.env?.[name];
  return value && value.trim().length > 0 ? value.trim() : undefined;
}

function json(body: unknown, status: number, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      // Never cached anywhere: the response is a short-lived credential.
      "cache-control": "no-store",
      ...extraHeaders,
    },
  });
}
