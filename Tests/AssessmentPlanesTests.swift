import XCTest
import simd
@testable import Kinetriq

/// Tests for the plane-aware assessment routing and the three new analyzer
/// variants introduced for v3.2 (sagittal squat, frontal hip hinge, sagittal
/// shoulder flexion).
final class AssessmentPlanesTests: XCTestCase {

    // MARK: - Routing

    func testEveryAssessmentSupportsBothPlanes() {
        for cfg in AssessmentConfig.all {
            XCTAssertEqual(
                Set(cfg.supportedPlanes), Set([ViewPlane.frontal, ViewPlane.sagittal]),
                "Assessment \(cfg.type.rawValue) should support both planes"
            )
        }
    }

    func testMakeAnalyzerReturnsTheRightConcreteTypeForEachPlane() {
        let cases: [(AssessmentType, ViewPlane, AssessmentAnalyzer.Type)] = [
            (.shoulderFlexion,    .frontal,  ShoulderFlexionAssessment.self),
            (.shoulderFlexion,    .sagittal, ShoulderFlexionSagittalAssessment.self),
            (.squatAssessment,    .frontal,  SquatAssessmentAnalyzer.self),
            (.squatAssessment,    .sagittal, SquatSagittalAssessment.self),
            (.hipHingeAssessment, .frontal,  HipHingeFrontalAssessment.self),
            (.hipHingeAssessment, .sagittal, HipHingeAssessmentAnalyzer.self),
        ]

        for (type, plane, expectedType) in cases {
            guard let cfg = AssessmentConfig.all.first(where: { $0.type == type }) else {
                XCTFail("Missing config for \(type.rawValue)"); continue
            }
            let analyzer = cfg.makeAnalyzer(side: .left, plane: plane)
            XCTAssertTrue(
                Swift.type(of: analyzer) == expectedType,
                "\(type.rawValue) / \(plane.rawValue) should produce \(expectedType) but produced \(Swift.type(of: analyzer))"
            )
        }
    }

    func testSagittalPlanesRequireSideSelectionAndFrontalDoesNot() {
        for cfg in AssessmentConfig.all {
            XCTAssertTrue(cfg.requiresSideSelection(plane: .sagittal),
                          "\(cfg.type.rawValue) sagittal should require side selection")
            XCTAssertFalse(cfg.requiresSideSelection(plane: .frontal),
                           "\(cfg.type.rawValue) frontal should not require side selection")
        }
    }

    // MARK: - SquatSagittalAssessment

    func testSquatSagittalProducesOverlaysAndKneeAngleFromSideView() {
        let analyzer = SquatSagittalAssessment(side: .left)
        let result = analyzer.analyze(landmarks: PoseResult(
            landmarks: [
                .leftShoulder: lm(0.50, 0.20, visibility: 0.95),
                .leftHip:      lm(0.50, 0.50, visibility: 0.95),
                .leftKnee:     lm(0.50, 0.70, visibility: 0.95),
                .leftAnkle:    lm(0.50, 0.95, visibility: 0.95),
                .leftEar:      lm(0.50, 0.10, visibility: 0.90)
            ],
            worldLandmarks: [
                .leftHip:   SIMD3<Float>(0.0, 0.0, 0.0),
                .leftKnee:  SIMD3<Float>(0.0, 0.5, 0.0),  // bent halfway
                .leftAnkle: SIMD3<Float>(0.5, 0.5, 0.0),  // shin horizontal — 90° at the knee
            ],
            timestamp: 0
        ))

        let kneeAngle = result.angles.first { $0.joint == .knee }?.degrees
        XCTAssertNotNil(kneeAngle)
        XCTAssertEqual(kneeAngle ?? 0, 90, accuracy: 1.0,
                       "Standing-shin geometry should produce a 90° knee angle")
        XCTAssertFalse(result.overlayInstructions.isEmpty,
                       "Sagittal squat should always render overlays when landmarks are present")
        XCTAssertEqual(result.repCount, 0, "Assessments do not count reps")
    }

    func testSquatSagittalGradesADepthAtVeryLowKneeAngle() {
        let analyzer = SquatSagittalAssessment(side: .left)
        // Feed a single deep frame: knee angle ~70° (= deep squat).
        _ = analyzer.analyze(landmarks: PoseResult(
            landmarks: [
                .leftShoulder: lm(0.50, 0.40, visibility: 0.95),
                .leftHip:      lm(0.50, 0.65, visibility: 0.95),
                .leftKnee:     lm(0.50, 0.85, visibility: 0.95),
                .leftAnkle:    lm(0.50, 1.00, visibility: 0.95)
            ],
            worldLandmarks: [
                // Hip just above knee, ankle behind knee — an angle close to 70°.
                .leftHip:   SIMD3<Float>(0.0, 0.10, 0.0),
                .leftKnee:  SIMD3<Float>(0.0, 0.0,  0.0),
                .leftAnkle: SIMD3<Float>(-0.30, 0.10, 0.0)
            ],
            timestamp: 0
        ))

        let metrics = analyzer.currentMetrics()
        XCTAssertTrue([LetterGrade.A, .B].contains(metrics.subGrades[0].grade),
                      "Deep squat (knee ~70°) should grade A or B for depth, got \(metrics.subGrades[0].grade)")
    }

    // MARK: - HipHingeFrontalAssessment

