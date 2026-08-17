//
//  MeetingRolesTests.swift
//  AnchorTests
//
//  Who gets scored at all.
//
//  Everything the FeatureCalculator tests pin happens *after* this decision, and
//  this one fails in two directions with very different symptoms. Score someone
//  who isn't a student and the error announces itself: the bot never speaks,
//  never unmutes and never turns a camera on, so it sinks straight to the top of
//  the "most disengaged" list and sits there on every refresh. Drop someone who
//  *is* a student and nothing announces anything — they are simply absent from
//  the dashboard, and a teacher has no way to notice a child who was never shown
//  to them.
//
//  So the asymmetry runs through these tests: a participant Anchor cannot
//  identify is a student. Filtering is only ever done on positive evidence —
//  the SDK saying "this is us", an address that matches, a host flag — and never
//  on the absence of it.
//
//  The two paths differ in what evidence exists at all. The Meeting SDK reports
//  roles and an `isSelf` flag; REST reports neither, so on that path the bot is
//  recognised only by the name it joined under and the teacher only by identity
//  matching. Both are covered here, because a pilot on a plan without the
//  participant scopes runs entirely on the poorer one.
//

import XCTest
@testable import Anchor

final class MeetingRolesTests: XCTestCase {

    // MARK: Fixtures

    private func participant(
        id: String = "p1",
        userID: String? = nil,
        name: String = "Ada Lovelace",
        email: String? = nil,
        accountUserID: String? = nil,
        isHost: Bool? = nil,
        isSelf: Bool? = nil
    ) -> ZoomParticipant {
        ZoomParticipant(
            id: id,
            userID: userID,
            name: name,
            email: email,
            isInMeeting: true,
            accountUserID: accountUserID,
            isHost: isHost,
            isSelf: isSelf
        )
    }

    /// The shape of a REST-only session: a host address off the meeting record
    /// and the connected teacher's account, and no in-meeting roles at all.
    private func roles(
        hostEmail: String? = nil,
        hostAccountID: String? = nil,
        teacherEmail: String? = nil,
        teacherName: String? = nil,
        botName: String? = nil
    ) -> MeetingRoles {
        MeetingRoles(
            hostEmail: hostEmail,
            hostAccountID: hostAccountID,
            teacherEmail: teacherEmail,
            teacherName: teacherName,
            botName: botName
        )
    }

    // MARK: - The bot

    func testTheSDKsOwnAnswerIdentifiesTheBot() {
        // `isSelf` is only ever set by the bot's own client, so it means exactly
        // "this is us" and needs no corroboration from the name.
        let role = roles().role(of: participant(name: "Something Else Entirely", isSelf: true))

        XCTAssertEqual(role, .anchorBot)
    }

    func testTheBotIsRecognisedBeforeTheHostCheckRuns() {
        // Ordering, and it is load-bearing. The bot is also the client reporting
        // the roster, and in a meeting it happens to host it would read as the
        // teacher — which sounds harmless until the teacher's own row goes
        // missing from a dashboard they are looking at.
        let role = roles().role(of: participant(isHost: true, isSelf: true))

        XCTAssertEqual(role, .anchorBot)
    }

    func testOnRestTheBotIsKnownOnlyByTheNameItJoinedUnder() {
        // REST reports no `isSelf` and no role, so the join name is the only
        // evidence there is. This is the path a pilot without the participant
        // scopes runs on.
        let role = roles().role(
            of: participant(name: MeetingRoles.botDisplayName, isSelf: nil)
        )

        XCTAssertEqual(role, .anchorBot)
    }

    func testZoomsDisambiguatingSuffixStillMatchesTheBot() {
        // Zoom appends a suffix when a display name is already taken in the
        // call, which is why the name is matched as a prefix rather than for
        // equality. A second Anchor in the room must not start being scored.
        let role = roles().role(
            of: participant(name: "\(MeetingRoles.botDisplayName) (1)")
        )

        XCTAssertEqual(role, .anchorBot)
    }

    func testAStudentCalledAnchorIsNotTheBot() {
        // The false positive that would silently remove a real child from the
        // dashboard. The bot's join name carries a parenthetical precisely so a
        // student's first name cannot collide with it, and prefix matching runs
        // in the direction that keeps that true: the participant's name must
        // start with the bot's, not the other way round.
        XCTAssertEqual(roles().role(of: participant(name: "Anchor")), .student)
        XCTAssertEqual(roles().role(of: participant(name: "Anchor Patel")), .student)
    }

    func testAShortCustomBotNameCanSwallowAStudentWhoSharesItsPrefix() {
        // Documented rather than fixed, because it is a property of the name a
        // deployment chooses rather than of this code. `botName` is matched as a
        // prefix, so a bot joining as plain "Anchor" *will* claim a student
        // called "Anchor Patel" and remove them from the roster with no trace on
        // screen. The shipped default avoids it by being long and parenthesised;
        // anything overriding it needs to be too.
        let shortName = roles(botName: "Anchor")

        XCTAssertEqual(shortName.role(of: participant(name: "Anchor Patel")), .anchorBot)
        XCTAssertEqual(
            MeetingRoles.botDisplayName, "Anchor (engagement assistant)",
            "The shipped default is what keeps the case above hypothetical"
        )
    }

    func testAnUnnamedParticipantIsNotMatchedAgainstTheBot() {
        // An empty name must not prefix-match its way into being the bot, which
        // is what an unguarded `hasPrefix("")` would do to every anonymous
        // participant in the call.
        XCTAssertEqual(roles().role(of: participant(name: "")), .student)
        XCTAssertEqual(roles().role(of: participant(name: "   ")), .student)
    }

