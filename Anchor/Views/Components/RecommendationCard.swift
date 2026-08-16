//
//  RecommendationCard.swift
//  Anchor
//
//  The "→ Ask Sarah about Question 3" card.
//
//  Read while teaching, so the visual hierarchy is the order a teacher needs the
//  information in: who, then what to say, then why. The reason is last and
//  quietest — it is what makes the suggestion trustworthy, not what makes it
//  actionable, and a teacher mid-sentence only reads the first two lines.
//

import SwiftUI

// MARK: - Urgency bridging

extension LiveRecommendation.Urgency {
    /// The recommendation and the student row it came from are coloured by the
    /// same scale, deliberately. See RecommendationGenerator for why urgency is
    /// never adjusted independently of the score.
    var riskLevel: RiskLevel {
        switch self {
        case .high: .high
        case .elevated: .elevated
        case .low: .low
        }
    }

    var color: Color { riskLevel.color }
}

// MARK: - Card

struct RecommendationCard: View {

    let recommendation: LiveRecommendation
    /// Tapping the card opens the student it is about.
    var onOpen: (() -> Void)?

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(alignment: .top, spacing: 0) {
                // A full-height bar rather than a dot: it ties the whole card to
                // one urgency at a glance, and survives the card being read from
                // three feet away over a laptop lid.
                Rectangle()
                    .fill(recommendation.urgency.color)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 5) {
                    header
                    action
                    if !recommendation.reason.isEmpty { reason }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(RowButtonStyle())
        .clipShape(RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .strokeBorder(recommendation.urgency.color.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens \(recommendation.studentName)'s detail")
    }

    // MARK: Rows

    private var header: some View {
        HStack(spacing: 5) {
            RiskDot(level: recommendation.urgency.riskLevel, size: 6)

            Text(recommendation.studentName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Text(recommendation.statusSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    /// The instruction, and under it the question to actually put to them.
    private var action: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(recommendation.urgency.color)

                Text(recommendation.headline)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            if let question = recommendation.suggestedQuestion {
                // Quoted because it is the teacher's own words coming back to
                // them, transcribed — not something Anchor composed.
                Text("“\(question)”")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 14)
            }
        }
    }

    private var reason: some View {
        Text(recommendation.reason)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    private var accessibilityLabel: String {
        [
            recommendation.studentName,
            recommendation.statusSummary,
            recommendation.headline,
            recommendation.suggestedQuestion,
            recommendation.reason
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }
}

// MARK: - Topic chip

/// "Photosynthesis · Question 3" with the source behind it.
struct TopicChip: View {
    let topic: ClassTopic
    var isAnalyzing: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isAnalyzing ? "waveform" : "text.bubble")
                .font(.system(size: 9, weight: .semibold))
                .symbolEffect(.variableColor, isActive: isAnalyzing)

            Text(topic.topic)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)

            if let label = topic.questionLabel {
                Text("·")
                    .font(.system(size: 10))
                    .opacity(0.5)
                Text(label)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(Theme.accent.opacity(0.12)))
        .help("\(topic.source.label). \(topic.questionDisplay ?? topic.topic)")
    }
}
