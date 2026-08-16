import { Link } from "@tanstack/react-router";
import { Anchor as AnchorIcon, ChevronDown, Menu, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";

/**
 * The single navigation for the whole site.
 *
 * Every destination is reachable from here: each section of the landing page
 * and both legal pages. Flat, that is eleven links and far too wide, so the
 * secondary sections and the legal pages sit in two dropdowns. Everything is
 * listed openly in the mobile sheet, where vertical space is free.
 *
 * `onLanding` decides whether section links are in-page anchors or have to
 * navigate home first — a bare `#features` on /privacy points at nothing.
 */

type Item = { label: string; href: string };

/** Always visible on desktop. The path a first-time visitor is likely to take. */
const PRIMARY: Item[] = [
  { label: "How it works", href: "#how-it-works" },
  { label: "Pilots", href: "#pilots" },
  { label: "FAQ", href: "#faq" },
];

/** The rest of the landing page, grouped under "More". */
const MORE: Item[] = [
  { label: "The problem", href: "#problem" },
  { label: "Detection", href: "#solution" },
  { label: "Teacher impact", href: "#impact" },
  { label: "Features", href: "#features" },
  { label: "Privacy & security", href: "#security" },
  { label: "Who's behind Anchor", href: "#about" },
];

/** Real routes, not anchors. */
const LEGAL: Item[] = [
  { label: "Privacy Policy", href: "/privacy" },
  { label: "Terms of Service", href: "/terms" },
  { label: "Pilot Program Terms", href: "/pilot-terms" },
];

function useDismissable(onClose: () => void) {
  const ref = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose();
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [onClose]);
  return ref;
}

function Dropdown({
  label,
  items,
  resolve,
}: {
  label: string;
  items: Item[];
  resolve: (href: string) => string;
}) {
  const [open, setOpen] = useState(false);
  const ref = useDismissable(() => setOpen(false));

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        aria-expanded={open}
        aria-haspopup="true"
        onClick={() => setOpen((v) => !v)}
        className="inline-flex items-center gap-1 text-sm text-muted-invert transition-colors duration-300 hover:text-foreground-invert"
      >
        {label}
        <ChevronDown
          size={14}
          aria-hidden="true"
          className={`transition-transform duration-200 ${open ? "rotate-180" : ""}`}
        />
      </button>

      {open && (
        <ul className="absolute right-0 top-full z-50 mt-3 min-w-56 overflow-hidden rounded-2xl border border-hairline bg-surface-deep/95 py-2 shadow-2xl backdrop-blur-xl">
          {items.map((item) => (
            <li key={item.href}>
              {item.href.startsWith("/") ? (
                <Link
                  to={item.href}
                  onClick={() => setOpen(false)}
                  className="flex min-h-11 items-center px-5 text-sm text-muted-invert transition-colors hover:bg-white/5 hover:text-foreground-invert"
                >
                  {item.label}
                </Link>
              ) : (
                <a
                  href={resolve(item.href)}
                  onClick={() => setOpen(false)}
                  className="flex min-h-11 items-center px-5 text-sm text-muted-invert transition-colors hover:bg-white/5 hover:text-foreground-invert"
                >
                  {item.label}
                </a>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export function SiteNav({ onLanding = false }: { onLanding?: boolean }) {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  // Lock the page behind the open mobile sheet.
  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [open]);

  const resolve = (href: string) => (onLanding ? href : `/${href}`);

  // The transparent state only works over the hero. Every other page has a light
  // background, where transparent would leave white-on-white links.
  const solid = !onLanding || scrolled || open;

  return (
    <header
      className={`fixed inset-x-0 top-0 z-50 transition-all duration-500 ${
        solid ? "border-b border-hairline bg-surface-deep/80 backdrop-blur-xl" : "bg-transparent"
      }`}
    >
      <nav aria-label="Main" className="shell flex h-16 items-center justify-between sm:h-20">
        <a
          href={resolve("#top")}
          className="inline-flex items-center gap-2 text-lg font-semibold tracking-tight text-foreground-invert"
        >
          <AnchorIcon className="h-5 w-5 shrink-0" aria-hidden="true" />
          Anchor
        </a>

        <ul className="hidden items-center gap-7 lg:flex">
          {PRIMARY.map((n) => (
            <li key={n.href}>
              <a
                href={resolve(n.href)}
                className="text-sm text-muted-invert transition-colors duration-300 hover:text-foreground-invert"
              >
                {n.label}
              </a>
            </li>
          ))}
          <li>
            <Dropdown label="More" items={MORE} resolve={resolve} />
          </li>
          <li>
            <Dropdown label="Legal" items={LEGAL} resolve={resolve} />
          </li>
          <li>
            <a
              href={resolve("#contact")}
              className="text-sm text-muted-invert transition-colors duration-300 hover:text-foreground-invert"
            >
              Contact
            </a>
          </li>
        </ul>

        <div className="flex items-center gap-3">
          <Link
            to="/apply"
            className="hidden min-h-11 items-center rounded-full bg-primary px-5 text-sm font-medium text-primary-foreground transition-transform duration-300 hover:scale-[1.04] lg:inline-flex"
          >
            Get Started
          </Link>
          <button
            type="button"
            aria-label={open ? "Close menu" : "Open menu"}
            aria-expanded={open}
            onClick={() => setOpen((v) => !v)}
            className="grid h-11 w-11 place-items-center rounded-full border border-hairline text-foreground-invert lg:hidden"
          >
            {open ? <X size={18} /> : <Menu size={18} />}
          </button>
        </div>
      </nav>

      {open && (
        <div className="max-h-[calc(100vh-4rem)] overflow-y-auto border-t border-hairline bg-surface-deep lg:hidden">
          <div className="shell py-6">
            <MobileGroup
              title="Explore"
              items={PRIMARY}
              resolve={resolve}
              close={() => setOpen(false)}
            />
            <MobileGroup title="More" items={MORE} resolve={resolve} close={() => setOpen(false)} />
            <MobileGroup
              title="Legal"
              items={LEGAL}
              resolve={resolve}
              close={() => setOpen(false)}
            />

            <a
              href={resolve("#contact")}
              onClick={() => setOpen(false)}
              className="mt-6 flex min-h-12 items-center text-base text-foreground-invert"
            >
              Contact
            </a>
            <Link
              to="/apply"
              onClick={() => setOpen(false)}
              className="mt-3 inline-flex min-h-12 w-full items-center justify-center rounded-full bg-primary px-6 text-base font-medium text-primary-foreground"
            >
              Get Started
            </Link>
          </div>
        </div>
      )}
    </header>
  );
}

function MobileGroup({
  title,
  items,
  resolve,
  close,
}: {
  title: string;
  items: Item[];
  resolve: (href: string) => string;
  close: () => void;
}) {
  return (
    <div className="border-b border-hairline pb-4 last:border-b-0">
      <p className="eyebrow mt-4 text-muted-invert">{title}</p>
      <ul className="mt-1">
        {items.map((item) => (
          <li key={item.href}>
            {item.href.startsWith("/") ? (
              <Link
                to={item.href}
                onClick={close}
                className="flex min-h-12 items-center text-base text-foreground-invert"
              >
                {item.label}
              </Link>
            ) : (
              <a
                href={resolve(item.href)}
                onClick={close}
                className="flex min-h-12 items-center text-base text-foreground-invert"
              >
                {item.label}
              </a>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
