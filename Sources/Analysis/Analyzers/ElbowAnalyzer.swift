import Foundation
import CoreMedia
import simd

/// Tracks elbow flexion/extension angle (shoulder → elbow → wrist) for bicep curls,
/// tricep extensions, and any elbow-dominant movement. Filmed from the side.
final class ElbowAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .elbowCurl
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [.shoulder(side), .elbow(side), .wrist(side)]
    }

    private let smoother = LandmarkSmoother()
    // Extended threshold lowered to 140: world-landmark elbow angle at full arm extension
    // typically reads 140–158°, so 155 caused the counter to get permanently stuck in
    // .flexed after the first curl and count 0 reps.
    // invertPhases: true because curling UP closes the elbow (angle ↓) = concentric.
    private let repCounter = RepCounter(extendedThreshold: 140, flexedThreshold: 55)
    private let tempoTracker = TempoTracker(invertPhases: true)

    init(side: BodySide) {
        self.side = side
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawShoulder = landmarks.position(for: .shoulder(side)),
              let rawElbow    = landmarks.position(for: .elbow(side)),
              let rawWrist    = landmarks.position(for: .wrist(side)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let shoulder = smoother.smooth(key: "\(side)_shoulder", position: rawShoulder, timestamp: ts)
        let elbow    = smoother.smooth(key: "\(side)_elbow",    position: rawElbow,    timestamp: ts)
        let wrist    = smoother.smooth(key: "\(side)_wrist",    position: rawWrist,    timestamp: ts)

        // Hip and ear are optional — bicep curls / tricep work are often filmed
        // tight enough to crop the lower body. If the hip lands inside the
        // frame we draw the spine overlay for postural context; otherwise the
        // overlay degrades gracefully to just the working arm.
        let hip = landmarks.position(for: .hip(side))
            .map { smoother.smooth(key: "\(side)_hip", position: $0, timestamp: ts) }
        let ear = landmarks.position(for: .ear(side))
            .map { smoother.smooth(key: "\(side)_ear", position: $0, timestamp: ts) }

        let w_shoulder = landmarks.worldPosition(for: .shoulder(side)).map { smoother.smooth3D(key: "\(side)_shoulder", position: $0, timestamp: ts) }
        let w_elbow    = landmarks.worldPosition(for: .elbow(side))   .map { smoother.smooth3D(key: "\(side)_elbow",    position: $0, timestamp: ts) }
        let w_wrist    = landmarks.worldPosition(for: .wrist(side))   .map { smoother.smooth3D(key: "\(side)_wrist",    position: $0, timestamp: ts) }

        let elbowAngle: Float
        if let ws = w_shoulder, let we = w_elbow, let ww = w_wrist {
            elbowAngle = AngleCalculator.angle3D(a: ws, b: we, c: ww)
        } else {
            elbowAngle = AngleCalculator.angle(a: shoulder, b: elbow, c: wrist)
        }

        repCounter.update(angle: elbowAngle, timestamp: ts)
        let frameTime = CMTimeMakeWithSeconds(landmarks.timestamp, preferredTimescale: 600)
        let phase = tempoTracker.update(angle: elbowAngle, time: frameTime)

        var instructions: [OverlayInstruction] = []

        // Spine overlay (drawn first when the hip is in frame so the arm
        // skeleton sits on top of it).
        if let hip {
            instructions.append(contentsOf: SpineOverlay.instructions(
                ear: ear, shoulder: shoulder, hip: hip))
        }

        // Forearm extension reference line (background reference)
        instructions.append(.extendedLine(from: elbow, through: wrist, color: .cyan, width: 2))

        // Upper arm and forearm
        instructions.append(.line(from: shoulder, to: elbow, color: .yellow, width: 3))
        instructions.append(.line(from: elbow, to: wrist, color: .yellow, width: 3))

        // Joints
        instructions.append(.circle(at: shoulder, radius: 10, color: .red,    filled: true))
        instructions.append(.circle(at: elbow,    radius: 12, color: .red,    filled: true))
        instructions.append(.circle(at: wrist,    radius: 8,  color: .orange, filled: true))

        // Angle label near elbow
        let elbowLabel = SIMD2<Float>(elbow.x + 0.03, elbow.y)
        instructions.append(.text("Elbow: \(AngleCalculator.displayDegrees(elbowAngle))\u{00B0}", at: elbowLabel, color: .white, size: 20))

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)", at: SIMD2(0.02, 0.05), color: .white, size: 24))
        instructions.append(.text(phase.rawValue,               at: SIMD2(0.02, 0.11), color: .cyan,  size: 18))

        return FrameAnalysis(
            angles: [JointAngle(joint: .elbow, degrees: elbowAngle)],
            repCount: repCounter.count,
            repState: repCounter.state,
            tempoPhase: phase,
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
        repCounter.reset()
        tempoTracker.reset()
    }
}
