"use client";

import { motion, useReducedMotion } from "framer-motion";
import { useEffect, useState, type ReactNode } from "react";
import CubeField from "../components/CubeField";

const ease = [0.22, 1, 0.36, 1] as const;

const reveal = {
  hidden: { opacity: 0, y: 18 },
  visible: { opacity: 1, y: 0, transition: { duration: 0.6, ease } },
};

function Reveal({
  children,
  className,
  delay = 0,
}: {
  children: ReactNode;
  className?: string;
  delay?: number;
}) {
  const reduceMotion = useReducedMotion();

  return (
    <motion.div
      className={className}
      initial={reduceMotion ? "visible" : "hidden"}
      whileInView="visible"
      viewport={{ once: true, amount: 0.25 }}
      variants={{
        hidden: reveal.hidden,
        visible: { ...reveal.visible, transition: { ...reveal.visible.transition, delay } },
      }}
    >
      {children}
    </motion.div>
  );
}

function Wordmark({ className = "" }: { className?: string }) {
  return (
    <a href="#top" className={`wordmark ${className}`} aria-label="Anchor home">
      Anchor
    </a>
  );
}

/* ---------------------------------------------------------------- icons */

function QuizIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true" className="h-5 w-5">
      <path d="M7 4h10a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z" stroke="currentColor" strokeWidth="1.5" />
      <path d="m8.5 10.5 1.5 1.5 3-3.5M8.5 16h3M14.5 16h1.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function PodcastIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true" className="h-5 w-5">
      <rect x="9" y="3" width="6" height="11" rx="3" stroke="currentColor" strokeWidth="1.5" />
      <path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3M9.5 21h5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

function VoiceIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true" className="h-5 w-5">
      <path d="M4 14h2.5L11 17.5v-11L6.5 10H4v4Z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
      <path d="M14.5 9.5a3.5 3.5 0 0 1 0 5M17.5 7a7 7 0 0 1 0 10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

function ShieldIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true" className="h-4 w-4">
      <path d="M12 3.5 5.5 6v5.5c0 4 2.7 7.2 6.5 8.5 3.8-1.3 6.5-4.5 6.5-8.5V6L12 3.5Z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
      <path d="m9.3 12 1.9 1.9 3.6-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/* ---------------------------------------------------------------- mockups */

function PhoneMockup() {
  const bars = [40, 68, 32, 84, 55, 92, 47, 74, 38, 61, 29, 80, 44, 66, 35];

  return (
    <div className="phone">
      <div className="phone-screen">
        <div className="phone-notch" />

        <div className="flex items-center justify-between">
          <span className="inline-flex items-center gap-2 rounded-full bg-white/10 px-2.5 py-1 text-[0.65rem] font-medium text-white/80">
            <span className="pill-dot" />
            Buffering
          </span>
          <span className="text-[0.65rem] tabular-nums text-white/45">02:47 / 03:00</span>
        </div>

        <div className="wave mt-5" aria-hidden="true">
          {bars.map((height, index) => (
            <span
              key={index}
              style={{ height: `${height}%`, "--d": `${index * 30}ms` } as React.CSSProperties}
            />
          ))}
        </div>

        <div className="mt-6 rounded-2xl bg-white/[0.07] p-3.5">
          <p className="text-[0.62rem] font-semibold uppercase tracking-[0.14em] text-white/40">
            Last 3 minutes
          </p>
          <p className="mt-2 text-[0.82rem] font-medium leading-snug text-white">
            She defined enthalpy, then worked example 4 on the board.
          </p>
          <div className="mt-3 space-y-2" aria-hidden="true">
            <div className="recap-line w-full" />
            <div className="recap-line w-11/12" />
            <div className="recap-line w-7/12" />
          </div>
        </div>

        <div className="mt-4 grid h-11 place-items-center rounded-full bg-white text-[0.85rem] font-semibold text-[#0b0b0c]">
          Catch Me Up
        </div>

        <p className="mt-3 text-center text-[0.62rem] text-white/35">Processed on device</p>
      </div>
    </div>
  );
}

/**
 * Stand-in for the product video.
 *
 * TO SWAP IN THE REAL VIDEO: drop the file in `website/public/` (e.g.
 * `public/demo.mp4`, plus a `public/demo-poster.jpg` still frame), then
 * replace the <div className="video-empty"> block below with:
 *
 *   <video
 *     className="video-media"
 *     src="/demo.mp4"
 *     poster="/demo-poster.jpg"
 *     controls
 *     playsInline
 *     preload="metadata"
 *   />
 *
 * The frame already sets a 16:9 box, rounded corners and overflow clipping,
 * so the video inherits the shape with no further styling.
 */
