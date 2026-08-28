import { createFileRoute } from "@tanstack/react-router";

import { LegalPage, LegalSectionBody, type LegalSection } from "@/components/LegalPage";
import { CONTACT_EMAIL, MIN_MACOS, absoluteUrl } from "@/lib/site";

/**
 * Zoom-specific documentation.
 *
 * Exists because the Marketplace listing requires a Documentation URL, and Zoom
 * is specific about what it wants there: "a Zoom-specific guide hosted on your
 * domain that includes detailed instructions on adding, using and removing the
 * app." A link to the homepage does not satisfy it, and a reviewer opens it.
 *
 * Written for two readers at once, which is why the removal section is as long
 * as the setup one: a teacher looking for the answer to "how do I get this out
 * of my Zoom account", and a reviewer checking that answer exists and is honest.
 * Reuses the legal page layout for the same reason `support.tsx` does.
 */
export const Route = createFileRoute("/docs/zoom")({
  head: () => ({
    meta: [
      { title: "Anchor and Zoom: Setup Guide" },
      {
        name: "description",
        content:
          "How to connect Anchor to Zoom, what it reads during a class, and how to remove it completely.",
      },
      { property: "og:title", content: "Anchor and Zoom: Setup Guide" },
      { property: "og:type", content: "article" },
    ],
    links: [{ rel: "canonical", href: absoluteUrl("/docs/zoom") }],
  }),
  component: ZoomDocs,
});

const SECTIONS: LegalSection[] = [
  { id: "what", heading: "What the integration does" },
  { id: "before", heading: "Before you start" },
  { id: "add", heading: "Adding Anchor to Zoom" },
  { id: "using", heading: "Using it during a class" },
  { id: "permissions", heading: "What Anchor reads" },
  { id: "remove", heading: "Removing Anchor" },
  { id: "trouble", heading: "If something goes wrong" },
];

