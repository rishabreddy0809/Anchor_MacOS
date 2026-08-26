import { createFileRoute, Link } from "@tanstack/react-router";
import {
  Mic,
  Video,
  ClipboardList,
  ShieldCheck,
  Cpu,
  Lock,
  Eye,
  ArrowRight,
  Check,
  Play,
} from "lucide-react";

import { AuroraSilk } from "@/components/AuroraSilk";
import { LiveClassPanel } from "@/components/LiveClassPanel";
import { PilotForm } from "@/components/PilotForm";
import { Reveal } from "@/components/Reveal";
import { SiteNav } from "@/components/SiteNav";
import { SiteFooter } from "@/components/SiteFooter";
import { Faq, faqStructuredData } from "@/components/Faq";
import {
  CONTACT_EMAIL,
  LEGAL_NAME,
  MIN_MACOS,
  PILOT_TERMS,
  PRESS,
  PILOT_TERMS_SETTLED,
  REQUIREMENTS,
  absoluteUrl,
} from "@/lib/site";
import dashboardShot from "@/assets/dashboard.jpg";
import homeShot from "@/assets/home.jpg";
import insightsShot from "@/assets/insights.jpg";
import menubarShot from "@/assets/menubar.jpg";
import integrationsShot from "@/assets/integrations.jpg";
import recommendationsShot from "@/assets/recommendations.jpg";
import episodeShot from "@/assets/professor-kev-episode.jpg";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Anchor — See what your students aren't saying" },
      {
        name: "description",
        content:
          "Anchor detects struggling students in real time during Zoom classes. Join the free pilot program for online teachers.",
      },
      { property: "og:title", content: "Anchor — See what your students aren't saying" },
      {
        property: "og:description",
        content:
          "Real-time struggle detection for Zoom classrooms. On-device ML, no facial recognition.",
      },
      { property: "og:type", content: "website" },
      { property: "og:url", content: absoluteUrl("/") },
      { property: "og:image", content: absoluteUrl("/og.png") },
      { property: "og:image:width", content: "1200" },
      { property: "og:image:height", content: "630" },
      {
        property: "og:image:alt",
        content: "Anchor — see what your students aren't saying",
      },
      { name: "twitter:card", content: "summary_large_image" },
      { name: "twitter:image", content: absoluteUrl("/og.png") },
    ],
    links: [{ rel: "canonical", href: absoluteUrl("/") }],
    // The FAQ is the strongest thing on the page; this is what lets a search
    // engine show those answers directly.
    scripts: [{ type: "application/ld+json", children: JSON.stringify(faqStructuredData()) }],
  }),
  component: Landing,
});

