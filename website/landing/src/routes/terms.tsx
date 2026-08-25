import { createFileRoute } from "@tanstack/react-router";

import { LegalPage, LegalSectionBody, type LegalSection } from "@/components/LegalPage";
import { CONTACT_EMAIL, LEGAL_NAME, MIN_MACOS, absoluteUrl } from "@/lib/site";

export const Route = createFileRoute("/terms")({
  head: () => ({
    meta: [
      { title: "Terms of Service — Anchor" },
      {
        name: "description",
        content:
          "Terms for the Anchor pilot program: eligibility, what the software does and does not claim, and the limits on how its output may be used.",
      },
      { property: "og:title", content: "Terms of Service — Anchor" },
      { property: "og:type", content: "article" },
    ],
    links: [{ rel: "canonical", href: absoluteUrl("/terms") }],
  }),
  component: Terms,
});

const SECTIONS: LegalSection[] = [
  { id: "acceptance", heading: "Acceptance" },
  { id: "pilot", heading: "The pilot program" },
  { id: "eligibility", heading: "Eligibility and your authority" },
  { id: "limitations", heading: "What Anchor does not claim" },
  { id: "acceptable-use", heading: "Acceptable use" },
  { id: "third-party", heading: "Zoom and Google" },
  { id: "requirements", heading: "System requirements" },
  { id: "ip", heading: "Intellectual property" },
  { id: "warranty", heading: "No warranty" },
  { id: "liability", heading: "Limitation of liability" },
  { id: "termination", heading: "Termination" },
  { id: "law", heading: "Governing law" },
  { id: "changes", heading: "Changes to these terms" },
  { id: "contact", heading: "Contact" },
];

