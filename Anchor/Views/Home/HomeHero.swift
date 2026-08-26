//
//  HomeHero.swift
//  Anchor
//
//  The top of Home, and the right-hand rail beside it.
//
//  Why this file exists. Home opened with a 22pt title, a one-line subtitle and
//  then a course grid, and on a 1472pt window a teacher with one Classroom
//  class saw a single 340pt card against about a thousand points of nothing.
//  The dead space was not a spacing bug — there was genuinely nothing else to
//  put there, because the three things a teacher wants first thing in the
//  morning were each somewhere else:
//
//    * what am I teaching today — only in the menu bar popover, via ScheduleCard
//    * is everything actually connected — only in Settings
//    * how much has Anchor seen — nowhere, only inferable from a session count
//      buried in the subtitle
//
//  So the rail is not decoration. It is the answer to "the right half of this
//  screen is empty", and each thing in it was already owed to the reader.
//
//  On the calendar specifically. Every title rendered here is the teacher's own
//  calendar data, frequently containing other people's names. It renders on this
//  Mac and goes nowhere: `CalendarService` is the file that owns those rules —
//  never logged even at `.private`, never sent to any model, never written to
//  the archive — and this view is downstream of them. Nothing here may start
//  logging an event title for debugging.
//

import SwiftUI

// MARK: - Hero band

/// Greeting, date, and whether Anchor's three inputs are actually live.
///
/// The connection chips are the part worth defending. Connection state used to
/// live only in Settings, which means the failure mode was a teacher looking at
/// an empty dashboard with no way to tell whether nothing happened or nothing
/// was connected. Those two look identical and have opposite fixes.
struct HomeHeroBand: View {
    @EnvironmentObject private var zoom: ZoomViewModel
    @ObservedObject private var classroom = ClassroomViewModel.shared
    @ObservedObject private var calendar = CalendarService.shared
    @ObservedObject private var profile = TeacherProfileStore.shared

    /// The shared window clock, so the greeting turns over at noon without a
    /// relaunch. Injected rather than read from `Date()` in the body: a view
    /// that reads the wall clock directly never re-renders when it changes.
    let now: Date

    /// Opens the calendar picker. Nil where there is nowhere to send them.
    var onConfigureCalendar: (() -> Void)?
    var onConnectClassroom: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    AnchorGlyph()
                        .stroke(style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 22, height: 22)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 8 }

                    Text(greeting)
                        .font(.system(size: 26, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Text(dateLine)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            // Wraps rather than truncating: on a narrow window three chips do
            // not fit beside a name, and a clipped connection indicator is
            // worse than a second row.
            HStack(spacing: 7) {
                IntegrationChip(
                    name: "Zoom",
                    state: zoomChipState,
                    action: nil
                )
                IntegrationChip(
                    name: "Classroom",
                    state: classroom.isConnected ? .live : .off,
                    action: classroom.isConnected ? nil : onConnectClassroom
                )
                IntegrationChip(
                    name: "Calendar",
                    state: calendar.isConfigured ? .live : .off,
                    action: calendar.isConfigured ? nil : onConfigureCalendar
                )
            }
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.11), Theme.accent.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.16), lineWidth: 1)
        )
    }

    /// Zoom has more than two states, and "retrying" must not read as "live":
    /// a teacher who sees a green dot stops looking for the reason the roster
    /// is empty.
    private var zoomChipState: IntegrationChip.State {
        switch zoom.state {
        case .connected, .waitingForMeeting: .live
        case .connecting, .retrying: .working
        case .idle, .failed: .off
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        let part = switch hour {
        case 0..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        guard let first = profile.firstName else { return part }
        return "\(part), \(first)"
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: now)
    }
}

/// One input, and whether it is actually feeding Anchor right now.
struct IntegrationChip: View {
    enum State {
        case live
        case working
        case off

        var tint: Color {
            switch self {
            case .live: Theme.riskLow
            case .working: Theme.riskElevated
            case .off: Color.secondary
            }
        }
    }