function Hero() {
  return (
    <section
      id="top"
      className="relative flex min-h-screen items-center overflow-hidden bg-surface-deep pt-32 pb-16"
    >
      <AuroraSilk />

      {/* legibility scrim + fade into the next section */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(90%_70%_at_20%_45%,rgba(0,0,0,0.62),transparent_70%)]"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 bottom-0 h-48 bg-gradient-to-t from-[var(--surface-deep)] to-transparent"
      />

      <div className="shell relative grid w-full items-center gap-14 lg:grid-cols-[1.05fr_0.95fr]">
        <Reveal from="none">
          <p className="eyebrow inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/5 px-3 py-1 text-primary backdrop-blur-sm">
            Now accepting pilot teachers
          </p>
          <h1 className="mt-6 text-[2.7rem] font-bold leading-[1.02] tracking-tight text-foreground-invert sm:text-6xl lg:text-[4.4rem]">
            See what your students{" "}
            <span className="bg-gradient-to-r from-primary to-[oklch(0.86_0.11_200)] bg-clip-text text-transparent">
              aren't saying.
            </span>
          </h1>
          {/* Outcome first, privacy second, mechanism third — in that order on
              purpose. The people reading this teach children online, and an app
              that watches a class is guilty until proven otherwise. Leading with
              "reads live Zoom behavior" asked them to trust the mechanism before
              they had any reason to. */}
          <p className="mt-6 max-w-lg text-lg text-muted-invert">
            The student who goes quiet is the one you lose. Anchor surfaces them while the lesson is
            still running — reading participation and coursework on your own Mac. No video, and
            nothing leaves your computer.
          </p>
          <div className="mt-9 flex flex-col gap-3 sm:flex-row">
            <Link
              to="/apply"
              className="inline-flex min-h-12 items-center justify-center gap-2 rounded-full bg-primary px-7 text-base font-medium text-primary-foreground transition-transform duration-300 hover:scale-[1.04]"
            >
              Join Pilot Program <ArrowRight size={18} />
            </Link>
            <a
              href="#how-it-works"
              className="inline-flex min-h-12 items-center justify-center rounded-full border border-white/20 px-7 text-base text-foreground-invert backdrop-blur-sm transition-colors duration-300 hover:bg-white/10"
            >
              How it works
            </a>
          </div>

          <p className="mt-8 text-sm text-muted-invert">
            Runs on-device on {MIN_MACOS}+ · No student install · Free for pilot classrooms
          </p>
        </Reveal>

        <Reveal from="right" delay={150} className="flex justify-center lg:justify-end">
          <div className="w-full max-w-2xl lg:max-w-none">
            <LiveClassPanel />
          </div>
        </Reveal>
      </div>
    </section>
  );
}

function Problem() {
  return (
    <section id="problem" className="bg-background py-24 sm:py-32">
      {/* Deliberately text-only. This section is about the gap Anchor fills, and
          a screenshot of the product sitting beside it answered the problem
          before it had been stated. The dashboard now appears in the solution
          section below, where it is the answer rather than a decoration. */}
      <div className="shell">
        <Reveal className="mx-auto max-w-3xl text-center">
          <p className="eyebrow text-muted-foreground">The problem</p>
          <h2 className="mt-4 text-3xl font-bold sm:text-5xl">The challenge of online teaching</h2>
          <p className="mt-6 text-lg text-muted-foreground">
            In a Zoom class, disengagement is invisible. A student can sit camera-off and silent for
            weeks, and the first hard signal is a grade — long after the moment you could have
            helped.
          </p>
        </Reveal>
      </div>
    </section>
  );
}

const SIGNALS = [
  { icon: Mic, title: "Speaking Time", copy: "Who's engaging?" },
  { icon: Video, title: "Camera Status", copy: "Who's present?" },
  { icon: ClipboardList, title: "Assignment Data", copy: "Who's falling behind?" },
];

function Solution() {
  return (
    <section id="solution" className="bg-background pb-24 sm:pb-32">
      <div className="shell grid items-center gap-14 lg:grid-cols-2">
        <div>
          <Reveal from="left">
            <p className="eyebrow text-muted-foreground">The solution</p>
            {/* Was "Anchor monitors behavioral signals to identify at-risk
                students instantly." Two problems. "Monitors" is the word this
                audience is scanning for, and "instantly" was simply untrue:
                ObservationRamp deliberately holds every score down for the
                first ten minutes of watching a student, because minute zero of
                a class is indistinguishable from a room full of disengaged
                students. Claiming the opposite of a designed behaviour is the
                kind of thing a pilot teacher notices in week one. */}
            <h2 className="mt-4 text-3xl font-bold sm:text-5xl">
              Who needs you, while you can still act
            </h2>
            <p className="mt-5 text-lg text-muted-foreground">
              Anchor reads participation and coursework together, names the student worth checking
              on, and gives you the question to ask them.
            </p>
          </Reveal>

          {/* Stacked rather than the previous three-across row: beside the
              screenshot each signal gets a narrow column, and a row of tall
              cards there would out-height the image it is meant to explain. */}
          <ul className="mt-10 space-y-3">
            {SIGNALS.map((s, i) => (
              <Reveal as="li" key={s.title} from="left" delay={120 + i * 90}>
                <div className="lift flex items-center gap-4 rounded-2xl border border-border bg-card p-5">
                  <s.icon size={20} className="shrink-0 text-primary" />
                  <div>
                    <h3 className="font-semibold">{s.title}</h3>
                    <p className="text-sm text-muted-foreground">{s.copy}</p>
                  </div>
                </div>
              </Reveal>
            ))}
          </ul>
        </div>

        <Reveal from="right" delay={120}>
          <div className="shot">
            <img
              src={dashboardShot}
              alt="Anchor's live class view: six students ranked by struggle score, the highest at 86% with five missing assignments and grades down 24%"
              width={1440}
              height={840}
              loading="lazy"
              className="w-full"
            />
          </div>
        </Reveal>
      </div>
    </section>
  );
}

