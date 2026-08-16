/**
 * A small in-memory sliding-window rate limiter for the pilot form.
 *
 * What this is for
 * ----------------
 * `submitPilotApplication` turns an anonymous POST into an email. Without a
 * limit, anyone who finds the endpoint can flood the inbox the pilot is run
 * from and burn the Resend quota, and the honeypot only stops bots naive
 * enough to fill every field. This makes that cost real without putting a
 * CAPTCHA in front of a teacher.
 *
 * What this is not
 * ----------------
 * The state lives in the module scope of one server instance. Vercel's Fluid
 * Compute reuses instances across requests, so in practice a burst from one
 * source is very likely to meet the same counter — but it is not guaranteed,
 * and it resets on redeploy or scale-out. That is the right trade for a pilot
 * whose store of record is an inbox: it stops casual abuse with no extra
 * infrastructure. If the programme outgrows the inbox, move both this and the
 * submissions into shared storage at the same time; until then a durable
 * limiter would be more moving parts than the thing it protects.
 *
 * Two windows are enforced. The per-IP window stops one source hammering the
 * form; the global window caps total sends per hour whatever the source, so a
 * distributed flood still cannot empty the Resend quota in one go.
 */

type Window = { limit: number; windowMs: number };

const envLimit = (name: string, fallback: number): number => {
  const raw = Number(process.env[name]);
  return Number.isFinite(raw) && raw > 0 ? raw : fallback;
};

/** Per-IP. Generous enough that a teacher who mistypes their email and
 *  resubmits twice is never blocked. */
const PER_IP: Window = { limit: envLimit("PILOT_LIMIT_PER_IP", 5), windowMs: 60 * 60 * 1000 };

/**
 * Whole-site hourly ceiling.
 *
 * Originally 60, sized for "the first group is 10 teachers". That is the wrong
 * number the moment the form is linked from a LinkedIn or Reddit post: a
 * thread that lands can send more than 60 genuine applicants in an hour, and
 * they would have been turned away with a rate-limit message. Raised to a
 * level a real launch spike will not reach, while still capping a flood.
 */
const GLOBAL_HOURLY: Window = {
  limit: envLimit("PILOT_LIMIT_HOURLY", 150),
  windowMs: 60 * 60 * 1000,
};

/**
 * Whole-site daily ceiling, and the one that actually protects the mail path.
 *
 * Resend's free tier allows 100 emails/day. Past that Resend rejects the send
 * itself, which surfaces to the teacher as "we couldn't send that just now"
 * and drops the application. Stopping just short means the failure is ours and
 * legible — the message points them at the contact address — rather than an
 * opaque provider rejection. Raise `PILOT_LIMIT_DAILY` if the Resend plan
 * changes; nothing else has to move.
 */
const GLOBAL_DAILY: Window = {
  limit: envLimit("PILOT_LIMIT_DAILY", 90),
  windowMs: 24 * 60 * 60 * 1000,
};

const hits = new Map<string, number[]>();

/** Stop the map growing without bound on a long-lived instance. */
const MAX_TRACKED_KEYS = 5_000;

function record(key: string, window: Window, now: number): boolean {
  const cutoff = now - window.windowMs;
  const recent = (hits.get(key) ?? []).filter((t) => t > cutoff);

  if (recent.length >= window.limit) {
    hits.set(key, recent);
    return false;
  }

  recent.push(now);
  hits.set(key, recent);
  return true;
}

/** Drops keys whose entries have all aged out. O(n) but only on overflow. */
function evictStale(now: number): void {
  if (hits.size <= MAX_TRACKED_KEYS) return;
  const cutoff = now - Math.max(PER_IP.windowMs, GLOBAL_HOURLY.windowMs, GLOBAL_DAILY.windowMs);
  for (const [key, times] of hits) {
    if (times.every((t) => t <= cutoff)) hits.delete(key);
  }
}

export type RateLimitResult = { ok: true } | { ok: false; retryAfterMinutes: number };

/**
 * Records one attempt from `ip`. The global counter is only charged once the
 * per-IP check passes, so a single blocked source cannot exhaust the
 * site-wide budget on everyone else's behalf.
 */
export function checkRateLimit(ip: string): RateLimitResult {
  const now = Date.now();
  evictStale(now);

  if (!record(`ip:${ip}`, PER_IP, now)) {
    return { ok: false, retryAfterMinutes: Math.ceil(PER_IP.windowMs / 60_000) };
  }
  if (!record("global:hour", GLOBAL_HOURLY, now)) {
    return { ok: false, retryAfterMinutes: Math.ceil(GLOBAL_HOURLY.windowMs / 60_000) };
  }
  if (!record("global:day", GLOBAL_DAILY, now)) {
    return { ok: false, retryAfterMinutes: Math.ceil(GLOBAL_DAILY.windowMs / 60_000) };
  }
  return { ok: true };
}

/** Test seam — the module-scope counters otherwise persist across cases. */
export function resetRateLimit(): void {
  hits.clear();
}
