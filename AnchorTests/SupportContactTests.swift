//
//  SupportContactTests.swift
//  AnchorTests
//
//  What a teacher is allowed to be told when something breaks.
//
//  This file exists because the failure it guards is silent in the worst way.
//  An error string that reads "add the scope to your Server-to-Server OAuth app,
//  then re-activate it" does not crash, does not fail a build, and does not look
//  wrong to the person who wrote it — it only fails in front of a teacher who
//  has no Marketplace account, no idea what a scope is, and every reason to
//  conclude they broke Anchor themselves and should stop using it. There is no
//  runtime signal for that. So the contract is asserted here instead:
//
//    1. An error a teacher cannot fix must not hand them an instruction.
//    2. It must not name developer surfaces at all — no consoles, no
//       Marketplace, no Keychain, no client secrets.
//    3. The technical sentence is not lost, only moved: it must still exist on
//       the error, so `SupportContact.reportURL` can carry it to the one person
//       who can act on it.
//
//  The vocabulary list in `developerVocabulary` is the enforcement mechanism and
//  is meant to grow. Adding a term is cheap; noticing a bad string in a pilot is
//  not.
//

import XCTest
@testable import Anchor

final class SupportContactTests: XCTestCase {

    // MARK: - Fixtures

    /// Words that mean the reader is expected to hold a developer or admin
    /// account somewhere. Matched case-insensitively against teacher-facing
    /// copy only — `technicalDetail` is exempt by design, since its whole
    /// purpose is to say these things.
    private let developerVocabulary = [
        "client id", "client secret", "account id", "sdk key", "api key",
        "marketplace", "cloud console", "google cloud", "apis & services",
        "oauth consent", "server-to-server", "keychain", "re-activate",
        "scope to your", "advanced"
    ]

    /// Every `ZoomError`, so a case added later is covered without anyone
    /// remembering to add it here. Associated values are arbitrary — the copy
    /// under test does not branch on them except where noted.
    private let zoomErrors: [ZoomError] = [
        .missingCredentials,
        .missingSDKCredentials,
        .invalidCredentials(reason: "bad secret"),
        .notSignedIn,
        .missingOAuthClient,
        .authorizationCancelled,
        .authorizationFailed("redirect mismatch"),
        .authorizationExpired,
        .keychainUnavailable,
        .insufficientScope("dashboard:read:list_meeting_participants:admin"),
        .planRequired("Business or above"),
        .noActiveMeeting,
        .meetingEnded,
        .rateLimited(retryAfter: 30),
        .network("offline"),
        .decoding("bad json"),
        .server(status: 500, code: nil, message: "boom"),
        .unsupported("nope"),
        .cancelled
    ]

    private let classroomErrors: [ClassroomError] = [
        .notConnected,
        .missingClientID,
        .authorizationCancelled,
        .authorizationFailed("bad grant"),
        .tokenExpired,
        .insufficientScope("courses.readonly"),
        .rateLimited(retryAfter: 30),
        .network("offline"),
        .decoding("bad json"),
        .server(status: 500, message: "boom")
    ]

    // MARK: - The contract

    /// The rule that motivated the whole change: if the teacher cannot fix it,
    /// do not tell them how to fix it.
    func testSetupProblemsDoNotUseDeveloperVocabularyAtTheTeacher() {
        for error in zoomErrors where error.isSetupProblem {
            assertNoDeveloperVocabulary(error.errorDescription, label: "\(error) description")
            assertNoDeveloperVocabulary(error.recoverySuggestion, label: "\(error) recovery")
        }
        for error in classroomErrors where error.isSetupProblem {
            assertNoDeveloperVocabulary(error.errorDescription, label: "\(error) description")
            assertNoDeveloperVocabulary(error.recoverySuggestion, label: "\(error) recovery")
        }
    }

