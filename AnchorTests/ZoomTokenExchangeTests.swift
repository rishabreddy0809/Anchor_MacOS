//
//  ZoomTokenExchangeTests.swift
//  AnchorTests
//
//  Pins which Zoom client identifier Anchor presents, and when.
//
//  ── Why this file exists, and why it was rewritten the same day ─────────────
//
//  `ZoomOAuthHandler.post` has two branches: HTTP Basic when a secret exists,
//  `client_id` in the body otherwise. The second had **never run** — a
//  developer's Keychain always holds a secret, while the shipped
//  `zoomClientSecret` is empty and every un-provisioned install takes it.
//
//  Probed against `zoom.us` on 2026-08-20 using the shipped `zoomClientID`
//  with no secret: `400 invalid_client`, byte-identical to sending a garbage id
//  or no id at all. The first version of this file concluded that Zoom refuses
//  PKCE-only, and gated Connect Zoom on having a secret.
//
//  **That was wrong.** The Marketplace console showed **Use Public Client
//  OAuth** enabled, which mints a *second, different* identifier. Re-probed
//  with it:
//
//      public id, PKCE, no secret  → 400 invalid_grant "Invalid authorization code"
//      confidential id, same call  → 400 invalid_client
//      public id, refresh_token    → 400 invalid_grant "Invalid refresh token"
//
//  `invalid_grant` means Zoom authenticated the client and went on to reject
//  the deliberately bogus code. Zoom supports PKCE-only; Anchor was presenting
//  the confidential client's id on the public client's flow.
//
//  **So the thing worth pinning is not "is a secret required" — it is *which
//  id goes out*.** That is what these tests assert, and the invariant in
//  `testTheSameIdentifierIsUsedForAuthorizeAndExchange` is the one that would
//  have caught the original bug, because it is the property the two call sites
//  can silently disagree about.
//

import XCTest
@testable import Anchor

final class ZoomTokenExchangeTests: XCTestCase {

    private let confidential = "SMDINiavSZKmyIoF4XmM_A"
    private let publicID = "kzU8QEfESJKsvxA3EzCe9A"

    private func config(secret: String?, publicClientID: String?) -> ZoomOAuthConfig {
        ZoomOAuthConfig(clientID: confidential, clientSecret: secret, publicClientID: publicClientID)
    }

    // MARK: - Which identifier goes out

    func testAnUnprovisionedInstallUsesThePublicClientID() {
        // The shape every teacher's Mac is in: no secret, both ids compiled in.
        // Presenting `confidential` here is the original bug, and it fails only
        // after the teacher has approved Anchor.
        XCTAssertEqual(
            config(secret: nil, publicClientID: publicID).effectiveClientID, publicID,
            "An install with no secret must present the PUBLIC client id. The confidential "
            + "one returns invalid_client, after consent."
        )
    }

    func testAProvisionedInstallStillUsesTheConfidentialPair() {
        // Per-school must not regress: an admin who provisioned the secret gets
        // exactly the behaviour they had before the public client existed.
        XCTAssertEqual(
            config(secret: "a-provisioned-secret", publicClientID: publicID).effectiveClientID,
            confidential,
            "A provisioned install must keep using the confidential pair it was set up with."
        )
    }

    func testAnEmptyOrWhitespaceSecretDoesNotCountAsProvisioned() {
        // A secret pasted with a trailing newline is the realistic failure. It
        // must fall back to the public client rather than sending the
        // confidential id with a blank Basic header.
        for blank in ["", "   \n", "\t"] {
            XCTAssertEqual(
                config(secret: blank, publicClientID: publicID).effectiveClientID, publicID,
                "A blank secret (\(blank.debugDescription)) selected the confidential id."
            )
        }
    }

    func testWithNeitherAUsableSecretNorAPublicClientThereIsNoIdentifier() {
        XCTAssertNil(
            config(secret: nil, publicClientID: nil).effectiveClientID,
            "A confidential id with no secret cannot authenticate; it must not be offered."
        )
        XCTAssertNil(
            ZoomOAuthConfig(clientID: "", clientSecret: "s", publicClientID: nil).effectiveClientID,
            "A secret with no id is half a configuration."
        )
    }

    // MARK: - The invariant that would have caught the original bug

