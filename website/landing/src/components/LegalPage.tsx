import { Link } from "@tanstack/react-router";
import { ArrowLeft } from "lucide-react";
import type { ReactNode } from "react";

import { SiteNav } from "@/components/SiteNav";
import { SiteFooter } from "@/components/SiteFooter";
import { LEGAL_LAST_UPDATED } from "@/lib/site";

export type LegalSection = { id: string; heading: string };

/**
 * Layout for the Privacy Policy and Terms pages.
 *
 * These are read in two ways: skimmed by a teacher deciding whether to trust the
 * app, and read closely by a school administrator or a Google OAuth reviewer.
 * The contents list serves the first, deep-linkable section ids serve the second.
 */
export function LegalPage({
  title,
  summary,
  sections,
  children,
}: {
  title: string;
  summary: string;
  sections: LegalSection[];
  children: ReactNode;
}) {
  return (
    <div className="min-h-screen bg-background">
      <SiteNav />

      {/* pt clears the fixed nav (h-16 / sm:h-20) */}
      <main className="shell pt-32 pb-16 sm:pt-40 sm:pb-24">
        <div className="mx-auto max-w-3xl">
          <Link
            to="/"
            className="inline-flex min-h-11 items-center gap-2 text-sm text-muted-foreground transition-colors hover:text-foreground"
          >
            <ArrowLeft size={16} aria-hidden="true" />
            Back to site
          </Link>

          <p className="eyebrow mt-8 text-muted-foreground">Legal</p>
          <h1 className="mt-4 text-4xl font-bold tracking-tight sm:text-5xl">{title}</h1>
          <p className="mt-5 text-lg text-muted-foreground">{summary}</p>
          <p className="mt-4 text-sm text-muted-foreground">Last updated {LEGAL_LAST_UPDATED}</p>

          <nav
            aria-label="On this page"
            className="mt-12 rounded-2xl border border-border bg-card p-7"
          >
            <h2 className="text-sm font-semibold">On this page</h2>
            <ol className="mt-4 space-y-2 text-sm">
              {sections.map((s, i) => (
                <li key={s.id}>
                  <a
                    href={`#${s.id}`}
                    className="text-muted-foreground underline-offset-4 transition-colors hover:text-primary hover:underline"
                  >
                    <span className="tabular-nums">{i + 1}.</span> {s.heading}
                  </a>
                </li>
              ))}
            </ol>
          </nav>

          <div className="legal-prose mt-14">{children}</div>
        </div>
      </main>

      <SiteFooter />
    </div>
  );
}

/** A numbered section. `id` must match the entry in the contents list. */
export function LegalSectionBody({
  id,
  index,
  heading,
  children,
}: {
  id: string;
  index: number;
  heading: string;
  children: ReactNode;
}) {
  return (
    <section
      id={id}
      className="scroll-mt-24 border-t border-border pt-10 first:border-t-0 first:pt-0"
    >
      <h2 className="text-2xl font-bold tracking-tight">
        <span className="mr-3 text-muted-foreground tabular-nums">{index}.</span>
        {heading}
      </h2>
      <div className="mt-5 space-y-4">{children}</div>
    </section>
  );
}
