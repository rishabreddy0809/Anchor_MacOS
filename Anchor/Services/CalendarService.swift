//
//  CalendarService.swift
//  Anchor
//
//  The teacher's own calendar, read through EventKit.
//
//  ── Why EventKit rather than the Google Calendar API ────────────────────────
//
//  Anchor already signs teachers in with Google, so asking Google for their
//  calendar looks like the obvious route. It is the expensive one.
//  `calendar.readonly` is a *sensitive* scope: adding it puts Anchor back into
//  Google's verification review and re-imposes the 100-user cap, undoing what
//  dropping `classroom.profile.emails` on 2026-08-17 bought — and adding any
//  scope invalidates every Classroom grant already given, so every teacher
//  would have to re-consent.
//
//  EventKit costs none of that, and on a Mac signed into a Google account it
//  usually returns *the same calendar*: macOS syncs Google Calendar into the
//  system store. So the local read gets the Google data for free, and the one
//  thing it genuinely cannot reach is Google Tasks, which does not sync to
//  Reminders. That is the only piece a sensitive scope would actually buy.
//
//  ── What this reads, and what it must never do with it ──────────────────────
//
//  Event titles are the teacher's own personal data and frequently other
//  people's — "Dentist", a colleague's name, a student's name in a 1:1. They
//  are shown to the teacher on their own Mac and go nowhere else:
//
//    * never logged, not even at `.private` — `ReleaseHygieneTests` exists
//      because a course name reaching the unified log was judged a real risk,
//      and a personal calendar is a larger one
//    * never sent to any model, local or hosted
//    * never written to the session archive
//    * never leave the Mac
//
//  Which calendars are read is the teacher's choice, defaulting to none
//  selected: a teaching dashboard that silently lists someone's private
//  appointments is worse than one that lists nothing.
//

import Combine
import EventKit
import Foundation

/// One event, reduced to what the dashboard shows.
///
/// Deliberately not `EKEvent`: that type is a live handle to the store, and
/// passing it into SwiftUI would make every view that shows a schedule depend
/// on EventKit — and on the store still being authorized when the view
/// re-renders.
nonisolated struct ScheduledClass: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var calendarName: String

    /// True when `now` falls inside the event.
    func isHappening(at now: Date = Date()) -> Bool {
        now >= start && now < end
    }

    /// "10:00 – 10:50", in the teacher's own locale and clock convention.
    var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    /// Minutes until it starts; negative once it has.
    func minutesUntilStart(from now: Date = Date()) -> Int {
        Int(start.timeIntervalSince(now) / 60)
    }
}

@MainActor
final class CalendarService: ObservableObject {

    static let shared = CalendarService()

    enum Access: Equatable {
        case notDetermined
        case denied
        case granted
    }

    @Published private(set) var access: Access = .notDetermined
    /// Today's events from the selected calendars, earliest first.
    @Published private(set) var today: [ScheduledClass] = []
    /// Every calendar EventKit can see, for the picker in Settings.
    @Published private(set) var availableCalendars: [(id: String, title: String)] = []

    /// Why the last access request produced nothing, in a teacher's words.
    ///
    /// Exists because the failure it describes is invisible otherwise. The
    /// request used to be `try?`, which turns every error into `false`, and
    /// `false` is indistinguishable from "the teacher said no" — so a request
    /// that never reached a prompt left the button looking broken and the card
    /// unchanged. A permission flow that can fail silently will, and the person
    /// it fails for is the one who cannot read the console.
    @Published private(set) var lastAccessFailure: String?

    /// Which calendars the teacher chose. Empty means none — see the file
    /// comment for why that is the default rather than "all".
    @Published var selectedCalendarIDs: Set<String> {
        didSet {
            defaults.set(Array(selectedCalendarIDs), forKey: Self.selectionKey)
            Task { await refresh() }
        }
    }

    private static let selectionKey = "anchor.calendar.selectedIdentifiers"

