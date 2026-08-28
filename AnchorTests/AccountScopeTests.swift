//
//  AccountScopeTests.swift
//  AnchorTests
//
//  Pins the rule that two Anchor accounts on one Mac are two separate copies
//  of Anchor.
//
//  The bug this covers shipped and was reported from a real pilot Mac: Firebase
//  was configured, both Google accounts signed in, both minted their own uid —
//  and the second account landed on the first account's Home tab, with the
//  first account's classes and rosters, having skipped onboarding entirely.
//  Nothing about *authentication* was wrong. Everything below it read one
//  shared `UserDefaults.standard` key, one fixed archive path and one fixed
//  Keychain account, so the uid the sign-in produced had nowhere to go.
//
//  Everything here is either pure or operates on throwaway suites and temporary
//  directories. `AccountScope.shared.activate` is deliberately never called:
//  it writes to `UserDefaults.standard` and moves files in the real
//  Application Support directory, and a test suite has no business doing that
//  to the Mac it runs on. The parts worth pinning are lifted out to be
//  reachable without it — the same move `AccountStore.requiresSignIn` and
//  `SessionArchive.isPrunableSidecar` already make.
//

import XCTest
@testable import Anchor

/// `@MainActor` because the stores are: the app builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and the test target does not.
@MainActor
final class AccountScopeTests: XCTestCase {

    // MARK: - Separation

    /// The whole fix in one assertion: two uids, three separate places to live.
    func testTwoAccountsShareNoStorage() {
        let first = AccountScopeIdentity(uid: "uid-first")
        let second = AccountScopeIdentity(uid: "uid-second")

        XCTAssertNotEqual(first.suiteName, second.suiteName)
        XCTAssertNotEqual(first.directoryURL, second.directoryURL)
        XCTAssertNotEqual(
            first.keychainAccount("oauth-tokens"),
            second.keychainAccount("oauth-tokens")
        )
    }

    /// The unscoped domain is not any account's, either — otherwise the first
    /// teacher to sign in would still be sharing with a signed-out app.
    func testScopedStorageIsNeverTheUnscopedStorage() {
        let scoped = AccountScopeIdentity(uid: "uid-first")
        let unscoped = AccountScopeIdentity.unscoped

        XCTAssertNil(unscoped.suiteName)
        XCTAssertNotNil(scoped.suiteName)
        XCTAssertNotEqual(scoped.directoryURL, unscoped.directoryURL)
        XCTAssertNotEqual(
            scoped.keychainAccount("user-tokens"),
            unscoped.keychainAccount("user-tokens")
        )
    }

    /// A build with no Firebase never reaches an account, and must behave
    /// exactly as it did before any of this existed: `UserDefaults.standard`,
    /// the original directory, the original Keychain account names.
    func testUnscopedStorageIsUnchangedFromBeforeAccounts() {
        let unscoped = AccountScopeIdentity.unscoped

        XCTAssertEqual(unscoped.defaults, UserDefaults.standard)
        XCTAssertEqual(unscoped.directoryURL.lastPathComponent, "Anchor")
        XCTAssertEqual(unscoped.keychainAccount("oauth-tokens"), "oauth-tokens")
    }

    /// An account's directory sits *under* Anchor's, so uninstalling still
    /// takes everything with it and the retention sweep still has one root.
    func testAccountDirectoryIsNestedUnderAnchors() {
        let scoped = AccountScopeIdentity(uid: "uid-first")
        let components = scoped.directoryURL.pathComponents.suffix(3)

        XCTAssertEqual(Array(components), ["Anchor", "Accounts", "uid-first"])
    }

    // MARK: - Adoption

