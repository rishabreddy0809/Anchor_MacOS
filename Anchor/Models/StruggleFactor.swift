//
//  StruggleFactor.swift
//  Anchor
//
//  One reason the model scored a student the way it did.
//
//  Produced by StruggleDetectionService.factors(for:), which measures each
//  feature's contribution against the loaded model rather than asserting it.
//

import Foundation

nonisolated struct StruggleFactor: Identifiable, Hashable, Sendable {

    /// How much this signal is holding the score up, in the teacher's language.
    enum Weight: String, Hashable, Sendable, Comparable {
        case high
        case medium
        case low

        /// Cut-offs in struggle-probability points. Below the `low` floor a
        /// feature is noise and is not shown at all.
        init?(impact: Double) {
            switch impact {
            case 0.12...:    self = .high
            case 0.05..<0.12: self = .medium
            case 0.015..<0.05: self = .low
            default:          return nil
            }
        }

        var label: String {
            switch self {
            case .high: "high weight"
            case .medium: "medium weight"
            case .low: "low weight"
            }
        }

        var rank: Int {
            switch self {
            case .high: 0
            case .medium: 1
            case .low: 2
            }
        }

        static func < (lhs: Weight, rhs: Weight) -> Bool { lhs.rank < rhs.rank }
    }

    let feature: StruggleFeature
    var title: String
    var weight: Weight
    /// Struggle probability points attributable to this feature, 0...1.
    var impact: Double

    var id: String { feature.rawValue }

    /// e.g. "Camera off (medium weight)"
    var display: String { "\(title) (\(weight.label))" }

    /// Percentage points, for the detail view.
    var impactPoints: Int { Int((impact * 100).rounded()) }
}
