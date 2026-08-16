//
//  StudentDetailView.swift
//  Anchor
//
//  Drill-down for one student: score, signals, trend, timeline and
//  suggested next steps.
//

import SwiftUI

struct StudentDetailView: View {
    let studentID: UUID

    @EnvironmentObject private var store: EngagementStore
    @EnvironmentObject private var coach: LiveCoachViewModel

    /// Confirmation text shown after an action button is used.
    @State private var actionConfirmation: String?

    var body: some View {
        if let student = store.student(id: studentID) {
            content(for: student)
        } else {
            missingState
        }
    }

    // MARK: - Content

    private func content(for student: Student) -> some View {
        let level = store.risk(for: student)

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                header(for: student, level: level)
                // Directly under the header: it is the only part of this screen
                // that is about right now, and the only part a teacher opens
                // mid-lesson to read.
                LiveTopicSection(student: student)
                ScoreBreakdownCard(student: student, level: level)
                StruggleFactorsSection(student: student, level: level)
                signals(for: student, level: level)
                QuickInfoCard(student: student)
                AcademicSection(student: student)
                trend(for: student, level: level)
                timeline(for: student)
                recommendations(for: student, level: level)
                actions(for: student)
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func header(for student: Student, level: RiskLevel) -> some View {
        HStack(spacing: 12) {
            ScoreRing(
                score: student.struggleScore,
                level: level,
                isKnown: student.hasReliableScore
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(student.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if student.hasReliableScore {
                        StatusChip(level.label, systemImage: level.symbolName, tint: level.color)
                    } else {
                        StatusChip("Not enough signal", systemImage: "questionmark", tint: .secondary)
                    }
                    StatusChip(
                        student.statusDescription(now: store.now),
                        systemImage: student.status.symbolName,
                        tint: .secondary
                    )
                }

                HStack(spacing: 4) {
                    Image(systemName: trendSymbol(for: student))
                        .font(.system(size: 9, weight: .bold))
                    Text(trendDescription(for: student))
                        .font(Theme.captionFont)
                }
                .foregroundStyle(trendColor(for: student))
            }

            Spacer(minLength: 0)
        }
    }

    private func signals(for student: Student, level: RiskLevel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Named for its source now that an ACADEMIC panel sits beside it.
            SectionLabel(text: "Engagement (Zoom)")

            // Three columns in both contexts: the window caps this pane's width,
            // so the tiles stay even (3 + 3) rather than wrapping raggedly.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3),
                spacing: 7
            ) {
                MetricTile(
                    symbolName: "waveform",
                    value: student.metrics.speakingDisplay,
                    caption: "Speaking",
                    tint: level.color
                )
                MetricTile(
                    symbolName: "bubble.left.fill",
                    value: "\(student.metrics.chatMessages)",
                    caption: "Chat msgs"
                )
                MetricTile(
                    symbolName: "video.fill",
                    value: "\(Int((student.metrics.cameraOnRatio * 100).rounded()))%",
                    caption: "Camera on"
                )
                MetricTile(
                    symbolName: "chart.bar.fill",
                    value: "\(student.metrics.pollResponses)/\(student.metrics.pollsAsked)",
                    caption: "Polls"
                )
                MetricTile(
                    symbolName: "questionmark.circle.fill",
                    value: "\(student.metrics.questionsAsked)",
                    caption: "Questions"
                )
                MetricTile(
                    symbolName: "timer",
                    value: "\(student.metrics.averageResponseSeconds)s",
                    caption: "Avg. reply"
                )
            }
        }
    }

    private func trend(for student: Student, level: RiskLevel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(
                text: "Struggle trend",
                trailingText: "Last \(student.trend.count) samples"
            )

            VStack(spacing: 4) {
                Sparkline(values: student.trend, tint: level.color)
                    .frame(height: 46)

                HStack {
                    Text("Session start")
                    Spacer()
                    Text("Now")
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }

    private func timeline(for student: Student) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Activity timeline")

            VStack(alignment: .leading, spacing: 0) {
                let events = Array(student.activity.prefix(7))
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    TimelineRow(
                        event: event,
                        now: store.now,
                        isFirst: index == 0,
                        isLast: index == events.count - 1
                    )
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }

    /// The model's next step where it wrote one, Anchor's composed lines where
    /// it didn't.
    ///
    /// One box rather than two. The model reads the live transcript and answers
    /// the question this panel asks — what to do about this student, right now —
    /// so when it has an answer, that is the answer, and the composed lines
    /// would only restate it less well. When it doesn't (no Apple Intelligence,
    /// no transcript, a refusal, a timeout) the composed lines are the whole
    /// feature, exactly as `RecommendationGenerator.fallback` describes.
    ///
    /// The source is always stated. A teacher acting on a sentence about a child
    /// should know whether a model wrote it.
    private func recommendations(for student: Student, level: RiskLevel) -> some View {
        let live = coach.recommendation(forStudentID: student.id)

        return VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Suggested next steps")

            VStack(alignment: .leading, spacing: 7) {
                if let live {
                    liveStep(live, level: level)
                } else {
                    ForEach(Array(student.recommendations.enumerated()), id: \.offset) { _, text in
                        composedStep(text, level: level)
                    }
                }

                if let note = student.note {
                    Divider().overlay(Theme.hairline)
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "note.text")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }

    /// The model's line: the instruction, then the evidence behind it, then the
    /// question to actually put to the student where the transcript gave one.
    private func liveStep(_ recommendation: LiveRecommendation, level: RiskLevel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "brain")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(level.color)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recommendation.headline)
                        .font(.system(size: 11, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recommendation.reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let question = recommendation.suggestedQuestion {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "questionmark.bubble")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    Text(question)
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(recommendation.source.label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    /// A composed line. `checklist` rather than `sparkles`: this text was
    /// assembled from the matched signals, and dressing it as generated output
    /// would mislead the one reader who matters.
    private func composedStep(_ text: String, level: RiskLevel) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "checklist")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(level.color)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The one action here that does something.
    ///
    /// Two buttons used to sit in this space — "Send check-in" and "Pair in
    /// breakout" — which answered "Private check-in sent" and "Queued for the
    /// next breakout" without sending or queueing anything. Anchor has no
    /// messaging and no breakout control, so both messages were false, and a
    /// teacher who believed the first would have thought a struggling child had
    /// been contacted when nobody had. That is the most expensive kind of bug
    /// this product can have.
    ///
    /// Putting the suggestion on the clipboard is the useful thing Anchor can
    /// actually do with it — the teacher pastes it into Zoom chat, an email or
    /// their own notes — so it is the only thing offered.
    private func actions(for student: Student) -> some View {
        let suggestion = suggestionText(for: student)

        return VStack(spacing: 7) {
            actionButton("Copy suggestion", systemImage: "doc.on.doc", prominent: true) {
                guard let suggestion else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(suggestion, forType: .string)
                confirm("Copied to the clipboard")
            }
            .disabled(suggestion == nil)

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

    /// Exactly the text shown in "Suggested next steps" above, so what lands on
    /// the clipboard is what the teacher just read. Nil when there is nothing to
    /// copy, which disables the button rather than copying an empty string.
    private func suggestionText(for student: Student) -> String? {
        if let live = coach.recommendation(forStudentID: student.id) {
            let parts = [live.headline, live.reason, live.suggestedQuestion]
                .compactMap { $0?.trimmed }
                .filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }

        let composed = student.recommendations
            .map(\.trimmed)
            .filter { !$0.isEmpty }
        return composed.isEmpty ? nil : composed.joined(separator: "\n\n")
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(prominent ? Theme.accent : Color.secondary.opacity(0.35))
        .controlSize(.small)
    }

    private var missingState: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("This student is no longer in the meeting.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func confirm(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            actionConfirmation = message
        }
    }

    private func trendSymbol(for student: Student) -> String {
        if student.trendDelta > 0.04 { return "arrow.up.right" }
        if student.trendDelta < -0.04 { return "arrow.down.right" }
        return "arrow.right"
    }

    private func trendDescription(for student: Student) -> String {
        let points = Int((abs(student.trendDelta) * 100).rounded())
        if student.trendDelta > 0.04 { return "Up \(points) pts this session" }
        if student.trendDelta < -0.04 { return "Down \(points) pts this session" }
        return "Holding steady this session"
    }

    private func trendColor(for student: Student) -> Color {
        if student.trendDelta > 0.04 { return Theme.riskHigh }
        if student.trendDelta < -0.04 { return Theme.riskLow }
        return .secondary
    }
}

// MARK: - Why this score

/// The model's own account of the score: each signal, and how much of the
/// prediction rests on it.
///
/// Attribution costs one extra prediction per feature, so it runs here — for the
/// one student a teacher opened — rather than for the whole roster on every
/// two-minute refresh.
private struct StruggleFactorsSection: View {
    let student: Student
    let level: RiskLevel

    @State private var factors: [StruggleFactor] = []
    @State private var isCalculating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Why this score", trailingText: student.scoreSource.label)

            VStack(alignment: .leading, spacing: 8) {
                headline

                // Only on the first pass: re-scoring an open student takes a
                // fraction of a frame, and flashing a spinner at them every two
                // minutes would read as instability rather than freshness.
                if isCalculating, factors.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).scaleEffect(0.7)
                        Text("Loading…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else if factors.isEmpty {
                    Text(emptyMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Factors:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    ForEach(factors) { factor in
                        row(factor)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
        .task(id: student.features) { await calculate() }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("Struggle Score:")
                .font(.system(size: 12, weight: .medium))
            Text(student.scoreDisplay)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(student.hasReliableScore ? level.color : Color.secondary)
            Spacer(minLength: 0)
            Image(systemName: student.scoreSource.symbolName)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private func row(_ factor: StruggleFactor) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(factor.weight.tint)
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            Text(factor.title)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text("(\(factor.weight.label))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Text("+\(factor.impactPoints)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(factor.weight.tint)
                .help("Removing this signal would lower the score by about \(factor.impactPoints) points.")
        }
    }

    private var emptyMessage: String {
        if student.scoreSource == .heuristic {
            return "The Core ML model isn't loaded, so this score comes from signal "
                + "heuristics and can't be broken down by factor."
        }
        if !student.hasReliableScore {
            return "Zoom isn't reporting enough in-meeting signal to explain this score."
        }
        return "No single signal stands out — the model reads this student as engaged."
    }

    private func calculate() async {
        guard let features = student.features else {
            factors = []
            return
        }

        isCalculating = true
        defer { isCalculating = false }

        // Off the main actor: 11 predictions is milliseconds, but the popover
        // should never be the thing waiting on them.
        factors = await Task.detached(priority: .userInitiated) {
            StruggleDetectionService.shared.factors(for: features)
        }.value
    }
}

private extension StruggleFactor.Weight {
    var tint: Color {
        switch self {
        case .high: Theme.riskHigh
        case .medium: Theme.riskElevated
        case .low: .secondary
        }
    }
}

// MARK: - Timeline row

private struct TimelineRow: View {
    let event: ActivityEvent
    let now: Date
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            // Connector rail
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Theme.hairline)
                    .frame(width: 1, height: 5)

                ZStack {
                    Circle()
                        .fill(event.kind.tint.opacity(0.18))
                        .frame(width: 16, height: 16)
                    Image(systemName: event.kind.symbolName)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(event.kind.tint)
                }

                Rectangle()
                    .fill(isLast ? Color.clear : Theme.hairline)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(event.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Text(Theme.relativeString(from: event.timestamp, to: now))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : 9)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
