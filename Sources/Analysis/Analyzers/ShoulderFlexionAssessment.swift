import Foundation
import simd

/// Bilateral shoulder flexion assessment filmed from the side.
/// Measures max overhead ROM (shoulder-hip-wrist angle) on each arm independently.
/// Grades: A >= 170°, B >= 150°, C >= 130°, D >= 110°, F < 110°.
/// Asymmetry flagged if left-right difference > 15°.
final class ShoulderFlexionAssessment: AssessmentAnalyzer {

    let assessmentType: AssessmentType = .shoulderFlexion

    var requiredLandmarks: [PoseLandmarkType] {
        [
            .shoulder(.left), .shoulder(.right),
            .elbow(.left), .elbow(.right),
            .wrist(.left), .wrist(.right),
            .hip(.left), .hip(.right),
            .ear(.left), .ear(.right)
        ]
    }

    private let smoother = LandmarkSmoother()
    private var peakLeftROM: Float = 0
    private var peakRightROM: Float = 0
    private let asymmetryThreshold: Float = 15.0
    private var hysteresisCounter: [BodySide: Int] = [.left: 0, .right: 0]
    private var displayedGrade: [BodySide: LetterGrade] = [.left: .F, .right: .F]

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawLS = landmarks.position(for: .shoulder(.left)),
              let rawRS = landmarks.position(for: .shoulder(.right)),
              let rawLE = landmarks.position(for: .elbow(.left)),
              let rawRE = landmarks.position(for: .elbow(.right)),
              let rawLW = landmarks.position(for: .wrist(.left)),
              let rawRW = landmarks.position(for: .wrist(.right)),
              let rawLH = landmarks.position(for: .hip(.left)),
              let rawRH = landmarks.position(for: .hip(.right)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let lShoulder = smoother.smooth(key: "left_shoulder",  position: rawLS, timestamp: ts)
        let rShoulder = smoother.smooth(key: "right_shoulder", position: rawRS, timestamp: ts)
        let lElbow    = smoother.smooth(key: "left_elbow",     position: rawLE, timestamp: ts)
        let rElbow    = smoother.smooth(key: "right_elbow",    position: rawRE, timestamp: ts)
        let lWrist    = smoother.smooth(key: "left_wrist",     position: rawLW, timestamp: ts)
        let rWrist    = smoother.smooth(key: "right_wrist",    position: rawRW, timestamp: ts)
        let lHip      = smoother.smooth(key: "left_hip",       position: rawLH, timestamp: ts)
        let rHip      = smoother.smooth(key: "right_hip",      position: rawRH, timestamp: ts)

        let lEar = landmarks.position(for: .ear(.left))
            .map { smoother.smooth(key: "left_ear", position: $0, timestamp: ts) }
        let rEar = landmarks.position(for: .ear(.right))
            .map { smoother.smooth(key: "right_ear", position: $0, timestamp: ts) }

        // 3D world positions for angle accuracy
        let wLS = landmarks.worldPosition(for: .shoulder(.left)) .map { smoother.smooth3D(key: "left_shoulder",  position: $0, timestamp: ts) }
        let wRS = landmarks.worldPosition(for: .shoulder(.right)).map { smoother.smooth3D(key: "right_shoulder", position: $0, timestamp: ts) }
        let wLW = landmarks.worldPosition(for: .wrist(.left))    .map { smoother.smooth3D(key: "left_wrist",     position: $0, timestamp: ts) }
        let wRW = landmarks.worldPosition(for: .wrist(.right))   .map { smoother.smooth3D(key: "right_wrist",    position: $0, timestamp: ts) }
        let wLH = landmarks.worldPosition(for: .hip(.left))      .map { smoother.smooth3D(key: "left_hip",       position: $0, timestamp: ts) }
        let wRH = landmarks.worldPosition(for: .hip(.right))     .map { smoother.smooth3D(key: "right_hip",      position: $0, timestamp: ts) }

        // ROM = shoulder-hip-wrist angle (larger = more overhead reach)
        let leftROM: Float
        if let ws = wLS, let wh = wLH, let ww = wLW {
            leftROM = AngleCalculator.angle3D(a: ww, b: ws, c: wh)
        } else {
            leftROM = AngleCalculator.angle(a: lWrist, b: lShoulder, c: lHip)
        }

        let rightROM: Float
        if let ws = wRS, let wh = wRH, let ww = wRW {
            rightROM = AngleCalculator.angle3D(a: ww, b: ws, c: wh)
        } else {
            rightROM = AngleCalculator.angle(a: rWrist, b: rShoulder, c: rHip)
        }

        peakLeftROM = max(peakLeftROM, leftROM)
        peakRightROM = max(peakRightROM, rightROM)

        let leftGrade = gradeROM(leftROM)
        let rightGrade = gradeROM(rightROM)

        // Apply hysteresis (5 frames) before changing displayed color grade
        for (side, newGrade) in [(BodySide.left, leftGrade), (.right, rightGrade)] {
            if newGrade != displayedGrade[side] {
                hysteresisCounter[side, default: 0] += 1
                if hysteresisCounter[side, default: 0] >= 5 {
                    displayedGrade[side] = newGrade
                    hysteresisCounter[side] = 0
                }
            } else {
                hysteresisCounter[side] = 0
            }
        }

        let leftColor = OverlayColor.romQuality(grade: displayedGrade[.left] ?? .F)
        let rightColor = OverlayColor.romQuality(grade: displayedGrade[.right] ?? .F)

        let shoulderMid = (lShoulder + rShoulder) / 2.0
        let hipMid = (lHip + rHip) / 2.0
        let earMid: SIMD2<Float>?
        if let le = lEar, let re = rEar { earMid = (le + re) / 2.0 }
        else { earMid = lEar ?? rEar }

        var instructions: [OverlayInstruction] = []

        // Spine
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: earMid, shoulder: shoulderMid, hip: hipMid))

        // Shoulder girdle and hip baseline
        instructions.append(.line(from: lShoulder, to: rShoulder, color: .yellow, width: 3))
        instructions.append(.line(from: lHip, to: rHip, color: .cyan, width: 2))

        // Left arm (colored by ROM quality)
        instructions.append(.line(from: lShoulder, to: lElbow, color: leftColor, width: 3))
        instructions.append(.line(from: lElbow, to: lWrist, color: leftColor, width: 3))

        // Right arm
        instructions.append(.line(from: rShoulder, to: rElbow, color: rightColor, width: 3))
        instructions.append(.line(from: rElbow, to: rWrist, color: rightColor, width: 3))

        // Joint circles
        instructions.append(.circle(at: lShoulder, radius: 10, color: leftColor,  filled: true))
        instructions.append(.circle(at: rShoulder, radius: 10, color: rightColor, filled: true))
        instructions.append(.circle(at: lElbow,    radius: 8,  color: leftColor,  filled: true))
        instructions.append(.circle(at: rElbow,    radius: 8,  color: rightColor, filled: true))
        instructions.append(.circle(at: lWrist,    radius: 7,  color: leftColor,  filled: true))
        instructions.append(.circle(at: rWrist,    radius: 7,  color: rightColor, filled: true))
        instructions.append(.circle(at: lHip,      radius: 8,  color: .cyan,      filled: true))
        instructions.append(.circle(at: rHip,      radius: 8,  color: .cyan,      filled: true))

        // Side labels
        instructions.append(.text("L", at: SIMD2(lShoulder.x - 0.05, lShoulder.y - 0.05), color: .white, size: 18))
        instructions.append(.text("R", at: SIMD2(rShoulder.x + 0.02, rShoulder.y - 0.05), color: .white, size: 18))

        // ROM angle labels
        instructions.append(.text("L: \(AngleCalculator.displayDegrees(leftROM))\u{00B0}",
            at: SIMD2(lElbow.x - 0.08, lElbow.y + 0.03), color: .white, size: 18))
        instructions.append(.text("R: \(AngleCalculator.displayDegrees(rightROM))\u{00B0}",
            at: SIMD2(rElbow.x + 0.02, rElbow.y + 0.03), color: .white, size: 18))

        // HUD: grade and peak ROM
        let overallGrade = currentMetrics().grade
        instructions.append(.text(overallGrade.rawValue,
            at: SIMD2(0.85, 0.05), color: OverlayColor.romQuality(grade: overallGrade), size: 36))
        instructions.append(.text("Peak L: \(AngleCalculator.displayDegrees(peakLeftROM))\u{00B0}  R: \(AngleCalculator.displayDegrees(peakRightROM))\u{00B0}",
            at: SIMD2(0.02, 0.05), color: .white, size: 18))

        let asymm = abs(peakLeftROM - peakRightROM)
        if asymm > asymmetryThreshold {
            let side = peakLeftROM < peakRightROM ? "Left" : "Right"
            instructions.append(.text("\(side) restricted by \(AngleCalculator.displayDegrees(asymm))\u{00B0}",
                at: SIMD2(0.02, 0.11), color: .orange, size: 16))
        }

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .shoulder, degrees: leftROM),
                JointAngle(joint: .shoulder, degrees: rightROM)
            ],
            repCount: 0,
            repState: .extended,
            tempoPhase: nil,
            overlayInstructions: instructions
        )
    }

    func currentMetrics() -> AssessmentMetrics {
        let leftGrade = gradeROM(peakLeftROM)
        let rightGrade = gradeROM(peakRightROM)
        let overall = max(leftGrade, rightGrade) // worst of the two
        let asymm = abs(peakLeftROM - peakRightROM)
        let flag = asymm > asymmetryThreshold

        var details: [String] = []
        details.append("Left peak: \(AngleCalculator.displayDegrees(peakLeftROM))° (\(leftGrade.rawValue))")
        details.append("Right peak: \(AngleCalculator.displayDegrees(peakRightROM))° (\(rightGrade.rawValue))")
        if flag {
            let side = peakLeftROM < peakRightROM ? "Left" : "Right"
            details.append("\(side) side restricted by \(AngleCalculator.displayDegrees(asymm))°")
        }

        return AssessmentMetrics(
            grade: overall,
            subGrades: [("Left ROM", leftGrade), ("Right ROM", rightGrade)],
            leftROM: peakLeftROM,
            rightROM: peakRightROM,
            asymmetryDeg: asymm,
            asymmetryFlag: flag,
            details: details
        )
    }

    func reset() {
        smoother.reset()
        peakLeftROM = 0
        peakRightROM = 0
        hysteresisCounter = [.left: 0, .right: 0]
        displayedGrade = [.left: .F, .right: .F]
    }

    private func gradeROM(_ rom: Float) -> LetterGrade {
        LetterGrade.gradeHigherIsBetter(value: rom, a: 170, b: 150, c: 130, d: 110)
    }
}
