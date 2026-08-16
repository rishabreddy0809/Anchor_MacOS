//
//  ActivityEvent.swift
//  Anchor
//
//  A single observed signal on the meeting timeline.
//

import SwiftUI

struct ActivityEvent: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case joined
        case spoke
        case chat
        case reaction
        case cameraOn
        case cameraOff
        case muted
        case unmuted
        case idle
        case poll
        case question
        case breakout

        var symbolName: String {
            switch self {
            case .joined: "person.fill.badge.plus"
            case .spoke: "waveform"
            case .chat: "bubble.left.fill"
            case .reaction: "hand.thumbsup.fill"
            case .cameraOn: "video.fill"
            case .cameraOff: "video.slash.fill"
            case .muted: "mic.slash.fill"
            case .unmuted: "mic.fill"
            case .idle: "moon.zzz.fill"
            case .poll: "chart.bar.fill"
            case .question: "questionmark.circle.fill"
            case .breakout: "rectangle.3.group.fill"
            }
        }

        /// Positive signals read green, negative signals read amber/red.
        var tint: Color {
            switch self {
            case .spoke, .chat, .reaction, .cameraOn, .unmuted, .poll, .question, .joined:
                Theme.riskLow
            case .cameraOff, .muted, .breakout:
                Theme.riskElevated
            case .idle:
                Theme.riskHigh
            }
        }
    }

    let id: UUID
    var kind: Kind
    var title: String
    var detail: String?
    var timestamp: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        detail: String? = nil,
        timestamp: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
    }
}