function VideoPlaceholder() {
  return (
    <div className="video-frame" id="demo">
      <div className="video-empty">
        <span className="video-play" aria-hidden="true">
          <svg viewBox="0 0 24 24" fill="none" className="h-6 w-6">
            <path d="M9 7.5v9l7.5-4.5L9 7.5Z" fill="currentColor" />
          </svg>
        </span>
        <p className="video-title">Demo video goes here</p>
        <p className="video-hint">
          Add <code>public/demo.mp4</code>, then swap the marked block in{" "}
          <code>app/page.tsx</code>
        </p>
      </div>
    </div>
  );
}

function DashboardMockup() {
  const bars = [28, 42, 35, 51, 44, 96, 88, 61, 39, 33];

  return (
    <div className="dashboard">
      <div className="dashboard-bar">
        <span className="dashboard-dot" />
        <span className="dashboard-dot" />
        <span className="dashboard-dot" />
        <p className="ml-2 text-[0.72rem] font-medium text-muted">Chem 2 · Period 4</p>
      </div>

      <div className="p-5 md:p-6">
        <div className="flex items-baseline justify-between">
          <p className="text-sm font-semibold tracking-[-0.02em]">Confusion, live</p>
          <span className="text-[0.7rem] text-muted">last 20 min</span>
        </div>

        <div className="bars mt-5" aria-hidden="true">
          {bars.map((height, index) => (
            <span
              key={index}
              data-peak={height > 80}
              style={{ height: `${height}%`, "--d": `${200 + index * 50}ms` } as React.CSSProperties}
            />
          ))}
        </div>

        <div className="mt-5 flex items-center gap-2 rounded-2xl bg-sand p-3.5">
          <span className="grid h-7 w-7 flex-none place-items-center rounded-full bg-[#ff6d9e] text-[0.7rem] font-semibold text-white">
            9
          </span>
          <p className="text-[0.8rem] leading-snug text-muted">
            <span className="font-semibold text-ink">9 students</span> asked for a recap during
            titration curves.
          </p>
        </div>
      </div>
    </div>
  );
}

/* ---------------------------------------------------------------- content */

const marqueeItems = [
  "Audio never leaves the phone",
  "3-minute rolling buffer",
  "Recaps in about a second",
  "No transcripts stored",
  "Anonymous counts only",
  "Works offline",
];

const learningModes = [
  {
    tint: "tint-violet",
    label: "Quiz me",
    title: "Prove you actually got it",
    body: "Turn the lesson into a short quiz, one question at a time, with a plain explanation whenever you miss one.",
    icon: <QuizIcon />,
  },
  {
    tint: "tint-rose",
    label: "Podcast mode",
    title: "Hear the big picture",
    body: "Reshape dense class material into a natural back-and-forth that connects the ideas and makes them stick.",
    icon: <PodcastIcon />,
  },
  {
    tint: "tint-sky",
    label: "Voice choice",
    title: "A voice you'll remember",
    body: "Pick an expressive narrator style, or a licensed voice from a participating creator. Always labeled, always authorized.",
    icon: <VoiceIcon />,
  },
];

const steps = [
  ["01", "Class starts", "The buffer runs quietly in the background, and you can always see that it's on."],
  ["02", "You lose the thread", "Tap Catch Me Up. The last three minutes get summarized right there on your phone."],
  ["03", "You're back", "A plain-English recap appears in about a second, and the lecture keeps going."],
];

const faqs = [
  [
    "Is my lecture audio uploaded anywhere?",
    "No. Anchor keeps a rolling three-minute buffer in memory on your device and generates the recap locally. The audio is never written to a server, and older audio is overwritten as the buffer rolls.",
  ],
  [
    "What can my teacher actually see?",
    "Anonymous counts, and nothing else. The dashboard shows how many students asked for a recap and roughly when, so a teacher can spot a confusing stretch. No names, no transcripts, no recordings.",
  ],
  [
    "Do I need to record the whole class?",
    "No. Anchor only ever holds the last three minutes. There is no full-session recording to manage, delete, or leak.",
  ],
  [
    "Does it work without a connection?",
    "Yes. Buffering and recaps run on device, so a dead campus Wi-Fi network doesn't stop you catching up.",
  ],
  [
    "Who built this?",
    "Nitin and Rishab — two 14-year-olds who kept zoning out in class and decided to build the thing they wanted to exist.",
  ],
];