    private let store = EKEventStore()
    /// Pinned by a test; `nil` follows whichever account is signed in.
    private let pinnedDefaults: UserDefaults?
    private var defaults: UserDefaults { pinnedDefaults ?? AccountScope.shared.defaults }
    private var scopeObserver: Any?

    init(defaults: UserDefaults? = nil) {
        self.pinnedDefaults = defaults
        let stored = (defaults ?? AccountScope.shared.defaults)
            .stringArray(forKey: Self.selectionKey) ?? []
        self.selectedCalendarIDs = Set(stored)
        self.access = Self.currentAccess()
        scopeObserver = AccountScope.observe { [weak self] in self?.accountDidChange() }
    }

    /// Which calendars hold a teacher's classes is their answer, not the Mac's.
    /// The assignment's own `didSet` refreshes the schedule.
    private func accountDidChange() {
        guard pinnedDefaults == nil else { return }
        selectedCalendarIDs = Set(defaults.stringArray(forKey: Self.selectionKey) ?? [])
    }

    // MARK: - Authorization

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .denied, .restricted: .denied
        // `.writeOnly` can read nothing, so for Anchor's purposes it is a
        // refusal rather than a partial grant — treating it as granted would
        // show a permanently empty schedule with no explanation.
        case .writeOnly: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    /// Prompts for calendar access, then loads what was granted.
    ///
    /// Full access, not write-only: Anchor only ever reads, and EventKit has no
    /// read-only level — write-only is for apps that add events without seeing
    /// existing ones, which is the opposite of this.
    func requestAccess() async {
        guard access != .granted else {
            await refresh()
            return
        }

        lastAccessFailure = nil

        do {
            let granted = try await store.requestFullAccessToEvents()
            access = granted ? .granted : Self.currentAccess()

            // A refusal macOS did not record is not a refusal. Declining the
            // prompt writes `.denied`, so still being `.notDetermined` after a
            // completed request means no prompt was ever shown — which is a
            // different problem with a different fix, and the teacher is
            // entitled to know which one they have.
            if !granted, access == .notDetermined {
                lastAccessFailure = "macOS did not show the calendar permission prompt."
            }
        } catch {
            access = Self.currentAccess()
            lastAccessFailure = error.localizedDescription
            AnchorDiag.log("Calendar access request failed: \(error)")
        }

        if access == .granted { await refresh() }
    }

    // MARK: - Reading

    func refresh(now: Date = Date()) async {
        guard access == .granted else {
            today = []
            availableCalendars = []
            return
        }

        let calendars = store.calendars(for: .event)
        availableCalendars = calendars
            .map { (id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let chosen = calendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else {
            today = []
            return
        }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }

        let predicate = store.predicateForEvents(
            withStart: dayStart,
            end: dayEnd,
            calendars: chosen
        )

        today = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .compactMap(Self.scheduled(from:))
            .sorted { $0.start < $1.start }
    }

    /// Maps an `EKEvent`, dropping anything without the two fields the
    /// dashboard needs. An untitled event is kept and labelled rather than
    /// discarded — a teacher who sees a gap where a real block sits would
    /// reasonably conclude the whole feature is broken.
    private static func scheduled(from event: EKEvent) -> ScheduledClass? {
        guard let start = event.startDate, let end = event.endDate else { return nil }
        let title = event.title?.trimmed
        return ScheduledClass(
            id: event.eventIdentifier ?? "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)",
            title: (title?.isEmpty == false ? title! : "Untitled event"),
            start: start,
            end: end,
            calendarName: event.calendar?.title ?? ""
        )
    }

    // MARK: - Derived

    /// What is running right now, if anything.
    func current(at now: Date = Date()) -> ScheduledClass? {
        today.first { $0.isHappening(at: now) }
    }

    /// The next thing that has not started yet.
    func next(at now: Date = Date()) -> ScheduledClass? {
        today.first { $0.start > now }
    }

    /// True once the teacher has both granted access and chosen a calendar.
    /// Either half missing means the schedule card has nothing to show and
    /// should say which half is missing rather than sitting blank.
    var isConfigured: Bool { access == .granted && !selectedCalendarIDs.isEmpty }
}
