//
//  ClassroomDataProviding.swift
//  Anchor
//
//  The contract an LMS has to satisfy to feed Anchor's academic signal, and the
//  bounded-concurrency helper any implementation of it will want.
//
//  Extracted from `GoogleClassroomService.swift` on 2026-08-18. Nothing here
//  changed in the move — the point is where it lives, not what it says.
//
//  Why it is worth its own file. This protocol is the entire seam between
//  Anchor and *an* LMS, and while it sat inside the Google client it read as
//  Google's protocol with a general-sounding name. That has a practical cost
//  and a design cost. The practical one: a Canvas implementation would import a
//  file whose header is 30 lines about Google's quota behaviour and whose body
//  is a Google client. The design one is worse — it is genuinely hard to tell,
//  from inside that file, which of the five methods describe *Anchor's needs*
//  and which describe *Google's shape*. Naming the seam is what makes that
//  question answerable before three weeks are spent on a connector.
//
//  Five methods, and the fifth is the one that matters. `submissions(courseID:
//  assignmentIDs:)` exists because it is the whole cost of a sync: fetched one
//  assignment at a time it is N sequential round trips per course, and both
//  Google and Canvas will serve all N in one paged request. A provider without
//  a bulk endpoint still works — the default implementation below fans out in
//  parallel — but it will be the slow one, and that is a property of the
//  provider rather than of Anchor.
//
//  What this protocol deliberately does *not* include: identity. Nothing here
//  returns an email or a login. Matching a roster entry to a Zoom participant
//  happens above this layer, in `AcademicMatchTable`, because the key that
//  works differs per LMS and per institution — Google no longer returns emails
//  at all since the `classroom.profile.emails` scope was dropped, and Canvas
//  gates `email` and `sis_user_id` on permissions configured per institution
//  while documenting `login_id` as always present. A protocol that named one of
//  those would have baked in whichever LMS was implemented first. See
//  `CANVAS_SPIKE.md`.
//

import Foundation

// MARK: - The seam

protocol ClassroomDataProviding: Sendable {
    func courses() async throws -> [ClassroomCourse]
    func students(courseID: String) async throws -> [ClassroomStudent]
    func assignments(courseID: String) async throws -> [ClassroomAssignment]
    func submissions(courseID: String, assignmentID: String) async throws -> [ClassroomSubmission]

    /// Every submission in a course, keyed by assignment id.
    ///
    /// Exists as its own call because it is the whole cost of a sync: fetched
    /// one assignment at a time it is N sequential round trips, and Google will
    /// serve all N in one paged request.
    func submissions(
        courseID: String,
        assignmentIDs: [String]
    ) async throws -> [String: [ClassroomSubmission]]
}

extension ClassroomDataProviding {
    /// Fallback for providers that have no bulk endpoint — still parallel,
    /// since the per-assignment calls are independent.
    func submissions(
        courseID: String,
        assignmentIDs: [String]
    ) async throws -> [String: [ClassroomSubmission]] {
        try await ClassroomConcurrency.map(assignmentIDs) { id in
            (id, try await submissions(courseID: courseID, assignmentID: id))
        }
        .reduce(into: [:]) { $0[$1.0] = $1.1 }
    }
}

// MARK: - Bounded concurrency

/// Runs independent Classroom calls a few at a time.
///
/// Not unbounded: Google's per-minute limit is the binding constraint, and a
/// 30-way burst is exactly what trips it. Six in flight keeps a course's sync
/// inside a second or two while staying well under the ceiling.
enum ClassroomConcurrency {
    static let width = 6

    static func map<T: Sendable, R: Sendable>(
        _ items: [T],
        transform: @escaping @Sendable (T) async throws -> R
    ) async throws -> [R] {
        guard !items.isEmpty else { return [] }

        return try await withThrowingTaskGroup(of: (Int, R).self) { group in
            var results = [R?](repeating: nil, count: items.count)
            var next = 0

            // Prime the pump, then add one task per completion so no more than
            // `width` requests are ever outstanding.
            while next < min(width, items.count) {
                let index = next
                group.addTask { (index, try await transform(items[index])) }
                next += 1
            }

            while let (index, value) = try await group.next() {
                results[index] = value
                if next < items.count {
                    let index = next
                    group.addTask { (index, try await transform(items[index])) }
                    next += 1
                }
            }

            return results.compactMap { $0 }
        }
    }
}
