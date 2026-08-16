//
//  CourseHistoryMatch.swift
//  Anchor
//
//  Ties a Google Classroom roster student to their real recorded Zoom
//  sessions in classes linked to that course. Shared by InsightsView, which
//  uses it to filter out students Anchor has never actually seen in class,
//  and CourseStudentHistoryView, which uses the same match to build the
//  student's history.
//

import Foundation

/// The identity keys a Classroom roster student's Zoom appearances might be
/// filed under: the verified email key always, plus the name key when nobody
/// else on the roster normalises to the same name — the same email-first,
/// name-as-fallback rule AcademicMatchTable uses for live scoring. Without the
/// name route, a student never verified by email on Zoom (the common case for
/// a Meeting SDK guest or a REST-only session) would never match at all.
///
/// `manualLinks` is the teacher's own identity-key → student-id map for the
/// course (`ManualRosterLinks.links(forCourse:)`), passed in rather than read
/// here so these stay free of actor isolation. It is the one route that can
/// rescue a student the derived keys miss — a Zoom account under a nickname,
/// say — and AcademicMatchTable already honours it for live scoring, so a
/// teacher who fixes a match on Home reasonably expects history to follow.
func matchIdentityKeys(
    for student: ClassroomStudent,
    roster: [ClassroomStudent],
    manualLinks: [String: String] = [:]
) -> [String] {
    var keys: [String] = []
    if let matchKey = student.matchKey { keys.append(matchKey) }
    if let nameKey = student.nameMatchKey {
        let collides = roster.contains { $0.id != student.id && $0.nameMatchKey == nameKey }
        if !collides { keys.append("name:" + nameKey) }
    }
    for (key, linkedID) in manualLinks where linkedID == student.id {
        let normalized = normalizedArchiveIdentity(key)
        if !keys.contains(normalized) { keys.append(normalized) }
    }
    return keys
}

/// An archived record's identity key, in the same shape `matchIdentityKeys`
/// produces, so the two can be compared directly.
///
/// The archive now files name-identified students under a normalised name, but
/// records written before it did hold the raw display name Zoom reported —
/// `name:jane doe (she/her)` where the roster forms `name:jane doe`. Normalising
/// both sides is what lets one term of history survive the change. Address and
/// participant-id keys carry no name and pass through untouched.
func normalizedArchiveIdentity(_ identityKey: String) -> String {
    guard let nameKey = ClassroomNameKey.make(identityKey: identityKey) else {
        return identityKey
    }
    return "name:" + nameKey
}

/// Every recorded appearance of this student across every recorded class
/// linked to this course, oldest first — several class periods can feed one
/// Classroom course, and a student's history belongs to all of them.
func recordedHistory(
    for student: ClassroomStudent,
    roster: [ClassroomStudent],
    courseID: String,
    archive: SessionArchive,
    manualLinks: [String: String] = [:]
) -> [(session: ClassSession, record: StudentSessionRecord)] {
    let keys = Set(matchIdentityKeys(for: student, roster: roster, manualLinks: manualLinks))
    guard !keys.isEmpty else { return [] }
    return archive.classrooms(forCourseID: courseID)
        .flatMap { linked in
            archive.sessions(forClassroom: linked.id).compactMap { session in
                session.students.first { keys.contains(normalizedArchiveIdentity($0.identityKey)) }
                    .map { (session, $0) }
            }
        }
        .sorted { $0.session.startedAt < $1.session.startedAt }
}

/// True when this student has attended at least one recorded session in a
/// class linked to this course — the only students there's insight to show.
func hasRecordedHistory(
    for student: ClassroomStudent,
    roster: [ClassroomStudent],
    courseID: String,
    archive: SessionArchive,
    manualLinks: [String: String] = [:]
) -> Bool {
    let keys = Set(matchIdentityKeys(for: student, roster: roster, manualLinks: manualLinks))
    guard !keys.isEmpty else { return false }
    return archive.classrooms(forCourseID: courseID).contains { linked in
        archive.sessions(forClassroom: linked.id).contains { session in
            session.students.contains { keys.contains(normalizedArchiveIdentity($0.identityKey)) }
        }
    }
}
