import "./lib/error-capture";

import { consumeLastCapturedError } from "./lib/error-capture";
import { renderErrorPage } from "./lib/error-page";
import { handleSdkTokenRequest } from "./lib/zoom-sdk-token";

/**
 * Endpoints answered here rather than by the router.
 *
 * TanStack Start at the version pinned here exposes `createServerFn` — an RPC
 * transport for the site's own client — and no file-based server-route API.
 * The Anchor macOS app is not that client: it needs a plain HTTP endpoint it
 * can POST to with an `Authorization` header. This file is already the fetch
 * entry point for every request, which makes it the one place such a route can
 * live without fighting the framework, and it inherits the security headers
 * below for free.
 */
const API_ROUTES: Record<string, (request: Request) => Promise<Response>> = {
  "/api/zoom/sdk-token": handleSdkTokenRequest,
};

type ServerEntry = {
  fetch: (request: Request, env: unknown, ctx: unknown) => Promise<Response> | Response;
};

let serverEntryPromise: Promise<ServerEntry> | undefined;

async function getServerEntry(): Promise<ServerEntry> {
  if (!serverEntryPromise) {
    serverEntryPromise = import("@tanstack/react-start/server-entry").then(
      (m) => (m.default ?? m) as ServerEntry,
    );
  }
  return serverEntryPromise;
}

// h3 swallows in-handler throws into a normal 500 Response with body
// {"unhandled":true,"message":"HTTPError"} — try/catch alone never fires for those.
async function normalizeCatastrophicSsrResponse(response: Response): Promise<Response> {
  if (response.status < 500) return response;
  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) return response;

  const body = await response.clone().text();
  if (!isH3SwallowedErrorBody(body)) return response;

  console.error(consumeLastCapturedError() ?? new Error(`h3 swallowed SSR error: ${body}`));
  return new Response(renderErrorPage(), {
    status: 500,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

function isH3SwallowedErrorBody(body: string): boolean {
  try {
    const payload = JSON.parse(body) as { unhandled?: unknown; message?: unknown };
    return payload.unhandled === true && payload.message === "HTTPError";
  } catch {
    return false;
  }
}

/**
 * Security headers applied to every response this worker produces.
 *
 * This is the right place for them rather than a `vercel.json`: nitro emits a
 * Build Output API v3 config (`.vercel/output/config.json`) whose routes send
 * everything off the filesystem to `/__server`, and that generated config —
 * not a hand-written vercel.json — is what Vercel honours. Every HTML document
 * and every server function response passes through the handler below, so
 * setting them here covers exactly the responses that matter. Static assets
 * under `/assets/*` are served straight from the filesystem and never reach
 * this code; they are immutable hashed JS/CSS, and none of these headers
 * changes how a browser treats them.
 *
 * Deliberately NOT a full Content-Security-Policy. A real one here would have
 * to allow the Google Fonts stylesheet and font files, React's injected
 * `data-precedence` stylesheets, and TanStack Start's inline hydration script —
 * which in practice means `'unsafe-inline'` for scripts, at which point the
 * policy buys close to nothing while being able to white-screen the site if a
 * single source is missed. `frame-ancestors` is the one directive that is
 * unambiguously safe to set alone: it constrains who may embed the page and
 * nothing about what the page may load.
 */
const SECURITY_HEADERS: Record<string, string> = {
  // Stop a browser second-guessing a declared content type.
  "x-content-type-options": "nosniff",
  // Clickjacking. frame-ancestors is the modern form and wins where both are
  // understood; X-Frame-Options stays for older browsers that ignore CSP.
  "content-security-policy": "frame-ancestors 'none'",
  "x-frame-options": "DENY",
  // Send the full URL same-origin, bare origin cross-origin. Keeps the path of
  // a page a teacher was on out of third-party referer logs.
  "referrer-policy": "strict-origin-when-cross-origin",
  // The landing page asks for none of these. Denying them means an injected
  // iframe or script cannot prompt a teacher for hardware access in our name.
  "permissions-policy": "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
};

/**
 * Returns `response` with the headers above applied.
 *
 * Rebuilt rather than mutated: a Response handed back from another handler can
 * have immutable headers, and assigning to them throws. Passing `body` through
 * preserves a streamed SSR response — but 204/304 must be reconstructed with a
 * null body or the Response constructor rejects it.
 */
function withSecurityHeaders(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
    headers.set(name, value);
  }
  const bodyless = response.status === 204 || response.status === 304;
  return new Response(bodyless ? null : response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export default {
  async fetch(request: Request, env: unknown, ctx: unknown) {
    try {
      // Checked before the SSR handler: the router would answer an unknown
      // path with the site's 404 page, so an API route reaching it at all
      // would surface as HTML where the app expects JSON.
      const apiRoute = API_ROUTES[new URL(request.url).pathname];
      if (apiRoute) {
        return withSecurityHeaders(await apiRoute(request));
      }

      const handler = await getServerEntry();
      const response = await handler.fetch(request, env, ctx);
      return withSecurityHeaders(await normalizeCatastrophicSsrResponse(response));
    } catch (error) {
      console.error(error);
      return withSecurityHeaders(
        new Response(renderErrorPage(), {
          status: 500,
          headers: { "content-type": "text/html; charset=utf-8" },
        }),
      );
    }
  },
};
