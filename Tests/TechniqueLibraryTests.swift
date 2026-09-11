import XCTest
@testable import Kinetriq

final class TechniqueLibraryTests: XCTestCase {

    // MARK: - Helpers

    private func rep(
        _ number: Int,
        peak: Float = 90,
        eccentric: Double = 2.0,
        concentric: Double = 1.5
    ) -> RepMetric {
        RepMetric(repNumber: number, peakFlexionAngle: peak,
                  eccentricDuration: eccentric, pauseBottomDuration: 0.4,
                  concentricDuration: concentric, pauseTopDuration: 0.4)
    }

    private func exerciseRecord(
        reps: [RepMetric],
        tracking: Double = 0.95,
        meanPeakAngle: Double? = nil,
        exerciseType: ExerciseType = .squat
    ) -> AnalysisRecord {
        var payload = AnalysisPayload()
        payload.perRepMetrics = reps

        return AnalysisRecord(
            kind: .exercise,
            movementKey: exerciseType.rawValue,
            movementName: exerciseType.rawValue,
            side: .left,
            source: .savedVideo,
            duration: 30,
            poseDetectionRate: tracking,
            totalReps: reps.count,
            finalScore: 80,
            meanPeakAngle: meanPeakAngle,
            payload: payload
        )
    }

    private func assessmentRecord(asymmetryFlag: Bool, tracking: Double = 0.95) -> AnalysisRecord {
        AnalysisRecord(
            kind: .assessment,
            movementKey: AssessmentType.shoulderFlexion.rawValue,
            movementName: "Shoulder Flexion",
            side: .left,
            plane: .frontal,
            source: .savedVideo,
            duration: 12,
            poseDetectionRate: tracking,
            grade: .B,
            asymmetryDeg: asymmetryFlag ? 14 : 2,
            asymmetryFlag: asymmetryFlag,
            payload: AnalysisPayload()
        )
    }

    // MARK: - Eccentric

    func testMajorityOfRushedRepsFlagsEccentricControl() {
        let reps = [rep(1, eccentric: 0.8), rep(2, eccentric: 0.9),
                    rep(3, eccentric: 0.7), rep(4, eccentric: 2.0)]
        let faults = TechniqueFaultDetector.faults(in: exerciseRecord(reps: reps))

        XCTAssertTrue(faults.contains(.rushedEccentric))
    }

    func testOneRushedRepOutOfFourIsNotAFault() {
        let reps = [rep(1, eccentric: 0.8), rep(2), rep(3), rep(4)]
        let faults = TechniqueFaultDetector.faults(in: exerciseRecord(reps: reps))

        XCTAssertFalse(faults.contains(.rushedEccentric))
    }

    // MARK: - Depth spread

    func testWidelyScatteredPeakAnglesFlagInconsistentDepth() {
        let reps = [rep(1, peak: 75), rep(2, peak: 95), rep(3, peak: 110), rep(4, peak: 88)]
        let faults = TechniqueFaultDetector.faults(in: exerciseRecord(reps: reps))

        XCTAssertTrue(faults.contains(.inconsistentDepth))
    }

    func testTightPeakAnglesDoNotFlagInconsistentDepth() {
        let reps = [rep(1, peak: 88), rep(2, peak: 90), rep(3, peak: 91), rep(4, peak: 89)]
        let faults = TechniqueFaultDetector.faults(in: exerciseRecord(reps: reps))

        XCTAssertFalse(faults.contains(.inconsistentDepth))
    }

    // MARK: - Tempo

    func testSetSpeedingUpInItsSecondHalfIsFlagged() {
        let reps = [rep(1, eccentric: 3.0, concentric: 2.0), rep(2, eccentric: 3.0, concentric: 2.0),
                    rep(3, eccentric: 1.5, concentric: 1.2), rep(4, eccentric: 1.4, concentric: 1.1)]
        let faults = TechniqueFaultDetector.faults(in: exerciseRecord(reps: reps))

        XCTAssertTrue(faults.contains(.acceleratingTempo))
    }

    /// Slowing down is fatigue, not a fault — the scoring code already excludes it.
    func testSetSlowingDownIsNotFlaggedAsAcceleration() {
        let reps = [rep(1, eccentric: 1.5, concentric: 1.1), rep(2, eccentric: 1.5, concentric: 1.2),
                    rep(3, eccentric: 3.0, concentric: 2.0), rep(4, eccentric: 3.0, concentric: 2.2)]
        let faults = TechniqueFaultDetector.faults(in: exerciseRecord(reps: reps))

        XCTAssertFalse(faults.contains(.acceleratingTempo))
    }

    // MARK: - Range vs the user's own best

    func testRangeWellBelowThePersonalBestIsFlagged() {
        let record = exerciseRecord(reps: [rep(1), rep(2), rep(3), rep(4)], meanPeakAngle: 105)
        let faults = TechniqueFaultDetector.faults(in: record, personalBestPeakAngle: 85)

        XCTAssertTrue(faults.contains(.rangeBelowPersonalBest))
    }

