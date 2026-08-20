//
//  ZoomTokenExchangeTests.swift
//  AnchorTests
//
//  Pins the one rule that decides whether a pilot teacher's very first action
//  in Anchor works: can this install complete Zoom's token exchange.
//
//  ── Why this test exists ────────────────────────────────────────────────────
//
//  `ZoomOAuthHandler.post` has two branches. With a secret it sends HTTP Basic;
//  without one it puts `client_id` in the body, which is the PKCE-only shape
//  that works at Google. The second branch had **never run against Zoom** — a
//  developer's Keychain always holds a secret, so every manual test took the
//  first branch, while the shipped `OAuthClientDefaults.zoomClientSecret` is
//  empty and every un-provisioned install takes the second.
//
//  Probed directly against `zoom.us` on 2026-08-20 (the full five probes are
//  recorded on `ZoomOAuthConfig.clientSecret`): Zoom does not read `client_id`
//  from the body at all — a garbage ID, the real ID, and no ID whatsoever
//  return byte-identical `invalid_client`. So the PKCE-only branch cannot
//  succeed, and `hasClientCredentials` used to be `clientID != nil`, which
//  enabled Connect Zoom on exactly the installs that cannot use it.
//
//  ── Why it is a pure-value test, and why that is not a cop-out ──────────────
//
//  HANDOFF.md records the trap: the stand-down guard could not be caught being
//  wrong in the shipped configuration, so every pure-function test passed the
//  *unfixed* code. That failure mode is worth checking for here, and this rule
//  does not have it. `canCompleteTokenExchange` takes both values as arguments,
//  so the secretless case is reachable by passing `nil` — no Keychain, no
//  MainActor, no network, and no shipped constant able to mask it. The case
//  that actually ships (ID present, secret absent) is `testShippedDefaults…`
//  below, and it reads the real constants rather than fixtures.
//

import XCTest
@testable import Anchor

final class ZoomTokenExchangeTests: XCTestCase {

    // MARK: - The rule

    func testAClientIDAloneCannotCompleteTheTokenExchange() {
        // The exact shape of a fresh, un-provisioned install, and the reason
        // this file exists. Zoom answers this `invalid_client`.
        XCTAssertFalse(
            ZoomOAuthConfig.canCompleteTokenExchange(
                clientID: "SMDINiavSZKmyIoF4XmM_A",
                clientSecret: nil
            ),
            "A client ID with no secret is what every un-provisioned install has. "
            + "Zoom rejects it, so Anchor must not offer Connect."
        )
    }

    func testBothHalvesTogetherCanCompleteTheTokenExchange() {
        XCTAssertTrue(
            ZoomOAuthConfig.canCompleteTokenExchange(
                clientID: "SMDINiavSZKmyIoF4XmM_A",
                clientSecret: "a-provisioned-secret"
            ),
            "A school provisioned through ANCHOR_ZOOM_OAUTH_CLIENT_SECRET must still connect — "
            + "tightening the gate must not close the branch that works."
        )
    }

    func testASecretWithoutAnIDIsAlsoRefused() {
        // Not symmetry for its own sake: `CredentialSeed` allows the two
        // variables to be provisioned independently, so half-provisioned is a
        // state an admin can really produce during a rotation.
        XCTAssertFalse(
            ZoomOAuthConfig.canCompleteTokenExchange(clientID: nil, clientSecret: "a-secret"),
            "Half a provisioning is not a provisioning."
        )
    }

    func testWhitespaceOnlyValuesDoNotCountAsProvisioned() {
        // A secret pasted into a Terminal command with a trailing newline is
        // the realistic way this goes wrong, and it must fail *here* — where
        // the reason can be explained — rather than at Zoom's endpoint after
        // the teacher has already approved Anchor.
        XCTAssertFalse(
            ZoomOAuthConfig.canCompleteTokenExchange(clientID: "SMDIN…", clientSecret: "   \n"),
            "Whitespace is not a secret."
        )
        XCTAssertFalse(
            ZoomOAuthConfig.canCompleteTokenExchange(clientID: "  ", clientSecret: "a-secret"),
            "Whitespace is not a client ID."
        )
        XCTAssertFalse(
            ZoomOAuthConfig.canCompleteTokenExchange(clientID: "", clientSecret: ""),
            "Empty strings are what OAuthClientDefaults ships."
        )
    }

    // MARK: - What actually ships

    func testShippedDefaultsAloneDoNotSatisfyTheRule() {
        // The claim under test is about the binary a teacher downloads, so it
        // reads the shipped constants rather than restating them. If someone
        // ever commits a real secret to `OAuthClientDefaults`, this fails —
        // which is the correct alarm, since that secret would then be
        // extractable from every copy of the app.
        XCTAssertFalse(
            ZoomOAuthConfig.canCompleteTokenExchange(
                clientID: OAuthClientDefaults.value(OAuthClientDefaults.zoomClientID),
                clientSecret: OAuthClientDefaults.value(OAuthClientDefaults.zoomClientSecret)
            ),
            "Either a secret has been committed to source, or the rule stopped requiring one. "
            + "Both are shipping problems."
        )
    }

    func testTheShippedClientIDIsStillPresentSoTheTestIsAboutTheSecret() {
        // Without this, `testShippedDefaultsAloneDoNotSatisfyTheRule` would
        // keep passing if the client ID were emptied by accident — passing for
        // the wrong reason, and hiding a broken build behind a green tick.
        XCTAssertNotNil(
            OAuthClientDefaults.value(OAuthClientDefaults.zoomClientID),
            "The shipped Zoom client ID is empty, so the test above is passing vacuously."
        )
    }
}
