import { createFileRoute } from "@tanstack/react-router";

import { LegalPage, LegalSectionBody, type LegalSection } from "@/components/LegalPage";
import { CONTACT_EMAIL, LEGAL_NAME, MIN_MACOS, absoluteUrl } from "@/lib/site";

export const Route = createFileRoute("/privacy")({
  head: () => ({
    meta: [
      { title: "Privacy Policy — Anchor" },
      {
        name: "description",
        content:
          "How Anchor handles teacher and student data. Anchor runs entirely on the teacher's Mac; student data is never transmitted to Anchor.",
      },
      { property: "og:title", content: "Privacy Policy — Anchor" },
      { property: "og:type", content: "article" },
    ],
    links: [{ rel: "canonical", href: absoluteUrl("/privacy") }],
  }),
  component: Privacy,
});

const SECTIONS: LegalSection[] = [
  { id: "summary", heading: "The short version" },
  { id: "who", heading: "Who we are" },
  { id: "zoom", heading: "What Anchor observes in a Zoom class" },
  { id: "classroom", heading: "What Anchor reads from Google Classroom" },
  { id: "storage", heading: "Where the data lives" },
  { id: "transmission", heading: "What leaves your Mac" },
  { id: "ai", heading: "How the models work" },
  { id: "students", heading: "Student data, FERPA and children" },
  { id: "responsibilities", heading: "Your responsibilities as the teacher" },
  { id: "retention", heading: "Retention and deletion" },
  { id: "rights", heading: "Your rights" },
  { id: "changes", heading: "Changes to this policy" },
  { id: "contact", heading: "Contact" },
];