function ZoomDocs() {
  return (
    <LegalPage
      title="Anchor and Zoom"
      summary="Anchor is a Mac app that helps a teacher see who is struggling during a live class. This page covers connecting it to Zoom, what it reads, and how to remove it."
      sections={SECTIONS}
      eyebrow="Documentation"
      lastUpdated="August 28, 2026"
    >
      <LegalSectionBody id="what" index={1} heading="What the integration does">
        <p>
          Anchor runs on the teacher's Mac. It connects to Zoom so that, during a class, it can see
          who is in the meeting and how they are taking part: whether they are muted, whether their
          camera is on, whether they have raised a hand. It turns that into a per-student engagement
          reading the teacher can act on while the lesson is still happening.
        </p>
        <p>
          Anchor does not host meetings, schedule them, or change anything in your Zoom account. It
          reads. The analysis happens on the teacher's own computer.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="before" index={2} heading="Before you start">
        <ul>
          <li>A Mac running {MIN_MACOS} or later, with Anchor installed.</li>
          <li>
            A Zoom account you are allowed to connect. You approve the connection yourself. No
            administrator has to do it for you, and nothing is installed on any student's computer.
          </li>
          <li>
            Your students do not need Anchor, a Zoom app, or an account with us. They join the class
            exactly as they always do.
          </li>
        </ul>
        <p>
          Some features depend on your Zoom plan rather than on Anchor. Reading the participant list
          over Zoom's API requires a Business, Education or Enterprise plan; on Basic or Pro that
          data is not available to any app, and Anchor falls back to its in-meeting assistant. It
          says which of the two it is using rather than leaving a blank dashboard unexplained.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="add" index={3} heading="Adding Anchor to Zoom">
        <ol>
          <li>Open Anchor and go to <strong>Settings → Integrations</strong>.</li>
          <li>
            Click <strong>Connect Zoom</strong>. Anchor opens your browser. Nothing is typed into
            Anchor, and Anchor never sees your Zoom password.
          </li>
          <li>
            Sign in to Zoom if you are not already, and review the permissions Anchor is asking for.
            They are listed in full below.
          </li>
          <li>
            Click <strong>Allow</strong>. Your browser returns you to Anchor, and Settings shows the
            account you connected.
          </li>
        </ol>
        <p>
          You only do this once. Anchor keeps the connection in your Mac's Keychain and renews it
          quietly from then on.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="using" index={4} heading="Using it during a class">
        <p>
          Start your Zoom class as normal. Anchor notices the meeting and asks whether you want it to
          watch this one. It does not start on its own.
        </p>
        <p>
          When you say yes, an assistant named <strong>"Anchor (engagement assistant)"</strong> joins
          the meeting. It appears in the participant list like anyone else. It is never hidden, it
          has no camera or microphone of its own, and it does not record.
        </p>
        <p>
          While the class runs, Anchor shows a live reading for each student and flags the ones who
          look like they are drifting, so you can pull them back in the moment rather than find out
          from an assignment a week later. When the class ends, the assistant leaves.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="permissions" index={5} heading="What Anchor reads">
        <p>Anchor asks Zoom for the narrowest set of permissions that lets it work:</p>
        <ul>
          <li>
            <strong>View your meetings</strong>, to find the class that is running now. Anchor has
            no meetings of its own.
          </li>
          <li>
            <strong>View your user information</strong>, to know which account is connected, and so
            that you are not counted as a student in your own class.
          </li>
          <li>
            <strong>Join a meeting on your behalf</strong>, so the assistant joins as you rather
            than as an anonymous guest.
          </li>
          <li>
            <strong>View meeting participants</strong> <em>(optional)</em>, the live participant
            list. Only available on Business, Education and Enterprise plans; Anchor works without
            it.
          </li>
        </ul>
        <p>
          <strong>What Anchor never does:</strong> it does not record audio or video, does not
          analyse video, does not read your cloud recordings, does not post or send anything, and
          does not change any Zoom setting. Engagement readings and class history stay on your Mac
          and are not sent to us.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="remove" index={6} heading="Removing Anchor">
        <p>There are two steps, and they do different things.</p>
        <p>
          <strong>1. Disconnect inside Anchor.</strong> Settings → Integrations → Zoom →{" "}
          <strong>Disconnect</strong>. Anchor tells Zoom to revoke the connection and deletes its
          copy from your Mac's Keychain immediately.
        </p>
        <p>
          <strong>2. Remove the app from your Zoom account.</strong> Sign in at{" "}
          <a href="https://marketplace.zoom.us" target="_blank" rel="noreferrer">
            marketplace.zoom.us
          </a>
          , go to <strong>Manage → Added Apps</strong>, find <strong>Anchor</strong>, and click{" "}
          <strong>Remove</strong>. This is the step that clears Anchor out of your Zoom account for
          good.
        </p>
        <p>
          Either step alone stops Anchor reading anything from Zoom. Doing both leaves nothing
          behind on Zoom's side.
        </p>
        <p>
          Class history already recorded stays on your Mac, because it is yours. Anchor never
          uploaded it. To delete that too, use Settings → Data &amp; Privacy inside Anchor, or drag
          the app to the Trash.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="trouble" index={7} heading="If something goes wrong">
        <p>
          <strong>"You cannot authorize this app."</strong> Zoom shows this when the app is not
          available to your account yet. Email us and we will tell you where it stands.
        </p>
        <p>
          <strong>The dashboard is empty during a class.</strong> Usually the assistant has not
          joined. Check the Zoom participant list for "Anchor (engagement assistant)". If it is not
          there, Anchor's Settings → Integrations panel says why.
        </p>
        <p>
          <strong>Zoom says the connection expired.</strong> Disconnect and connect again in Settings
          → Integrations. Nothing on your Mac is lost by reconnecting.
        </p>
        <p>
          Anything else: email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>. It reaches a
          person.
        </p>
      </LegalSectionBody>
    </LegalPage>
  );
}
