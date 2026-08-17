//
//  AcademicEscalation.swift
//  Anchor
//
//  Raises a struggle score for academic reasons the Core ML model cannot see.
//
//  WHY THIS EXISTS, AND WHEN IT SHOULD STOP
//
//  The shipped model was trained on 11 Zoom features. Google Classroom adds five
//  more, but a model cannot use a column it was never trained on, so until it is
//  retrained the academic signals would have no effect on any score at all.
//
//  Rather than pretend otherwise, this applies an explicit, bounded, fully
//  itemised adjustment on top of the model's prediction. Every point it adds is
//  attributable to a named rule that the teacher can read in the detail view.
//  It is *not* a model output and is never presented as one — `Student.scoreSource`
//  becomes `.modelWithAcademic` so the provenance travels with the number.
//
//  This layer is designed to be deleted. Once a 16-feature model is trained on
//  real labelled data, `StruggleDetectionService.usesAcademicFeatures` returns
//  true, `EscalationPolicy.isActive` returns false, and the model's own learned
//  weights take over. That switch is automatic — see `apply(to:)`.
//
//  The weights below are judgement, not measurement. They are deliberately
//  modest: the largest possible adjustment is +0.20, so academic history can
//  raise a flag but can never on its own manufacture a high-risk student out of
//  someone who is engaged in the room.
//

import Foundation

// MARK: - Reason

/// One named rule that fired, and what it contributed.
struct AcademicFactor: Identifiable, Hashable {
    enum Severity: Hashable {
        case high
        case medium
        /// Evidence the student is coping. Lowers the score rather than raising
        /// it, and is shown differently — a teacher reading a list of concerns
        /// must not mistake "no missing work" for one of them.
        case reassuring

        var label: String {
            switch self {
            case .high: "high weight"
            case .medium: "medium weight"
            case .reassuring: "lowers concern"
            }
        }

        var lowersScore: Bool { self == .reassuring }
    }

    var title: String
    var severity: Severity
    /// Contribution in 0...1 score units.
    var impact: Double

    var id: String { title }

    /// "+3" — the same whole-point unit the model's own factors are shown in.
    /// Negative for a reassurance.
    var impactPoints: Int { Int((impact * 100).rounded()) }

    /// Ready to render, sign included. A reassuring factor reads "−6", so a
    /// teacher scanning the column can see at a glance which way each line
    /// pushed — string interpolation of `"+\(impactPoints)"` would have printed
    /// "+-6".
    var signedPoints: String {
        impactPoints < 0 ? "−\(abs(impactPoints))" : "+\(impactPoints)"
    }
}

// MARK: - Result

struct AcademicEscalationResult: Hashable {
    /// The model's own prediction, before any adjustment.
    var baseScore: Double
    /// After escalation. Never above 0.97, matching the scorer's own ceiling.
    var adjustedScore: Double
    var factors: [AcademicFactor]

    var totalImpact: Double { adjustedScore - baseScore }
    var totalImpactPoints: Int { Int((totalImpact * 100).rounded()) }
    var didEscalate: Bool { totalImpactPoints > 0 }
}

// MARK: - Policy