/**
 * One screenshot beside the text that explains it.
 *
 * `flip` puts the image on the left instead, so consecutive sections alternate
 * rather than marching down the page in one column. Each screenshot is a real
 * capture of the app, so the alt text describes what is actually in the frame.
 */
function Showcase({
  eyebrow,
  title,
  copy,
  img,
  alt,
  w,
  h,
  flip = false,
}: {
  eyebrow: string;
  title: string;
  copy: string;
  img: string;
  alt: string;
  w: number;
  h: number;
  flip?: boolean;
}) {
  return (
    <div className="shell grid items-center gap-14 lg:grid-cols-2">
      <Reveal from={flip ? "right" : "left"} className={flip ? "lg:order-2" : ""}>
        <p className="eyebrow text-muted-foreground">{eyebrow}</p>
        <h2 className="mt-4 text-3xl font-bold sm:text-5xl">{title}</h2>
        <p className="mt-5 text-lg text-muted-foreground">{copy}</p>
      </Reveal>
      <Reveal from={flip ? "left" : "right"} delay={120} className={flip ? "lg:order-1" : ""}>
        <div className="shot">
          <img src={img} alt={alt} width={w} height={h} loading="lazy" className="w-full" />
        </div>
      </Reveal>
    </div>
  );
}

function Explainability() {
  return (
    <section id="explainability" className="bg-background pb-24 sm:pb-32">
      <Showcase
        flip
        eyebrow="Every score, explained"
        title="No black box"
        copy="Open a student and Anchor shows the signals behind the number — each one named, weighted and in plain language. A teacher can disagree with it, which they can only do if they can see it."
        img={recommendationsShot}
        alt="A student's detail view: the model's score broken down into weighted factors, alongside Zoom engagement and Google Classroom standing"
        w={1280}
        h={900}
      />
    </section>
  );
}

function Dashboard() {
  return (
    <section id="dashboard" className="bg-background pb-24 sm:pb-32">
      <Showcase
        eyebrow="Your dashboard"
        title="Every class you've taught, in one place"
        copy="Anchor keeps what happened after the meeting ends: which classes you ran, who was behind on work, and every session you can open back up. It is there when the class isn't — and it clears itself after a term unless you say otherwise."
        img={homeShot}
        alt="Anchor's home dashboard: a live class banner, a linked Google Classroom course showing three students behind on work, and a list of recent recorded sessions"
        w={1100}
        h={647}
      />
    </section>
  );
}

function MenuBar() {
  return (
    <section id="menubar" className="bg-background pb-24 sm:pb-32">
      <Showcase
        flip
        eyebrow="In your menu bar"
        title="One click, never another tab"
        copy="Anchor sits in the menu bar while you teach. A click shows the class you're running, who needs attention right now, and what the lesson is on — without pulling you out of Zoom."
        img={menubarShot}
        alt="Anchor's menu bar popover: the live class with elapsed time, a high/medium/low breakdown, the current lesson topic, and the four students who need attention ranked by struggle score"
        w={820}
        h={660}
      />
    </section>
  );
}

