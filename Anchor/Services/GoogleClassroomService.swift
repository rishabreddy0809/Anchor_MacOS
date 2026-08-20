//
//  GoogleClassroomService.swift
//  Anchor
//
//  Read-only Google Classroom client: courses, roster, coursework, submissions,
//  and the per-student academic rollup the scorer reads.
//
//  Shape mirrors ZoomService deliberately — an actor holding the network work,
//  with a @MainActor view model (ClassroomViewModel) owning the UI state and the
//  sync loop. Anything that already reasons about the Zoom path reads the same
//  way here.
//
//  Cost control. The whole course is fetched in one pass every 10 minutes and
//  cached, rather than per-student on every 2-minute scoring pass — polling per
//  student would be thousands of calls an hour against a quota that only looks
//  infinite.
//
//  Speed. A pass is about three requests per course, not one per assignment:
//  submissions come back through the `courseWork/-` wildcard in one paged call,
//  roster and coursework go out together, and every response is trimmed with a
//  `fields` mask. What is still fanned out — the roster load, the fallback
//  path — runs a few at a time through `ClassroomConcurrency` rather than all at
//  once, because Google's per-minute limit is the constraint that bites.
//
//  Privacy. Grades stay in memory. Nothing here is written to the session
//  archive or any other file — see `AcademicSnapshot`. `clear()` drops
//  everything when monitoring stops.
//
//  TODO(manual): needs a real teacher account to exercise. A Classroom course
//  with at least one past-due assignment and one graded assignment is required
//  to see missing counts and grade trends do anything.
//

import Combine
import Foundation
import os

// The `ClassroomDataProviding` protocol and `ClassroomConcurrency` moved to
// ClassroomDataProviding.swift on 2026-08-18 — they are the vendor-neutral
// seam, and living inside the Google client made them read as Google's.
// This type is one implementation of that protocol; a Canvas one would be
// another, and should need nothing from this file.

// MARK: - Service

