import XCTest
import simd
@testable import Kinetriq

final class LandmarkSmootherAnchorTests: XCTestCase {

    func testStationaryAnchorLocksAndIgnoresJitter() {
        let smoother = LandmarkSmoother()
        var locked: SIMD2<Float>?

        for i in 0..<5 {
            let jitter = Float(i) * 0.001
            locked = smoother.stabilizeAnchor(
                key: "wrist",
                position: SIMD2<Float>(0.40 + jitter, 0.50),
                stableRadius: 0.01,
                releaseRadius: 0.05,
                requiredSamples: 5
            )
        }

        let afterJitter = smoother.stabilizeAnchor(
            key: "wrist",
            position: SIMD2<Float>(0.42, 0.50),
            stableRadius: 0.01,
            releaseRadius: 0.05,
            requiredSamples: 5
        )

        XCTAssertEqual(afterJitter.x, locked?.x ?? -1, accuracy: 0.0001)
        XCTAssertEqual(afterJitter.y, locked?.y ?? -1, accuracy: 0.0001)
    }

    func testStationaryAnchorReleasesAfterSustainedRelocation() {
        let smoother = LandmarkSmoother()
        for _ in 0..<5 {
            _ = smoother.stabilizeAnchor(
                key: "ankle",
                position: SIMD2<Float>(0.40, 0.80),
                stableRadius: 0.01,
                releaseRadius: 0.05,
                requiredSamples: 5,
                requiredReleaseFrames: 3
            )
        }

        var relocated = SIMD2<Float>.zero
        for _ in 0..<3 {
            relocated = smoother.stabilizeAnchor(
                key: "ankle",
                position: SIMD2<Float>(0.55, 0.80),
                stableRadius: 0.01,
                releaseRadius: 0.05,
                requiredSamples: 5,
                requiredReleaseFrames: 3
            )
        }

        XCTAssertEqual(relocated.x, 0.55, accuracy: 0.0001)
        XCTAssertEqual(relocated.y, 0.80, accuracy: 0.0001)
    }
}