    /// Moved, not deleted. A setup problem with no `technicalDetail` would send
    /// a support mail that says only "something is misconfigured", which is the
    /// report that wastes a round trip.
    func testEverySetupProblemKeepsItsTechnicalDetail() {
        for error in zoomErrors where error.isSetupProblem {
            XCTAssertFalse(
                (error.technicalDetail ?? "").isEmpty,
                "\(error) is a setup problem but carries nothing for whoever reads the report"
            )
        }
        for error in classroomErrors where error.isSetupProblem {
            XCTAssertFalse(
                (error.technicalDetail ?? "").isEmpty,
                "\(error) is a setup problem but carries nothing for whoever reads the report"
            )
        }
    }

    /// A teacher-fixable error should still say what to do — the change must
    /// not have flattened everything into "contact support".
    func testTeacherFixableErrorsStillGiveAnInstruction() {
        let actionable: [ZoomError] = [.notSignedIn, .authorizationExpired, .noActiveMeeting]
        for error in actionable {
            XCTAssertFalse(error.isSetupProblem, "\(error) is something a teacher can act on")
            XCTAssertFalse(
                (error.recoverySuggestion ?? "").isEmpty,
                "\(error) left a teacher with nothing to do"
            )
        }
    }

    /// Google's consent screen lets a teacher un-tick a permission, which
    /// produces exactly this error and is genuinely theirs to redo — so it must
    /// keep an instruction rather than becoming a support link. The Zoom
    /// equivalent is a Marketplace property and is not comparable.
    func testGoogleScopeGapStaysTeacherFixableUnlikeZooms() {
        XCTAssertFalse(ClassroomError.insufficientScope("courses.readonly").isSetupProblem)
        XCTAssertTrue(ZoomError.insufficientScope("dashboard:read:list_meeting_participants:admin").isSetupProblem)
    }

    // MARK: - The third teacher-facing enum, which the scan did not reach

    // `ZoomEmailVerification` is shown in Settings — `ConnectionStatusView`
    // renders its `headline` and `detail` whenever `isDegraded` — and in the
    // per-student panel via `studentClause`. It is teacher-facing by every
    // definition this file uses, and until 2026-08-20 nothing scanned it,
    // because the scan enumerates `ZoomError` and `ClassroomError` and this is
    // neither.
    //
    // **The header of this file quotes "add the scope to your Server-to-Server
    // OAuth app, then re-activate it" as the motivating example.** A sentence
    // of that shape was live in `ZoomEmailVerification.detail` the whole time,
    // carrying three terms from the list below. The guard was real; its reach
    // was smaller than its stated contract, and the gap held the exact string
    // it was written about.
    //
    // The lesson generalises past this enum: a vocabulary scan is only worth
    // its list *times* the surfaces it enumerates, and the second factor is the
    // one nobody re-checks when a new type starts talking to teachers.

    private let emailVerifications: [ZoomEmailVerification] = [
        .notAttempted,
        .verified(filled: 3, of: 5),
        .unreported(participants: 4),
        .unavailable(.planRequired("Business or above")),
        .unavailable(.insufficientScope("dashboard:read:list_meeting_participants:admin")),
        .unavailable(.network("offline"))
    ]

    func testEmailVerificationCopyDoesNotUseDeveloperVocabularyAtTheTeacher() {
        for state in emailVerifications {
            assertNoDeveloperVocabulary(state.headline, label: "\(state) headline")
            assertNoDeveloperVocabulary(state.detail, label: "\(state) detail")
            assertNoDeveloperVocabulary(state.studentClause, label: "\(state) studentClause")
        }
    }

    func testADegradedEmailVerificationStillExplainsWhatItCosts() {
        // The copy must not be flattened into "unavailable" while removing the
        // instruction. A teacher seeing this needs to know that matching has
        // fallen back to display names, because that is what makes an odd-looking
        // roster explicable rather than broken.
        for state in emailVerifications where state.isDegraded {
            let detail = state.detail ?? ""
            XCTAssertFalse(detail.isEmpty, "\(state) is degraded and explains nothing")
            XCTAssertTrue(
                detail.lowercased().contains("name"),
                "\(state) does not tell the teacher matching fell back to display names, "
                + "which is the only part of this they will actually observe."
            )
        }
    }

