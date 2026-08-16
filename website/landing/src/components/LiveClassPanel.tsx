import { useEffect, useState } from "react";
import { Mic, MicOff, Video, VideoOff, TrendingDown } from "lucide-react";

type Student = {
  name: string;
  muted: boolean;
  camera: boolean;
  score: number; // 0-100 struggle score
};

const ROSTER: Student[] = [
  { name: "Ava R.", muted: false, camera: true, score: 12 },
  { name: "Noah P.", muted: true, camera: true, score: 21 },
  { name: "Mia T.", muted: true, camera: false, score: 74 },
  { name: "Liam K.", muted: false, camera: true, score: 8 },
  { name: "Zoe C.", muted: true, camera: true, score: 33 },
  { name: "Ethan W.", muted: false, camera: true, score: 17 },
];

const ALERT_INDEX = 2;

/**
 * LiveClassPanel — a glass "class in session" card. Tiles breathe, signals
 * flicker, and one student quietly slips into the red while Anchor flags them.
 */
export function LiveClassPanel() {
  const [tick, setTick] = useState(0);
  const [alerted, setAlerted] = useState(false);
  const [score, setScore] = useState(38);

  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 1400);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    const reveal = setTimeout(() => setAlerted(true), 2200);
    return () => clearTimeout(reveal);
  }, []);

  useEffect(() => {
    if (!alerted) return;
    let v = 38;
    const id = setInterval(() => {
      v = Math.min(74, v + 2);
      setScore(v);
      if (v >= 74) clearInterval(id);
    }, 40);
    return () => clearInterval(id);
  }, [alerted]);

  return (
    <div className="relative w-full max-w-md">
      <div
        aria-hidden
        className="absolute -inset-6 rounded-[2rem] bg-primary/20 blur-3xl"
        style={{ opacity: alerted ? 0.55 : 0.3, transition: "opacity 1.2s ease" }}
      />
      <div className="relative overflow-hidden rounded-3xl border border-white/10 bg-white/[0.06] p-4 shadow-2xl backdrop-blur-xl">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="relative flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-primary opacity-70" />
              <span className="relative inline-flex h-2 w-2 rounded-full bg-primary" />
            </span>
            <p className="text-sm font-medium text-foreground-invert">Algebra II · Live</p>
          </div>
          <p className="text-xs text-muted-invert">24 students</p>
        </div>

        <div className="mt-4 grid grid-cols-3 gap-2.5">
          {ROSTER.map((s, i) => {
            const isAlert = alerted && i === ALERT_INDEX;
            const speaking = !s.muted && (tick + i) % 3 === 0;
            return (
              <div
                key={s.name}
                className="relative aspect-[4/3] overflow-hidden rounded-xl border bg-black/30 transition-all duration-700"
                style={{
                  borderColor: isAlert
                    ? "color-mix(in oklab, oklch(0.63 0.21 25) 75%, transparent)"
                    : speaking
                      ? "color-mix(in oklab, var(--primary) 60%, transparent)"
                      : "rgba(255,255,255,0.08)",
                  boxShadow: isAlert
                    ? "0 0 0 1px color-mix(in oklab, oklch(0.63 0.21 25) 50%, transparent), 0 8px 30px -8px oklch(0.63 0.21 25 / 0.6)"
                    : speaking
                      ? "0 0 18px -6px color-mix(in oklab, var(--primary) 80%, transparent)"
                      : "none",
                }}
              >
                <div
                  className="absolute inset-0 transition-opacity duration-700"
                  style={{
                    background: isAlert
                      ? "radial-gradient(120% 100% at 50% 100%, oklch(0.63 0.21 25 / 0.35), transparent 70%)"
                      : "radial-gradient(120% 100% at 50% 100%, color-mix(in oklab, var(--primary) 18%, transparent), transparent 70%)",
                  }}
                />
                <div className="absolute inset-x-2 bottom-1.5 flex items-center justify-between">
                  <span className="truncate text-[11px] font-medium text-foreground-invert/90">
                    {s.name}
                  </span>
                  <span className="flex items-center gap-1 text-foreground-invert/70">
                    {s.muted ? <MicOff size={11} /> : <Mic size={11} />}
                    {s.camera ? <Video size={11} /> : <VideoOff size={11} />}
                  </span>
                </div>
              </div>
            );
          })}
        </div>

        <div
          className="mt-4 flex items-center gap-3 rounded-2xl border border-white/10 bg-black/30 p-3 transition-all duration-700"
          style={{ opacity: alerted ? 1 : 0, transform: `translateY(${alerted ? 0 : 8}px)` }}
        >
          <div
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full"
            style={{ background: "oklch(0.63 0.21 25 / 0.18)", color: "oklch(0.72 0.18 25)" }}
          >
            <TrendingDown size={16} />
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium text-foreground-invert">
              Mia T. needs support
            </p>
            <p className="truncate text-xs text-muted-invert">
              Silent 14 min · 2 missed assignments
            </p>
          </div>
          <div className="text-right">
            <p
              className="text-base font-semibold tabular-nums"
              style={{ color: "oklch(0.72 0.18 25)" }}
            >
              {score}
            </p>
            <p className="text-[10px] uppercase tracking-wider text-muted-invert">risk</p>
          </div>
        </div>
      </div>
    </div>
  );
}
