//
//  AnchorAccountTests.swift
//  AnchorTests
//
//  The account layer, minus Firebase.
//
//  Everything here runs without `GoogleService-Info.plist` and without a
//  network, because everything here is the part that stays Anchor's problem
//  when Firebase is doing its job. Two things earn most of the file:
//
//  1. **The ID token claim reader.** It decodes base64url by hand, and
//     base64url drops padding while Foundation's decoder requires it. A JWT
//     payload whose length mod 4 is 2 or 3 decodes to nil unless the padding is
//     restored — and the symptom is not a crash, it is a teacher signing in
//     successfully with a blank name, which nobody files a bug about. Google's
//     real payloads vary in length, so this fails intermittently in the field
//     and never on the one account you tested with.
//
//  2. **The label and greeting fallbacks.** `AnchorAccount.label` is what the
//     finish screen and Settings show. Getting it wrong prints a raw email
//     address at a teacher, which is the kind of small wrongness that reads as
//     an unfinished product.
//

import XCTest
@testable import Anchor

final class AnchorAccountTests: XCTestCase {

    // MARK: - Label and greeting

    func testLabelPrefersDisplayName() {
        let account = AnchorAccount(
            uid: "u1", email: "rivera@school.org", displayName: "Ms. Rivera", provider: .password
        )
        XCTAssertEqual(account.label, "Ms. Rivera")
    }

    func testLabelFallsBackToEmailWhenNameIsBlank() {
        // Firebase returns "" rather than nil for a name that was never set,
        // so a nil check alone would print an empty string at the teacher.
        let account = AnchorAccount(
            uid: "u1", email: "rivera@school.org", displayName: "   ", provider: .password
        )
        XCTAssertEqual(account.label, "rivera@school.org")
    }

    func testLabelNeverRendersEmpty() {
        let account = AnchorAccount(uid: "u1", email: nil, displayName: nil, provider: .google)
        XCTAssertEqual(account.label, "Signed in")
    }

    func testFirstNameTakesOneWordOnly() {
        // Matches TeacherProfileStore.firstName: "Hi Ms. Rivera", not
        // "Hi Ms. Rivera Thompson".
        let account = AnchorAccount(
            uid: "u1", email: nil, displayName: "Ms. Rivera Thompson", provider: .google
        )
        XCTAssertEqual(account.firstName, "Ms.")
    }

    func testFirstNameIsNilForABlankName() {
        let account = AnchorAccount(uid: "u1", email: nil, displayName: "  ", provider: .google)
        XCTAssertNil(account.firstName)
    }

    // MARK: - State

    func testUnknownIsNotResolvedAndNotSignedIn() {
        // The distinction the onboarding gate depends on: at launch Firebase
        // has not reported yet, and treating that as signed-out would flash a
        // sign-up screen at a teacher who is already signed in.
        XCTAssertFalse(AccountState.unknown.isResolved)
        XCTAssertFalse(AccountState.unknown.isSignedIn)
        XCTAssertNil(AccountState.unknown.account)
    }

    func testSignedOutIsResolved() {
        XCTAssertTrue(AccountState.signedOut.isResolved)
        XCTAssertFalse(AccountState.signedOut.isSignedIn)
    }

    func testSignedInCarriesTheAccount() {
        let account = AnchorAccount(uid: "u9", email: "a@b.c", displayName: "A", provider: .password)
        let state = AccountState.signedIn(account)

        XCTAssertTrue(state.isResolved)
        XCTAssertTrue(state.isSignedIn)
        XCTAssertEqual(state.account?.uid, "u9")
    }

    // MARK: - Errors

    func testOnlyNotConfiguredIsASetupProblem() {
        // Drives whether ErrorNotice offers the support-mail button, which is
        // for whoever packaged the build rather than the teacher using it.
        XCTAssertTrue(AccountError.notConfigured.isSetupProblem)

        for error in [AccountError.wrongPassword, .invalidEmail, .weakPassword,
                      .networkUnavailable, .emailAlreadyInUse, .noSuchAccount,
                      .tooManyAttempts, .cancelled] {
            XCTAssertFalse(error.isSetupProblem, "\(error) should not be a setup problem")
        }
    }