function Impact() {
  return (
    <section id="impact" className="bg-surface-soft py-24 sm:py-32">
      <div className="shell">
        <Reveal className="max-w-2xl">
          <p className="eyebrow text-muted-foreground">Teacher impact</p>
          <h2 className="mt-4 text-3xl font-bold sm:text-5xl">What the pilot will measure</h2>
          <p className="mt-5 text-lg text-muted-foreground">
            Anchor has not run a pilot yet, so there are no results to show and nothing here is
            invented. These are the three things the first group is being run to find out — and when
            there are numbers and teachers willing to be quoted, they will appear here, measured,
            attributed and dated.
          </p>
        </Reveal>

        {/* Swap in a real quote here once a pilot teacher has given one, with their name and school. */}

        <dl className="mt-16 grid gap-10 border-t border-border pt-12 sm:grid-cols-3">
          {[
            {
              term: "Lead time",
              def: "How far ahead of a falling grade Anchor flagged the student.",
            },
            { term: "Precision", def: "How often a flag was a student who genuinely needed help." },
            { term: "Retention", def: "Whether teachers kept using it once the pilot ended." },
          ].map((s, i) => (
            <Reveal key={s.term} delay={i * 120}>
              <dt className="text-2xl font-bold tracking-tight sm:text-3xl">{s.term}</dt>
              <dd className="mt-3 text-muted-foreground">{s.def}</dd>
            </Reveal>
          ))}
        </dl>
      </div>
    </section>
  );
}

const STEPS = [
  {
    n: "01",
    title: "Connect your Zoom account",
    copy: "One-time authorization. No plugins for students.",
  },
  {
    n: "02",
    title: "Go live with a class",
    copy: "Anchor listens to session signals as you teach.",
  },
  {
    n: "03",
    title: "Anchor detects struggling students",
    copy: "Ranked alerts with suggested next steps.",
  },
];

function HowItWorks() {
  return (
    <section id="how-it-works" className="bg-background py-24 sm:py-32">
      <div className="shell">
        <Reveal className="max-w-2xl">
          <p className="eyebrow text-muted-foreground">How it works</p>
          <h2 className="mt-4 text-3xl font-bold sm:text-5xl">3 simple steps</h2>
        </Reveal>

        <ol className="mt-14 grid gap-px overflow-hidden rounded-3xl border border-border bg-border sm:grid-cols-3">
          {STEPS.map((s, i) => (
            <Reveal as="li" key={s.n} delay={i * 140} className="bg-card">
              <div className="h-full p-8 sm:p-10">
                <span className="text-sm font-semibold tracking-[0.2em] text-primary">{s.n}</span>
                <h3 className="mt-6 text-xl font-semibold">{s.title}</h3>
                <p className="mt-2 text-muted-foreground">{s.copy}</p>
              </div>
            </Reveal>
          ))}
        </ol>
      </div>
    </section>
  );
}

const FEATURES = [
  {
    title: "Real-time Detection",
    copy: "See struggle indicators as class happens.",
    img: dashboardShot,
    alt: "Anchor live class dashboard",
    w: 1440,
    h: 840,
  },
  {
    title: "Classroom Integration",
    copy: "Combine Zoom signals with assignment data.",
    img: integrationsShot,
    alt: "Zoom and Google Classroom integration settings",
    w: 900,
    h: 620,
  },
  {
    title: "AI Recommendations",
    copy: "Actionable next steps powered by on-device AI.",
    img: recommendationsShot,
    alt: "Student detail view with the model's per-signal score breakdown",
    w: 1280,
    h: 900,
  },
  {
    title: "Term-long History",
    copy: "See whether today is a bad day or a pattern.",
    img: insightsShot,
    alt: "A student's engagement timeline over four weeks, climbing from low to high, with speaking time against the class average and suggested actions",
    w: 900,
    h: 640,
  },
];

