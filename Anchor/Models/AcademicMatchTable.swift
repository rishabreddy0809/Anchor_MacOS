//
//  AcademicMatchTable.swift
//  Anchor
//
//  Resolves a Zoom identity into a Classroom roster entry and its academic
//  snapshot.
//
//  Two ways in, and the difference between them is reported rather than hidden:
//
//  * **Verified** — Zoom gave an email address and it is on the roster. This is
//    proof of identity and the only match the escalation rules can rely on
//    without caveat.
//  * **By name** — no addresses were available to compare, so the display name
//    is matched against the roster instead. That happens when Zoom reported no
//    email (the macOS Meeting SDK never does, and Zoom's Dashboard API
//    withholds it for participants outside your account), or when Google
//    withheld the roster's addresses. Only an *unambiguous* name matches: two
//    students who normalise to the same name both drop out of the table rather
//    than one of them being picked. The UI labels this match as unverified
//    everywhere it appears.
//
//  A name never overrides an address. Two addresses that disagree mean two
//  people, however alike the names look.
//
//  A pure value type on purpose: the scorer runs off the main actor and must not
//  reach back into ClassroomViewModel to ask a question mid-pass.
//

import Foundation

nonisolated struct AcademicMatchTable: Sendable {

    /// How a Zoom participant was tied to a roster entry.
    enum Match: Hashable, Sendable {
        case verified(ClassroomStudent)
        case byName(ClassroomStudent)
        /// The teacher said so — see ManualRosterLinks.
        case manual(ClassroomStudent)

        var student: ClassroomStudent {
            switch self {
            case .verified(let student), .byName(let student), .manual(let student): student
            }
        }

        /// True only when an email address proved the identity.
        var isVerified: Bool {
            if case .verified = self { return true }
            return false
        }

        /// True when a person asserted this link rather than Anchor deriving it.
        var isManual: Bool {
            if case .manual = self { return true }
            return false
        }

        /// Whether the UI should warn about this link. A teacher who picked the
        /// student off their own roster doesn't need to be told Anchor guessed —
        /// it didn't.
        var needsCaveat: Bool {
            if case .byName = self { return true }
            return false
        }
    }

    private var byEmail: [String: ClassroomStudent] = [:]
    private var byName: [String: ClassroomStudent] = [:]
    private var overrides: [String: ClassroomStudent] = [:]
    private var snapshotsByRosterKey: [String: AcademicSnapshot] = [:]

    /// The empty table — no Classroom connection, no course selected. Every
    /// lookup returns nil, which is what makes Zoom-only scoring the default.
    init() {}

    init(
        roster: [ClassroomStudent],
        snapshots: [String: AcademicSnapshot],
        /// Identity key → Classroom student id, as recorded by the teacher.
        manualLinks: [String: String] = [:]
    ) {
        snapshotsByRosterKey = snapshots

        let rosterByID = Dictionary(
            roster.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // A link to someone who has since left the course is dropped rather than
        // carried as a dangling id.
        overrides = manualLinks.compactMapValues { rosterByID[$0] }

        for student in roster {
            guard let key = student.matchKey else { continue }
            byEmail[key] = student
        }

        // Ambiguous names are removed outright. A wrong match shows one
        // student's grades under another's name, which is worse than showing no
        // grades at all — so a collision loses both entries, not one.
        var ambiguous: Set<String> = []
        for student in roster {
            guard let key = student.nameMatchKey else { continue }
            if let existing = byName[key], existing.id != student.id {
                ambiguous.insert(key)
            } else {
                byName[key] = student
            }
        }
        for key in ambiguous { byName.removeValue(forKey: key) }
    }

    /// The roster entry for a Zoom identity key, and how it was found.
    ///
    /// `name` is the participant's Zoom display name. Pass it whenever it is to
    /// hand: an identity key only carries a name when Zoom gave *no* account
    /// identity at all, and the case that matters most — a Meeting SDK
    /// participant, whose key is the meeting-local `user:16778240` — is not
    /// that case. Without the name those participants can never match.
    ///
    /// The address decides wherever there is one on both sides. An email that
    /// matches links the student outright and a name that disagrees can't
    /// unmake it; an email that *doesn't* match blocks the link outright and a
    /// name that agrees can't rescue it — two people sharing a name is ordinary,
    /// and the address is the thing that tells them apart. The name is only ever
    /// consulted where no addresses were available to compare.
    ///
    /// A link the teacher recorded by hand outranks both routes, including a
    /// matching address. They can see both people and Anchor can't, and the
    /// override exists precisely for the cases the derived rules refuse — a
    /// name shared by two students, or an account that belongs to a sibling.
    func match(forIdentity identityKey: String, name: String? = nil) -> Match? {
        let nameKey = nameKey(forIdentity: identityKey, name: name)

        if let student = overrides[identityKey] ?? nameKey.flatMap({ overrides["name:" + $0] }) {
            return .manual(student)
        }

        let candidate = nameKey.flatMap { byName[$0] }

        guard identityKey.hasPrefix("email:") else {
            // Zoom gave no address at all — a Meeting SDK participant, a guest,
            // a phone dial-in. Nothing to contradict the name.
            return candidate.map(Match.byName)
        }

        if let student = byEmail[identityKey] { return .verified(student) }

        // Zoom named an address and the roster doesn't hold it. If the roster
        // entry this name points at has an address of its own, the two
        // disagree and that settles it — a personal Zoom account belonging to
        // someone else's brother is exactly this shape.
        //
        // The one exception is a roster Google gave no address for: there is no
        // second address, so there is nothing to disagree with, and refusing
        // here would blank the whole class for teachers whose grant withheld
        // the profile-email scope.
        guard let candidate, candidate.matchKey == nil else { return nil }
        return .byName(candidate)
    }

    /// The normalised name to match on: the display name where we have it,
    /// otherwise whatever the identity key carries.
    private func nameKey(forIdentity identityKey: String, name: String?) -> String? {
        name.flatMap { ClassroomNameKey.make($0) }
            ?? ClassroomNameKey.make(identityKey: identityKey)
    }

    /// The keys a manual link for this participant may be filed under, most
    /// specific first. Shared with the writer so the two always agree.
    static func linkKeys(forIdentity identityKey: String, name: String?) -> [String] {
        var keys = [identityKey]
        if let nameKey = name.flatMap({ ClassroomNameKey.make($0) })
            ?? ClassroomNameKey.make(identityKey: identityKey) {
            let key = "name:" + nameKey
            if key != identityKey { keys.append(key) }
        }
        return keys
    }

    /// The academic rollup for a Zoom identity, by either route.
    ///
    /// Nil when the student isn't matched, and also when they are matched but
    /// coursework hasn't synced — the caller distinguishes those with `match`.
    func snapshot(forIdentity identityKey: String, name: String? = nil) -> AcademicSnapshot? {
        guard let key = match(forIdentity: identityKey, name: name)?.student.rosterKey else {
            return nil
        }
        return snapshotsByRosterKey[key]
    }

    var isEmpty: Bool { byEmail.isEmpty && byName.isEmpty && overrides.isEmpty }
}
