import XCTest
import simd
@testable import Kinetriq

final class LungeAnalyzerTests: XCTestCase {

    /// A real missed rep from a user video: the top of the rep peaked at 154° of knee
    /// extension, one degree short of the old 155° gate, so the counter never re-armed.
    func testCountsRepWhoseTopPeaksAt154Degrees() {
        let counter = RepCounter(extendedThreshold: 145, flexedThreshold: 100)

        counter.update(angle: 154, timestamp: 0.0)
        counter.update(angle: 68, timestamp: 1.0)
        counter.update(angle: 154, timestamp: 2.0)

        XCTAssertEqual(counter.count, 1)
    }

    /// The 145° gate still has to reject a partial that never returns near lockout.
    func testDoesNotCountPartialRepThatStaysFlexed() {
        let counter = RepCounter(extendedThreshold: 145, flexedThreshold: 100)

        counter.update(angle: 154, timestamp: 0.0)
        counter.update(angle: 68, timestamp: 1.0)
        counter.update(angle: 120, timestamp: 2.0)

        XCTAssertEqual(counter.count, 0)
    }

    func testKneeAngleDrivesRepCountingFromSelectedSide() {
        let analyzer = LungeAnalyzer(side: .left)
        let result = analyzer.analyze(landmarks: PoseResult(
            landmarks: [
                .leftShoulder: landmark(0.50, 0.20),
                .leftHip: landmark(0.50, 0.45),
                .leftKnee: landmark(0.50, 0.65),
                .leftAnkle: landmark(0.50, 0.85)
            ],
            worldLandmarks: [:],
            timestamp: 0
        ))

        let kneeAngle = result.angles.first { $0.joint == .knee }?.degrees
        XCTAssertNotNil(kneeAngle)
        XCTAssertEqual(kneeAngle ?? 0, 180, accuracy: 1.0)
    }

    private func landmark(_ x: Float, _ y: Float, visibility: Float = 0.95) -> NormalizedLandmark {
        NormalizedLandmark(position: SIMD2<Float>(x, y), z: 0, visibility: visibility)
    }
}