function Features() {
  return (
    <section id="features" className="bg-background pb-24 sm:pb-32">
      <div className="shell">
        <Reveal className="max-w-2xl">
          <p className="eyebrow text-muted-foreground">Features</p>
          <h2 className="mt-4 text-3xl font-bold sm:text-5xl">Built for teachers</h2>
        </Reveal>

        <ul className="mt-12 grid gap-6 sm:grid-cols-2">
          {FEATURES.map((f, i) => (
            <Reveal as="li" key={f.title} delay={i * 110}>
              <article className="lift flex h-full flex-col overflow-hidden rounded-3xl border border-border bg-card">
                <img
                  src={f.img}
                  alt={f.alt}
                  width={f.w}
                  height={f.h}
                  loading="lazy"
                  className="aspect-[3/2] w-full border-b border-border object-cover object-top"
                />
                <div className="p-7">
                  <h3 className="text-lg font-semibold">{f.title}</h3>
                  <p className="mt-2 text-muted-foreground">{f.copy}</p>
                </div>
              </article>
            </Reveal>
          ))}
        </ul>
      </div>
    </section>
  );
}

const TRUST = [
  {
    icon: ShieldCheck,
    title: "No facial recognition",
    copy: "Camera on or off is a true/false flag from Zoom. The picture is never read.",
  },
  {
    icon: Cpu,
    title: "On-device processing",
    copy: "Scoring runs on your Mac. Nothing about a student reaches us.",
  },
  {
    icon: Eye,
    title: "Visible in the call",
    copy: 'Anchor appears in the participant list as "Anchor (engagement assistant)".',
  },
  {
    icon: Lock,
    title: "Captions are never stored",
    copy: "The transcript stays in memory and is discarded when the meeting ends.",
  },
];

