import XCTest
import simd
@testable import Kinetriq

final class DipsAnalyzerTests: XCTestCase {

    func testDipsConfigUsesSideProfileAnalyzerAndLandmarks() {
        let config = ExerciseConfig.all.first { $0.type == .dips }

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.displayName, "Dips")
        XCTAssertEqual(config?.requiresSideSelection, true)

        let analyzer = config?.makeAnalyzer(side: .left)
        XCTAssertTrue(analyzer is DipsAnalyzer)
        XCTAssertEqual(
            Set(analyzer?.requiredLandmarks ?? []),
            Set([
                .leftShoulder, .leftElbow, .leftWrist,
                .leftHip, .leftKnee, .leftAnkle
            ])
        )
    }

    func testDipsProducesElbowAndShoulderAnglesWithLowerBodyOverlay() {
        let analyzer = DipsAnalyzer(side: .left)
        let result = analyzer.analyze(landmarks: PoseResult(
            landmarks: [
                .leftShoulder: landmark(0.40, 0.30),
                .leftElbow: landmark(0.50, 0.30),
                .leftWrist: landmark(0.60, 0.30),
                .leftHip: landmark(0.40, 0.55),
                .leftKnee: landmark(0.40, 0.75),
                .leftAnkle: landmark(0.40, 0.95)
            ],
            worldLandmarks: [:],
            timestamp: 0
        ))

        XCTAssertNotNil(result.angles.first { $0.joint == .elbow })
        XCTAssertNotNil(result.angles.first { $0.joint == .shoulder })
        XCTAssertGreaterThanOrEqual(result.overlayInstructions.count, 12)
    }

    private func landmark(_ x: Float, _ y: Float) -> NormalizedLandmark {
        NormalizedLandmark(position: SIMD2<Float>(x, y), z: 0, visibility: 0.95)
    }
}
