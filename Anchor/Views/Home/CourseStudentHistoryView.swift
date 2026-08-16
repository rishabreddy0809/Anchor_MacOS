//
//  CourseStudentHistoryView.swift
//  Anchor
//
//  Drill-down for one Classroom roster student, opened from the ranked card
//  grid on CourseDetailView.
//
//  Unlike StudentDetailView — which reads the *live* meeting roster and stops
//  working the moment a student leaves the call — everything here comes from
//  SessionArchive: every recorded session tied to this Classroom course, for
//  this student, across however many class periods the teacher has linked to
//  it. A student with no recorded sessions yet gets an honest empty state
//  rather than an invented chart.
//
//  The "suggested actions" panel is deliberately not called AI: nothing here
//  runs a model. It is composed from the same real signals as the chart above
//  it, in the same voice as StudentDetailView's own composed recommendations
//  — see the note there about why that distinction matters.
//

import SwiftUI
import Charts

struct CourseStudentHistoryView: View {
    let courseID: String
    let studentID: String

    @EnvironmentObject private var store: EngagementStore
    @ObservedObject private var classroom = ClassroomViewModel.shared
    @ObservedObject private var archive = SessionArchive.shared
    @ObservedObject private var links = ManualRosterLinks.shared

    @State private var range: TimelineRange = .fourWeeks
    @State private var actionConfirmation: String?

    enum TimelineRange: String, CaseIterable, Identifiable {
        case fourWeeks = "Last 4 weeks"
        case eightWeeks = "Last 8 weeks"
        case allTime = "All time"

        var id: String { rawValue }

        var days: Int? {
            switch self {
            case .fourWeeks: 28
            case .eightWeeks: 56
            case .allTime: nil
            }
        }
    }

    private var student: ClassroomStudent? {
        classroom.roster(forCourse: courseID).first { $0.id == studentID }
    }

    private var snapshot: AcademicSnapshot? {
        student?.matchKey.flatMap { classroom.snapshots(forCourse: courseID)[$0] }
    }

    /// Every recorded appearance of this student across every recorded class
    /// linked to this course, oldest first — several class periods can feed
    /// one Classroom course, and a student's history belongs to all of them.
    private var history: [(session: ClassSession, record: StudentSessionRecord)] {
        guard let student else { return [] }
        return recordedHistory(
            for: student,
            roster: classroom.roster(forCourse: courseID),
            courseID: courseID,
            archive: archive,
            manualLinks: links.links(forCourse: courseID)
        )
    }

