//
//  RiskLevelThresholdTests.swift
//  AnchorTests
//
//  Pins the operating point published in README.md.
//
//  The README states the bands as a table — Engaged below 0.40, Watch at 0.40,
//  Needs attention at 0.70, with a sensitivity slider moving both by ±0.15 —
//  and quotes precision and recall measured at exactly those cut-offs. A
//  retrain, or a well-meant tweak to the slider maths, can shift the banding
//  without breaking a single build: every student still gets a colour, and the
//  colour is quietly no longer the one the published numbers describe.
//
//  So these assertions are documentation with teeth. If one fails, the fix is
//  not necessarily the code — it may be that the README and the marketing copy
//  now describe a model that no longer exists, and both have to move together.
//

import XCTest
@testable import Anchor

final class RiskLevelThresholdTests: XCTestCase {

    // MARK: Default operating point

    func testDefaultBandsMatchTheReadme() {
        XCTAssertEqual(RiskLevel.defaultElevatedThreshold, 0.40)
        XCTAssertEqual(RiskLevel.defaultHighThreshold, 0.70)
    }

    func testDefaultSensitivityLeavesTheBandsWhereTheReadmePutsThem() {
        XCTAssertEqual(RiskLevel.elevatedThreshold(sensitivity: 0.5), 0.40, accuracy: 0.0001)
        XCTAssertEqual(RiskLevel.highThreshold(sensitivity: 0.5), 0.70, accuracy: 0.0001)
    }

    func testScoresLandInTheBandTheReadmeClaims() {
        XCTAssertEqual(RiskLevel.level(for: 0.00), .low)
        XCTAssertEqual(RiskLevel.level(for: 0.39), .low)
        XCTAssertEqual(RiskLevel.level(for: 0.40), .elevated, "0.40 is Watch, inclusive")
        XCTAssertEqual(RiskLevel.level(for: 0.69), .elevated)
        XCTAssertEqual(RiskLevel.level(for: 0.70), .high, "0.70 is Needs attention, inclusive")
        XCTAssertEqual(RiskLevel.level(for: 1.00), .high)
    }

    // MARK: The slider

    func testSensitivityMovesBothCutOffsByAtMostFifteenPoints() {
        // The README promises ±0.15. The endpoints are what the slider can
        // actually reach, and they are quoted in the precision/recall table.
        XCTAssertEqual(RiskLevel.elevatedThreshold(sensitivity: 0), 0.55, accuracy: 0.0001)
        XCTAssertEqual(RiskLevel.elevatedThreshold(sensitivity: 1), 0.25, accuracy: 0.0001)
        XCTAssertEqual(RiskLevel.highThreshold(sensitivity: 0), 0.85, accuracy: 0.0001)
        XCTAssertEqual(RiskLevel.highThreshold(sensitivity: 1), 0.55, accuracy: 0.0001)
    }

    func testHigherSensitivityFlagsEarlier() {
        // The direction is easy to invert by accident and the symptom — a
        // teacher dragging "more sensitive" and seeing fewer students — would
        // be blamed on the model rather than on the slider.
        let quiet = RiskLevel.elevatedThreshold(sensitivity: 0.2)
        let eager = RiskLevel.elevatedThreshold(sensitivity: 0.8)
        XCTAssertLessThan(eager, quiet)
    }

    func testTheTwoBandsNeverCross() {
        // A high cut-off below the elevated one would make `.elevated`
        // unreachable, and `level(for:)` checks high first — so every flagged
        // student would jump straight to red with nothing in between.
        for step in 0...20 {
            let sensitivity = Double(step) / 20
            XCTAssertGreaterThan(
                RiskLevel.highThreshold(sensitivity: sensitivity),
                RiskLevel.elevatedThreshold(sensitivity: sensitivity),
                "Bands crossed at sensitivity \(sensitivity)"
            )
        }
    }

    func testBandingIsMonotonicInScore() {
        // Whatever the thresholds are, a higher score must never be a calmer
        // verdict. This holds regardless of retraining.
        for sensitivity in [0.0, 0.25, 0.5, 0.75, 1.0] {
            var previous = RiskLevel.level(for: 0, sensitivity: sensitivity).rank
            for step in 0...100 {
                let rank = RiskLevel.level(for: Double(step) / 100, sensitivity: sensitivity).rank
                XCTAssertLessThanOrEqual(rank, previous, "Banding went backwards at sensitivity \(sensitivity)")
                previous = rank
            }
        }
    }

    // MARK: Labels

    func testLabelsAreTheOnesTheReadmePublishes() {
        XCTAssertEqual(RiskLevel.low.label, "Engaged")
        XCTAssertEqual(RiskLevel.elevated.label, "Watch")
        XCTAssertEqual(RiskLevel.high.label, "Needs attention")
    }
}
