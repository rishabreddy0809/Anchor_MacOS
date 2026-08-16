//
//  CourseCard.swift
//  Anchor
//
//  The Google Classroom-style tile used on Home: a coloured header carrying the
//  class name, section and roster size, a body for whatever Anchor knows about
//  the class, and a footer of actions.
//
//  Why it mirrors Classroom's own card: a teacher arriving from classroom.google
//  .com should recognise their classes instantly, before reading a word.
//
//  The colour cannot be read from Google — the Classroom API's `Course` resource
//  has no theme, banner or theme-colour field at all, so the header a teacher
//  sees on classroom.google.com is not available to us. It is therefore derived
//  from the course id, and the teacher can override it per class from the header
//  itself. See `CourseThemes`.
//

import SwiftUI

// MARK: - Course card

struct CourseCard: View {
    let course: ClassroomCourse
    /// Nil until the roster has loaded — shown as "—" rather than "0 students",
    /// which would be a claim Anchor hasn't earned yet.
    let studentCount: Int?
    /// True for the course Anchor is syncing coursework from.
    let isMonitored: Bool
    /// Line under the header: whatever is actually known about this class.
    let detail: CourseCardDetail
    /// Recorded classes the teacher has tied to this course. Shown as chips so
    /// the link is visible from the grid, not only after opening the class.
    var linkedClasses: [LinkedRecordedClass] = []
    let onOpen: () -> Void
    var onMonitor: (() -> Void)?
    /// Opens one linked recorded class.
    var onOpenLinked: ((UUID) -> Void)?

    @State private var isHovering = false
    @ObservedObject private var themes = CourseThemes.shared

