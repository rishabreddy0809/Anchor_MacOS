//
//  RiskLevel.swift
//  Anchor
//
//  Classification of a struggle score into a traffic-light band.
//

import SwiftUI

enum RiskLevel: String, CaseIterable, Identifiable, Hashable {
    case low
    case elevated
    case high

    var id: String { rawValue }

    /// Base cut-offs used at the default sensitivity (0.5):
    /// red above 70%, amber 40–70%, green below 40%.
    static let defaultHighThreshold = 0.70
    static let defaultElevatedThreshold = 0.40

    /// Sensitivity shifts both cut-offs by up to ±0.15.
    /// Higher sensitivity flags students earlier.
    static func highThreshold(sensitivity: Double) -> Double {
        defaultHighThreshold + 0.15 - (0.30 * sensitivity)
    }

    static func elevatedThreshold(sensitivity: Double) -> Double {
        defaultElevatedThreshold + 0.15 - (0.30 * sensitivity)
    }

    static func level(for score: Double, sensitivity: Double = 0.5) -> RiskLevel {
        if score >= highThreshold(sensitivity: sensitivity) { return .high }
        if score >= elevatedThreshold(sensitivity: sensitivity) { return .elevated }
        return .low
    }

    var color: Color {
        switch self {
        case .high: Theme.riskHigh
        case .elevated: Theme.riskElevated
        case .low: Theme.riskLow
        }
    }

    var label: String {
        switch self {
        case .high: "Needs attention"
        case .elevated: "Watch"
        case .low: "Engaged"
        }
    }

    var shortLabel: String {
        switch self {
        case .high: "High"
        case .elevated: "Medium"
        case .low: "Low"
        }
    }

    var symbolName: String {
        switch self {
        case .high: "exclamationmark.triangle.fill"
        case .elevated: "eye.fill"
        case .low: "checkmark.circle.fill"
        }
    }

    /// Sort weight so high risk floats to the top.
    var rank: Int {
        switch self {
        case .high: 0
        case .elevated: 1
        case .low: 2
        }
    }
}
