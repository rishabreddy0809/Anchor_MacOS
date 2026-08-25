//
//  MeetingMonitorCoordinator.swift
//  Anchor
//
//  Owns the join flow end to end:
//
//    local call detection
//      → confirm the teacher is the HOST of a live meeting (REST)
//      → floating panel "Start monitoring [name]?  [X] participants"  [Start] [Not now]
//      → Yes: bot credentials from Keychain → bot OAuth → bot joins → monitoring
//      → No:  dismiss, nothing joins, dashboard sits at "Ready to monitor"
//

import Combine
import Foundation

/// A live meeting the teacher hosts, resolved before we prompt.
nonisolated struct DetectedMeeting: Sendable, Equatable, Identifiable {
    var id: String
    var uuid: String?
    var name: String
    var participantCount: Int

    var participantSummary: String {
        participantCount == 1 ? "1 participant" : "\(participantCount) participants"
    }
}

@MainActor
final class MeetingMonitorCoordinator: ObservableObject {

    enum Phase: Equatable {
        case idle
        /// Call detected locally; checking whether the teacher hosts it.
        case resolving
        /// Prompt shown, waiting on Yes/No.
        case awaitingConsent(DetectedMeeting)
        /// Teacher said no — stay out of the way until the call ends.
        case declined(DetectedMeeting)
        case joining(DetectedMeeting)
        case monitoring(DetectedMeeting)
        case failed(String)

        var isMonitoring: Bool {
            if case .monitoring = self { return true }
            return false
        }
    }

    @Published private(set) var phase: Phase = .idle
    /// Transient "Bot joined" style confirmation for the UI.
    @Published private(set) var confirmation: String?

    static let shared = MeetingMonitorCoordinator(zoom: .shared, store: .shared)

    private let zoom: ZoomViewModel
    private let store: EngagementStore
    private let detector = CallDetector()
    /// Shared, not owned: LiveCoachViewModel posts recommendation banners
    /// through the same object. See MeetingNotifier.
    private let notifier = MeetingNotifier.shared
    /// The consent prompt itself. Notifications are still used for the
    /// mid-class recommendation banners — this replaces only the one prompt
    /// that has to be answered before anything can happen.
    private let consentPanel = MeetingConsentPanelController.shared

    init(zoom: ZoomViewModel, store: EngagementStore) {
        self.zoom = zoom
        self.store = store
        wire()
    }

    // MARK: - Lifecycle

    func start() {
        notifier.requestAuthorization()
        detector.start()
    }

    func stop() {
        detector.stop()
        notifier.clear()
    }

    private func wire() {
        detector.onCallStarted = { [weak self] in
            Task { await self?.handleCallStarted() }
        }
        detector.onCallEnded = { [weak self] in
            Task { await self?.handleCallEnded() }
        }
        notifier.onConnect = { [weak self] in
            Task { await self?.acceptMonitoring() }
        }
        notifier.onDecline = { [weak self] in
            self?.declineMonitoring()
        }
    }

    // MARK: - Detection

    private func handleCallStarted() async {
        // Don't re-prompt for a call we're already on, or one already refused.
        switch phase {
        case .awaitingConsent, .joining, .monitoring, .declined:
            return
        case .idle, .resolving, .failed:
            break
        }

        phase = .resolving

        // Requirement: only prompt when the teacher is the host. A meeting they
        // merely joined is invisible to the REST API, so staying quiet is the
        // correct outcome rather than guessing — but say *which* reason applies,
        // because they are fixed in completely different places.
        switch await resolveHostedMeeting() {
        case .found(let meeting):
            phase = .awaitingConsent(meeting)
            // A floating panel rather than a notification. The teacher is about
            // to teach, so a Focus is very likely on and a banner would be
            // suppressed silently — and if they ever declined notification
            // permission, the prompt had nowhere to go at all. See
            // MeetingConsentPanel for the rest of the reasoning.
            consentPanel.present(
                meeting: meeting,
                onAccept: { [weak self] in Task { await self?.acceptMonitoring() } },
                onDecline: { [weak self] in self?.declineMonitoring() }
            )

        case .noCredentials:
            phase = .idle
            store.setConnectionSummary(
                "In a Zoom call, but Anchor has no Zoom credentials — add them in Settings."
            )

        case .noLiveMeeting(let account):
            phase = .idle
            store.setConnectionSummary(
                account.map {
                    "In a Zoom call, but Zoom reports no live meeting hosted by \($0). "
                    + "Either you are not the host, or your Zoom app is signed into a "
                    + "different account than the credentials in Settings."
                } ?? "In a Zoom call, but you are not the host — Anchor only monitors meetings you host."
            )

        case .failed(let error):
            // Previously a `try?` swallowed this, so an expired secret, a
            // missing scope or a disabled app all surfaced as "you are not the
            // host" — which sends you looking in exactly the wrong place.
            phase = .failed(error.errorDescription ?? "Could not reach Zoom.")
            store.setConnectionSummary(
                [error.errorDescription, error.recoverySuggestion]
                    .compactMap { $0 }
                    .joined(separator: " ")
            )
        }
    }