    func testTheSameIdentifierIsUsedForAuthorizeAndExchange() {
        // An authorization code is issued *to a client*. A code obtained under
        // one id and redeemed under the other fails at the exchange — after
        // consent. The two call sites in ZoomOAuthHandler read this one
        // accessor precisely so they cannot drift; this asserts the accessor is
        // deterministic, which is what makes that safe.
        for secret in [nil, "", "a-secret"] as [String?] {
            let c = config(secret: secret, publicClientID: publicID)
            XCTAssertEqual(
                c.effectiveClientID, c.effectiveClientID,
                "effectiveClientID is not stable, so authorize and exchange could differ."
            )
            XCTAssertTrue(
                [confidential, publicID].contains(c.effectiveClientID),
                "effectiveClientID returned something that is neither configured id."
            )
        }
    }

    // MARK: - The gate

    func testTheGateAllowsAPublicClientWithNoSecret() {
        XCTAssertTrue(
            ZoomOAuthConfig.canCompleteTokenExchange(
                clientID: confidential, clientSecret: nil, publicClientID: publicID
            ),
            "This is the shipped configuration. Disabling Connect Zoom here — as the first "
            + "version of this file did — costs exactly the reach the public client provides."
        )
    }

    func testTheGateRefusesAConfidentialIDWithNoSecret() {
        XCTAssertFalse(
            ZoomOAuthConfig.canCompleteTokenExchange(
                clientID: confidential, clientSecret: nil, publicClientID: nil
            ),
            "Without a public client, a bare confidential id cannot complete the exchange — "
            + "measured: 400 invalid_client."
        )
    }

    // MARK: - A half-provisioned school must not fall back to Anchor's own app

    /// A school's own Marketplace app, provisioned through ADMIN-SETUP.md
    /// step 3. Deliberately unlike either shipped id so a fallback shows up as
    /// a swap rather than as a near-miss.
    private let schoolID = "SCHOOLownCONFIDENTIALid"

    func testAProvisionedClientIDSuppressesTheShippedPublicClient() {
        // The defect this section exists for. Step 3 sets four variables in one
        // command; if the secret half does not land — a mistyped name, a
        // quoting mistake, one of the two Keychain writes failing — the store
        // holds the school's id and no secret. `effectiveClientID` then falls
        // through to the public client, and the public client belongs to
        // *Anchor's* registration, not the school's.
        XCTAssertNil(
            ZoomOAuthConfig.offeredPublicClientID(
                shipped: publicID, provisionedClientID: schoolID
            ),
            "Anchor's own public client was offered as the fallback for a school's "
            + "confidential id. The teacher would be signed in to the wrong Marketplace app."
        )
    }

    func testAHalfProvisionedSchoolIsRefusedBeforeConsentRatherThanAfter() {
        // What the suppression buys, stated as the outcome rather than the
        // mechanism: the whole config is unusable, so Connect Zoom is off with
        // a reason. The alternative is not "it works" — it is "You cannot
        // authorize", which ADMIN-SETUP.md records as the most misleading page
        // in the flow, because a skipped step 3 and a typo'd redirect URL
        // produce the identical screen.
        let offered = ZoomOAuthConfig.offeredPublicClientID(
            shipped: publicID, provisionedClientID: schoolID
        )
        XCTAssertFalse(
            ZoomOAuthConfig.canCompleteTokenExchange(
                clientID: schoolID, clientSecret: nil, publicClientID: offered
            ),
            "A school id with no secret was offered as connectable."
        )
        XCTAssertNotEqual(
            ZoomOAuthConfig(
                clientID: schoolID, clientSecret: nil, publicClientID: offered
            ).effectiveClientID,
            publicID,
            "Anchor would authorize under its own id while the deployment named another."
        )
    }

    func testAFullyProvisionedSchoolIsUnaffected() {
        // The path that has actually been used must not move. Both halves
        // present: the confidential pair wins, and the shipped public client is
        // not theirs to fall back to anyway.
        let offered = ZoomOAuthConfig.offeredPublicClientID(
            shipped: publicID, provisionedClientID: schoolID
        )
        XCTAssertEqual(
            ZoomOAuthConfig(
                clientID: schoolID, clientSecret: "school-secret", publicClientID: offered
            ).effectiveClientID,
            schoolID,
            "A fully provisioned school stopped using its own registration."
        )
    }

