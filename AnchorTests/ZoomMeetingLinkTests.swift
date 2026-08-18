//
//  ZoomMeetingLinkTests.swift
//  AnchorTests
//
//  What a teacher actually pastes.
//
//  Almost none of these inputs are a meeting number, because almost nobody has
//  a meeting number to hand. They have the invitation their school's calendar
//  sent them, and they have it in the thirty seconds before a class starts. So
//  the fixtures here are real invitation shapes rather than tidy strings, and
//  the most important test in the file is the one about phone numbers: a Zoom
//  invitation carries a block of dial-in numbers, and "+1 312 626 6799" is
//  eleven digits once punctuation is stripped — the same length as a personal
//  meeting id. Any parser that goes looking for a plausible run of digits finds
//  a phone number in Chicago and blames the teacher for it.
//

import XCTest
@testable import Anchor

final class ZoomMeetingLinkTests: XCTestCase {

    // MARK: - Typed by hand

    func testABareNumberIsTakenAsIs() {
        let link = ZoomMeetingLink.parse("12345678900")

        XCTAssertEqual(link?.meetingNumber, "12345678900")
        XCTAssertNil(link?.passcode)
    }

    func testTheGroupingZoomShowsOnScreenIsAccepted() {
        // Zoom displays ids grouped, so a teacher reading one off their own
        // window types it grouped. Both spellings are the same meeting.
        XCTAssertEqual(ZoomMeetingLink.parse("123 4567 8900")?.meetingNumber, "12345678900")
        XCTAssertEqual(ZoomMeetingLink.parse("123-4567-8900")?.meetingNumber, "12345678900")
        XCTAssertEqual(ZoomMeetingLink.parse("  812 3456 7890  ")?.meetingNumber, "81234567890")
    }

    func testANineDigitIdIsValidToo() {
        // Older and scheduled meetings are nine or ten digits; only personal
        // meeting ids reach eleven.
        XCTAssertEqual(ZoomMeetingLink.parse("123456789")?.meetingNumber, "123456789")
        XCTAssertEqual(ZoomMeetingLink.parse("1234567890")?.meetingNumber, "1234567890")
    }

    func testSomethingTooShortOrTooLongIsNotAMeetingNumber() {
        // Rejected rather than trimmed to fit. A number of the wrong length is
        // not a meeting id with a typo in it — it is something else entirely,
        // and joining "something else" fails in a way nobody can read.
        XCTAssertNil(ZoomMeetingLink.parse("12345678"))
        XCTAssertNil(ZoomMeetingLink.parse("123456789012"))
        XCTAssertNil(ZoomMeetingLink.parse(""))
        XCTAssertNil(ZoomMeetingLink.parse("   "))
    }

    // MARK: - Join URLs

    func testAPlainJoinURL() {
        let link = ZoomMeetingLink.parse("https://zoom.us/j/12345678900")

        XCTAssertEqual(link?.meetingNumber, "12345678900")
        XCTAssertNil(link?.passcode)
    }

    func testAVanitySubdomainIsIrrelevant() {
        // Every school has its own: us02web, company.zoom.us, and so on.
        XCTAssertEqual(
            ZoomMeetingLink.parse("https://us02web.zoom.us/j/12345678900")?.meetingNumber,
            "12345678900"
        )
        XCTAssertEqual(
            ZoomMeetingLink.parse("https://oakridge.zoom.us/j/98765432100")?.meetingNumber,
            "98765432100"
        )
    }

    func testAWebinarAndAHostStartLinkBothCarryTheirNumber() {
        // `/w/` is a webinar. `/s/` is the host's own start link, which is what
        // a teacher copies when they grab the URL from their own Zoom window
        // rather than from the invitation they sent out.
        XCTAssertEqual(
            ZoomMeetingLink.parse("https://zoom.us/w/12345678900")?.meetingNumber,
            "12345678900"
        )
        XCTAssertEqual(
            ZoomMeetingLink.parse("https://zoom.us/s/12345678900")?.meetingNumber,
            "12345678900"
        )
    }

    func testTheDesktopClientDeepLink() {
        let link = ZoomMeetingLink.parse("zoommtg://zoom.us/join?confno=12345678900&pwd=aBcD1234")

        XCTAssertEqual(link?.meetingNumber, "12345678900")
        XCTAssertEqual(link?.passcode, "aBcD1234")
    }

    func testAURLPasscodeIsReadWhenThereIsNoInvitationAroundIt() {
        // A bare link is the other common paste. The `pwd=` parameter is an
        // encoded form rather than the digits a human types, but it is the only
        // thing on offer here and a passcode that might work beats none.
        let link = ZoomMeetingLink.parse("https://us02web.zoom.us/j/12345678900?pwd=aBcD.eFgH1234")

        XCTAssertEqual(link?.meetingNumber, "12345678900")
        XCTAssertEqual(link?.passcode, "aBcD.eFgH1234")
    }

    func testAPasscodeKeepsItsCaseAndStopsAtTheNextParameter() {
        // Passcodes are case-sensitive even though the parameter name is not,
        // and a trailing fragment or another parameter is not part of the value.
        let link = ZoomMeetingLink.parse(
            "https://zoom.us/j/12345678900?pwd=AbCdEf&uname=Ada#success"
        )

        XCTAssertEqual(link?.passcode, "AbCdEf")
    }

