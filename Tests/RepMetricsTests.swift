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
            simulateIdenticalRep(collector, repNumber: i, at: Double(i - 1) * 4)
        }

        let score = collector.computeScore()
        XCTAssertNotNil(score)
        XCTAssertEqual(score, 100)
    }

    // MARK: - High ROM variance = low score

    func testHighROMVarianceLowersScore() {
        let collector = RepMetricsCollector()
        // Peak angles: 80, 100, 120 → stddev ≈ 16.3 → ROM_Score = 100 - 5*16.3 ≈ 18
        simulateRep(collector, repNumber: 1, peakAngle: 80, at: 0)
        simulateRep(collector, repNumber: 2, peakAngle: 100, at: 4)
        simulateRep(collector, repNumber: 3, peakAngle: 120, at: 8)

        let score = collector.computeScore()
        XCTAssertNotNil(score)
        XCTAssertLessThan(score!, 50)
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

    // MARK: - Helpers

    private func simulateRep(_ collector: RepMetricsCollector, repNumber: Int, peakAngle: Float, at baseTime: Double) {
        collector.update(phase: .eccentric, angle: 160, repCount: repNumber - 1, timestamp: baseTime)
        collector.update(phase: .eccentric, angle: peakAngle, repCount: repNumber - 1, timestamp: baseTime + 0.5)
        collector.update(phase: .pauseBottom, angle: peakAngle, repCount: repNumber - 1, timestamp: baseTime + 1.0)
        collector.update(phase: .concentric, angle: 140, repCount: repNumber - 1, timestamp: baseTime + 1.5)
        collector.update(phase: .pauseTop, angle: 160, repCount: repNumber - 1, timestamp: baseTime + 2.0)
        // Rep completes
        collector.update(phase: .eccentric, angle: 155, repCount: repNumber, timestamp: baseTime + 2.5)
    }

    private func simulateIdenticalRep(_ collector: RepMetricsCollector, repNumber: Int, at baseTime: Double) {
        collector.update(phase: .eccentric, angle: 160, repCount: repNumber - 1, timestamp: baseTime)
        collector.update(phase: .eccentric, angle: 90, repCount: repNumber - 1, timestamp: baseTime + 1.0)
        collector.update(phase: .pauseBottom, angle: 90, repCount: repNumber - 1, timestamp: baseTime + 1.5)
        collector.update(phase: .concentric, angle: 130, repCount: repNumber - 1, timestamp: baseTime + 2.0)
        collector.update(phase: .pauseTop, angle: 160, repCount: repNumber - 1, timestamp: baseTime + 3.0)
        collector.update(phase: .eccentric, angle: 155, repCount: repNumber, timestamp: baseTime + 3.5)
    }
}
