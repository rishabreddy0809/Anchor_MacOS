//
//  ManualRosterLinks.swift
//  Anchor
//
//  Teacher-asserted links between a Zoom participant and a Google Classroom
//  roster entry.
//
//  Anchor refuses to guess an identity, and on a Zoom plan without the Dashboard
//  API there is no address to verify one with — so two students sharing a
//  display name match nobody, and the class loses academic scoring for both.
//  This is the way out that doesn't involve guessing: a human who can see both
//  people says which is which.
//
//  ## What gets remembered, and for how long
//
//  Links are keyed on the identity Zoom gave, and the key decides the lifetime:
//
//  * `email:…` or `name:…` — durable. Written to UserDefaults and reapplied in
//    next week's class, because both survive a new meeting.
//  * `user:…` — session only, held in memory. The Meeting SDK's participant id
//    is unique *within one meeting* and Zoom reuses the numbers, so persisting
//    one would eventually attach a student's grades to a stranger. These are
//    dropped when the meeting ends.
//
//  Only the Classroom student *id* is stored against the key — never a name,
//  never an address, never a grade.
//

import Combine
import Foundation

@MainActor
final class ManualRosterLinks: ObservableObject {

    static let shared = ManualRosterLinks()

    /// courseID → identity key → Classroom student id.
    @Published private(set) var durable: [String: [String: String]] = [:]
    /// The same shape, for meeting-local keys. Never written to disk.
    @Published private(set) var session: [String: [String: String]] = [:]

    /// Pinned by a test; `nil` follows whichever account is signed in.
    private let pinnedDefaults: UserDefaults?
    private var defaults: UserDefaults { pinnedDefaults ?? AccountScope.shared.defaults }
    private var scopeObserver: Any?
    private static let storageKey = "anchor.classroom.manualLinks"

    init(defaults: UserDefaults? = nil) {
        self.pinnedDefaults = defaults
        load()
        scopeObserver = AccountScope.observe { [weak self] in self?.accountDidChange() }
    }

    /// Links name students in one teacher's Classroom courses. Carrying them
    /// across an account switch would map a stranger's roster onto this one.
    private func accountDidChange() {
        guard pinnedDefaults == nil else { return }
        durable = [:]
        session = [:]
        load()
    }

    // MARK: - Lookup

    /// The linked Classroom student id for any of `keys`, most specific first.
    ///
    /// Session links are consulted ahead of durable ones: inside a meeting the
    /// participant id names one particular person, where a name might not.
    func studentID(forKeys keys: [String], course: String) -> String? {
        for key in keys {
            if let id = session[course]?[key] { return id }
        }
        for key in keys {
            if let id = durable[course]?[key] { return id }
        }
        return nil
    }

    /// Every link for a course, flattened into the lookup the match table wants.
    func links(forCourse course: String) -> [String: String] {
        (durable[course] ?? [:]).merging(session[course] ?? [:]) { _, session in session }
    }

    // MARK: - Editing

    /// Records a link. `isDurable` is the caller's call because only it can see
    /// whether another participant in *this* meeting answers to the same name —
    /// where two do, the name key would resolve to both and must not be kept.
    func link(key: String, studentID: String, course: String, isDurable: Bool) {
        if isDurable, key.hasPrefix("email:") || key.hasPrefix("name:") {
            durable[course, default: [:]][key] = studentID
            save()
        } else {
            session[course, default: [:]][key] = studentID
        }
    }

    /// Removes any link stored under any of `keys`, in both scopes.
    func unlink(keys: [String], course: String) {
        for key in keys {
            session[course]?.removeValue(forKey: key)
            durable[course]?.removeValue(forKey: key)
        }
        save()
    }

    /// Drops meeting-local links. Called when a meeting ends — see the note on
    /// recycled participant ids above.
    func clearSession() {
        guard !session.isEmpty else { return }
        session = [:]
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        durable = (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(durable) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
