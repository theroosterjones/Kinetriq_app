import XCTest
@testable import Kinetriq

final class CoachingInsightsTests: XCTestCase {

    func testFastEccentricInsightWarnsAboutLackOfControl() {
        let reps = (1...3).map { n in
            RepMetric(repNumber: n, peakFlexionAngle: 90,
                      eccentricDuration: 0.8, pauseBottomDuration: 0.4,
                      concentricDuration: 1.0, pauseTopDuration: 0.4)
        }
        let insights = CoachingInsights.exercise(summary: summary(reps: reps, score: 75),
                                                exerciseType: .squat)

        XCTAssertTrue(insights.contains { $0.text.contains("lack control") })
    }

    func testConcentricSlowingInsightCallsOutChallengingSet() {
        let reps = [
            RepMetric(repNumber: 1, peakFlexionAngle: 90,
                      eccentricDuration: 2.0, pauseBottomDuration: 0.5,
                      concentricDuration: 1.0, pauseTopDuration: 0.5),
            RepMetric(repNumber: 2, peakFlexionAngle: 90,
                      eccentricDuration: 2.0, pauseBottomDuration: 0.5,
                      concentricDuration: 1.5, pauseTopDuration: 0.5),
            RepMetric(repNumber: 3, peakFlexionAngle: 90,
                      eccentricDuration: 2.0, pauseBottomDuration: 0.5,
                      concentricDuration: 2.0, pauseTopDuration: 0.5)
        ]
        let insights = CoachingInsights.exercise(summary: summary(reps: reps, score: 100),
                                                exerciseType: .squat)

        XCTAssertTrue(insights.contains { $0.text.contains("challenging set") })
        XCTAssertTrue(insights.contains { $0.text.contains("Concentric slowed") })
        XCTAssertFalse(insights.contains { $0.text.contains("Stop a rep") })
    }

    func testControlledSteadySetDoesNotWarnAboutSpeed() {
        let reps = (1...4).map { n in
            RepMetric(repNumber: n, peakFlexionAngle: 90,
                      eccentricDuration: 2.0, pauseBottomDuration: 0.5,
                      concentricDuration: 1.0, pauseTopDuration: 0.5)
        }
        let insights = CoachingInsights.exercise(summary: summary(reps: reps, score: 100),
                                                exerciseType: .squat)

        XCTAssertFalse(insights.contains { $0.text.contains("lack control") })
        XCTAssertFalse(insights.contains { $0.text.contains("challenging set") })
        XCTAssertTrue(insights.contains { $0.text.contains("Tempo stayed steady") })
    }

    private func summary(reps: [RepMetric], score: Int) -> AnalysisSummary {
        let lastFrame = FrameAnalysis(
            angles: [],
            repCount: reps.count,
            repState: .extended,
            tempoPhase: nil,
            overlayInstructions: []
        )
        return AnalysisSummary(from: [lastFrame], duration: 20,
                               repMetrics: reps, score: score)
    }
}
