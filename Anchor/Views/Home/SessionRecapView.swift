//
//  SessionRecapView.swift
//  Anchor
//
//  One past class, after the fact: who needed attention, and what the signals
//  said at the time.
//
//  Ranked by *peak* rather than final score. A student who spent the first half
//  of the lesson in the red and came back by the bell is exactly who a recap
//  should surface — the final number alone would file them as fine.
//

import SwiftUI

struct SessionRecapView: View {
    let sessionID: UUID

    @EnvironmentObject private var store: EngagementStore
    @ObservedObject private var archive = SessionArchive.shared

    private var sensitivity: Double { store.settings.sensitivity }

    var body: some View {
        if let session = archive.session(id: sessionID) {
            content(for: session)
                .navigationTitle(className(for: session))
        } else {
            ContentUnavailableView(
                "Session removed",
                systemImage: "tray",
                description: Text("This session is no longer in your history.")
            )
        }
    }

    private func content(for session: ClassSession) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                header(session)

                if session.isThin {
                    thinNotice(session)
                } else {
                    tiles(session)
                    needsAttention(session)
                }

                roster(session)

                if !session.unavailableSignals.isEmpty, !session.isThin {
                    signalNotice(session)
                }
            }
            .padding(22)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func className(for session: ClassSession) -> String {
        archive.classroom(id: session.classroomID)?.displayName ?? session.topic
    }

    // MARK: - Header

    private func header(_ session: ClassSession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(session.dateDisplay)
                .font(.system(size: 24, weight: .semibold))

            HStack(spacing: 6) {
                Text(session.timeRangeDisplay)
                Text("·")
                Text(session.durationDisplay)
                Text("·")
                Text("\(session.studentCount) \(session.studentCount == 1 ? "student" : "students")")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            if session.wasInterrupted {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text("Anchor stopped before this class ended — the end time is the "
                         + "last reading, not the real finish.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.riskElevated)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Tiles

    private func tiles(_ session: ClassSession) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            SummaryTile(
                value: session.averageScoreDisplay,
                label: "Class average",
                symbolName: "speedometer",
                tint: session.averageScore.map {
                    RiskLevel.level(for: $0, sensitivity: sensitivity).color
                } ?? .primary
            )
            SummaryTile(
                value: "\(session.highRiskCount(sensitivity: sensitivity))",
                label: "Needed attention",
                symbolName: "exclamationmark.triangle.fill",
                tint: Theme.riskHigh
            )
            SummaryTile(
                value: "\(session.elevatedCount(sensitivity: sensitivity))",
                label: "Worth watching",
                symbolName: "eye.fill",
                tint: Theme.riskElevated
            )
            SummaryTile(
                value: "\(session.engagedCount(sensitivity: sensitivity))",
                label: "Engaged",
                symbolName: "checkmark.circle.fill",
                tint: Theme.riskLow
            )
        }
    }

    // MARK: - Needed attention

    @ViewBuilder
    private func needsAttention(_ session: ClassSession) -> some View {
        let flagged = session.everAtRisk(sensitivity: sensitivity)

        HomeSection(
            title: "Needed attention",
            trailingText: flagged.isEmpty ? nil : "Ranked by worst point in the class"
        ) {
            if flagged.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.riskLow)
                    Text("No student reached high risk in this session.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(12)
            } else {
                VStack(spacing: 1) {
                    ForEach(flagged) { record in
                        ArchivedStudentRow(
                            record: record,
                            sensitivity: sensitivity,
                            usesPeak: true,
                            trailingNote: recoveryNote(for: record)
                        )
                    }
                }
            }
        }
    }

    /// Distinguishes a student who recovered from one who was still struggling
    /// when the class ended — the same peak means very different things.
    private func recoveryNote(for record: StudentSessionRecord) -> String? {
        guard record.hasReliableScore else { return nil }
        let finalLevel = record.risk(sensitivity: sensitivity)
        let drop = record.peakScore - record.finalScore

        if finalLevel == .high {
            return "Still high risk at the end · finished \(record.scoreDisplay)"
        }
        if drop >= 0.15 {
            return "Recovered to \(record.scoreDisplay) by the end"
        }
        return "Finished \(record.scoreDisplay)"
    }

    // MARK: - Roster

    private func roster(_ session: ClassSession) -> some View {
        HomeSection(
            title: "Everyone in this class",
            trailingText: session.unscoredCount > 0
                ? "\(session.unscoredCount) without enough signal"
                : nil
        ) {
            VStack(spacing: 1) {
                ForEach(rankedRoster(session)) { record in
                    ArchivedStudentRow(record: record, sensitivity: sensitivity)
                }
            }
        }
    }

    /// Scored students first, worst last-reading at the top; unscored students
    /// sink to the bottom rather than sitting among real measurements.
    private func rankedRoster(_ session: ClassSession) -> [StudentSessionRecord] {
        session.students.sorted { lhs, rhs in
            if lhs.hasReliableScore != rhs.hasReliableScore { return lhs.hasReliableScore }
            if lhs.finalScore == rhs.finalScore { return lhs.name < rhs.name }
            return lhs.finalScore > rhs.finalScore
        }
    }

    // MARK: - Notices

    /// The session ran, but Zoom gave nothing worth scoring. Say that plainly
    /// rather than showing a page of zeroes.
    private func thinNotice(_ session: ClassSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.riskElevated)
                Text("Not enough signal to score this session")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }

            Text(thinExplanation(session))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.riskElevated.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.riskElevated.opacity(0.25), lineWidth: 1)
        )
    }

    private func thinExplanation(_ session: ClassSession) -> String {
        let attendance = "Anchor recorded \(session.studentCount) "
            + "\(session.studentCount == 1 ? "participant" : "participants") and how long "
            + "they were present, but nothing it could score a struggle level from."

        guard !session.unavailableSignals.isEmpty else { return attendance }
        return attendance + " Zoom did not report "
            + session.unavailableSignals.joined(separator: ", ")
            + " for this meeting."
    }

    private func signalNotice(_ session: ClassSession) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .padding(.top, 1)
            Text("Scored without "
                 + session.unavailableSignals.joined(separator: ", ")
                 + " — Zoom did not report those signals during this meeting.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }
}