    func testHipHingeFrontalGradesALevelHipsAndShoulders() {
        let analyzer = HipHingeFrontalAssessment()
        // Perfect bilateral symmetry — no tilt, no valgus.
        _ = analyzer.analyze(landmarks: PoseResult(
            landmarks: [
                .leftShoulder:  lm(0.40, 0.20, visibility: 0.95),
                .rightShoulder: lm(0.60, 0.20, visibility: 0.95),
                .leftHip:       lm(0.45, 0.50, visibility: 0.95),
                .rightHip:      lm(0.55, 0.50, visibility: 0.95),
                .leftKnee:      lm(0.45, 0.70, visibility: 0.95),
                .rightKnee:     lm(0.55, 0.70, visibility: 0.95),
                .leftAnkle:     lm(0.45, 0.95, visibility: 0.95),
                .rightAnkle:    lm(0.55, 0.95, visibility: 0.95)
            ],
            worldLandmarks: [:],
            timestamp: 0
        ))

        let metrics = analyzer.currentMetrics()
        XCTAssertEqual(metrics.grade, .A, "Symmetric stance should grade A overall")
        XCTAssertEqual(metrics.subGrades.count, 3)
    }

    func testHipHingeFrontalFlagsExcessiveHipTilt() {
        let analyzer = HipHingeFrontalAssessment()
        // Right hip dropped well below the left → ~16° tilt: should grade F.
        _ = analyzer.analyze(landmarks: PoseResult(
            landmarks: [
                .leftShoulder:  lm(0.40, 0.20, visibility: 0.95),
                .rightShoulder: lm(0.60, 0.20, visibility: 0.95),
                .leftHip:       lm(0.40, 0.50, visibility: 0.95),
                .rightHip:      lm(0.60, 0.55, visibility: 0.95),
                .leftKnee:      lm(0.40, 0.70, visibility: 0.95),
                .rightKnee:     lm(0.60, 0.75, visibility: 0.95),
                .leftAnkle:     lm(0.40, 0.95, visibility: 0.95),
                .rightAnkle:    lm(0.60, 0.95, visibility: 0.95)
            ],
            worldLandmarks: [:],
            timestamp: 0
        ))

        let metrics = analyzer.currentMetrics()
        let hipGrade = metrics.subGrades.first { $0.label == "Hip Level" }?.grade
        XCTAssertNotNil(hipGrade)
        XCTAssertGreaterThanOrEqual(hipGrade ?? .A, .D,
                                    "A clearly tilted hip line should drop the Hip Level grade to D or worse")
    }

    // MARK: - ShoulderFlexionSagittalAssessment

    func testShoulderFlexionSagittalProducesOverlaysAndROMAngle() {
        let analyzer = ShoulderFlexionSagittalAssessment(side: .left)
        let result = analyzer.analyze(landmarks: PoseResult(
            landmarks: [
                .leftShoulder: lm(0.50, 0.30, visibility: 0.95),
                .leftElbow:    lm(0.55, 0.20, visibility: 0.95),
                .leftWrist:    lm(0.55, 0.10, visibility: 0.95),
                .leftHip:      lm(0.50, 0.60, visibility: 0.95),
                .leftEar:      lm(0.50, 0.20, visibility: 0.90)
            ],
            worldLandmarks: [
                .leftShoulder: SIMD3<Float>(0.0, 0.0, 0.0),
                .leftWrist:    SIMD3<Float>(0.0, 1.0, 0.0),  // arm straight up
                .leftHip:      SIMD3<Float>(0.0, -1.0, 0.0)  // hip below shoulder
            ],
            timestamp: 0
        ))

        let romAngle = result.angles.first { $0.joint == .shoulder }?.degrees
        XCTAssertNotNil(romAngle)
        XCTAssertEqual(romAngle ?? 0, 180, accuracy: 1.0,
                       "Arm overhead with hip straight below should produce ~180° flexion")
        XCTAssertFalse(result.overlayInstructions.isEmpty)

        let metrics = analyzer.currentMetrics()
        XCTAssertEqual(metrics.grade, .A,
                       "180° peak ROM should grade A on the higher-is-better scale")
    }

    func testShoulderFlexionSagittalFallsBackToBetterTrackedSide() {
        let analyzer = ShoulderFlexionSagittalAssessment(side: .left)
        let result = analyzer.analyze(landmarks: PoseResult(
            landmarks: [
                .leftShoulder:  lm(0.50, 0.30, visibility: 0.05),
                .leftElbow:     lm(0.55, 0.20, visibility: 0.05),
                .leftWrist:     lm(0.55, 0.10, visibility: 0.05),
                .leftHip:       lm(0.50, 0.60, visibility: 0.05),
                .rightShoulder: lm(0.50, 0.30, visibility: 0.95),
                .rightElbow:    lm(0.55, 0.20, visibility: 0.95),
                .rightWrist:    lm(0.55, 0.10, visibility: 0.95),
                .rightHip:      lm(0.50, 0.60, visibility: 0.95)
            ],
            worldLandmarks: [:],
            timestamp: 0
        ))

        XCTAssertFalse(result.overlayInstructions.isEmpty,
                       "Should still render overlays after auto-fallback to right side")
    }

    // MARK: - Helpers

    private func lm(_ x: Float, _ y: Float, visibility: Float) -> NormalizedLandmark {
        NormalizedLandmark(position: SIMD2<Float>(x, y), z: 0, visibility: visibility)
    }
}
