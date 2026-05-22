import Foundation
import simd

/// Squat quality assessment filmed from the **sagittal plane** (strict side profile).
///
/// Sub-metrics graded:
///   - **Depth** — single-side knee angle (hip → knee → ankle). Lower is deeper.
///   - **Knee Flexion** — total knee flexion at the bottom (180° − knee angle).
///     This is exposed alongside Depth as a more clinically familiar number for
///     PTs/coaches; both are derived from the same vertex angle so they share a
///     letter grade.
///   - **Torso Lean** — angle of the shoulder→hip line from vertical. Some forward
///     lean is expected on a squat (especially low bar / pendulum / front-leaning
///     setups), so unlike the rear-view assessment this is graded against a band
///     rather than purely lower-is-better. Excessive lean (>50°) is flagged.
///
/// Overall grade = worst sub-metric (weakest-link model).
final class SquatSagittalAssessment: AssessmentAnalyzer {

    let assessmentType: AssessmentType = .squatAssessment
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [.shoulder(side), .hip(side), .knee(side), .ankle(side), .ear(side)]
    }

    private let smoother = LandmarkSmoother()

    /// Best (deepest) knee angle observed across the whole video. Lower is deeper.
    private var bestKneeAngle: Float = 180
    /// Torso lean (deg from vertical) at the moment of best depth — captures the
    /// posture *at* the bottom rather than the literal max lean across the clip,
    /// which would otherwise be biased by the descent and ascent phases.
    private var torsoLeanAtBestDepth: Float = 0
    /// Worst-observed torso lean across the whole clip. Used purely as a safety
    /// flag in `details` so the user is alerted to a transient form breakdown
    /// even if their bottom position was acceptable.
    private var worstTorsoLean: Float = 0

    private var depthHysteresis = GradeHysteresis()
    private var leanHysteresis  = GradeHysteresis()

    init(side: BodySide = .left) {
        self.side = side
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawShoulder = landmarks.position(for: .shoulder(side)),
              let rawHip      = landmarks.position(for: .hip(side)),
              let rawKnee     = landmarks.position(for: .knee(side)),
              let rawAnkle    = landmarks.position(for: .ankle(side)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let shoulder = smoother.smooth(key: "\(side)_shoulder", position: rawShoulder, timestamp: ts)
        let hip      = smoother.smooth(key: "\(side)_hip",      position: rawHip,      timestamp: ts)
        let knee     = smoother.smooth(key: "\(side)_knee",     position: rawKnee,     timestamp: ts)
        let ankle    = smoother.smooth(key: "\(side)_ankle",    position: rawAnkle,    timestamp: ts)
        let ear      = landmarks.position(for: .ear(side))
            .map { smoother.smooth(key: "\(side)_ear", position: $0, timestamp: ts) }

        let w_hip   = landmarks.worldPosition(for: .hip(side))  .map { smoother.smooth3D(key: "\(side)_hip",   position: $0, timestamp: ts) }
        let w_knee  = landmarks.worldPosition(for: .knee(side)) .map { smoother.smooth3D(key: "\(side)_knee",  position: $0, timestamp: ts) }
        let w_ankle = landmarks.worldPosition(for: .ankle(side)).map { smoother.smooth3D(key: "\(side)_ankle", position: $0, timestamp: ts) }

        // Knee angle — primary depth driver. 3D when available (foreshortening-safe).
        let kneeAngle: Float
        if let wh = w_hip, let wk = w_knee, let wa = w_ankle {
            kneeAngle = AngleCalculator.angle3D(a: wh, b: wk, c: wa)
        } else {
            kneeAngle = AngleCalculator.angle(a: hip, b: knee, c: ankle)
        }

        // Torso lean from vertical — purely 2D since we want the *visual* sagittal
        // lean as the camera sees it, not the 3D world rotation (which would
        // require a calibrated camera reference frame).
        let dx = shoulder.x - hip.x
        let dy = shoulder.y - hip.y
        let torsoLean = atan2(abs(dx), abs(dy)) * (180.0 / .pi)

        // Track best depth and capture lean at that moment.
        if kneeAngle < bestKneeAngle {
            bestKneeAngle = kneeAngle
            torsoLeanAtBestDepth = torsoLean
        }
        worstTorsoLean = max(worstTorsoLean, torsoLean)

        let depthGrade = LetterGrade.gradeLowerIsBetter(value: kneeAngle, a: 80, b: 95, c: 110, d: 125)
        let leanGrade  = leanGradeFor(torsoLean, atKneeAngle: kneeAngle)

        let displayDepth = depthHysteresis.update(depthGrade)
        let displayLean  = leanHysteresis.update(leanGrade)

        let depthColor = OverlayColor.romQuality(grade: displayDepth)
        let leanColor  = OverlayColor.romQuality(grade: displayLean)

        var instructions: [OverlayInstruction] = []

        // Spine overlay (drawn first so it sits behind joint labels)
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: ear, shoulder: shoulder, hip: hip, color: leanColor))

        // Vertical reference plumb line through the hip to make torso lean obvious.
        let plumbTop    = SIMD2<Float>(hip.x, hip.y - 0.30)
        let plumbBottom = SIMD2<Float>(hip.x, hip.y + 0.05)
        instructions.append(.line(from: plumbTop, to: plumbBottom, color: .white, width: 1))

        // Skeleton (legs colored by depth grade, torso by lean grade)
        instructions.append(.line(from: shoulder, to: hip,   color: leanColor,  width: 3))
        instructions.append(.line(from: hip,      to: knee,  color: depthColor, width: 3))
        instructions.append(.line(from: knee,     to: ankle, color: depthColor, width: 3))

        // Key joints
        instructions.append(.circle(at: hip,      radius: 12, color: depthColor, filled: true))
        instructions.append(.circle(at: knee,     radius: 12, color: depthColor, filled: true))
        instructions.append(.circle(at: shoulder, radius: 10, color: leanColor,  filled: true))
        instructions.append(.circle(at: ankle,    radius: 8,  color: .orange,    filled: true))

        // Joint labels
        instructions.append(.text("Knee: \(AngleCalculator.displayDegrees(kneeAngle))\u{00B0}",
            at: SIMD2(knee.x + 0.02, knee.y - 0.04), color: .white, size: 18))
        instructions.append(.text("Lean: \(AngleCalculator.displayDegrees(torsoLean))\u{00B0}",
            at: SIMD2(hip.x + 0.02, hip.y - 0.04), color: .white, size: 16))

        // HUD
        let overall = currentMetrics().grade
        instructions.append(.text(overall.rawValue,
            at: SIMD2(0.85, 0.05), color: OverlayColor.romQuality(grade: overall), size: 36))
        instructions.append(.text("Depth: \(AngleCalculator.displayDegrees(kneeAngle))\u{00B0}",
            at: SIMD2(0.02, 0.05), color: depthColor, size: 18))
        instructions.append(.text("Flexion: \(AngleCalculator.displayDegrees(180 - kneeAngle))\u{00B0}",
            at: SIMD2(0.02, 0.11), color: depthColor, size: 18))
        instructions.append(.text("Torso lean: \(AngleCalculator.displayDegrees(torsoLean))\u{00B0}",
            at: SIMD2(0.02, 0.17), color: leanColor, size: 18))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .knee, degrees: kneeAngle),
                JointAngle(joint: .hip,  degrees: torsoLean)
            ],
            repCount: 0,
            repState: .extended,
            tempoPhase: nil,
            overlayInstructions: instructions
        )
    }

    func currentMetrics() -> AssessmentMetrics {
        let depthGrade = LetterGrade.gradeLowerIsBetter(value: bestKneeAngle, a: 80, b: 95, c: 110, d: 125)
        let leanGrade  = leanGradeFor(torsoLeanAtBestDepth, atKneeAngle: bestKneeAngle)
        let overall    = max(depthGrade, leanGrade)

        var details: [String] = []
        details.append("Best depth: \(AngleCalculator.displayDegrees(bestKneeAngle))° (\(depthGrade.rawValue))")
        details.append("Peak knee flexion: \(AngleCalculator.displayDegrees(180 - bestKneeAngle))°")
        details.append("Torso lean at depth: \(AngleCalculator.displayDegrees(torsoLeanAtBestDepth))° (\(leanGrade.rawValue))")
        if worstTorsoLean > torsoLeanAtBestDepth + 10 {
            details.append("Max lean during set: \(AngleCalculator.displayDegrees(worstTorsoLean))° (mid-rep form check)")
        }

        return AssessmentMetrics(
            grade: overall,
            subGrades: [("Depth", depthGrade), ("Torso Lean", leanGrade)],
            leftROM: nil,
            rightROM: nil,
            asymmetryDeg: nil,
            asymmetryFlag: false,
            details: details
        )
    }

    func reset() {
        smoother.reset()
        bestKneeAngle = 180
        torsoLeanAtBestDepth = 0
        worstTorsoLean = 0
        depthHysteresis = GradeHysteresis()
        leanHysteresis  = GradeHysteresis()
    }

    /// Grades torso lean from vertical, with context-aware thresholds based on squat depth.
    ///
    /// **Shallow / mid squat** (knee angle ≥ 90°):
    /// - 0–25°: A  |  26–35°: B  |  36–45°: C  |  46–55°: D  |  56°+: F
    ///
    /// **Deep squat** (knee angle < 90°): greater forward lean is anatomically expected
    /// due to hip/ankle mobility demands. Thresholds are more forgiving:
    /// - 0–50°: A  |  51–60°: B  |  61–70°: C  |  71–80°: D  |  81°+: F
    private func leanGradeFor(_ degrees: Float, atKneeAngle kneeAngle: Float) -> LetterGrade {
        if kneeAngle < 90 {
            return LetterGrade.gradeLowerIsBetter(value: degrees, a: 50, b: 60, c: 70, d: 80)
        } else {
            return LetterGrade.gradeLowerIsBetter(value: degrees, a: 25, b: 35, c: 45, d: 55)
        }
    }
}
