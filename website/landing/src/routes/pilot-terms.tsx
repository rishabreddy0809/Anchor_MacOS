import { createFileRoute, Link } from "@tanstack/react-router";

import { LegalPage, LegalSectionBody, type LegalSection } from "@/components/LegalPage";
import { CONTACT_EMAIL, LEGAL_NAME, MIN_MACOS, PILOT_TERMS, absoluteUrl } from "@/lib/site";

export const Route = createFileRoute("/pilot-terms")({
  head: () => ({
    meta: [
      { title: "Pilot Program Terms — Anchor" },
      {
        name: "description",
        content:
          "The terms of the free Anchor pilot: what a cohort involves, what is asked of a pilot teacher, what is promised in return, and how either side can walk away.",
      },
      { property: "og:title", content: "Pilot Program Terms — Anchor" },
      { property: "og:type", content: "article" },
    ],
    links: [{ rel: "canonical", href: absoluteUrl("/pilot-terms") }],
  }),
  component: PilotTerms,
});

const SECTIONS: LegalSection[] = [
  { id: "what-this-is", heading: "What this document is" },
  { id: "at-a-glance", heading: "The pilot at a glance" },
  { id: "who", heading: "Who can join" },
  { id: "included", heading: "What you get" },
  { id: "asked", heading: "What is asked of you" },
  { id: "promised", heading: "What is promised to you" },
  { id: "students", heading: "Your students during the pilot" },
  { id: "feedback", heading: "Feedback, and what happens to it" },
  { id: "pre-release", heading: "Pre-release software" },
  { id: "publicity", heading: "Naming you or your school" },
  { id: "leaving", heading: "Leaving, and being asked to leave" },
  { id: "after", heading: "After the pilot ends" },
  { id: "changes", heading: "Changes to these terms" },
  { id: "contact", heading: "Contact" },
];

