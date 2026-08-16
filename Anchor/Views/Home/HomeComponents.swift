//
//  HomeComponents.swift
//  Anchor
//
//  Building blocks for the Home tab: classroom cards, session rows and the
//  small session-over-session chart.
//
//  These read the archive, never the live store, so nothing here can imply a
//  class is running when it isn't.
//

import SwiftUI

// MARK: - Classroom card

struct ClassroomCard: View {
    let summary: SessionArchive.ClassroomSummary
    let sensitivity: Double
    /// Courses this class can be tied to. Empty when Google Classroom isn't
    /// connected, which hides the link row entirely — offering a link with
    /// nothing to link to would only read as a broken control.
    var courses: [ClassroomCourse] = []
    /// Ties this class to a course. Cards shown here are never already linked:
    /// once they are, they move into the Google Classroom section, and that is
    /// where the link is changed or removed.
    var onLink: ((String) -> Void)?
    let action: () -> Void

    @State private var isHovering = false

    private var classroom: Classroom { summary.classroom }

    private var showsLinkRow: Bool { onLink != nil && !courses.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Divider().overlay(Theme.hairline)
                    footer
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(classroom.displayName), \(summary.sessionCount) sessions")

            // Outside the card's own button rather than inside its label: a menu
            // nested in a tappable card swallows its first click on macOS.
            if showsLinkRow {
                Divider().overlay(Theme.hairline)
                linkRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(isHovering ? Theme.surfaceHover : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    // MARK: Link to a Classroom course

    /// The one action this card offers besides opening: say which Google
    /// Classroom class this Zoom meeting actually is. Once set, the class moves
    /// up into the Google Classroom section.
    private var linkRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.accent)

            Menu {
                ForEach(courses) { course in
                    Button(course.displayName) { onLink?(course.id) }
                }
            } label: {
                Text("Connect to Google Classroom")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Tie this recorded class to one of your Google Classroom classes — "
                  + "it then appears under that class above")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: 10) {
            monogram

            VStack(alignment: .leading, spacing: 2) {
                Text(classroom.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = classroom.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Text(lastSessionText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var monogram: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.accent.opacity(0.16))
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.30), lineWidth: 1)
            Text(classroom.initials)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .frame(width: 38, height: 38)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 14) {
            metric(
                value: "\(summary.sessionCount)",
                label: summary.sessionCount == 1 ? "session" : "sessions"
            )

            metric(
                value: "\(summary.studentsTracked)",
                label: summary.studentsTracked == 1 ? "student" : "students"
            )

            if summary.recurringConcernCount > 0 {
                metric(
                    value: "\(summary.recurringConcernCount)",
                    label: "recurring",
                    tint: Theme.riskHigh
                )
            }

            Spacer(minLength: 0)

            SessionTrendChart(values: summary.averageTrend, sensitivity: sensitivity)
                .frame(width: 62, height: 26)
        }
    }

    private func metric(value: String, label: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
    }

    private var lastSessionText: String {
        guard let last = summary.lastSession else { return "No sessions yet" }
        return "Last: \(last.dateDisplay)"
    }
}

// MARK: - Session-over-session chart

/// One bar per session, oldest to newest, coloured by risk band.
///
/// Deliberately not a line: the gaps between sessions are days, not a continuous
/// signal, and a line would imply Anchor knew something about the time between
/// lessons.
struct SessionTrendChart: View {
    let values: [Double]
    let sensitivity: Double
    var barWidth: CGFloat = 5
    /// Compact (card) mode packs fixed-width bars against the trailing edge.
    /// Expanded mode spreads them across the full width — at section size the
    /// packed layout leaves most of the frame empty and reads as a broken chart.
    var expands: Bool = false
    /// Number of most recent sessions to show. Older ones scroll off the left.
    var limit: Int = 8

    var body: some View {
        GeometryReader { geo in
            if values.isEmpty {
                Text("—")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: expands ? .center : .trailing
                    )
            } else {
                HStack(alignment: .bottom, spacing: expands ? 8 : 2.5) {
                    if !expands { Spacer(minLength: 0) }

                    ForEach(Array(visible.enumerated()), id: \.offset) { _, value in
                        let level = RiskLevel.level(for: value, sensitivity: sensitivity)
                        RoundedRectangle(cornerRadius: expands ? 4 : 1.5, style: .continuous)
                            .fill(level.color)
                            .frame(
                                // Floor so a near-zero session still shows a mark
                                // rather than vanishing into the baseline.
                                height: max(3, geo.size.height * CGFloat(min(1, max(0, value))))
                            )
                            // Capped so a class with three sessions renders as a
                            // chart rather than three slabs filling the frame.
                            .frame(maxWidth: expands ? 46 : barWidth)
                    }

                    if expands { Spacer(minLength: 0) }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: expands ? .bottomLeading : .bottomTrailing
                )
            }
        }
    }

    private var visible: [Double] {
        Array(values.suffix(limit))
    }
}

