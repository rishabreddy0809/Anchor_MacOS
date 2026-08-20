//
//  CredentialSeedTests.swift
//  AnchorTests
//
//  Pins the rule that decides what a provisioning launch writes.
//
//  ── Why this file is worth its length ───────────────────────────────────────
//
//  Provisioning has no GUI in a shipped build, so a school's admin sets
//  environment variables on one Terminal launch (ADMIN-SETUP.md step 3). The
//  code that consumed them used to read the environment and write the Keychain
//  in one step, and therefore could not distinguish **"the admin did not
//  mention this variable"** from **"the admin wants this variable empty"**. It
//  resolved that ambiguity destructively.
//
//  The two defects that came out of it are the first two tests below. Both are
//  invisible on a first setup, where every variable is supplied, and both
//  appear on a *rotation*, where only the value being rotated is — which is
//  months later, on a call, with someone waiting.
//
//  ── Why the tests are here and not against the Keychain ─────────────────────
//
//  The bug was never in storage. It was in the decision taken before anything
//  was written, so that decision is what is worth pinning. Nothing else in this
//  target touches a real Keychain and this file does not start: a Keychain test
//  needs the developer's own login keychain or a signed test host, and it would
//  be testing Apple's code rather than Anchor's rule.
//
//  ── This file was shown to fail before it was trusted ───────────────────────
//
//  `CredentialIntent.read` was temporarily reverted to the old rule — returning
//  the equivalent of "clear" for an absent variable — and the first two tests
//  failed, which is the only reason to believe they test anything. The
//  ship-checklist's own history is the argument for bothering:
//  `RetentionPolicyTests` once shipped *wrong* because a bare `contains` check
//  passed a canary it should have failed.
//

import XCTest
@testable import Anchor

final class CredentialSeedTests: XCTestCase {

    // MARK: - The two defects this type exists to prevent

    /// **Defect 1.** Rotating only the Meeting SDK secret used to delete the
    /// key beside it, because the branch fired on either variable and then
    /// wrote both halves, passing `nil` — "delete" — for the unmentioned one.
    ///
    /// The damage was not the deletion. It was that `resolved()` then fell back
    /// to Anchor's *shipped* `meetingSDKKey` and paired it with the school's
    /// secret, so the app kept a complete-looking pair that could never
    /// authenticate, and reported the failure as a missing credential.
    func testRotatingOnlyTheSDKSecretLeavesTheKeyAlone() {
        let seed = CredentialSeed.read(from: ["ANCHOR_ZOOM_SDK_SECRET": "rotated-secret-value"])

        XCTAssertEqual(seed.sdkKey, .leave, "an unmentioned key must not be written, let alone deleted")
        XCTAssertEqual(seed.sdkSecret, .set("rotated-secret-value"))
        XCTAssertFalse(seed.sdkKey.writes, "`.leave` is the whole fix: it must write nothing")
        XCTAssertTrue(seed.sdkSecret.writes)
    }

    /// **Defect 2.** Setting only the browser sign-in secret used to write
    /// nothing and say nothing, because the whole branch was gated on the
    /// client ID being present.
    func testRotatingOnlyTheOAuthSecretIsHonoured() {
        let seed = CredentialSeed.read(from: ["ANCHOR_ZOOM_OAUTH_CLIENT_SECRET": "rotated-oauth-secret"])

        XCTAssertEqual(seed.oauthClientSecret, .set("rotated-oauth-secret"))
        XCTAssertEqual(seed.oauthClientID, .leave)
        XCTAssertFalse(seed.isEmpty, "a run that names a variable is not an ordinary launch")
    }

    /// The same clobber in the other direction: supplying only the OAuth client
    /// ID used to clear a provisioned secret.
    func testSupplyingOnlyTheOAuthClientIDLeavesTheSecretAlone() {
        let seed = CredentialSeed.read(from: ["ANCHOR_ZOOM_OAUTH_CLIENT_ID": "school-client-id"])

        XCTAssertEqual(seed.oauthClientID, .set("school-client-id"))
        XCTAssertEqual(seed.oauthClientSecret, .leave)
    }

    // MARK: - Un-provisioning must survive the fix

