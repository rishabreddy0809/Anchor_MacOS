//
//  AcademicEscalationTests.swift
//  AnchorTests
//
//  The hand-written layer that stands in for a model that cannot see grades.
//
//  This is the one place in Anchor where a number a teacher acts on is decided
//  by judgement rather than by the classifier, and its own header says so: the
//  weights are "judgement, not measurement", the layer is "designed to be
//  deleted", and it switches itself off the moment a 16-feature model arrives.
//  All three of those promises are properties of the arithmetic, not of the
//  type system, and none of them fail loudly. A broken cap still returns a
//  score. A switch that stops switching still returns a score. The dashboard
//  renders either way.
//
//  So the tests below concentrate on the bounds rather than on the individual
//  rules: that academic history can raise a flag but never manufacture one,
//  that a clean record buys a quiet student the benefit of the doubt without
//  ever clearing them, and that the whole layer stands down when the model no
//  longer needs it. The per-rule thresholds are pinned too, because they are
//  the numbers a teacher will be told and argue with.
//

import XCTest
@testable import Anchor

final class AcademicEscalationTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(
        missing: Int = 0,
        late: Int = 0,
        graded: Int = 0,
        average: Double? = nil,
        trend: Double? = nil,
        pastDue: Int = 0,
        lastSubmission: Date? = nil
    ) -> AcademicSnapshot {
        AcademicSnapshot(
            studentID: "s1",
            name: "Ada",
            email: "ada@example.edu",
            missingAssignments: (0..<missing).map {
                ClassroomAssignment(id: "a\($0)", courseID: "c1", title: "Worksheet \($0 + 1)")
            },
            lateCount: late,
            gradedCount: graded,
            averageGrade: average,
            gradeTrend: trend,
            lastSubmission: lastSubmission,
            pastDueCount: pastDue
        )
    }

    /// A student behind on everything the rules know how to look at.
    private func strugglingOnEveryAxis() -> AcademicSnapshot {
        snapshot(
            missing: 9,
            late: 6,
            graded: 8,
            average: 0.31,
            trend: -0.30,
            pastDue: 12,
            lastSubmission: Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        )
    }

    /// A student with the best record the reassurance rules can recognise.
    private func spotlessRecord() -> AcademicSnapshot {
        snapshot(missing: 0, graded: 6, average: 0.95, pastDue: 4)
    }

    private func factor(_ title: String, in result: AcademicEscalationResult) -> AcademicFactor? {
        result.factors.first { $0.title == title }
    }

    // MARK: When this layer must not speak at all

    func testNoClassroomDataLeavesTheModelScoreExactlyAsItWas() {
        let result = AcademicEscalation(now: now)
            .apply(to: 0.42, snapshot: nil, modelUsesAcademicFeatures: false)

        XCTAssertEqual(result.adjustedScore, 0.42)
        XCTAssertTrue(result.factors.isEmpty)
        XCTAssertFalse(result.didEscalate)
    }

    func testAnEmptyRecordIsNotEvidenceInEitherDirection() {
        // Classroom matched the student and had nothing to say — no graded
        // work, nothing overdue, nothing late. That is the state of a class in
        // its first week, not a finding about the student.
        let result = AcademicEscalation(now: now)
            .apply(to: 0.42, snapshot: snapshot(), modelUsesAcademicFeatures: false)

        XCTAssertEqual(result.adjustedScore, 0.42)
        XCTAssertTrue(result.factors.isEmpty)
    }

    func testARetrainedModelSwitchesThisWholeLayerOff() {
        // The automatic hand-off this file was written to make possible. Once
        // StruggleDetectionService loads a model that declares the academic
        // columns, the model's own learned weights already account for the
        // missing work — applying these rules on top would count every missing
        // assignment twice, and the second count is guesswork stacked on a
        // measurement. Nothing else in the codebase enforces the exclusivity.
        let result = AcademicEscalation(now: now).apply(
            to: 0.42,
            snapshot: strugglingOnEveryAxis(),
            modelUsesAcademicFeatures: true
        )

        XCTAssertEqual(result.adjustedScore, 0.42)
        XCTAssertTrue(result.factors.isEmpty)
        XCTAssertFalse(result.didEscalate)
    }

    // MARK: The bounds

    func testAcademicHistoryCanNeverAddMoreThanTwentyPoints() {
        // The rules sum to 0.27 for a student behind on everything, so the cap
        // is load-bearing rather than theoretical. It is what stops academic
        // history deciding a score instead of informing one: at +0.27 a student
        // sitting mid-Watch would be pushed into "Needs attention" purely on
        // last month's homework, with nothing in today's lesson to support it.
        let result = AcademicEscalation(now: now).apply(
            to: 0.30,
            snapshot: strugglingOnEveryAxis(),
            modelUsesAcademicFeatures: false
        )

        let raw = result.factors.reduce(0) { $0 + $1.impact }
        XCTAssertGreaterThan(raw, AcademicEscalation.maximumAdjustment, "Cap is doing nothing here")
        XCTAssertEqual(result.totalImpactPoints, 20)
        XCTAssertEqual(result.adjustedScore, 0.50, accuracy: 0.0001)
    }

    func testAGoodRecordIsWorthHalfOfWhatABadOneIs() {
        // The asymmetry is the argument of the whole reassurance section: being
        // behind is stronger evidence that something is wrong than being up to
        // date is evidence that nothing is, because a student can be completely
        // lost in the lesson with a spotless record. Equalising these would let
        // a good record cancel a genuine concern one-for-one.
        XCTAssertEqual(AcademicEscalation.maximumReduction, AcademicEscalation.maximumAdjustment / 2)
    }

    func testAcademicHistoryCanNeverRemoveMoreThanTenPoints() {
        let result = AcademicEscalation(now: now).apply(
            to: 0.60,
            snapshot: spotlessRecord(),
            modelUsesAcademicFeatures: false
        )

        XCTAssertEqual(result.totalImpactPoints, -10)
        XCTAssertEqual(result.adjustedScore, 0.50, accuracy: 0.0001)
        XCTAssertFalse(result.didEscalate, "Evidence running the other way is not an escalation")
    }

    func testAPerfectRecordCannotClearAStudentTheModelFlagged() {
        // The failure mode the reduction cap exists to prevent. A student can
        // have done every piece of homework and still be completely lost in
        // today's lesson; if a clean record could walk a red student down into
        // the green, Anchor would hide exactly the person it exists to surface.
        let result = AcademicEscalation(now: now).apply(
            to: 0.85,
            snapshot: spotlessRecord(),
            modelUsesAcademicFeatures: false
        )

        XCTAssertEqual(RiskLevel.level(for: result.adjustedScore), .high)
    }

    func testTheCeilingMatchesTheScorersOwn() {
        // StruggleScoreCalculator clamps its own output to 0.97 (a literal, in
        // its `score` function). If escalation could exceed that, a student
        // would be presented as more certain than the scorer is capable of
        // being — and the extra certainty would come from the hand-written
        // layer, not the model.
        XCTAssertEqual(AcademicEscalation.scoreCeiling, 0.97)

        let result = AcademicEscalation(now: now).apply(
            to: 0.95,
            snapshot: strugglingOnEveryAxis(),
            modelUsesAcademicFeatures: false
        )

        XCTAssertEqual(result.adjustedScore, 0.97, accuracy: 0.0001)
    }

    func testAReducedScoreNeverGoesNegative() {
        let result = AcademicEscalation(now: now).apply(
            to: 0.04,
            snapshot: spotlessRecord(),
            modelUsesAcademicFeatures: false
        )

        XCTAssertEqual(result.adjustedScore, 0, accuracy: 0.0001)
    }

    // MARK: Missing work

    func testMissingWorkIsBandedRatherThanCounted() {
        // Thresholds, not a smooth function of submission rate: "two missing
        // assignments" is something a teacher can check and disagree with.
        func impact(missing: Int) -> Double {
            AcademicEscalation(now: now)
                .apply(to: 0.30, snapshot: snapshot(missing: missing), modelUsesAcademicFeatures: false)
                .totalImpact
        }

        XCTAssertEqual(impact(missing: 1), 0.03, accuracy: 0.0001)
        XCTAssertEqual(impact(missing: 2), 0.06, accuracy: 0.0001)
        XCTAssertEqual(impact(missing: 3), 0.06, accuracy: 0.0001)
        XCTAssertEqual(impact(missing: 4), 0.10, accuracy: 0.0001)
        XCTAssertEqual(impact(missing: 40), 0.10, accuracy: 0.0001, "The top band is the top band")
    }

    func testASingleMissingAssignmentIsWordedInTheSingular() {
        // These titles are read verbatim in the detail view; "1 missing
        // assignments" is the kind of thing that costs a teacher's trust in
        // everything else on the screen.
        let result = AcademicEscalation(now: now)
            .apply(to: 0.30, snapshot: snapshot(missing: 1), modelUsesAcademicFeatures: false)
        XCTAssertEqual(result.factors.first?.title, "1 missing assignment")

        let plural = AcademicEscalation(now: now)
            .apply(to: 0.30, snapshot: snapshot(missing: 2), modelUsesAcademicFeatures: false)
        XCTAssertEqual(plural.factors.first?.title, "2 missing assignments")
    }

    // MARK: Grades

    func testFallingGradesNeedToBeActuallyFalling() {
        // `graded` is set only to keep the snapshot from reading as empty —
        // an entirely blank record short-circuits `apply` before any rule runs.
        func impact(trend: Double) -> Double {
            AcademicEscalation(now: now)
                .apply(
                    to: 0.30,
                    snapshot: snapshot(graded: 4, trend: trend),
                    modelUsesAcademicFeatures: false
                )
                .totalImpact
        }

        XCTAssertEqual(impact(trend: 0.20), 0, accuracy: 0.0001, "Improving grades are not a concern")
        XCTAssertEqual(impact(trend: -0.04), 0, accuracy: 0.0001, "Inside the noise")
        XCTAssertEqual(impact(trend: -0.05), 0.03, accuracy: 0.0001)
        XCTAssertEqual(impact(trend: -0.14), 0.03, accuracy: 0.0001)
        XCTAssertEqual(impact(trend: -0.15), 0.06, accuracy: 0.0001)
    }

    func testALowAverageCountsEvenWithNoTrendAtAll() {
        // A student who has been struggling all term shows no trend — their
        // grades have been consistently low. Reading direction alone would let
        // the most obviously struggling case fall through both rules.
        let result = AcademicEscalation(now: now).apply(
            to: 0.30,
            snapshot: snapshot(graded: 4, average: 0.55, trend: nil),
            modelUsesAcademicFeatures: false
        )

        XCTAssertEqual(result.totalImpact, 0.05, accuracy: 0.0001)
        XCTAssertNotNil(factor("Grade average 55%", in: result))
    }

    func testOneBadMarkIsNotATermsWorthOfEvidence() {
        // gradedCount >= 2. A single graded assignment is a bad day, and it is
        // the only thing in the record for a course that has just started
        // marking work.
        let result = AcademicEscalation(now: now).apply(
            to: 0.30,
            snapshot: snapshot(graded: 1, average: 0.40),
            modelUsesAcademicFeatures: false
        )

        XCTAssertEqual(result.totalImpact, 0, accuracy: 0.0001)
    }

    // MARK: Submissions and lateness

    func testGoingQuietOnSubmissionsNeedsACourseThatExpectedSomething() {
        // Without the pastDueCount guard, every student in a course that has
        // set no deadlines yet reads as having gone silent on their work.
        let silent = Calendar.current.date(byAdding: .day, value: -21, to: Date())!

        // The single late submission is there only so the snapshot is not
        // `isEmpty`, which would short-circuit `apply` before any rule runs.
        let noDeadlines = AcademicEscalation(now: now).apply(
            to: 0.30,
            snapshot: snapshot(late: 1, pastDue: 0, lastSubmission: silent),
            modelUsesAcademicFeatures: false
        )
        XCTAssertEqual(noDeadlines.totalImpact, 0, accuracy: 0.0001)

        let overdue = AcademicEscalation(now: now).apply(
            to: 0.30,
            snapshot: snapshot(late: 1, pastDue: 3, lastSubmission: silent),
            modelUsesAcademicFeatures: false
        )
        XCTAssertEqual(overdue.totalImpact, 0.04, accuracy: 0.0001)
    }

    func testAFortnightIsTheThresholdForSilence() {
        func impact(daysAgo: Int) -> Double {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
            return AcademicEscalation(now: now)
                .apply(
                    to: 0.30,
                    snapshot: snapshot(late: 1, pastDue: 3, lastSubmission: date),
                    modelUsesAcademicFeatures: false
                )
                .totalImpact
        }

        XCTAssertEqual(impact(daysAgo: 13), 0, accuracy: 0.0001)
        XCTAssertEqual(impact(daysAgo: 14), 0.04, accuracy: 0.0001)
    }

    func testLatenessOnlyCountsWhenItIsChronic() {
        // Weak on its own, real in aggregate — everyone is late once.
        func impact(late: Int) -> Double {
            AcademicEscalation(now: now)
                .apply(to: 0.30, snapshot: snapshot(late: late), modelUsesAcademicFeatures: false)
                .totalImpact
        }

        XCTAssertEqual(impact(late: 2), 0, accuracy: 0.0001)
        XCTAssertEqual(impact(late: 3), 0.02, accuracy: 0.0001)
    }

    // MARK: Evidence the other way

    func testAnEmptyRecordIsNotAGoodRecord() {
        // Reassurance requires *graded* work. A student with nothing marked has
        // not demonstrated they are coping; they have demonstrated nothing, and
        // crediting that would hand every student in a new class a discount.
        let result = AcademicEscalation(now: now).apply(
            to: 0.60,
            snapshot: snapshot(missing: 0, late: 1, graded: 1, average: 0.95, pastDue: 4),
            modelUsesAcademicFeatures: false
        )

        XCTAssertTrue(result.factors.isEmpty)
        XCTAssertEqual(result.adjustedScore, 0.60, accuracy: 0.0001)
    }

    func testABrandNewCourseCannotEarnCreditForNoMissingWork() {
        // Without the pastDueCount guard every student in a course with no
        // deadlines yet reads as "fully up to date" on the strength of there
        // being nothing to be behind on.
        let result = AcademicEscalation(now: now).apply(
            to: 0.60,
            snapshot: snapshot(missing: 0, graded: 6, average: 0.90, pastDue: 0),
            modelUsesAcademicFeatures: false
        )

        XCTAssertNil(factor("No missing work", in: result))
        XCTAssertEqual(result.totalImpact, -0.04, accuracy: 0.0001, "Only the grade average is earned")
    }

    func testAQuietHighPerformerGetsTheBenefitOfTheDoubt() {
        // The case that motivated the whole section: the class is going over
        // homework this student has already done, so they have nothing to say
        // and no reason to say it. Anchor held the evidence they were fine and
        // was throwing it away.
        let result = AcademicEscalation(now: now).apply(
            to: 0.45,
            snapshot: spotlessRecord(),
            modelUsesAcademicFeatures: false
        )

        XCTAssertNotNil(factor("No missing work", in: result))
        XCTAssertNotNil(factor("Grade average 95%", in: result))
        XCTAssertEqual(RiskLevel.level(for: 0.45), .elevated)
        XCTAssertEqual(RiskLevel.level(for: result.adjustedScore), .low, "Watch, walked back to Engaged")
    }

    func testReassurancesAreMarkedSoATeacherCannotReadThemAsConcerns() {
        // The factor list is rendered as a column of reasons. A line that
        // *lowered* the score sitting unmarked among the ones that raised it
        // would read as "no missing work" being a cause for concern.
        let result = AcademicEscalation(now: now).apply(
            to: 0.60,
            snapshot: spotlessRecord(),
            modelUsesAcademicFeatures: false
        )

        for reassurance in result.factors where reassurance.severity == .reassuring {
            XCTAssertTrue(reassurance.severity.lowersScore)
            XCTAssertLessThan(reassurance.impact, 0)
            XCTAssertEqual(reassurance.severity.label, "lowers concern")
        }
        XCTAssertFalse(result.factors.isEmpty)
    }

    func testASignedReductionRendersAsAMinusRatherThanAPlusMinus() {
        // Interpolating "+\(impactPoints)" prints "+-6". The sign is how a
        // teacher scanning the column tells which way each line pushed.
        let reassurance = AcademicFactor(title: "No missing work", severity: .reassuring, impact: -0.06)
        XCTAssertEqual(reassurance.impactPoints, -6)
        XCTAssertEqual(reassurance.signedPoints, "−6")

        let concern = AcademicFactor(title: "1 missing assignment", severity: .medium, impact: 0.03)
        XCTAssertEqual(concern.signedPoints, "+3")
    }

    func testConcernsAreListedBeforeTheEvidenceAgainstThem() {
        // A teacher reads the top of this list first, and the actionable half
        // is the concerns.
        let result = AcademicEscalation(now: now).apply(
            to: 0.60,
            snapshot: snapshot(missing: 0, late: 4, graded: 6, average: 0.95, pastDue: 4),
            modelUsesAcademicFeatures: false
        )

        let firstReassurance = result.factors.firstIndex { $0.severity == .reassuring }
        let lastConcern = result.factors.lastIndex { $0.severity != .reassuring }
        XCTAssertNotNil(firstReassurance)
        XCTAssertNotNil(lastConcern)
        XCTAssertLessThan(lastConcern!, firstReassurance!)
    }

    // MARK: Recommendations

    func testRecommendationsAreUntouchedWithoutClassroomData() {
        let engagement = ["Check in with Ada after class."]

        XCTAssertEqual(
            AcademicEscalation.recommendations(engagement: engagement, snapshot: nil, score: 0.9),
            engagement
        )
        XCTAssertEqual(
            AcademicEscalation.recommendations(engagement: engagement, snapshot: snapshot(), score: 0.9),
            engagement
        )
    }

    func testEngagementAdviceStaysFirst() {
        // The class is happening now; the academic context is what makes the
        // check-in specific, not what a teacher should act on first.
        let engagement = ["Check in with Ada after class."]
        let combined = AcademicEscalation.recommendations(
            engagement: engagement,
            snapshot: snapshot(missing: 2, graded: 3),
            score: 0.80
        )

        XCTAssertEqual(combined.first, engagement[0])
        XCTAssertGreaterThan(combined.count, 1)
    }

    func testMissingWorkIsOnlyRaisedOnceTheScoreWarrantsIt() {
        // Below the threshold there is no concern to give an opening for, and
        // volunteering a student's missing homework unprompted is not what this
        // line is for.
        let quiet = AcademicEscalation.recommendations(
            engagement: [],
            snapshot: snapshot(missing: 2, graded: 3),
            score: 0.44
        )
        XCTAssertTrue(quiet.isEmpty)

        let flagged = AcademicEscalation.recommendations(
            engagement: [],
            snapshot: snapshot(missing: 2, graded: 3),
            score: 0.45
        )
        XCTAssertEqual(flagged.count, 1)
    }

    func testAtMostTwoAssignmentsAreNamed() {
        // The line is meant to give a teacher a concrete opening, not to read
        // out a backlog.
        let advice = AcademicEscalation.recommendations(
            engagement: [],
            snapshot: snapshot(missing: 4),
            score: 0.80
        ).joined()

        XCTAssertTrue(advice.contains("Worksheet 1, Worksheet 2"))
        XCTAssertFalse(advice.contains("Worksheet 3"))
        XCTAssertTrue(advice.contains("4 missing assignments"))
    }

    func testAStudentOnTopOfTheWorkGetsADifferentScript() {
        // Disengaged in the room but up to date on coursework is a different
        // problem, and repeating the "chase the assignments" advice at a
        // teacher who has nothing to chase makes the whole panel look
        // automated.
        let advice = AcademicEscalation.recommendations(
            engagement: [],
            snapshot: snapshot(missing: 0, graded: 5, average: 0.9),
            score: 0.70
        )

        XCTAssertEqual(advice.count, 1)
        XCTAssertTrue(advice[0].contains("unlikely to be about workload"))

        let notYetFlagged = AcademicEscalation.recommendations(
            engagement: [],
            snapshot: snapshot(missing: 0, graded: 5, average: 0.9),
            score: 0.69
        )
        XCTAssertTrue(notYetFlagged.isEmpty)
    }

    func testFallingGradesAreMentionedRegardlessOfTodaysScore() {
        // Unlike the other two lines this one has no score gate: a downward
        // trend is worth raising with a student who looks fine today, because
        // it is the one signal in this file that predates the lesson.
        let advice = AcademicEscalation.recommendations(
            engagement: [],
            snapshot: snapshot(graded: 6, trend: -0.12),
            score: 0.10
        )

        XCTAssertEqual(advice.count, 1)
        XCTAssertTrue(advice[0].contains("Grades are"))
        XCTAssertTrue(advice[0].contains("12%"))
    }
}
