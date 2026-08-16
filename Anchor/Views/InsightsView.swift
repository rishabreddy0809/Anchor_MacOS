//
//  InsightsView.swift
//  Anchor
//
//  Every monitored class's roster in one place, ranked the same way
//  CourseDetailView ranks a single class — worst coursework standing first.
//  Tapping a student opens the same drill-down CourseDetailView's cards open:
//  CourseStudentHistoryView, built from that student's real recorded
//  sessions in that class.
//
//  Two filters, both about only showing a student where there's something
//  real to say about them:
//
//    * Scoped to monitored classes — an unmonitored course has a roster but
//      no coursework sync, so every card in it would read "No data".
//    * Scoped to students Anchor has actually seen in a recorded session
//      linked to that course. A roster entry nobody has ever matched to a
//      Zoom appearance has no engagement timeline, no speaking time and no
//      suggestions to open into — just a card that goes nowhere useful.
//

import SwiftUI

struct InsightsView: View {
    @ObservedObject private var classroom = ClassroomViewModel.shared
    @ObservedObject private var archive = SessionArchive.shared
    @ObservedObject private var links = ManualRosterLinks.shared

#if DEBUG
    /// Screenshot mode can open straight into a student's history, which is the
    /// screen that actually shows long-term data — the grid in front of it only
    /// shows where each student stands today.
    @State private var path: [InsightsRoute] = {
        guard DemoData.view == .history, let id = DemoData.historyStudentID else { return [] }
        return [.student(courseID: DemoData.courseID, studentID: id)]
    }()
#else
    @State private var path: [InsightsRoute] = []
#endif

    enum InsightsRoute: Hashable {
        case student(courseID: String, studentID: String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if classroom.monitoredCourses.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationDestination(for: InsightsRoute.self) { route in
                switch route {
                case .student(let courseID, let studentID):
                    CourseStudentHistoryView(courseID: courseID, studentID: studentID)
                }
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                title

                ForEach(classroom.monitoredCourses) { course in
                    courseSection(course)
                }
            }
            .padding(22)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Insights")
                .font(.system(size: 22, weight: .semibold))
            Text("Students Anchor has seen in class, ranked by coursework standing.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func courseSection(_ course: ClassroomCourse) -> some View {
        let roster = classroom.roster(forCourse: course.id)
        let snapshots = classroom.snapshots(forCourse: course.id)
        let manualLinks = links.links(forCourse: course.id)
        let seen = roster.filter {
            hasRecordedHistory(
                for: $0,
                roster: roster,
                courseID: course.id,
                archive: archive,
                manualLinks: manualLinks
            )
        }
        let sorted = sortedByAcademicRisk(seen, snapshots: snapshots)

        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: course.displayName, trailingText: seen.isEmpty ? nil : "\(seen.count)")

            if seen.isEmpty {
                Text(emptyCourseMessage(roster: roster))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .fill(Theme.surface)
                    )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 148, maximum: 190), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, student in
                        NavigationLink(
                            value: InsightsRoute.student(courseID: course.id, studentID: student.id)
                        ) {
                            CourseStudentCard(
                                rank: index + 1,
                                student: student,
                                snapshot: student.matchKey.flatMap { snapshots[$0] },
                                history: sessionHistory(
                                    for: student,
                                    roster: roster,
                                    courseID: course.id,
                                    manualLinks: manualLinks
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// This student's final score in each recorded session of `courseID`,
    /// oldest first.
    ///
    /// Matched on the same identity keys `hasRecordedHistory` uses, so a
    /// student who shows up in the grid always has a line to draw.
    private func sessionHistory(
        for student: ClassroomStudent,
        roster: [ClassroomStudent],
        courseID: String,
        manualLinks: [String: String]
    ) -> [Double] {
        let keys = Set(matchIdentityKeys(for: student, roster: roster, manualLinks: manualLinks))
        guard !keys.isEmpty else { return [] }

        return archive.classrooms(forCourseID: courseID)
            .flatMap { archive.sessions(forClassroom: $0.id) }
            .sorted { $0.startedAt < $1.startedAt }
            .compactMap { session in
                session.students
                    .first { keys.contains(normalizedArchiveIdentity($0.identityKey)) }?
                    .finalScore
            }
    }

    /// Distinguishes "nobody's roster loaded" from "the roster loaded but
    /// nobody's been matched to a recorded session yet" — the fix for each is
    /// different, so the message shouldn't be the same.
    private func emptyCourseMessage(roster: [ClassroomStudent]) -> String {
        if roster.isEmpty {
            return classroom.isLoadingCourses ? "Loading the roster…" : "No roster loaded yet for this class."
        }
        return "No students matched to a recorded session in this class yet."
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text(classroom.isConnected ? "No monitored classes yet" : "Connect Google Classroom for insights")
                    .font(.system(size: 15, weight: .semibold))

                Text(classroom.isConnected
                     ? "Monitor a class from Home to see every student's standing here."
                     : "Insights groups every student by class, using the same coursework "
                        + "Anchor already reads for each class you monitor.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