    func testAnUnprovisionedInstallKeepsThePublicClient() {
        // The reach the 20 Aug correction bought, and the thing this rule is
        // most likely to break by over-reaching. No id was provisioned, so the
        // shipped registration is the one in play and its public client is
        // fair game.
        XCTAssertEqual(
            ZoomOAuthConfig.offeredPublicClientID(shipped: publicID, provisionedClientID: nil),
            publicID,
            "A fresh install lost browser sign-in — exactly the regression the public "
            + "client was added to prevent."
        )
    }

    func testASecretWithNoProvisionedIDIsNotIncoherent() {
        // The asymmetry, and the reason this rule keys on the *id* alone.
        // A provisioned secret with no provisioned id completes the SHIPPED
        // registration — which is how the developer's own Mac is set up, and
        // how a school could choose to use Anchor's app rather than its own.
        // Keying on "either half overridden" would have broken both.
        XCTAssertEqual(
            ZoomOAuthConfig.offeredPublicClientID(shipped: publicID, provisionedClientID: nil),
            publicID,
            "A secret-only provisioning was treated as naming a different registration."
        )
        XCTAssertEqual(
            ZoomOAuthConfig(
                clientID: confidential, clientSecret: "the-real-secret", publicClientID: publicID
            ).effectiveClientID,
            confidential,
            "The shipped confidential pair stopped working when its secret was provisioned."
        )
    }

    func testABlankProvisionedIDCountsAsNotProvisioned() {
        // `clientIDOverride` is folded through `OAuthClientDefaults.value`, so
        // it should never arrive blank — but a Keychain value that survived a
        // paste with a trailing newline is the realistic failure everywhere
        // else in this file, and a blank id here would silently switch off
        // sign-in for a fresh install rather than merely mis-selecting an id.
        for blank in ["", "   \n", "\t"] {
            XCTAssertEqual(
                ZoomOAuthConfig.offeredPublicClientID(shipped: publicID, provisionedClientID: blank),
                publicID,
                "A blank provisioned id (\(blank.debugDescription)) suppressed the public client."
            )
        }
    }

    // MARK: - What actually ships

    func testTheShippedDefaultsCanCompleteTheExchange() {
        // Reads the real constants rather than restating them, so emptying one
        // by accident fails here rather than on a teacher's Mac.
        XCTAssertTrue(
            ZoomOAuthConfig.canCompleteTokenExchange(
                clientID: OAuthClientDefaults.value(OAuthClientDefaults.zoomClientID),
                clientSecret: OAuthClientDefaults.value(OAuthClientDefaults.zoomClientSecret),
                publicClientID: OAuthClientDefaults.value(OAuthClientDefaults.zoomPublicClientID)
            ),
            "A fresh install can no longer sign in to Zoom at all."
        )
    }

    func testTheShippedBuildSendsThePublicClientAndNoSecret() {
        // The three claims that together describe the binary a teacher gets:
        // the public id ships, the secret does not, and the public id is the
        // one that goes out. If a secret is ever committed the third breaks,
        // which is the correct alarm — a committed secret is extractable from
        // every copy of the app.
        XCTAssertNotNil(
            OAuthClientDefaults.value(OAuthClientDefaults.zoomPublicClientID),
            "The public client id is empty, so a fresh install has nothing to sign in with."
        )
        XCTAssertNil(
            OAuthClientDefaults.value(OAuthClientDefaults.zoomClientSecret),
            "A client secret has been committed to source."
        )
        XCTAssertEqual(
            ZoomOAuthConfig(
                clientID: OAuthClientDefaults.zoomClientID,
                clientSecret: OAuthClientDefaults.value(OAuthClientDefaults.zoomClientSecret),
                publicClientID: OAuthClientDefaults.value(OAuthClientDefaults.zoomPublicClientID)
            ).effectiveClientID,
            OAuthClientDefaults.zoomPublicClientID,
            "The shipped build would present the confidential id — the original defect."
        )
    }

    func testTheTwoShippedIdentifiersAreNotTheSame() {
        // Without this, every test above passes vacuously if someone "tidies
        // up" by setting both constants to the same value — which is exactly
        // the mistake the whole correction was about.
        XCTAssertNotEqual(
            OAuthClientDefaults.zoomClientID, OAuthClientDefaults.zoomPublicClientID,
            "The confidential and public client ids are identical, so nothing here means anything."
        )
    }
}

