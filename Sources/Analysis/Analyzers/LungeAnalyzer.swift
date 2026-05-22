import Foundation
import simd

/// Tracks the front knee angle (hip→knee→ankle) for the lunge.
/// Film from a strict side profile with the working leg closest to the camera.
/// Rep cycle: standing (~165°) → bottom of lunge (~90°) → back to standing.
final class LungeAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .lunge
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [.hip(side), .knee(side), .ankle(side), .shoulder(side), .ear(side)]
    }

    private let smoother     = LandmarkSmoother()
    private let repCounter   = RepCounter(extendedThreshold: 155, flexedThreshold: 100)
    private let tempoTracker = TempoTracker()

    init(side: BodySide) {
        self.side = side
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawHip      = landmarks.position(for: .hip(side)),
              let rawKnee     = landmarks.position(for: .knee(side)),
              let rawAnkle    = landmarks.position(for: .ankle(side)),
              let rawShoulder = landmarks.position(for: .shoulder(side)) else {
            return .empty
        }

        let ts       = landmarks.timestamp
        let hip      = smoother.smooth(key: "\(side)_hip",      position: rawHip,      timestamp: ts)
        let knee     = smoother.smooth(key: "\(side)_knee",     position: rawKnee,     timestamp: ts)
        let ankle    = smoother.smooth(key: "\(side)_ankle",    position: rawAnkle,    timestamp: ts)
        let shoulder = smoother.smooth(key: "\(side)_shoulder", position: rawShoulder, timestamp: ts)
        let ear      = landmarks.position(for: .ear(side))
            .map { smoother.smooth(key: "\(side)_ear", position: $0, timestamp: ts) }

        let w_hip      = landmarks.worldPosition(for: .hip(side))     .map { smoother.smooth3D(key: "\(side)_hip",      position: $0, timestamp: ts) }
        let w_knee     = landmarks.worldPosition(for: .knee(side))    .map { smoother.smooth3D(key: "\(side)_knee",     position: $0, timestamp: ts) }
        let w_ankle    = landmarks.worldPosition(for: .ankle(side))   .map { smoother.smooth3D(key: "\(side)_ankle",    position: $0, timestamp: ts) }
        let w_shoulder = landmarks.worldPosition(for: .shoulder(side)).map { smoother.smooth3D(key: "\(side)_shoulder", position: $0, timestamp: ts) }

        let kneeAngle: Float
        if let wh = w_hip, let wk = w_knee, let wa = w_ankle {
            kneeAngle = AngleCalculator.angle3D(a: wh, b: wk, c: wa)
        } else {
            kneeAngle = AngleCalculator.angle(a: hip, b: knee, c: ankle)
        }

        // Trunk upright angle: how vertical the torso is (shoulder→hip relative to vertical).
        // Values near 90° = upright, lower = forward lean.
        let trunkAngle: Float
        if let ws = w_shoulder, let wh = w_hip {
            // Use x (lateral) vs y (vertical) displacement in world space
            let dx = ws.x - wh.x
            let dy = ws.y - wh.y
            trunkAngle = atan2(abs(dx), abs(dy)) * (180.0 / .pi)
        } else {
            let dx = shoulder.x - hip.x
            let dy = shoulder.y - hip.y
            trunkAngle = atan2(abs(dx), abs(dy)) * (180.0 / .pi)
        }

        repCounter.update(angle: kneeAngle, timestamp: ts)

        var instructions: [OverlayInstruction] = []

        // Spine overlay (behind joint labels)
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: ear, shoulder: shoulder, hip: hip))

        // Torso and leg skeleton
        instructions.append(.line(from: shoulder, to: hip,   color: .green,  width: 3))
        instructions.append(.line(from: hip,      to: knee,  color: .green,  width: 3))
        instructions.append(.line(from: knee,     to: ankle, color: .green,  width: 3))

        // Key joints
        instructions.append(.circle(at: knee,     radius: 12, color: .red,    filled: true))
        instructions.append(.circle(at: hip,      radius: 10, color: .yellow, filled: true))
        instructions.append(.circle(at: shoulder, radius: 10, color: .yellow, filled: true))
        instructions.append(.circle(at: ankle,    radius: 8,  color: .orange, filled: true))

        // Hip angle (shoulder→hip→knee) — display only, no effect on rep/tempo logic
        let hipAngle: Float
        if let ws = w_shoulder, let wh = w_hip, let wk = w_knee {
            hipAngle = AngleCalculator.angle3D(a: ws, b: wh, c: wk)
        } else {
            hipAngle = AngleCalculator.angle(a: shoulder, b: hip, c: knee)
        }

        // Angle labels
        instructions.append(.text("Knee: \(AngleCalculator.displayDegrees(kneeAngle))\u{00B0}",
            at: SIMD2(knee.x + 0.02, knee.y - 0.04), color: .white, size: 20))
        if hipAngle.isFinite {
            instructions.append(.text("Hip: \(AngleCalculator.displayDegrees(hipAngle))\u{00B0}",
                at: SIMD2(hip.x + 0.02, hip.y - 0.04), color: .cyan, size: 18))
        }
        instructions.append(.text("Trunk: \(AngleCalculator.displayDegrees(trunkAngle))\u{00B0}",
            at: SIMD2(0.02, 0.17), color: .cyan, size: 18))

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)",
            at: SIMD2(0.02, 0.05), color: .white, size: 24))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .knee, degrees: kneeAngle),
                JointAngle(joint: .hip,  degrees: trunkAngle)
            ],
            repCount: repCounter.count,
            repState: repCounter.state,
            tempoPhase: tempoTracker.update(angle: kneeAngle, timestamp: ts),
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
        repCounter.reset()
        tempoTracker.reset()
    }
}
