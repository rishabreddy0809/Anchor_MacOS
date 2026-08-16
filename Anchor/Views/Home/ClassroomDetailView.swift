//
//  ClassroomDetailView.swift
//  Anchor
//
//  One class over time: how it has trended, who keeps struggling, and every
//  session on record.
//
//  The point of this screen is the pattern a single lesson can't show. A student
//  who has a bad Tuesday is noise; a student flagged in four sessions out of six
//  is the thing a teacher needs to know.
//

import SwiftUI

struct ClassroomDetailView: View {
    let classroomID: UUID
    let onOpenSession: (UUID) -> Void

    @EnvironmentObject private var store: EngagementStore
    @ObservedObject private var archive = SessionArchive.shared

    @State private var isRenaming = false
    @State private var draftName = ""

    private var sensitivity: Double { store.settings.sensitivity }

    var body: some View {
        if let classroom = archive.classroom(id: classroomID) {
            content(for: classroom)
                .navigationTitle(classroom.displayName)
        } else {
            // Reachable if the class is deleted while its detail is open.
            ContentUnavailableView(
                "Class removed",
                systemImage: "tray",
                description: Text("This class is no longer in your history.")
            )
        }
    }

    private func content(for classroom: Classroom) -> some View {
        let summary = archive.summary(for: classroom, sensitivity: sensitivity)
        let concerns = archive.recurringConcerns(inClassroom: classroomID, sensitivity: sensitivity)
        let sessions = archive.sessions(forClassroom: classroomID)

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                header(classroom, summary: summary)
                tiles(summary, sessions: sessions)

                if summary.averageTrend.count >= 2 {
                    trendSection(summary)
                }

                if !concerns.isEmpty {
                    concernsSection(concerns)
                } else if sessions.count >= 2 {
                    noConcernsNotice
                }

                sessionsSection(sessions)
            }
            .padding(22)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Rename Class…") {
                        draftName = classroom.customName ?? classroom.zoomTopic
                        isRenaming = true
                    }
                    if classroom.customName != nil {
                        Button("Reset to Zoom Topic") {
                            archive.rename(classroomID: classroomID, to: nil)
                        }
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Rename class", isPresented: $isRenaming) {
            TextField("Class name", text: $draftName)
            Button("Save") { archive.rename(classroomID: classroomID, to: draftName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown instead of the Zoom meeting topic.")
        }
    }

    // MARK: - Header

    private func header(_ classroom: Classroom, summary: SessionArchive.ClassroomSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(classroom.displayName)
                .font(.system(size: 24, weight: .semibold))

            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.accent)
                Text("Zoom meeting \(classroom.zoomMeetingID)")
                if let last = summary.lastSession {
                    Text("·")
                    Text("Last taught \(last.dateDisplay)")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tiles

    private func tiles(
        _ summary: SessionArchive.ClassroomSummary,
        sessions: [ClassSession]
    ) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            SummaryTile(
                value: "\(summary.sessionCount)",
                label: summary.sessionCount == 1 ? "Session" : "Sessions",
                symbolName: "calendar"
            )

            SummaryTile(
                value: "\(summary.studentsTracked)",
                label: "Students tracked",
                symbolName: "person.2.fill"
            )

            SummaryTile(
                value: averageDisplay(sessions),
                label: "Average struggle",
                symbolName: "speedometer",
                tint: averageTint(sessions)
            )

            SummaryTile(
                value: "\(summary.recurringConcernCount)",
                label: "Recurring concerns",
                symbolName: "exclamationmark.arrow.circlepath",
                tint: summary.recurringConcernCount > 0 ? Theme.riskHigh : .primary
            )
        }
    }

    /// Mean of the per-session class averages, skipping sessions that had
    /// nothing scoreable in them.
    private func averageDisplay(_ sessions: [ClassSession]) -> String {
        let averages = sessions.compactMap(\.averageScore)
        guard !averages.isEmpty else { return "—" }
        let mean = averages.reduce(0, +) / Double(averages.count)
        return "\(Int((mean * 100).rounded()))%"
    }

    private func averageTint(_ sessions: [ClassSession]) -> Color {
        let averages = sessions.compactMap(\.averageScore)
        guard !averages.isEmpty else { return .primary }
        let mean = averages.reduce(0, +) / Double(averages.count)
        return RiskLevel.level(for: mean, sensitivity: sensitivity).color
    }

    // MARK: - Trend

    private func trendSection(_ summary: SessionArchive.ClassroomSummary) -> some View {
        HomeSection(
            title: "Class average over time",
            trailingText: trendCaption(summary),
            padded: false
        ) {
            SessionTrendPanel(values: summary.averageTrend, sensitivity: sensitivity)
                .padding(14)
        }
    }

    /// "Up 6 pts since last session" — direction stated in the teacher's terms,
    /// where up is worse.
    private func trendCaption(_ summary: SessionArchive.ClassroomSummary) -> String {
        guard let delta = summary.trendDelta else { return "" }
        let points = Int((abs(delta) * 100).rounded())
        if points < 2 { return "Holding steady" }
        return delta > 0
            ? "Up \(points) pts since last session"
            : "Down \(points) pts since last session"
    }

    // MARK: - Recurring concerns

    private func concernsSection(_ concerns: [SessionArchive.RecurringConcern]) -> some View {
        HomeSection(
            title: "Students to watch",
            trailingText: "Flagged in more than one session"
        ) {
            VStack(spacing: 1) {
                ForEach(concerns) { concern in
                    concernRow(concern)
                }
            }
        }
    }

    private func concernRow(_ concern: SessionArchive.RecurringConcern) -> some View {
        let level = RiskLevel.level(for: concern.averagePeak, sensitivity: sensitivity)

        return HStack(spacing: 10) {
            Avatar(initials: initials(concern.name), level: level, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(concern.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)

                    if concern.isNameOnlyIdentity {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .help("Matched by display name only — Zoom didn't report an "
                                  + "account for this participant, so this history could "
                                  + "cover more than one person.")
                    }
                }

                Text("High risk in \(concern.highRiskSessions) of \(concern.scoredSessions) sessions")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            frequencyDots(concern)

            VStack(alignment: .trailing, spacing: -1) {
                Text("\(Int((concern.averagePeak * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(level.color)
                Text("avg peak")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// One dot per scored session, filled where the student was flagged.
    private func frequencyDots(_ concern: SessionArchive.RecurringConcern) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<min(concern.scoredSessions, 8), id: \.self) { index in
                Circle()
                    .fill(index < concern.highRiskSessions ? Theme.riskHigh : Theme.hairline)
                    .frame(width: 5, height: 5)
            }
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private var noConcernsNotice: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.riskLow)
            Text("No student has been flagged in more than one session of this class.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    // MARK: - Sessions

    private func sessionsSection(_ sessions: [ClassSession]) -> some View {
        HomeSection(
            title: "Sessions",
            trailingText: "\(sessions.count) on record"
        ) {
            VStack(spacing: 1) {
                ForEach(sessions) { session in
                    SessionRow(session: session, sensitivity: sensitivity) {
                        onOpenSession(session.id)
                    }
                    .contextMenu {
                        Button("Delete Session", role: .destructive) {
                            archive.delete(sessionID: session.id)
                        }
                    }
                }
            }
        }
    }
}