function Privacy() {
  return (
    <LegalPage
      title="Privacy Policy"
      summary="Anchor runs on your Mac. Student data is processed there and is never sent to us — we operate no server that could receive it."
      sections={SECTIONS}
    >
      <LegalSectionBody id="summary" index={1} heading="The short version">
        <p>This summary is not a substitute for the sections below, but it is accurate.</p>
        <ul>
          <li>
            <strong>Anchor has no backend.</strong> There is no Anchor server, account system or
            database. Nothing you or your students do in Anchor is transmitted to us.
          </li>
          <li>
            <strong>We never receive student data.</strong> Not names, not grades, not speech, not
            engagement scores. It is technically impossible for us to, because the app never sends
            it anywhere.
          </li>
          <li>
            <strong>No video is analysed and no facial recognition is used.</strong> Anchor reads
            whether a camera is on or off — a true/false flag from Zoom — and never looks at the
            picture.
          </li>
          <li>
            <strong>Speech is never written to disk.</strong> Live captions are held in memory
            during a class, in a bounded window, and are discarded when the meeting ends.
          </li>
          <li>
            <strong>No analytics, no telemetry, no advertising, no data sales.</strong> Anchor
            contains no third-party tracking of any kind.
          </li>
        </ul>
      </LegalSectionBody>

      <LegalSectionBody id="who" index={2} heading="Who we are">
        <p>
          Anchor is a macOS application built and operated by an individual developer,{" "}
          <strong>{LEGAL_NAME}</strong> ("Anchor", "we", "us"), reachable at{" "}
          <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
        </p>
        <p>
          This policy covers the Anchor macOS application and this website. Because Anchor processes
          data only on your own computer, for most purposes under data protection law{" "}
          <strong>you — or your school — are the data controller</strong>, and Anchor is software
          you run rather than a service that holds your data.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="zoom" index={3} heading="What Anchor observes in a Zoom class">
        <p>
          To read in-meeting state, Anchor joins your Zoom meeting as an additional participant
          named <strong>"Anchor (engagement assistant)"</strong>. This is deliberate: participant
          state such as mute and camera status is only visible to a client inside the meeting.{" "}
          <strong>
            The bot is visible in the participant list to everyone in the call, exactly like any
            other attendee.
          </strong>{" "}
          Anchor does not join silently.
        </p>
        <h3>Signals read from the meeting</h3>
        <ul>
          <li>Microphone state, and how long a participant has been unmuted</li>
          <li>Whether a participant is currently speaking, and for how long</li>
          <li>
            Camera on or off — <strong>a state flag only; no video frame is ever read</strong>
          </li>
          <li>Hand-raise state and how many times a hand has been raised</li>
          <li>
            The <strong>length</strong> of chat messages — a character count, not the message text
          </li>
          <li>
            From Zoom's live caption stream: counts of hesitation markers, whether an utterance was
            a question, and a derived confidence estimate
          </li>
        </ul>
        <h3>How captions are handled</h3>
        <p>
          Captions are speech by children in a classroom, and are treated accordingly. The
          transcript exists in memory only, is limited to a recent window rather than the whole
          lesson, is dropped when the meeting ends, and is <strong>never written to disk</strong>.
          The only thing derived from a lesson that persists is the lesson topic, if you type one in
          yourself.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="classroom" index={4} heading="What Anchor reads from Google Classroom">
        <p>
          Connecting Google Classroom is optional. Anchor works on Zoom signals alone; Classroom
          adds academic context. If you connect it, Anchor requests these scopes:
        </p>
        <ul>
          <li>
            <code>classroom.courses.readonly</code> — your course list
          </li>
          <li>
            <code>classroom.rosters.readonly</code> — student rosters, to match students to meeting
            participants
          </li>
          <li>
            <code>classroom.student-submissions.students.readonly</code> — submission and grade
            state
          </li>
          <li>
            <code>classroom.coursework.students</code> — coursework. Google's console does not offer
            a read-only variant of this scope for our configuration, so the broader one is
            requested.{" "}
            <strong>Anchor makes only read requests and never writes to your Classroom.</strong>
          </li>
          <li>
            <code>userinfo.email</code> — your own email, to show which account is connected
          </li>
        </ul>
        <p>
          <strong>Anchor does not request your students' email addresses.</strong> It used to, to
          match a Classroom roster entry to the right person in the Zoom call. That was the only
          permission on this list Google classes as sensitive, and it was removed on 17 August 2026.
          Anchor now matches students by name instead, which is less certain — so it only accepts an
          unambiguous name, shows any such match as unverified, and asks you to confirm the rest
          yourself. Two students whose names look alike are both left unmatched rather than one of
          them being guessed at.
        </p>
        <p>
          Google shows these as individual checkboxes and grants only what you tick. Anchor checks
          afterwards what was actually granted and degrades rather than failing.
        </p>
        <p>
          From this data Anchor derives five academic signals: missing assignments, grade average,
          grade trend, days since last submission and late submissions.
        </p>
        <p>
          Anchor's use of information from Google APIs adheres to the{" "}
          <a
            href="https://developers.google.com/terms/api-services-user-data-policy"
            target="_blank"
            rel="noreferrer"
          >
            Google API Services User Data Policy
          </a>
          , including the Limited Use requirements. Classroom data is used solely to display
          engagement and risk information to you, is never transferred to us or any third party, is
          never used for advertising, and is never used to train any model outside your own Mac.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="storage" index={5} heading="Where the data lives">
        <ul>
          <li>
            <strong>Session history</strong> — a JSON file in your Mac's Application Support
            directory. It records engagement scores and Zoom signals.{" "}
            <strong>It never contains a line of speech.</strong> Anchor deletes each session's
            record <strong>120 days after the class ends</strong>, and removes its own leftover
            copies of the file on the same schedule. You can change the window, or turn the
            deletion off, in Settings → Data &amp; Privacy.
          </li>
          <li>
            <strong>Your Google refresh token</strong> — the macOS Keychain. The short-lived access
            token is held in memory only and never written to disk.
          </li>
          <li>
            <strong>Your Zoom sign-in</strong> — the macOS Keychain, if you connect Zoom. Anchor
            keeps the refresh token, the current access token and its expiry, the permissions Zoom
            granted, and the account name shown in Settings. Unlike the Google token above, the
            Zoom access token is stored rather than held in memory, so that reopening Anchor does
            not send you back through Zoom's sign-in page mid-lesson.
          </li>
          <li>
            <strong>Settings and onboarding state</strong> — standard macOS preferences.
          </li>
          <li>
            <strong>Live transcript</strong> — memory only, for the duration of the meeting.
          </li>
        </ul>
        <p>
          All of this is on your machine, under your account, protected by your Mac's own file
          permissions and disk encryption. If you use FileVault, it is encrypted at rest by
          FileVault.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="transmission" index={6} heading="What leaves your Mac">
        <p>Anchor connects to exactly three destinations, all of them necessary:</p>
        <ul>
          <li>
            <strong>Zoom</strong> — to join the meeting and receive participant state
          </li>
          <li>
            <strong>Google</strong> — sign-in and Classroom reads, only if you connect Classroom
          </li>
          <li>
            <strong>An OAuth redirect page</strong> we host, which exists solely to hand the sign-in
            result back to the app and receives no student data
          </li>
        </ul>
        <p>
          There are no other network destinations in the application. Anchor contains no analytics
          SDK, no crash reporter that transmits off-device, no advertising identifier and no
          third-party tracking.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="ai" index={7} heading="How the models work">
        <p>
          Anchor's struggle detection is a Core ML model that runs on your Mac. The lesson-assistant
          features use Apple's on-device Foundation Models via Apple Intelligence, which also run
          locally.
        </p>
        <p>
          <strong>
            No student data is sent to any external AI service. No prompt, transcript, score or
            roster leaves your machine for inference.
          </strong>{" "}
          Anchor does not use OpenAI, Anthropic, Google Gemini or any other hosted model provider.
        </p>
        <p>
          Anchor does not use your classroom data to train or improve any model we distribute. If
          you choose to export training data to retrain the model yourself, that export is a file
          you create, on your machine, that you control.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="students" index={8} heading="Student data, FERPA and children">
        <p>
          Anchor is used in classrooms that include children. This deserves a direct answer rather
          than a hedge.
        </p>
        <p>
          Under <strong>FERPA</strong>, education records stay under the control of the school.
          Anchor is positioned as a tool operated by a school official — you — under the school's
          direct control. Because student information is never transmitted to us, we never become a
          recipient or holder of education records.
        </p>
        <p>
          Under <strong>COPPA</strong>, the operator obligations that attach to collecting personal
          information from children under 13 are triggered by collection by the operator. Anchor
          performs no such collection: we receive nothing. This does not remove your school's own
          obligations to notify parents and obtain consent where its policy or state law requires
          it.
        </p>
        <p>
          Several US states impose additional student-privacy duties on schools and vendors. Because
          the answer to "what does the vendor receive" is "nothing", Anchor is straightforward to
          assess — but the assessment is still your school's to make.
        </p>
        <p>
          <mark>
            This section describes how the software behaves. It is not legal advice, and it has not
            been reviewed by an attorney. Have counsel review this policy and your school's data
            agreements before running a pilot with real students.
          </mark>
        </p>
      </LegalSectionBody>

      <LegalSectionBody
        id="responsibilities"
        index={9}
        heading="Your responsibilities as the teacher"
      >
        <p>
          Anchor gives you information about students. Using it lawfully and decently is your part
          of the arrangement:
        </p>
        <ul>
          <li>
            Tell participants that Anchor is in the meeting. The bot is visible, but visible is not
            the same as disclosed, and several jurisdictions require notice before captions or
            meeting content are processed.
          </li>
          <li>
            Follow your school's policy and any applicable state student-privacy law before
            connecting Classroom or running a session.
          </li>
          <li>Confirm you are authorised to connect the Zoom and Google accounts you connect.</li>
          <li>
            Treat what Anchor shows you as an estimate that prompts a human check, never as a
            finding about a child. See the{" "}
            <a href="/terms#limitations">limitations section of the Terms</a>.
          </li>
        </ul>
      </LegalSectionBody>

      <LegalSectionBody id="retention" index={10} heading="Retention and deletion">
        <p>
          We hold nothing, so there is nothing for us to delete. Everything is under your control:
        </p>
        <ul>
          <li>
            <strong>Live transcripts</strong> — discarded automatically when the meeting ends.
          </li>
          <li>
            <strong>Session history</strong> — deleted automatically 120 days after each class
            ends. You can shorten that to nothing, extend it to a school year, or switch automatic
            deletion off entirely in Settings → Data &amp; Privacy. You can also delete any session
            or class immediately in the app, or delete the whole file yourself.
          </li>
          <li>
            <strong>Google connection</strong> — disconnect in the app, and revoke Anchor's access
            at{" "}
            <a href="https://myaccount.google.com/permissions" target="_blank" rel="noreferrer">
              myaccount.google.com/permissions
            </a>
            . Revoking at Google invalidates the stored refresh token immediately.
          </li>
          <li>
            <strong>Zoom connection</strong> — disconnect in the app. Anchor asks Zoom to revoke
            the grant and then deletes it from the Keychain, and it deletes its own copy even when
            that request cannot reach Zoom, so Disconnect never leaves you still connected. You can
            also remove Anchor yourself at{" "}
            <a href="https://marketplace.zoom.us/user/installed" target="_blank" rel="noreferrer">
              marketplace.zoom.us/user/installed
            </a>
            .
          </li>
          <li>
            <strong>Everything</strong> — deleting the app and its Application Support directory
            removes all locally stored Anchor data.
          </li>
        </ul>
      </LegalSectionBody>

      <LegalSectionBody id="rights" index={11} heading="Your rights">
        <p>
          Depending on where you live you may have rights to access, correct, export or delete
          personal data held about you, and to object to its processing.
        </p>
        <p>
          For data inside Anchor these rights are satisfied directly: the data is on your Mac, in
          files you can read, copy and delete without asking us. If you email us about the pilot, we
          hold that correspondence, and you can ask us to delete it at{" "}
          <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
        </p>
        <p>
          This website is served as static files. It sets no cookies, runs no analytics and does not
          fingerprint visitors. Our host records standard server logs, including IP addresses, for
          delivery and security.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="changes" index={12} heading="Changes to this policy">
        <p>
          If this policy changes materially — particularly if Anchor ever gains a backend, or begins
          transmitting data anywhere it does not today — we will update the date at the top of this
          page and notify pilot teachers by email before the change takes effect.
        </p>
        <p>
          Anchor requires {MIN_MACOS} or later. Changes to the underlying Zoom or Google APIs may
          change what signals are available; we will keep this page accurate as that happens.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="contact" index={13} heading="Contact">
        <p>
          Questions about this policy, or about anything Anchor does with data, go to{" "}
          <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>. Questions from a school's privacy
          officer or counsel are welcome and will get a direct answer.
        </p>
      </LegalSectionBody>
    </LegalPage>
  );
}