    /// The migration that keeps this fix from *looking* like the bug it fixes.
    ///
    /// Without it, shipping account scoping tells every teacher already using
    /// Anchor to onboard again with an empty app — indistinguishable, from
    /// their side, from the defect being reported.
    func testFirstAccountInheritsPreferencesThatPredateAccounts() throws {
        let (legacy, legacyName) = try makeSuite()
        let (adopting, adoptingName) = try makeSuite()
        defer {
            legacy.removePersistentDomain(forName: legacyName)
            adopting.removePersistentDomain(forName: adoptingName)
        }

        legacy.set(true, forKey: "anchor.onboarding.completed")
        legacy.set("Ms. Rivera", forKey: "anchor.teacher.name")

        AccountScope.adoptPreferences(from: legacy, to: adopting)

        XCTAssertTrue(adopting.bool(forKey: "anchor.onboarding.completed"))
        XCTAssertEqual(adopting.string(forKey: "anchor.teacher.name"), "Ms. Rivera")
    }

    /// Copy *then* remove, so the teacher's settings exist in exactly one place
    /// afterwards — leaving the originals behind would hand them to the next
    /// account to sign in, which is the defect.
    func testAdoptedPreferencesDoNotStayBehindForTheNextAccount() throws {
        let (legacy, legacyName) = try makeSuite()
        let (adopting, adoptingName) = try makeSuite()
        defer {
            legacy.removePersistentDomain(forName: legacyName)
            adopting.removePersistentDomain(forName: adoptingName)
        }

        legacy.set(true, forKey: "anchor.onboarding.completed")
        AccountScope.adoptPreferences(from: legacy, to: adopting)

        XCTAssertNil(legacy.object(forKey: "anchor.onboarding.completed"))
    }

    /// Only Anchor's own keys move. Application-domain defaults belong to
    /// AppKit and to macOS, and copying them into a per-account suite would be
    /// both useless and, for anything a system framework wrote, harmful.
    func testAdoptionTakesOnlyAnchorsOwnPreferences() throws {
        let (legacy, legacyName) = try makeSuite()
        let (adopting, adoptingName) = try makeSuite()
        defer {
            legacy.removePersistentDomain(forName: legacyName)
            adopting.removePersistentDomain(forName: adoptingName)
        }

        legacy.set("kept", forKey: "NSSomeAppKitPreference")
        legacy.set("moved", forKey: "anchor.teacher.name")

        AccountScope.adoptPreferences(from: legacy, to: adopting)

        XCTAssertEqual(legacy.string(forKey: "NSSomeAppKitPreference"), "kept")
        XCTAssertNil(adopting.object(forKey: "NSSomeAppKitPreference"))
    }

    /// A scope that already holds a value has been used by a real teacher.
    /// Adoption must never write over it — the guard that stops a second run,
    /// or a re-signed-in account, from being handed somebody else's answers.
    func testAdoptionNeverOverwritesWhatAnAccountAlreadyHas() throws {
        let (legacy, legacyName) = try makeSuite()
        let (adopting, adoptingName) = try makeSuite()
        defer {
            legacy.removePersistentDomain(forName: legacyName)
            adopting.removePersistentDomain(forName: adoptingName)
        }

        legacy.set("Ms. Rivera", forKey: "anchor.teacher.name")
        adopting.set("Mr. Okafor", forKey: "anchor.teacher.name")

        AccountScope.adoptPreferences(from: legacy, to: adopting)

        XCTAssertEqual(adopting.string(forKey: "anchor.teacher.name"), "Mr. Okafor")
        XCTAssertEqual(legacy.string(forKey: "anchor.teacher.name"), "Ms. Rivera")
    }

    /// The predicate in front of `FileManager.moveItem`. `Accounts` is the
    /// directory the migration writes *into*: matching it would move the
    /// destination inside itself and take every account's archive with it.
    func testOnlyArchiveFilesAreAdopted() {
        XCTAssertTrue(AccountScope.isAdoptableArchiveFile("session-archive.json"))
        XCTAssertTrue(AccountScope.isAdoptableArchiveFile("session-archive.corrupt-2026-08-01.json"))
        XCTAssertTrue(AccountScope.isAdoptableArchiveFile("session-archive.backup-2026-08-01.json"))

        XCTAssertFalse(AccountScope.isAdoptableArchiveFile("Accounts"))
        XCTAssertFalse(AccountScope.isAdoptableArchiveFile("training-export.csv"))
        XCTAssertFalse(AccountScope.isAdoptableArchiveFile("my-session-archive.json"))
    }

