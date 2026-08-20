//
//  OAuthBounceContractTests.swift
//  AnchorTests
//
//  Pins the three-way agreement that Zoom sign-in depends on and nothing else
//  checks.
//
//  ── The failure this guards ─────────────────────────────────────────────────
//
//  Zoom will not honour an `http://` loopback redirect (ZOOM_INTEGRATION.md
//  §2a: registration is rejected, and toggling Use Public Client OAuth does not
//  change it), so Anchor registers an **HTTPS** page instead and that page
//  forwards the query string to a loopback listener the app is holding open.
//  Three artifacts have to agree for a teacher to get past Zoom's consent
//  screen:
//
//    1. `ZoomOAuthConfig.loopbackPort` / `.redirectRoute` — where
//       `LoopbackRedirectListener` is actually listening.
//    2. `Web/oauth-zoom-bounce.html`'s `TARGET` — where the deployed page
//       sends the browser.
//    3. The redirect URL registered on the Marketplace app, which must equal
//       `ZoomOAuthConfig.bounceURL` character for character.
//
//  Only the first two are in this repository, so only those two can be pinned
//  here — see `testTheBounceURLIsStatedOnceSoTheRegistrationHasOneSourceOfTruth`
//  for what is deliberately *not* claimed about the third.
//
//  **Change the port in Swift and not in the page and nothing fails loudly.**
//  The build succeeds. The tests pass. Zoom's consent screen appears exactly as
//  it should. The teacher approves Anchor, the browser is sent to a port with
//  nothing on it, and Anchor sits waiting on a redirect that will never arrive
//  — presenting, from where the teacher is standing, as Zoom being broken. That
//  is the same shape as the token-exchange defect found on 2026-08-20: a
//  failure that lands *after* consent, where it costs the most trust and
//  explains itself the least.
//
//  Verified against the live page on 2026-08-20 — `curl` of
//  https://anchor-oauth-bounce.vercel.app/oauth/zoom returned 200 and a `TARGET`
//  of `http://127.0.0.1:51789/oauth/zoom`, matching both values below. That
//  check is recorded rather than automated: the deployed page is not something
//  a unit test should reach for, and `anchor-oauth-bounce` has no Git
//  connection (ship-checklist §1), so the file and the deployment can drift
//  independently of anything this file can see.
//

import XCTest
@testable import Anchor

final class OAuthBounceContractTests: XCTestCase {

    /// The bounce page as committed. Read from source for the same reason
    /// `RetentionPolicyTests` reads `privacy.tsx`: the artifact that has to
    /// agree is not Swift, so only the file itself can be asked.
    private func bouncePageSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // AnchorTests/
            .deletingLastPathComponent()        // repo root
            .appendingPathComponent("Web/oauth-zoom-bounce.html")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testTheBouncePageForwardsToThePortTheAppIsListeningOn() throws {
        let source = try bouncePageSource()
        let expected = "http://127.0.0.1:\(ZoomOAuthConfig.loopbackPort)/\(ZoomOAuthConfig.redirectRoute)"

        XCTAssertTrue(
            source.contains(expected),
            """
            Web/oauth-zoom-bounce.html does not forward to \(expected).

            Nothing about this mismatch fails loudly: the build succeeds, Zoom's \
            consent screen appears, the teacher approves Anchor, and then Anchor \
            waits forever on a redirect sent somewhere else. Change both together, \
            and redeploy the page — Web/deploy.sh, since that project has no Git \
            connection and will not deploy itself.
            """
        )
    }

    func testThePageTargetsExactlyOneLoopbackAddress() throws {
        // Without this the test above is satisfiable by a page that *mentions*
        // the right address in a comment while sending the browser elsewhere,
        // which is precisely how a half-finished edit survives review. The
        // literal `127.0.0.1` must appear once and only once.
        let source = try bouncePageSource()
        let occurrences = source.components(separatedBy: "127.0.0.1").count - 1

        XCTAssertEqual(
            occurrences, 1,
            "Expected exactly one loopback address in the bounce page, found \(occurrences). "
            + "A second one means either a stale copy left behind or a comment that will "
            + "outlive the value it describes."
        )
    }

    func testLocalhostIsNeverUsedInPlaceOfTheNumericAddress() throws {
        // Zoom's redirect-URL validator rejects the hostname outright
        // ("Localhost is not allowed, please use 127.0.0.1 or [::1] instead"),
        // and `LoopbackRedirectListener` binds the literal address rather than
        // resolving a name — so `localhost` here would fail on both ends at
        // once, in a browser, after consent.
        let source = try bouncePageSource()
        XCTAssertFalse(
            source.contains("localhost"),
            "The bounce page names `localhost`. Zoom rejects it and the listener does not bind it."
        )
    }

    func testTheBounceURLIsStatedOnceSoTheRegistrationHasOneSourceOfTruth() {
        // What this does NOT claim: that the Marketplace app is registered with
        // this string. That lives in Zoom's console and no test can reach it.
        // What it does claim is the next best thing — that there is exactly one
        // string in the app to compare the registration against, and that the
        // redirect the app builds is derived from it rather than written twice.
        XCTAssertEqual(
            ZoomOAuthConfig.redirectURIForDisplay, ZoomOAuthConfig.bounceURL,
            "The redirect Anchor sends to Zoom no longer equals `bounceURL`, so the value "
            + "registered on the Marketplace app now matches neither with certainty."
        )
        XCTAssertTrue(
            ZoomOAuthConfig.bounceURL.hasPrefix("https://"),
            "Zoom will not honour a non-HTTPS redirect — that is the whole reason this page exists."
        )
        XCTAssertTrue(
            ZoomOAuthConfig.bounceURL.hasSuffix("/\(ZoomOAuthConfig.redirectRoute)"),
            "The registered URL and the loopback path have diverged; the page forwards by route."
        )
    }
}
