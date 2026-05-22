import XCTest
import simd
@testable import Kinetriq

final class RowAnalyzerTests: XCTestCase {

    func testFallsBackToBetterTrackedSideWhenSelectedSideVisibilityIsPoor() {
        let analyzer = RowAnalyzer(side: .left)
        let result = analyzer.analyze(landmarks: PoseResult(
            landmarks: [
                .leftShoulder: landmark(0.10, 0.20, visibility: 0.10),
                .leftElbow: landmark(0.20, 0.20, visibility: 0.10),
                .leftWrist: landmark(0.30, 0.20, visibility: 0.10),
                .leftHip: landmark(0.10, 0.35, visibility: 0.10),
                .rightShoulder: landmark(0.40, 0.30, visibility: 0.95),
                .rightElbow: landmark(0.50, 0.30, visibility: 0.95),
                .rightWrist: landmark(0.50, 0.40, visibility: 0.95),
                .rightHip: landmark(0.40, 0.45, visibility: 0.95)
            ],
            worldLandmarks: [:],
            timestamp: 0
        ))

        let elbowAngle = result.angles.first { $0.joint == .elbow }?.degrees
        XCTAssertNotNil(elbowAngle)
        XCTAssertEqual(elbowAngle ?? 0, 90, accuracy: 1.0)
        XCTAssertFalse(result.overlayInstructions.isEmpty)
    }

    func testKeepsOverlayWhenOppositeShoulderIsMissing() {
        let analyzer = RowAnalyzer(side: .left)
        let result = analyzer.analyze(landmarks: PoseResult(
            landmarks: [
                .leftShoulder: landmark(0.30, 0.30, visibility: 0.95),
                .leftElbow: landmark(0.40, 0.30, visibility: 0.95),
                .leftWrist: landmark(0.45, 0.40, visibility: 0.95),
                .leftHip: landmark(0.30, 0.50, visibility: 0.95)
            ],
            worldLandmarks: [:],
            timestamp: 0
        ))

        XCTAssertEqual(result.angles.count, 2)
        XCTAssertFalse(result.overlayInstructions.isEmpty)
    }

    private func landmark(_ x: Float, _ y: Float, visibility: Float) -> NormalizedLandmark {
        NormalizedLandmark(position: SIMD2<Float>(x, y), z: 0, visibility: visibility)
    }
}
