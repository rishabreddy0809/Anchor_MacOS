//
//  StudentRow.swift
//  Anchor
//
//  One student line in the dashboard / roster list.
//

import SwiftUI

struct StudentRow: View {
    let student: Student
    let level: RiskLevel
    let now: Date
    var showsChevron: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                RiskDot(level: level, isKnown: student.hasReliableScore)

                VStack(alignment: .leading, spacing: 1) {
                    Text(student.name)
                        .font(Theme.rowNameFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Image(systemName: student.status.symbolName)
                            .font(.system(size: 9))
                        Text(student.statusDescription(now: now))
                            .font(Theme.captionFont)
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    // The academic half of the picture, when there is one:
                    // "2 missing assignments · grades −12%".
                    if let academic = student.academic?.headline {
                        HStack(spacing: 4) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 8))
                            Text(academic)
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Theme.riskElevated)
                        .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                Sparkline(values: student.trend, tint: level.color)
                    .frame(width: 38, height: 18)
                    .opacity(0.9)

                VStack(alignment: .trailing, spacing: -1) {
                    Text(student.scoreDisplay)
                        .font(Theme.scoreFont)
                        .foregroundStyle(student.hasReliableScore ? level.color : Color.secondary)
                    Text("struggle")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 40, alignment: .trailing)
                .help(student.hasReliableScore
                      ? "\(student.scorePercent)% struggle · \(student.scoreSource.label)"
                      : "Not enough signal from Zoom to score this student.")

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(
            "\(student.name), \(student.scorePercent) percent struggle, \(student.statusDescription(now: now))"
        )
    }
}
