//
//  AccountGateTests.swift
//  AnchorTests
//
//  Pins "no account, no app", and the one case that must NOT be gated.
//
//  An Anchor account is what a subscription attaches to, so a copy nobody has
//  signed into is a copy nobody is paying for. Enforced on the window —
//  `SignedOutGate` replaces the tabs — rather than in onboarding, because
//  `hasCompletedOnboarding` is durable: a teacher who signed in on Monday and
//  signed out on Friday never sees the walkthrough again and would otherwise
//  keep the whole app.
//
//  **The case worth a test is the dormant one.** `isConfigured` is false when
//  FirebaseAuth is absent or `GoogleService-Info.plist` is missing, and in that
//  state no teacher can create an account however much they want to. Gating
//  there protects no subscription; it makes the app unopenable for everybody,
//  including whoever is building it. It is also the state every build is in
//  today, so a regression here would not be subtle — it would be total, and it
//  would arrive the moment someone "simplified" the rule to `!isSignedIn`.
//
//  That simplification is the specific thing this file exists to catch, and it
//  is an easy one to make: `isConfigured && !isSignedIn` reads like a paranoid
//  extra condition rather than the load-bearing half.
//

import XCTest
@testable import Anchor

final class AccountGateTests: XCTestCase {

    // MARK: - The rule

    func testAConfiguredBuildWithNoSessionIsGated() {
        XCTAssertTrue(
            AccountStore.requiresSignIn(isConfigured: true, isSignedIn: false),
            """
            A build where accounts work, with nobody signed in, must be gated. \
            This is the whole point: an account is what a subscription attaches \
            to, and an ungated signed-out app is an unpaid one.
            """
        )
    }

    func testASignedInTeacherIsNeverGated() {
        XCTAssertFalse(
            AccountStore.requiresSignIn(isConfigured: true, isSignedIn: true),
            "A signed-in teacher must reach the app."
        )
    }

    func testAnUnconfiguredBuildIsNeverGated() {
        XCTAssertFalse(
            AccountStore.requiresSignIn(isConfigured: false, isSignedIn: false),
            """
            A build with no account backend must NOT be gated. Nobody can sign \
            in to satisfy it, so gating makes the app unopenable rather than \
            protecting anything — and this is the state every build is in until \
            GoogleService-Info.plist exists.
            """
        )
        XCTAssertFalse(
            AccountStore.requiresSignIn(isConfigured: false, isSignedIn: true),
            "An unconfigured build is never gated, whatever the session says."
        )
    }

    // MARK: - One definition, two enforcement points

    /// Both places that gate must read the rule rather than restate it.
    ///
    /// They were written as two copies of `isConfigured && !isSignedIn`, which
    /// is exactly how one of them later loses the first half while the other
    /// keeps it — and the two disagreeing means the window locks a teacher out
    /// while onboarding still offers Skip, or the reverse.
    func testTheGateIsReadFromOnePlace() throws {
        let sites = [
            "Anchor/Views/Window/MainWindowView.swift",
            "Anchor/Views/Onboarding/OnboardingView.swift"
        ]

        for path in sites {
            let source = try String(
                contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8
            )

            XCTAssertTrue(
                source.contains("accounts.requiresSignIn"),
                "\(path) no longer reads AccountStore.requiresSignIn."
            )

            // The rule spelled out by hand, anywhere outside AccountStore.
            let restated = source.contains("isConfigured && !")
                || source.contains("isConfigured, !")
            XCTAssertFalse(
                restated,
                """
                \(path) restates the sign-in rule instead of reading it. There \
                is one definition, in AccountStore.requiresSignIn, because two \
                copies of a gate drift apart in exactly the direction that \
                opens one of them.
                """
            )
        }
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
