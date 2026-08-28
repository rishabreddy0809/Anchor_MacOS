//
//  CourseThemes.swift
//  Anchor
//
//  Which colour each course card wears.
//
//  This exists because Google won't tell us. The Classroom API's `Course`
//  resource carries no theme, banner or even theme *colour* field — the
//  pea-pod header a teacher sees on classroom.google.com lives only in the web
//  app, and is neither readable nor writable through the API. So the card's
//  colour was a hash of the course id: stable, distinct, and matching the real
//  class only by luck.
//
//  A teacher picking it once is the only way the tile can actually look like
//  their class. The hash stays as the default, so a teacher who never opens the
//  picker sees exactly what they saw before.
//
//  Only a colour name per course id is stored, in UserDefaults, next to
//  `anchor.classroom.monitoredCourseIDs`. No student data, and nothing that
//  matters if it is lost.
//

import Combine
import SwiftUI

// MARK: - Theme

/// The colours Google Classroom's own stock themes are built around.
///
/// Named rather than stored as RGB so the palette can be retuned later without
/// silently repainting every teacher's saved choice.
enum CourseTheme: String, CaseIterable, Identifiable, Sendable {
    case blue
    case purple
    case green
    case amber
    case crimson
    case teal
    case indigo
    case brown

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: Color(red: 0.16, green: 0.50, blue: 0.73)
        case .purple: Color(red: 0.42, green: 0.24, blue: 0.60)
        case .green: Color(red: 0.11, green: 0.53, blue: 0.36)
        case .amber: Color(red: 0.78, green: 0.42, blue: 0.11)
        case .crimson: Color(red: 0.67, green: 0.18, blue: 0.31)
        case .teal: Color(red: 0.13, green: 0.45, blue: 0.51)
        case .indigo: Color(red: 0.35, green: 0.38, blue: 0.68)
        case .brown: Color(red: 0.55, green: 0.30, blue: 0.16)
        }
    }

    /// For the picker's accessibility label and its tooltip.
    var label: String { rawValue.capitalized }

    /// The colour a course gets before anyone chooses one.
    ///
    /// FNV-1a over the id's UTF-8 bytes rather than `hashValue`: Swift seeds its
    /// hasher per process, which would repaint every card on every launch.
    static func fallback(forCourseID id: String) -> CourseTheme {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let all = allCases
        return all[Int(hash % UInt64(all.count))]
    }
}

// MARK: - Store

/// Remembers the teacher's per-course choice.
@MainActor
final class CourseThemes: ObservableObject {

    static let shared = CourseThemes()

    private static let keyPrefix = "anchor.classroom.theme."

    /// Mirrored in memory so the cards don't hit UserDefaults on every redraw —
    /// Home rebuilds the whole grid on each Classroom publish.
    @Published private var chosen: [String: CourseTheme] = [:]

    /// Pinned by a test; `nil` follows whichever account is signed in.
    private let pinnedDefaults: UserDefaults?
    private var defaults: UserDefaults { pinnedDefaults ?? AccountScope.shared.defaults }
    private var scopeObserver: Any?

    init(defaults: UserDefaults? = nil) {
        self.pinnedDefaults = defaults
        scopeObserver = AccountScope.observe { [weak self] in self?.accountDidChange() }
    }

    /// Drops the in-memory mirror so the next read faults in the new account's
    /// colours. Nothing is written: the previous teacher's picks stay in their
    /// own suite, waiting for them.
    private func accountDidChange() {
        guard pinnedDefaults == nil, !chosen.isEmpty else { return }
        chosen = [:]
    }

    /// The course's colour: the teacher's pick, or the id-derived default.
    func theme(forCourseID id: String) -> CourseTheme {
        if let chosen = chosen[id] { return chosen }

        // First read for this course — fault it in from disk once, then serve
        // from memory.
        if let raw = defaults.string(forKey: Self.key(id)),
           let stored = CourseTheme(rawValue: raw) {
            chosen[id] = stored
            return stored
        }
        return CourseTheme.fallback(forCourseID: id)
    }

    func setTheme(_ theme: CourseTheme, forCourseID id: String) {
        guard chosen[id] != theme else { return }
        chosen[id] = theme
        defaults.set(theme.rawValue, forKey: Self.key(id))
    }

    /// Back to the id-derived colour.
    func resetTheme(forCourseID id: String) {
        chosen[id] = nil
        defaults.removeObject(forKey: Self.key(id))
        // The in-memory map can't represent "explicitly unset" — `theme(for:)`
        // would fault the deleted key straight back in as nil and fall through
        // to the default, which is what we want — but the published change has
        // to fire for the card to repaint.
        objectWillChange.send()
    }

    func hasCustomTheme(forCourseID id: String) -> Bool {
        defaults.string(forKey: Self.key(id)) != nil
    }

    private static func key(_ courseID: String) -> String { keyPrefix + courseID }
}