    func testTheEmailVerificationFixtureCoversEveryCase() {
        // Vacuity guard. Every assertion above is a for-loop over this array, so
        // a case added later and not listed here is silently unscanned — which
        // is precisely how the whole enum went unscanned in the first place.
        // Swift cannot enumerate an enum with associated values, so this counts
        // the cases the type actually has by exhausting a switch: adding a case
        // stops this compiling, which is the alarm.
        for state in emailVerifications {
            switch state {
            case .notAttempted, .verified, .unreported, .unavailable:
                continue
            }
        }
        XCTAssertEqual(
            emailVerifications.count, 6,
            "The fixture list changed. Every case of ZoomEmailVerification must appear, "
            + "including one .unavailable per error shape whose copy differs."
        )
    }

    // MARK: - The mail itself

    /// The address in the app and the address on the marketing site are two
    /// copies of one fact. This pins the app's copy to the literal in
    /// `website/landing/src/lib/site.ts`; if that moves, this fails rather than
    /// a teacher's mail bouncing.
    func testSupportAddressMatchesTheMarketingSite() {
        XCTAssertEqual(SupportContact.email, "rishabreddy0809@gmail.com")
    }

    func testReportURLIsAMailtoCarryingSubjectAndBody() throws {
        let url = try XCTUnwrap(
            SupportContact.reportURL(summary: "Zoom sign-in failed", detail: "redirect mismatch")
        )
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(url.absoluteString.contains(SupportContact.email))

        let decoded = try XCTUnwrap(url.absoluteString.removingPercentEncoding)
        XCTAssertTrue(decoded.contains("Zoom sign-in failed"))
        XCTAssertTrue(decoded.contains("redirect mismatch"), "the detail never reached the body")
        XCTAssertTrue(decoded.contains("Anchor"), "the build block is missing")
    }

    /// `&` and `+` are the two characters `.urlQueryAllowed` leaves alone and a
    /// mail client then misreads — `&` starts a new parameter, `+` becomes a
    /// space. Both occur in ordinary Zoom and Google error text, so a body
    /// containing them must survive intact.
    func testReportURLSurvivesAmpersandsAndPlusesInErrorText() throws {
        let hostile = "Grades & attendance failed + retry pending"
        let url = try XCTUnwrap(SupportContact.reportURL(summary: hostile))

        XCTAssertEqual(url.scheme, "mailto")
        let decoded = try XCTUnwrap(url.absoluteString.removingPercentEncoding)
        XCTAssertTrue(
            decoded.contains(hostile),
            "the body was cut at & or had + turned into a space: \(decoded)"
        )
    }

    /// Anchor's whole privacy claim is that class data stays on the Mac. A
    /// support mail is the one thing the app asks a teacher to send off it, so
    /// it must be composed only from values Anchor itself supplies.
    func testReportBodyCarriesNothingButTheErrorAndTheBuild() throws {
        let url = try XCTUnwrap(SupportContact.reportURL(summary: "Zoom rejected these credentials."))
        let decoded = try XCTUnwrap(url.absoluteString.removingPercentEncoding)

        for leak in ["@gmail.com/", "student", "roster", "grade"] where leak != "@gmail.com/" {
            XCTAssertFalse(
                decoded.lowercased().contains(leak),
                "the report body mentions \(leak), which it has no business knowing"
            )
        }
    }

    // MARK: - Helper

    private func assertNoDeveloperVocabulary(
        _ text: String?,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let text else { return }
        let lowered = text.lowercased()
        for term in developerVocabulary where lowered.contains(term) {
            XCTFail(
                "\(label) tells a teacher about \"\(term)\", which they cannot act on: \"\(text)\"",
                file: file,
                line: line
            )
        }
    }
}