    /// The fix must not make clearing impossible. A school that pasted the
    /// wrong secret has to be able to take it back out, and an empty variable
    /// is the only route in a build with no Settings panel.
    func testAnEmptyVariableStillClears() {
        let seed = CredentialSeed.read(from: [
            "ANCHOR_ZOOM_SDK_SECRET": "",
            "ANCHOR_ZOOM_OAUTH_CLIENT_SECRET": ""
        ])

        XCTAssertEqual(seed.sdkSecret, .clear)
        XCTAssertEqual(seed.oauthClientSecret, .clear)
        XCTAssertTrue(seed.sdkSecret.writes, "clearing is still a write — it just writes nothing")
        XCTAssertNil(seed.sdkSecret.storedValue, "`.clear` is the nil that means delete")
    }

    /// Whitespace is not a credential. A value that survived a copy-paste with
    /// a stray newline would otherwise be stored and fail later, further from
    /// the cause — Zoom secrets are pasted from a browser, so this is the
    /// likely accident rather than a theoretical one.
    func testWhitespaceOnlyCountsAsEmptyAndValuesAreTrimmed() {
        let seed = CredentialSeed.read(from: [
            "ANCHOR_ZOOM_SDK_SECRET": "   \n ",
            "ANCHOR_ZOOM_SDK_KEY": "  padded-key\n"
        ])

        XCTAssertEqual(seed.sdkSecret, .clear)
        XCTAssertEqual(seed.sdkKey, .set("padded-key"))
    }

    // MARK: - The ordinary launch

    /// The overwhelmingly common case: a double-click, naming nothing. It must
    /// touch no storage at all — not even to rewrite a value with itself, since
    /// a write is a chance to fail.
    func testAnOrdinaryLaunchAsksForNothing() {
        let seed = CredentialSeed.read(from: [:])

        XCTAssertTrue(seed.isEmpty)
        for intent in [seed.sdkKey, seed.sdkSecret, seed.oauthClientID, seed.oauthClientSecret] {
            XCTAssertEqual(intent, .leave)
        }
        XCTAssertNil(seed.serverToServer)
        XCTAssertFalse(seed.serverToServerIsPartial)
    }

    /// Unrelated variables must not make a launch look like a provisioning run.
    /// `ANCHOR_NO_AUTOCONNECT` is documented beside these and travels with them.
    func testUnrelatedVariablesAreIgnored() {
        let seed = CredentialSeed.read(from: [
            "ANCHOR_NO_AUTOCONNECT": "1",
            "PATH": "/usr/bin",
            "ANCHOR_DEMO_DATA": "1"
        ])

        XCTAssertTrue(seed.isEmpty)
    }

    // MARK: - A first setup still works

    /// ADMIN-SETUP.md step 3 supplies all four in one command. Nothing about
    /// the fix may change that path, which is the one that has actually been
    /// used.
    func testTheDocumentedFourVariableSetupIsUnchanged() {
        let seed = CredentialSeed.read(from: [
            "ANCHOR_ZOOM_OAUTH_CLIENT_ID": "oauth-id",
            "ANCHOR_ZOOM_OAUTH_CLIENT_SECRET": "oauth-secret",
            "ANCHOR_ZOOM_SDK_KEY": "sdk-key",
            "ANCHOR_ZOOM_SDK_SECRET": "sdk-secret"
        ])

        XCTAssertEqual(seed.oauthClientID, .set("oauth-id"))
        XCTAssertEqual(seed.oauthClientSecret, .set("oauth-secret"))
        XCTAssertEqual(seed.sdkKey, .set("sdk-key"))
        XCTAssertEqual(seed.sdkSecret, .set("sdk-secret"))
        XCTAssertFalse(seed.isEmpty)
    }

    // MARK: - The Server-to-Server triple is all-or-nothing

    /// These three authenticate together, so a partial set is a broken
    /// configuration rather than an incomplete one.
    func testAllThreeServerToServerValuesProduceCredentials() {
        let seed = CredentialSeed.read(from: [
            "ANCHOR_ZOOM_ACCOUNT_ID": "acct",
            "ANCHOR_ZOOM_CLIENT_ID": "cid",
            "ANCHOR_ZOOM_CLIENT_SECRET": "csec"
        ])

        XCTAssertEqual(
            seed.serverToServer,
            ServerToServerSeed(accountID: "acct", clientID: "cid", clientSecret: "csec")
        )
        XCTAssertFalse(seed.serverToServerIsPartial)
    }

