//
//  MeetingSDKTokenTests.swift
//  AnchorTests
//
//  Pins the Meeting SDK JWT: what is in it, what is deliberately *not*, and
//  that it is signed with the secret it claims to be signed with.
//
//  ── Why this is worth a file ────────────────────────────────────────────────
//
//  On a Basic or Pro Zoom account the two participant scopes cannot be granted
//  at all (ship-checklist §3, proven in the console by their absence), so the
//  in-meeting bot is not the richer of two live-signal sources — it is the only
//  one. Everything the dashboard shows during a live class passes through this
//  token. It is also the last thing that runs entirely on Anchor's own machine:
//  after this the next actor is Zoom.
//
//  Until now the whole specification lived in a comment above `token()`. That
//  comment is right, and a comment cannot fail a build.
//
//  ── The regression it is written against ────────────────────────────────────
//
//  `mn` and `role` belong to the **Web** Meeting SDK signature, which binds a
//  token to one meeting and one role. The native macOS SDK authenticates the
//  *app*, not a meeting, and takes the meeting number through
//  `ZoomSDKJoinMeetingElements` instead. Sending the web claims makes `sdkAuth`
//  reject the token — and `sdkKey` is a deprecated alias for `appKey` that does
//  the same.
//
//  This is not a hypothetical edit. Every Zoom Meeting SDK tutorial and sample
//  on the web is the *Web* SDK, and all of them show `mn` and `role`. The next
//  person to debug a failing join will find those examples first, and adding
//  them back looks like fixing an omission.
//
//  ── Why the failure would be misread ────────────────────────────────────────
//
//  A rejected claim set surfaces as `ZoomSDKAuthError_KeyOrSecretWrong` or
//  `_JwtTokenWrong` on a delegate callback, which `ZoomMeetingSDKBridge.describe`
//  renders as "the SDK Key or Secret is wrong (check the Meeting SDK app's
//  Client ID/Secret)". That sentence is accurate for what Zoom returned and
//  points at the wrong half of the problem: the credentials would be perfectly
//  correct. The same shape of misdirection this project has been bitten by
//  twice — `invalid_client` meaning the id was *wrong* rather than *missing*,
//  and "No Meeting SDK Key/Secret" reported when both were present but
//  mismatched. An error naming a credential is not evidence about a credential.
//

import XCTest
import CryptoKit
@testable import Anchor

final class MeetingSDKTokenTests: XCTestCase {

    private let key = "QdI3h9EXTtWgQWmZB9frVQ"
    private let secret = "a-meeting-sdk-client-secret"
    private let issuedAt = Date(timeIntervalSince1970: 1_760_000_000)

    private func provider() -> MeetingSDKTokenProvider {
        MeetingSDKTokenProvider(sdkKey: key, sdkSecret: secret)
    }