    // MARK: - Following the account

    /// `OnboardingStore` is the one the pilot teacher actually saw: the second
    /// Google account skipped the walkthrough because completion was a single
    /// shared flag. Read per suite, a fresh account has not completed it.
    func testOnboardingCompletionDoesNotCarryToAnotherAccount() throws {
        let (first, firstName) = try makeSuite()
        let (second, secondName) = try makeSuite()
        defer {
            first.removePersistentDomain(forName: firstName)
            second.removePersistentDomain(forName: secondName)
        }

        let firstTeacher = OnboardingStore(defaults: first)
        firstTeacher.finish()
        XCTAssertTrue(firstTeacher.hasCompletedOnboarding)

        let secondTeacher = OnboardingStore(defaults: second)
        XCTAssertFalse(
            secondTeacher.hasCompletedOnboarding,
            "A second account must walk the onboarding flow, not inherit the first account's."
        )
    }

    /// And the other half of it: the first teacher does not get the walkthrough
    /// a second time just because somebody else used their Mac.
    func testOnboardingCompletionSurvivesForTheAccountThatFinishedIt() throws {
        let (suite, name) = try makeSuite()
        defer { suite.removePersistentDomain(forName: name) }

        OnboardingStore(defaults: suite).finish()

        XCTAssertTrue(OnboardingStore(defaults: suite).hasCompletedOnboarding)
    }

    /// The teacher's name is per account for the same reason — it is what the
    /// Home title and the onboarding finish screen greet them by.
    func testTeacherNameDoesNotCarryToAnotherAccount() throws {
        let (first, firstName) = try makeSuite()
        let (second, secondName) = try makeSuite()
        defer {
            first.removePersistentDomain(forName: firstName)
            second.removePersistentDomain(forName: secondName)
        }

        TeacherProfileStore(defaults: first).name = "Ms. Rivera"

        XCTAssertEqual(TeacherProfileStore(defaults: first).name, "Ms. Rivera")
        XCTAssertEqual(TeacherProfileStore(defaults: second).name, "")
    }

    // MARK: - Helpers

    /// A suite nothing else on this Mac reads, removed by the caller.
    private func makeSuite() throws -> (UserDefaults, String) {
        let name = "com.anchor.tests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        return (suite, name)
    }
}

/// Pins how the signed-out gate gets a new account into the walkthrough and a
/// returning one past it.
///
/// Reported 2026-08-27: signing in with a second Google account dropped the
/// teacher straight into Anchor instead of onboarding them. The completion
/// record was already per-account and correct — the walkthrough was being
/// *presented* by `SignedOutGate`, which SwiftUI tears down the instant
/// `requiresSignIn` goes false, killing its own sheet mid-dismiss while
/// `MainWindowView` tried to raise a second one. The fix moved presentation to
/// the view that survives the transition, which means the gate now opens the
/// walkthrough for everybody and the flow itself works out who arrived.
@MainActor
final class OnboardingHandoffTests: XCTestCase {

