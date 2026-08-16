//
//  LessonTopicPrompt.swift
//  Anchor
//
//  A short, per-class check-in shown once Anchor's bot has entered a meeting.
//

import SwiftUI

struct LessonTopicPrompt: View {
    @EnvironmentObject private var coach: LiveCoachViewModel
    @EnvironmentObject private var zoom: ZoomViewModel

    @State private var topic = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("What is this class about?", systemImage: "book.closed.fill")
                .font(.system(size: 20, weight: .semibold))

            Text("Anchor just joined this class. Add the lesson topic to make its student insights more relevant. You can also continue without one.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("e.g. Photosynthesis", text: $topic)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .onSubmit(useTopic)

            HStack {
                Button("Skip for this class") {
                    coach.clearManualTopic()
                    zoom.dismissLessonTopicPrompt()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Use lesson topic", action: useTopic)
                    .buttonStyle(.borderedProminent)
                    .disabled(topic.trimmed.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .interactiveDismissDisabled()
    }

    private func useTopic() {
        let trimmed = topic.trimmed
        guard !trimmed.isEmpty else { return }
        coach.setManualTopic(topic: trimmed)
        zoom.dismissLessonTopicPrompt()
    }
}