actor GoogleClassroomService: ClassroomDataProviding {

    private let credentials: GoogleCredentialsStore
    private let oauth: GoogleOAuthClient
    private let session: URLSession
    private let logger = Logger(subsystem: "com.anchor.google", category: "Classroom")

    private static let baseURL = URL(string: "https://classroom.googleapis.com/v1")!
    private static let pageSize = 100
    /// Cap on pages per collection, so a pathological course can't spin forever.
    private static let maxPages = 20
    /// Submissions are the one collection counted per student *per assignment*,
    /// so the same cap that is generous for courses is not for these: 30
    /// students over 40 assignments is already 12 pages.
    private static let maxSubmissionPages = 60

    /// Coalesces concurrent token refreshes. Without it, the parallel calls a
    /// sync now makes would each see the same 401 and each spend a refresh.
    private var refreshTask: Task<Void, Error>?

    init(
        credentials: GoogleCredentialsStore = .shared,
        oauth: GoogleOAuthClient = GoogleOAuthClient(),
        session: URLSession = .shared
    ) {
        self.credentials = credentials
        self.oauth = oauth
        self.session = session
    }

    // MARK: - Endpoints

    /// The signed-in account's active courses.
    ///
    /// Teaching comes first, since that is who Anchor is for. The student
    /// fallback exists because signing in with an account that is *enrolled* in
    /// the class rather than teaching it returns a perfectly successful, empty
    /// list — which is indistinguishable, from the UI, from being connected to
    /// nothing at all. Showing those classes (flagged as such) is far better
    /// than an empty screen that looks like a broken connection.
    func courses() async throws -> [ClassroomCourse] {
        let teaching = try await courses(role: "teacherId")
        guard teaching.isEmpty else { return teaching }
        return try await courses(role: "studentId").map {
            var course = $0
            course.enrolledAsStudent = true
            return course
        }
    }

    private func courses(role: String) async throws -> [ClassroomCourse] {
        let pages: [ClassroomDTO.CourseList] = try await paged(
            path: "/courses",
            query: [
                URLQueryItem(name: role, value: "me"),
                URLQueryItem(name: "courseStates", value: "ACTIVE")
            ],
            fields: "nextPageToken,courses(id,name,section,enrollmentCode,courseState)"
        ) { $0.nextPageToken }

        return pages.flatMap { $0.courses ?? [] }.map { dto in
            ClassroomCourse(
                id: dto.id,
                name: dto.name ?? "Untitled course",
                section: dto.section,
                enrollmentCode: dto.enrollmentCode,
                courseState: dto.courseState
            )
        }
    }

    func students(courseID: String) async throws -> [ClassroomStudent] {
        let pages: [ClassroomDTO.StudentList] = try await paged(
            path: "/courses/\(courseID)/students",
            query: [],
            fields: "nextPageToken,students(userId,profile(id,emailAddress,"
                + "name(fullName,givenName,familyName)))"
        ) { $0.nextPageToken }

        return pages.flatMap { $0.students ?? [] }.compactMap { dto in
            guard let userID = dto.userId ?? dto.profile?.id else { return nil }
            return ClassroomStudent(
                id: userID,
                name: dto.profile?.name?.fullName
                    ?? [dto.profile?.name?.givenName, dto.profile?.name?.familyName]
                        .compactMap { $0 }
                        .joined(separator: " "),
                email: dto.profile?.emailAddress
            )
        }
    }

    func assignments(courseID: String) async throws -> [ClassroomAssignment] {
        let pages: [ClassroomDTO.CourseWorkList] = try await paged(
            path: "/courses/\(courseID)/courseWork",
            query: [URLQueryItem(name: "orderBy", value: "dueDate desc")],
            fields: "nextPageToken,courseWork(id,courseId,title,maxPoints,workType,"
                + "creationTime,dueDate,dueTime)"
        ) { $0.nextPageToken }

        return pages.flatMap { $0.courseWork ?? [] }.map { dto in
            ClassroomAssignment(
                id: dto.id,
                courseID: dto.courseId ?? courseID,
                title: dto.title ?? "Untitled assignment",
                dueDate: Self.dueDate(from: dto),
                maxPoints: dto.maxPoints,
                workType: dto.workType,
                creationTime: dto.creationTime
            )
        }
    }

    func submissions(courseID: String, assignmentID: String) async throws -> [ClassroomSubmission] {
        let pages: [ClassroomDTO.SubmissionList] = try await paged(
            path: "/courses/\(courseID)/courseWork/\(assignmentID)/studentSubmissions",
            query: [],
            fields: Self.submissionFields,
            maxPages: Self.maxSubmissionPages
        ) { $0.nextPageToken }

        return pages.flatMap { $0.studentSubmissions ?? [] }.compactMap {
            Self.submission(from: $0, courseID: courseID, assignmentID: assignmentID)
        }
    }

    /// Every submission in the course in one paged call.
    ///
    /// Google accepts `-` in place of a coursework id, which turns what used to
    /// be one request per assignment into one request per 100 submissions. For a
    /// 25-student, 40-assignment course that is ~10 requests instead of 40, and
    /// the pages stream back while the earlier ones are still being decoded.
    ///
    /// Falls back to the per-assignment fan-out if the wildcard is refused for
    /// any reason other than a problem that would sink both — better a slow sync
    /// than none.
    func submissions(
        courseID: String,
        assignmentIDs: [String]
    ) async throws -> [String: [ClassroomSubmission]] {
        guard !assignmentIDs.isEmpty else { return [:] }

        let wanted = Set(assignmentIDs)
        do {
            let pages: [ClassroomDTO.SubmissionList] = try await paged(
                path: "/courses/\(courseID)/courseWork/-/studentSubmissions",
                query: [],
                fields: Self.submissionFields,
                maxPages: Self.maxSubmissionPages
            ) { $0.nextPageToken }

            let all = pages.flatMap { $0.studentSubmissions ?? [] }.compactMap {
                Self.submission(from: $0, courseID: courseID, assignmentID: nil)
            }
            // Coursework the caller didn't ask about — drafts, or work created
            // between the assignments call and this one — is dropped rather than
            // rolled up against an assignment we know nothing about.
            return Dictionary(grouping: all.filter { wanted.contains($0.assignmentID) }) {
                $0.assignmentID
            }
        } catch let error as ClassroomError {
            switch error {
            case .notConnected, .tokenExpired, .missingClientID, .insufficientScope:
                throw error
            default:
                logger.warning(
                    """
                    Bulk submissions failed (\(error.localizedDescription, privacy: .public)); \
                    falling back to per-assignment fetch.
                    """
                )
            }
        }

        return try await ClassroomConcurrency.map(assignmentIDs) { id in
            (id, try await self.submissions(courseID: courseID, assignmentID: id))
        }
        .reduce(into: [:]) { $0[$1.0] = $1.1 }
    }

    /// Trimmed to what `AcademicRollup` reads. Worth doing: the full resource
    /// carries `submissionHistory` and attachment metadata, which for a busy
    /// course is most of the bytes and all of the decoding time.
    private static let submissionFields =
        "nextPageToken,studentSubmissions(id,courseId,courseWorkId,userId,state,"
        + "late,assignedGrade,updateTime)"

    private static func submission(
        from dto: ClassroomDTO.Submission,
        courseID: String,
        assignmentID: String?
    ) -> ClassroomSubmission? {
        guard let userID = dto.userId,
              let assignment = dto.courseWorkId ?? assignmentID
        else { return nil }

        return ClassroomSubmission(
            id: dto.id,
            courseID: dto.courseId ?? courseID,
            assignmentID: assignment,
            userID: userID,
            state: ClassroomSubmission.State(rawValue: dto.state ?? "") ?? .unspecified,
            isLate: dto.late ?? false,
            assignedGrade: dto.assignedGrade,
            updateTime: dto.updateTime
        )
    }

    /// Google splits a deadline into an optional date and an optional time, both
    /// in UTC. No date means no deadline, which is not the same as "due now".
    private static func dueDate(from dto: ClassroomDTO.CourseWork) -> Date? {
        guard let due = dto.dueDate,
              let year = due.year, let month = due.month, let day = due.day
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        // Google documents dueTime as UTC; a missing time means end of day.
        components.hour = dto.dueTime?.hours ?? 23
        components.minute = dto.dueTime?.minutes ?? 59
        components.timeZone = TimeZone(identifier: "UTC")

        return Calendar(identifier: .gregorian).date(from: components)
    }

    // MARK: - Request plumbing

    private func paged<T: Decodable>(
        path: String,
        query: [URLQueryItem],
        fields: String? = nil,
        maxPages: Int? = nil,
        nextToken: (T) -> String?
    ) async throws -> [T] {
        var results: [T] = []
        var pageToken: String?
        var pages = 0
        let limit = maxPages ?? Self.maxPages

        repeat {
            var items = query
            items.append(URLQueryItem(name: "pageSize", value: String(Self.pageSize)))
            if let fields { items.append(URLQueryItem(name: "fields", value: fields)) }
            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            let page: T = try await get(path: path, query: items)
            results.append(page)
            pageToken = nextToken(page)
            pages += 1
        } while !(pageToken ?? "").isEmpty && pages < limit

        return results
    }

    private func get<T: Decodable>(
        path: String,
        query: [URLQueryItem],
        isRetry: Bool = false
    ) async throws -> T {
        let token = try await accessToken()

        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw ClassroomError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClassroomError.decoding("Response was not HTTP.")
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try Self.makeDecoder().decode(T.self, from: data)
            } catch {
                throw ClassroomError.decoding("\(path): \(error.localizedDescription)")
            }

        case 400 where query.contains(where: { $0.name == "fields" }):
            // The `fields` masks are an optimisation, not a feature. If Google
            // ever rejects one, ask for the whole resource instead of letting a
            // bandwidth saving take the sync down with it.
            logger.warning("Field mask rejected for \(path, privacy: .public); refetching in full.")
            return try await get(
                path: path,
                query: query.filter { $0.name != "fields" },
                isRetry: isRetry
            )

        case 401:
            // Access token rejected — refresh once, then treat as expired.
            guard !isRetry else { throw ClassroomError.tokenExpired }
            try await forceRefresh()
            return try await get(path: path, query: query, isRetry: true)

        case 403:
            let body = try? Self.makeDecoder().decode(ClassroomDTO.APIError.self, from: data)
            let message = body?.error?.message ?? ""
            let status = body?.error?.status ?? ""

            // Google reports quota exhaustion as 403 with a distinct status.
            if status == "RESOURCE_EXHAUSTED" || message.localizedCaseInsensitiveContains("quota") {
                throw ClassroomError.rateLimited(retryAfter: nil)
            }
            // The API not being enabled on the project is also a 403, and needs
            // the opposite fix to a missing scope — don't collapse them.
            if status == "PERMISSION_DENIED",
               message.localizedCaseInsensitiveContains("has not been used in project")
                || message.localizedCaseInsensitiveContains("disabled") {
                throw ClassroomError.server(status: 403, message: message)
            }
            throw ClassroomError.insufficientScope(Self.scopeHint(for: path))

        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            // Requests now go out several at a time, so an occasional 429 is the
            // expected way to discover the ceiling rather than a failure. Wait
            // it out once here — losing a whole course's sync to one throttled
            // page would be a far worse trade than a few seconds.
            guard !isRetry else { throw ClassroomError.rateLimited(retryAfter: retryAfter) }
            try await Task.sleep(for: .seconds(min(retryAfter ?? 2, 30)))
            return try await get(path: path, query: query, isRetry: true)

        case 500, 502, 503, 504:
            // Google's own transient failures. A 503 means "try again shortly",
            // not "something is wrong with Anchor" — but without a retry here
            // the whole pass fails and the next one is a full sync interval
            // away, so a blip that lasted two seconds took the coursework panel
            // down for ten minutes. One short retry absorbs almost all of them.
            guard !isRetry else {
                let body = try? Self.makeDecoder().decode(ClassroomDTO.APIError.self, from: data)
                throw ClassroomError.server(status: http.statusCode, message: body?.error?.message)
            }
            logger.warning("\(http.statusCode, privacy: .public) from \(path, privacy: .public); retrying once")
            try await Task.sleep(for: .seconds(2))
            return try await get(path: path, query: query, isRetry: true)

        default:
            let body = try? Self.makeDecoder().decode(ClassroomDTO.APIError.self, from: data)
            throw ClassroomError.server(status: http.statusCode, message: body?.error?.message)
        }
    }

    private static func scopeHint(for path: String) -> String? {
        if path.contains("studentSubmissions") { return "classroom.student-submissions.students.readonly" }
        if path.contains("courseWork") { return "classroom.coursework.students" }
        if path.contains("students") { return "classroom.rosters.readonly" }
        if path.contains("courses") { return "classroom.courses.readonly" }
        return nil
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Tokens

    private func accessToken() async throws -> String {
        // One hop rather than two: every request pays this, and a sync now makes
        // several at a time.
        let (tokens, config) = await credentialsSnapshot()
        guard let tokens else { throw ClassroomError.notConnected }
        guard config != nil else { throw ClassroomError.missingClientID }

        if let accessToken = tokens.accessToken, !tokens.isExpired {
            return accessToken
        }

        try await forceRefresh()
        guard let refreshed = await credentialsSnapshot().0?.accessToken else {
            throw ClassroomError.tokenExpired
        }
        return refreshed
    }

    private func credentialsSnapshot() async -> (GoogleTokens?, GoogleOAuthConfig?) {
        let store = credentials
        return await MainActor.run { (store.tokens, store.config()) }
    }

    /// Refreshes once for however many callers are waiting.
    ///
    /// The parallel requests in a sync all carry the same access token, so when
    /// it expires they all see 401 at once. Without coalescing that is one
    /// refresh per in-flight request, and every one after the first spends a
    /// round trip to learn what the first already found out.
    private func forceRefresh() async throws {
        if let refreshTask {
            try await refreshTask.value
            return
        }

        let store = credentials
        let oauth = self.oauth
        let task = Task<Void, Error> {
            let snapshot = await MainActor.run { (store.tokens, store.config()) }
            guard let tokens = snapshot.0, let config = snapshot.1 else {
                throw ClassroomError.notConnected
            }
            let (accessToken, expiresAt) = try await oauth.refresh(tokens: tokens, config: config)
            await MainActor.run { store.updateAccessToken(accessToken, expiresAt: expiresAt) }
        }
        refreshTask = task

        defer { refreshTask = nil }
        try await task.value
    }
}