    func testAVanityPersonalRoomLinkHasNoNumberToFind() {
        // Nothing in it names a meeting id, so the honest answer is nil. This is
        // the one paste the UI has to explain rather than silently accept.
        XCTAssertNil(ZoomMeetingLink.parse("https://zoom.us/my/msrivera"))
        XCTAssertNil(ZoomMeetingLink.parse("https://us02web.zoom.us/my/oakridge.maths"))
    }

    // MARK: - The whole invitation

    /// What Outlook and Google Calendar actually hand over, dial-in block and
    /// all. Every fixture below is a variation on this.
    private let invitation = """
    Ms Rivera is inviting you to a scheduled Zoom meeting.

    Topic: Year 9 Maths — Tuesday
    Time: Sep 1, 2026 09:00 AM London

    Join Zoom Meeting
    https://us02web.zoom.us/j/81234567890?pwd=bWFwbGVzeXJ1cA

    Meeting ID: 812 3456 7890
    Passcode: 481920

    ---

    Dial by your location
            +1 312 626 6799 US (Chicago)
            +1 646 931 3860 US (New York)
            +44 203 481 5237 United Kingdom
    Meeting ID: 812 3456 7890
    Find your local number: https://us02web.zoom.us/u/kbQr3Ln
    """

    func testTheWholeInvitationParses() {
        let link = ZoomMeetingLink.parse(invitation)

        XCTAssertEqual(link?.meetingNumber, "81234567890")
    }

    func testTheLabelledPasscodeBeatsTheOneInTheURL() {
        // The invitation carries both and they are not interchangeable: `pwd=`
        // is encoded for the browser, while the digits after "Passcode:" are
        // what a client asks a human for — and what the Meeting SDK's join
        // elements expect. Taking the URL's would hand the SDK a string that
        // looks like a passcode and is refused like a wrong one.
        let link = ZoomMeetingLink.parse(invitation)

        XCTAssertEqual(link?.passcode, "481920")
        XCTAssertNotEqual(link?.passcode, "bWFwbGVzeXJ1cA")
    }

    func testADialInNumberIsNeverMistakenForTheMeeting() {
        // The test this file exists for. "+1 312 626 6799" is eleven digits with
        // the punctuation gone, exactly as long as a personal meeting id, and it
        // appears in every invitation Zoom generates. Nothing here scans free
        // text for digits, which is the only reason this passes.
        let link = ZoomMeetingLink.parse(invitation)

        XCTAssertEqual(link?.meetingNumber, "81234567890")
        XCTAssertNotEqual(link?.meetingNumber, "13126266799")
        XCTAssertNotEqual(link?.meetingNumber, "16469313860")
    }

    func testAnInvitationWithTheLinkStrippedStillWorks() {
        // Mail clients and school filters rewrite or remove URLs. The labelled
        // id is the fallback, and it has to survive the dial-in block sitting
        // right underneath it.
        let stripped = """
        Join Zoom Meeting
        [link removed by IT]

        Meeting ID: 812 3456 7890
        Passcode: 481920

        Dial by your location
                +1 312 626 6799 US (Chicago)
        """

        let link = ZoomMeetingLink.parse(stripped)

        XCTAssertEqual(link?.meetingNumber, "81234567890")
        XCTAssertEqual(link?.passcode, "481920")
    }

    func testALabelAndAPasscodeSharingOneLineDoNotRunTogether() {
        // Some clients reflow the invitation onto a single line. Accumulating
        // every digit after the label would produce a seventeen-digit number
        // that matches no meeting.
        let link = ZoomMeetingLink.parse("Meeting ID: 812 3456 7890 Passcode: 481920")

        XCTAssertEqual(link?.meetingNumber, "81234567890")
        XCTAssertEqual(link?.passcode, "481920")
    }

    func testAmericanAndBritishSpellingsOfTheLabelBothWork() {
        // Zoom says "Passcode"; older invitations and some locales say
        // "Password". A teacher forwarding a colleague's invitation may have
        // either.
        XCTAssertEqual(
            ZoomMeetingLink.parse("Meeting ID: 812 3456 7890\nPassword: hunter2")?.passcode,
            "hunter2"
        )
        XCTAssertEqual(
            ZoomMeetingLink.parse("Webinar ID: 812 3456 7890")?.meetingNumber,
            "81234567890"
        )
    }

    func testTheLabelIsMatchedWhateverItsCase() {
        XCTAssertEqual(
            ZoomMeetingLink.parse("MEETING ID: 812 3456 7890\nPASSCODE: 481920")?.meetingNumber,
            "81234567890"
        )
        XCTAssertEqual(
            ZoomMeetingLink.parse("meeting id: 812 3456 7890\npasscode: 481920")?.passcode,
            "481920"
        )
    }

    // MARK: - What the bot receives

    func testWhatComesOutIsWhatBotJoinRequestWants() {
        // The parser's output feeds straight into a join, so the two have to
        // agree about what a meeting number looks like: bare digits, no
        // grouping. `normalizedMeetingNumber` strips grouping again on its own,
        // and this pins that the parser is not relying on it to.
        let link = ZoomMeetingLink.parse(invitation)!
        let request = BotJoinRequest(
            meetingNumber: link.meetingNumber,
            passcode: link.passcode
        )

        XCTAssertEqual(request.normalizedMeetingNumber, link.meetingNumber)
        XCTAssertEqual(request.normalizedMeetingNumber, "81234567890")
        XCTAssertEqual(request.passcode, "481920")
    }
}
