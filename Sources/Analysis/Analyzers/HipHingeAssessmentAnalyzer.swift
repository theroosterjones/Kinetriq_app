import Foundation
import simd

/// Hip hinge quality assessment filmed from the side.
/// Evaluates hinge depth (shoulder-hip-knee angle) and spinal neutrality
/// (deviation of mid-spine point from the ear-hip line).
/// Overall grade = worst sub-metric (weakest-link model).
final class HipHingeAssessmentAnalyzer: AssessmentAnalyzer {

    let assessmentType: AssessmentType = .hipHingeAssessment

    var requiredLandmarks: [PoseLandmarkType] {
        [.shoulder(side), .hip(side), .knee(side), .ankle(side), .ear(side)]
    }

    private let side: BodySide
    private let smoother = LandmarkSmoother()
    private var bestHipAngle: Float = 180    // lower = deeper hinge
    private var bestSpineDev: Float = 90     // lower = more neutral spine

    private var depthHysteresis = GradeHysteresis()
    private var spineHysteresis = GradeHysteresis()

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

        let w_shoulder = landmarks.worldPosition(for: .shoulder(side)).map { smoother.smooth3D(key: "\(side)_shoulder", position: $0, timestamp: ts) }
        let w_hip      = landmarks.worldPosition(for: .hip(side))     .map { smoother.smooth3D(key: "\(side)_hip",      position: $0, timestamp: ts) }
        let w_knee     = landmarks.worldPosition(for: .knee(side))    .map { smoother.smooth3D(key: "\(side)_knee",     position: $0, timestamp: ts) }

        // Hip hinge angle (shoulder → hip → knee)
        let hipAngle: Float
        if let ws = w_shoulder, let wh = w_hip, let wk = w_knee {
            hipAngle = AngleCalculator.angle3D(a: ws, b: wh, c: wk)
        } else {
            hipAngle = AngleCalculator.angle(a: shoulder, b: hip, c: knee)
        }

        // Spinal neutrality: perpendicular distance from mid-spine to ear-hip line,
        // expressed as an angle-equivalent (degrees deviation from straight).
        let midSpine = (shoulder + hip) / 2.0
        let spineDev: Float
        if let ear {
            let lineVec = hip - ear
            let lineLen = simd_length(lineVec)
            if lineLen > 1e-6 {
                let pointVec = midSpine - ear
                let cross = abs(lineVec.x * pointVec.y - lineVec.y * pointVec.x)
                let perpDist = cross / lineLen
                // Convert to angle: deviation relative to half the ear-hip distance
                spineDev = atan2(perpDist, lineLen / 2.0) * (180.0 / .pi)
            } else {
                spineDev = 0
            }
        } else {
            spineDev = 0
        }

        bestHipAngle = min(bestHipAngle, hipAngle)
        bestSpineDev = min(bestSpineDev, spineDev)

        let depthGrade = LetterGrade.gradeLowerIsBetter(value: hipAngle, a: 70, b: 90, c: 110, d: 130)
        let spineGrade = LetterGrade.gradeLowerIsBetter(value: spineDev, a: 5, b: 10, c: 15, d: 20)

        let displayDepth = depthHysteresis.update(depthGrade)
        let displaySpine = spineHysteresis.update(spineGrade)

        let depthColor = OverlayColor.romQuality(grade: displayDepth)
        let spineColor = OverlayColor.romQuality(grade: displaySpine)

        var instructions: [OverlayInstruction] = []

        // Spine overlay (colored by neutrality grade)
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: ear, shoulder: shoulder, hip: hip, color: spineColor))

        // Vertical plumb line through hip
        let plumbTop    = SIMD2<Float>(hip.x, hip.y - 0.20)
        let plumbBottom = SIMD2<Float>(hip.x, hip.y + 0.20)
        instructions.append(.line(from: plumbTop, to: plumbBottom, color: .white, width: 1))

        // Skeleton (colored by depth grade)
        instructions.append(.line(from: shoulder, to: hip,   color: depthColor, width: 3))
        instructions.append(.line(from: hip,      to: knee,  color: depthColor, width: 3))
        instructions.append(.line(from: knee,     to: ankle, color: depthColor, width: 3))

        // Key joints
        instructions.append(.circle(at: hip,      radius: 12, color: depthColor, filled: true))
        instructions.append(.circle(at: shoulder, radius: 10, color: spineColor, filled: true))
        instructions.append(.circle(at: knee,     radius: 10, color: .yellow,    filled: true))
        instructions.append(.circle(at: ankle,    radius: 8,  color: .orange,    filled: true))
        if let ear {
            instructions.append(.circle(at: ear, radius: 8, color: spineColor, filled: true))
        }

        // Angle labels
        instructions.append(.text("Hip: \(AngleCalculator.displayDegrees(hipAngle))\u{00B0}",
            at: SIMD2(hip.x + 0.02, hip.y - 0.04), color: .white, size: 20))

        // HUD
        let overall = currentMetrics().grade
        instructions.append(.text(overall.rawValue,
            at: SIMD2(0.85, 0.05), color: OverlayColor.romQuality(grade: overall), size: 36))
        instructions.append(.text("Hinge: \(AngleCalculator.displayDegrees(hipAngle))\u{00B0}",
            at: SIMD2(0.02, 0.05), color: depthColor, size: 18))
        instructions.append(.text("Spine: \(String(format: "%.1f", spineDev))\u{00B0} dev",
            at: SIMD2(0.02, 0.11), color: spineColor, size: 18))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .hip,   degrees: hipAngle),
                JointAngle(joint: .spine, degrees: spineDev)
            ],
            repCount: 0,
            repState: .extended,
            tempoPhase: nil,
            overlayInstructions: instructions
        )
    }

    func currentMetrics() -> AssessmentMetrics {
        let depthGrade = LetterGrade.gradeLowerIsBetter(value: bestHipAngle, a: 70, b: 90, c: 110, d: 130)
        let spineGrade = LetterGrade.gradeLowerIsBetter(value: bestSpineDev, a: 5, b: 10, c: 15, d: 20)
        let overall = max(depthGrade, spineGrade)

        var details: [String] = []
        details.append("Best hinge depth: \(AngleCalculator.displayDegrees(bestHipAngle))° (\(depthGrade.rawValue))")
        details.append("Best spine neutrality: \(String(format: "%.1f", bestSpineDev))° (\(spineGrade.rawValue))")

        return AssessmentMetrics(
            grade: overall,
            subGrades: [("Hinge Depth", depthGrade), ("Spine Neutrality", spineGrade)],
            leftROM: nil,
            rightROM: nil,
            asymmetryDeg: nil,
            asymmetryFlag: false,
            details: details
        )
    }

    func reset() {
        smoother.reset()
        bestHipAngle = 180
        bestSpineDev = 90
        depthHysteresis = GradeHysteresis()
        spineHysteresis = GradeHysteresis()
    }
}
