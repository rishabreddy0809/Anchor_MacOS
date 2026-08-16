import { createFileRoute } from "@tanstack/react-router";

import { LegalPage, LegalSectionBody, type LegalSection } from "@/components/LegalPage";
import { CONTACT_EMAIL, LEGAL_NAME, MIN_MACOS, absoluteUrl } from "@/lib/site";

/**
 * Support page.
 *
 * Exists because the Zoom Marketplace listing requires a Support URL, and a
 * reviewer will open it. Before this page, that field pointed at the homepage,
 * which showed no way to get help — a listing whose support link goes nowhere
 * useful is a review risk.
 *
 * Reuses the legal page layout rather than inventing a second one: the audience
 * is the same (a teacher deciding whether to trust this, or a reviewer checking
 * it is real) and the contents list makes it skimmable.
 */
export const Route = createFileRoute("/support")({
  head: () => ({
    meta: [
      { title: "Support — Anchor" },
      {
        name: "description",
        content:
          "How to get help with Anchor: what to send, where to send it, and what to check first for the most common problems.",
      },
      { property: "og:title", content: "Support — Anchor" },
      { property: "og:type", content: "article" },
    ],
    links: [{ rel: "canonical", href: absoluteUrl("/support") }],
  }),
  component: Support,
});

const SECTIONS: LegalSection[] = [
  { id: "contact", heading: "Getting help" },
  { id: "include", heading: "What to include" },
  { id: "common", heading: "Common problems" },
  { id: "privacy", heading: "What not to send" },
  { id: "scope", heading: "Response times" },
];

function Support() {
  return (
    <LegalPage
      title="Support"
      summary="Anchor is maintained by one person. Email is the only support channel, and it is read."
      sections={SECTIONS}
    >
      <LegalSectionBody id="contact" index={1} heading="Getting help">
        <p>
          Email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>. That address reaches{" "}
          {LEGAL_NAME} directly — there is no ticketing system and no bot in front of it.
        </p>
        <p>
          The same address handles bug reports, questions about the pilot, privacy questions, and
          requests to remove your data.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="include" index={2} heading="What to include">
        <p>Most problems are diagnosable from four things:</p>
        <ul>
          <li>What you were doing, and what happened instead.</li>
          <li>Your macOS version, and whether Anchor was updated recently.</li>
          <li>
            Whether Zoom shows as connected in <strong>Settings → Zoom</strong>.
          </li>
          <li>The exact wording of any error message.</li>
        </ul>
      </LegalSectionBody>

      <LegalSectionBody id="common" index={3} heading="Common problems">
        <p>
          <strong>Anchor will not connect to Zoom.</strong> Anchor is in a limited pilot, so only
          approved Zoom accounts can authorize it. If sign-in ends on a Zoom page saying you cannot
          authorize the app, your account has not been added yet — email us rather than retrying.
        </p>
        <p>
          <strong>The bot does not join the meeting.</strong> Anchor only joins after you answer
          yes to the monitoring prompt, and only for meetings you host. It cannot join a meeting
          hosted by somebody else.
        </p>
        <p>
          <strong>Some panels stay empty.</strong> A few live signals come from Zoom endpoints that
          require a Business, Education or Enterprise plan. On a Free or Pro plan Anchor keeps
          running on the signals it can see and says so rather than showing nothing.
        </p>
        <p>
          <strong>Anchor will not launch.</strong> Anchor needs {MIN_MACOS} or later.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="privacy" index={4} heading="What not to send">
        <p>
          Please do not email student names, student work, class rosters, or screenshots containing
          them. Nothing about your class is needed to debug a problem, and Anchor is built so that
          this data never leaves your Mac in the first place — sending it to support would defeat
          that. Describe the problem instead, and redact any screenshot before attaching it.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="scope" index={5} heading="Response times">
        <p>
          Anchor is a free pilot maintained by one person, so there is no guaranteed response time.
          In practice, email is answered within a few days. If something is actively blocking a
          lesson, say so in the subject line.
        </p>
      </LegalSectionBody>
    </LegalPage>
  );
}
