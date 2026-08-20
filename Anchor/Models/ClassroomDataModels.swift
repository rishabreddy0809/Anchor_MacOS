//
//  ClassroomDataModels.swift
//  Anchor
//
//  Google Classroom domain models, the wire DTOs they decode from, and the
//  per-student academic rollup the dashboard reads.
//
//  Naming: everything here is prefixed `Classroom…` and refers to *Google
//  Classroom*. The unprefixed `Classroom` type in Classroom.swift is Anchor's
//  own grouping of recorded Zoom sessions — a different thing entirely, and the
//  two are deliberately never mixed.
//
//  Privacy: grades and student names live in memory and in the Keychain-backed
//  token only. Nothing here is Codable *to disk* — `AcademicSnapshot` is not
//  written into the session archive, so a term of grades never lands in
//  session-archive.json. See GoogleClassroomService for the retention rules.
//

import Foundation

// MARK: - Course

/// A Google Classroom course the teacher owns.
struct ClassroomCourse: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var section: String?
    var enrollmentCode: String?
    var courseState: String?
    /// True when the signed-in account is enrolled in this class rather than
    /// teaching it. Google only lets a student read their *own* submissions, so
    /// a roster and a class-wide missing-work count are not available — the UI
    /// says so instead of showing an empty roster as fact.
    var enrolledAsStudent: Bool = false

    var displayName: String {
        guard let section, !section.isEmpty else { return name }
        return "\(name) · \(section)"
    }

    var isActive: Bool { (courseState ?? "ACTIVE") == "ACTIVE" }
}

// MARK: - Student

/// An enrolled student. `email` is the identifier Anchor prefers to match on;
/// display name is the fallback for when Zoom reports no email at all — see
/// `AcademicMatchTable`.
struct ClassroomStudent: Identifiable, Hashable, Sendable {
    let id: String                 // Classroom user id
    var name: String
    /// Requires the classroom.profile.emails scope. Nil when Google withholds it.
    var email: String?

    /// Normalised key used to match against a Zoom participant.
    var matchKey: String? {
        guard let email, !email.trimmed.isEmpty else { return nil }
        return "email:" + email.trimmed.lowercased()
    }

    /// The weaker key, used only when Zoom supplies no email. Nil when the name
    /// normalises to nothing to match on.
    var nameMatchKey: String? { ClassroomNameKey.make(name) }

    /// The key an academic snapshot is filed and looked up under.
    ///
    /// Email where there is one, normalised name otherwise. This exists because
    /// Anchor stopped requesting `classroom.profile.emails` on 2026-08-17, so
    /// `matchKey` is now nil for every roster entry on a normal install — and
    /// everything that filed or fetched a snapshot by `matchKey` alone was
    /// therefore about to return nothing at all. The academic columns are ~74%
    /// of the model's weight, so "nothing at all" is not a degraded mode, it is
    /// the feature switched off.
    ///
    /// Note this is deliberately *not* a claim of identity. `AcademicMatchTable`
    /// still decides whether a link is `.verified` or `.byName`, still refuses
    /// ambiguous names outright, and the UI still labels an unverified match as
    /// unverified. This key only says where the rollup is stored.
    var rosterKey: String? { matchKey ?? nameMatchKey }
}

/// Normalises a display name enough that Zoom and Classroom can agree on it.
///
/// Zoom display names are whatever the student typed: "jane doe", "Jane Doe
/// (she/her)", "Jane  Doe.". Classroom's is whatever the school directory holds.
/// Case, punctuation and parenthetical asides are noise; the words are the name.
nonisolated enum ClassroomNameKey {

    static func make(_ raw: String) -> String? {
        var stripped = ""
        var depth = 0

        // Drop bracketed asides — pronouns, class periods, "(parent)".
        for character in raw {
            switch character {
            case "(", "[": depth += 1
            case ")", "]": depth = max(0, depth - 1)
            default:
                guard depth == 0 else { continue }
                if character.isLetter || character.isWhitespace {
                    stripped.append(character)
                } else if character == "'" || character == "-" || character == "’" {
                    stripped.append(character)
                } else {
                    // Punctuation and digits become separators rather than
                    // vanishing, so "Doe,Jane" doesn't collapse into one word.
                    stripped.append(" ")
                }
            }
        }

        let words = stripped.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        return words.joined(separator: " ")
    }

    /// The name carried inside a `name:` identity key, normalised the same way.
    /// Nil for identity keys that carry an account identity instead.
    static func make(identityKey: String) -> String? {
        let prefix = "name:"
        guard identityKey.hasPrefix(prefix) else { return nil }
        return make(String(identityKey.dropFirst(prefix.count)))
    }
}

