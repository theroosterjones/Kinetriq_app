import XCTest
import simd
@testable import Kinetriq

final class LatPulldownFrontAnalyzerTests: XCTestCase {

    func testCountsRepFromShoulderFallbackWhenWristsAreOccluded() {
        let analyzer = LatPulldownFrontAnalyzer(side: .left)
        var result = FrameAnalysis.empty

        let frames: [(Double, Float)] = [
            (0.00, 0.02), (0.12, 0.02),
            (0.28, 0.80), (0.44, 0.80), (0.60, 0.80),
            (0.78, 0.02), (0.94, 0.02), (1.10, 0.02)
        ]

        for (timestamp, elbowY) in frames {
            result = analyzer.analyze(landmarks: pose(elbowY: elbowY, timestamp: timestamp))
        }

        XCTAssertEqual(result.repCount, 1)
    }

    private func pose(elbowY: Float, timestamp: Double) -> PoseResult {
        PoseResult(
            landmarks: [
                .leftShoulder: landmark(0.40, 0.30),
                .rightShoulder: landmark(0.60, 0.30),
                .leftElbow: landmark(0.30, elbowY),
                .rightElbow: landmark(0.70, elbowY),
                .leftWrist: landmark(0.30, elbowY + 0.12, visibility: 0.10),
                .rightWrist: landmark(0.70, elbowY + 0.12, visibility: 0.10),
                .leftHip: landmark(0.42, 0.65),
                .rightHip: landmark(0.58, 0.65)
            ],
            worldLandmarks: [:],
            timestamp: timestamp
        )
    }

    private func landmark(_ x: Float, _ y: Float, visibility: Float = 0.95) -> NormalizedLandmark {
        NormalizedLandmark(position: SIMD2<Float>(x, y), z: 0, visibility: visibility)
    }
}
