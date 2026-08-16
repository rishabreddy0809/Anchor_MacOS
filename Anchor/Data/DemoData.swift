//
//  DemoData.swift
//  Anchor
//
//  A fixed, fabricated classroom used to photograph the app for the website.
//
//  WHY THIS IS DEBUG-ONLY
//
//  This file manufactures students, grades and struggle scores out of nothing.
//  That is exactly the shape of data Anchor exists to report truthfully, so a
//  build a teacher runs must not be able to produce it under any circumstance —
//  not behind a hidden setting, not behind a launch flag someone could copy out
//  of a support thread. `#if DEBUG` means the code is not compiled into the
//  Release build at all, so there is no path to it in anything shipped.
//
//  Screenshots are therefore taken from a Debug build. The UI layer is
//  identical between configurations; only optimisation and assertions differ.
//
//  Every name here is invented. No real student, teacher, school or course
//  appears in this file, and nothing in it is derived from a real session.
//
//  Usage:
//      ANCHOR_DEMO_DATA=1 ./Anchor.app/Contents/MacOS/Anchor
//

#if DEBUG

import Foundation

enum DemoData {

    /// True when this launch should show the fabricated classroom.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["ANCHOR_DEMO_DATA"] == "1"
    }

    /// Which screen to open on, from `ANCHOR_DEMO_VIEW`.
    ///
    /// Driving this from the environment rather than clicking through the UI
    /// keeps screenshots reproducible and avoids needing Accessibility
    /// permission to script the interface.
    ///
    ///   overview  the class dashboard (default)
    ///   student   the highest-risk student's detail view
    ///   settings  the integrations pane
    ///   insights  the Insights grid, every student ranked by coursework
    ///   history   one student's drill-down: engagement timeline, speaking
    ///             time against the class, and suggested actions
    ///   home      the classes dashboard: live class, Classroom courses,
    ///             recent recorded sessions
    ///   popover   the menu bar dashboard, opened for capture
    enum View: String {
        case overview, student, settings, insights, history, home, popover
    }

    static var view: View {
        guard isEnabled,
              let raw = ProcessInfo.processInfo.environment["ANCHOR_DEMO_VIEW"],
              let parsed = View(rawValue: raw)
        else { return .overview }
        return parsed
    }

    /// The highest-risk student's id, for pre-selecting the detail view.
    ///
    /// Stable because `students` is a `static let`, so this is the same UUID the
    /// store was seeded with. Reading it at `@State` initialisation avoids the
    /// race that `.onAppear` lost: a TabView builds its children before the tab
    /// is switched, so the selection was being set and then discarded.
    static var topStudentID: UUID? {
        students.max(by: { $0.struggleScore < $1.struggleScore })?.id
    }

    /// The lesson the live-coach panel is working from.
    ///
    /// Without one the popover shows "Listening for the topic — or set it
    /// yourself", which is an honest empty state and a poor advertisement: the
    /// panel's whole point is what it does once it *has* a topic.
    static let topic = ClassTopic(
        topic: "Quadratic equations",
        questionLabel: "Question 4",
        questionText: "Solve x² − 5x + 6 = 0 by factoring",
        concepts: ["factoring", "roots", "quadratics"],
        capturedAt: minutesAgo(6),
        source: .foundationModel
    )

    /// The roster id the Insights drill-down opens on.
    ///
    /// Maya rather than the top-ranked card: she is the silent-and-behind case
    /// the timeline reads best on, climbing from green to red across the term.
    static var historyStudentID: String? {
        roster.first { $0.name == "Maya Whitfield" }?.id
    }

    /// The invented teacher shown in Settings.
    ///
    /// Overriding this matters: the Settings pane otherwise renders the real
    /// signed-in Google account, and these screenshots go on a public web page.
    /// A capture is not the place to publish anybody's address.
    static let teacherName = "Jordan Alvarez"
    static let teacherEmail = "j.alvarez@example.edu"

    private static func minutesAgo(_ minutes: Int) -> Date {
        Date().addingTimeInterval(-Double(minutes) * 60)
    }

    private static func daysAgo(_ days: Int) -> Date {
        Date().addingTimeInterval(-Double(days) * 86_400)
    }

    // MARK: - Meeting

    /// `let`, not a computed property: these are read more than once per
    /// launch (the delayed re-assert in AppDelegate calls loadDemoData again),
    /// and a computed property minted a new UUID each time — which silently
    /// invalidated the sidebar selection and bounced the detail view back to
    /// the class overview mid-capture. Lazy `static let` fixes both the ids
    /// and the relative timestamps to their first evaluation.
    static let meeting: Meeting = Meeting(
            title: "Algebra II — Period 3",
            platform: .zoom,
            isLive: true,
            startedAt: minutesAgo(38),
            participantCount: 6,
            hostName: "Jordan Alvarez"
    )

    // MARK: - Assignments

    private static func assignment(_ title: String, dueDaysAgo: Int) -> ClassroomAssignment {
        ClassroomAssignment(
            id: "demo-\(title.hashValue)",
            courseID: "demo-course",
            title: title,
            dueDate: daysAgo(dueDaysAgo),
            maxPoints: 100,
            workType: "ASSIGNMENT",
            creationTime: daysAgo(dueDaysAgo + 7)
        )
    }


    // MARK: - Long-term history (Insights tab)
    //
    // Insights reads from Google Classroom (for the roster and coursework
    // standing) and from SessionArchive (for "has Anchor actually seen this
    // student in a recorded session"). Both have to be seeded or the tab
    // renders its empty state.
    //
    // Twelve sessions over six weeks, two a week, matching the pilot's "teach
    // two live classes a week" shape. Each student's `trend` walks toward the
    // score they hold today, so the history explains the present rather than
    // contradicting it.

    static let courseID = "demo-course"

    static let course = ClassroomCourse(
        id: courseID,
        name: "Algebra II",
        section: "Period 3",
        enrollmentCode: nil,
        courseState: "ACTIVE"
    )

    static let roster: [ClassroomStudent] = students.map { student in
        ClassroomStudent(
            id: "roster-\(student.name)",
            name: student.name,
            email: student.academic?.email
        )
    }

    /// Keyed by `ClassroomStudent.matchKey`, which is what InsightsView looks up.
    static let courseSnapshots: [String: AcademicSnapshot] = {
        var byKey: [String: AcademicSnapshot] = [:]
        for student in students {
            guard let snapshot = student.academic,
                  let key = ClassroomStudent(
                      id: "roster-\(student.name)", name: student.name, email: snapshot.email
                  ).matchKey
            else { continue }
            byKey[key] = snapshot
        }
        return byKey
    }()

    static let archiveClassroom = Classroom(
        id: UUID(uuidString: "D3E70000-0000-4000-8000-000000000001")!,
        zoomMeetingID: "820 1234 5678",
        zoomTopic: "Algebra II — Period 3",
        customName: nil,
        googleCourseID: courseID,
        createdAt: daysAgo(44)
    )

    /// Twelve recorded sessions, **newest first** — the order SessionArchive
    /// stores them in, and the one HomeView relies on when it takes
    /// `sessions.prefix(6)` for "Recent sessions". Each student's score walks
    /// from where they started toward today's reading.
    static let archiveSessions: [ClassSession] = {
        let count = 12
        return (0..<count).map { index in
            // Two classes a week, working backwards from three days ago.
            let daysBack = 3 + (count - 1 - index) * 3
            let progress = Double(index) / Double(count - 1)

            let records: [StudentSessionRecord] = students.map { student in
                // Start nearer the middle of the range and converge on today's
                // score, so an improving student improves and a sliding one
                // slides rather than every line being flat.
                let start = 0.35 + (student.struggleScore - 0.35) * 0.15
                let score = start + (student.struggleScore - start) * progress
                let wobble = (Double((index * 7 + student.name.count) % 5) - 2) * 0.012
                let final = min(0.97, max(0.02, score + wobble))

                return StudentSessionRecord(
                    identityKey: student.identityKey,
                    name: student.name,
                    finalScore: final,
                    peakScore: min(0.98, final + 0.06),
                    averageScore: max(0.01, final - 0.03),
                    confidence: student.confidence,
                    scoreSource: "model",
                    speakingSeconds: student.metrics.speakingSeconds,
                    chatMessages: student.metrics.chatMessages,
                    handRaiseCount: student.features?.handRaiseCount ?? 0,
                    cameraOnRatio: student.metrics.cameraOnRatio,
                    minutesPresent: 38,
                    lastStatus: student.status.rawValue,
                    trend: [final - 0.05, final - 0.02, final]
                )
            }

            return ClassSession(
                classroomID: archiveClassroom.id,
                instanceKey: "demo-instance-\(index)",
                topic: "Algebra II — Period 3",
                startedAt: daysAgo(daysBack),
                endedAt: daysAgo(daysBack).addingTimeInterval(38 * 60),
                lastSampledAt: daysAgo(daysBack).addingTimeInterval(38 * 60),
                students: records
            )
        }.reversed()
    }()

    // MARK: - Feature vectors
    //
    // These are what the model actually scores, and every `struggleScore`
    // below is the probability StudentStruggleModel_PRODUCTION returns for the
    // matching vector — not a number picked to look good. That matters twice
    // over: the detail view's "why this score" panel re-runs the model to
    // attribute the score, so an invented score would be explained by factors
    // that do not add up to it; and a screenshot claiming a capability is a
    // claim about the product.

    private static let sessionElapsed: TimeInterval = 38 * 60

    private static let fullyObserved: ObservedSignals = [
        .mute, .camera, .hand, .speaking, .audio, .chat, .academic, .grades
    ]

    private static func features(
        isMuted: Int, timeUnmuted: Int, isSpeaking: Int, speakingDuration: Int,
        cameraOn: Int, handRaised: Int, handRaiseCount: Int, messageLength: Int,
        hesitationCount: Int, hasQuestion: Int, confidenceLevel: Int,
        missingAssignments: Int, gradeAverage: Int, gradeTrend: Int,
        daysSinceSubmission: Int, lateSubmissions: Int
    ) -> StruggleFeatures {
        var f = StruggleFeatures()
        f.isMuted = isMuted
        f.timeUnmuted = timeUnmuted
        f.isSpeaking = isSpeaking
        f.speakingDuration = speakingDuration
        f.cameraOn = cameraOn
        f.handRaised = handRaised
        f.handRaiseCount = handRaiseCount
        f.messageLength = messageLength
        f.hesitationCount = hesitationCount
        f.hasQuestion = hasQuestion
        f.confidenceLevel = confidenceLevel
        f.missingAssignments = missingAssignments
        f.gradeAverage = gradeAverage
        f.gradeTrend = gradeTrend
        f.daysSinceSubmission = daysSinceSubmission
        f.lateSubmissions = lateSubmissions
        f.observed = fullyObserved
        f.meetingElapsed = sessionElapsed
        return f
    }

    // MARK: - Students
    //
    // Six students spanning the range the product is meant to distinguish:
    // one clearly struggling and quiet, one who looks fine in the room but is
    // behind on coursework (the case a Zoom-only signal set cannot see), an
    // introvert who is doing well, and three unremarkable ones. The scores are
    // the ones the shipped model actually returns for these feature vectors.

    static let students: [Student] = [
        Student(
            name: "Maya Whitfield",
            struggleScore: 0.861,
            status: .silent,
            statusSince: minutesAgo(31),
            metrics: EngagementMetrics(
                speakingSeconds: 0, chatMessages: 0, cameraOnRatio: 0,
                pollResponses: 0, pollsAsked: 3, questionsAsked: 0,
                averageResponseSeconds: 0, attentionRatio: 0.41
            ),
            trend: [0.42, 0.51, 0.63, 0.70, 0.78, 0.83, 0.861],
            activity: [
                ActivityEvent(kind: .idle, title: "No activity for 31 min", timestamp: minutesAgo(31)),
                ActivityEvent(kind: .cameraOff, title: "Camera off", timestamp: minutesAgo(34)),
                ActivityEvent(kind: .muted, title: "Muted", timestamp: minutesAgo(36)),
                ActivityEvent(kind: .joined, title: "Joined the class", timestamp: minutesAgo(38)),
            ],
            recommendations: [
                "Ask Maya a low-stakes question by name — she hasn't spoken or typed all session.",
                "Five assignments are outstanding and her average has fallen 24 points. Worth a check-in before Friday's quiz.",
            ],
            confidence: 0.92,
            scoreSource: .model,
            features: features(
                isMuted: 1, timeUnmuted: 0, isSpeaking: 0, speakingDuration: 0,
                cameraOn: 0, handRaised: 0, handRaiseCount: 0, messageLength: 0,
                hesitationCount: 0, hasQuestion: 0, confidenceLevel: 4,
                missingAssignments: 5, gradeAverage: 48, gradeTrend: 76,
                daysSinceSubmission: 21, lateSubmissions: 4
            ),
            academic: AcademicSnapshot(
                studentID: "demo-1", name: "Maya Whitfield", email: "maya.w@example.edu",
                missingAssignments: [
                    assignment("Problem Set 6 — Inequalities", dueDaysAgo: 16),
                    assignment("Problem Set 7 — Quadratics", dueDaysAgo: 9),
                    assignment("Problem Set 8 — Factoring", dueDaysAgo: 3),
                    assignment("Unit 3 Reflection", dueDaysAgo: 6),
                    assignment("Graphing Practice B", dueDaysAgo: 12),
                ],
                lateCount: 4, gradedCount: 11, averageGrade: 0.48,
                gradeTrend: -0.24, lastSubmission: daysAgo(21), pastDueCount: 6
            )
        ),
        Student(
            name: "Daniel Okonkwo",
            struggleScore: 0.613,
            status: .speaking,
            statusSince: minutesAgo(2),
            metrics: EngagementMetrics(
                speakingSeconds: 264, chatMessages: 7, cameraOnRatio: 0.97,
                pollResponses: 3, pollsAsked: 3, questionsAsked: 1,
                averageResponseSeconds: 6, attentionRatio: 0.94
            ),
            trend: [0.35, 0.38, 0.44, 0.49, 0.55, 0.58, 0.613],
            activity: [
                ActivityEvent(kind: .spoke, title: "Answered a question", detail: "34s", timestamp: minutesAgo(2)),
                ActivityEvent(kind: .question, title: "Asked about factoring", timestamp: minutesAgo(11)),
                ActivityEvent(kind: .chat, title: "Sent a message", timestamp: minutesAgo(17)),
                ActivityEvent(kind: .joined, title: "Joined the class", timestamp: minutesAgo(38)),
            ],
            recommendations: [
                "Daniel is one of the most active students in the room and five assignments behind — the gap is outside the lesson, not in it.",
                "Worth asking what's getting in the way of turning work in.",
            ],
            confidence: 0.88,
            scoreSource: .model,
            features: features(
                isMuted: 0, timeUnmuted: 420, isSpeaking: 1, speakingDuration: 264,
                cameraOn: 1, handRaised: 0, handRaiseCount: 2, messageLength: 48,
                hesitationCount: 0, hasQuestion: 1, confidenceLevel: 82,
                missingAssignments: 5, gradeAverage: 47, gradeTrend: 74,
                daysSinceSubmission: 22, lateSubmissions: 5
            ),
            academic: AcademicSnapshot(
                studentID: "demo-2", name: "Daniel Okonkwo", email: "daniel.o@example.edu",
                missingAssignments: [
                    assignment("Problem Set 5 — Systems", dueDaysAgo: 23),
                    assignment("Problem Set 6 — Inequalities", dueDaysAgo: 16),
                    assignment("Problem Set 7 — Quadratics", dueDaysAgo: 9),
                    assignment("Problem Set 8 — Factoring", dueDaysAgo: 3),
                    assignment("Unit 3 Reflection", dueDaysAgo: 6),
                ],
                lateCount: 5, gradedCount: 12, averageGrade: 0.47,
                gradeTrend: -0.26, lastSubmission: daysAgo(22), pastDueCount: 6
            )
        ),
        Student(
            name: "Tomas Lindqvist",
            struggleScore: 0.529,
            status: .cameraOff,
            statusSince: minutesAgo(12),
            metrics: EngagementMetrics(
                speakingSeconds: 58, chatMessages: 2, cameraOnRatio: 0.12,
                pollResponses: 2, pollsAsked: 3, questionsAsked: 0,
                averageResponseSeconds: 19, attentionRatio: 0.66
            ),
            trend: [0.31, 0.35, 0.39, 0.43, 0.47, 0.50, 0.529],
            activity: [
                ActivityEvent(kind: .cameraOff, title: "Camera off", timestamp: minutesAgo(12)),
                ActivityEvent(kind: .spoke, title: "Spoke briefly", detail: "12s", timestamp: minutesAgo(19)),
                ActivityEvent(kind: .joined, title: "Joined the class", timestamp: minutesAgo(37)),
            ],
            recommendations: [
                "Tomas has drifted since the camera went off — a direct question would confirm he's still with you.",
            ],
            confidence: 0.81,
            scoreSource: .model,
            features: features(
                isMuted: 1, timeUnmuted: 90, isSpeaking: 0, speakingDuration: 58,
                cameraOn: 0, handRaised: 0, handRaiseCount: 0, messageLength: 12,
                hesitationCount: 0, hasQuestion: 0, confidenceLevel: 31,
                missingAssignments: 3, gradeAverage: 66, gradeTrend: 88,
                daysSinceSubmission: 11, lateSubmissions: 2
            ),
            academic: AcademicSnapshot(
                studentID: "demo-3", name: "Tomas Lindqvist", email: "tomas.l@example.edu",
                missingAssignments: [
                    assignment("Problem Set 7 — Quadratics", dueDaysAgo: 9),
                    assignment("Problem Set 8 — Factoring", dueDaysAgo: 3),
                    assignment("Graphing Practice B", dueDaysAgo: 12),
                ],
                lateCount: 2, gradedCount: 12, averageGrade: 0.66,
                gradeTrend: -0.12, lastSubmission: daysAgo(11), pastDueCount: 6
            )
        ),
        Student(
            name: "Ethan Caldwell",
            struggleScore: 0.124,
            status: .silent,
            statusSince: minutesAgo(8),
            metrics: EngagementMetrics(
                speakingSeconds: 96, chatMessages: 3, cameraOnRatio: 0.88,
                pollResponses: 3, pollsAsked: 3, questionsAsked: 0,
                averageResponseSeconds: 11, attentionRatio: 0.89
            ),
            trend: [0.19, 0.17, 0.16, 0.15, 0.14, 0.13, 0.124],
            activity: [
                ActivityEvent(kind: .poll, title: "Responded to poll", timestamp: minutesAgo(8)),
                ActivityEvent(kind: .spoke, title: "Spoke briefly", detail: "24s", timestamp: minutesAgo(23)),
                ActivityEvent(kind: .joined, title: "Joined the class", timestamp: minutesAgo(38)),
            ],
            recommendations: [],
            confidence: 0.90,
            scoreSource: .model,
            features: features(
                isMuted: 1, timeUnmuted: 140, isSpeaking: 0, speakingDuration: 96,
                cameraOn: 1, handRaised: 0, handRaiseCount: 1, messageLength: 18,
                hesitationCount: 0, hasQuestion: 0, confidenceLevel: 61,
                missingAssignments: 0, gradeAverage: 83, gradeTrend: 99,
                daysSinceSubmission: 2, lateSubmissions: 0
            ),
            academic: AcademicSnapshot(
                studentID: "demo-4", name: "Ethan Caldwell", email: "ethan.c@example.edu",
                missingAssignments: [], lateCount: 0, gradedCount: 12,
                averageGrade: 0.83, gradeTrend: -0.01,
                lastSubmission: daysAgo(2), pastDueCount: 6
            )
        ),
        Student(
            name: "Priya Raghunathan",
            struggleScore: 0.093,
            status: .chatting,
            statusSince: minutesAgo(4),
            metrics: EngagementMetrics(
                speakingSeconds: 41, chatMessages: 14, cameraOnRatio: 1.0,
                pollResponses: 3, pollsAsked: 3, questionsAsked: 3,
                averageResponseSeconds: 4, attentionRatio: 0.98
            ),
            trend: [0.16, 0.14, 0.13, 0.12, 0.11, 0.10, 0.093],
            activity: [
                ActivityEvent(kind: .chat, title: "Answered in chat", timestamp: minutesAgo(4)),
                ActivityEvent(kind: .poll, title: "Responded to poll", timestamp: minutesAgo(9)),
                ActivityEvent(kind: .question, title: "Asked a question", timestamp: minutesAgo(21)),
                ActivityEvent(kind: .joined, title: "Joined the class", timestamp: minutesAgo(38)),
            ],
            recommendations: [],
            confidence: 0.95,
            scoreSource: .model,
            features: features(
                isMuted: 1, timeUnmuted: 60, isSpeaking: 0, speakingDuration: 41,
                cameraOn: 1, handRaised: 0, handRaiseCount: 1, messageLength: 84,
                hesitationCount: 0, hasQuestion: 1, confidenceLevel: 72,
                missingAssignments: 0, gradeAverage: 94, gradeTrend: 103,
                daysSinceSubmission: 1, lateSubmissions: 0
            ),
            academic: AcademicSnapshot(
                studentID: "demo-5", name: "Priya Raghunathan", email: "priya.r@example.edu",
                missingAssignments: [], lateCount: 0, gradedCount: 12,
                averageGrade: 0.94, gradeTrend: 0.03,
                lastSubmission: daysAgo(1), pastDueCount: 6
            )
        ),
        Student(
            name: "Aisha Bello",
            struggleScore: 0.030,
            status: .unmuted,
            statusSince: minutesAgo(6),
            metrics: EngagementMetrics(
                speakingSeconds: 173, chatMessages: 5, cameraOnRatio: 0.99,
                pollResponses: 3, pollsAsked: 3, questionsAsked: 1,
                averageResponseSeconds: 5, attentionRatio: 0.96
            ),
            trend: [0.09, 0.07, 0.06, 0.05, 0.04, 0.035, 0.030],
            activity: [
                ActivityEvent(kind: .spoke, title: "Worked through a problem", detail: "1m 12s", timestamp: minutesAgo(6)),
                ActivityEvent(kind: .poll, title: "Responded to poll", timestamp: minutesAgo(14)),
                ActivityEvent(kind: .joined, title: "Joined the class", timestamp: minutesAgo(38)),
            ],
            recommendations: [],
            confidence: 0.94,
            scoreSource: .model,
            features: features(
                isMuted: 0, timeUnmuted: 300, isSpeaking: 0, speakingDuration: 173,
                cameraOn: 1, handRaised: 0, handRaiseCount: 2, messageLength: 30,
                hesitationCount: 0, hasQuestion: 1, confidenceLevel: 88,
                missingAssignments: 0, gradeAverage: 88, gradeTrend: 106,
                daysSinceSubmission: 2, lateSubmissions: 1
            ),
            academic: AcademicSnapshot(
                studentID: "demo-6", name: "Aisha Bello", email: "aisha.b@example.edu",
                missingAssignments: [], lateCount: 1, gradedCount: 12,
                averageGrade: 0.88, gradeTrend: 0.06,
                lastSubmission: daysAgo(2), pastDueCount: 6
            )
        ),
    ]
}

#endif