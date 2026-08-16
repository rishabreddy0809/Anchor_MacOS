//
//  MeetingNotifier.swift
//  Anchor
//
//  Every notification Anchor posts:
//
//  * "You're in a Zoom call — connect Anchor?" with Yes / No actions.
//  * "Rishab is slipping — ask about Question 3", tapped to open that student.
//
//  Both live here rather than in two types because the notification centre has
//  exactly one delegate slot and `setNotificationCategories` replaces the whole
//  set. Two independent notifier objects would silently disable each other's
//  buttons depending on which initialised last — a failure that only shows up on
//  a real device, mid-lesson.
//
//  A singleton for the same reason: `MeetingMonitorCoordinator` and
//  `LiveCoachViewModel` both post, and both must post through the same
//  registration.
//

import Combine
import Foundation
import UserNotifications

@MainActor
final class MeetingNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    static let shared = MeetingNotifier()

    enum Identifier {
        static let category = "ANCHOR_CALL_DETECTED"
        static let connect = "ANCHOR_CONNECT"
        static let decline = "ANCHOR_DECLINE"
        static let request = "anchor.call-detected"

        static let recommendationCategory = "ANCHOR_RECOMMENDATION"
        static let openStudent = "ANCHOR_OPEN_STUDENT"
        /// One request id per student, so a fresher alert about the same student
        /// replaces the older one instead of stacking beneath it.
        static func recommendation(studentID: UUID) -> String {
            "anchor.recommendation.\(studentID.uuidString)"
        }
        static let studentIDKey = "anchor.studentID"
    }

    /// Teacher tapped Yes.
    var onConnect: (() -> Void)?
    /// Teacher tapped No — don't ask again for this call.
    var onDecline: (() -> Void)?
    /// Teacher tapped a recommendation — open that student's detail view.
    var onOpenStudent: ((UUID) -> Void)?

    @Published private(set) var isAuthorized = false

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    // MARK: - Setup

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.isAuthorized = granted }
        }
    }

    private func registerCategories() {
        let call = UNNotificationCategory(
            identifier: Identifier.category,
            actions: [
                UNNotificationAction(
                    identifier: Identifier.connect,
                    title: "Yes",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: Identifier.decline,
                    title: "No",
                    options: []
                )
            ],
            intentIdentifiers: [],
            options: []
        )

        // One action, and it's the same thing tapping the banner body does. The
        // alternatives a teacher actually has here — call on the student, let it
        // ride — happen in the room, not in Notification Center.
        let recommendation = UNNotificationCategory(
            identifier: Identifier.recommendationCategory,
            actions: [
                UNNotificationAction(
                    identifier: Identifier.openStudent,
                    title: "Open",
                    options: [.foreground]
                )
            ],
            intentIdentifiers: [],
            options: []
        )

        // Set together — this call replaces the whole set, so registering them
        // in two calls would leave only the second.
        center.setNotificationCategories([call, recommendation])
    }

    // MARK: - Posting

    /// "Start monitoring Math 101?" / "14 participants" / [Yes] [No]
    func notifyMonitoringPrompt(for meeting: DetectedMeeting) {
        let content = UNMutableNotificationContent()
        content.title = "Start monitoring \(meeting.name)?"
        content.subtitle = meeting.participantSummary
        content.body = "Anchor will send a bot into the meeting to read engagement signals."
        content.categoryIdentifier = Identifier.category
        content.sound = .default

        // Replaces any previous prompt rather than stacking them up.
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.request])
        center.removeDeliveredNotifications(withIdentifiers: [Identifier.request])

        let request = UNNotificationRequest(
            identifier: Identifier.request,
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    /// "Rishab is slipping away" / "Ask about Question 3 (Chlorophyll)" / the reason.
    ///
    /// The student's name goes in the title here even though it never goes to
    /// the model: this is Anchor's own text, addressed to the teacher, on their
    /// own Mac. A banner that didn't say who it was about would be useless.
    func notifyRecommendation(_ recommendation: LiveRecommendation) {
        let content = UNMutableNotificationContent()
        content.title = "\(recommendation.studentName) — \(recommendation.statusSummary)"
        content.subtitle = recommendation.headline
        content.body = recommendation.reason
        content.categoryIdentifier = Identifier.recommendationCategory
        content.userInfo = [Identifier.studentIDKey: recommendation.studentID.uuidString]
        // Deliberately silent. This fires while the teacher is mid-lesson with
        // the class listening, and a notification chime over a live room is the
        // fastest way to have the feature switched off.
        content.sound = nil
        content.interruptionLevel = .active

        let id = Identifier.recommendation(studentID: recommendation.studentID)
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func clear() {
        center.removeDeliveredNotifications(withIdentifiers: [Identifier.request])
    }

    /// Drops every recommendation banner still on screen. For the end of a
    /// meeting: a suggestion about a lesson that has finished is noise.
    func clearRecommendations(studentIDs: [UUID]) {
        let ids = studentIDs.map { Identifier.recommendation(studentID: $0) }
        guard !ids.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let categoryID = response.notification.request.content.categoryIdentifier
        // Read out to a Sendable value here rather than carrying the whole
        // `[AnyHashable: Any]` across the actor hop.
        let studentID = (response.notification.request.content
            .userInfo[Identifier.studentIDKey] as? String)
            .flatMap(UUID.init(uuidString:))

        await MainActor.run {
            // Dispatch on the category first. `UNNotificationDefaultActionIdentifier`
            // means "the banner body was tapped" for *both* kinds, so keying on
            // the action alone would have a tapped recommendation start a Zoom
            // bot join.
            switch categoryID {
            case Identifier.recommendationCategory:
                guard let studentID else { return }
                onOpenStudent?(studentID)

            default:
                switch response.actionIdentifier {
                case Identifier.connect, UNNotificationDefaultActionIdentifier:
                    onConnect?()
                case Identifier.decline:
                    onDecline?()
                default:
                    break
                }
            }
        }
    }
}