    private var filteredHistory: [(session: ClassSession, record: StudentSessionRecord)] {
        guard let days = range.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return history }
        return history.filter { $0.session.startedAt >= cutoff }
    }

    var body: some View {
        Group {
            if let student {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 18) {
                        header(student)

                        if history.isEmpty {
                            emptyHistoryNote
                        } else {
                            timelineSection
                            speakingTimeSection
                            suggestionsSection
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
                .navigationTitle(student.name.isEmpty ? "Student" : student.name)
            } else {
                Text("This student is no longer on the roster.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Header

    private func header(_ student: ClassroomStudent) -> some View {
        HStack(spacing: 12) {
            Avatar(initials: initials(student.name), level: headerLevel, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(student.name.isEmpty ? "Unnamed student" : student.name)
                    .font(.system(size: 18, weight: .semibold))

                if let email = student.email, !email.trimmed.isEmpty {
                    Text(email)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var headerLevel: RiskLevel {
        guard let latest = history.last(where: { $0.record.hasReliableScore }) else { return .low }
        return latest.record.risk(sensitivity: store.settings.sensitivity)
    }

    private var emptyHistoryNote: some View {
        Text("No recorded sessions yet for \(firstName) in this class. Engagement "
             + "history fills in once Anchor has monitored a session with them in it.")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
    }

    // MARK: - Engagement timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Engagement timeline")
                Spacer(minLength: 8)
                Picker("", selection: $range) {
                    ForEach(TimelineRange.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }

            let points = filteredHistory.filter { $0.record.hasReliableScore }

            if points.isEmpty {
                Text("No scored sessions in this range.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .fill(Theme.surface)
                    )
            } else {
                chart(points)
            }
        }
    }

    private func chart(_ points: [(session: ClassSession, record: StudentSessionRecord)]) -> some View {
        Chart(points, id: \.session.id) { point in
            LineMark(
                x: .value("Date", point.session.startedAt),
                y: .value("Score", point.record.finalScore)
            )
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .foregroundStyle(
                .linearGradient(
                    colors: [Theme.riskHigh, Theme.riskElevated, Theme.riskLow],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            PointMark(
                x: .value("Date", point.session.startedAt),
                y: .value("Score", point.record.finalScore)
            )
            .foregroundStyle(point.record.risk(sensitivity: store.settings.sensitivity).color)
            .symbolSize(34)
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(values: [0.15, 0.5, 0.85]) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(bandLabel(raw))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 9))
            }
        }
        .frame(height: 150)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private func bandLabel(_ score: Double) -> String {
        if score >= 0.7 { return "High" }
        if score >= 0.4 { return "Medium" }
        return "Low"
    }

    // MARK: - Speaking time

    private var speakingTimeSection: some View {
        let thisWeek = windowSeconds(daysAgo: 0..<7)
        let lastWeek = windowSeconds(daysAgo: 7..<14)
        let cohort = cohortWindowSeconds(daysAgo: 0..<7)

        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Speaking time")

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.accent)
                        Text(minutesDisplay(thisWeek))
                            .font(.system(size: 20, weight: .semibold))
                    }
                    Text("This week")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                if lastWeek > 0 {
                    statTile(
                        value: percentChangeDisplay(from: lastWeek, to: thisWeek),
                        label: "vs last week",
                        tint: thisWeek >= lastWeek ? Theme.riskLow : Theme.riskElevated,
                        symbol: thisWeek >= lastWeek ? "arrow.up.right" : "arrow.down.right"
                    )
                }

                if let average = cohortAverage(cohort) {
                    statTile(value: minutesDisplay(average), label: "Class average")
                }

                if let percentile = percentile(thisWeek, in: cohort) {
                    statTile(value: ordinal(percentile), label: "Percentile")
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }

    private func statTile(value: String, label: String, tint: Color = .primary, symbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                }
                Text(value).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    /// Seconds this student spoke across recorded sessions starting between
    /// `daysAgo.upperBound` and `daysAgo.lowerBound` days before now — `0..<7`
    /// reads as "this week", `7..<14` as "the week before".
    private func windowSeconds(daysAgo: Range<Int>) -> Int {
        guard let lower = Calendar.current.date(byAdding: .day, value: -daysAgo.upperBound, to: Date()),
              let upper = Calendar.current.date(byAdding: .day, value: -daysAgo.lowerBound, to: Date())
        else { return 0 }
        return history
            .filter { $0.session.startedAt >= lower && $0.session.startedAt < upper }
            .reduce(0) { $0 + $1.record.speakingSeconds }
    }

    /// Every roster student's speaking seconds in the same window, keyed by
    /// identity — the only way to say "class average" or "percentile" honestly.
    ///
    /// Restricted to identities that match somebody on the roster. A recorded
    /// session also holds whoever else was in the room — Anchor's own bot on
    /// archives written before it was excluded, a co-teacher, a guest — and
    /// counting them makes "class average" an average of something that isn't
    /// the class. The bot in particular never speaks, so leaving it in dragged
    /// the average toward zero and flattered every student's percentile.
    private func cohortWindowSeconds(daysAgo: Range<Int>) -> [String: Int] {
        guard let lower = Calendar.current.date(byAdding: .day, value: -daysAgo.upperBound, to: Date()),
              let upper = Calendar.current.date(byAdding: .day, value: -daysAgo.lowerBound, to: Date())
        else { return [:] }

        let roster = classroom.roster(forCourse: courseID)
        let manualLinks = links.links(forCourse: courseID)
        let rosterKeys = Set(roster.flatMap {
            matchIdentityKeys(for: $0, roster: roster, manualLinks: manualLinks)
        })
        guard !rosterKeys.isEmpty else { return [:] }

        var totals: [String: Int] = [:]
        for linked in archive.classrooms(forCourseID: courseID) {
            for session in archive.sessions(forClassroom: linked.id)
            where session.startedAt >= lower && session.startedAt < upper {
                for record in session.students {
                    let key = normalizedArchiveIdentity(record.identityKey)
                    guard rosterKeys.contains(key) else { continue }
                    totals[key, default: 0] += record.speakingSeconds
                }
            }
        }
        return totals
    }

    private func cohortAverage(_ cohort: [String: Int]) -> Double? {
        guard !cohort.isEmpty else { return nil }
        return Double(cohort.values.reduce(0, +)) / Double(cohort.count)
    }

    /// Nil unless there's at least one other student to be measured against —
    /// a percentile of one is not a percentile.
    private func percentile(_ mine: Int, in cohort: [String: Int]) -> Int? {
        guard let student else { return nil }
        let keys = matchIdentityKeys(
            for: student,
            roster: classroom.roster(forCourse: courseID),
            manualLinks: links.links(forCourse: courseID)
        )
        guard keys.contains(where: { cohort[$0] != nil }), cohort.count > 1 else { return nil }
        let values = cohort.values.sorted()
        let below = values.filter { $0 < mine }.count
        return Int((Double(below) / Double(values.count - 1) * 100).rounded())
    }

    // MARK: - Suggested actions

    /// A composed suggestion. Deliberately carries no action of its own.
    ///
    /// Each of these used to end in a button — "Suggest action", "Assign peer
    /// group", "Send encouragement" — that answered "Encouragement sent." and
    /// "Added to the next peer group." while doing nothing at all. Anchor sends
    /// no messages and builds no groups, so every one of those confirmations
    /// was false. The suggestion itself is the deliverable; the only thing
    /// Anchor can honestly do with it is hand it to the teacher, which is what
    /// the copy button now does. See StudentDetailView.actions for the same
    /// reasoning applied to the live screen.
    private struct Suggestion: Identifiable {
        var id: String { title }
        let icon: String
        let tint: Color
        let title: String
        let detail: String

        /// What lands on the clipboard: the heading and the reason behind it.
        var copyText: String { title + "\n\n" + detail }
    }

    private var suggestions: [Suggestion] {
        var result: [Suggestion] = []
        let cohort = cohortWindowSeconds(daysAgo: 0..<7)
        let thisWeek = windowSeconds(daysAgo: 0..<7)

        if let average = cohortAverage(cohort), average > 0, cohort.count > 1, Double(thisWeek) < average * 0.75 {
            result.append(Suggestion(
                icon: "bubble.left.fill",
                tint: Theme.accent,
                title: "Encourage class participation",
                detail: "\(firstName) spoke less than the class average this week."
            ))
        }

        if let snapshot, snapshot.missingCount > 0 {
            result.append(Suggestion(
                icon: "person.2.fill",
                tint: Theme.riskElevated,
                title: "Collaborative learning opportunity",
                detail: "\(firstName) has \(snapshot.missingCount) missing "
                    + "assignment\(snapshot.missingCount == 1 ? "" : "s") — pair them with a "
                    + "peer for a small-group activity."
            ))
        }

        if isImproving {
            result.append(Suggestion(
                icon: "star.fill",
                tint: Theme.riskLow,
                title: "Reinforce recent progress",
                detail: "Recognize \(firstName)'s improved engagement this week."
            ))
        }

        return Array(result.prefix(3))
    }

    /// The two most recent reliable sessions read as improving when the score
    /// dropped by a real margin, not by noise.
    private var isImproving: Bool {
        let reliable = history.filter { $0.record.hasReliableScore }.suffix(2).map(\.record.finalScore)
        guard reliable.count == 2 else { return false }
        return reliable[0] - reliable[1] >= 0.08
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "Suggested actions")
                Text("Composed from \(firstName)'s recent signals — not generated by a model.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if suggestions.isEmpty {
                Text("No flags right now — steady engagement across recent sessions.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .fill(Theme.surface)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(suggestions) { suggestion in
                        suggestionRow(suggestion)
                        if suggestion.id != suggestions.last?.id {
                            Divider().overlay(Theme.hairline)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .fill(Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
            }

            if let actionConfirmation {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text(actionConfirmation)
                        .font(.system(size: 10.5))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.riskLow)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func suggestionRow(_ suggestion: Suggestion) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(suggestion.tint.opacity(0.14))
                Image(systemName: suggestion.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(suggestion.tint)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.system(size: 12, weight: .medium))
                Text(suggestion.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(suggestion.copyText, forType: .string)
                withAnimation(.easeOut(duration: 0.2)) {
                    actionConfirmation = "Copied to the clipboard"
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Formatting

    private var firstName: String {
        guard let name = student?.name, !name.isEmpty else { return "This student" }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private func minutesDisplay(_ seconds: Int) -> String {
        "\(Int((Double(seconds) / 60).rounded())) min"
    }

    private func minutesDisplay(_ seconds: Double) -> String {
        minutesDisplay(Int(seconds.rounded()))
    }

    private func percentChangeDisplay(from old: Int, to new: Int) -> String {
        guard old > 0 else { return "—" }
        let percent = Int((((Double(new) - Double(old)) / Double(old)) * 100).rounded())
        return percent >= 0 ? "+\(percent)%" : "\(percent)%"
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 100 {
        case 11...13:
            suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
