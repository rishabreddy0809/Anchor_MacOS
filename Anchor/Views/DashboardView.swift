//
//  DashboardView.swift
//  Anchor
//
//  The default popover route: meeting status, session controls and the
//  most-struggling students.
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: EngagementStore
    @EnvironmentObject private var router: PopoverRouter
    @EnvironmentObject private var coach: LiveCoachViewModel

    @State private var isEditingTopic = false

    var body: some View {
        if store.hasData, let meeting = store.meeting {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    meetingCard(meeting)
                    // Only once it has something to say. Mid-class the roster is
                    // what matters, and an unconfigured prompt here would be
                    // asking a teacher to go and set something up during a
                    // lesson — hence no `onConnect`.
                    ScheduleCard()
                    riskSummary
                    // Above the roster on purpose: this is the part a teacher
                    // can act on without reading anything else, and the ranked
                    // list below is the evidence behind it.
                    engagementSection
                    studentList
                    seeAllButton
                    modelFootnote
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            // The dashboard's weakest moment, and most of a teaching day:
            // nothing is running. The schedule is the one thing worth showing
            // between classes, so it goes above the empty state rather than
            // instead of it — the empty state still explains why there is no
            // roster.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    ScheduleCard(onConnect: { router.push(.settings) })
                    EmptyStateView(isCompact: true) { router.push(.settings) }
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Meeting card

    private func meetingCard(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: meeting.platform.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                Text(meeting.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                liveIndicator(meeting)
            }

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("Elapsed")
                        .font(Theme.captionFont)
                        .foregroundStyle(.secondary)
                    Text(Theme.elapsedString(store.elapsed))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }

                Divider().frame(height: 12)

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9))
                    Text("\(store.students.count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                sessionControls
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private func liveIndicator(_ meeting: Meeting) -> some View {
        let isLive = meeting.isLive && store.sessionState.isRunning
        return StatusChip(
            isLive ? "Live" : "Paused",
            systemImage: isLive ? "circle.fill" : "pause.fill",
            tint: isLive ? Theme.riskLow : .secondary
        )
    }

    private var sessionControls: some View {
        HStack(spacing: 5) {
            Button {
                store.setSessionState(.running)
            } label: {
                Label("Start", systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(store.sessionState.isRunning)

            Button {
                store.setSessionState(.paused)
            } label: {
                Label("Pause", systemImage: "pause.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(!store.sessionState.isRunning)
        }
        .controlSize(.small)
    }

    // MARK: - Risk summary

    private var riskSummary: some View {
        HStack(spacing: 7) {
            summaryPill(count: store.highRiskCount, level: .high)
            summaryPill(count: store.elevatedCount, level: .elevated)
            summaryPill(count: store.engagedCount, level: .low)
        }
    }

    private func summaryPill(count: Int, level: RiskLevel) -> some View {
        HStack(spacing: 5) {
            RiskDot(level: level, size: 6)
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
            Text(level.shortLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.surface)
        )
    }

    // MARK: - Engagement

    /// Live, topic-aware suggestions.
    ///
    /// The section is rendered even when it has no cards, because *why* it is
    /// empty is itself the useful information — "listening for the topic" and
    /// "Zoom won't transcribe this meeting" call for completely different things
    /// from the teacher, and an absent section says neither.
    @ViewBuilder
    private var engagementSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                SectionLabel(text: "Engagement")

                Spacer(minLength: 4)

                if let topic = coach.effectiveTopic {
                    TopicChip(topic: topic, isAnalyzing: coach.isAnalyzing)
                } else if coach.isAnalyzing {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                    Text("Reading the transcript…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                topicButton
            }
            .padding(.horizontal, 2)
            .animation(.easeInOut(duration: 0.2), value: coach.isAnalyzing)

            if coach.recommendations.isEmpty {
                emptyEngagementState
            } else {
                VStack(spacing: 5) {
                    ForEach(coach.recommendations) { recommendation in
                        RecommendationCard(recommendation: recommendation) {
                            router.push(.detail(recommendation.studentID))
                        }
                    }
                }
                // Cards appear and reorder as students go quiet and the topic
                // moves on; sliding them keeps that legible where a hard cut
                // mid-lesson reads as the panel glitching.
                .animation(
                    .easeInOut(duration: 0.3),
                    value: coach.recommendations.map(\.id)
                )
            }

            if let note = engagementFootnote {
                Text(note)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }

    /// Topic entry, on the dashboard rather than only in Settings.
    ///
    /// The transcript is the preferred source and needs nothing from the
    /// teacher — but Zoom's automated captions are a paid-plan feature, so for a
    /// large share of rooms the transcript will never arrive and this is the
    /// *only* way the topic-aware half of the app ever runs. Leaving the one
    /// control that unblocks it two screens away, in Settings, meant a teacher
    /// whose plan can't transcribe had no way to find it mid-lesson.
    ///
    /// A popover rather than a push: setting the topic is a ten-second
    /// interruption during a live class, not a destination.
    private var topicButton: some View {
        Button {
            isEditingTopic = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 9, weight: .semibold))
                Text(coach.effectiveTopic == nil ? "Set topic" : "Change")
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.accent)
        .popover(isPresented: $isEditingTopic, arrowEdge: .bottom) {
            LessonTopicPanel()
                .environmentObject(coach)
                .frame(width: 320)
                .padding(10)
        }
        .help("Tell Anchor what the lesson is about, so it can match coursework to it")
    }

    private var emptyEngagementState: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: coach.transcriptAvailability.isBlocked
                ? "exclamationmark.bubble"
                : "ear")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(coach.emptyStateExplanation ?? "Nothing to suggest right now.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = coach.transcriptAvailability.detail,
                   coach.transcriptAvailability.isBlocked {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    /// Named only when the on-device model *isn't* writing the recommendations.
    ///
    /// Same rule as the Core ML footnote below: a working model needs no
    /// announcement, but a teacher reading composed text should not believe they
    /// are reading generated text.
    private var engagementFootnote: String? {
        guard !coach.recommendations.isEmpty else { return nil }
        guard !coach.modelAvailability.isReady else { return nil }
        return coach.modelAvailability.headline
    }

    // MARK: - Students

    private var studentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                SectionLabel(text: "Needs attention")

                Spacer(minLength: 4)

                if store.isScoring {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                    Text("Updating scores…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Highest struggle first")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
            .animation(.easeInOut(duration: 0.2), value: store.isScoring)

            VStack(spacing: 1) {
                ForEach(store.topStudents) { student in
                    StudentRow(
                        student: student,
                        level: store.risk(for: student),
                        now: store.now
                    ) {
                        router.push(.detail(student.id))
                    }
                }
            }
            // Students change rank every refresh once scores update live;
            // sliding them into place reads as the list responding, where a
            // hard cut every ten seconds reads as a glitch.
            .animation(.easeInOut(duration: 0.35), value: store.topStudents.map(\.id))
        }
    }

    private var seeAllButton: some View {
        Button {
            router.push(.allStudents)
        } label: {
            HStack(spacing: 5) {
                Text("See All Students")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(store.students.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(RowButtonStyle())
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    // MARK: - Model status

    /// Only shown when the model *isn't* driving the scores — a working model
    /// needs no announcement, but a silent fallback to arithmetic would be a
    /// misrepresentation of what the numbers mean.
    @ViewBuilder
    private var modelFootnote: some View {
        if case .ready = store.modelState {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.top, 1)
                Text(store.modelState.summary)
                    .font(.system(size: 10))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
        }
    }
}