    func testCancellationIsRecognisedSoItNeverShowsARedBanner() {
        XCTAssertTrue(AccountError.cancelled.isCancellation)
        XCTAssertFalse(AccountError.wrongPassword.isCancellation)
        XCTAssertFalse(AccountError.googleSignInFailed("boom").isCancellation)
    }

    func testEveryErrorHasATeacherFacingDescription() {
        // No case may fall through to an empty string: AccountStep joins
        // description and recovery suggestion, and an empty description
        // produces a banner that says only "Try again."
        let errors: [AccountError] = [
            .notConfigured, .emailAlreadyInUse, .invalidEmail, .weakPassword,
            .wrongPassword, .noSuchAccount, .networkUnavailable, .tooManyAttempts,
            .cancelled, .googleSignInFailed("detail"), .unknown("detail")
        ]
        for error in errors {
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.trimmed.isEmpty, "\(error) has no description")
        }
    }

    // MARK: - ID token claims

    /// Builds a JWT-shaped string whose payload is `json`, base64url encoded
    /// with the padding stripped exactly as a real token has it.
    private func makeToken(payload json: String) -> String {
        var encoded = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        while encoded.hasSuffix("=") { encoded.removeLast() }
        return "header.\(encoded).signature"
    }

    func testClaimsReadsEmailAndName() {
        let token = makeToken(payload: #"{"email":"rivera@school.org","name":"Ms. Rivera"}"#)
        let claims = GoogleIdentityClient.claims(fromIDToken: token)

        XCTAssertEqual(claims["email"] as? String, "rivera@school.org")
        XCTAssertEqual(claims["name"] as? String, "Ms. Rivera")
    }

    func testClaimsDecodeAtEveryPaddingLength() {
        // The actual bug this file exists for. Payload lengths whose base64
        // encoding needs one or two '=' characters are the ones that break, and
        // which of those you hit depends on how long the signed-in teacher's
        // email address happens to be.
        for padding in 0..<4 {
            let filler = String(repeating: "x", count: padding)
            let token = makeToken(payload: #"{"email":"a@b.co","name":"N\#(filler)"}"#)
            let claims = GoogleIdentityClient.claims(fromIDToken: token)

            XCTAssertEqual(
                claims["name"] as? String, "N\(filler)",
                "payload with \(padding) filler characters failed to decode"
            )
        }
    }

    func testClaimsReturnEmptyForAMalformedToken() {
        // Must degrade to "no name" rather than trapping: nothing is authorised
        // from these claims, so an unreadable token is a cosmetic loss only.
        XCTAssertTrue(GoogleIdentityClient.claims(fromIDToken: "not-a-jwt").isEmpty)
        XCTAssertTrue(GoogleIdentityClient.claims(fromIDToken: "one.two").isEmpty)
        XCTAssertTrue(GoogleIdentityClient.claims(fromIDToken: "a.!!!!.c").isEmpty)
        XCTAssertTrue(GoogleIdentityClient.claims(fromIDToken: "").isEmpty)
    }

    // MARK: - Scopes

    func testIdentitySignInAsksForOpenIDAndNoClassroomScope() {
        // Two guarantees in one assertion, and both are load-bearing.
        //
        // `openid` missing means Google returns no id_token at all and Firebase
        // has nothing to verify — the failure GoogleIdentitySignIn names
        // explicitly because every downstream symptom points at Firebase.
        //
        // A Classroom scope creeping in here would mean a teacher creating an
        // account is asked to hand over their roster before they have one, and
        // would invalidate the separate Classroom grant they may already hold.
        XCTAssertTrue(GoogleIdentityConfig.scopes.contains("openid"))
        XCTAssertTrue(GoogleIdentityConfig.scopes.contains("email"))

        for scope in GoogleIdentityConfig.scopes {
            XCTAssertFalse(
                scope.contains("classroom"),
                "identity sign-in must not request the Classroom scope \(scope)"
            )
        }
    }
}
