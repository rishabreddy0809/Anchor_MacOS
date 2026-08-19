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

    // MARK: Standing the academic rules down
    //
    // A second, separate question from routing, and the one that was wrong.
    // Routing asks "which model scores this student"; this asks "may
    // `AcademicEscalation` switch itself off". Both are phrased over a model's
    // declared columns, which is exactly why they were easy to conflate — and
    // conflating them is silent, because the rules simply stop firing and every
    // score still looks like a score.

    private func standsDown(_ columns: [String]) -> Bool {
        StruggleDetectionService.standsDownAcademicRules(declaredInputs: Set(columns))
    }

    private var engagementColumns: [String] {
        StruggleFeature.engagementFeatures.map(\.rawValue)
    }

    private var academicColumns: [String] {
        StruggleFeature.academicFeatures.map(\.rawValue)
    }

    func testAFullSixteenFeatureModelStandsTheRulesDown() {
        // The intended end state: the model's learned weights replace the
        // hand-written rules, which is what `AcademicEscalation` was built to
        // be deleted for.
        XCTAssertTrue(standsDown(engagementColumns + academicColumns))
    }

    func testAnEngagementOnlyModelLeavesTheRulesRunning() {
        // Nothing academic reaches the model, so the rules are the only path
        // academic evidence has to a score.
        XCTAssertFalse(standsDown(engagementColumns))
    }

    func testAPartialAcademicModelDoesNotStandDownRulesItCannotReplace() {
        // The defect this guard exists for. `StudentStruggleModel_CORRECTED`
        // declares 13 columns — the 11 engagement ones plus `grade_trend` and
        // `missing_assignments`. Under the old `academicModel != nil` test it
        // counted as academic and stood down all five rules, including the
        // `daysSinceSubmission >= 14` escalation it is blind to. A student two
        // weeks past due was then read by neither the model nor the rules.
        let corrected = engagementColumns + ["grade_trend", "missing_assignments"]
        XCTAssertEqual(corrected.count, 13, "pins the shape being described")
        XCTAssertFalse(
            standsDown(corrected),
            "a model blind to grade_average, days_since_submission and late_submissions must not switch off the rules that read them"
        )
    }

    func testEveryProperSubsetOfTheAcademicColumnsLeavesTheRulesRunning() {
        // Stated over every one-column-missing case rather than the single
        // 13-feature model, so a differently-partial model shipped later is
        // covered by the same guard instead of needing a new test nobody writes.
        for missing in academicColumns {
            let partial = engagementColumns + academicColumns.filter { $0 != missing }
            XCTAssertFalse(
                standsDown(partial),
                "a model missing \(missing) must leave the rules running"
            )
        }
    }

    // MARK: What is actually in the bundle
    //
    // Everything above is a statement about column sets. This is the statement
    // about the app being shipped, and nothing else in the suite makes one:
    // `Anchor/` is a synchronised Xcode group, so a model ships by existing in
    // that directory, and `candidateModelURLs` loads every `.mlmodelc` in the
    // bundle regardless of the preference list. A model can therefore be added
    // or removed without any code change to notice it.

    func testTheBundledModelsAreTheOnesThisSuiteDescribes() {
        // `Bundle.main`, not the test bundle. The tests are app-hosted
        // (`TEST_HOST` is Anchor.app), so this is the same bundle
        // `candidateModelURLs` reads — which is the point: reading anything
        // else would describe a bundle nobody ships. Written against the test
        // bundle first, where it found nothing and skipped itself into
        // permanent green.
        let urls = Bundle.main.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) ?? []
        let names = Set(urls.map { $0.deletingPathExtension().lastPathComponent })

        XCTAssertFalse(
            names.isEmpty,
            "no compiled model in the host app — every student would fall back to heuristic scoring"
        )

        XCTAssertTrue(
            names.contains("StudentStruggleModel_16"),
            "the 16-feature academic model is the one that makes standing the rules down correct"
        )
        XCTAssertTrue(
            names.contains("StudentStruggleModel_11"),
            "without the engagement model an unmatched student is scored off academic defaults"
        )

        // The end-to-end consequence, read off the real service rather than a
        // column set: with the full 16-feature model bundled, the rules are
        // expected to stand down. Asserting the *true* case as well as the
        // false ones is what stops the guard being tightened into something
        // that never lets the model take over at all — the failure mode of
        // over-correcting this defect.
        XCTAssertTrue(
            StruggleDetectionService.shared.usesAcademicFeatures,
            "a bundled 16-feature model must still switch AcademicEscalation off"
        )
    }

    // MARK: The property itself, against real models
    //
    // Everything above tests `standsDownAcademicRules` — a pure function over
    // column sets. `AcademicEscalation` does not read that function; it reads
    // `usesAcademicFeatures`, and against the shipped bundle that property
    // cannot be caught being wrong: the full 16-feature model is present and
    // wins, so the correct rule and the old broken one (`academicModel != nil`)
    // both answer true. Reverting the fix would have passed every test above.
    //
    // These load a *chosen* model set through the seam, which is the only way
    // to put the property in front of a partial model — the case it exists for.

    func testAPartialModelAloneDoesNotSwitchTheEscalationRulesOff() {
        // The defect, end to end, against the real 13-feature file that ships.
        let service = StruggleDetectionService(resourceNames: ["StudentStruggleModel_CORRECTED"])
        // Read the property first: it is what drives `loadIfNeeded`. `isReady`
        // deliberately does not, so checking readiness first reports "no model"
        // for a service that simply has not been asked anything yet.
        let standsDown = service.usesAcademicFeatures
        guard service.isReady else {
            return XCTFail("StudentStruggleModel_CORRECTED did not load; this test is asserting nothing")
        }
        XCTAssertFalse(
            standsDown,
            "a 13-feature model must leave AcademicEscalation running — it cannot see days_since_submission, and the rules are the only thing that can"
        )
    }

    func testAFullModelAloneDoesSwitchTheEscalationRulesOff() {
        // The other half, so the guard cannot be "fixed" by making the property
        // always false, which would double-count academic evidence forever.
        let service = StruggleDetectionService(resourceNames: ["StudentStruggleModel_16"])
        let standsDown = service.usesAcademicFeatures
        guard service.isReady else {
            return XCTFail("StudentStruggleModel_16 did not load; this test is asserting nothing")
        }
        XCTAssertTrue(standsDown)
    }

    func testAnEngagementOnlyBundleLeavesTheRulesRunning() {
        let service = StruggleDetectionService(resourceNames: ["StudentStruggleModel_11"])
        let standsDown = service.usesAcademicFeatures
        guard service.isReady else {
            return XCTFail("StudentStruggleModel_11 did not load; this test is asserting nothing")
        }
        XCTAssertFalse(standsDown)
    }

    func testThePartialModelIsStillPreferredForAMatchedStudent() {
        // Narrowing the stand-down rule must not have narrowed *routing* with
        // it. A matched student should still be scored by the model that reads
        // two academic columns rather than the one that reads none — the two
        // questions were split precisely so this stayed true.
        let service = StruggleDetectionService(
            resourceNames: ["StudentStruggleModel_CORRECTED", "StudentStruggleModel_11"]
        )
        let standsDown = service.usesAcademicFeatures
        guard service.isReady else {
            return XCTFail("models did not load; this test is asserting nothing")
        }

        var matched = StruggleFeatures()
        matched.observed.insert(.academic)
        XCTAssertNotNil(service.predictStruggle(matched))
        XCTAssertFalse(
            standsDown,
            "preferred for routing, and still not a replacement for the rules"
        )
    }
}
