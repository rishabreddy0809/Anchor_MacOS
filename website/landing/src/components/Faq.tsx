import { Link } from "@tanstack/react-router";
import { isValidElement, type ReactNode } from "react";

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { Reveal } from "@/components/Reveal";
import { MIN_MACOS } from "@/lib/site";

/**
 * The questions a teacher actually asks before letting software watch their
 * class. Every answer here is checked against the app's behaviour — if the app
 * changes, these change.
 */
const FAQS: { q: string; a: ReactNode }[] = [
  {
    q: "Do my students have to install anything?",
    a: (
      <p>
        No. Anchor joins the Zoom meeting as its own participant and reads meeting state from there.
        Students do nothing, install nothing, and sign up for nothing.
      </p>
    ),
  },
  {
    q: "Will my students know Anchor is in the class?",
    a: (
      <p>
        Yes. Anchor appears in the participant list as{" "}
        <strong>"Anchor (engagement assistant)"</strong>, visible to everyone in the call. It does
        not join invisibly. You should still tell your class what it is — visible is not the same as
        explained.
      </p>
    ),
  },
  {
    q: "Does Anchor watch video or use facial recognition?",
    a: (
      <p>
        No. Anchor reads whether a camera is on or off — a true/false flag from Zoom — and never
        reads the picture. There is no facial recognition, no emotion detection from faces, and no
        image processing anywhere in the app.
      </p>
    ),
  },
  {
    q: "Where does my students' data go?",
    a: (
      <p>
        Nowhere. Anchor has no server and no account system, so student data stays on your Mac. We
        never receive it — not names, grades, speech or scores. The{" "}
        <Link to="/privacy">Privacy Policy</Link> sets out exactly what is stored and where.
      </p>
    ),
  },
  {
    q: "Is what students say recorded?",
    a: (
      <p>
        Zoom's live captions are read during class to spot hesitation and questions, but the
        transcript stays in memory, covers only a recent window, and is discarded when the meeting
        ends. It is never written to disk. Session history keeps scores and signals — never words.
      </p>
    ),
  },
  {
    q: "What does Anchor actually measure?",
    a: (
      <>
        <p>Eleven live signals from the meeting, including:</p>
        <ul>
          <li>Mute state and time spent unmuted</li>
          <li>Whether and how long a student speaks</li>
          <li>Camera on or off</li>
          <li>Hand raises</li>
          <li>Chat message length — the count, not the text</li>
          <li>Hesitation markers and questions, from captions</li>
        </ul>
        <p>
          With Google Classroom connected it adds five academic signals: missing assignments, grade
          average, grade trend, days since last submission and late submissions.
        </p>
      </>
    ),
  },
  {
    q: "Do I need Google Classroom?",
    a: (
      <p>
        No. Anchor works from your Zoom classes alone. Classroom is optional and adds grades and
        assignments to the picture — Anchor only ever reads it, and never changes anything in it.
      </p>
    ),
  },
  {
    q: "What do I need to run it?",
    a: (
      <p>
        A Mac running {MIN_MACOS} or later, and a Zoom account you're allowed to connect. The
        lesson-assistant features additionally need Apple Intelligence enabled; without it the rest
        of the app still works.
      </p>
    ),
  },
  {
    q: "Do I need approval from my school or district?",
    a: (
      <>
        <p>
          Probably, and that is your call to make rather than ours. Because nothing about a student
          is ever transmitted to us, we never hold education records under FERPA and the collection
          that triggers COPPA operator obligations does not happen — Anchor is a tool operated by a
          school official, you, under your school's control.
        </p>
        <p>
          That does not remove your school's own duty to notify parents and obtain the consent its
          policy or your state law requires. The <Link to="/privacy">Privacy Policy</Link> is
          written to be handed to whoever has to assess it.
        </p>
      </>
    ),
  },
  {
    q: "How accurate is it?",
    a: (
      <p>
        We do not publish an accuracy figure, because we have not established one on a held-out test
        set — and quoting a number we cannot defend would be worse than saying nothing. Anchor
        produces estimates that are worth a human look, not findings about a child. Measuring this
        properly is one of the things the pilot is for.
      </p>
    ),
  },
  {
    q: "What does the pilot cost?",
    a: (
      <p>
        Nothing. The pilot is free, with the full feature set and direct support. You are helping
        shape the product, and getting a say in what it becomes.
      </p>
    ),
  },
];

/**
 * Flattens an answer's element tree to plain text for the structured data
 * below, so the JSON-LD is derived from the rendered answers rather than
 * duplicated beside them — there is nothing to keep in sync.
 */
function toPlainText(node: ReactNode): string {
  if (node == null || typeof node === "boolean") return "";
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(toPlainText).join("");
  if (isValidElement(node)) {
    const text = toPlainText((node.props as { children?: ReactNode }).children);
    // Block-level answers run together without this: "…on your Mac.We never…"
    return node.type === "p" || node.type === "li" ? `${text} ` : text;
  }
  return "";
}

/** schema.org FAQPage markup for the questions above. */
export function faqStructuredData() {
  return {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: FAQS.map((f) => ({
      "@type": "Question",
      name: f.q,
      acceptedAnswer: { "@type": "Answer", text: toPlainText(f.a).replace(/\s+/g, " ").trim() },
    })),
  };
}

export function Faq() {
  return (
    <section id="faq" className="bg-background py-24 sm:py-32">
      <div className="shell">
        <Reveal className="max-w-2xl">
          <p className="eyebrow text-muted-foreground">FAQ</p>
          <h2 className="mt-4 text-3xl font-bold sm:text-5xl">Questions teachers ask</h2>
          <p className="mt-5 text-lg text-muted-foreground">
            The ones that come up before anyone lets software watch their classroom.
          </p>
        </Reveal>

        <Reveal delay={100} className="mt-12">
          <Accordion type="single" collapsible className="mx-auto max-w-3xl">
            {FAQS.map((f, i) => (
              <AccordionItem key={f.q} value={`faq-${i}`}>
                <AccordionTrigger className="text-left text-base font-medium sm:text-lg">
                  {f.q}
                </AccordionTrigger>
                <AccordionContent className="faq-answer text-base text-muted-foreground">
                  {f.a}
                </AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </Reveal>
      </div>
    </section>
  );
}