    private func handleCallEnded() async {
        consentPanel.dismiss()
        notifier.clear()
        if phase.isMonitoring {
            await zoom.leaveBot()
            zoom.stop()
        }
        phase = .idle
        confirmation = nil
    }

    /// Why no meeting was resolved. "Not the host" and "Zoom rejected the
    /// credentials" are indistinguishable to the user but need opposite fixes,
    /// so they stay separate all the way to the status line.
    private enum HostLookup {
        case found(DetectedMeeting)
        case noCredentials
        /// Authenticated fine; Zoom just has no live meeting for this account.
        case noLiveMeeting(account: String?)
        case failed(ZoomError)
    }

    /// Asks Zoom for a live meeting this account hosts, with its name and
    /// participant count.
    private func resolveHostedMeeting() async -> HostLookup {
        guard ZoomViewModel.hasAnyZoomCredential else { return .noCredentials }

        let meetings: [ZoomMeeting]
        do {
            meetings = try await zoom.hostedLiveMeetings()
        } catch let error as ZoomError {
            return .failed(error)
        } catch {
            return .failed(.network(error.localizedDescription))
        }

        guard let first = meetings.first else {
            // Naming the account is the whole point: an empty list almost always
            // means the Zoom desktop client is signed in as somebody else.
            // `account` is only populated by a successful sync, so resolve it
            // here — one extra call, on a path that means "nothing to do".
            var account = zoom.account?.email ?? zoom.account?.displayName
            if account == nil, case .success(let info) = await zoom.testConnection() {
                account = info.email ?? info.displayName
            }
            return .noLiveMeeting(account: account)
        }

        return .found(
            DetectedMeeting(
                id: first.id,
                uuid: first.uuid,
                name: first.topic,
                participantCount: first.participantCount
            )
        )
    }

    // MARK: - Yes / No

    func acceptMonitoring() async {
        guard case .awaitingConsent(let meeting) = phase else { return }

        consentPanel.dismiss()
        phase = .joining(meeting)
        confirmation = nil
        store.setConnectionSummary("Sending the bot into \(meeting.name)…")

        let joined = await zoom.joinBotUsingStoredCredentials(
            meetingNumber: meeting.id,
            passcode: nil
        )

        switch joined {
        case .success:
            phase = .monitoring(meeting)
            confirmation = "Bot joined \(meeting.name)"
            zoom.start()
        case .failure(let error):
            phase = .failed(error.errorDescription ?? "The bot could not join.")
            confirmation = nil
        }
    }

    func declineMonitoring() {
        guard case .awaitingConsent(let meeting) = phase else { return }
        // Requirement: nothing else happens. No join, no polling, no data.
        phase = .declined(meeting)
        confirmation = nil
        consentPanel.dismiss()
        notifier.clear()
        store.setConnectionSummary("Ready to monitor — Anchor is not watching this meeting.")
    }

    /// Lets the teacher opt in later from the UI after declining.
    func promptAgain() async {
        if case .declined = phase { phase = .idle }
        await handleCallStarted()
    }

    func stopMonitoring() async {
        await zoom.leaveBot()
        zoom.stop()
        phase = .idle
        confirmation = nil
    }

    // MARK: - Display

    /// Header text: "🟢 Monitoring Math 101"
    var headerStatus: String? {
        switch phase {
        case .monitoring(let meeting): "🟢 Monitoring \(meeting.name)"
        case .joining(let meeting): "Joining \(meeting.name)…"
        case .awaitingConsent(let meeting): "Waiting on you — \(meeting.name)"
        case .declined: "Ready to monitor"
        case .failed(let message): "⚠️ \(message)"
        case .resolving: "Checking meeting…"
        case .idle: nil
        }
    }
}