// MARK: - Scope coverage for a school deployment

/// Pins that Anchor verifies every scope `ADMIN-SETUP.md` step 1.4 asks a
/// school's Zoom admin to add.
///
/// Found 2026-08-28 while checking the per-school route was complete. Three
/// things were wrong at once and each hid the next:
///
///   * `ZoomOAuthConfig.requiredScopes` listed three scopes. Step 1.4 asks for
///     five. `user:read:zak` and the report scope were never checked.
///   * `ZoomOAuthConfig.degradedScopes` — the function that reports a missing
///     *optional* scope — had **no callers at all**, so even the one optional
///     scope it did know about was computed and thrown away.
///   * A second, five-entry scope table in `ZoomConfig` had no callers either,
///     and being the more complete of the two it read as reassurance.
///
/// Net effect on a school: an admin who missed the ZAK scope got a connection
/// Anchor called healthy, and an assistant that silently joined the class as an
/// anonymous guest rather than as the teacher — `MeetingBot` mints the ZAK with
/// `try?` and falls back, correctly, without anywhere to report it.
@MainActor
final class ZoomScopeCoverageTests: XCTestCase {

    /// Every scope ADMIN-SETUP asks for is one Anchor actually looks for.
    func testEveryScopeTheAdminIsAskedToAddIsVerified() {
        let checked = Set(ZoomOAuthConfig.requiredScopes.flatMap(\.names))

        for scope in [
            "user:read:user",
            "meeting:read:list_meetings",
            "user:read:zak",
            "dashboard:read:list_meeting_participants:admin",
            "report:read:list_meeting_participants:admin"
        ] {
            XCTAssertTrue(
                checked.contains(scope),
                "\(scope) is in ADMIN-SETUP.md step 1.4 but nothing verifies a grant carries it."
            )
        }
    }

    /// The two Anchor cannot work at all without stay required; everything else
    /// must stay optional, or a teacher whose admin skipped a Business-only
    /// scope is refused a sign-in that would have worked.
    func testOnlyTheTwoIndispensableScopesBlockASignIn() {
        let required = ZoomOAuthConfig.requiredScopes.filter { !$0.isOptional }

        XCTAssertEqual(required.count, 2)
        XCTAssertEqual(
            Set(required.map(\.displayName)),
            ["user:read:user", "meeting:read:list_meetings"]
        )
    }

    /// A full grant is quiet.
    func testAFullGrantProducesNoWarning() {
        let granted: Set<String> = [
            "user:read:user",
            "meeting:read:list_meetings",
            "user:read:zak",
            "dashboard:read:list_meeting_participants:admin",
            "report:read:list_meeting_participants:admin"
        ]

        XCTAssertTrue(ZoomOAuthConfig.missingScopes(in: granted).isEmpty)
        XCTAssertTrue(ZoomOAuthConfig.degradedScopes(in: granted).isEmpty)
    }

    /// The ZAK case, which is the one that used to pass silently. A grant good
    /// enough to connect, missing the scope the assistant needs to join as the
    /// teacher, must be reported as degraded rather than as fine.
    func testAMissingZakScopeIsReportedRatherThanSwallowed() {
        let granted: Set<String> = ["user:read:user", "meeting:read:list_meetings"]

        XCTAssertTrue(
            ZoomOAuthConfig.missingScopes(in: granted).isEmpty,
            "This grant is good enough to connect — it must not block sign-in."
        )
        XCTAssertTrue(
            ZoomOAuthConfig.degradedScopes(in: granted).map(\.displayName)
                .contains("user:read:zak"),
            "A missing ZAK scope must be reported; the bot degrades to a guest join without it."
        )
    }

    /// Zoom issues admin-suffixed spellings to some apps. A school's grant must
    /// satisfy the same requirement.
    func testAdminSpellingsSatisfyTheSameRequirement() {
        let granted: Set<String> = [
            "user:read:user:admin",
            "meeting:read:list_meetings:admin",
            "user:read:zak:admin"
        ]

        XCTAssertTrue(ZoomOAuthConfig.missingScopes(in: granted).isEmpty)
        XCTAssertFalse(
            ZoomOAuthConfig.degradedScopes(in: granted).map(\.displayName)
                .contains("user:read:zak"),
            "user:read:zak:admin satisfies the ZAK requirement."
        )
    }
}
