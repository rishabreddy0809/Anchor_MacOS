//
//  ClassOverviewView.swift
//  Anchor
//
//  Default right-hand pane: how the whole class is doing, and who to look at
//  first. Selecting anyone here opens their detail.
//

import SwiftUI

struct ClassOverviewView: View {
    @EnvironmentObject private var store: EngagementStore
    /// Opens a student in the detail pane.
    let onSelect: (UUID) -> Void

    var body: some View {
        if store.hasData {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    statCards
                    needsAttention
                    classProfile
                }
                .padding(22)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        } else {
            EmptyStateView(isCompact: false)
        }
    }

    // MARK: - Stat cards

    private var statCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Class overview")
                .font(.system(size: 18, weight: .semibold))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                spacing: 10
            ) {
                StatCard(
                    value: "\(Int((store.classAverageScore * 100).rounded()))%",
                    label: "Class average",
                    symbolName: "speedometer",
                    tint: RiskLevel.level(
                        for: store.classAverageScore,
                        sensitivity: store.settings.sensitivity
                    ).color
                )
                StatCard(
                    value: "\(store.highRiskCount)",
                    label: "Need attention",
                    symbolName: "exclamationmark.triangle.fill",
                    tint: Theme.riskHigh
                )
                StatCard(
                    value: "\(store.elevatedCount)",
                    label: "Worth watching",
                    symbolName: "eye.fill",
                    tint: Theme.riskElevated
                )
                StatCard(
                    value: "\(store.engagedCount)",
                    label: "Engaged",
                    symbolName: "checkmark.circle.fill",
                    tint: Theme.riskLow
                )
            }
        }
    }

    // MARK: - Needs attention

    private var needsAttention: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Needs attention first", trailingText: "Click to open a student")

            VStack(spacing: 1) {
                ForEach(store.topStudents) { student in
                    StudentRow(
                        student: student,
                        level: store.risk(for: student),
                        now: store.now
                    ) {
                        onSelect(student.id)
                    }
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }

    // MARK: - Whole-class profile

    private var classProfile: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(
                text: "Struggle profile",
                trailingText: "All \(store.students.count) students"
            )

            VStack(spacing: 7) {
                ForEach(store.rankedStudents) { student in
                    let level = store.risk(for: student)
                    Button {
                        onSelect(student.id)
                    } label: {
                        HStack(spacing: 10) {
                            Text(student.name)
                                .font(.system(size: 11))
                                .frame(width: 130, alignment: .leading)
                                .lineLimit(1)

                            ProgressView(value: student.hasReliableScore ? student.struggleScore : 0)
                                .progressViewStyle(.linear)
                                .tint(student.hasReliableScore ? level.color : Color.secondary)
                                .opacity(student.hasReliableScore ? 1 : 0.4)

                            Text(student.scoreDisplay)
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(student.hasReliableScore ? level.color : Color.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(RowButtonStyle(cornerRadius: 6))
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }
}

// MARK: - Stat card

private struct StatCard: View {
    let value: String
    let label: String
    let symbolName: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 24, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}
