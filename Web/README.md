# Web — the Zoom OAuth bounce page

One static page. Zoom will not honour an `http://` loopback redirect (see
ZOOM_INTEGRATION.md §2a), so Anchor registers an **HTTPS** URL instead and this
page forwards `code` and `state` to `http://127.0.0.1:51789/oauth/zoom`, where
`LoopbackRedirectListener` catches it exactly as before.

```
Web/
  vercel.json                 rewrite /oauth/zoom → the page, plus no-store/CSP headers
  oauth-zoom-bounce.html      the page itself
  deploy.sh                   deploy, verify, and sync ZoomOAuthConfig.bounceURL
```

## Current state (2026-08-08)

Live and registered. Nothing needs doing unless the URL moves.

| | |
|---|---|
| Redirect URL | `https://anchor-oauth-bounce.vercel.app/oauth/zoom` |
| Vercel project | `rishabreddy0809s-projects/anchor-oauth-bounce` |
| `ZoomOAuthConfig.bounceURL` | matches |
| Marketplace app | registered in **both** OAuth Redirect URL and OAuth allow list, Development tab |

Verified: Zoom's consent screen renders for this URL, and an unregistered URL on
the same host still returns `Invalid redirect URL` — so the check is passing,
not being skipped.

## Redeploy

```bash
./deploy.sh
```

It deploys with `--prod`, checks the page really serves and still points at the
loopback listener, and only then rewrites `ZoomOAuthConfig.bounceURL` to match.
If any check fails it leaves the constant alone rather than pointing the app at
a broken URL.

Two things that will bite otherwise:

- **`--prod`, never a preview.** Previews get a fresh URL every push, and Zoom
  matches the registered redirect character for character.
- **The deployment-specific URL is not public.** Vercel's Deployment Protection
  puts it behind an SSO login; only the production alias
  (`anchor-oauth-bounce.vercel.app`) is reachable by teachers. Test that one.

## If the URL ever moves

Both ends must agree, character for character:

1. `ZoomOAuthConfig.bounceURL` in `Anchor/Services/OAuth/ZoomOAuthHandler.swift`
   — `deploy.sh` does this for you.
2. The Marketplace app's **OAuth Redirect URL** *and* its **OAuth allow list**
   entry, on the **Development** credentials tab. Setting only one of the two
   fields fails with the same unhelpful `Invalid redirect URL`.

To serve it from `anchor-app.com` instead, add that domain to the Vercel project
and point its DNS there. The domain currently serves a GoDaddy Website Builder
site, so this would take over the apex — use a subdomain if that site is wanted.

## Verifying by hand

```bash
curl -si 'https://anchor-oauth-bounce.vercel.app/oauth/zoom?code=probe&state=probe' | head -20
```

Expect `200`, `cache-control: no-store`, and HTML referencing `127.0.0.1:51789`.
The page forwards only `code`, `state`, `error` and `error_description`;
anything else in the query string is dropped rather than relayed onward.

The authorization code passes through this page. Keep it static — no analytics,
no tag managers, no third-party scripts, since any of them could read the code
out of the URL. It is single-use and PKCE-bound, so interception alone does not
yield tokens, but there is no reason to widen the window.
