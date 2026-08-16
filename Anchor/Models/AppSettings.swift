//
//  AppSettings.swift
//  Anchor
//
//  User-tunable monitoring preferences.
//

import Foundation

struct AppSettings: Equatable {
    enum RefreshInterval: Int, CaseIterable, Identifiable {
        case tenSeconds = 10
        case thirtySeconds = 30
        case oneMinute = 60
        case twoMinutes = 120
        case fiveMinutes = 300

        var id: Int { rawValue }
        var seconds: TimeInterval { TimeInterval(rawValue) }

        var label: String {
            switch self {
            case .tenSeconds: "10 seconds"
            case .thirtySeconds: "30 seconds"
            case .oneMinute: "1 minute"
            case .twoMinutes: "2 minutes"
            case .fiveMinutes: "5 minutes"
            }
        }

        /// Only the bot can actually deliver this cadence — Zoom's Dashboard
        /// REST endpoints are heavy rate-limited and are held to
        /// `ZoomConfig.minimumPollInterval` regardless of this setting.
        var needsBot: Bool { seconds < ZoomConfig.minimumPollInterval }
    }

    /// Nil until a live meeting is ingested — Anchor has no meetings of its own.
    var selectedMeetingID: UUID?
    var sensitivity: Double = 0.5          // 0 = conservative, 1 = eager
    var refreshInterval: RefreshInterval = .tenSeconds
    var notifyOnHighRisk: Bool = true
    var showsBadge: Bool = true
    var includesCameraSignal: Bool = true

    var sensitivityLabel: String {
        switch sensitivity {
        case ..<0.25: "Conservative"
        case ..<0.45: "Relaxed"
        case ..<0.65: "Balanced"
        case ..<0.85: "Alert"
        default: "Very alert"
        }
    }
}
