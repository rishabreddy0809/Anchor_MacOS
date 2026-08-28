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

// MARK: - Which account the UI names

/// Pins the two lines that tell a teacher which Google account is which.
///
/// Reported from a pilot Mac on 2026-08-27: signed in as one Google account,
/// the Settings profile card named a different one. Nothing about the sign-in
/// was wrong — the card sourced its address from `GoogleCredentialsStore`, the
/// *Classroom* grant, because it was written before Anchor had accounts. Under
/// the teacher's own name, that reads as "you are signed in as this".
@MainActor
final class AccountIdentityLabelTests: XCTestCase {

    private func google(email: String?, name: String? = nil) -> AnchorAccount {
        AnchorAccount(uid: "uid", email: email, displayName: name, provider: .google)
    }

    // MARK: - The profile card

    /// The card names the account, and only the account.
    func testProfileSubtitleIsTheAccountsOwnEmail() {
        let subtitle = AnchorAccount.profileSubtitle(for: google(email: "teacher@school.edu"))

        XCTAssertEqual(subtitle, "teacher@school.edu")
    }

    /// The defect itself, stated as the thing that must not happen: a connected
    /// Classroom address belongs to a different account and must never reach
    /// this line. `profileSubtitle` takes no connection to reach for, which is
    /// what makes that true — this case documents why the signature is narrow.
    func testProfileSubtitleCannotBeAConnectionsEmail() {
        let signedIn = "signed-in@school.edu"
        let connectedElsewhere = "other-account@gmail.com"

        let subtitle = AnchorAccount.profileSubtitle(for: google(email: signedIn))

        XCTAssertEqual(subtitle, signedIn)
        XCTAssertNotEqual(subtitle, connectedElsewhere)
    }

    /// Signed out is said plainly. It used to read "No account connected",
    /// which described a *connection* and left a signed-out teacher no wiser.
    func testProfileSubtitleSaysSoWhenNobodyIsSignedIn() {
        XCTAssertEqual(AnchorAccount.profileSubtitle(for: nil), "Not signed in")
    }

    /// Firebase can hold an account with no email — an anonymous or
    /// provider-only record. Blank under a name is worse than a plain sentence.
    func testProfileSubtitleFallsBackToTheProviderRatherThanBlank() {
        XCTAssertEqual(
            AnchorAccount.profileSubtitle(for: google(email: nil)),
            "Signed in via Google"
        )
        XCTAssertEqual(
            AnchorAccount.profileSubtitle(for: google(email: "   ")),
            "Signed in via Google"
        )
    }

    // MARK: - The Classroom card

    /// Matching accounts get the address and nothing else — no note, no noise.
    func testConnectionDetailIsBareWhenBothAccountsMatch() {
        let detail = AnchorAccount.connectionDetail(
            connected: "teacher@school.edu",
            signedInGoogleEmail: "teacher@school.edu"
        )

        XCTAssertEqual(detail, "teacher@school.edu")
    }

    /// Google addresses are case-insensitive; a difference in case is not a
    /// different account and must not be reported as one.
    func testConnectionDetailIgnoresCaseAndSurroundingSpace() {
        let detail = AnchorAccount.connectionDetail(
            connected: " Teacher@School.edu ",
            signedInGoogleEmail: "teacher@school.edu"
        )

        XCTAssertEqual(detail, " Teacher@School.edu ")
    }

    /// A genuine mismatch is legal — personal Anchor login, school Google — so
    /// it is stated rather than treated as an error. Being invisible is what
    /// made the original report so confusing.
    func testConnectionDetailSaysSoWhenTheAccountsDiffer() {
        let detail = AnchorAccount.connectionDetail(
            connected: "other-account@gmail.com",
            signedInGoogleEmail: "teacher@school.edu"
        )

        XCTAssertEqual(detail, "other-account@gmail.com — not the account you signed in with")
    }

    /// A password account has no Google identity to compare against, and its
    /// address is frequently not a Google one at all. Comparing anyway would
    /// put a mismatch note on every password account that ever connects
    /// Classroom — which is all of them.
    func testConnectionDetailDoesNotAccuseAPasswordAccount() {
        let detail = AnchorAccount.connectionDetail(
            connected: "teacher@school.edu",
            signedInGoogleEmail: AnchorAccount(
                uid: "uid",
                email: "teacher@personal.com",
                displayName: nil,
                provider: .password
            ).googleEmail
        )

        XCTAssertEqual(detail, "teacher@school.edu")
    }

    /// Nothing connected, nothing to say.
    func testConnectionDetailIsNilWhenClassroomIsNotConnected() {
        XCTAssertNil(
            AnchorAccount.connectionDetail(connected: nil, signedInGoogleEmail: "teacher@school.edu")
        )
        XCTAssertNil(
            AnchorAccount.connectionDetail(connected: "  ", signedInGoogleEmail: "teacher@school.edu")
        )
    }
}

// MARK: - Which Google account Classroom connects as

/// Pins "use the account I signed in with, and ask me when you can't".
///
/// Three requirements meet in this one rule. A teacher who signed in to Anchor
/// with Google should not have to choose an identity twice in one onboarding
/// flow. A teacher who signed in with an email and password has no Google
/// identity to pin to and must be asked. And neither may ever be handed a
/// Classroom that belongs to somebody else — which is what `prompt=consent`
/// with no picker does when Anchor has no account to pin to: Google re-consents
/// whichever account the browser is already signed into, silently.
@MainActor
final class ClassroomAccountPinningTests: XCTestCase {

    /// Signed in with Google, nothing connected yet: straight to consent for
    /// that address. No picker.
    func testGoogleAccountIsUsedWithoutAskingAgain() {
        XCTAssertFalse(
            ClassroomViewModel.forcesAccountPicker(
                signedInGoogleEmail: "teacher@school.edu",
                connectedEmail: nil
            )
        )
    }

    /// Reconnecting the same account stays pinned.
    func testReconnectingTheSameAccountStaysPinned() {
        XCTAssertFalse(
            ClassroomViewModel.forcesAccountPicker(
                signedInGoogleEmail: "teacher@school.edu",
                connectedEmail: "Teacher@School.edu "
            ),
            "Case and spacing are not a different Google account."
        )
    }

    /// A password account has no Google identity to pin to. Without the picker
    /// Google would consent as whatever the browser is signed into — the silent
    /// wrong-account grant this rule exists to prevent.
    func testPasswordAccountIsAlwaysAsked() {
        XCTAssertTrue(
            ClassroomViewModel.forcesAccountPicker(signedInGoogleEmail: nil, connectedEmail: nil)
        )
        XCTAssertTrue(
            ClassroomViewModel.forcesAccountPicker(signedInGoogleEmail: "  ", connectedEmail: nil)
        )
    }

    /// The escape hatch. A grant already held for a different address means the
    /// pin already failed once — the browser's session beat the hint. Pinning
    /// again would fail identically every time and strand the teacher, so the
    /// picker opens itself.
    func testPickerReturnsAfterAMismatchedGrant() {
        XCTAssertTrue(
            ClassroomViewModel.forcesAccountPicker(
                signedInGoogleEmail: "teacher@school.edu",
                connectedEmail: "someone-else@gmail.com"
            )
        )
    }
}
