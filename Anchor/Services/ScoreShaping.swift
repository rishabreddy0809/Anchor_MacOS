//
//  ScoreShaping.swift
//  Anchor
//
//  Two adjustments applied to a struggle score after the model has spoken, both
//  about *time* — the dimension a single-poll feature vector can't see.
//
//  ## ObservationRamp — nothing is known at minute zero
//
//  A class opens with everyone muted, cameras settling, nobody speaking yet.
//  That is indistinguishable, feature by feature, from a room full of
//  disengaged students, so an un-ramped score lights the dashboard red in the
//  first thirty seconds and cries wolf before the lesson starts. The ramp holds
//  scores at zero on first sighting and grows them to full weight over the first
//  ten minutes of *observation* — per student, so someone who joins late ramps
//  from their own arrival rather than inheriting the room's clock.
//
//  ## EngagementDrift — being engaged early doesn't stay true
//
//  The engagement counters only grow, so a student who answered two questions in
//  the first five minutes keeps that credit for the rest of the hour. Losing
//  someone at minute forty is exactly the case Anchor exists to catch, and it is
//  invisible to a cumulative total. This layer reads the decayed counters in
//  `StruggleSignalHistory` and raises the score of a student who *was*
//  participating and has since gone quiet.
//
//  Both are deliberately rules rather than model features: the shipped model was
//  trained on whole-session aggregates and has no column for "how long have we
//  been watching" or "how long since they last spoke".
//

import Foundation

// MARK: - Warm-up

nonisolated enum ObservationRamp: Sendable {

    /// How long Anchor watches a student before its score carries full weight.
    static let warmUpSeconds: TimeInterval = 600

    /// 0 at first sighting, 1 once `warmUpSeconds` of this student has been seen.
    static func factor(observedSeconds: Int) -> Double {
        guard warmUpSeconds > 0 else { return 1 }
        return min(1, max(0, Double(observedSeconds) / warmUpSeconds))
    }

    /// True while a score is still being held down by the ramp.
    static func isWarmingUp(observedSeconds: Int) -> Bool {
        factor(observedSeconds: observedSeconds) < 1
    }

    /// The line the UI shows so a low early score isn't read as a verdict.
    static func note(observedSeconds: Int) -> String? {
        guard isWarmingUp(observedSeconds: observedSeconds) else { return nil }
        let watched = Int((Double(observedSeconds) / 60).rounded(.down))
        let total = Int(warmUpSeconds / 60)
        return "Warming up (\(watched) of \(total) min observed) — scores stay low "
            + "until Anchor has seen enough of the session to judge."
    }
}

// MARK: - Drift

/// Raises the score of a student who was participating and has gone quiet.
nonisolated struct EngagementDrift: Sendable {

    /// Silence shorter than this is just listening, not drifting.
    static let graceSeconds: TimeInterval = 300
    /// Struggle points added per minute of silence beyond the grace period.
    static let pointsPerMinute: Double = 0.02
    /// Ceiling on the whole adjustment, so drift can nudge a score but never
    /// manufacture a red flag on its own.
    static let maximumAdjustment: Double = 0.15

    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    struct Result: Equatable, Sendable {
        var adjustedScore: Double
        /// How long they've been quiet, when that's the reason for the change.
        var quietSeconds: TimeInterval?
        var addedPoints: Double

        var didDrift: Bool { addedPoints > 0 }

        /// Whole struggle points, for display.
        var impactPoints: Int { Int((addedPoints * 100).rounded()) }
    }

    func apply(to score: Double, history: StruggleSignalHistory) -> Result {
        // Never engaged means nothing to drift *from*. A student who has been
        // quiet all hour is the model's problem, not this layer's — double
        // counting them here would punish the same silence twice.
        guard let lastEngagementAt = history.lastEngagementAt else {
            return Result(adjustedScore: score, quietSeconds: nil, addedPoints: 0)
        }

        let quiet = now.timeIntervalSince(lastEngagementAt)
        guard quiet > Self.graceSeconds else {
            return Result(adjustedScore: score, quietSeconds: quiet, addedPoints: 0)
        }

        let minutesBeyondGrace = (quiet - Self.graceSeconds) / 60
        let added = min(Self.maximumAdjustment, minutesBeyondGrace * Self.pointsPerMinute)

        return Result(
            adjustedScore: min(1, score + added),
            quietSeconds: quiet,
            addedPoints: added
        )
    }

    /// The teacher-facing reason, when the adjustment fired.
    static func recommendation(for result: Result, name: String) -> String? {
        guard result.didDrift, let quiet = result.quietSeconds else { return nil }
        let minutes = Int((quiet / 60).rounded())
        return "\(name) was participating earlier but hasn't spoken in \(minutes) min — "
            + "a direct, low-stakes question is the cheapest way to find out why."
    }
}

