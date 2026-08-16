//
//  CourseStudentCard.swift
//  Anchor
//
//  One student, ranked by coursework standing — shared by CourseDetailView's
//  own roster and by InsightsView, which shows the same cards pooled across
//  every monitored class.
//
//  The ring and band label read like a live struggle score, but nothing here
//  is live: Classroom coursework is all this card is built from, checked on
//  its own sync clock. See CourseStudentHistoryView for the same honesty
//  applied to the drill-down these cards open into.
//

import SwiftUI

/// A coursework-only stand-in for a struggle score, on the same 0...1 scale a
/// live engagement score would use: missing work weighs most, lateness a
/// little, a low average a little more. Nil when Classroom hasn't given
/// enough to say anything.
func academicRiskScore(_ snapshot: AcademicSnapshot?) -> Double? {
    guard let snapshot, !snapshot.isEmpty else { return nil }

    // A weighted mean over the components Classroom could actually supply —
    // the same shape as FeatureCalculator.confidenceLevel. A course with
    // nothing graded is scored on missing and late work alone, rather than
    // being credited with a perfect average nobody earned.
    var total = 0.0
    var earned = 0.0
    func add(_ share: Double, weight: Double) {
        total += weight
        earned += weight * min(1, max(0, share))
    }

    // Counts saturate smoothly instead of hitting a wall. The previous version
    // capped missing work at 0.7 after four assignments and then clipped the
    // sum at 1.0, so every student with four or more missing and a failing
    // average scored exactly 100% — the gauge stopped telling them apart at
    // precisely the point a teacher most needs it to. `1 - exp(-n/3)` keeps
    // rising with every extra assignment while still flattening, so ten
    // missing reads worse than five and the top of the scale stays reachable.
    add(1 - exp(-Double(snapshot.missingCount) / 3), weight: 0.45)
    add(1 - exp(-Double(snapshot.lateCount) / 3), weight: 0.15)

    // Graded work is measured against a pass line rather than linearly from
    // zero: an 83% average is not "17% of a concern", it is no concern at all,
    // while a 48% average is nearly all of one.
    if let average = snapshot.averageGrade {
        add((0.75 - average) / 0.35, weight: 0.40)
    }

    guard total > 0 else { return nil }
    return earned / total
}

/// The five-tier reading under the ring — finer-grained than the three-colour
/// band, the same way a teacher would talk about it out loud.
func academicRiskBandLabel(_ score: Double?) -> String? {
    guard let score else { return nil }
    switch score {
    case 0.8...: return "Very high"
    case 0.6..<0.8: return "High"
    case 0.35..<0.6: return "Moderate"
    case 0.15..<0.35: return "Low"
    default: return "Very low"
    }
}

/// Worst academic standing first — nil scores (nothing for Classroom to say)
/// sort to the bottom rather than reading as "doing fine".
func sortedByAcademicRisk(
    _ roster: [ClassroomStudent],
    snapshots: [String: AcademicSnapshot]
) -> [ClassroomStudent] {
    roster.sorted { lhs, rhs in
        let left = academicRiskScore(lhs.matchKey.flatMap { snapshots[$0] }) ?? -1
        let right = academicRiskScore(rhs.matchKey.flatMap { snapshots[$0] }) ?? -1
        if left != right { return left > right }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

struct CourseStudentCard: View {
    let rank: Int
    let student: ClassroomStudent
    let snapshot: AcademicSnapshot?
    /// This student's score in each recorded session, oldest first.
    ///
    /// The ring is a reading of *today*; this is the shape of the term. A card
    /// showing only the ring answered "how are they doing" but not "is this
    /// new", which is the question the Insights tab exists to answer and the
    /// only one a live dashboard cannot.
    var history: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(rank)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                Avatar(initials: initials, level: level, size: 34)

                Text(student.name.isEmpty ? "Unnamed student" : student.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)

                ScoreRing(
                    score: score ?? 0,
                    level: level,
                    size: 58,
                    lineWidth: 5,
                    isKnown: score != nil
                )

                Text(bandLabel)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)

                if history.count > 1 {
                    VStack(spacing: 3) {
                        Sparkline(values: history, tint: level.color)
                            .frame(height: 22)
                        Text(historyCaption)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.top, 1)
                }

                statusPill
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(isTopConcern ? level.color.opacity(0.07) : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(isTopConcern ? level.color.opacity(0.4) : Theme.hairline, lineWidth: isTopConcern ? 1.5 : 1)
        )
        .help(detail)
    }

    /// "12 sessions · struggle +18" — the direction of travel in one line, so
    /// the sparkline is readable without hovering it.
    ///
    /// The metric is named because it is *not* the one in the ring above it:
    /// the ring is coursework standing today, this is the live struggle score
    /// across recorded sessions. Two different readings of the same student,
    /// and an unlabelled "+18" invited them to be read as one.
    private var historyCaption: String {
        guard let first = history.first, let last = history.last else { return "" }
        let delta = Int(((last - first) * 100).rounded())
        let sessions = "\(history.count) sessions"
        if delta == 0 { return sessions + " · struggle flat" }
        return sessions + " · struggle \(delta > 0 ? "+" : "−")\(abs(delta))"
    }

    /// Not shown on the card itself — the grid has no room for it — but still
    /// reachable, since it's the one thing that explains why a student might
    /// never get a score at all.
    private var detail: String {
        guard let email = student.email, !email.trimmed.isEmpty else {
            return "No email from Google — can't be matched to a Zoom participant"
        }
        guard let snapshot else { return email }

        var parts = [email]
        if snapshot.lateCount > 0 { parts.append("\(snapshot.lateCount) late") }
        if snapshot.gradedCount > 0 { parts.append("\(snapshot.gradedCount) graded") }
        return parts.joined(separator: " · ")
    }

    private var score: Double? { academicRiskScore(snapshot) }

    private var bandLabel: String { academicRiskBandLabel(score) ?? "No data" }

    /// The avatar and ring tint track coursework, not engagement — there is no
    /// live score on this screen and colouring it as if there were would
    /// mislead. Unknown reads as the least alarming band rather than as
    /// "doing fine", same as the rest of the dashboard.
    private var level: RiskLevel {
        guard let score else { return .low }
        return RiskLevel.level(for: score)
    }

    /// Only the single worst card gets the highlighted border, and only when
    /// there's genuinely something to flag — a class where nobody is behind
    /// shouldn't have its first card look urgent just for being first.
    private var isTopConcern: Bool { rank == 1 && level == .high }

    @ViewBuilder
    private var statusPill: some View {
        let text = statusText
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(score == nil ? .secondary : level.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(score == nil ? Color.secondary.opacity(0.12) : level.color.opacity(0.14))
            )
    }

    private var statusText: String {
        guard score != nil else { return "No data" }
        switch level {
        case .high: return "Needs attention"
        case .elevated: return "Monitor"
        case .low: return "On track"
        }
    }

    private var initials: String {
        let parts = student.name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