/// Which roster entries Anchor cannot tie to a Zoom participant on its own, and
/// why.
///
/// ── Why this is a type rather than a `filter` at the call site ──────────────
///
/// It used to be one: `monitoredRoster.filter { $0.matchKey == nil }`, feeding
/// a count that a note in Settings displays. That predicate was written when
/// Google still returned roster addresses and `matchKey` was nil for the odd
/// student. **Anchor dropped `classroom.profile.emails` on 2026-08-17, so
/// `matchKey` is now nil for every entry** — and the count silently became the
/// whole class.
///
/// The number is not the damage. The sentence it drives is: *"N student(s) on
/// this roster have no email address from Google, so they can't be matched to a
/// Zoom participant. Their coursework won't affect any score."* On a normal
/// install that told every teacher, about every student, two things that are
/// false. Name matching is the ordinary path now and it works; their coursework
/// does reach their score. It is the first thing shown after connecting
/// Classroom, which makes it the worst place in the app to be wrong.
///
/// Both rules are pure and static so they can be tested without a view model,
/// a Google grant or a MainActor — the `CredentialSeed` shape, for the same
/// reason: the defect was in a decision, and decisions are testable where
/// published properties are not.
nonisolated enum RosterMatchability {

    /// Entries with nothing to match on at all: no address *and* no name that
    /// normalises to anything. These are genuinely unreachable — a manual link
    /// is the only route, and even that needs the teacher to recognise them.
    static func unmatchable(in roster: [ClassroomStudent]) -> [ClassroomStudent] {
        roster.filter { $0.rosterKey == nil }
    }

    /// Entries that could only be matched by name, where more than one student
    /// normalises to that name.
    ///
    /// `AcademicMatchTable` refuses these on purpose — a wrong match shows one
    /// student's grades under another's name — so they need the teacher to link
    /// them by hand. Counted separately from `unmatchable` because the fix is
    /// different: this one is a two-click recovery, that one is not.
    ///
    /// An entry with an address is excluded even when its name collides: the
    /// address decides, and a shared name cannot unmake it.
    static func ambiguouslyNamed(in roster: [ClassroomStudent]) -> [ClassroomStudent] {
        var owners: [String: [ClassroomStudent]] = [:]
        for student in roster where student.matchKey == nil {
            guard let key = student.nameMatchKey else { continue }
            if !owners[key, default: []].contains(where: { $0.id == student.id }) {
                owners[key, default: []].append(student)
            }
        }
        return owners.values.filter { $0.count > 1 }.flatMap { $0 }
    }
}

// MARK: - Assignment

/// One piece of coursework.
struct ClassroomAssignment: Identifiable, Hashable, Sendable {
    let id: String
    var courseID: String
    var title: String
    var dueDate: Date?
    var maxPoints: Double?
    var workType: String?
    var creationTime: Date?

    /// Only past-due work can be "missing" — an assignment set for next Friday
    /// says nothing about a student today.
    func isPastDue(now: Date = Date()) -> Bool {
        guard let dueDate else { return false }
        return dueDate < now
    }
}

// MARK: - Submission

/// One student's submission for one assignment.
struct ClassroomSubmission: Identifiable, Hashable, Sendable {
    /// Mirrors Google's `SubmissionState`.
    enum State: String, Hashable, Sendable {
        case unspecified = "SUBMISSION_STATE_UNSPECIFIED"
        case created = "CREATED"
        case new = "NEW"
        case turnedIn = "TURNED_IN"
        case returned = "RETURNED_TO_STUDENT"
        case reclaimed = "RECLAIMED_BY_STUDENT"

        /// Work the student has actually handed in.
        var isSubmitted: Bool { self == .turnedIn || self == .returned }
    }

    let id: String
    var courseID: String
    var assignmentID: String
    /// Classroom user id of the student.
    var userID: String
    var state: State
    var isLate: Bool
    /// Teacher-assigned grade. Nil when ungraded — never treated as zero.
    var assignedGrade: Double?
    var updateTime: Date?