    /// The point of `serverToServerIsPartial` is that the refusal can be
    /// *reported*. Silently ignoring a partial set is how an admin ends a setup
    /// call believing a value landed.
    func testAPartialServerToServerSetIsRefusedAndFlagged() {
        let seed = CredentialSeed.read(from: [
            "ANCHOR_ZOOM_ACCOUNT_ID": "acct",
            "ANCHOR_ZOOM_CLIENT_SECRET": "csec"
        ])

        XCTAssertNil(seed.serverToServer, "two of three must write nothing")
        XCTAssertTrue(seed.serverToServerIsPartial, "and must be reportable rather than silent")
        XCTAssertFalse(seed.isEmpty, "a partial set is still a launch that asked for something")
    }

    /// An empty member counts as named, so blanking one third of the triple is
    /// reported rather than treated as an absent variable.
    func testAnEmptyServerToServerMemberIsPartialRatherThanAbsent() {
        let seed = CredentialSeed.read(from: [
            "ANCHOR_ZOOM_ACCOUNT_ID": "acct",
            "ANCHOR_ZOOM_CLIENT_ID": "cid",
            "ANCHOR_ZOOM_CLIENT_SECRET": ""
        ])

        XCTAssertNil(seed.serverToServer)
        XCTAssertTrue(seed.serverToServerIsPartial)
    }

    /// The SDK and OAuth pairs are independent of the triple: provisioning one
    /// must not be read as a partial attempt at the other.
    func testTheSDKPairDoesNotLookLikeAPartialServerToServerSet() {
        let seed = CredentialSeed.read(from: ["ANCHOR_ZOOM_SDK_SECRET": "s"])

        XCTAssertFalse(seed.serverToServerIsPartial)
        XCTAssertNil(seed.serverToServer)
    }

    // MARK: - The document the admin actually follows

    // Everything above pins what Anchor does with a variable it was given. This
    // pins the step before: that the variable names in ADMIN-SETUP.md step 3 are
    // the ones `CredentialSeed.read` looks for.
    //
    // The failure is the same shape as the two defects this file was written
    // about, and lands in the same place -- a rotation call, months later, with
    // someone waiting. Rename a constant in Swift and the document keeps
    // printing the old name. The admin pastes a four-line command, Anchor
    // launches normally, nothing is written and nothing is said, and the call
    // ends with everyone believing the school is provisioned. The first sign is
    // a teacher's Connect button being disabled weeks later.
    //
    // Checked by hand on 2026-08-20 -- the four names match -- and pinned here
    // so it stays checked.

    private func adminSetupDocument() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // AnchorTests/
            .deletingLastPathComponent()        // repo root
            .appendingPathComponent("ADMIN-SETUP.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Every `ANCHOR_*` name the document tells an admin to set.
    private func namesInAdminSetup(_ source: String) throws -> Set<String> {
        let pattern = try NSRegularExpression(pattern: "ANCHOR_[A-Z_]+")
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return Set(pattern.matches(in: source, range: range).compactMap {
            Range($0.range, in: source).map { String(source[$0]) }
        })
    }

    func testEveryVariableAdminSetupNamesIsOneTheCodeActuallyReads() throws {
        let named = try namesInAdminSetup(try adminSetupDocument())

        // Read back through `CredentialSeed.read` rather than against a list of
        // string literals. A literal list would be a second copy of the names
        // and could rot in exactly the way this test exists to prevent.
        for name in named.sorted() {
            let seed = CredentialSeed.read(from: [name: "a-value"])
            XCTAssertFalse(
                seed.isEmpty,
                """
                ADMIN-SETUP.md tells an admin to set \(name), and setting it                 provisions nothing. The command in step 3 would run, say nothing,                 and write nothing.
                """
            )
        }
    }

    func testAdminSetupStillNamesTheFourVariablesItsCommandDependsOn() throws {
        // Without this the test above passes vacuously the moment someone
        // reformats the document and the regex stops matching -- an empty set
        // satisfies a for-loop. The four are the pair for browser sign-in and
        // the pair for the bot.
        let named = try namesInAdminSetup(try adminSetupDocument())
        XCTAssertEqual(
            named,
            [
                "ANCHOR_ZOOM_OAUTH_CLIENT_ID",
                "ANCHOR_ZOOM_OAUTH_CLIENT_SECRET",
                "ANCHOR_ZOOM_SDK_KEY",
                "ANCHOR_ZOOM_SDK_SECRET"
            ],
            """
            The set of variables ADMIN-SETUP.md names has changed. If a variable was             added, check it is read; if one was dropped, check the feature it             provisioned is genuinely gone. The Server-to-Server trio is deliberately             absent -- that document records the bot no longer needs it.
            """
        )
    }
}