// MARK: - Recovery

/// Lowers the score of a student who has started participating again.
///
/// The mirror of `EngagementDrift`, and needed for the same reason. The model's
/// `speaking_duration` and `time_unmuted` are whole-session totals that only
/// ever grow, so a student who was silent for half an hour and then talks
/// steadily for two minutes barely moves them — the session average still says
/// "quiet". Drift stopping is not enough on its own either: that only removes
/// the penalty for going quiet, leaving the score exactly where it was before
/// they spoke, which reads to a teacher as Anchor ignoring the student in front
/// of them putting their hand up.
///
/// This reads `recentTalkingSeconds`, the decayed counter
/// `StruggleSignalHistory` already maintains and — until now — nothing consumed.
/// Because it decays, the credit fades on its own once they stop again, so
/// recovery can never become permanent immunity.
///
/// Bounded twice, so repeated speech cannot walk a score down to nothing: the
/// reduction is a function of the *current* decayed counter rather than a tally
/// of past reductions, and it saturates at `maximumReduction`. Every poll
/// recomputes the whole chain from the model's score, so nothing here
/// accumulates across polls.
nonisolated struct EngagementRecovery: Sendable {

    /// Below this, recent speech is a cough or a "yeah" — not participation.
    static let meaningfulSeconds: Double = 15
    /// Recent talking at or above this earns the full reduction.
    static let fullCreditSeconds: Double = 90
    /// Ceiling on the reduction. Matches `EngagementDrift.maximumAdjustment`, so
    /// coming back is worth exactly what going quiet cost.
    static let maximumReduction: Double = 0.15

    struct Result: Equatable, Sendable {
        var adjustedScore: Double
        /// Decayed talking seconds behind the credit, for the teacher-facing note.
        var recentTalkingSeconds: Double
        var removedPoints: Double

        var didRecover: Bool { removedPoints > 0 }
        var impactPoints: Int { Int((removedPoints * 100).rounded()) }
    }

    func apply(
        to score: Double,
        history: StruggleSignalHistory,
        now: Date = Date()
    ) -> Result {
        let recent = history.recentTalkingSeconds

        guard recent > Self.meaningfulSeconds else {
            return Result(adjustedScore: score, recentTalkingSeconds: recent, removedPoints: 0)
        }

        // Recency gate, and the reason it has to exist: `recentTalkingSeconds`
        // saturates near 300s under continuous speech and decays with the same
        // 300s constant, so a student who talked a lot keeps *most* of a full
        // credit for ten minutes after falling silent. Drift starts penalising
        // at five. Without this guard the two overlap for that whole window and
        // recovery swamps the very signal drift exists to raise — a student who
        // has said nothing for eight minutes reads as recovering.
        //
        // Handing the regimes to one layer each keeps the score honest: inside
        // the grace period this owns it, past it drift does.
        guard let lastEngagementAt = history.lastEngagementAt,
              now.timeIntervalSince(lastEngagementAt) <= EngagementDrift.graceSeconds
        else {
            return Result(adjustedScore: score, recentTalkingSeconds: recent, removedPoints: 0)
        }

        let span = Self.fullCreditSeconds - Self.meaningfulSeconds
        let fraction = min(1, (recent - Self.meaningfulSeconds) / span)
        let removed = Self.maximumReduction * fraction

        return Result(
            adjustedScore: max(0, score - removed),
            recentTalkingSeconds: recent,
            removedPoints: removed
        )
    }

    /// The teacher-facing reason, when the reduction fired.
    ///
    /// Worth saying out loud: a score that drops without explanation is as
    /// confusing as one that rises without explanation, and this is the good
    /// news — the student came back.
    static func note(for result: Result, name: String) -> String? {
        guard result.didRecover else { return nil }
        let seconds = Int(result.recentTalkingSeconds.rounded())
        return "\(name) has been talking again in the last few minutes "
            + "(\(seconds)s) — score lowered to match."
    }
}