function Terms() {
  return (
    <LegalPage
      title="Terms of Service"
      summary="Terms for the free Anchor pilot. The most important section is the one about what Anchor's output means — and what it must never be used to decide."
      sections={SECTIONS}
    >
      <LegalSectionBody id="acceptance" index={1} heading="Acceptance">
        <p>
          By installing or using Anchor, or by joining the pilot program, you agree to these terms.
          If you are using Anchor in a school, you also confirm you are doing so consistently with
          that school's policies. If you do not agree, do not use the software.
        </p>
        <p>
          These terms are between you and <strong>{LEGAL_NAME}</strong>, an individual developer
          operating Anchor ("Anchor", "we", "us").
        </p>
        <p>
          If you are taking part in the pilot program, the{" "}
          <a href="/pilot-terms">Pilot Program Terms</a> also apply, and take precedence over these
          where the two disagree about the pilot.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="pilot" index={2} heading="The pilot program">
        <p>
          Anchor is pre-release software offered free of charge to pilot classrooms. There is no fee
          and no payment obligation during the pilot.
        </p>
        <p>
          Because it is a pilot: features may change or be removed, the software may contain
          defects, there is no uptime or support commitment, and we may end the program or your
          participation at any time. We will give pilot teachers reasonable notice before ending the
          program.
        </p>
        <p>
          If Anchor later becomes a paid product, the pilot does not entitle you to free continued
          use, but we will not begin charging you without notice and your agreement.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="eligibility" index={3} heading="Eligibility and your authority">
        <p>You may use Anchor only if all of the following are true:</p>
        <ul>
          <li>You are at least 18 years old.</li>
          <li>
            You are a teacher, instructor or other educator responsible for the class you are
            monitoring.
          </li>
          <li>
            You are authorised to connect the Zoom account and, if applicable, the Google Classroom
            account you connect.
          </li>
          <li>
            Your use is permitted by your school or institution and by the law that applies to you.
          </li>
        </ul>
        <p>
          Anchor is not for students, parents or observers. It is a teacher's instrument for the
          class that teacher is running.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="limitations" index={4} heading="What Anchor does not claim">
        <p>
          This is the section to read if you read only one. Anchor produces{" "}
          <strong>statistical estimates from behavioural signals</strong>. It does not observe
          understanding, effort, wellbeing or intent, and it cannot.
        </p>
        <p>
          A student may be quiet because they are thinking, shy, on a poor connection, sharing a
          room, neurodivergent, unwell, or listening carefully. Anchor sees the same signal in all
          of these cases. A high struggle score means "worth a human look", nothing more.
        </p>
        <p>
          <strong>You must not use Anchor's output as the sole or primary basis for:</strong>
        </p>
        <ul>
          <li>Any disciplinary action</li>
          <li>Any grade, mark or academic assessment</li>
          <li>
            Any referral, diagnosis or determination concerning a disability, mental health or
            special-education need
          </li>
          <li>Any placement, streaming or tracking decision</li>
          <li>Any report to a third party about a student</li>
          <li>Any other decision that materially affects a student</li>
        </ul>
        <p>
          Anchor is not a medical, psychological, diagnostic or safeguarding tool, and no output
          should be read as a clinical or professional finding. It does not replace your judgement,
          your school's safeguarding process, or a conversation with the student.
        </p>
        <p>
          <strong>
            No accuracy figure is published for Anchor's model, because none has been established on
            a held-out test set.
          </strong>{" "}
          Treat its output with the scepticism that deserves.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="acceptable-use" index={5} heading="Acceptable use">
        <p>You agree not to:</p>
        <ul>
          <li>
            Use Anchor to surveil, profile or build a persistent behavioural record of a student
            beyond what teaching the class requires
          </li>
          <li>
            Use Anchor in a meeting you are not entitled to monitor, or conceal its presence from
            participants who ask
          </li>
          <li>
            Share, publish or transmit another person's engagement data without a lawful basis and
            your school's approval
          </li>
          <li>
            Reverse engineer, decompile or redistribute the software, except where that restriction
            is unenforceable under applicable law
          </li>
          <li>Use Anchor to violate any law, or any school or platform policy</li>
        </ul>
        <p>
          You are responsible for disclosing Anchor's presence to participants and for obtaining any
          consent your jurisdiction or institution requires before processing meeting captions.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="third-party" index={6} heading="Zoom and Google">
        <p>
          Anchor works with Zoom and, optionally, Google Classroom. Your use of those services
          remains governed by their own terms, and we are not responsible for them. Anchor is not
          affiliated with, endorsed by or sponsored by Zoom Communications, Inc. or Google LLC.
        </p>
        <p>
          If either provider changes or withdraws the interfaces Anchor depends on, features may
          stop working. We will tell pilot teachers when that happens, but cannot prevent it.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="requirements" index={7} heading="System requirements">
        <p>
          Anchor requires a Mac running {MIN_MACOS} or later. The lesson-assistant features
          additionally require Apple Intelligence to be available and enabled on that Mac; where it
          is not, those features are unavailable and the rest of the app continues to work.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="ip" index={8} heading="Intellectual property">
        <p>
          Anchor, including the application, its models and this website, remains our property. The
          pilot grants you a personal, non-exclusive, non-transferable, revocable licence to use the
          software for teaching your own classes for the duration of the program.
        </p>
        <p>
          Data produced on your machine — session history, exports, anything you type — is yours. We
          claim no ownership of it and, as described in the <a href="/privacy">Privacy Policy</a>,
          never receive it.
        </p>
        <p>
          Feedback you send us about the product may be used to improve Anchor without obligation or
          compensation to you. This covers your opinions about the software, not your classroom
          data.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="warranty" index={9} heading="No warranty">
        <p>
          Anchor is provided{" "}
          <strong>"as is" and "as available", without warranty of any kind</strong>, express or
          implied, including any implied warranty of merchantability, fitness for a particular
          purpose, accuracy or non-infringement.
        </p>
        <p>
          We do not warrant that Anchor will be uninterrupted, error-free, or that its estimates
          will be correct for any student or any class.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="liability" index={10} heading="Limitation of liability">
        <p>
          To the maximum extent permitted by law, we are not liable for any indirect, incidental,
          consequential, special or punitive damages, or for any loss of data, opportunity or
          reputation, arising out of your use of Anchor.
        </p>
        <p>
          Because the pilot is free of charge, our total aggregate liability arising from Anchor is
          limited to <strong>USD 100</strong>.
        </p>
        <p>
          Nothing here limits liability that cannot be limited by law, including for fraud or for
          death or personal injury caused by negligence. Some jurisdictions do not allow certain
          exclusions, in which case the narrowest permitted exclusion applies.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="termination" index={11} heading="Termination">
        <p>
          You may stop using Anchor at any time by deleting it and revoking its access to your
          connected accounts. We may suspend or end your access if you breach these terms, or if we
          end the pilot program.
        </p>
        <p>
          Termination does not delete anything of yours from your machine, and nothing about your
          classes was ever on our side to delete. Your Anchor account is the exception, since it
          does not live on your Mac: email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>{" "}
          and we will delete it. Sections 4, 8, 9, 10 and 12 survive termination.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="law" index={12} heading="Governing law">
        <p>
          These terms are governed by the laws of the United States and of the Commonwealth of
          Massachusetts, without regard to its conflict-of-laws rules. The state and federal courts
          located in the Commonwealth of Massachusetts have exclusive jurisdiction over any dispute,
          except that either party may seek injunctive relief in any competent court.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="changes" index={13} heading="Changes to these terms">
        <p>
          We may update these terms. The date at the top of this page changes when we do, and we
          will notify pilot teachers by email of any material change before it takes effect.
          Continuing to use Anchor after that means you accept the updated terms.
        </p>
      </LegalSectionBody>

      <LegalSectionBody id="contact" index={14} heading="Contact">
        <p>
          Questions about these terms go to <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
        </p>
      </LegalSectionBody>
    </LegalPage>
  );
}
