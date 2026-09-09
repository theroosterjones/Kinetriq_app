import XCTest
@testable import Kinetriq

final class RepMetricsTests: XCTestCase {

    // MARK: - Score requires >= 3 reps

    func testScoreNilWithFewerThanThreeReps() {
        let collector = RepMetricsCollector()
        // Simulate 2 reps
        simulateRep(collector, repNumber: 1, peakAngle: 90, at: 0)
        simulateRep(collector, repNumber: 2, peakAngle: 92, at: 3)

        XCTAssertNil(collector.computeScore())
    }

    // MARK: - Perfect consistency = 100

    func testPerfectConsistencyScoresOneHundred() {
        let collector = RepMetricsCollector()
        // 3 identical reps
        for i in 1...3 {
            simulateIdenticalRep(collector, repNumber: i, at: Double(i - 1) * 3.5)
        }

        let score = collector.computeScore()
        XCTAssertNotNil(score)
        XCTAssertEqual(score, 100)
    }

    // MARK: - ROM peak-angle SD bands

    func testROMScoreBandsFromPeakAngleStdDev() {
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 0), 100)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 1.5), 100)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 2), 90)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 3), 90)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 4), 80)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 5), 80)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 6), 70)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 7), 70)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 8), 50)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 10), 50)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 11), 40)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 12), 40)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 12.5), 30)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 13), 30)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 14), 20)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 15), 20)
        XCTAssertEqual(RepMetricsCollector.romScore(forPeakAngleStdDev: 16), 0)
    }

    func testModerateROMVarianceUsesEightToTenBand() {
        let collector = RepMetricsCollector()
        // Peak angles 80, 90, 100 → σ ≈ 8.2 → ROM band 50.
        // Controlled ecc so tempo/control stay at 100: final = 0.6*50 + 0.4*100 = 70.
        var t = 0.0
        for (i, peak) in zip(1...3, [Float(80), 90, 100]) {
            simulateTimedRep(collector, repNumber: i, peakAngle: peak, at: t)
            t += 4.0
        }

        let score = collector.computeScore()
        XCTAssertNotNil(score)
        XCTAssertEqual(score!, 70)
    }

    // MARK: - High ROM variance still lowers the score

    func testHighROMVarianceLowersScore() {
        let collector = RepMetricsCollector()
        // Peak angles: 80, 100, 120 → σ ≈ 16.3 → ROM 0 → final = 40
        var t = 0.0
        for (i, peak) in zip(1...3, [Float(80), 100, 120]) {
            simulateTimedRep(collector, repNumber: i, peakAngle: peak, at: t)
            t += 4.0
        }

        let score = collector.computeScore()
        XCTAssertNotNil(score)
        XCTAssertEqual(score!, 40)
    }

    // MARK: - Concentric slowing does not lower the score

    func testConcentricSlowingDoesNotLowerScore() {
        let steady = RepMetricsCollector()
        let fatiguing = RepMetricsCollector()
        var steadyT = 0.0
        var fatigueT = 0.0
        for i in 1...3 {
            let concentric = 1.0 + Double(i - 1) * 0.6
            simulateTimedRep(steady, repNumber: i, peakAngle: 90, at: steadyT, concentric: 1.0)
            simulateTimedRep(fatiguing, repNumber: i, peakAngle: 90, at: fatigueT, concentric: concentric)
            steadyT += 4.0
            fatigueT += 3.0 + concentric
        }

        XCTAssertEqual(steady.computeScore(), fatiguing.computeScore())
        XCTAssertEqual(steady.computeScore(), 100)
    }

    // MARK: - Fast eccentric lowers the score

    func testFastEccentricLowersScore() {
        let controlled = RepMetricsCollector()
        let rushed = RepMetricsCollector()
        var controlledT = 0.0
        var rushedT = 0.0
        for i in 1...3 {
            simulateTimedRep(controlled, repNumber: i, peakAngle: 90, at: controlledT, eccentric: 2.0)
            simulateTimedRep(rushed, repNumber: i, peakAngle: 90, at: rushedT, eccentric: 0.8)
            controlledT += 4.0
            rushedT += 2.8
        }

        XCTAssertEqual(controlled.computeScore(), 100)
        XCTAssertEqual(rushed.computeScore(), 75)
    }

    // MARK: - Reset clears all state

    func testResetClearsState() {
        let collector = RepMetricsCollector()
        simulateRep(collector, repNumber: 1, peakAngle: 90, at: 0)
        XCTAssertEqual(collector.completedReps.count, 1)

        collector.reset()
        XCTAssertEqual(collector.completedReps.count, 0)
        XCTAssertNil(collector.computeScore())
    }

    // MARK: - Tempo string format

    func testCurrentTempoStringFormat() {
        let collector = RepMetricsCollector()
        // Start with eccentric phase
        collector.update(phase: .eccentric, angle: 150, repCount: 0, timestamp: 0)
        collector.update(phase: .eccentric, angle: 140, repCount: 0, timestamp: 1)
        collector.update(phase: .pauseBottom, angle: 90, repCount: 0, timestamp: 2)
        collector.update(phase: .concentric, angle: 100, repCount: 0, timestamp: 3)

        let tempo = collector.currentTempoString()
        // Should contain digits and dashes
        XCTAssertTrue(tempo.contains("-"))
        XCTAssertNotEqual(tempo, "--")
    }

    func testTempoStringRoundsUsingSixTenthsThreshold() {
        let metric = RepMetric(
            repNumber: 1,
            peakFlexionAngle: 90,
            eccentricDuration: 2.3,
            pauseBottomDuration: 2.5,
            concentricDuration: 2.6,
            pauseTopDuration: 4.65
        )

        XCTAssertEqual(metric.tempoString, "2-2-3-5")
    }

    func testTempoStringRoundsDownBelowSixTenthsAndUpAtSixTenths() {
        let metric = RepMetric(
            repNumber: 1,
            peakFlexionAngle: 90,
            eccentricDuration: 4.1,
            pauseBottomDuration: 4.59,
            concentricDuration: 4.6,
            pauseTopDuration: 4.99
        )

        XCTAssertEqual(metric.tempoString, "4-4-5-5")
    }

    func testCurrentTempoStringUsesSixTenthsThreshold() {
        let collector = RepMetricsCollector()

        collector.update(phase: .eccentric, angle: 150, repCount: 0, timestamp: 0)
        collector.update(phase: .pauseBottom, angle: 90, repCount: 0, timestamp: 2.5)
        collector.update(phase: .concentric, angle: 100, repCount: 0, timestamp: 3.1)
        collector.update(phase: .pauseTop, angle: 150, repCount: 0, timestamp: 5.7)
        collector.update(phase: .pauseTop, angle: 150, repCount: 0, timestamp: 6.3)

        XCTAssertEqual(collector.currentTempoString(), "2-1-3-1")
    }

    // MARK: - Helpers

    private func simulateRep(_ collector: RepMetricsCollector, repNumber: Int, peakAngle: Float, at baseTime: Double) {
        simulateTimedRep(collector, repNumber: repNumber, peakAngle: peakAngle, at: baseTime)
    }

    private func simulateTimedRep(
        _ collector: RepMetricsCollector,
        repNumber: Int,
        peakAngle: Float,
        at baseTime: Double,
        eccentric: Double = 2.0,
        pauseBottom: Double = 0.5,
        concentric: Double = 1.0,
        pauseTop: Double = 0.5
    ) {
        collector.update(phase: .eccentric, angle: 160, repCount: repNumber - 1, timestamp: baseTime)
        collector.update(phase: .eccentric, angle: 130, repCount: repNumber - 1, timestamp: baseTime + eccentric * 0.3)
        if peakAngle <= 100 {
            collector.update(phase: .eccentric, angle: 100, repCount: repNumber - 1, timestamp: baseTime + eccentric * 0.6)
        }
        collector.update(phase: .eccentric, angle: peakAngle, repCount: repNumber - 1, timestamp: baseTime + eccentric * 0.9)
        let pauseBottomStart = baseTime + eccentric
        collector.update(phase: .pauseBottom, angle: peakAngle, repCount: repNumber - 1, timestamp: pauseBottomStart)
        let concentricStart = pauseBottomStart + pauseBottom
        collector.update(phase: .concentric, angle: min(peakAngle + 30, 140), repCount: repNumber - 1, timestamp: concentricStart)
        let pauseTopStart = concentricStart + concentric
        collector.update(phase: .pauseTop, angle: 160, repCount: repNumber - 1, timestamp: pauseTopStart)
        collector.update(phase: .eccentric, angle: 155, repCount: repNumber, timestamp: pauseTopStart + pauseTop)
    }

    private func simulateIdenticalRep(_ collector: RepMetricsCollector, repNumber: Int, at baseTime: Double) {
        collector.update(phase: .eccentric, angle: 160, repCount: repNumber - 1, timestamp: baseTime)
        collector.update(phase: .eccentric, angle: 130, repCount: repNumber - 1, timestamp: baseTime + 0.4)
        collector.update(phase: .eccentric, angle: 100, repCount: repNumber - 1, timestamp: baseTime + 0.8)
        collector.update(phase: .eccentric, angle: 90, repCount: repNumber - 1, timestamp: baseTime + 1.0)
        collector.update(phase: .pauseBottom, angle: 90, repCount: repNumber - 1, timestamp: baseTime + 1.5)
        collector.update(phase: .concentric, angle: 130, repCount: repNumber - 1, timestamp: baseTime + 2.0)
        collector.update(phase: .pauseTop, angle: 160, repCount: repNumber - 1, timestamp: baseTime + 3.0)
        collector.update(phase: .eccentric, angle: 155, repCount: repNumber, timestamp: baseTime + 3.5)
    }
}
