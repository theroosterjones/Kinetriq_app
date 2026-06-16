import XCTest
import simd
@testable import Kinetriq

final class CustomOverlayBuilderTests: XCTestCase {

    func testNoOptionsProduceNoCustomOverlayInstructions() {
        let instructions = CustomOverlayBuilder.instructions(
            options: [],
            landmarks: pose,
            side: .left
        )

        XCTAssertTrue(instructions.isEmpty)
    }

    func testSelectedAlignmentOptionsProduceExtendedLines() {
        let instructions = CustomOverlayBuilder.instructions(
            options: [.centerFoot, .forearmAlignment, .lowerLegAlignment, .backAlignment],
            landmarks: pose,
            side: .left
        )

        let extendedLineCount = instructions.filter {
            if case .extendedLine = $0 { return true }
            return false
        }.count

        XCTAssertEqual(extendedLineCount, 4)
    }

    func testCenterFootLocksAfterStableSamplesAndIgnoresJitter() {
        let state = CustomOverlayState()
        var lockedThrough: SIMD2<Float>?

        for i in 0..<6 {
            let jitter = Float(i) * 0.001
            let instruction = CustomOverlayBuilder.instructions(
                options: [.centerFoot],
                landmarks: pose(heelX: 0.41 + jitter, toeX: 0.50 + jitter),
                side: .left,
                state: state
            ).first

            if i == 5, case let .extendedLine(_, through, _, _)? = instruction {
                lockedThrough = through
            }
        }

        let jitteredInstruction = CustomOverlayBuilder.instructions(
            options: [.centerFoot],
            landmarks: pose(heelX: 0.43, toeX: 0.52),
            side: .left,
            state: state
        ).first

        guard case let .extendedLine(_, through, _, _)? = jitteredInstruction else {
            XCTFail("Expected locked center-foot line")
            return
        }

        XCTAssertEqual(through.x, lockedThrough?.x ?? -1, accuracy: 0.0001)
        XCTAssertEqual(through.y, lockedThrough?.y ?? -1, accuracy: 0.0001)
    }

    func testForearmAlignmentUsesWristToElbowLandmarksDirectly() {
        let state = CustomOverlayState()
        let instruction = CustomOverlayBuilder.instructions(
            options: [.forearmAlignment],
            landmarks: pose(wrist: SIMD2<Float>(0.40, 0.50), elbow: SIMD2<Float>(0.60, 0.85)),
            side: .left,
            state: state
        ).first

        guard case let .extendedLine(from, through, _, _)? = instruction else {
            XCTFail("Expected forearm alignment line")
            return
        }

        XCTAssertEqual(from.x, 0.40, accuracy: 0.0001)
        XCTAssertEqual(from.y, 0.50, accuracy: 0.0001)
        XCTAssertEqual(through.x, 0.60, accuracy: 0.0001)
        XCTAssertEqual(through.y, 0.85, accuracy: 0.0001)
    }

    func testBackAlignmentUsesSpineMidlineForFrontBackExercises() {
        let instruction = CustomOverlayBuilder.instructions(
            options: [.backAlignment],
            landmarks: PoseResult(
                landmarks: [
                    .leftShoulder: landmark(0.35, 0.25),
                    .rightShoulder: landmark(0.65, 0.25),
                    .leftHip: landmark(0.42, 0.60),
                    .rightHip: landmark(0.58, 0.60)
                ],
                worldLandmarks: [:],
                timestamp: 0
            ),
            side: .left,
            exerciseType: .overheadPress
        ).first

        guard case let .extendedLine(from, through, _, _)? = instruction else {
            XCTFail("Expected back alignment line")
            return
        }

        XCTAssertEqual(from.x, 0.50, accuracy: 0.0001)
        XCTAssertEqual(from.y, 0.60, accuracy: 0.0001)
        XCTAssertEqual(through.x, 0.50, accuracy: 0.0001)
        XCTAssertEqual(through.y, 0.25, accuracy: 0.0001)
    }

    private var pose: PoseResult {
        pose(heelX: 0.41, toeX: 0.50)
    }

    private func pose(heelX: Float, toeX: Float) -> PoseResult {
        pose(
            wrist: SIMD2<Float>(0.55, 0.50),
            elbow: SIMD2<Float>(0.48, 0.38),
            heelX: heelX,
            toeX: toeX
        )
    }

    private func pose(wrist: SIMD2<Float>, elbow: SIMD2<Float>) -> PoseResult {
        pose(wrist: wrist, elbow: elbow, heelX: 0.41, toeX: 0.50)
    }

    private func pose(
        wrist: SIMD2<Float>,
        elbow: SIMD2<Float>,
        heelX: Float,
        toeX: Float
    ) -> PoseResult {
        PoseResult(
            landmarks: [
                .leftShoulder: landmark(0.40, 0.25),
                .leftElbow: landmark(elbow.x, elbow.y),
                .leftWrist: landmark(wrist.x, wrist.y),
                .leftHip: landmark(0.42, 0.55),
                .leftKnee: landmark(0.44, 0.74),
                .leftAnkle: landmark(0.45, 0.92),
                .leftHeel: landmark(heelX, 0.96),
                .leftFootIndex: landmark(toeX, 0.96)
            ],
            worldLandmarks: [:],
            timestamp: 0
        )
    }

    private func landmark(_ x: Float, _ y: Float) -> NormalizedLandmark {
        NormalizedLandmark(position: SIMD2<Float>(x, y), z: 0, visibility: 0.95)
    }
}
