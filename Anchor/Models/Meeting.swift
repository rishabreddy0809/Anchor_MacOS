//
//  Meeting.swift
//  Anchor
//
//  The class session being monitored, populated from live Zoom data.
//

import SwiftUI

struct Meeting: Identifiable, Hashable {
    enum Platform: String, Hashable, CaseIterable {
        case zoom = "Zoom"
        case meet = "Google Meet"
        case teams = "Teams"

        var symbolName: String {
            switch self {
            case .zoom: "video.fill"
            case .meet: "person.2.wave.2.fill"
            case .teams: "person.3.fill"
            }
        }
    }

    let id: UUID
    var title: String
    var platform: Platform
    var isLive: Bool
    var startedAt: Date
    var participantCount: Int
    var hostName: String

    var displayName: String { "\(title) (\(platform.rawValue))" }

    init(
        id: UUID = UUID(),
        title: String,
        platform: Platform,
        isLive: Bool,
        startedAt: Date,
        participantCount: Int,
        hostName: String
    ) {
        self.id = id
        self.title = title
        self.platform = platform
        self.isLive = isLive
        self.startedAt = startedAt
        self.participantCount = participantCount
        self.hostName = hostName
    }
}