    // MARK: - The teacher

    func testTheHostFlagIsEnoughOnItsOwn() {
        XCTAssertEqual(roles().role(of: participant(isHost: true)), .teacher)
    }

    func testTheHostAddressFromTheMeetingRecordIdentifiesTheTeacher() {
        let session = roles(hostEmail: "rivera@school.edu")
        let role = session.role(of: participant(email: "Rivera@School.edu"))

        XCTAssertEqual(role, .teacher, "Addresses are compared case-insensitively")
    }

    func testTheConnectedTeacherIsFoundInAClassSomebodyElseScheduled() {
        // The normal shape of a co-taught or admin-scheduled class: the teacher
        // is in the call without hosting it, so the meeting's host fields point
        // at someone else entirely and only the connected account matches.
        let session = roles(hostEmail: "admin@school.edu", teacherEmail: "rivera@school.edu")
        let role = session.role(of: participant(email: "rivera@school.edu"))

        XCTAssertEqual(role, .teacher)
    }

    func testAVerifiedAddressThatMatchesNobodySettlesItAsAStudent() {
        // The subtle one. A student who happens to share the teacher's display
        // name — a family member in the same class, a duplicated roster entry —
        // must not be filtered out on the strength of that name when Zoom has
        // already told us their address, and it isn't the teacher's. A verified
        // address is stronger evidence than a display name, so it ends the
        // question rather than falling through to a weaker check.
        let session = roles(teacherEmail: "rivera@school.edu", teacherName: "Maria Rivera")
        let role = session.role(
            of: participant(name: "Maria Rivera", email: "maria.rivera.jr@school.edu")
        )

        XCTAssertEqual(role, .student)
    }

    func testTheAccountIdIsComparedButTheInMeetingIdIsNot() {
        // `hostID` is an account-level id and the in-meeting participant id is a
        // different number space, so the two are never compared. They can
        // collide by accident, and a collision here would filter a real student
        // off the dashboard for having drawn the wrong number.
        let session = roles(hostAccountID: "acct-9000")

        XCTAssertEqual(
            session.role(of: participant(accountUserID: "acct-9000")),
            .teacher
        )
        XCTAssertEqual(
            session.role(of: participant(userID: "acct-9000", accountUserID: nil)),
            .student,
            "An in-meeting id that happens to equal the host's account id proves nothing"
        )
    }

    func testTheTeachersNameIsTheLastResortWhenZoomWithholdsAddresses() {
        // The common case: Zoom reports no addresses at all, so the connected
        // teacher's display name is all that is left. Normalised the same way
        // roster matching normalises names, so honorifics, punctuation and
        // bracketed pronouns don't defeat it.
        let session = roles(teacherName: "Ms. Rivera")

        XCTAssertEqual(session.role(of: participant(name: "Ms Rivera (she/her)")), .teacher)
    }

    func testAnUnknownParticipantIsAStudent() {
        // The direction this whole type errs in. No role, no address, no
        // account, no name match — and the answer is still "student", because
        // the alternative is a child who is never shown to their teacher.
        XCTAssertEqual(roles().role(of: participant()), .student)

        let session = roles(
            hostEmail: "rivera@school.edu",
            hostAccountID: "acct-9000",
            teacherEmail: "rivera@school.edu",
            teacherName: "Maria Rivera"
        )
        XCTAssertEqual(session.role(of: participant(name: "Grace Hopper")), .student)
    }

    func testAnUnknownRoleIsNotTreatedAsAHost() {
        // `isHost` is Optional for the same reason the engagement signals are:
        // REST doesn't report it. Nil must not read as true — that would empty
        // the dashboard — and it must not read as a *positive* "not the teacher"
        // either, which is why the checks below it still run.
        let session = roles(teacherEmail: "rivera@school.edu")

        XCTAssertEqual(session.role(of: participant(isHost: nil)), .student)
        XCTAssertEqual(
            session.role(of: participant(email: "rivera@school.edu", isHost: nil)),
            .teacher
        )
    }

    // MARK: - The roster the dashboard actually sees

    func testOnlyStudentsSurviveTheFilter() {
        // The end-to-end shape of a real call: a teacher, the bot, and three
        // children. Everything downstream — the counts, the archive, the recap —
        // reads this list, so they all agree only if this does.
        let session = roles(teacherEmail: "rivera@school.edu")
        let everyone = [
            participant(id: "p1", name: "Ms. Rivera", email: "rivera@school.edu"),
            participant(id: "p2", name: MeetingRoles.botDisplayName, isSelf: true),
            participant(id: "p3", name: "Ada Lovelace"),
            participant(id: "p4", name: "Grace Hopper"),
            participant(id: "p5", name: "Katherine Johnson")
        ]

        let students = session.students(from: everyone)

        XCTAssertEqual(students.map(\.id), ["p3", "p4", "p5"])
    }

    func testAnEmptyCallProducesAnEmptyRosterRatherThanAFailure() {
        XCTAssertTrue(roles().students(from: []).isEmpty)
    }

    func testTheOrderTheCallReportedIsPreserved() {
        // The dashboard sorts by score, but a stable input order is what keeps
        // equal scores from shuffling between refreshes in front of a teacher.
        let everyone = (1...5).map { participant(id: "p\($0)", name: "Student \($0)") }

        XCTAssertEqual(
            roles().students(from: everyone).map(\.id),
            ["p1", "p2", "p3", "p4", "p5"]
        )
    }
}
