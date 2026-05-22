import Foundation
import simd

/// Tracks the hip hinge pattern from a strict side profile view.
/// Measures the hip angle (shoulder→hip→knee), which opens from ~60° at full hinge
/// to ~170° when standing. Suited for Romanian deadlifts, good mornings, and hip hinge drills.
/// Also overlays a vertical plumb line through the hip to help cue a hip-back hinge.
final class HipHingeSideAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .hipHingeSide
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [.shoulder(side), .hip(side), .knee(side), .ankle(side), .ear(side)]
    }

    private let smoother     = LandmarkSmoother()
    private let repCounter   = RepCounter(extendedThreshold: 155, flexedThreshold: 65)
    private let tempoTracker = TempoTracker()

    init(side: BodySide) {
        self.side = side
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawShoulder = landmarks.position(for: .shoulder(side)),
              let rawHip      = landmarks.position(for: .hip(side)),
              let rawKnee     = landmarks.position(for: .knee(side)),
              let rawAnkle    = landmarks.position(for: .ankle(side)) else {
            return .empty
        }

        let ts       = landmarks.timestamp
        let shoulder = smoother.smooth(key: "\(side)_shoulder", position: rawShoulder, timestamp: ts)
        let hip      = smoother.smooth(key: "\(side)_hip",      position: rawHip,      timestamp: ts)
        let knee     = smoother.smooth(key: "\(side)_knee",     position: rawKnee,     timestamp: ts)
        let ankle    = smoother.smooth(key: "\(side)_ankle",    position: rawAnkle,    timestamp: ts)
        let ear      = landmarks.position(for: .ear(side))
            .map { smoother.smooth(key: "\(side)_ear", position: $0, timestamp: ts) }

        let w_shoulder = landmarks.worldPosition(for: .shoulder(side)).map { smoother.smooth3D(key: "\(side)_shoulder", position: $0, timestamp: ts) }
        let w_hip      = landmarks.worldPosition(for: .hip(side))     .map { smoother.smooth3D(key: "\(side)_hip",      position: $0, timestamp: ts) }
        let w_knee     = landmarks.worldPosition(for: .knee(side))    .map { smoother.smooth3D(key: "\(side)_knee",     position: $0, timestamp: ts) }
        let w_ankle    = landmarks.worldPosition(for: .ankle(side))   .map { smoother.smooth3D(key: "\(side)_ankle",    position: $0, timestamp: ts) }

        // Primary: hip hinge angle (shoulder→hip→knee)
        let hipAngle: Float
        if let ws = w_shoulder, let wh = w_hip, let wk = w_knee {
            hipAngle = AngleCalculator.angle3D(a: ws, b: wh, c: wk)
        } else {
            hipAngle = AngleCalculator.angle(a: shoulder, b: hip, c: knee)
        }

        // Secondary: knee flexion (hip→knee→ankle) — should stay relatively soft (<30° of bend)
        let kneeAngle: Float
        if let wh = w_hip, let wk = w_knee, let wa = w_ankle {
            kneeAngle = AngleCalculator.angle3D(a: wh, b: wk, c: wa)
        } else {
            kneeAngle = AngleCalculator.angle(a: hip, b: knee, c: ankle)
        }

        // Torso lean from vertical: 0° = upright, 90° = parallel to ground
        let torsoDeg: Float
        let dx = shoulder.x - hip.x
        let dy = hip.y - shoulder.y  // y-down screen; dy positive when hip below shoulder
        torsoDeg = atan2(abs(dx), max(abs(dy), 1e-6)) * (180.0 / .pi)

        repCounter.update(angle: hipAngle, timestamp: ts)

        var instructions: [OverlayInstruction] = []

        // Spine overlay (behind other layers)
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: ear, shoulder: shoulder, hip: hip))

        // Vertical plumb line through hip (visual hinge cue)
        let plumbTop    = SIMD2<Float>(hip.x, hip.y - 0.20)
        let plumbBottom = SIMD2<Float>(hip.x, hip.y + 0.20)
        instructions.append(.line(from: plumbTop, to: plumbBottom, color: .magenta, width: 1))

        // Skeleton
        instructions.append(.line(from: shoulder, to: hip,   color: .green,  width: 3))
        instructions.append(.line(from: hip,      to: knee,  color: .green,  width: 3))
        instructions.append(.line(from: knee,     to: ankle, color: .green,  width: 3))

        // Key joints
        instructions.append(.circle(at: hip,      radius: 12, color: .red,    filled: true))
        instructions.append(.circle(at: shoulder, radius: 10, color: .yellow, filled: true))
        instructions.append(.circle(at: knee,     radius: 10, color: .yellow, filled: true))
        instructions.append(.circle(at: ankle,    radius: 8,  color: .orange, filled: true))

        // Angle labels
        instructions.append(.text("Hip: \(AngleCalculator.displayDegrees(hipAngle))\u{00B0}",
            at: SIMD2(hip.x + 0.02, hip.y - 0.04), color: .white, size: 20))
        instructions.append(.text("Knee: \(AngleCalculator.displayDegrees(kneeAngle))\u{00B0}",
            at: SIMD2(knee.x + 0.02, knee.y - 0.04), color: .cyan, size: 18))

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)",
            at: SIMD2(0.02, 0.05), color: .white, size: 24))
        instructions.append(.text("Torso: \(AngleCalculator.displayDegrees(torsoDeg))\u{00B0} fwd",
            at: SIMD2(0.02, 0.11), color: .cyan, size: 18))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .hip,  degrees: hipAngle),
                JointAngle(joint: .knee, degrees: kneeAngle)
            ],
            repCount: repCounter.count,
            repState: repCounter.state,
            tempoPhase: tempoTracker.update(angle: hipAngle, timestamp: ts),
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
        repCounter.reset()
        tempoTracker.reset()
    }
}
