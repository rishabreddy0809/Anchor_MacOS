/** @type {import('next').NextConfig} */

// Marketing site only. Deploys to its own Vercel project, separate from the
// Zoom OAuth bounce page in ../oauth-bounce.
//
// Keep it that way. The two were briefly merged into one project so that
// anchor-oauth-bounce.vercel.app could serve both, and the first deploy took
// Zoom sign-in down: the project had been created from a static folder, so
// Vercel had framework "Other" / output directory `public` saved, served
// public/ raw, and /oauth/zoom 404'd. It was recoverable, but the failure mode
// is the point — a routine marketing deploy could break every teacher's
// sign-in, and this site will be redeployed far more often than that page.
//
// If they ever are merged again: pin `"framework": "nextjs"` in vercel.json,
// re-add the /oauth/zoom rewrite *and* its four headers (no-store,
// no-referrer, nosniff, CSP — the authorization code travels in that URL),
// deploy a preview first, and verify with
// `vercel curl <preview>/oauth/zoom` before promoting.

const nextConfig = {};

export default nextConfig;