    func testRangeIsNeverFlaggedWithoutHistoryToCompareAgainst() {
        let record = exerciseRecord(reps: [rep(1), rep(2), rep(3), rep(4)], meanPeakAngle: 105)
        let faults = TechniqueFaultDetector.faults(in: record, personalBestPeakAngle: nil)

        XCTAssertFalse(faults.contains(.rangeBelowPersonalBest))
    }

    func testMatchingThePersonalBestIsNotAFault() {
        let record = exerciseRecord(reps: [rep(1), rep(2), rep(3), rep(4)], meanPeakAngle: 86)
        let faults = TechniqueFaultDetector.faults(in: record, personalBestPeakAngle: 85)

        XCTAssertFalse(faults.contains(.rangeBelowPersonalBest))
    }

    // MARK: - Filming and rep count

    func testPoorTrackingIsReportedBeforeAnyTechniqueFault() {
        let reps = [rep(1, eccentric: 0.8), rep(2, eccentric: 0.8), rep(3, eccentric: 0.8)]
        let faults = TechniqueFaultDetector.faults(in: exerciseRecord(reps: reps, tracking: 0.4))

        XCTAssertEqual(faults.first, .lowTracking)
    }

    func testShortSetsReportOnlyTheRepCountProblem() {
        let faults = TechniqueFaultDetector.faults(in: exerciseRecord(reps: [rep(1, eccentric: 0.5)]))

        XCTAssertEqual(faults, [.tooFewReps])
    }

    // MARK: - Assessments

    func testFlaggedAssessmentProducesAnAsymmetryFault() {
        XCTAssertEqual(TechniqueFaultDetector.faults(in: assessmentRecord(asymmetryFlag: true)),
                       [.asymmetry])
    }

    func testBalancedAssessmentProducesNoFaults() {
        XCTAssertTrue(TechniqueFaultDetector.faults(in: assessmentRecord(asymmetryFlag: false)).isEmpty)
    }

    // MARK: - Lesson selection

    func testACleanSetEarnsNoLessons() {
        let reps = (1...5).map { rep($0, peak: Float(88 + $0 % 2)) }
        XCTAssertTrue(TechniqueLibrary.lessons(for: exerciseRecord(reps: reps)).isEmpty)
    }

    func testLessonsAreCappedSoTheResultsScreenStaysActionable() {
        let reps = [rep(1, peak: 70, eccentric: 0.8, concentric: 2.0),
                    rep(2, peak: 100, eccentric: 0.7, concentric: 2.0),
                    rep(3, peak: 120, eccentric: 0.5, concentric: 1.0),
                    rep(4, peak: 80, eccentric: 0.4, concentric: 0.9)]
        let record = exerciseRecord(reps: reps, meanPeakAngle: 110)
        let history = [TrendSample(date: Date(), kind: .exercise, meanPeakAngle: 80)]

        let lessons = TechniqueLibrary.lessons(for: record, history: history)

        XCTAssertFalse(lessons.isEmpty)
        XCTAssertLessThanOrEqual(lessons.count, TechniqueLibrary.maximumLessons)
    }

    /// The user's deepest session sets the bar, not their most recent one.
    func testPersonalBestUsesTheDeepestAngleInHistory() {
        let record = exerciseRecord(reps: [rep(1), rep(2), rep(3), rep(4)], meanPeakAngle: 105)
        let history = [
            TrendSample(date: Date(), kind: .exercise, meanPeakAngle: 84),
            TrendSample(date: Date(), kind: .exercise, meanPeakAngle: 102)
        ]

        let lessons = TechniqueLibrary.lessons(for: record, history: history)

        XCTAssertTrue(lessons.contains { $0.fault == .rangeBelowPersonalBest })
    }

    // MARK: - Content coverage

    func testEveryFaultHasContentForEveryMovementFamily() {
        let families: [MovementFamily] = [.squat, .hinge, .lunge, .horizontalPull,
                                          .verticalPull, .press, .dip, .curl, .assessment]

        for family in families {
            for fault in MovementFault.allCases {
                XCTAssertNotNil(TechniqueLibrary.lesson(for: fault, family: family),
                                "Missing \(fault.rawValue) content for \(family.rawValue)")
            }
        }
    }

    func testEveryLessonHasCuesToActOn() {
        for family in [MovementFamily.squat, .hinge, .curl, .assessment] {
            for lesson in TechniqueLibrary.catalog(for: family) {
                XCTAssertFalse(lesson.cues.isEmpty, "\(lesson.id) has no cues")
                XCTAssertFalse(lesson.title.isEmpty, "\(lesson.id) has no title")
            }
        }
    }

    func testEveryExerciseTypeMapsToAMovementFamily() {
        for exerciseType in ExerciseType.allCases {
            let family = MovementFamily(exerciseType: exerciseType)
            XCTAssertFalse(TechniqueLibrary.catalog(for: family).isEmpty)
        }
    }
}