    /// Splits a compact JWS and decodes the two JSON segments.
    private func decode(_ token: String) throws -> (header: [String: Any], payload: [String: Any]) {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        XCTAssertEqual(parts.count, 3, "Not a compact JWS: \(parts.count) segments.")
        func json(_ segment: Substring) throws -> [String: Any] {
            var base64 = String(segment)
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            while base64.count % 4 != 0 { base64.append("=") }
            let data = try XCTUnwrap(Data(base64Encoded: base64), "Segment is not base64url.")
            return try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any],
                "Segment is not a JSON object."
            )
        }
        return (try json(parts[0]), try json(parts[1]))
    }

    // MARK: - The claim set, exactly

    func testThePayloadCarriesExactlyTheFourNativeClaims() throws {
        let (_, payload) = try decode(try provider().token(issuedAt: issuedAt))

        XCTAssertEqual(
            Set(payload.keys), ["appKey", "iat", "exp", "tokenExp"],
            """
            The Meeting SDK claim set changed. `mn`, `role` and `sdkKey` belong to the \
            WEB SDK signature and make sdkAuth reject the token — which reports itself \
            as a wrong Key or Secret, so the next person debugs the credentials instead \
            of the claims. Read the comment above MeetingSDKTokenProvider.token before \
            changing this.
            """
        )
    }

    func testTheWebSDKClaimsAreAbsentByName() throws {
        // The set assertion above already covers these. Named separately so the
        // failure says *which* claim was added — the set diff on a dictionary
        // of four keys is not much help at 2am on a setup call, and these three
        // are the ones every web tutorial will hand you.
        let (_, payload) = try decode(try provider().token(issuedAt: issuedAt))
        for claim in ["mn", "role", "sdkKey"] {
            XCTAssertNil(
                payload[claim],
                "`\(claim)` is a Web Meeting SDK claim. The native macOS SDK authenticates "
                + "the app, not a meeting, and rejects it."
            )
        }
    }

    func testTheHeaderIsHS256() throws {
        // Not decoration: the secret is used as a raw HMAC key, so the
        // algorithm and the key type have to agree. It is also the reason this
        // secret cannot ship — see ship-checklist §4.
        let (header, _) = try decode(try provider().token(issuedAt: issuedAt))
        XCTAssertEqual(header["alg"] as? String, "HS256")
        XCTAssertEqual(header["typ"] as? String, "JWT")
    }

    func testTheAppKeyIsTheSDKKeyItWasGiven() throws {
        let (_, payload) = try decode(try provider().token(issuedAt: issuedAt))
        XCTAssertEqual(payload["appKey"] as? String, key)
    }

    // MARK: - Zoom's timing rules

    func testExpirySitsWhereZoomRequires() throws {
        // Zoom requires `exp` between 30 minutes and 48 hours out, and
        // `tokenExp` at least `exp`. Checked against the SHIPPED default rather
        // than a value passed in, because the default is what every join
        // actually uses — `token()` is called with no arguments at the one call
        // site in MeetingBot.
        let (_, payload) = try decode(try provider().token(issuedAt: issuedAt))
        let iat = try XCTUnwrap(payload["iat"] as? Int)
        let exp = try XCTUnwrap(payload["exp"] as? Int)
        let tokenExp = try XCTUnwrap(payload["tokenExp"] as? Int)

        XCTAssertEqual(iat, Int(issuedAt.timeIntervalSince1970))
        XCTAssertGreaterThanOrEqual(
            exp - iat, 30 * 60,
            "The default lifetime is under Zoom's 30-minute floor, so every join fails."
        )
        XCTAssertLessThanOrEqual(
            exp - iat, 48 * 60 * 60,
            "The default lifetime is over Zoom's 48-hour ceiling."
        )
        XCTAssertGreaterThanOrEqual(
            tokenExp, exp,
            "tokenExp is before exp, which Zoom rejects."
        )
    }

    func testALifetimeOutsideZoomsWindowStillProducesTheRequestedExpiry() throws {
        // Deliberately NOT clamped, and this pins that decision rather than
        // leaving it ambiguous. `token(lifetime:)` is a signing function; a
        // caller asking for 10 minutes has made a mistake that a silent clamp
        // would hide until someone wondered why the token outlived its request.
        // The rule that matters is on the default, above.
        let (_, payload) = try decode(
            try provider().token(lifetime: 10 * 60, issuedAt: issuedAt)
        )
        XCTAssertEqual(
            try XCTUnwrap(payload["exp"] as? Int) - Int(issuedAt.timeIntervalSince1970),
            10 * 60
        )
    }

    // MARK: - The signature

    func testTheSignatureVerifiesAgainstAnIndependentlyComputedHMAC() throws {
        // Recomputed here from the token's own first two segments rather than
        // compared to a recorded string, so this keeps meaning something when
        // the claim set legitimately changes.
        let token = try provider().token(issuedAt: issuedAt)
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        let signingInput = "\(parts[0]).\(parts[1])"

        let expected = HMAC<SHA256>.authenticationCode(
            for: Data(signingInput.utf8),
            using: SymmetricKey(data: Data(secret.utf8))
        )
        let encoded = Data(expected).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        XCTAssertEqual(String(parts[2]), encoded, "The token is not signed with its own secret.")
    }

    func testADifferentSecretProducesADifferentSignature() throws {
        // The vacuity guard for the case above: without it, a signer that
        // ignored the secret entirely would satisfy the recomputation, because
        // the recomputation would ignore it too.
        let a = try MeetingSDKTokenProvider(sdkKey: key, sdkSecret: "secret-one")
            .token(issuedAt: issuedAt)
        let b = try MeetingSDKTokenProvider(sdkKey: key, sdkSecret: "secret-two")
            .token(issuedAt: issuedAt)
        XCTAssertNotEqual(a, b, "The secret does not affect the token, so it is not signing it.")
    }

    func testEverySegmentIsBase64URLAndUnpadded() throws {
        // `+`, `/` and `=` are legal base64 and illegal in a JWT segment. A
        // signature containing one is rejected by Zoom as a malformed token —
        // indistinguishable, from the outside, from a wrong secret.
        let token = try provider().token(issuedAt: issuedAt)
        for character in ["+", "/", "="] {
            XCTAssertFalse(
                token.contains(character),
                "The token contains `\(character)`, which is base64 rather than base64url."
            )
        }
    }

    // MARK: - Refusing to mint a token that cannot work

    func testAMissingHalfThrowsRatherThanSigningWithIt() {
        // An empty secret would sign perfectly happily with a zero-length HMAC
        // key and produce a token Zoom rejects — a network round trip and a
        // misleading error away from the actual cause, which is local and
        // knowable here. `MeetingSDKCredentialStore.resolved()` already refuses
        // to hand over half a pair; this is the same rule at the other end.
        for (key, secret) in [("", "s"), ("k", ""), ("", "")] {
            XCTAssertThrowsError(
                try MeetingSDKTokenProvider(sdkKey: key, sdkSecret: secret).token(),
                "Signed a token with a missing half (key: \(key.debugDescription), "
                + "secret: \(secret.debugDescription))."
            ) { error in
                XCTAssertEqual(
                    error as? ZoomError, .missingSDKCredentials,
                    "The failure does not name the missing credential."
                )
            }
        }
    }
}
