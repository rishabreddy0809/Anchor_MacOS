//
//  MeetingRoles.swift
//  Anchor
//
//  Decides who in a Zoom meeting is a student.
//
//  Two people in every monitored call are not: the teacher, and Anchor's own
//  bot. Scoring either is worse than useless — the bot never speaks, never
//  unmutes and never turns a camera on, so it sinks to the top of the "most
//  disengaged" list on every refresh, and the teacher is the person *reading*
//  the dashboard. Both are filtered out before anything downstream sees them, so
//  the roster, the counts, the archive and the recap all agree.
//
//  Roles come from the Meeting SDK where it can supply them, and from identity
//  matching where it can't: the REST path reports no role at all, so the host is
//  recognised by the meeting's own host fields and by the connected teacher
//  account. Anyone who matches nothing is a student — an unknown role must never
//  cause a real student to be dropped.
//

import Foundation

nonisolated struct MeetingRoles: Sendable, Equatable {

    /// The name the bot joins under. Matched as a prefix because Zoom appends a
    /// disambiguating suffix when a display name is already taken in the call.
    static let botDisplayName = BotJoinRequest.defaultDisplayName

    /// From the REST meeting record — the host's address and account id.
    var hostEmail: String?
    var hostAccountID: String?
    /// The Zoom account Anchor itself is connected with: the teacher's. This is
    /// what catches a teacher who is *in* the call without hosting it, which is
    /// the normal shape of a co-taught or admin-scheduled class.
    var teacherEmail: String?
    var teacherName: String?
    /// The name the bot actually joined under this session, when it joined.
    /// Falls back to `Self.botDisplayName`.
    var botName: String?

    init(
        hostEmail: String? = nil,
        hostAccountID: String? = nil,
        teacherEmail: String? = nil,
        teacherName: String? = nil,
        botName: String? = nil
    ) {
        self.hostEmail = hostEmail
        self.hostAccountID = hostAccountID
        self.teacherEmail = teacherEmail
        self.teacherName = teacherName
        self.botName = botName
    }

    enum Role: String, Sendable {
        case student
        case teacher
        case anchorBot = "Anchor bot"
    }

    // MARK: - Classification

    func role(of participant: ZoomParticipant) -> Role {
        // The bot first: it is also the client reporting the roster, and on a
        // meeting the bot happens to host it would otherwise read as "teacher".
        if isBot(participant) { return .anchorBot }
        if isTeacher(participant) { return .teacher }
        return .student
    }

    /// The participants the dashboard should score.
    func students(from participants: [ZoomParticipant]) -> [ZoomParticipant] {
        participants.filter { role(of: $0) == .student }
    }

    // MARK: - Bot

    private func isBot(_ participant: ZoomParticipant) -> Bool {
        // The SDK's own answer, where we have it. `isSelf` is only ever set by
        // the bot's client, so it means exactly "this is us".
        if participant.isSelf == true { return true }

        // On the REST path nothing identifies the bot but the name it joined
        // under — REST sees it as one more participant.
        let name = Self.normalized(participant.name)
        guard !name.isEmpty else { return false }
        return [botName, Self.botDisplayName]
            .compactMap { $0.map(Self.normalized) }
            .contains { !$0.isEmpty && name.hasPrefix($0) }
    }

    // MARK: - Teacher

    private func isTeacher(_ participant: ZoomParticipant) -> Bool {
        if participant.isHost == true { return true }

        if let email = participant.email?.trimmed.lowercased(), !email.isEmpty {
            if Self.matches(email, hostEmail) || Self.matches(email, teacherEmail) {
                return true
            }
            // A verified address that belongs to neither settles it: this is a
            // student, and the name check below must not overrule that.
            return false
        }

        // `hostID` is an account-level id, so it is compared against the
        // account-level id — never against the in-meeting participant id, which
        // is a different number space and could collide by accident.
        if let account = participant.accountUserID?.trimmed, !account.isEmpty,
           Self.matches(account.lowercased(), hostAccountID) {
            return true
        }

        // Last resort, for the common case where Zoom withholds addresses: the
        // teacher's own display name, normalised the same way roster matching
        // normalises names.
        guard let teacherName, let expected = ClassroomNameKey.make(teacherName),
              let actual = ClassroomNameKey.make(participant.name) else { return false }
        return expected == actual
    }

    // MARK: - Helpers

    private static func matches(_ value: String, _ candidate: String?) -> Bool {
        guard let candidate = candidate?.trimmed.lowercased(), !candidate.isEmpty else {
            return false
        }
        return value == candidate
    }

    /// Lowercased, whitespace-collapsed — enough to survive the padding Zoom
    /// display names pick up, while keeping the parenthetical that distinguishes
    /// "Anchor (engagement assistant)" from a student called Anchor.
    private static func normalized(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}

// MARK: - Tracing

extension MeetingRoles {

    /// One line naming everyone who was held back and why. Debug builds only —
    /// see AnchorDiag. Without it, "a student is missing from the dashboard" and
    /// "the teacher was correctly filtered out" look identical from the console.
    func traceExclusions(from participants: [ZoomParticipant]) {
        let excluded = participants.compactMap { participant -> String? in
            let role = role(of: participant)
            guard role != .student else { return nil }
            return "\"\(participant.name)\" → \(role.rawValue)"
        }

        AnchorDiag.logIfChanged(
            key: "roles",
            "roles: \(participants.count) participant(s), "
            + (excluded.isEmpty
                ? "none excluded"
                : "excluded \(excluded.joined(separator: ", "))")
        )
    }
}
