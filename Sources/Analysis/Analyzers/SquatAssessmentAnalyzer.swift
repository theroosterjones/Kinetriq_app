import Foundation
import simd

/// Squat quality assessment filmed from behind (frontal plane).
/// Evaluates depth (hip-knee-ankle angle), trunk lean (shoulder-hip vs vertical),
/// and knee tracking (valgus/varus offset as % of hip width).
/// Overall grade = worst sub-metric (weakest-link model).
final class SquatAssessmentAnalyzer: AssessmentAnalyzer {

    let assessmentType: AssessmentType = .squatAssessment

    var requiredLandmarks: [PoseLandmarkType] {
        [
            .shoulder(.left), .shoulder(.right),
            .hip(.left),      .hip(.right),
            .knee(.left),     .knee(.right),
            .ankle(.left),    .ankle(.right),
            .ear(.left),      .ear(.right)
        ]
    }

    private let smoother = LandmarkSmoother()
    private var bestDepthAngle: Float = 180   // lower = deeper squat
    private var bestTrunkLean: Float = 90     // lower = more upright
    private var bestKneeTracking: Float = 100 // lower = less valgus

    // Hysteresis for dynamic color stability
    private var depthHysteresis = GradeHysteresis()
    private var trunkHysteresis = GradeHysteresis()
    private var kneeHysteresis  = GradeHysteresis()

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawLS = landmarks.position(for: .shoulder(.left)),
              let rawRS = landmarks.position(for: .shoulder(.right)),
              let rawLH = landmarks.position(for: .hip(.left)),
              let rawRH = landmarks.position(for: .hip(.right)),
              let rawLK = landmarks.position(for: .knee(.left)),
              let rawRK = landmarks.position(for: .knee(.right)),
              let rawLA = landmarks.position(for: .ankle(.left)),
              let rawRA = landmarks.position(for: .ankle(.right)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let lShoulder = smoother.smooth(key: "left_shoulder",  position: rawLS, timestamp: ts)
        let rShoulder = smoother.smooth(key: "right_shoulder", position: rawRS, timestamp: ts)
        let lHip      = smoother.smooth(key: "left_hip",       position: rawLH, timestamp: ts)
        let rHip      = smoother.smooth(key: "right_hip",      position: rawRH, timestamp: ts)
        let lKnee     = smoother.smooth(key: "left_knee",      position: rawLK, timestamp: ts)
        let rKnee     = smoother.smooth(key: "right_knee",     position: rawRK, timestamp: ts)
        let lAnkle    = smoother.smooth(key: "left_ankle",     position: rawLA, timestamp: ts)
        let rAnkle    = smoother.smooth(key: "right_ankle",    position: rawRA, timestamp: ts)

        let lEar = landmarks.position(for: .ear(.left))
            .map { smoother.smooth(key: "left_ear", position: $0, timestamp: ts) }
        let rEar = landmarks.position(for: .ear(.right))
            .map { smoother.smooth(key: "right_ear", position: $0, timestamp: ts) }

        // 3D angles where available
        let wLH = landmarks.worldPosition(for: .hip(.left))    .map { smoother.smooth3D(key: "left_hip",    position: $0, timestamp: ts) }
        let wRH = landmarks.worldPosition(for: .hip(.right))   .map { smoother.smooth3D(key: "right_hip",   position: $0, timestamp: ts) }
        let wLK = landmarks.worldPosition(for: .knee(.left))   .map { smoother.smooth3D(key: "left_knee",   position: $0, timestamp: ts) }
        let wRK = landmarks.worldPosition(for: .knee(.right))  .map { smoother.smooth3D(key: "right_knee",  position: $0, timestamp: ts) }
        let wLA = landmarks.worldPosition(for: .ankle(.left))  .map { smoother.smooth3D(key: "left_ankle",  position: $0, timestamp: ts) }
        let wRA = landmarks.worldPosition(for: .ankle(.right)) .map { smoother.smooth3D(key: "right_ankle", position: $0, timestamp: ts) }

        // Depth: average of bilateral knee angles (hip-knee-ankle)
        let leftKneeAngle: Float
        if let wh = wLH, let wk = wLK, let wa = wLA {
            leftKneeAngle = AngleCalculator.angle3D(a: wh, b: wk, c: wa)
        } else {
            leftKneeAngle = AngleCalculator.angle(a: lHip, b: lKnee, c: lAnkle)
        }
        let rightKneeAngle: Float
        if let wh = wRH, let wk = wRK, let wa = wRA {
            rightKneeAngle = AngleCalculator.angle3D(a: wh, b: wk, c: wa)
        } else {
            rightKneeAngle = AngleCalculator.angle(a: rHip, b: rKnee, c: rAnkle)
        }
        let avgKneeAngle = (leftKneeAngle + rightKneeAngle) / 2.0

        // Trunk lean: angle of shoulder-mid to hip-mid from vertical
        let shoulderMid = (lShoulder + rShoulder) / 2.0
        let hipMid = (lHip + rHip) / 2.0
        let dx = shoulderMid.x - hipMid.x
        let dy = shoulderMid.y - hipMid.y
        let trunkLeanDeg = atan2(abs(dx), abs(dy)) * (180.0 / .pi)

        // Knee tracking: worst valgus offset of either knee as % of hip width
        func kneeOffset(hip: SIMD2<Float>, knee: SIMD2<Float>, ankle: SIMD2<Float>) -> Float {
            let mid = (hip + ankle) / 2.0
            return knee.x - mid.x
        }
        let hipWidth = abs(rHip.x - lHip.x)
        let lOff = hipWidth > 1e-4 ? abs(kneeOffset(hip: lHip, knee: lKnee, ankle: lAnkle) / hipWidth) * 100 : 0
        let rOff = hipWidth > 1e-4 ? abs(kneeOffset(hip: rHip, knee: rKnee, ankle: rAnkle) / hipWidth) * 100 : 0
        let worstKneeOff = max(lOff, rOff)

        // Track best values
        bestDepthAngle = min(bestDepthAngle, avgKneeAngle)
        bestTrunkLean = min(bestTrunkLean, trunkLeanDeg)
        bestKneeTracking = min(bestKneeTracking, worstKneeOff)

        // Grade current frame
        let depthGrade = LetterGrade.gradeLowerIsBetter(value: avgKneeAngle, a: 80, b: 95, c: 110, d: 125)
        let trunkGrade = LetterGrade.gradeLowerIsBetter(value: trunkLeanDeg, a: 15, b: 25, c: 35, d: 45)
        let kneeGrade  = LetterGrade.gradeLowerIsBetter(value: worstKneeOff, a: 5, b: 10, c: 15, d: 20)

        let displayDepth = depthHysteresis.update(depthGrade)
        let displayTrunk = trunkHysteresis.update(trunkGrade)
        let displayKnee  = kneeHysteresis.update(kneeGrade)

        let depthColor = OverlayColor.romQuality(grade: displayDepth)
        let trunkColor = OverlayColor.romQuality(grade: displayTrunk)
        let kneeColor  = OverlayColor.romQuality(grade: displayKnee)

        let earMid: SIMD2<Float>?
        if let le = lEar, let re = rEar { earMid = (le + re) / 2.0 }
        else { earMid = lEar ?? rEar }

        var instructions: [OverlayInstruction] = []

        // Spine overlay
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: earMid, shoulder: shoulderMid, hip: hipMid))

        // Trunk line (colored by lean grade)
        instructions.append(.line(from: shoulderMid, to: hipMid, color: trunkColor, width: 3))

        // Shoulder girdle and hip baseline
        instructions.append(.line(from: lShoulder, to: rShoulder, color: .yellow, width: 3))
        instructions.append(.line(from: lHip, to: rHip, color: .cyan, width: 3))

        // Leg lines (colored by depth grade)
        instructions.append(.line(from: lHip,  to: lKnee,  color: depthColor, width: 3))
        instructions.append(.line(from: lKnee, to: lAnkle, color: depthColor, width: 3))
        instructions.append(.line(from: rHip,  to: rKnee,  color: depthColor, width: 3))
        instructions.append(.line(from: rKnee, to: rAnkle, color: depthColor, width: 3))

        // Knee tracking guide lines
        instructions.append(.line(from: lHip, to: lAnkle, color: .white, width: 1))
        instructions.append(.line(from: rHip, to: rAnkle, color: .white, width: 1))

        // Joint circles (knees colored by tracking grade)
        instructions.append(.circle(at: lShoulder, radius: 10, color: .yellow,   filled: true))
        instructions.append(.circle(at: rShoulder, radius: 10, color: .yellow,   filled: true))
        instructions.append(.circle(at: lHip,      radius: 10, color: .cyan,     filled: true))
        instructions.append(.circle(at: rHip,      radius: 10, color: .cyan,     filled: true))
        instructions.append(.circle(at: lKnee,     radius: 12, color: kneeColor, filled: true))
        instructions.append(.circle(at: rKnee,     radius: 12, color: kneeColor, filled: true))
        instructions.append(.circle(at: lAnkle,    radius: 8,  color: .orange,   filled: true))
        instructions.append(.circle(at: rAnkle,    radius: 8,  color: .orange,   filled: true))

        // Side labels
        instructions.append(.text("L", at: SIMD2(lShoulder.x - 0.05, lShoulder.y - 0.05), color: .white, size: 18))
        instructions.append(.text("R", at: SIMD2(rShoulder.x + 0.02, rShoulder.y - 0.05), color: .white, size: 18))

        // HUD
        let overall = currentMetrics().grade
        instructions.append(.text(overall.rawValue,
            at: SIMD2(0.85, 0.05), color: OverlayColor.romQuality(grade: overall), size: 36))
        instructions.append(.text("Depth: \(AngleCalculator.displayDegrees(avgKneeAngle))\u{00B0}",
            at: SIMD2(0.02, 0.05), color: depthColor, size: 18))
        instructions.append(.text("Trunk: \(AngleCalculator.displayDegrees(trunkLeanDeg))\u{00B0}",
            at: SIMD2(0.02, 0.11), color: trunkColor, size: 18))
        instructions.append(.text("Knee: \(String(format: "%.0f", worstKneeOff))%",
            at: SIMD2(0.02, 0.17), color: kneeColor, size: 18))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .knee, degrees: avgKneeAngle),
                JointAngle(joint: .hip,  degrees: trunkLeanDeg)
            ],
            repCount: 0,
            repState: .extended,
            tempoPhase: nil,
            overlayInstructions: instructions
        )
    }

    func currentMetrics() -> AssessmentMetrics {
        let depthGrade = LetterGrade.gradeLowerIsBetter(value: bestDepthAngle, a: 80, b: 95, c: 110, d: 125)
        let trunkGrade = LetterGrade.gradeLowerIsBetter(value: bestTrunkLean,  a: 15, b: 25, c: 35, d: 45)
        let kneeGrade  = LetterGrade.gradeLowerIsBetter(value: bestKneeTracking, a: 5, b: 10, c: 15, d: 20)
        let overall    = max(depthGrade, max(trunkGrade, kneeGrade))

        var details: [String] = []
        details.append("Best depth: \(AngleCalculator.displayDegrees(bestDepthAngle))° (\(depthGrade.rawValue))")
        details.append("Best trunk lean: \(AngleCalculator.displayDegrees(bestTrunkLean))° (\(trunkGrade.rawValue))")
        details.append("Best knee tracking: \(String(format: "%.0f", bestKneeTracking))% (\(kneeGrade.rawValue))")

        return AssessmentMetrics(
            grade: overall,
            subGrades: [("Depth", depthGrade), ("Trunk Lean", trunkGrade), ("Knee Tracking", kneeGrade)],
            leftROM: nil,
            rightROM: nil,
            asymmetryDeg: nil,
            asymmetryFlag: false,
            details: details
        )
    }

    func reset() {
        smoother.reset()
        bestDepthAngle = 180
        bestTrunkLean = 90
        bestKneeTracking = 100
        depthHysteresis = GradeHysteresis()
        trunkHysteresis = GradeHysteresis()
        kneeHysteresis = GradeHysteresis()
    }
}
