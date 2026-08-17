//
//  PollSchedule.swift
//  Anchor
//
//  How long to wait before asking Zoom again.
//
//  Two different questions wearing the same shape. On the happy path the answer
//  is a cadence — how fresh the dashboard should be, bounded by what the current
//  data source can sustain. After a failure it is a retreat — how long to stay
//  away so a struggling connection is given room to recover instead of being
//  hammered.
//
//  Pulled out of `ZoomViewModel` because it is the part of reconnection that can
//  actually be reasoned about: pure arithmetic over a failure count, a floor and
//  whatever the provider told us. What is left in the view model is the loop
//  itself, which cannot be unit tested and does not need to be — it has one job,
//  which is to wait this long.
//
//  ## Sleep and wake
//
//  Nothing here models a suspended laptop, and nothing needs to. The loop
//  measures elapsed time against a wall clock, so a lid closed for an hour comes
//  back with the interval long since exceeded and syncs immediately. That is the
//  wanted behaviour — a teacher reopening a laptop mid-lesson wants the current
//  roster, not the remainder of a wait that started before lunch. The arithmetic
//  that *does* have to survive a suspend lives in `StruggleSignalHistory`, where
//  crediting is clamped and decay is not.
//

import Foundation

nonisolated enum PollSchedule: Sendable {

    // MARK: - Steady state

    /// Cadence when the last sync succeeded.
    ///
    /// The floor depends on where the data comes from, which is why it is passed
    /// in rather than looked up: a joined bot is read in-process and can honour a
    /// 10-second setting exactly, while the REST Dashboard endpoints are heavily
    /// rate limited and stay at 30 seconds however low the teacher sets the
    /// picker. Settings explains the gap rather than appearing to ignore what
    /// they chose.
    static func steadyInterval(floor: TimeInterval, chosen: TimeInterval) -> TimeInterval {
        max(floor, chosen)
    }

    // MARK: - Backoff

    /// Fraction of the base interval added as jitter, so several clients that
    /// failed on the same outage don't come back in lockstep.
    static let jitterSpread: Double = 0.2

    /// Ceiling on a single wait.
    ///
    /// Only reachable through a provider-supplied `Retry-After`, since the ladder
    /// tops out below it. A rate-limit header is trusted, but not unboundedly: a
    /// bogus or wildly long value would otherwise park a live lesson until after
    /// the bell, and retrying four times an hour is more useful to a teacher than
    /// not retrying at all.
    static let maximumInterval: TimeInterval = 900

    /// How long to wait after `consecutiveFailures` consecutive failures.
    ///
    /// - Parameters:
    ///   - consecutiveFailures: 1 for the first failure. Values past the end of
    ///     the ladder hold at its last rung rather than growing without bound.
    ///   - jitterFraction: 0...1, drawn **once per retry** by the caller. It is a
    ///     parameter rather than a `Double.random` call inside here for two
    ///     reasons: it makes this testable, and it makes the single-draw
    ///     requirement visible at the call site. Re-drawing it on every tick of a
    ///     wait loop collapses the jitter toward the base value and undoes the
    ///     decorrelation it exists for.
    ///   - retryAfter: the provider's own `Retry-After`, when it sent one.
    static func retryInterval(
        consecutiveFailures: Int,
        jitterFraction: Double,
        retryAfter: TimeInterval? = nil
    ) -> TimeInterval {
        let ladder = ZoomConfig.backoffLadder
        let index = min(max(0, consecutiveFailures - 1), ladder.count - 1)
        let base = ladder[index]
        let jittered = base + base * jitterSpread * min(1, max(0, jitterFraction))

        // Zoom answering "come back in N seconds" is better information than any
        // ladder, and it was being parsed and thrown away: `rateLimited` has
        // carried a `retryAfter` from the start and nothing ever read it, so a
        // 429 saying "wait two minutes" was answered fifteen seconds later. Each
        // early retry earns another 429, walks the ladder up, and on some
        // providers extends the penalty — the loop digs itself in exactly when it
        // most needs to stop.
        //
        // Taken as a floor rather than an override: after five failures the
        // ladder's five minutes is the more cautious number, and a provider
        // asking for two seconds should not talk us out of it.
        guard let retryAfter, retryAfter.isFinite, retryAfter > 0 else {
            return min(jittered, maximumInterval)
        }
        return min(max(jittered, retryAfter), maximumInterval)
    }
}