/* ---------------------------------------------------------------- page */

export default function Home() {
  const reduceMotion = useReducedMotion();

  return (
    <main id="top">
      <div className="nav-wrap shell">
        <nav className="nav">
          <Wordmark />
          <div className="flex items-center gap-1 sm:gap-6">
            <a href="#modes" className="nav-link hidden md:block">Study modes</a>
            <a href="#students" className="nav-link hidden md:block">For students</a>
            <a href="#teachers" className="nav-link hidden md:block">For teachers</a>
            <a href="#faq" className="nav-link hidden md:block">FAQ</a>
            <a href="#demo" className="btn btn-dark">Try the demo</a>
          </div>
        </nav>
      </div>

      {/* WebGL hero: ~20k GPU-animated cubes with a wave rolling through. */}
      <CubeField />

      <header className="hero">
        <div className="shell">
          <motion.div
            initial={reduceMotion ? "visible" : "hidden"}
            animate="visible"
            variants={{ visible: { transition: { staggerChildren: 0.09, delayChildren: 0.05 } } }}
          >
            <motion.div variants={reveal}>
              <span className="pill">
                <ShieldIcon />
                Built by students, for students
              </span>
            </motion.div>

            <motion.h1 variants={reveal} className="display mt-7">
              You zoned out.
              <br />
              Anchor didn&apos;t.
            </motion.h1>

            <motion.p variants={reveal} className="subhead mx-auto mt-6 max-w-xl">
              A rolling on-device buffer turns the last three minutes of any lecture into an
              instant recap. Your audio never leaves your Mac.
            </motion.p>

            <motion.div variants={reveal} className="mt-9 flex justify-center">
              <a href="#demo" className="btn btn-blue btn-lg">
                Try the demo
              </a>
            </motion.div>

            <motion.p variants={reveal} className="mt-6 text-[0.85rem] text-muted">
              Free for students ·{" "}
              <a href="#how" className="hero-link">
                See how it works
              </a>
            </motion.p>
          </motion.div>
        </div>
      </header>

      <section className="page-solid pt-8">
        <div className="shell">
          <Reveal>
            <VideoPlaceholder />
          </Reveal>
        </div>
      </section>

      <div className="marquee mt-10">
        <div className="marquee-track" aria-hidden="true">
          {[...marqueeItems, ...marqueeItems].map((item, index) => (
            <span key={index} className="marquee-item">
              <span className="h-1.5 w-1.5 rounded-full bg-[#8b7aff]" />
              {item}
            </span>
          ))}
        </div>
      </div>

      <section id="modes" className="section">
        <div className="shell">
          <Reveal className="max-w-2xl">
            <p className="kicker">More than a recap</p>
            <h2 className="headline mt-4">Learn it in the format that makes it click.</h2>
            <p className="subhead mt-5">
              The same private, on-device lesson context can become a quick knowledge check, a
              conversation, or a voice you actually enjoy listening to.
            </p>
          </Reveal>

          <div className="mt-12 grid gap-4 md:grid-cols-3">
            {learningModes.map((mode, index) => (
              <Reveal key={mode.label} delay={index * 0.08}>
                <div className={`card card-tint ${mode.tint} h-full`}>
                  <span className="card-icon">{mode.icon}</span>
                  <p className="kicker mt-8 text-ink/60">{mode.label}</p>
                  <h3 className="mt-3 text-2xl font-semibold tracking-[-0.035em]">{mode.title}</h3>
                  <p className="mt-3 text-[0.95rem] leading-relaxed text-ink/65">{mode.body}</p>
                </div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section id="students" className="section pt-0">
        <div className="shell">
          <div className="grid items-center gap-10 md:grid-cols-2 md:gap-16">
            <Reveal>
              <p className="kicker">For students</p>
              <h2 className="headline mt-4">One button gets you back in the room.</h2>
              <p className="subhead mt-5">
                No note-taking guilt, no asking the person next to you what just happened. Tap once
                and get the last three minutes in plain English, then keep listening.
              </p>
              <ul className="mt-7 space-y-3">
                {[
                  "Recap generated entirely on your device",
                  "Nothing is recorded past the rolling buffer",
                  "Works in lectures, labs, and study groups",
                ].map((item) => (
                  <li key={item} className="flex items-start gap-3 text-[0.95rem] text-muted">
                    <span className="mt-1.5 h-1.5 w-1.5 flex-none rounded-full bg-ink" />
                    {item}
                  </li>
                ))}
              </ul>
            </Reveal>

            <Reveal delay={0.1} className="justify-self-center">
              <PhoneMockup />
            </Reveal>
          </div>
        </div>
      </section>

      <section id="teachers" className="section pt-0">
        <div className="shell">
          <div className="grid items-center gap-10 md:grid-cols-2 md:gap-16">
            <Reveal className="md:order-2">
              <p className="kicker">For teachers</p>
              <h2 className="headline mt-4">Spot confusion while you can fix it.</h2>
              <p className="subhead mt-5">
                When a room full of students quietly loses the thread, you find out on the test.
                Anchor shows you the spike as it happens, using anonymous counts only.
              </p>
              <ul className="mt-7 space-y-3">
                {[
                  "Live view of recap requests by minute",
                  "Anonymous counts sync, never transcripts",
                  "Nothing to install for your students",
                ].map((item) => (
                  <li key={item} className="flex items-start gap-3 text-[0.95rem] text-muted">
                    <span className="mt-1.5 h-1.5 w-1.5 flex-none rounded-full bg-ink" />
                    {item}
                  </li>
                ))}
              </ul>
            </Reveal>

            <Reveal delay={0.1} className="md:order-1">
              <DashboardMockup />
            </Reveal>
          </div>
        </div>
      </section>

      <section id="how" className="section pt-0">
        <div className="shell">
          <Reveal className="max-w-2xl">
            <p className="kicker">How it works</p>
            <h2 className="headline mt-4">From lost to caught up.</h2>
          </Reveal>

          <div className="steps mt-12">
            {steps.map(([number, title, body], index) => (
              <Reveal key={number} delay={index * 0.08} className="step">
                <span className="step-num">{number}</span>
                <h3 className="mt-8 text-xl font-semibold tracking-[-0.03em]">{title}</h3>
                <p className="mt-3 text-[0.95rem] leading-relaxed text-muted">{body}</p>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section id="faq" className="section pt-0">
        <div className="shell grid gap-8 md:grid-cols-[20rem_minmax(0,1fr)] md:gap-16">
          <Reveal>
            <p className="kicker">FAQ</p>
            <h2 className="headline-sm mt-4">The privacy questions, answered.</h2>
          </Reveal>

          <Reveal delay={0.08}>
            <div className="border-t border-[var(--line)]">
              {faqs.map(([question, answer]) => (
                <details key={question} className="faq-item">
                  <summary>
                    {question}
                    <svg viewBox="0 0 16 16" aria-hidden="true" className="faq-sign h-4 w-4">
                      <path d="M8 2v12M2 8h12" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
                    </svg>
                  </summary>
                  <p className="text-[0.95rem] leading-relaxed text-muted">{answer}</p>
                </details>
              ))}
            </div>
          </Reveal>
        </div>
      </section>

      <section className="section pt-0">
        <div className="shell">
          <Reveal>
            <div className="band">
              <h2 className="display mx-auto max-w-3xl">Stop rewinding your own memory.</h2>
              <p className="subhead mx-auto mt-6 max-w-lg text-white/60">
                Anchor keeps the last three minutes so you don&apos;t have to.
              </p>
              <div className="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
                <a href="#demo" className="btn btn-invert btn-lg w-full sm:w-auto">
                  Try the demo
                </a>
                <a href="#how" className="btn btn-lg w-full border border-white/25 text-white hover:bg-white/10 sm:w-auto">
                  How it works
                </a>
              </div>
            </div>
          </Reveal>
        </div>
      </section>

      <footer className="border-t border-[var(--line)]">
        <div className="shell flex flex-col gap-6 py-10 md:flex-row md:items-center md:justify-between">
          <div>
            <Wordmark />
            <p className="mt-2 max-w-md text-[0.85rem] leading-relaxed text-muted">
              Built by Nitin and Rishab — two 14-year-olds turning smart ideas into things people
              can actually use.
            </p>
          </div>
          <div className="flex gap-6 text-[0.85rem] text-muted">
            <a href="#" className="transition-colors hover:text-ink">GitHub</a>
            <a href="#" className="transition-colors hover:text-ink">Devpost</a>
          </div>
        </div>
      </footer>
    </main>
  );
}
