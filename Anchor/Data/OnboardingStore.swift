//
//  OnboardingStore.swift
//  Anchor
//
//  Whether the first-launch onboarding flow has been completed.
//
//  Two flags rather than one: `hasCompletedOnboarding` is the durable record,
//  written to UserDefaults; `isPresented` is transient and drives the sheet
//  directly, so replaying onboarding from Settings doesn't need to touch the
//  completion record until the teacher actually finishes it again.
//

import Combine
import SwiftUI

@MainActor
final class OnboardingStore: ObservableObject {

    static let shared = OnboardingStore()

    private static let completedKey = "anchor.onboarding.completed"

    @Published private(set) var hasCompletedOnboarding: Bool
    @Published var isPresented = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Self.completedKey)
    }

    /// Called once, from the main window's `onAppear`.
    func presentIfNeeded() {
        guard !hasCompletedOnboarding else { return }
        isPresented = true
    }

    /// Reached by finishing the flow or by Skip — both mean the teacher has
    /// seen it and it shouldn't come back on its own.
    func finish() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Self.completedKey)
        isPresented = false
    }

    /// "Show onboarding again" in Settings. Doesn't clear the completion
    /// record until the teacher reaches the end again, so dismissing this
    /// replay early doesn't resurrect it on next launch.
    func replay() {
        isPresented = true
    }
}
