//
//  LessonTopicPanel.swift
//  Anchor
//
//  "Option C": the teacher tells Anchor what the lesson is about.
//
//  Anchor prefers to read the topic off the live transcript, but a lot of
//  meetings will never give it one — Zoom's automated captions are a paid-plan
//  feature, and in a meeting without multi-language transcription only the host
//  can start them. This panel is what keeps the topic-aware half of the feature
//  working in those rooms, and it is also the fastest way for a teacher to
//  correct Anchor when the transcript reads the lesson wrong.
//
//  It shows the live state first, so a teacher who doesn't need it can see that
//  and move on rather than filling in a form Anchor was never going to use.
//

import SwiftUI

struct LessonTopicPanel: View {

    @EnvironmentObject private var coach: LiveCoachViewModel

    @State private var topic = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title

            statusRow

            if coach.transcriptAvailability.isBlocked,
               let detail = coach.transcriptAvailability.detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Theme.hairline)

            entryFields
            buttons

            if let manual = coach.transcript.manualTopic {
                appliedRow(manual)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .onAppear(perform: loadExistingEntry)
    }

    // MARK: - Header

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Lesson topic")
                .font(Theme.titleFont)
            Text("Anchor asks for this when it joins each class. You can update "
                 + "it here if the lesson changes or the transcript reads it wrong.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What Anchor currently believes, and where it got it.
    private var statusRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 10))
                .foregroundStyle(coach.transcriptAvailability.isBlocked ? Theme.riskElevated : Theme.accent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(coach.transcriptAvailability.headline)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)

                if let current = coach.effectiveTopic {
                    Text("Currently: \(current.questionDisplay.map { "\(current.topic) — \($0)" } ?? current.topic)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var symbolName: String {
        if coach.transcriptAvailability.isBlocked { return "exclamationmark.bubble" }
        return coach.transcriptAvailability.isLive ? "waveform" : "text.bubble"
    }

    // MARK: - Entry

    /// One field. There is deliberately nowhere to type the current *question*:
    /// it changes every few minutes, so a box for it is a box the teacher has to
    /// keep coming back to mid-lesson, and a stale entry aims the recommendation
    /// at something the class finished twenty minutes ago. Questions come from
    /// the live transcript, which can keep up. This is for the topic, which
    /// holds for the whole lesson — and it is remembered, so a teacher on a unit
    /// types it once rather than every morning.
    private var entryFields: some View {
        LabeledField(
            label: "Topic",
            placeholder: "Photosynthesis",
            text: $topic
        )
        .onSubmit(apply)
    }

    private var buttons: some View {
        HStack(spacing: 7) {
            Button("Use this topic", action: apply)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(topic.trimmed.isEmpty || topic.trimmed == coach.transcript.manualTopic?.topic)

            if coach.transcript.manualTopic != nil {
                Button("Clear") {
                    coach.clearManualTopic()
                    topic = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer(minLength: 0)
        }
    }

    private func apply() {
        guard !topic.trimmed.isEmpty else { return }
        coach.setManualTopic(topic: topic)
    }

    /// Confirms what was stored, and — the part worth stating — that the live
    /// transcript still wins while it is running.
    private func appliedRow(_ manual: ClassTopic) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(Theme.riskLow)
                .padding(.top, 1)

            Text(coach.transcriptAvailability.isLive
                 ? "Saved as a fallback. The live transcript is running, so Anchor "
                    + "is using what it hears; this takes over if captions stop."
                 : "Anchor is matching students' coursework against “\(manual.topic)”.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Helpers

    /// Repopulates the fields from what was already saved, so reopening Settings
    /// shows the current entry rather than two blank boxes over a filled state.
    private func loadExistingEntry() {
        guard let manual = coach.transcript.manualTopic else { return }
        if topic.isEmpty { topic = manual.topic }
    }
}

// MARK: - Field

private struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
        }
    }
}
