//
//  TeacherProfileStore.swift
//  Anchor
//
//  The one thing onboarding asks about the teacher themselves: what to call
//  them. Used to personalize the onboarding finish screen and the Home title.
//

import Combine
import SwiftUI

@MainActor
final class TeacherProfileStore: ObservableObject {

    static let shared = TeacherProfileStore()

    private static let nameKey = "anchor.teacher.name"

    @Published var name: String {
        didSet {
#if DEBUG
            // Screenshot mode swaps in an invented teacher name. It must not
            // reach UserDefaults, or taking a screenshot would silently rename
            // the actual person using this Mac.
            if isDemoName { return }
#endif
            defaults.set(name, forKey: Self.nameKey)
        }
    }

#if DEBUG
    private var isDemoName = false

    /// Shows `value` as the teacher's name without persisting it.
    func applyDemoName(_ value: String) {
        isDemoName = true
        name = value
    }
#endif

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.name = defaults.string(forKey: Self.nameKey) ?? ""
    }

    /// First word only, for a greeting that reads like one rather than a form
    /// field echoed back ("Hi Ms. Rivera", not "Hi Ms. Rivera Thompson").
    var firstName: String? {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return nil }
        return trimmed.components(separatedBy: .whitespaces).first
    }
}