nonisolated struct AcademicEscalation: Sendable {

    /// Ceiling on the total adjustment. Academic history informs a score; it
    /// does not get to decide one.
    static let maximumAdjustment = 0.20

    /// Floor on the same adjustment, for the evidence that runs the other way —
    /// see `reassurances(for:)`. Half the ceiling, because a clean record is
    /// weaker proof that a quiet student is fine than a pile of missing work is
    /// that they aren't.
    static let maximumReduction = 0.10

    /// Matches `StruggleScoreCalculator`'s ceiling so an escalated score can
    /// never exceed what the scorer itself would produce.
    static let scoreCeiling = 0.97

    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    /// Applies the rules to a model score.
    ///
    /// Returns an unchanged result when there is no academic data, or when the
    /// loaded model already consumes the academic features itself — double
    /// counting would be worse than not counting at all.
    func apply(
        to baseScore: Double,
        snapshot: AcademicSnapshot?,
        modelUsesAcademicFeatures: Bool
    ) -> AcademicEscalationResult {
        guard let snapshot, !snapshot.isEmpty, !modelUsesAcademicFeatures else {
            return AcademicEscalationResult(
                baseScore: baseScore,
                adjustedScore: baseScore,
                factors: []
            )
        }

        let factors = self.factors(for: snapshot)
        let raw = factors.reduce(0) { $0 + $1.impact }
        // Asymmetric on purpose: academic history can raise a score by up to
        // 0.20 and lower it by at most 0.10. Being behind is stronger evidence
        // that something is wrong than being up to date is evidence that nothing
        // is — a student can be lost in the lesson with a spotless record.
        let capped = min(Self.maximumAdjustment, max(-Self.maximumReduction, raw))

        return AcademicEscalationResult(
            baseScore: baseScore,
            adjustedScore: min(Self.scoreCeiling, max(0, baseScore + capped)),
            factors: factors
        )
    }

    /// The rules, in the order they're shown to a teacher.
    ///
    /// Each is thresholded rather than continuous: "two missing assignments" is
    /// something a teacher can verify and argue with, where a smooth function of
    /// submission rate is neither.
    func factors(for snapshot: AcademicSnapshot) -> [AcademicFactor] {
        var found: [AcademicFactor] = []

        // Missing work — the strongest academic signal, and the most actionable.
        switch snapshot.missingCount {
        case 0:
            break
        case 1:
            found.append(AcademicFactor(
                title: "1 missing assignment",
                severity: .medium,
                impact: 0.03
            ))
        case 2...3:
            found.append(AcademicFactor(
                title: "\(snapshot.missingCount) missing assignments",
                severity: .high,
                impact: 0.06
            ))
        default:
            found.append(AcademicFactor(
                title: "\(snapshot.missingCount) missing assignments",
                severity: .high,
                impact: 0.10
            ))
        }

        // Falling grades. Only counted when there was enough graded work to
        // establish a trend at all — see AcademicRollup.trend.
        if let trend = snapshot.gradeTrend {
            let points = Int((abs(trend) * 100).rounded())
            if trend <= -0.15 {
                found.append(AcademicFactor(
                    title: "Grade average down \(points)%",
                    severity: .high,
                    impact: 0.06
                ))
            } else if trend <= -0.05 {
                found.append(AcademicFactor(
                    title: "Grade average down \(points)%",
                    severity: .medium,
                    impact: 0.03
                ))
            }
        }

        // A low absolute average, independent of direction — a student who has
        // been struggling all term shows no trend at all.
        if let average = snapshot.averageGrade, snapshot.gradedCount >= 2, average < 0.60 {
            found.append(AcademicFactor(
                title: "Grade average \(Int((average * 100).rounded()))%",
                severity: .high,
                impact: 0.05
            ))
        }

        // Gone quiet on submissions, but only where the course actually expected
        // something by now.
        //
        // `asOf: now` rather than the bare property. This type takes an
        // injectable clock so its rules can be evaluated at a fixed moment, and
        // reading `Date()` inside the property made that injection a no-op —
        // the one time-dependent rule here was the one thing it could not reach.
        if snapshot.pastDueCount > 0, let days = snapshot.daysSinceSubmission(asOf: now), days >= 14 {
            found.append(AcademicFactor(
                title: "Nothing submitted in \(days) days",
                severity: .medium,
                impact: 0.04
            ))
        }

        // Chronic lateness — weak on its own, real in aggregate.
        if snapshot.lateCount >= 3 {
            found.append(AcademicFactor(
                title: "\(snapshot.lateCount) late submissions",
                severity: .medium,
                impact: 0.02
            ))
        }

        // --- Evidence the other way -------------------------------------
        //
        // Everything above only ever raises a score. That made silence and a
        // clean record add up to the same verdict as silence and seven missing
        // assignments, which is wrong in an ordinary and important case: the
        // class is going over homework this student has already done, so they
        // have nothing to say and no reason to say it. Anchor holds the evidence
        // that they are fine and was throwing it away.
        //
        // Deliberately weaker than the escalations (‑0.10 against +0.20). A
        // student who has done the work can still be genuinely lost, and a good
        // record must never be able to hide someone who is. This buys a quiet
        // high-performer some benefit of the doubt; it does not clear them.
        found.append(contentsOf: reassurances(for: snapshot))

        return found
    }

    /// Academic evidence that a quiet student is probably fine.
    ///
    /// Requires *graded* work: an empty record is not a good one, and a class
    /// three weeks old with nothing marked yet says nothing either way.
    private func reassurances(for snapshot: AcademicSnapshot) -> [AcademicFactor] {
        guard snapshot.gradedCount >= 2 else { return [] }

        var found: [AcademicFactor] = []

        // Nothing outstanding, in a course that has actually set work. Without
        // the `pastDueCount` guard, every student in a brand-new class would
        // read as "fully up to date" on the strength of no deadlines existing.
        if snapshot.missingCount == 0, snapshot.pastDueCount > 0 {
            found.append(AcademicFactor(
                title: "No missing work",
                severity: .reassuring,
                impact: -0.06
            ))
        }

        if let average = snapshot.averageGrade, average >= 0.85 {
            found.append(AcademicFactor(
                title: "Grade average \(Int((average * 100).rounded()))%",
                severity: .reassuring,
                impact: -0.04
            ))
        }

        return found
    }

    // MARK: - Recommendations

    /// Combined next steps, in the order a teacher would act on them.
    ///
    /// Engagement first — the class is happening now — then the academic context
    /// that makes the check-in specific rather than generic.
    static func recommendations(
        engagement existing: [String],
        snapshot: AcademicSnapshot?,
        score: Double
    ) -> [String] {
        guard let snapshot, !snapshot.isEmpty else { return existing }

        var combined = existing

        if snapshot.missingCount > 0, score >= 0.45 {
            let titles = snapshot.missingAssignments.prefix(2).map(\.title)
            let named = titles.isEmpty ? "" : " (\(titles.joined(separator: ", ")))"
            combined.append(
                "Ask about the \(snapshot.missingCount) missing "
                + "assignment\(snapshot.missingCount == 1 ? "" : "s")\(named) rather than "
                + "about today's silence — it's the more concrete opening."
            )
        }

        if let trend = snapshot.gradeTrend, trend <= -0.05 {
            combined.append(
                "Grades are \(snapshot.gradeTrendDisplay) over the term. Worth a "
                + "check-in after class about whether the material has got away from them."
            )
        }

        if snapshot.missingCount == 0, snapshot.gradedCount > 0, score >= 0.70 {
            // Disengaged in the room but on top of the work — a different
            // problem, and worth saying so rather than recommending the same
            // "chase the assignments" script.
            combined.append(
                "Coursework is up to date, so today's disengagement is unlikely to "
                + "be about workload."
            )
        }

        return combined
    }
}