    private var theme: CourseTheme { themes.theme(forCourseID: course.id) }
    private var tint: Color { theme.color }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                header
                summary
                Divider().overlay(Theme.hairline)
                footer
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(isHovering ? tint.opacity(0.55) : Theme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .shadow(
                color: .black.opacity(isHovering ? 0.16 : 0.06),
                radius: isHovering ? 8 : 3,
                y: isHovering ? 3 : 1
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [tint, tint.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // The decorative geometry Classroom puts in its own headers. Kept
            // abstract on purpose — a stock illustration would date badly and
            // would say nothing about the class.
            headerFlourish

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 6) {
                    Text(course.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    // On hover the badge gives way to the theme picker. The
                    // header is small and the badge is the more important of the
                    // two at rest, but a teacher reaching for the colour is
                    // already pointing at the card.
                    if isHovering {
                        themeMenu
                    } else if isMonitored {
                        monitoringBadge
                    }
                }

                if let section = course.section, !section.isEmpty {
                    Text(section)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }

                Text(studentCountText)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(height: 96)
    }

    private var headerFlourish: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: geo.size.height * 1.15)
                    .offset(x: geo.size.width - geo.size.height * 0.55, y: -geo.size.height * 0.18)

                Circle()
                    .strokeBorder(.white.opacity(0.16), lineWidth: 8)
                    .frame(width: geo.size.height * 0.8)
                    .offset(x: geo.size.width - geo.size.height * 0.15, y: geo.size.height * 0.45)
            }
        }
        .allowsHitTesting(false)
    }

    /// The colour picker, as a menu rather than eight inline swatches: the
    /// header is 96pt tall and already carries the name, section and roster
    /// size, and a row of dots there would compete with all three.
    private var themeMenu: some View {
        Menu {
            ForEach(CourseTheme.allCases) { option in
                Button {
                    themes.setTheme(option, forCourseID: course.id)
                } label: {
                    // A tick, not just a colour: the menu is also how a teacher
                    // checks what the card is currently set to.
                    Label(
                        option.label,
                        systemImage: option == theme ? "checkmark.circle.fill" : "circle.fill"
                    )
                }
            }

            if themes.hasCustomTheme(forCourseID: course.id) {
                Divider()
                Button("Reset to default") {
                    themes.resetTheme(forCourseID: course.id)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("Theme")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(.white.opacity(0.22)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Google doesn't share a class's theme, so pick the colour to match")
    }

    private var monitoringBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(.white)
                .frame(width: 5, height: 5)
            Text("Monitored")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(.white.opacity(0.22)))
    }

    private var studentCountText: String {
        // Google won't hand a student the roster, so a count would be a guess.
        if course.enrolledAsStudent { return "You're enrolled as a student" }
        guard let studentCount else { return "— students" }
        return "\(studentCount) student\(studentCount == 1 ? "" : "s")"
    }

    // MARK: Body

    /// Classroom leaves this area empty until there's an announcement. Anchor
    /// fills it with the one thing a teacher would want at a glance, and says
    /// plainly when there is nothing yet rather than faking a stat.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let headline = detail.headline {
                HStack(spacing: 6) {
                    Image(systemName: detail.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(detail.tint)
                    Text(headline)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }

            Text(detail.caption)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !linkedClasses.isEmpty {
                linkedRow
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 9)
    }

    /// The recorded classes tied to this course. This is where a class linked
    /// from "Recorded by Anchor" shows up — the whole point of linking is that
    /// the history stops living in a separate list.
    private var linkedRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(linkedClasses.prefix(2)) { linked in
                Button {
                    onOpenLinked?(linked.id)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(linked.name)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                        Text(linked.sessionCount == 1 ? "1 session" : "\(linked.sessionCount) sessions")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tint.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Open the engagement history Anchor recorded for this class")
            }

            if linkedClasses.count > 2 {
                Text("+\(linkedClasses.count - 2) more recorded by Anchor")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 2)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if let onMonitor, !isMonitored {
                Button(action: onMonitor) {
                    Text("Monitor this class")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
                .help("Sync coursework from this class and use it while scoring")
            }

            Spacer(minLength: 0)

            Image(systemName: "person.2")
                .help("Open the roster")
            Image(systemName: "chart.line.uptrend.xyaxis")
                .help("Open this class")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var accessibilityLabel: String {
        [course.displayName, studentCountText, detail.headline]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

// MARK: - Linked recorded class

/// A class Anchor recorded, tied by the teacher to a Classroom course.
struct LinkedRecordedClass: Identifiable, Hashable {
    /// The archive `Classroom` id, so tapping opens its history.
    let id: UUID
    let name: String
    let sessionCount: Int
}

// MARK: - Card detail

/// What the middle of a card says. Built by the caller so the card itself has no
/// opinion about where the numbers came from.
struct CourseCardDetail {
    var symbol: String = "sparkles"
    /// Nil when there is nothing measured to lead with.
    var headline: String?
    var caption: String
    var tint: Color = Theme.accent

    static let notSynced = CourseCardDetail(
        symbol: "clock",
        headline: nil,
        caption: "Coursework isn't synced for this class yet. Open it to load the "
            + "roster and assignments.",
        tint: .secondary
    )

    /// A class the signed-in account attends rather than teaches. Google gives a
    /// student no view of anyone else's work, so Anchor has nothing to score.
    static let enrolledAsStudent = CourseCardDetail(
        symbol: "person.crop.circle",
        headline: "Not your class to monitor",
        caption: "You're enrolled here as a student, so Google won't share the "
            + "roster or other students' coursework.",
        tint: .secondary
    )

    /// A course that isn't the monitored one but does have recorded classes
    /// tied to it — the history is real even though the coursework isn't synced.
    static func linkedHistory(classes: Int, sessions: Int) -> CourseCardDetail {
        CourseCardDetail(
            symbol: "clock.arrow.circlepath",
            headline: sessions == 1 ? "1 recorded session" : "\(sessions) recorded sessions",
            caption: classes == 1
                ? "Linked to a class Anchor recorded. Monitor this class to sync its coursework too."
                : "Linked to \(classes) classes Anchor recorded. Monitor this class to sync its coursework too.",
            tint: Theme.accent
        )
    }

    /// A monitored class Anchor hasn't read yet.
    ///
    /// Deliberately says nothing about syncing. The sync is background work on a
    /// ten-minute clock that the teacher neither triggered nor waits on, and
    /// narrating it — "Syncing coursework…", with a spinner — turned an
    /// invisible housekeeping task into something that looked like it needed
    /// watching. The card simply has nothing to report yet, and says that.
    ///
    /// Failures are still reported: see `syncFailed` and `syncStalled`. Quiet
    /// applies to work that is going fine.
    static let awaitingCoursework = CourseCardDetail(
        symbol: "book.closed",
        headline: nil,
        caption: "No coursework to report yet.",
        tint: .secondary
    )

    /// Monitored, never synced, and nothing is going to sync it.
    ///
    /// Split from `syncing` because the two were previously the same card: a
    /// class that had never synced showed a spinner whether or not anything was
    /// running, so a stopped sync was indistinguishable from a slow one and the
    /// teacher's only clue was that it never finished.
    static let syncStalled = CourseCardDetail(
        symbol: "exclamationmark.arrow.triangle.2.circlepath",
        headline: "Coursework not synced",
        caption: "Anchor stopped syncing this class. Use Sync Now in Settings, "
            + "or reconnect Google Classroom.",
        tint: Theme.riskElevated
    )

    /// Tried, failed, and will try again — with the reason Google gave.
    ///
    /// The retry is why this isn't fatal, and the reason is why it isn't
    /// "Syncing…": a class that fails every attempt would otherwise sit on a
    /// spinner forever while the loop quietly retried behind it.
    static func syncFailed(reason: String) -> CourseCardDetail {
        CourseCardDetail(
            symbol: "exclamationmark.arrow.triangle.2.circlepath",
            headline: "Couldn't sync coursework",
            caption: "\(reason) Anchor will try again on the next sync.",
            tint: Theme.riskElevated
        )
    }

    /// Connected, monitoring this class, but Google withheld the coursework
    /// permissions — the roster is all there is.
    static let rosterOnly = CourseCardDetail(
        symbol: "lock",
        headline: "Roster only",
        caption: "Google didn't grant permission to read this class's assignments "
            + "or grades.",
        tint: Theme.riskElevated
    )

    static let noCoursework = CourseCardDetail(
        symbol: "checkmark.circle",
        headline: "Nothing overdue",
        caption: "No missing assignments across this roster.",
        tint: Theme.riskLow
    )

    /// The headline a synced course leads with: who is behind, and by how much.
    static func academic(missingStudents: Int, missingItems: Int, sessions: Int) -> CourseCardDetail {
        var caption = sessions > 0
            ? "\(sessions) recorded session\(sessions == 1 ? "" : "s")"
            : "No sessions recorded yet"

        if missingItems > 0 {
            caption += " · \(missingItems) missing item\(missingItems == 1 ? "" : "s")"
        }

        return CourseCardDetail(
            symbol: missingStudents > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle",
            headline: missingStudents > 0
                ? "\(missingStudents) student\(missingStudents == 1 ? "" : "s") behind on work"
                : "Nothing overdue",
            caption: caption,
            tint: missingStudents > 0 ? Theme.riskElevated : Theme.riskLow
        )
    }
}
