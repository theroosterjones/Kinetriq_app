import Foundation
import simd

/// Bilateral overhead press analyzer filmed from the front or back.
/// Tracks elbow angle (shoulder→elbow→wrist) on both arms independently and counts reps
/// using the average of both elbow angles.
/// Also shows a torso lean angle (shoulder midpoint vs hip midpoint) to flag excessive back arch.
final class OverheadPressAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .overheadPress
    // Bilateral — side is not applicable; stored as .left to satisfy the protocol.
    let side: BodySide = .left

    var requiredLandmarks: [PoseLandmarkType] {
        [
            .shoulder(.left), .elbow(.left), .wrist(.left),
            .shoulder(.right), .elbow(.right), .wrist(.right),
            .hip(.left), .hip(.right)
        ]
    }

    private let smoother     = LandmarkSmoother()
    private let repCounter   = RepCounter(extendedThreshold: 155, flexedThreshold: 90)
    private let tempoTracker = TempoTracker()

    init(side: BodySide) {
        // side parameter ignored — bilateral analyzer
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawLS = landmarks.position(for: .shoulder(.left)),
              let rawLE = landmarks.position(for: .elbow(.left)),
              let rawLW = landmarks.position(for: .wrist(.left)),
              let rawRS = landmarks.position(for: .shoulder(.right)),
              let rawRE = landmarks.position(for: .elbow(.right)),
              let rawRW = landmarks.position(for: .wrist(.right)),
              let rawLH = landmarks.position(for: .hip(.left)),
              let rawRH = landmarks.position(for: .hip(.right)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let lShoulder = smoother.smooth(key: "left_shoulder",  position: rawLS, timestamp: ts)
        let lElbow    = smoother.smooth(key: "left_elbow",     position: rawLE, timestamp: ts)
        let lWrist    = smoother.smooth(key: "left_wrist",     position: rawLW, timestamp: ts)
        let rShoulder = smoother.smooth(key: "right_shoulder", position: rawRS, timestamp: ts)
        let rElbow    = smoother.smooth(key: "right_elbow",    position: rawRE, timestamp: ts)
        let rWrist    = smoother.smooth(key: "right_wrist",    position: rawRW, timestamp: ts)
        let lHip      = smoother.smooth(key: "left_hip",       position: rawLH, timestamp: ts)
        let rHip      = smoother.smooth(key: "right_hip",      position: rawRH, timestamp: ts)

        // Ears are optional — when both are visible we use the midpoint to anchor
        // the cervical end of the spine overlay; otherwise we fall back to either
        // available ear, or skip the cervical extension entirely.
        let lEar = landmarks.position(for: .ear(.left))
            .map { smoother.smooth(key: "left_ear", position: $0, timestamp: ts) }
        let rEar = landmarks.position(for: .ear(.right))
            .map { smoother.smooth(key: "right_ear", position: $0, timestamp: ts) }
        let earMid: SIMD2<Float>?
        if let le = lEar, let re = rEar { earMid = (le + re) / 2.0 }
        else { earMid = lEar ?? rEar }

        let wLS = landmarks.worldPosition(for: .shoulder(.left)) .map { smoother.smooth3D(key: "left_shoulder",  position: $0, timestamp: ts) }
        let wLE = landmarks.worldPosition(for: .elbow(.left))    .map { smoother.smooth3D(key: "left_elbow",     position: $0, timestamp: ts) }
        let wLW = landmarks.worldPosition(for: .wrist(.left))    .map { smoother.smooth3D(key: "left_wrist",     position: $0, timestamp: ts) }
        let wRS = landmarks.worldPosition(for: .shoulder(.right)).map { smoother.smooth3D(key: "right_shoulder", position: $0, timestamp: ts) }
        let wRE = landmarks.worldPosition(for: .elbow(.right))   .map { smoother.smooth3D(key: "right_elbow",    position: $0, timestamp: ts) }
        let wRW = landmarks.worldPosition(for: .wrist(.right))   .map { smoother.smooth3D(key: "right_wrist",    position: $0, timestamp: ts) }

        let leftElbowAngle: Float
        if let ws = wLS, let we = wLE, let ww = wLW {
            leftElbowAngle = AngleCalculator.angle3D(a: ws, b: we, c: ww)
        } else {
            leftElbowAngle = AngleCalculator.angle(a: lShoulder, b: lElbow, c: lWrist)
        }

        let rightElbowAngle: Float
        if let ws = wRS, let we = wRE, let ww = wRW {
            rightElbowAngle = AngleCalculator.angle3D(a: ws, b: we, c: ww)
        } else {
            rightElbowAngle = AngleCalculator.angle(a: rShoulder, b: rElbow, c: rWrist)
        }

        // Use the average of both elbows to drive rep counting
        let avgElbowAngle = (leftElbowAngle + rightElbowAngle) / 2.0

        repCounter.update(angle: avgElbowAngle, timestamp: ts)

        // Torso lean: angle between shoulder midpoint and hip midpoint relative to vertical.
        // A large value indicates the athlete is leaning back excessively.
        let shoulderMid = (lShoulder + rShoulder) / 2.0
        let hipMid      = (lHip + rHip) / 2.0
        let dx = shoulderMid.x - hipMid.x
        let dy = shoulderMid.y - hipMid.y  // screen-space (y-down)
        // Angle from vertical: 0° = perfectly upright, positive = leaning back
        let torsoLeanDeg = atan2(abs(dx), abs(dy)) * (180.0 / .pi)

        var instructions: [OverlayInstruction] = []

        // Spine overlay (ear midpoint → shoulder midpoint → mid-spine → hip midpoint).
        // Drawn first so the arm skeleton and shoulder girdle sit on top of it.
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: earMid, shoulder: shoulderMid, hip: hipMid))

        // Shoulder girdle
        instructions.append(.line(from: lShoulder, to: rShoulder, color: .yellow, width: 3))

        // Hip baseline
        instructions.append(.line(from: lHip, to: rHip, color: .cyan, width: 2))

        // Left arm
        instructions.append(.line(from: lShoulder, to: lElbow, color: .yellow, width: 3))
        instructions.append(.line(from: lElbow,    to: lWrist, color: .yellow, width: 3))

        // Right arm
        instructions.append(.line(from: rShoulder, to: rElbow, color: .yellow, width: 3))
        instructions.append(.line(from: rElbow,    to: rWrist, color: .yellow, width: 3))

        // Joint circles
        instructions.append(.circle(at: lShoulder, radius: 10, color: .red,    filled: true))
        instructions.append(.circle(at: rShoulder, radius: 10, color: .red,    filled: true))
        instructions.append(.circle(at: lElbow,    radius: 10, color: .orange, filled: true))
        instructions.append(.circle(at: rElbow,    radius: 10, color: .orange, filled: true))
        instructions.append(.circle(at: lWrist,    radius: 8,  color: .white,  filled: true))
        instructions.append(.circle(at: rWrist,    radius: 8,  color: .white,  filled: true))
        instructions.append(.circle(at: lHip,      radius: 8,  color: .green,  filled: true))
        instructions.append(.circle(at: rHip,      radius: 8,  color: .green,  filled: true))

        // Side labels
        instructions.append(.text("L", at: SIMD2(lShoulder.x - 0.05, lShoulder.y - 0.05), color: .red,  size: 18))
        instructions.append(.text("R", at: SIMD2(rShoulder.x + 0.02, rShoulder.y - 0.05), color: .blue, size: 18))

        // Elbow angle labels
        instructions.append(.text("L: \(AngleCalculator.displayDegrees(leftElbowAngle))\u{00B0}",
            at: SIMD2(lElbow.x - 0.08, lElbow.y + 0.03), color: .white, size: 18))
        instructions.append(.text("R: \(AngleCalculator.displayDegrees(rightElbowAngle))\u{00B0}",
            at: SIMD2(rElbow.x + 0.02, rElbow.y + 0.03), color: .white, size: 18))

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)",
            at: SIMD2(0.02, 0.05), color: .white, size: 24))
        instructions.append(.text("Lean: \(String(format: "%.1f", torsoLeanDeg))\u{00B0}",
            at: SIMD2(0.02, 0.11), color: torsoLeanDeg > 15 ? .red : .cyan, size: 18))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .elbow,    degrees: avgElbowAngle),
                JointAngle(joint: .shoulder, degrees: torsoLeanDeg)
            ],
            repCount: repCounter.count,
            repState: repCounter.state,
            tempoPhase: tempoTracker.update(angle: avgElbowAngle, timestamp: ts),
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
        repCounter.reset()
        tempoTracker.reset()
    }
}