function Privacy() {
  return (
    <section id="security" className="bg-surface-soft py-24 sm:py-32">
      <div className="shell">
        <Reveal className="max-w-2xl">
          <p className="eyebrow text-muted-foreground">Privacy &amp; security</p>
          <h2 className="mt-4 text-3xl font-bold sm:text-5xl">Privacy first</h2>
          <p className="mt-5 text-lg text-muted-foreground">
            Anchor is a teacher's instrument, not a surveillance product. There is no data to sell,
            because none of it ever leaves your Mac.
          </p>
        </Reveal>

        <ul className="mt-12 grid gap-4 sm:grid-cols-2">
          {TRUST.map((t, i) => (
            <Reveal as="li" key={t.title} delay={i * 100}>
              <div className="lift flex h-full items-start gap-4 rounded-2xl border border-border bg-card p-7">
                <t.icon size={20} className="mt-0.5 shrink-0 text-primary" />
                <div>
                  <h3 className="font-medium">{t.title}</h3>
                  <p className="mt-1 text-sm text-muted-foreground">{t.copy}</p>
                </div>
              </div>
            </Reveal>
          ))}
        </ul>

        <Reveal delay={200} className="mt-10">
          <div className="rounded-2xl border border-border bg-card p-7 sm:p-9">
            <h3 className="text-lg font-semibold">FERPA, COPPA and your district</h3>
            <p className="mt-3 max-w-3xl text-muted-foreground">
              Because student information is never transmitted to us, we never become a holder of
              education records under <strong className="text-foreground">FERPA</strong>, and the
              collection that triggers operator obligations under{" "}
              <strong className="text-foreground">COPPA</strong> does not happen. Anchor is a tool
              operated by a school official — you — under your school's control. That does not
              remove your school's own duty to notify parents and obtain whatever consent its policy
              or your state law requires, and the assessment remains your district's to make.
            </p>
            <p className="mt-4 text-sm text-muted-foreground">
              This describes how the software behaves; it is not legal advice.{" "}
              <Link className="text-primary underline underline-offset-4" to="/privacy">
                Read the full Privacy Policy
              </Link>
              .
            </p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

/**
 * A pilot term that has not been decided yet, rendered so it cannot ship by
 * accident. Same convention as the <mark> placeholders in the legal pages.
 */
function Undecided({ hint }: { hint: string }) {
  return (
    <span className="rounded bg-destructive/15 px-1.5 py-0.5 text-base font-medium text-foreground">
      TODO: {hint}
    </span>
  );
}

function Pilots() {
  const perks = [
    "Free for the whole programme",
    "Full feature set, nothing held back",
    "Direct support from the person who built it",
    "A real say in what Anchor becomes",
  ];

  return (
    <section id="pilots" className="bg-background py-24 sm:py-32">
      <div className="shell">
        <Reveal className="mx-auto max-w-2xl text-center">
          <p className="eyebrow text-muted-foreground">The pilot</p>
          <h2 className="mt-4 text-3xl font-bold sm:text-5xl">Currently accepting pilots</h2>
          <p className="mt-5 text-lg text-muted-foreground">
            A small first group of teachers who teach live on Zoom. Free, and honest about being
            early.
          </p>
        </Reveal>

        <div className="mt-14 grid gap-6 lg:grid-cols-3">
          <Reveal className="h-full">
            <div className="h-full rounded-3xl border border-border bg-card p-7 sm:p-9">
              <h3 className="text-lg font-semibold">What you're signing up for</h3>
              <dl className="mt-6 space-y-5">
                {PILOT_TERMS.map((t) => (
                  <div key={t.label}>
                    <dt className="eyebrow text-muted-foreground">{t.label}</dt>
                    <dd className="mt-1.5">{t.value ?? <Undecided hint={t.hint} />}</dd>
                  </div>
                ))}
              </dl>
              <p className="mt-7 border-t border-border pt-5 text-sm text-muted-foreground">
                {PILOT_TERMS_SETTLED ? (
                  <>
                    The full version — what's asked of you, what's promised back, and how either of
                    us can walk away — is in the{" "}
                    <Link className="text-primary underline underline-offset-4" to="/pilot-terms">
                      Pilot Program Terms
                    </Link>
                    .
                  </>
                ) : (
                  <>
                    These terms are still being set. Nothing above is a commitment until it is
                    written here — ask when you apply and you'll get a straight answer.
                  </>
                )}
              </p>
            </div>
          </Reveal>

          <Reveal delay={110} className="h-full">
            <div className="h-full rounded-3xl border border-border bg-surface-soft p-7 sm:p-9">
              <h3 className="text-lg font-semibold">What you need</h3>
              <ul className="mt-6 space-y-5">
                {REQUIREMENTS.map((r) => (
                  <li key={r.need} className="flex items-start gap-3">
                    <Check size={18} className="mt-1 shrink-0 text-primary" />
                    <div>
                      <p className="font-medium">{r.need}</p>
                      <p className="mt-0.5 text-sm text-muted-foreground">{r.detail}</p>
                    </div>
                  </li>
                ))}
              </ul>
            </div>
          </Reveal>

          <Reveal delay={220} className="h-full">
            <div className="h-full rounded-3xl border border-border bg-card p-7 sm:p-9">
              <p className="text-4xl font-bold tracking-tight">Free</p>
              <p className="mt-2 text-muted-foreground">for pilot teachers, during the programme</p>
              <ul className="mt-6 space-y-3">
                {perks.map((p) => (
                  <li key={p} className="flex items-start gap-3">
                    <Check size={18} className="mt-1 shrink-0 text-primary" />
                    <span className="text-muted-foreground">{p}</span>
                  </li>
                ))}
              </ul>
            </div>
          </Reveal>
        </div>

        <Reveal delay={120} className="mt-12 text-center">
          <Link
            to="/apply"
            className="inline-flex min-h-13 items-center gap-2 rounded-full bg-primary px-8 py-3.5 text-base font-medium text-primary-foreground transition-transform duration-300 hover:scale-[1.04]"
          >
            Apply for the pilot <ArrowRight size={18} />
          </Link>
          <p className="mt-4 text-sm text-muted-foreground">
            Takes a minute. You'll hear back from a person.
          </p>
        </Reveal>
      </div>
    </section>
  );
}

/**
 * Who is behind the software. Early-stage classroom tools are accepted or
 * refused on trust, and an anonymous product asking to sit in a lesson is a
 * harder sell than an honest one-person project with a name on it.
 *
 * Everything here is verifiable from the code and the legal pages. The one gap
 * left marked is the motivation, which is a fact about a person rather than
 * about the software, and is the one thing that must not be written for you.
 */
function About() {
  return (
    <section id="about" className="bg-background pb-24 sm:pb-32">
      <div className="shell">
        <Reveal className="mx-auto max-w-3xl">
          <p className="eyebrow text-muted-foreground">Who's behind Anchor</p>
          <h2 className="mt-4 text-3xl font-bold sm:text-5xl">
            I built this for the student I was
          </h2>
          <div className="mt-6 space-y-4 text-lg text-muted-foreground">
            <p>
              In a math class, I was completely lost. Everyone around me looked like they were
              following it, so I never put my hand up — and the longer I left it, the worse asking
              got, because by then I would have had to admit I hadn't understood anything since the
              first week. So I never asked. I failed that class.
            </p>
            <p>
              None of that was visible from the front of the room. A student who is lost and a
              student who is fine look identical if neither of them says anything. Online, where the
              camera can be off and the class is a grid of tiles, it is worse.
            </p>
            <p>
              I started Anchor over the summer as a hackathon project, and kept building it
              afterwards because the thing that would have helped me was somebody noticing before
              the grade did.
            </p>
            <p>
              It's just me — {LEGAL_NAME}. No company, no funding, no investor waiting to be repaid
              out of a classroom. That's the constraint and the promise: support email is answered
              by the person who wrote the code, there's no server holding your students' data, and
              when something is unproven — the model's accuracy, most
              of all — you'll be told so plainly rather than sold around it.
            </p>
          </div>
          <p className="mt-8 text-muted-foreground">
            You can reach me directly at{" "}
            <a
              className="text-primary underline underline-offset-4"
              href={`mailto:${CONTACT_EMAIL}`}
            >
              {CONTACT_EMAIL}
            </a>
            .
          </p>
        </Reveal>
      </div>
    </section>
  );
}

function FinalCta() {
  return (
    <section id="contact" className="bg-surface-deep py-24 sm:py-32">
      <div className="shell text-center">
        <Reveal className="mx-auto max-w-2xl">
          <h2 className="text-3xl font-bold text-foreground-invert sm:text-5xl">
            Ready to support your students?
          </h2>
          <p className="mt-5 text-lg text-muted-invert">
            Apply for the pilot. It takes a minute, and you'll hear back from a person.
          </p>
          <Link
            to="/apply"
            className="mt-9 inline-flex min-h-13 items-center gap-2 rounded-full bg-primary px-8 py-3.5 text-base font-medium text-primary-foreground transition-transform duration-300 hover:scale-[1.04]"
          >
            Apply for the pilot <ArrowRight size={18} />
          </Link>
          <p className="mt-6 text-sm text-muted-invert">
            Questions? Email{" "}
            <a
              className="text-primary underline-offset-4 hover:underline"
              href={`mailto:${CONTACT_EMAIL}`}
            >
              {CONTACT_EMAIL}
            </a>
          </p>
        </Reveal>
      </div>
    </section>
  );
}

/**
 * The Professor Kev Show feature, sitting between the final CTA and the black
 * footer.
 *
 * This is the only outside credential Anchor has, and the page is otherwise
 * scrupulous about not claiming anything it cannot show — the Teacher impact
 * section says outright that there are no pilot results yet. So this one gets
 * the real treatment rather than a badge: the actual episode thumbnail, the
 * host named, the runtime stated, and a link to the episode itself rather than
 * to the show's channel. A reader who doubts it is one click from checking.
 *
 * The copy follows how the show itself announced the episode rather than being
 * a second description written for this page. That is not laziness: a press
 * mention that paraphrases itself into different claims invites the reader to
 * check which version the episode actually supports, and this one survives the
 * check because it is the host's own summary.
 *
 * The artwork is served from our own assets rather than hot-linked from
 * img.youtube.com. On a site whose entire pitch is that nothing about your
 * classroom leaves your machine, silently calling a Google CDN on page load is
 * the wrong default, and a self-hosted 148KB JPEG is faster anyway.
 */
function OnTheShow() {
  return (
    <section id="press" className="bg-show-band py-20 sm:py-24">
      <div className="shell grid items-center gap-12 lg:grid-cols-[0.9fr_1.1fr] lg:gap-16">
        <Reveal from="left">
          <p className="eyebrow text-show-band-soft">On the show</p>
          <h2 className="mt-4 text-3xl font-bold text-white sm:text-4xl">
            This was on The Professor Kev Show
          </h2>
          <p className="mt-5 text-lg leading-relaxed text-white/85">
            {PRESS.host} had me on to talk about how a hard summer math class led to a privacy-first
            macOS app: one that monitors Zoom classes, detects when students are struggling in real
            time, and alerts the teacher — all without transmitting student voice data to the cloud.
          </p>
          <a
            href={PRESS.url}
            target="_blank"
            rel="noreferrer"
            className="group mt-8 inline-flex min-h-12 items-center gap-2.5 rounded-full bg-white px-7 text-base font-medium text-[color:var(--show-band)] transition-transform duration-300 hover:scale-[1.04]"
          >
            <Play size={15} fill="currentColor" aria-hidden="true" />
            Watch the full conversation
            <span className="text-[color:var(--show-band)]/60">{PRESS.duration}</span>
          </a>
        </Reveal>

        <Reveal from="right" delay={120}>
          <a
            href={PRESS.url}
            target="_blank"
            rel="noreferrer"
            className="group relative block overflow-hidden rounded-2xl ring-1 ring-white/25 shadow-[0_24px_60px_-20px_rgba(0,0,0,0.7)] transition-transform duration-300 hover:scale-[1.02]"
          >
            <img
              src={episodeShot}
              alt={`Thumbnail for the episode "${PRESS.episode}" — Prof. Kev and Rishab either side of the show's microphone logo.`}
              width={1280}
              height={720}
              loading="lazy"
              className="w-full"
            />
            {/* No caption overlay and no scrim. The artwork already carries
                the episode title, the host's name and both faces — printing our
                own title on top of it just collided with the text that is
                baked into the image. The runtime is not stamped on the frame
                either — the button beside it already says 6:15, and on artwork
                this busy the badge landed against the guest's name. Only the
                play affordance is added. */}
            <span
              aria-hidden
              className="pointer-events-none absolute inset-0 flex items-center justify-center"
            >
              <span className="flex h-16 w-16 items-center justify-center rounded-full bg-white/95 shadow-lg transition-transform duration-300 group-hover:scale-110">
                <Play
                  size={24}
                  fill="currentColor"
                  className="translate-x-0.5 text-[color:var(--show-band)]"
                />
              </span>
            </span>
          </a>
        </Reveal>
      </div>
    </section>
  );
}

function Landing() {
  return (
    <div className="bg-background">
      <SiteNav onLanding />
      <main>
        <Hero />
        <Problem />
        <Solution />
        <Explainability />
        <Dashboard />
        <MenuBar />
        <Impact />
        <HowItWorks />
        <Features />
        <Privacy />
        <Pilots />
        <Faq />
        <About />
        <FinalCta />
        <OnTheShow />
      </main>
      <SiteFooter onLanding />
    </div>
  );
}