// MARK: - Rollup

/// Turns raw coursework and submissions into one `AcademicSnapshot` per student.
///
/// Kept separate from the network layer so it can be reasoned about — and later
/// tested — without a Google account.
nonisolated struct AcademicRollup: Sendable {

    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    func snapshots(
        students: [ClassroomStudent],
        assignments: [ClassroomAssignment],
        submissions: [String: [ClassroomSubmission]]   // keyed by assignment id
    ) -> [String: AcademicSnapshot] {
        let pastDue = assignments.filter { $0.isPastDue(now: now) }
        let assignmentsByID = Dictionary(
            assignments.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var result: [String: AcademicSnapshot] = [:]

        for student in students {
            // Filed under the roster key — email when Anchor has one, normalised
            // name otherwise.
            //
            // This used to require an email and `continue` without one, on the
            // reasoning that an unmatched student has nothing to build a
            // snapshot for. That reasoning stopped holding when Anchor dropped
            // the classroom.profile.emails scope: every roster entry lost its
            // email at once, so the guard skipped the entire roster and returned
            // an empty map — silently taking out all five academic features,
            // which carry about 74% of the model's weight.
            //
            // A student who normalises to no name at all is still skipped: there
            // is genuinely no key to file them under.
            // Named for what it holds. This binding was called `matchKey`
            // while holding a `rosterKey`, and that is not a cosmetic slip: a
            // reader who takes the name at face value concludes snapshots are
            // filed under `matchKey` and writes the lookup that way — which is
            // exactly the defect found in `CourseStudentHistoryView` on
            // 2026-08-20, silently emptying that panel on every install.
            guard let rosterKey = student.rosterKey else { continue }

            var missing: [ClassroomAssignment] = []
            var late = 0
            var graded: [(date: Date, fraction: Double)] = []
            /// The same graded work, itemised with its title so a live topic can
            /// be matched against it. Built alongside `graded` rather than from
            /// it because the mean and the trend only need the numbers.
            var gradedWork: [GradedWork] = []
            var lastSubmission: Date?

            for assignment in pastDue {
                let submission = submissions[assignment.id]?.first { $0.userID == student.id }
                guard let submission, submission.state.isSubmitted else {
                    missing.append(assignment)
                    continue
                }
                if submission.isLate { late += 1 }
            }

            // Grades are read across *all* coursework, not just past-due: work
            // graded early still says something about how the student is doing.
            for assignment in assignments {
                guard let submission = submissions[assignment.id]?.first(where: { $0.userID == student.id })
                else { continue }

                if let updated = submission.updateTime, submission.state.isSubmitted {
                    lastSubmission = max(lastSubmission ?? updated, updated)
                }

                if let fraction = submission.fraction(
                    maxPoints: assignmentsByID[assignment.id]?.maxPoints
                ) {
                    // Order by due date where possible so "trend" means over
                    // time rather than over Google's arbitrary list order.
                    let date = assignment.dueDate ?? assignment.creationTime ?? now
                    graded.append((date, fraction))
                    gradedWork.append(
                        GradedWork(
                            id: assignment.id,
                            title: assignment.title,
                            fraction: fraction,
                            date: date,
                            isLate: submission.isLate
                        )
                    )
                }
            }

            graded.sort { $0.date < $1.date }
            let fractions = graded.map(\.fraction)

            result[rosterKey] = AcademicSnapshot(
                studentID: student.id,
                name: student.name,
                email: student.email,
                missingAssignments: missing.sorted {
                    ($0.dueDate ?? .distantPast) > ($1.dueDate ?? .distantPast)
                },
                lateCount: late,
                gradedCount: fractions.count,
                averageGrade: fractions.isEmpty
                    ? nil
                    : fractions.reduce(0, +) / Double(fractions.count),
                gradeTrend: Self.trend(of: fractions),
                lastSubmission: lastSubmission,
                pastDueCount: pastDue.count,
                // Newest first: asked "how has she done on photosynthesis", the
                // most recent evidence is the evidence a teacher wants quoted.
                gradedWork: gradedWork.sorted { $0.date > $1.date }
            )
        }

        return result
    }

    /// Later half's mean minus the earlier half's.
    ///
    /// Needs at least four graded assignments: with two or three, one bad test
    /// reads as a collapsing trend, and telling a teacher a student is "down
    /// 30%" on that basis would be worse than saying nothing.
    static func trend(of fractions: [Double]) -> Double? {
        guard fractions.count >= 4 else { return nil }
        let midpoint = fractions.count / 2
        let earlier = fractions.prefix(midpoint)
        let later = fractions.suffix(fractions.count - midpoint)
        guard !earlier.isEmpty, !later.isEmpty else { return nil }

        let earlierMean = earlier.reduce(0, +) / Double(earlier.count)
        let laterMean = later.reduce(0, +) / Double(later.count)
        return laterMean - earlierMean
    }
}