/// The expanded chart plus its scale.
///
/// The axis matters here: class averages sit low on a 0–100% scale, so without
/// labelled bounds a healthy class looks like a rendering failure rather than a
/// good result.
struct SessionTrendPanel: View {
    let values: [Double]
    let sensitivity: Double

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing) {
                Text("100%")
                Spacer(minLength: 0)
                Text("50%")
                Spacer(minLength: 0)
                Text("0%")
            }
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(.tertiary)
            .frame(height: 110)

            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        Spacer(minLength: 0)
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        Spacer(minLength: 0)
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }

                    SessionTrendChart(
                        values: values,
                        sensitivity: sensitivity,
                        expands: true
                    )
                }
                .frame(height: 110)

                HStack {
                    Text("Oldest")
                    Spacer()
                    Text("Most recent")
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Session row

struct SessionRow: View {
    let session: ClassSession
    /// Shown when the row appears outside its own classroom.
    var classroomName: String?
    let sensitivity: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                dateBlock

                VStack(alignment: .leading, spacing: 2) {
                    Text(classroomName ?? session.topic)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                riskPills

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .buttonStyle(RowButtonStyle())
    }

    private var dateBlock: some View {
        VStack(spacing: -1) {
            Text(session.startedAt, format: .dateTime.day())
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
            Text(session.startedAt, format: .dateTime.month(.abbreviated))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(width: 34)
    }

    private var subtitle: String {
        var parts = [session.timeRangeDisplay, "\(session.studentCount) students"]
        if session.isThin {
            parts.append("not enough signal to score")
        } else if session.unscoredCount > 0 {
            parts.append("\(session.unscoredCount) unscored")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var riskPills: some View {
        if session.isThin {
            Text("—")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 7) {
                countPill(session.highRiskCount(sensitivity: sensitivity), level: .high)
                countPill(session.elevatedCount(sensitivity: sensitivity), level: .elevated)
                countPill(session.engagedCount(sensitivity: sensitivity), level: .low)
            }
        }
    }

    private func countPill(_ count: Int, level: RiskLevel) -> some View {
        HStack(spacing: 3) {
            RiskDot(level: level, size: 5)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(count == 0 ? .secondary : .primary)
        }
    }
}

// MARK: - Archived student row

/// One student inside a past session or a classroom roster.
struct ArchivedStudentRow: View {
    let record: StudentSessionRecord
    let sensitivity: Double
    /// Rank by worst point rather than by the score at the bell.
    var usesPeak: Bool = false
    var trailingNote: String?

    var body: some View {
        let level = usesPeak
            ? record.peakRisk(sensitivity: sensitivity)
            : record.risk(sensitivity: sensitivity)

        HStack(spacing: 10) {
            Avatar(initials: record.initials, level: level, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)

                Text(trailingNote ?? signalSummary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if !record.trend.isEmpty {
                Sparkline(values: record.trend, tint: level.color)
                    .frame(width: 44, height: 20)
                    .opacity(0.9)
            }

            VStack(alignment: .trailing, spacing: -1) {
                Text(usesPeak ? record.peakDisplay : record.scoreDisplay)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(record.hasReliableScore ? level.color : Color.secondary)
                Text(usesPeak ? "peak" : "final")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// The signals actually worth reading back, skipping any that were never
    /// measured — a flat "0 messages" on a REST-only session would read as a
    /// silent student rather than a missing feed.
    private var signalSummary: String {
        guard record.hasReliableScore else {
            return "Not enough signal from Zoom to score"
        }

        var parts: [String] = []
        if record.speakingSeconds > 0 {
            parts.append("spoke \(Self.duration(record.speakingSeconds))")
        } else {
            parts.append("didn't speak")
        }
        if record.chatMessages > 0 {
            parts.append("\(record.chatMessages) chat")
        }
        if record.handRaiseCount > 0 {
            parts.append("\(record.handRaiseCount) hand")
        }
        if record.minutesPresent >= 1 {
            parts.append("\(record.presenceDisplay) present")
        }
        return parts.joined(separator: " · ")
    }

    private static func duration(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60)m" : "\(seconds)s"
    }
}

// MARK: - Section container

/// Titled card used to group the Home sections.
struct HomeSection<Content: View>: View {
    let title: String
    var trailingText: String?
    var padded: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title, trailingText: trailingText)

            content
                .padding(padded ? 4 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .fill(Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
        }
    }
}

// MARK: - Summary tile

/// Compact stat used across the classroom and recap headers.
struct SummaryTile: View {
    let value: String
    let label: String
    var symbolName: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint == .primary ? .primary : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}