    /// Grade as a 0...1 fraction of the assignment's maximum.
    func fraction(maxPoints: Double?) -> Double? {
        guard let assignedGrade, let maxPoints, maxPoints > 0 else { return nil }
        return min(1, max(0, assignedGrade / maxPoints))
    }
}

// MARK: - Graded work

/// One graded assignment, retained per student.
///
/// The aggregate `averageGrade` answers "how is this student doing"; this
/// answers "how did they do *on photosynthesis*", which is the question a live
/// transcript makes askable. Titles are kept because they are the only thing
/// Classroom gives Anchor to match a topic against — Google has no notion of an
/// assignment's subject.
struct GradedWork: Identifiable, Hashable, Sendable {
    /// The assignment id.
    let id: String
    var title: String
    /// 0...1 fraction of the assignment's maximum.
    var fraction: Double
    /// Due date where there is one, else when it was set — used to order work
    /// and to tell the teacher how long ago it was.
    var date: Date
    var isLate: Bool

    var scoreDisplay: String { "\(Int((fraction * 100).rounded()))%" }
}

// MARK: - Per-student rollup

/// What Anchor actually reads at scoring time: one student's academic standing
/// in the monitored course.
///
/// Every field is Optional-or-counted rather than defaulted, for the same reason
/// the Zoom signals are: a course with no graded work yet must read as "no
/// grade information", not as "this student is failing".
struct AcademicSnapshot: Hashable, Sendable {
    /// Classroom user id.
    var studentID: String
    var name: String
    /// Optional since 2026-08-17, when Anchor stopped requesting
    /// `classroom.profile.emails`. On a normal install this is now always nil —
    /// it stays in the type because a Workspace deployment that grants the scope
    /// separately would still populate it, and because "we were not told" is a
    /// state the UI shows rather than hides.
    var email: String?

    /// Past-due assignments with nothing turned in.
    var missingAssignments: [ClassroomAssignment]
    /// Turned in, but after the due date.
    var lateCount: Int
    /// Assignments graded so far.
    var gradedCount: Int
    /// Mean grade as 0...1 across all graded work. Nil when nothing is graded.
    var averageGrade: Double?
    /// Change between the earlier and more recent halves of graded work, in
    /// 0...1 units. Negative means grades are falling. Nil when there isn't
    /// enough graded work to compare.
    var gradeTrend: Double?
    /// Most recent submission of any kind.
    var lastSubmission: Date?
    /// Total assignments in the course that are past due.
    var pastDueCount: Int
    /// The itemised graded work behind `averageGrade` and `gradedCount`.
    ///
    /// Defaulted so every existing construction site keeps compiling; the rollup
    /// fills it in. Read by TopicMatcher, and by nothing that writes to disk —
    /// see the privacy note at the top of this file.
    var gradedWork: [GradedWork] = []

    var missingCount: Int { missingAssignments.count }

    /// True when Classroom had nothing useful to say about this student — no
    /// graded work and nothing overdue. Used to avoid rendering an academic
    /// panel that is entirely blank.
    var isEmpty: Bool {
        missingCount == 0 && gradedCount == 0 && lateCount == 0
    }

    // MARK: Display

    var averageGradeDisplay: String {
        guard let averageGrade else { return "—" }
        return "\(Int((averageGrade * 100).rounded()))%"
    }

    /// "−12%" / "+4%" / "—"
    var gradeTrendDisplay: String {
        guard let gradeTrend else { return "—" }
        let points = Int((gradeTrend * 100).rounded())
        if points == 0 { return "No change" }
        return points > 0 ? "+\(points)%" : "\(points)%"
    }

    var lastSubmissionDisplay: String {
        guard let lastSubmission else { return "Nothing submitted" }
        let days = Calendar.current.dateComponents(
            [.day],
            from: lastSubmission,
            to: Date()
        ).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }

    var daysSinceSubmission: Int? { daysSinceSubmission(asOf: Date()) }