    private func makeSuite() throws -> (UserDefaults, String) {
        let name = "com.anchor.tests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    /// A brand new account stays in the walkthrough. This is the reported bug.
    func testNewAccountIsNotSentStraightIntoTheApp() {
        XCTAssertFalse(
            OnboardingStore.shouldFinishOnSignIn(uid: "uid-new", hasCompletedOnboarding: false),
            "An account that has never onboarded must walk the flow, not be dropped into Anchor."
        )
    }

    /// A returning account is not walked round a tour it finished last term.
    func testReturningAccountIsLetStraightThrough() {
        XCTAssertTrue(
            OnboardingStore.shouldFinishOnSignIn(uid: "uid-known", hasCompletedOnboarding: true)
        )
    }

    /// Signing *out* must not close the walkthrough. The gate opens it to sign
    /// back in, and a uid going to nil while it is open is that flow starting,
    /// not finishing — dropping the completion check here would close the sheet
    /// the moment it was needed.
    func testSigningOutDoesNotCloseTheWalkthrough() {
        XCTAssertFalse(
            OnboardingStore.shouldFinishOnSignIn(uid: nil, hasCompletedOnboarding: true)
        )
        XCTAssertFalse(
            OnboardingStore.shouldFinishOnSignIn(uid: nil, hasCompletedOnboarding: false)
        )
    }

    /// The gate cannot consult a completion record — nobody is signed in, so
    /// the one it would read describes nobody. `present()` opens regardless;
    /// `presentIfNeeded()` is the launch-time call that respects the record.
    func testGateCanOpenTheWalkthroughWithNoAccountToConsult() throws {
        let (suite, name) = try makeSuite()
        defer { suite.removePersistentDomain(forName: name) }

        let store = OnboardingStore(defaults: suite)
        store.finish()
        XCTAssertFalse(store.isPresented)

        store.presentIfNeeded()
        XCTAssertFalse(store.isPresented, "presentIfNeeded must respect a completion record.")

        store.present()
        XCTAssertTrue(store.isPresented, "The gate must be able to open the flow regardless.")
    }

    /// An account switch reloads the record but must leave the sheet up: the
    /// commonest way to reach it is a teacher signing in *on the account step*,
    /// and closing there tore down the flow mid-use.
    func testAccountSwitchDoesNotTearDownAnOpenWalkthrough() {
        // Deliberately **not** a pinned suite. `accountDidChange` returns early
        // for a pinned store, so a test built on one would assert that an
        // untouched flag is untouched and pass however this method is written —
        // including the way it was written when it broke the flow. An unpinned
        // store runs the real path; it only ever *reads* `anchor.onboarding.
        // completed`, and nothing below writes, so the Mac running the suite is
        // left exactly as it was found.
        let store = OnboardingStore()
        store.present()
        XCTAssertTrue(store.isPresented)

        // The scope switch every per-teacher store listens for — what a
        // sign-in on the account step actually delivers.
        NotificationCenter.default.post(name: AccountScope.didChange, object: nil)

        XCTAssertTrue(
            store.isPresented,
            "Signing in from inside the walkthrough must not dismiss the walkthrough."
        )
    }
}

/// Pins that a Zoom connection belongs to a teacher, not to a Mac.
///
/// Reported 2026-08-27: a brand new account found Zoom already connected.
/// Two separate causes, and this file guards the one a future tidy-up would
/// undo. `ZoomViewModel.hasTeacherZoomConnection` used to be
/// `hasAnyZoomCredential` and read
/// `ZoomOAuthStore.isConnected || ZoomCredentialsStore.hasCredentials` — the
/// second being an administrator's Server-to-Server credential, shared by
/// everyone on the machine. Counting it meant Home offered "Go to Live Class"
/// to a teacher whose classes were in a different Zoom account entirely.
///
/// A source scan rather than a behavioural test, deliberately: the property
/// reads two Keychain-backed singletons, so proving it *behaves* would mean
/// writing real credentials onto the Mac running the suite. What actually
/// needs pinning is which store it consults, and that is visible in the text.
/// Same idiom as `PublishedClaimScanTests` and `CredentialSeedTests`.
final class ZoomConnectionOwnershipTests: XCTestCase {

