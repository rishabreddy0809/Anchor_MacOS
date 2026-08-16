/**
 * Single source of truth for site-wide constants.
 *
 * SITE_URL is used for canonical tags, the sitemap and absolute og:image URLs.
 * Social scrapers and Google OAuth verification both reject relative URLs, so
 * this has to be the real origin.
 *
 * This is the production alias Vercel assigns the project. Point it at a custom
 * domain once there is one — everything that needs the origin reads it from
 * here, so changing this one line updates the canonical tags, the OG tags and
 * `scripts/sitemap.mjs` output. Re-run `npm run sitemap` after changing it.
 */
export const SITE_URL = "https://anchorteach.vercel.app";

export const CONTACT_EMAIL = "rishabreddy0809@gmail.com";

/**
 * The person the legal documents are an agreement with.
 *
 * Anchor is not a company, so the counterparty is an individual. This name
 * appears in the Terms, the Pilot Program Terms and the Privacy Policy — change
 * it here and all three follow.
 */
export const LEGAL_NAME = "Rishab Reddy Paili";

/** Shown on the legal pages. Bump when any of them changes materially. */
export const LEGAL_LAST_UPDATED = "August 13, 2026";

/** Minimum macOS version, from MACOSX_DEPLOYMENT_TARGET in the Xcode project. */
export const MIN_MACOS = "macOS 26.5";

export const MAILTO_PILOT = `mailto:${CONTACT_EMAIL}?subject=Anchor%20pilot%20program`;

/**
 * What a teacher must already have before Anchor can run for them at all.
 *
 * These are hard gates, not preferences — a teacher on Windows or on an older
 * macOS cannot take part. They are shown next to the application form so nobody
 * fills it in and finds out afterwards.
 */
export const REQUIREMENTS: { need: string; detail: string }[] = [
  {
    need: `A Mac running ${MIN_MACOS} or later`,
    detail: "Anchor runs on your computer, not ours.",
  },
  {
    need: "A Zoom account you're allowed to connect",
    detail: "You approve it once. Your students don't install anything.",
  },
  {
    need: "Permission to use it in your classroom",
    detail: "Whatever your school or district requires you to get.",
  },
  {
    need: "Optional: Google Classroom and Apple Intelligence",
    detail:
      "Google Classroom adds grades and assignments to what Anchor sees. Apple Intelligence runs the lesson assistant.",
  },
];

/**
 * The terms of the pilot programme, summarised for the landing page. The full
 * version is the Pilot Program Terms at /pilot-terms — keep the two in step.
 *
 * `value: null` renders a loud, unmissable placeholder rather than a number, so
 * the page can ship without promising a teacher something that has not been
 * decided. Fill the string in and the placeholder disappears — nothing else has
 * to change. `PILOT_TERMS_SETTLED` below is derived, not maintained by hand.
 */
export const PILOT_TERMS: { label: string; value: string | null; hint: string }[] = [
  { label: "How long", value: "6 weeks", hint: "how many weeks a group runs" },
  {
    label: "Spots",
    value: "10 teachers in the first group",
    hint: "how many teachers you can support at once",
  },
  {
    label: "What you do",
    value: "Teach two live classes a week, then one 30-minute call at the end",
    hint: "classes per week, plus any feedback call at the end",
  },
  {
    label: "When it starts",
    value: "A new group starts as soon as the last one fills up",
    hint: "when the first group begins",
  },
  {
    label: "What it costs",
    value: "Nothing. You're never charged automatically, or without being asked first",
    hint: "what access and price become",
  },
];

/** True once every term above has a real value. Drives the "not final" notice. */
export const PILOT_TERMS_SETTLED = PILOT_TERMS.every((t) => t.value !== null);

export function absoluteUrl(path: string): string {
  return new URL(path, SITE_URL).toString();
}