    /// The same figure against a caller-supplied clock.
    ///
    /// `AcademicEscalation` takes an injectable `now` so its rules can be
    /// reasoned about and tested at a fixed moment. That injection was silently
    /// doing nothing: the one time-dependent rule it has — "nothing submitted in
    /// N days" — reached this property, which read `Date()` directly. So the
    /// escalation could not be tested against a fixed clock however the caller
    /// constructed it. The parameter is the fix; the property above keeps every
    /// other call site unchanged.
    func daysSinceSubmission(asOf now: Date) -> Int? {
        guard let lastSubmission else { return nil }
        return max(0, Calendar.current.dateComponents(
            [.day],
            from: lastSubmission,
            to: now
        ).day ?? 0)
    }

    // MARK: Combining

    /// Folds another class's rollup for the same student into this one.
    ///
    /// Used only where the question is about the person rather than the class —
    /// "is this student behind on work", asked of a meeting Anchor can't tie to
    /// a single course. Per-course screens read the per-course rollup, so a
    /// class card never reports another class's missing work as its own.
    func combined(with other: AcademicSnapshot) -> AcademicSnapshot {
        var result = self
        result.missingAssignments = missingAssignments + other.missingAssignments
        // Concatenated rather than merged on id: two courses never share an
        // assignment id, and a topic match wants every class's work on the
        // subject, not just the class that happened to sync last.
        result.gradedWork = gradedWork + other.gradedWork
        result.lateCount = lateCount + other.lateCount
        result.gradedCount = gradedCount + other.gradedCount
        result.pastDueCount = pastDueCount + other.pastDueCount
        result.averageGrade = Self.weightedMean(
            (averageGrade, gradedCount),
            (other.averageGrade, other.gradedCount)
        )
        // Trends aren't averageable across courses in any meaningful way; the
        // one backed by more graded work is the more trustworthy reading.
        result.gradeTrend = other.gradedCount > gradedCount
            ? (other.gradeTrend ?? gradeTrend)
            : (gradeTrend ?? other.gradeTrend)
        result.lastSubmission = [lastSubmission, other.lastSubmission].compactMap { $0 }.max()
        return result
    }

    /// Weighted by how much graded work each mean rests on, so a class with two
    /// graded assignments doesn't swing a class with twenty.
    private static func weightedMean(
        _ lhs: (value: Double?, weight: Int),
        _ rhs: (value: Double?, weight: Int)
    ) -> Double? {
        switch (lhs.value, rhs.value) {
        case (nil, nil): return nil
        case (let value?, nil): return value
        case (nil, let value?): return value
        case (let left?, let right?):
            let leftWeight = Double(max(1, lhs.weight))
            let rightWeight = Double(max(1, rhs.weight))
            return (left * leftWeight + right * rightWeight) / (leftWeight + rightWeight)
        }
    }

