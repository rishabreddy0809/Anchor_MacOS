//
//  ModelRoutingTests.swift
//  AnchorTests
//
//  Which of the two models scores a given student.
//
//  Anchor ships two: a 16-feature model for a student matched in Google
//  Classroom or Canvas, and an 11-feature engagement-only model for everyone
//  else. The routing between them is the part most able to be wrong without
//  anybody noticing, because *either* model returns a plausible number for any
//  input. There is no crash, no empty state, no log line at the point of use —
//  a mis-routed student simply gets a score built partly from values nobody
//  measured, and it looks exactly like a score built from evidence.
//
//  The specific hazard: the five academic columns have benign defaults.
//  `grade_average` sits at 80 and `grade_trend` at 100 for a student Classroom
//  never matched, because those are what a student in good standing looks like
//  and something had to be put there. Handed to the 16-feature model, whose
//  weight sits mostly on exactly those columns, they read as evidence that the
//  student is fine. That is the zero-versus-unknown distinction `ObservedSignals`
//  protects everywhere else in the pipeline, arriving at the model boundary.
//

import XCTest
@testable import Anchor

final class ModelRoutingTests: XCTestCase {

    private typealias Kind = StruggleDetectionService.ModelKind

    private func route(
        academic: Bool,
        academicAvailable: Bool = true,
        engagementAvailable: Bool = true
    ) -> Kind? {
        StruggleDetectionService.modelKind(
            hasAcademicSignals: academic,
            academicAvailable: academicAvailable,
            engagementAvailable: engagementAvailable
        )
    }

    // MARK: Both models present — the shipping case

    func testAMatchedStudentIsScoredWithTheAcademicModel() {
        XCTAssertEqual(route(academic: true), .academic)
    }

    func testAnUnmatchedStudentIsScoredWithTheEngagementModel() {
        // The whole reason the second model exists. This student's academic
        // columns are defaults rather than readings, and the 16-feature model
        // cannot tell the difference.
        XCTAssertEqual(route(academic: false), .engagement)
    }

    func testTwoStudentsInTheSameClassCanRouteDifferently() {
        // The reason this is decided per prediction and not once at launch.
        // Classroom matching runs on normalised display names since the
        // `classroom.profile.emails` scope was dropped, so within one connected
        // class some students match and some do not.
        XCTAssertEqual(route(academic: true), .academic)
        XCTAssertEqual(route(academic: false), .engagement)
    }

    // MARK: Only one model bundled

    func testWithNoAcademicModelAMatchedStudentFallsBackRatherThanGoingUnscored() {
        // The engagement model ignores the academic columns rather than reading
        // them, which is the safe direction: it scores what it can see, and
        // `AcademicEscalation` is still live to supply the rest.
        XCTAssertEqual(route(academic: true, academicAvailable: false), .engagement)
    }

    func testWithNoEngagementModelAnUnmatchedStudentIsStillScored() {
        // The degraded case, and it is a deliberate trade rather than an
        // oversight: this student will be scored partly off in-good-standing
        // defaults, which is precisely what the split exists to prevent. A
        // degraded score still beats no score, and the load path logs that the
        // engagement model is missing so the cause is findable.
        XCTAssertEqual(route(academic: false, engagementAvailable: false), .academic)
    }

    func testAnEmptyBundleRoutesNowhere() {
        // Callers fall back to StruggleScoreCalculator, which says so on screen
        // rather than inventing a number.
        XCTAssertNil(route(academic: true, academicAvailable: false, engagementAvailable: false))
        XCTAssertNil(route(academic: false, academicAvailable: false, engagementAvailable: false))
    }

    // MARK: The signal the routing reads

    func testRoutingFollowsObservedAcademicRatherThanTheValuesThemselves() {
        // `hasAcademicSignals` is `observed.contains(.academic)` — whether the
        // numbers were *measured*, not whether they look plausible. A vector
        // carrying the in-good-standing defaults and no observation flag is the
        // exact shape that must not reach the academic model, and it is
        // indistinguishable from a real reading by value alone.
        var unmatched = StruggleFeatures()
        XCTAssertEqual(unmatched.gradeAverage, 80, "the default, not a measurement")
        XCTAssertEqual(unmatched.gradeTrend, 100)
        XCTAssertFalse(unmatched.hasAcademicSignals)

        var matched = unmatched
        matched.observed.insert(.academic)

        XCTAssertEqual(
            route(academic: unmatched.hasAcademicSignals), .engagement,
            "identical values, no observation — must not reach the academic model"
        )
        XCTAssertEqual(route(academic: matched.hasAcademicSignals), .academic)
    }

    func testAClassroomMatchWithNoGradedWorkStillCountsAsAcademic() {
        // `.academic` says Classroom matched this student and returned
        // coursework; `.grades` says the course has graded work. A brand-new
        // course sets the first and not the second, and that is still a real
        // observation — missing counts and submission dates are measured even
        // when nothing is marked yet.
        var features = StruggleFeatures()
        features.applyClassroomFeatures(
            FeatureCalculator.extractClassroomFeatures(
                from: AcademicSnapshot(
                    studentID: "s1", name: "Ada", email: nil,
                    missingAssignments: [], lateCount: 0, gradedCount: 0,
                    averageGrade: nil, gradeTrend: nil,
                    lastSubmission: nil, pastDueCount: 0
                )
            )
        )

        XCTAssertTrue(features.hasAcademicSignals)
        XCTAssertFalse(features.observed.contains(.grades))
        XCTAssertEqual(route(academic: features.hasAcademicSignals), .academic)
    }
}
