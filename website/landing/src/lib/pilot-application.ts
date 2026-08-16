import { createServerFn } from "@tanstack/react-start";
import { getRequestIP } from "@tanstack/react-start/server";
import { z } from "zod";

import { checkRateLimit } from "@/lib/rate-limit";
import { CONTACT_EMAIL } from "@/lib/site";

/**
 * The pilot application: schema, server function, and the mail it produces.
 *
 * The form is the only conversion path on the site, so it asks for exactly what
 * is needed to decide whether a teacher can run Anchor at all (Mac, Zoom,
 * permission) plus enough context to prioritise. Anything more is friction.
 *
 * There is no database. A submission becomes one email to CONTACT_EMAIL — for a
 * pilot of a few dozen teachers an inbox is the right store, and it means no
 * teacher or student detail is persisted on a server we own. If the programme
 * outgrows that, add storage here and nothing above has to change.
 *
 * The schema deliberately uses no `.default()` or `.transform()`, so the parsed
 * type and the form's field types are identical and react-hook-form needs no
 * casts.
 */

/** Checkboxes that are hard gates rather than preferences. */
const mustBeTicked = (message: string) => z.boolean().refine((v) => v, { message });

export const pilotApplicationSchema = z.object({
  name: z.string().trim().min(2, "Please tell us your name.").max(120),
  email: z.string().trim().email("That doesn't look like an email address.").max(200),
  school: z.string().trim().min(2, "Which school or organization do you teach at?").max(200),
  teaches: z.string().trim().min(2, "Roughly what subject and grade do you teach?").max(200),
  classSize: z.string().trim().max(40),
  notes: z.string().trim().max(2000),
  usesClassroom: z.boolean(),
  hasMac: mustBeTicked("Anchor only runs on a Mac, so this one you really do need."),
  hasZoom: mustBeTicked("Anchor works by watching your live Zoom classes, so you'll need Zoom."),
  understandsConsent: mustBeTicked(
    "Please confirm you'll handle the permission your school asks for.",
  ),
  /**
   * Honeypot. Bots fill every field; humans never see this one.
   *
   * Deliberately unconstrained: the handler decides what to do with it. A
   * `.max(0)` here would reject the request during validation instead, which
   * both signals to the bot that it was caught and — worse — leaves a human
   * whose autofill touched the field with a form that silently refuses to
   * submit and no visible error to explain why.
   */
  website: z.string().optional(),
});

export type PilotApplication = z.infer<typeof pilotApplicationSchema>;

function renderApplication(a: PilotApplication): string {
  const rows: [string, string][] = [
    ["Name", a.name],
    ["Email", a.email],
    ["School", a.school],
    ["Teaches", a.teaches],
    ["Class size", a.classSize || "—"],
    ["Google Classroom", a.usesClassroom ? "yes" : "no"],
    ["Notes", a.notes || "—"],
  ];
  return rows.map(([k, v]) => `${k}: ${v}`).join("\n");
}

export const submitPilotApplication = createServerFn({ method: "POST" })
  .validator(pilotApplicationSchema)
  .handler(async ({ data }) => {
    // Silently accept the honeypot so a bot gets no signal it was caught.
    // Checked before the rate limit so obvious bot traffic never consumes the
    // budget a real teacher might need.
    if (data.website) return { ok: true as const };

    // xForwardedFor is trusted here because the only path to this function is
    // through Vercel's proxy, which overwrites the header rather than
    // appending to a client-supplied one.
    const ip = getRequestIP({ xForwardedFor: true }) ?? "unknown";
    const limit = checkRateLimit(ip);
    if (!limit.ok) {
      throw new Error(
        `That's a few too many applications from here at once. Please try again in ` +
          `${limit.retryAfterMinutes} minutes, or email ${CONTACT_EMAIL} directly.`,
      );
    }

    const apiKey = process.env["RESEND_API_KEY"];
    if (!apiKey) {
      // Losing an application to a config mistake is worse than a loud failure.
      console.error("RESEND_API_KEY is not set — pilot application dropped:", data.email);
      throw new Error(
        `The application form isn't connected yet. Please email ${CONTACT_EMAIL} instead.`,
      );
    }

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        // Resend only allows arbitrary from-addresses on a verified domain.
        // Until Anchor has one, onboarding@resend.dev delivers to the account owner.
        from: process.env["PILOT_FROM_EMAIL"] ?? "Anchor pilots <onboarding@resend.dev>",
        to: [CONTACT_EMAIL],
        reply_to: data.email,
        subject: `Pilot application — ${data.name}, ${data.school}`,
        text: renderApplication(data),
      }),
    });

    if (!response.ok) {
      console.error("Resend rejected a pilot application:", response.status, await response.text());
      throw new Error(
        `We couldn't send that just now. Please try again, or email ${CONTACT_EMAIL} directly.`,
      );
    }

    return { ok: true as const };
  });
