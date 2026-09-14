import XCTest
@testable import Kinetriq

final class TrendInsightsTests: XCTestCase {

    // MARK: - Helpers

    /// Samples spaced a few days apart, oldest first — the order `TrendInsights` expects.
    private func samples(
        scores: [Int?] = [],
        peaks: [Double?] = [],
        eccentrics: [Double?] = [],
        asymmetries: [Double?] = [],
        kind: AnalysisKind = .exercise,
        daySpacing: Int = 3
    ) -> [TrendSample] {
        let count = max(scores.count, max(peaks.count, max(eccentrics.count, asymmetries.count)))
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        return (0..<count).map { index in
            TrendSample(
                date: start.addingTimeInterval(Double(index * daySpacing) * 86_400),
                kind: kind,
                totalReps: 5,
                score: index < scores.count ? scores[index] : nil,
                meanPeakAngle: index < peaks.count ? peaks[index] : nil,
                meanEccentric: index < eccentrics.count ? eccentrics[index] : nil,
                asymmetryDeg: index < asymmetries.count ? asymmetries[index] : nil
            )
        }
    }

    // MARK: - Sparse history

    func testFewerThanThreeSessionsReportsProgressTowardATrend() {
        let insights = TrendInsights.insights(
            for: samples(scores: [70, 74]),
            movementName: "Squat"
        )

        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights.first?.tone, .info)
        XCTAssertTrue(insights[0].text.contains("2 Squat sessions"))
        XCTAssertTrue(insights[0].text.contains("1 more"))
    }

    func testNoSessionsProducesNoInsights() {
        XCTAssertTrue(TrendInsights.insights(for: [], movementName: "Squat").isEmpty)
    }

    // MARK: - Score direction

    func testRisingScoreIsReportedAsImprovement() {
        let insights = TrendInsights.insights(
            for: samples(scores: [60, 68, 75]),
            movementName: "Squat"
        )

        XCTAssertEqual(insights.first?.tone, .positive)
        XCTAssertTrue(insights[0].text.contains("up 15 points"))
    }

    func testFallingScoreIsReportedAsCaution() {
        let insights = TrendInsights.insights(
            for: samples(scores: [82, 76, 70]),
            movementName: "Deadlift"
        )

        XCTAssertEqual(insights.first?.tone, .caution)
        XCTAssertTrue(insights[0].text.contains("slipped 12 points"))
    }

    /// A swing smaller than the threshold is session-to-session noise, not a trend.
    func testScoreChangeInsideTheThresholdReadsAsSteady() {
        let insights = TrendInsights.insights(
            for: samples(scores: [70, 73, 72]),
            movementName: "Row"
        )

        XCTAssertEqual(insights.first?.tone, .positive)
        XCTAssertTrue(insights[0].text.contains("holding steady"))
    }

    // MARK: - Personal best

    func testLatestSessionBeingTheBestEverIsCalledOut() {
        let insights = TrendInsights.insights(
            for: samples(scores: [60, 70, 88]),
            movementName: "Squat"
        )

        XCTAssertTrue(insights.contains { $0.text.contains("most consistent set") })
    }

    func testTyingAPreviousBestIsNotCalledAPersonalBest() {
        let insights = TrendInsights.insights(
            for: samples(scores: [88, 70, 88]),
            movementName: "Squat"
        )

        XCTAssertFalse(insights.contains { $0.text.contains("most consistent set") })
    }

    // MARK: - Depth

    /// Peak flexion angle getting smaller means the lifter is going deeper.
    func testShrinkingPeakAngleReadsAsMoreDepth() {
        let insights = TrendInsights.insights(
            for: samples(scores: [70, 71, 72], peaks: [100, 95, 88]),
            movementName: "Squat"
        )

        XCTAssertTrue(insights.contains { $0.text.contains("deeper") })
    }

    func testGrowingPeakAngleReadsAsLostDepth() {
        let insights = TrendInsights.insights(
            for: samples(scores: [70, 71, 72], peaks: [88, 95, 100]),
            movementName: "Squat"
        )

        XCTAssertTrue(insights.contains { $0.text.contains("Depth has dropped") })
    }

    func testSmallAngleChangeIsTreatedAsCameraNoise() {
        let insights = TrendInsights.insights(
            for: samples(scores: [70, 71, 72], peaks: [90, 92, 93]),
            movementName: "Squat"
        )

        XCTAssertFalse(insights.contains { $0.text.contains("deeper") })
        XCTAssertFalse(insights.contains { $0.text.contains("Depth has dropped") })
    }

    // MARK: - Eccentric control

    func testEccentricCollapsingBelowTheControlThresholdWarns() {
        let insights = TrendInsights.insights(
            for: samples(scores: [70, 71, 72], eccentrics: [2.4, 1.6, 0.8]),
            movementName: "Squat"
        )

        XCTAssertTrue(insights.contains { $0.text.contains("eccentric has shortened") })
    }

    func testSteadyEccentricAcrossSessionsIsPraised() {
        let insights = TrendInsights.insights(
            for: samples(scores: [70, 71, 72], eccentrics: [2.0, 2.1, 1.9]),
            movementName: "Squat"
        )

        XCTAssertTrue(insights.contains { $0.text.contains("repeatable control") })
    }

    // MARK: - Asymmetry

    func testNarrowingAsymmetryIsPositive() {
        let insights = TrendInsights.insights(
            for: samples(asymmetries: [14, 10, 6], kind: .assessment),
            movementName: "Shoulder Flexion"
        )

        XCTAssertTrue(insights.contains { $0.text.contains("narrowed") })
    }

    func testWideningAsymmetryIsCaution() {
        let insights = TrendInsights.insights(
            for: samples(asymmetries: [5, 9, 13], kind: .assessment),
            movementName: "Shoulder Flexion"
        )

        XCTAssertTrue(insights.contains { insight in
            insight.text.contains("widened") && insight.tone == .caution
        })
    }

    // MARK: - Layoff

    func testReturnAfterALongGapIsAcknowledged() {
        let insights = TrendInsights.insights(
            for: samples(scores: [70, 71, 72], daySpacing: 30),
            movementName: "Squat"
        )

        XCTAssertTrue(insights.contains { $0.text.contains("first squat session in") })
    }

    func testRegularTrainingDoesNotTriggerTheLayoffNote() {
        let insights = TrendInsights.insights(
            for: samples(scores: [70, 71, 72], daySpacing: 3),
            movementName: "Squat"
        )

        XCTAssertFalse(insights.contains { $0.text.contains("first squat session in") })
    }

    // MARK: - Volume

    func testAtMostFourInsightsAreReturned() {
        let insights = TrendInsights.insights(
            for: samples(
                scores: [55, 70, 90],
                peaks: [110, 98, 85],
                eccentrics: [2.0, 2.1, 1.9],
                asymmetries: [14, 10, 5],
                daySpacing: 30
            ),
            movementName: "Squat"
        )

        XCTAssertLessThanOrEqual(insights.count, 4)
    }
}