    let name: String
    let state: State
    /// Present only when there is something the teacher can do about it, which
    /// is what makes the chip worth tapping rather than merely worth reading.
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { chip }
                .buttonStyle(.plain)
                .help("Set up \(name)")
        } else {
            chip
        }
    }

    private var chip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state == .off ? Color.clear : state.tint)
                .overlay(
                    Circle().strokeBorder(
                        state == .off ? Theme.hairline : Color.clear,
                        lineWidth: 1.5
                    )
                )
                .frame(width: 6, height: 6)

            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(state == .off ? Color.secondary : Color.primary)

            if action != nil {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Theme.surface)
        )
        .overlay(
            Capsule().strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Today

/// Today's teaching, from the teacher's own calendar.
///
/// The rail version of `ScheduleCard`: same data and the same two-part
/// configuration rule, more room. It shows the whole day rather than only
/// now-and-next, because the rail has the height for it and "what does the rest
/// of my day look like" is a different question from "what is next".
struct TodayPanel: View {
    @ObservedObject private var calendar = CalendarService.shared

    let now: Date
    var onConfigure: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Today", trailingText: trailingText)

            VStack(alignment: .leading, spacing: 0) {
                if calendar.isConfigured {
                    if calendar.today.isEmpty {
                        emptyRow("Nothing on your calendar today.")
                    } else {
                        ForEach(Array(calendar.today.enumerated()), id: \.element.id) { index, event in
                            TodayRow(
                                event: event,
                                now: now,
                                isFirst: index == 0,
                                isLast: index == calendar.today.count - 1
                            )
                        }
                    }
                } else {
                    invitation
                }
            }
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

    /// Only ever a count of the teacher's own events. Never a title — this
    /// string is the one most likely to be copied into a log line later.
    private var trailingText: String? {
        guard calendar.isConfigured, !calendar.today.isEmpty else { return nil }
        let count = calendar.today.count
        return "\(count) \(count == 1 ? "event" : "events")"
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Names which half is missing. Access and calendar choice are separate
    /// steps and they look identical on screen — a teacher who granted access
    /// and picked nothing sees exactly what a teacher who granted nothing sees,
    /// and the two have different fixes in different places.
    private var invitation: some View {
        Button {
            onConfigure?()
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "calendar")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.accent.opacity(0.13)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your calendar")
                        .font(.system(size: 12, weight: .medium))
                    Text(invitationSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onConfigure == nil)
    }

    private var invitationSubtitle: String {
        switch calendar.access {
        case .notDetermined:
            "See what you are teaching next, read from this Mac's own calendar. "
            + "Nothing is uploaded."
        case .denied:
            "Anchor was refused calendar access. Turn it back on in System "
            + "Settings, under Privacy & Security."
        case .granted:
            "Access is on. Choose which calendars Anchor should read in Settings."
        }
    }
}

/// One event, on a rail: filled dot for what is running, hollow for what is not.
private struct TodayRow: View {
    let event: ScheduledClass
    let now: Date
    let isFirst: Bool
    let isLast: Bool

    private var isNow: Bool { event.isHappening(at: now) }
    private var isPast: Bool { event.end <= now }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // The rail. Drawn per row rather than as one background line so a
            // row can be the first or last without the line overshooting into
            // the card's padding.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Theme.hairline)
                    .frame(width: 1, height: 6)
                Circle()
                    .fill(isNow ? Theme.riskLow : Color.clear)
                    .overlay(
                        Circle().strokeBorder(
                            isNow ? Color.clear : Theme.hairline,
                            lineWidth: 1.5
                        )
                    )
                    .frame(width: 7, height: 7)
                Rectangle()
                    .fill(isLast ? Color.clear : Theme.hairline)
                    .frame(width: 1)
            }
            .frame(width: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: isNow ? .semibold : .regular))
                    .foregroundStyle(isPast ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(event.timeRange)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                    if let relative = relativeLabel {
                        Text(relative)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isNow ? Theme.riskLow : Theme.accent)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(isPast ? 0.55 : 1)
    }

    /// "Now", or "in 12 min" for something close enough to matter.
    ///
    /// Deliberately silent beyond an hour: "in 4 hr 20 min" is not a thing a
    /// teacher acts on, and a label on every row makes the one that matters
    /// stop standing out.
    private var relativeLabel: String? {
        if isNow { return "Now" }
        if isPast { return nil }
        let minutes = event.minutesUntilStart(from: now)
        guard minutes >= 0, minutes <= 60 else { return nil }
        return minutes <= 1 ? "Starting now" : "in \(minutes) min"
    }
}

// MARK: - At a glance

/// Three numbers Anchor can stand behind, in the rail under Today.
///
/// Every one of these is counted from the archive rather than estimated, and
/// none of them is a score: this panel says how much Anchor has seen, not how
/// anybody is doing. The distinction matters because a rollup of struggle
/// scores across classes is exactly the kind of number that reads as a finding
/// about children, which `ZOOM_INTEGRATION.md` §6 and the privacy policy both
/// say Anchor does not produce.
struct GlancePanel: View {
    let sessionCount: Int
    let studentCount: Int
    let classCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Anchor has seen")

            HStack(spacing: 8) {
                GlanceTile(value: "\(sessionCount)", label: sessionCount == 1 ? "session" : "sessions")
                GlanceTile(value: "\(studentCount)", label: studentCount == 1 ? "student" : "students")
                GlanceTile(value: "\(classCount)", label: classCount == 1 ? "class" : "classes")
            }
        }
    }
}

private struct GlanceTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
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
