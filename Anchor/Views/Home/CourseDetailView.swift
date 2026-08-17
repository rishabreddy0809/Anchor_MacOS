//
//  CourseDetailView.swift
//  Anchor
//
//  One Google Classroom course: its roster, and what Classroom says about each
//  student's coursework.
//
//  This is the screen that answers "did connecting actually do anything" — the
//  connection state alone is not evidence, a roster with names on it is.
//
//  Coursework only exists for the *monitored* course: assignments and
//  submissions are one call per assignment, so Anchor syncs the class the
//  teacher nominated rather than every class they own. The header says which
//  one that is and lets it be changed here.
//

import SwiftUI

struct CourseDetailView: View {
    let courseID: String

    @ObservedObject private var classroom = ClassroomViewModel.shared
    @ObservedObject private var archive = SessionArchive.shared
    /// Observed, not just read: the teacher can change the colour from the grid
    /// card while this view is open behind it.
    @ObservedObject private var themes = CourseThemes.shared

    private var course: ClassroomCourse? {
        classroom.courses.first { $0.id == courseID }
    }

    private var isMonitored: Bool { classroom.isMonitored(courseID: courseID) }
    private var roster: [ClassroomStudent] { classroom.roster(forCourse: courseID) }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                if let course {
                    header(course)
                    tiles
                    recordedSection(course)
                    rosterSection
                } else {
                    Text("This class is no longer in your Google Classroom account.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(course?.name ?? "Class")
    }

    // MARK: - Header

    private func header(_ course: ClassroomCourse) -> some View {
        // Same colour the grid card wears, teacher's pick included — the detail
        // view opening in a different colour to the tile it came from would read
        // as a different class.
        let tint = themes.theme(forCourseID: course.id).color

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                    .overlay(
                        Text(initials(of: course.name))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(course.name)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(2)

                    Text(subtitle(course))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if course.enrolledAsStudent {
                    EmptyView()
                } else if isMonitored {
                    Button("Stop monitoring") {
                        classroom.setMonitored(false, courseID: course.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Monitor this class") {
                        classroom.setMonitored(true, courseID: course.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if course.enrolledAsStudent {
                note(
                    symbol: "person.crop.circle",
                    text: "You're enrolled in this class as a student. Google only lets a "
                        + "student see their own work, so Anchor can't load the roster or "
                        + "score anyone here. Sign in with the account that teaches the "
                        + "class to monitor it."
                )
            } else if !isMonitored {
                note(
                    symbol: "info.circle",
                    text: "Monitor this class to pull in its assignments, grades and "
                        + "missing work — the roster below is already loaded. You can "
                        + "monitor as many classes as you teach; each is synced "
                        + "separately."
                )
            } else if !classroom.canReadCoursework {
                note(
                    symbol: "lock",
                    text: "Google didn't grant permission to read this class's assignments "
                        + "or grades, so the roster below is all Anchor can show. "
                        + "Reconnect from Home or Settings to ask for it again."
                )
            } else if let error = classroom.lastSyncError(courseID: courseID),
                      classroom.lastSynced(courseID: courseID) == nil {
                // A sync in flight is deliberately not mentioned — it is
                // background work on a ten-minute clock. A sync that *failed*
                // is, because nothing below it can be trusted to be complete.
                note(
                    symbol: "exclamationmark.triangle",
                    text: "Anchor couldn't read this class's coursework. \(error.localizedDescription) "
                        + "It will try again on the next sync."
                )
            } else if snapshots.isEmpty {
                // Covers both "read, and there genuinely is nothing" and "not
                // read yet" — which is the point. The teacher gets the same
                // honest sentence either way instead of a progress report.
                note(
                    symbol: "info.circle",
                    text: "No graded or overdue work to show for this class yet."
                )
            }
        }
    }

    private func subtitle(_ course: ClassroomCourse) -> String {
        var parts: [String] = []
        if let section = course.section, !section.isEmpty { parts.append(section) }
        parts.append("\(roster.count) student\(roster.count == 1 ? "" : "s")")
        if let code = course.enrollmentCode, !code.isEmpty { parts.append("code \(code)") }
        if isMonitored, let synced = classroom.lastSynced(courseID: courseID) {
            parts.append("synced \(Theme.relativeString(from: synced, to: Date()).lowercased())")
        }
        return parts.joined(separator: " · ")
    }

    private func initials(of name: String) -> String {
        let words = name.split { !$0.isLetter && !$0.isNumber }
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "#" : String(letters).uppercased()
    }

    private func note(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.accent.opacity(0.07))
        )
    }

    // MARK: - Tiles

    private var tiles: some View {
        HStack(spacing: 10) {
            SummaryTile(
                value: "\(roster.count)",
                label: "on the roster",
                symbolName: "person.2"
            )

            SummaryTile(
                value: isMonitored ? "\(studentsBehind)" : "—",
                label: "behind on work",
                symbolName: "exclamationmark.triangle",
                tint: studentsBehind > 0 && isMonitored ? Theme.riskElevated : .primary
            )

            SummaryTile(
                value: averageGradeDisplay,
                label: "class average",
                symbolName: "chart.bar"
            )

            SummaryTile(
                value: "\(sessionCount)",
                label: sessionCount == 1 ? "recorded session" : "recorded sessions",
                symbolName: "clock.arrow.circlepath"
            )
        }
    }

    /// This course's rollups and no one else's. Several classes can be
    /// monitored at once, so every academic figure on this screen reads the
    /// per-course set rather than the pooled one.
    private var snapshots: [String: AcademicSnapshot] {
        isMonitored ? classroom.snapshots(forCourse: courseID) : [:]
    }

    private var studentsBehind: Int {
        snapshots.values.filter { $0.missingCount > 0 }.count
    }

    private var averageGradeDisplay: String {
        let grades = snapshots.values.compactMap(\.averageGrade)
        guard isMonitored, !grades.isEmpty else { return "—" }
        let mean = grades.reduce(0, +) / Double(grades.count)
        return "\(Int((mean * 100).rounded()))%"
    }

    /// Sessions Anchor has recorded for this course: the classes the teacher
    /// linked to it, plus any unlinked class whose name happens to match. The
    /// two systems share no identifier — Zoom meetings and Classroom courses are
    /// unrelated — so a link is the only firm tie.
    private var sessionCount: Int {
        guard let course else { return 0 }
        let name = course.name.lowercased().trimmed
        return archive.classrooms
            .filter { recorded in
                if let linkedID = recorded.googleCourseID { return linkedID == course.id }
                return recorded.displayName.lowercased().trimmed == name
            }
            .reduce(0) { $0 + archive.sessions(forClassroom: $1.id).count }
    }

    // MARK: - Linked recorded classes

    /// The recorded classes tied to this course, and the control for tying more.
    ///
    /// This is the other half of the button on a "Recorded by Anchor" card: what
    /// was linked there shows up here, under the class it belongs to.
    private func recordedSection(_ course: ClassroomCourse) -> some View {
        let linked = archive.classrooms(forCourseID: course.id)

        return HomeSection(
            title: "Recorded by Anchor",
            trailingText: linked.isEmpty ? nil : "\(linked.count)",
            padded: false
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(linked) { recorded in
                    NavigationLink(value: HomeView.HomeRoute.classroom(recorded.id)) {
                        linkedRow(recorded)
                    }
                    .buttonStyle(RowButtonStyle())

                    Divider().overlay(Theme.hairline)
                }

                HStack(spacing: 8) {
                    if linkable.isEmpty {
                        Text(linked.isEmpty
                             ? "No recorded classes to connect yet. Anchor lists a class here once it has monitored one of your Zoom meetings."
                             : "Every recorded class is already connected to one of your Classroom classes.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Menu {
                            ForEach(linkable) { recorded in
                                Button(recorded.displayName) {
                                    archive.link(classroomID: recorded.id, toCourseID: course.id)
                                }
                            }
                        } label: {
                            Label("Connect a recorded class", systemImage: "link")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    /// Recorded classes not already tied to some course. A class linked to a
    /// *different* course is left alone — moving it is an unlink first, done
    /// from the class it currently belongs to.
    private var linkable: [Classroom] {
        archive.classrooms.filter { !$0.isLinkedToCourse }
    }

    private func linkedRow(_ recorded: Classroom) -> some View {
        let sessions = archive.sessions(forClassroom: recorded.id)

        return HStack(spacing: 10) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(recorded.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)

                Text(rowDetail(sessions: sessions))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button("Disconnect") { archive.link(classroomID: recorded.id, toCourseID: nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 10.5))
                .help("Move this class back to the Recorded by Anchor section")

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func rowDetail(sessions: [ClassSession]) -> String {
        guard let last = sessions.first else { return "No sessions recorded yet" }
        let count = sessions.count == 1 ? "1 session" : "\(sessions.count) sessions"
        return "\(count) · last \(last.dateDisplay)"
    }

    // MARK: - Roster

    private var rosterSection: some View {
        HomeSection(
            title: "Students",
            trailingText: roster.isEmpty ? nil : "\(roster.count)",
            padded: false
        ) {
            if roster.isEmpty {
                Text(rosterEmptyText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 148, maximum: 190), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(Array(sortedRoster.enumerated()), id: \.element.id) { index, student in
                        NavigationLink(
                            value: HomeView.HomeRoute.courseStudent(courseID: courseID, studentID: student.id)
                        ) {
                            CourseStudentCard(
                                rank: index + 1,
                                student: student,
                                snapshot: student.rosterKey.flatMap { snapshots[$0] }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
        }
    }

    private var rosterEmptyText: String {
        if course?.enrolledAsStudent == true {
            return "Google doesn't share a class roster with a student account."
        }
        return classroom.isLoadingCourses
            ? "Loading the roster…"
            : "Google Classroom returned no students for this class."
    }

    /// Worst academic standing first — the reason a teacher opens this list.
    /// Students Classroom has nothing to say about sort to the bottom rather
    /// than reading as "doing fine".
    private var sortedRoster: [ClassroomStudent] {
        sortedByAcademicRisk(roster, snapshots: snapshots)
    }
}
