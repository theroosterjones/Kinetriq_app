import Foundation
import simd

/// Ported from pose_analyzer.py.
/// Tracks elbow angle, shoulder angle, extended forearm line.
final class LatPulldownAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .latPulldown
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [.shoulder(side), .elbow(side), .wrist(side), .hip(side)]
    }

    private let smoother = LandmarkSmoother()
    // Reps are driven by SHOULDER extension (angle of upper arm vs. the torso/back
    // line: hip→shoulder→elbow), which has a large, reliable range in a lat pulldown
    // (arms overhead ≈ 150°+, elbows pulled to the sides ≈ 40°). Elbow flexion was
    // unreliable here: world-landmark arm extension tops out near 140–150°, so the
    // old extendedThreshold of 150° was rarely reached and no reps were counted.
    //
    // invertPhases: true — pulling the bar down decreases the shoulder angle
    // (angle ↓) = concentric.
    private let repCounter = RepCounter(extendedThreshold: 120, flexedThreshold: 70)
    private let tempoTracker = TempoTracker(invertPhases: true)

    /// Velocity limits (coordinate units/second) for the arm chain, matching the
    /// squat leg-chain spike rejection: single-frame MediaPipe snaps (the elbow
    /// "drift" in deep flexion) are clamped while a real, fast pull still tracks.
    /// 2D is normalized [0,1] screen space; 3D is metric meters.
    private let armMaxSpeed2D: Float = 3.0
    private let armMaxSpeed3D: Float = 5.0

    init(side: BodySide) {
        self.side = side
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawShoulder = landmarks.position(for: .shoulder(side)),
              let rawElbow    = landmarks.position(for: .elbow(side)),
              let rawWrist    = landmarks.position(for: .wrist(side)),
              let rawHip      = landmarks.position(for: .hip(side)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let shoulder = smoother.smooth(key: "\(side)_shoulder", position: rawShoulder, timestamp: ts, maxSpeed: armMaxSpeed2D)
        let elbow    = smoother.smooth(key: "\(side)_elbow",    position: rawElbow,    timestamp: ts, maxSpeed: armMaxSpeed2D)
        let wrist    = smoother.smooth(key: "\(side)_wrist",    position: rawWrist,    timestamp: ts, maxSpeed: armMaxSpeed2D)
        let hip      = smoother.smooth(key: "\(side)_hip",      position: rawHip,      timestamp: ts, maxSpeed: armMaxSpeed2D)
        let ear      = landmarks.position(for: .ear(side))
            .map { smoother.smooth(key: "\(side)_ear", position: $0, timestamp: ts) }

        let w_shoulder = landmarks.worldPosition(for: .shoulder(side)).map { smoother.smooth3D(key: "\(side)_shoulder", position: $0, timestamp: ts, maxSpeed: armMaxSpeed3D) }
        let w_elbow    = landmarks.worldPosition(for: .elbow(side))   .map { smoother.smooth3D(key: "\(side)_elbow",    position: $0, timestamp: ts, maxSpeed: armMaxSpeed3D) }
        let w_wrist    = landmarks.worldPosition(for: .wrist(side))   .map { smoother.smooth3D(key: "\(side)_wrist",    position: $0, timestamp: ts, maxSpeed: armMaxSpeed3D) }
        let w_hip      = landmarks.worldPosition(for: .hip(side))     .map { smoother.smooth3D(key: "\(side)_hip",      position: $0, timestamp: ts, maxSpeed: armMaxSpeed3D) }

        let elbowAngle: Float
        if let ws = w_shoulder, let we = w_elbow, let ww = w_wrist {
            elbowAngle = AngleCalculator.angle3D(a: ws, b: we, c: ww)
        } else {
            elbowAngle = AngleCalculator.angle(a: shoulder, b: elbow, c: wrist)
        }

        let shoulderAngle: Float
        if let wh = w_hip, let ws = w_shoulder, let we = w_elbow {
            shoulderAngle = AngleCalculator.angle3D(a: wh, b: ws, c: we)
        } else {
            shoulderAngle = AngleCalculator.angle(a: hip, b: shoulder, c: elbow)
        }

        // Shoulder angle drives rep counting and tempo (see thresholds above).
        repCounter.update(angle: shoulderAngle, timestamp: ts)

        var instructions: [OverlayInstruction] = []

        // Spine overlay (ear → shoulder → mid-spine → hip). Drawn first so the
        // arm skeleton sits on top of it.
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: ear, shoulder: shoulder, hip: hip))

        // Arm skeleton
        instructions.append(.line(from: shoulder, to: elbow, color: .yellow, width: 3))
        instructions.append(.line(from: elbow, to: wrist, color: .yellow, width: 3))

        // Key joints — draw the elbow marker on the point of the elbow (olecranon)
        // rather than the rotation center, which reads as steadier in the side view.
        let elbowTip = JointTip.position(vertex: elbow, toward: shoulder, and: wrist)
        instructions.append(.circle(at: elbowTip, radius: 10, color: .red, filled: true))
        instructions.append(.circle(at: shoulder, radius: 10, color: .red, filled: true))

        // Angle labels
        instructions.append(.text("Elbow: \(AngleCalculator.displayDegrees(elbowAngle))",
            at: SIMD2(elbow.x - 0.05, elbow.y + 0.05), color: .white, size: 20))
        instructions.append(.text("Shoulder: \(AngleCalculator.displayDegrees(shoulderAngle))",
            at: SIMD2(shoulder.x - 0.05, shoulder.y - 0.03), color: .white, size: 20))

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)",
            at: SIMD2(0.02, 0.05), color: .white, size: 24))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .shoulder, degrees: shoulderAngle),
                JointAngle(joint: .elbow, degrees: elbowAngle)
            ],
            repCount: repCounter.count,
            repState: repCounter.state,
            tempoPhase: tempoTracker.update(angle: shoulderAngle, timestamp: ts),
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
        repCounter.reset()
        tempoTracker.reset()
    }
}
