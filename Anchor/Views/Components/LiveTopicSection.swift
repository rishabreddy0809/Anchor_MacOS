//
//  LiveTopicSection.swift
//  Anchor
//
//  The detail view's answer to "why is Anchor telling me to ask this student
//  about this?"
//
//  The instruction itself lives elsewhere — on the dashboard card, and in the
//  "Suggested next steps" box further down this same screen. This is the working
//  behind it: what the class is on, the question the teacher actually asked,
//  and — the part that makes the suggestion worth trusting — the specific past
//  assignments the claim rests on, with their titles and marks.
//
//  Quoting the evidence rather than summarising it is deliberate. "Struggled
//  with photosynthesis" is an assertion a teacher has to take on faith; "58% on
//  Photosynthesis Lab, and the chlorophyll worksheet is missing" is something
//  they can check, disagree with, and act on.
//

import SwiftUI

struct LiveTopicSection: View {

    let student: Student

    @EnvironmentObject private var coach: LiveCoachViewModel

    private var topic: ClassTopic? { coach.effectiveTopic }
    private var weakness: TopicWeakness? { coach.weakness(forStudentID: student.id) }

    var body: some View {
        // Gated on the topic alone, because every row in the card is about the
        // topic: without one there is a header and an empty box. The dashboard
        // already explains *why* there's no topic; repeating it on every student
        // would be three copies of the same sentence on screen at once.
        if topic != nil {
            VStack(alignment: .leading, spacing: 6) {
                header
                card
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 5) {
            SectionLabel(text: "Live topic")
            Spacer(minLength: 4)
            if let topic {
                TopicChip(topic: topic, isAnalyzing: coach.isAnalyzing)
            }
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let question = topic?.questionDisplay {
                questionRow(question)
            }

            // The suggestion itself deliberately isn't repeated here — it is the
            // "Suggested next steps" box further down the same screen, and two
            // copies of one instruction on one screen reads as two instructions.
            // This card is the working behind it: the topic, the question, and
            // the past marks the claim rests on.
            if let weakness, !weakness.isEmpty {
                if topic?.questionDisplay != nil { divider }
                historyRows(weakness)
            } else if let topic {
                if topic.questionDisplay != nil { divider }
                noHistoryRow(topic)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private var divider: some View {
        Divider().overlay(Theme.hairline)
    }

    // MARK: - Rows

    /// The question as the teacher put it, transcribed.
    private func questionRow(_ question: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "questionmark.bubble")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("On the floor now")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(question)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }


    /// The past work behind the claim, most relevant first.
    private func historyRows(_ weakness: TopicWeakness) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Earlier work on \(weakness.topic.lowercased())")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 4)

                if weakness.averageFraction != nil {
                    Text(weakness.averageDisplay)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Self.gradeColor(weakness.averageFraction))
                }
            }

            ForEach(weakness.relatedWork.prefix(4)) { work in
                workRow(work)
            }

            if weakness.relatedWork.count > 4 {
                Text("+ \(weakness.relatedWork.count - 4) more on this topic")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func workRow(_ work: TopicWeakness.RelatedWork) -> some View {
        HStack(spacing: 6) {
            Image(systemName: work.isMissing ? "exclamationmark.circle" : "checkmark.circle")
                .font(.system(size: 8))
                .foregroundStyle(work.isMissing ? Theme.riskHigh : .secondary)

            Text(work.title)
                .font(.system(size: 10))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(work.scoreDisplay)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(
                    work.isMissing ? Theme.riskHigh : Self.gradeColor(work.fraction)
                )
        }
        // The relevance behind each row, for a teacher who wants to know why
        // Anchor thinks this assignment is about the topic at all.
        .help("\(Int((work.relevance * 100).rounded()))% match to the current topic")
    }

    /// Said explicitly, because "no history shown" and "no difficulty on this
    /// topic" look identical otherwise — and only one of them is reassuring.
    private func noHistoryRow(_ topic: ClassTopic) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "tray")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)

            Text(explanationForNoHistory(topic))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func explanationForNoHistory(_ topic: ClassTopic) -> String {
        guard student.academic != nil else {
            return "No Google Classroom coursework matched to this student, so "
                + "there's no earlier work on \(topic.topic.lowercased()) to compare."
        }
        return "No earlier coursework on \(topic.topic.lowercased()) — this "
            + "suggestion rests on the live signals alone."
    }

    // MARK: - Helpers

    /// Same traffic light as everywhere else, so a grade reads the way a
    /// struggle score does.
    private static func gradeColor(_ fraction: Double?) -> Color {
        guard let fraction else { return .secondary }
        if fraction < 0.6 { return Theme.riskHigh }
        if fraction < 0.75 { return Theme.riskElevated }
        return Theme.riskLow
    }
}