    func testTeacherZoomConnectionIgnoresTheSharedDeploymentCredential() throws {
        let source = try zoomViewModelSource()
        let property = try XCTUnwrap(
            Self.body(ofProperty: "hasTeacherZoomConnection", in: source),
            "hasTeacherZoomConnection was not found in ZoomViewModel.swift — if it was "
                + "renamed, rename it here too rather than deleting this guard."
        )

        XCTAssertTrue(
            property.contains("ZoomOAuthStore"),
            "A teacher's Zoom connection is their own OAuth grant."
        )
        XCTAssertFalse(
            property.contains("ZoomCredentialsStore"),
            """
            hasTeacherZoomConnection consults ZoomCredentialsStore again — the \
            Server-to-Server credential an administrator provisions once per Mac. \
            That is shared by every account on the machine, so it makes a brand new \
            teacher look connected to somebody else's Zoom, with none of their own \
            classes in it. See ADMIN-SETUP.md, "What is deliberately not here".
            """
        )
    }

    /// The old name must not come back with the old meaning attached.
    func testTheOldSharedCredentialGateIsGoneEverywhere() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Anchor")

        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "Scanned no Swift files — the guard would pass vacuously.")

        let offenders = files.filter {
            (try? String(contentsOf: $0, encoding: .utf8))?.contains("hasAnyZoomCredential") == true
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "hasAnyZoomCredential is back in \(offenders.map(\.lastPathComponent)). It counted a "
                + "shared deployment credential as a teacher's own connection."
        )
    }

    // MARK: - Helpers

    private func zoomViewModelSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // AnchorTests/
            .deletingLastPathComponent()        // repo root
            .appendingPathComponent("Anchor/Services/ZoomViewModel.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The lines of a computed property, from its declaration to the first line
    /// that closes it at the same indentation.
    private static func body(ofProperty name: String, in source: String) -> String? {
        let lines = source.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.contains("var \(name): Bool {") }) else {
            return nil
        }
        let indent = lines[start].prefix { $0 == " " }
        let end = lines[(start + 1)...].firstIndex { $0 == indent + "}" } ?? lines.endIndex
        return lines[start...min(end, lines.index(before: lines.endIndex))].joined(separator: "\n")
    }
}

/// Pins that Anchor lists only classes the signed-in account **teaches**.
///
/// `GoogleClassroomService.courses()` used to fall back to `studentId=me` when
/// the account taught nothing, and show those classes flagged "enrolled as a
/// student". The intent was sound — an empty list looks like a broken
/// connection — but the result was a screen full of classes Anchor could do
/// nothing with: Google shows a student nobody's work but their own, so they
/// could not be monitored, scored, or given a roster. Home's own empty row had
/// meanwhile always claimed "classes you're enrolled in as a student aren't
/// shown", so the app contradicted itself in writing.
///
/// A source scan, for the same reason as `ZoomConnectionOwnershipTests`: the
/// method is one HTTP call deep and proving it behaviourally would mean
/// standing up a Google fake for a question that is really "does this query
/// exist at all". The query string is the thing worth pinning.
final class ClassroomTeachingOnlyTests: XCTestCase {

    func testCoursesAreNeverFetchedForAnAccountThatOnlyAttendsThem() throws {
        let source = try serviceSource()

        XCTAssertTrue(
            source.contains("teacherId"),
            "The teaching query is gone — Anchor would list no classes at all."
        )
        XCTAssertFalse(
            source.contains("studentId"),
            """
            GoogleClassroomService queries studentId again. That returns classes the \
            account is enrolled in rather than teaches, which Anchor cannot monitor, \
            score or load a roster for — and Home's empty row promises they are not \
            shown. If this is being restored deliberately, fix that copy too.
            """
        )
    }

    /// The flag those classes were carried on. Its absence is what makes the
    /// rest of the UI unable to quietly start showing them again.
    func testNoCourseCarriesAStudentEnrolmentFlag() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Anchor")

        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "Scanned no Swift files — the guard would pass vacuously.")

        let offenders = files.filter {
            (try? String(contentsOf: $0, encoding: .utf8))?.contains("enrolledAsStudent") == true
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "enrolledAsStudent is back in \(offenders.map(\.lastPathComponent))."
        )
    }

    private func serviceSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // AnchorTests/
            .deletingLastPathComponent()        // repo root
            .appendingPathComponent("Anchor/Services/GoogleClassroomService.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