    /// One-line summary for the dashboard row, or nil when there's nothing to say.
    var headline: String? {
        var parts: [String] = []
        if missingCount > 0 {
            parts.append("\(missingCount) missing assignment\(missingCount == 1 ? "" : "s")")
        }
        if let gradeTrend, gradeTrend <= -0.05 {
            parts.append("grades \(gradeTrendDisplay)")
        }
        if parts.isEmpty, lateCount > 0 {
            parts.append("\(lateCount) late submission\(lateCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Wire DTOs

/// Decoded straight from the Classroom REST API. Kept separate from the domain
/// models above so a change in Google's payload shape stays in one place.
enum ClassroomDTO {

    struct CourseList: Decodable {
        var courses: [Course]?
        var nextPageToken: String?
    }

    struct Course: Decodable {
        var id: String
        var name: String?
        var section: String?
        var enrollmentCode: String?
        var courseState: String?
    }

    struct StudentList: Decodable {
        var students: [Student]?
        var nextPageToken: String?
    }

    struct Student: Decodable {
        var userId: String?
        var profile: Profile?
    }

    struct Profile: Decodable {
        var id: String?
        var name: Name?
        var emailAddress: String?
    }

    struct Name: Decodable {
        var fullName: String?
        var givenName: String?
        var familyName: String?
    }

    struct CourseWorkList: Decodable {
        var courseWork: [CourseWork]?
        var nextPageToken: String?
    }

    struct CourseWork: Decodable {
        var id: String
        var courseId: String?
        var title: String?
        var maxPoints: Double?
        var workType: String?
        var creationTime: Date?
        var dueDate: DueDate?
        var dueTime: DueTime?
    }

    /// Google splits the deadline across two objects, both optional and both in
    /// the course's local time zone.
    struct DueDate: Decodable {
        var year: Int?
        var month: Int?
        var day: Int?
    }

    struct DueTime: Decodable {
        var hours: Int?
        var minutes: Int?
    }

    struct SubmissionList: Decodable {
        var studentSubmissions: [Submission]?
        var nextPageToken: String?
    }

    struct Submission: Decodable {
        var id: String
        var courseId: String?
        var courseWorkId: String?
        var userId: String?
        var state: String?
        var late: Bool?
        var assignedGrade: Double?
        var updateTime: Date?
    }

    struct APIError: Decodable {
        struct Body: Decodable {
            var code: Int?
            var message: String?
            var status: String?
        }
        var error: Body?
    }
}

// MARK: - Errors

enum ClassroomError: LocalizedError, Equatable {
    case notConnected
    case missingClientID
    case authorizationCancelled
    case authorizationFailed(String)
    case tokenExpired
    case insufficientScope(String?)
    case rateLimited(retryAfter: TimeInterval?)
    case network(String)
    case decoding(String)
    case server(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Google Classroom isn't connected."
        case .missingClientID:
            "Anchor hasn't been set up to connect to Google Classroom."
        case .authorizationCancelled:
            "Sign-in was cancelled."
        case .authorizationFailed(let reason):
            "Google sign-in failed: \(reason)"
        case .tokenExpired:
            "The Google sign-in has expired."
        case .insufficientScope(let scope):
            scope.map { "Google Classroom access is missing the \($0) scope." }
                ?? "Google Classroom access is missing a required scope."
        case .rateLimited:
            "Google Classroom is rate limiting Anchor."
        case .network(let message):
            "Couldn't reach Google Classroom: \(message)"
        case .decoding(let detail):
            "Unexpected response from Google Classroom: \(detail)"
        case .server(let status, let message):
            // Google's own messages usually end in a full stop ("The service is
            // currently unavailable."), so appending another produced ".." on
            // screen. Only punctuate when Google didn't.
            "Google Classroom returned \(status)"
                + (message.map { ": \($0.trimmed)" } ?? "")
                + ((message?.trimmed.hasSuffix(".") ?? false) ? "" : ".")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notConnected:
            "Open Settings → Google Classroom to connect."
        case .missingClientID:
            "This copy of Anchor is missing part of its Google setup. It isn't something you can fix from here."
        case .tokenExpired, .authorizationFailed:
            "Reconnect Google Classroom in Settings."
        case .insufficientScope:
            "Anchor wasn't granted everything it needs to read Classroom. Reconnecting and "
                + "ticking every box Google offers usually fixes it."
        case .rateLimited:
            "Anchor will retry automatically."
        default:
            nil
        }
    }

    /// True where the teacher reading this cannot be the one to fix it.
    /// See `ZoomError.isSetupProblem` for the reasoning; the two enums answer
    /// the same question so the views can treat them alike.
    ///
    /// `.insufficientScope` is deliberately *not* here. Unlike the Zoom one it
    /// has a real teacher-side remedy — Google shows a per-permission consent
    /// screen and un-ticking a box produces exactly this error — so it keeps an
    /// instruction rather than a support link.
    var isSetupProblem: Bool {
        switch self {
        case .missingClientID:
            true
        case .notConnected, .authorizationCancelled, .authorizationFailed, .tokenExpired,
             .insufficientScope, .rateLimited, .network, .decoding, .server:
            false
        }
    }

    /// Carried into the support mail rather than shown. See
    /// `ZoomError.technicalDetail`.
    var technicalDetail: String? {
        switch self {
        case .missingClientID:
            "OAuthClientDefaults.googleClientID resolved empty, and no Keychain override is set."
        case .insufficientScope(let scope):
            "Missing scope \(scope ?? "(unnamed)"). Grant under APIs & Services → "
                + "OAuth consent screen → Data access, then disconnect and reconnect."
        default:
            nil
        }
    }

    /// Errors that will never fix themselves — stop syncing and wait for the
    /// teacher rather than burning quota.
    var requiresUserAction: Bool {
        switch self {
        case .notConnected, .missingClientID, .tokenExpired,
             .authorizationFailed, .authorizationCancelled, .insufficientScope:
            true
        default:
            false
        }
    }
}
