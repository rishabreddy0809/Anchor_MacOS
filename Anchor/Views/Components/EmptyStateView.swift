//
//  EmptyStateView.swift
//  Anchor
//
//  What the dashboard shows when Zoom has not delivered a roster. Anchor has no
//  fallback data, so this is the honest resting state — and it explains what to
//  do rather than just showing a blank pane.
//

import AppKit
import SwiftUI

struct EmptyStateView: View {
    @EnvironmentObject private var store: EngagementStore
    @EnvironmentObject private var zoom: ZoomViewModel
    @ObservedObject private var monitor = MeetingMonitorCoordinator.shared

    /// Larger presentation for the main window; compact for the popover.
    var isCompact = true
    var onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(spacing: isCompact ? 8 : 12) {
            Image(systemName: state.symbolName)
                .font(.system(size: isCompact ? 26 : 38, weight: .light))
                .foregroundStyle(state.tint)

            Text(state.title)
                .font(.system(size: isCompact ? 13 : 17, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(state.message)
                .font(.system(size: isCompact ? 11 : 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: isCompact ? 280 : 400)

            if let action = state.action {
                Button(action.title) { action.perform() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(isCompact ? 18 : 32)
    }

    // MARK: - State

    private struct Action {
        var title: String
        var perform: () -> Void
    }

    private struct Presentation {
        var symbolName: String
        var title: String
        var message: String
        var tint: Color
        var action: Action?
    }

    private var state: Presentation {
        // The join flow's own states take priority — they're the most specific
        // thing we can tell the teacher.
        switch monitor.phase {
        case .awaitingConsent(let meeting):
            return Presentation(
                symbolName: "bell.badge",
                title: "Start monitoring \(meeting.name)?",
                message: "\(meeting.participantSummary) · Answer the notification, or choose here.",
                tint: Theme.riskElevated,
                action: Action(title: "Yes, monitor") {
                    Task { await monitor.acceptMonitoring() }
                }
            )

        case .joining(let meeting):
            return Presentation(
                symbolName: "arrow.triangle.2.circlepath",
                title: "Joining \(meeting.name)…",
                message: "The bot is signing in to Zoom.",
                tint: Theme.riskElevated,
                action: nil
            )

        case .declined(let meeting):
            return Presentation(
                symbolName: "checkmark.circle",
                title: "Ready to monitor",
                message: "Anchor is not watching \(meeting.name). Nothing has joined the meeting.",
                tint: .secondary,
                action: Action(title: "Monitor this meeting") {
                    Task { await monitor.promptAgain() }
                }
            )

        case .failed(let message):
            return Presentation(
                symbolName: "exclamationmark.triangle",
                title: "The bot couldn't join",
                message: message,
                tint: Theme.riskHigh,
                action: Action(title: "Try again") {
                    Task { await monitor.promptAgain() }
                }
            )

        case .idle, .resolving, .monitoring:
            break
        }

        if !ZoomViewModel.hasTeacherZoomConnection {
            return Presentation(
                symbolName: "key.slash",
                title: "Connect Zoom",
                message: "Sign in with your Zoom account in Settings — Anchor opens Zoom in your browser and can read a class once you're back.",
                tint: .secondary,
                action: onOpenSettings.map { Action(title: "Open Settings", perform: $0) }
            )
        }

        switch zoom.state {
        case .connecting:
            return Presentation(
                symbolName: "arrow.triangle.2.circlepath",
                title: "Connecting to Zoom…",
                message: "Checking for a live meeting.",
                tint: Theme.riskElevated,
                action: nil
            )

        case .waitingForMeeting:
            return Presentation(
                symbolName: "clock",
                title: "Waiting for a meeting",
                message: "Anchor is connected but no live meeting was found on this account. "
                    + "Start your class, or join one and accept the notification so Anchor can send a bot in.",
                tint: Theme.riskElevated,
                action: nil
            )

        case .failed(let error):
            let message = [error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")

            // "Try again" is the wrong offer for a setup problem: retrying a
            // missing scope or an unconfigured client fails identically every
            // time, so the button trains the teacher that Anchor is simply
            // broken. Where they cannot fix it, hand them the one action that
            // can — reaching the person who can.
            return Presentation(
                symbolName: "exclamationmark.triangle",
                title: error.isSetupProblem ? "Anchor isn't set up for Zoom yet" : "Zoom disconnected",
                message: message,
                tint: Theme.riskHigh,
                action: error.isSetupProblem
                    ? Action(title: "Email support") {
                        let url = SupportContact.reportURL(
                            summary: error.errorDescription ?? "Zoom setup problem",
                            detail: error.technicalDetail
                        ) ?? URL(string: "mailto:\(SupportContact.email)")
                        if let url { NSWorkspace.shared.open(url) }
                    }
                    : Action(title: "Try again") { zoom.start() }
            )

        case .retrying(let after, _):
            return Presentation(
                symbolName: "arrow.triangle.2.circlepath",
                title: "Reconnecting…",
                message: "Anchor will retry in about \(Int(after)) seconds.",
                tint: Theme.riskElevated,
                action: nil
            )

        case .connected:
            // Connected to a meeting that currently has nobody in it.
            return Presentation(
                symbolName: "person.2.slash",
                title: "No participants yet",
                message: "\(store.meetingTitle) is live, but no one has joined.",
                tint: .secondary,
                action: nil
            )

        case .idle:
            return Presentation(
                symbolName: "antenna.radiowaves.left.and.right.slash",
                title: "Not connected",
                message: "Anchor is not monitoring a meeting. Connect to Zoom to start reading engagement signals.",
                tint: .secondary,
                action: Action(title: "Connect") { zoom.start() }
            )
        }
    }
}
