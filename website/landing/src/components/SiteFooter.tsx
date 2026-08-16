import { Link } from "@tanstack/react-router";
import { Anchor as AnchorIcon, Mail } from "lucide-react";

import { CONTACT_EMAIL } from "@/lib/site";

/**
 * Shared by the landing page and the legal pages so the Privacy and Terms links
 * can never drift apart between them.
 *
 * The contact link differs by page: on `/` it is an in-page anchor, elsewhere it
 * has to navigate back to the landing page first.
 *
 * There are deliberately no social icons. Anchor has no LinkedIn or Twitter
 * account, and the previous buttons pointed at those sites' bare homepages.
 */
export function SiteFooter({ onLanding = false }: { onLanding?: boolean }) {
  const contactHref = onLanding ? "#contact" : "/#contact";

  return (
    <footer className="border-t border-hairline bg-black py-12">
      <div className="shell flex flex-col gap-8 sm:flex-row sm:items-center sm:justify-between">
        <Link
          to="/"
          className="inline-flex items-center gap-2 text-lg font-semibold text-foreground-invert"
        >
          <AnchorIcon className="h-5 w-5 shrink-0" aria-hidden="true" />
          Anchor
        </Link>

        <nav aria-label="Footer">
          <ul className="flex flex-wrap gap-6 text-sm text-muted-invert">
            <li>
              <a href={contactHref} className="transition-colors hover:text-foreground-invert">
                Contact
              </a>
            </li>
            <li>
              <Link to="/privacy" className="transition-colors hover:text-foreground-invert">
                Privacy
              </Link>
            </li>
            <li>
              <Link to="/terms" className="transition-colors hover:text-foreground-invert">
                Terms
              </Link>
            </li>
            <li>
              <Link to="/pilot-terms" className="transition-colors hover:text-foreground-invert">
                Pilot terms
              </Link>
            </li>
          </ul>
        </nav>

        <a
          href={`mailto:${CONTACT_EMAIL}`}
          className="inline-flex min-h-11 items-center gap-2 rounded-full border border-hairline px-5 text-sm text-muted-invert transition-colors hover:text-foreground-invert"
        >
          <Mail size={16} aria-hidden="true" />
          {CONTACT_EMAIL}
        </a>
      </div>

      <div className="shell mt-8 text-xs text-muted-invert">
        © {new Date().getFullYear()} Anchor. All rights reserved.
      </div>
    </footer>
  );
}