function PilotTerms() {
  return (
    <LegalPage
      title="Pilot Program Terms"
      summary="The agreement for the free Anchor pilot: what a cohort involves, what is asked of you, what is promised back, and how either of us can walk away."
      sections={SECTIONS}
    >
      <LegalSectionBody id="what-this-is" index={1} heading="What this document is">
        <p>
          These terms cover participation in the Anchor pilot program. They sit on top of the{" "}
          <Link to="/terms">Terms of Service</Link>, which govern the software itself, and the{" "}
          <Link to="/privacy">Privacy Policy</Link>, which sets out what is stored and where. Where
          this document and the Terms of Service disagree about the pilot specifically, this
          document wins.
        </p>
        <p>
          The agreement is between you and <strong>{LEGAL_NAME}</strong>, an individual developer
          operating Anchor ("Anchor", "we", "us"). There is no company behind it, and it is worth
          knowing that before you rely on it in a classroom.
        </p>
        <p>
          You accept these terms by submitting a pilot application or by using Anchor as a pilot
          teacher.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="at-a-glance" index={2} heading="The pilot at a glance">
        <p>The full terms are below; this is the summary shown on the site.</p>
        <ul>
          {PILOT_TERMS.map((t) => (
            <li key={t.label}>
              <strong>{t.label}:</strong> {t.value ?? <mark>still to be decided — {t.hint}</mark>}
            </li>
          ))}
        </ul>
        <p>
          The pilot is free. There is no fee, no card, no trial that converts into a subscription,
          and no payment obligation of any kind during the program.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="who" index={3} heading="Who can join">
        <p>You can take part if all of the following are true:</p>
        <ul>
          <li>You are at least 18 and are the teacher responsible for the class involved.</li>
          <li>You teach live classes on Zoom and are authorised to connect that Zoom account.</li>
          <li>
            You have a Mac running {MIN_MACOS} or later. This is a hard requirement — Anchor runs on
            your machine, and there is no Windows, iPad or web version.
          </li>
          <li>
            Your school or institution permits it, and you have whatever notice or consent its
            policy and your state's law require.
          </li>
        </ul>
        <p>
          That last point is yours to satisfy, not ours. We cannot assess your district's policy for
          you, and we do not treat an application as evidence that you have cleared it.
        </p>
        <p>
          Places are limited and applications are read individually. Applying does not guarantee a
          place, and we may decline an application without giving a reason.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="included" index={4} heading="What you get">
        <ul>
          <li>
            The complete application, with no features held back or locked behind a paid tier.
          </li>
          <li>
            Direct support from the person who wrote the software, by email, for the duration of
            your cohort.
          </li>
          <li>
            A genuine say in the product. Pilot feedback decides what gets built next, and you will
            be told when something you asked for ships.
          </li>
          <li>No charge, at any point during the program.</li>
        </ul>
      </LegalSectionBody>

      <LegalSectionBody id="asked" index={5} heading="What is asked of you">
        <p>
          A pilot only produces something worth having if it is actually used. In return for the
          above, you are asked to:
        </p>
        <ul>
          <li>
            Run Anchor in roughly two live classes a week across the cohort. Weeks off happen —
            holidays, illness, a week that gets away from you — and nobody is being audited.
          </li>
          <li>
            Tell your class that Anchor is there and what it does. It appears in the participant
            list as "Anchor (engagement assistant)", but being visible is not the same as being
            explained.
          </li>
          <li>
            Report problems when they happen, rather than working around them quietly. A bug you
            tolerate is a bug that ships to the next teacher.
          </li>
          <li>
            Take one 30-minute call at the end of the cohort, to talk through what worked and what
            did not.
          </li>
        </ul>
        <p>
          None of this is enforceable and none of it is billed. If it stops being worth your time,
          say so and stop — see <a href="#leaving">Leaving</a>.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="promised" index={6} heading="What is promised to you">
        <ul>
          <li>
            <strong>You will be answered.</strong> Support email gets a reply within two working
            days during your cohort. If that slips, it slips honestly and you will be told why.
          </li>
          <li>
            <strong>No surprise charges, ever.</strong> You will not be charged during the pilot,
            and you will not be moved onto a paid plan without being asked first and agreeing.
          </li>
          <li>
            <strong>Nothing about your students reaches us.</strong> Not names, not grades, not
            speech, not scores. Your Anchor account holds your name and email address, and nothing
            about a class is ever sent.
          </li>
          <li>
            <strong>Notice before the program ends.</strong> If the pilot is wound up early you get
            at least 14 days' notice, so a cohort does not vanish mid-term.
          </li>
          <li>
            <strong>Your feedback is not repackaged as a claim.</strong> Nothing you say becomes a
            marketing quote or a statistic without your written agreement — see{" "}
            <a href="#publicity">Naming you</a>.
          </li>
        </ul>
      </LegalSectionBody>

      <LegalSectionBody id="students" index={7} heading="Your students during the pilot">
        <p>
          Students are not participants in this agreement. They install nothing, sign up for
          nothing, and are not asked to agree to anything. The relationship is between you and us.
        </p>
        <p>
          The pilot changes nothing about how student data is handled. It stays on your Mac. The
          limits in the Terms of Service on what Anchor's output may be used for —{" "}
          <strong>
            never as the sole or primary basis for discipline, grading, referral, diagnosis,
            placement or any decision that materially affects a student
          </strong>{" "}
          — apply in full during the pilot, and matter more here than anywhere, because the model
          has not yet been measured against a held-out test set.
        </p>
        <p>
          If a student or a parent objects to Anchor being in the room, the answer is to stop using
          it for that class. Tell us and it will not count against your participation.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="feedback" index={8} heading="Feedback, and what happens to it">
        <p>
          Feedback you give about the product — bug reports, opinions, feature requests, what you
          said on the closing call — may be used to improve Anchor and to decide what to build, with
          no obligation or payment to you. That is the trade the pilot is built on.
        </p>
        <p>
          This covers your views about the software. It does not cover your classroom data, which we
          never receive and cannot use. If you want to send a screenshot or an export to illustrate
          a problem, remove student names first, and do not send anything your school's policy does
          not permit you to send.
        </p>
        <p>
          Aggregate findings from the pilot may be published — how far ahead of a falling grade a
          flag arrived, how often a flag was worth acting on, how many teachers kept using it. These
          will never identify you, your school or a student without your written permission.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="pre-release" index={9} heading="Pre-release software">
        <p>
          Anchor is pre-release. It will have defects, features will change or disappear, and an
          update may break something that worked last week. There is no uptime commitment and no
          service level.
        </p>
        <p>
          Do not make Anchor the only thing standing between a struggling student and someone
          noticing. It is an extra pair of eyes on a class you are already teaching, and during a
          pilot it is an unproven one.
        </p>
        <p>
          The "as is" warranty disclaimer and the limitation of liability in the{" "}
          <Link to="/terms">Terms of Service</Link> apply to the pilot in full.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="publicity" index={10} heading="Naming you or your school">
        <p>
          We will not name you, quote you, use your school's name or logo, or describe your
          classroom in any public material without your written permission, given for that specific
          use. Taking part in the pilot is not that permission.
        </p>
        <p>
          Permission can be withdrawn at any time. Ask, and the material comes down at the next
          reasonable opportunity.
        </p>
        <p>
          You are free to talk publicly about your experience of Anchor, good or bad. There is no
          confidentiality obligation on you and no non-disparagement clause. If it was poor, say it
          was poor.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="leaving" index={11} heading="Leaving, and being asked to leave">
        <p>
          You can leave the pilot at any time, for any reason or none, by emailing us and deleting
          the app. Nothing is owed, no exit interview is required, and you will not be chased.
        </p>
        <p>
          We may end your participation if you breach these terms or the Terms of Service — in
          particular the limits on what Anchor's output may be used for — or if we end the program
          altogether.
        </p>
        <p>
          Either way, everything on your Mac stays on your Mac. Deleting the app removes it, and no
          classroom data was ever on our side to delete. The one thing that is ours to delete is
          your Anchor account, which holds your email address and name and nothing about a class:
          email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a> and we will remove it.
          Revoking Anchor's access to your Zoom and Google accounts is done in those accounts, not
          here.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="after" index={12} heading="After the pilot ends">
        <p>
          When your cohort finishes, Anchor keeps working on your machine until an update or a
          change to Zoom's or Google's interfaces stops it. Nothing is switched off remotely at the
          end of a cohort.
        </p>
        <p>
          If Anchor later becomes a paid product, taking part in the pilot does not entitle you to
          free use forever — but you will not be charged without being told in advance and agreeing.
          No card is held, so nothing can be charged silently.
        </p>
        <p>
          Sections 7, 8, 9 and 10 continue to apply after the pilot ends. So do the corresponding
          sections of the Terms of Service.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="changes" index={13} heading="Changes to these terms">
        <p>
          These terms may be updated. The date at the top of this page changes when they are, and
          pilot teachers are emailed before any material change takes effect. If a change does not
          suit you, leaving the pilot is always available and costs nothing.
        </p>
        <p>
          <mark>
            This document describes how the program is intended to run. It is not legal advice and
            has not been reviewed by an attorney. Have counsel review it before running a pilot with
            a school.
          </mark>
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="contact" index={14} heading="Contact">
        <p>
          Questions about the pilot, or about these terms, go to{" "}
          <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>. They are read by the person who
          wrote both the software and this page.
        </p>
      </LegalSectionBody>
    </LegalPage>
  );
}
