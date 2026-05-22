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
    // invertPhases: true — pulling bar down closes the elbow (angle ↓) = concentric.
    private let repCounter = RepCounter(extendedThreshold: 150, flexedThreshold: 80)
    private let tempoTracker = TempoTracker(invertPhases: true)

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
        let shoulder = smoother.smooth(key: "\(side)_shoulder", position: rawShoulder, timestamp: ts)
        let elbow    = smoother.smooth(key: "\(side)_elbow",    position: rawElbow,    timestamp: ts)
        let wrist    = smoother.smooth(key: "\(side)_wrist",    position: rawWrist,    timestamp: ts)
        let hip      = smoother.smooth(key: "\(side)_hip",      position: rawHip,      timestamp: ts)
        let ear      = landmarks.position(for: .ear(side))
            .map { smoother.smooth(key: "\(side)_ear", position: $0, timestamp: ts) }

        let w_shoulder = landmarks.worldPosition(for: .shoulder(side)).map { smoother.smooth3D(key: "\(side)_shoulder", position: $0, timestamp: ts) }
        let w_elbow    = landmarks.worldPosition(for: .elbow(side))   .map { smoother.smooth3D(key: "\(side)_elbow",    position: $0, timestamp: ts) }
        let w_wrist    = landmarks.worldPosition(for: .wrist(side))   .map { smoother.smooth3D(key: "\(side)_wrist",    position: $0, timestamp: ts) }
        let w_hip      = landmarks.worldPosition(for: .hip(side))     .map { smoother.smooth3D(key: "\(side)_hip",      position: $0, timestamp: ts) }

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

        repCounter.update(angle: elbowAngle, timestamp: ts)

        var instructions: [OverlayInstruction] = []

        // Spine overlay (ear → shoulder → mid-spine → hip). Drawn first so the
        // arm skeleton sits on top of it.
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: ear, shoulder: shoulder, hip: hip))

        // Extended forearm line
        instructions.append(.extendedLine(from: wrist, through: elbow, color: .cyan, width: 2))

        // Arm skeleton
        instructions.append(.line(from: shoulder, to: elbow, color: .yellow, width: 3))
        instructions.append(.line(from: elbow, to: wrist, color: .yellow, width: 3))

        // Key joints
        instructions.append(.circle(at: elbow, radius: 10, color: .red, filled: true))
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
                JointAngle(joint: .elbow, degrees: elbowAngle),
                JointAngle(joint: .shoulder, degrees: shoulderAngle)
            ],
            repCount: repCounter.count,
            repState: repCounter.state,
            tempoPhase: tempoTracker.update(angle: elbowAngle, timestamp: ts),
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
        repCounter.reset()
        tempoTracker.reset()
    }
}
