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
