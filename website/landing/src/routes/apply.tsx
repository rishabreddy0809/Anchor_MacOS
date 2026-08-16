import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowLeft, Check } from "lucide-react";

import { PilotForm } from "@/components/PilotForm";
import { SiteNav } from "@/components/SiteNav";
import { SiteFooter } from "@/components/SiteFooter";
import { PILOT_TERMS, PILOT_TERMS_SETTLED, REQUIREMENTS, absoluteUrl } from "@/lib/site";

export const Route = createFileRoute("/apply")({
  head: () => ({
    meta: [
      { title: "Apply for the pilot — Anchor" },
      {
        name: "description",
        content:
          "Apply to join the free Anchor pilot. A Mac, a Zoom account and permission to run it in your classroom is all it takes.",
      },
      { property: "og:title", content: "Apply for the Anchor pilot" },
      {
        property: "og:description",
        content: "A small first group of teachers who teach live on Zoom. Free.",
      },
      { property: "og:type", content: "website" },
      { property: "og:url", content: absoluteUrl("/apply") },
    ],
    links: [{ rel: "canonical", href: absoluteUrl("/apply") }],
  }),
  component: Apply,
});

/**
 * The application form on its own page rather than inline on the landing page.
 *
 * A form buried two-thirds down a marketing page competes with everything above
 * it; here the only thing to do is fill it in. It carries just enough context to
 * decide — the requirements and the terms summary — because a teacher arriving
 * from a shared link has read nothing else.
 */
function Apply() {
  return (
    <div className="min-h-screen bg-background">
      <SiteNav />

      {/* pt clears the fixed nav (h-16 / sm:h-20) */}
      <main className="shell pt-32 pb-20 sm:pt-40 sm:pb-28">
        <div className="mx-auto max-w-5xl">
          <Link
            to="/"
            className="inline-flex min-h-11 items-center gap-2 text-sm text-muted-foreground transition-colors hover:text-foreground"
          >
            <ArrowLeft size={16} aria-hidden="true" />
            Back to site
          </Link>

          <p className="eyebrow mt-8 text-muted-foreground">The pilot</p>
          <h1 className="mt-4 text-4xl font-bold tracking-tight sm:text-5xl">
            Apply for the pilot
          </h1>
          <p className="mt-5 max-w-2xl text-lg text-muted-foreground">
            A small first group of teachers who teach live on Zoom. It's free, it's early, and a
            real person reads every application and writes back.
          </p>

          <div className="mt-14 grid items-start gap-8 lg:grid-cols-[0.85fr_1.15fr]">
            <aside className="space-y-6">
              <div className="rounded-3xl border border-border bg-surface-soft p-7 sm:p-8">
                <h2 className="text-lg font-semibold">Before you start</h2>
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

              <div className="rounded-3xl border border-border bg-card p-7 sm:p-8">
                <h2 className="text-lg font-semibold">What you're agreeing to</h2>
                <dl className="mt-6 space-y-4">
                  {PILOT_TERMS.map((t) => (
                    <div key={t.label}>
                      <dt className="eyebrow text-muted-foreground">{t.label}</dt>
                      <dd className="mt-1">
                        {t.value ?? (
                          <span className="rounded bg-destructive/15 px-1.5 py-0.5 font-medium text-foreground">
                            TODO: {t.hint}
                          </span>
                        )}
                      </dd>
                    </div>
                  ))}
                </dl>
                <p className="mt-6 border-t border-border pt-5 text-sm text-muted-foreground">
                  {PILOT_TERMS_SETTLED ? (
                    <>
                      In full in the{" "}
                      <Link className="text-primary underline underline-offset-4" to="/pilot-terms">
                        Pilot Program Terms
                      </Link>
                      .
                    </>
                  ) : (
                    <>
                      We're still working these out. Ask when you apply and you'll get a straight
                      answer.
                    </>
                  )}
                </p>
              </div>
            </aside>

            <PilotForm />
          </div>
        </div>
      </main>

      <SiteFooter />
    </div>
  );
}
