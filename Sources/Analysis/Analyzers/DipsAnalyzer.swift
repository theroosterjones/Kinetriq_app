import Foundation
import simd

/// Side-profile dips analyzer.
/// Tracks elbow angle for reps and shoulder angle relative to the torso/chest line.
final class DipsAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .dips
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [
            .shoulder(side), .elbow(side), .wrist(side),
            .hip(side), .knee(side), .ankle(side)
        ]
    }

    private let smoother = LandmarkSmoother()
    private let repCounter = RepCounter(extendedThreshold: 145, flexedThreshold: 95)
    private let tempoTracker = TempoTracker()

    init(side: BodySide) {
        self.side = side
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawShoulder = landmarks.position(for: .shoulder(side)),
              let rawElbow = landmarks.position(for: .elbow(side)),
              let rawWrist = landmarks.position(for: .wrist(side)),
              let rawHip = landmarks.position(for: .hip(side)),
              let rawKnee = landmarks.position(for: .knee(side)),
              let rawAnkle = landmarks.position(for: .ankle(side)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let shoulder = smoother.smooth(key: "\(side)_shoulder", position: rawShoulder, timestamp: ts)
        let elbow = smoother.smooth(key: "\(side)_elbow", position: rawElbow, timestamp: ts)
        let wrist = smoother.stabilizeAnchor(key: "\(side)_dip_wrist_anchor", position: rawWrist)
        let hip = smoother.smooth(key: "\(side)_hip", position: rawHip, timestamp: ts)
        let knee = smoother.smooth(key: "\(side)_knee", position: rawKnee, timestamp: ts)
        let ankle = smoother.smooth(key: "\(side)_ankle", position: rawAnkle, timestamp: ts)

        let ear = landmarks.position(for: .ear(side))
            .map { smoother.smooth(key: "\(side)_ear", position: $0, timestamp: ts) }

        let wShoulder = landmarks.worldPosition(for: .shoulder(side))
            .map { smoother.smooth3D(key: "\(side)_shoulder", position: $0, timestamp: ts) }
        let wElbow = landmarks.worldPosition(for: .elbow(side))
            .map { smoother.smooth3D(key: "\(side)_elbow", position: $0, timestamp: ts) }
        let wWrist = landmarks.worldPosition(for: .wrist(side))
            .map { smoother.stabilizeAnchor3D(key: "\(side)_dip_wrist_anchor", position: $0) }
        let wHip = landmarks.worldPosition(for: .hip(side))
            .map { smoother.smooth3D(key: "\(side)_hip", position: $0, timestamp: ts) }

        let elbowAngle: Float
        if let ws = wShoulder, let we = wElbow, let ww = wWrist {
            elbowAngle = AngleCalculator.angle3D(a: ws, b: we, c: ww)
        } else {
            elbowAngle = AngleCalculator.angle(a: shoulder, b: elbow, c: wrist)
        }

        let shoulderAngle: Float
        if let wh = wHip, let ws = wShoulder, let we = wElbow {
            shoulderAngle = AngleCalculator.angle3D(a: wh, b: ws, c: we)
        } else {
            shoulderAngle = AngleCalculator.angle(a: hip, b: shoulder, c: elbow)
        }

        repCounter.update(angle: elbowAngle, timestamp: ts)
        let phase = tempoTracker.update(angle: elbowAngle, timestamp: ts)

        var instructions: [OverlayInstruction] = []
        instructions.append(contentsOf: SpineOverlay.instructions(ear: ear, shoulder: shoulder, hip: hip))

        instructions.append(.line(from: shoulder, to: elbow, color: .yellow, width: 3))
        instructions.append(.line(from: elbow, to: wrist, color: .yellow, width: 3))
        instructions.append(.line(from: hip, to: knee, color: .green, width: 3))
        instructions.append(.line(from: knee, to: ankle, color: .green, width: 3))

        instructions.append(.circle(at: shoulder, radius: 10, color: .red, filled: true))
        instructions.append(.circle(at: elbow, radius: 11, color: .red, filled: true))
        instructions.append(.circle(at: wrist, radius: 8, color: .orange, filled: true))
        instructions.append(.circle(at: hip, radius: 9, color: .green, filled: true))
        instructions.append(.circle(at: knee, radius: 8, color: .green, filled: true))
        instructions.append(.circle(at: ankle, radius: 8, color: .green, filled: true))

        instructions.append(.text("Elbow: \(AngleCalculator.displayDegrees(elbowAngle))\u{00B0}",
            at: SIMD2(elbow.x + 0.03, elbow.y), color: .white, size: 20))
        instructions.append(.text("Shoulder/Chest: \(AngleCalculator.displayDegrees(shoulderAngle))\u{00B0}",
            at: SIMD2(shoulder.x + 0.03, shoulder.y - 0.04), color: .white, size: 18))

        instructions.append(.text("Reps: \(repCounter.count)", at: SIMD2(0.02, 0.05), color: .white, size: 24))
        instructions.append(.text(phase.rawValue, at: SIMD2(0.02, 0.11), color: .cyan, size: 18))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .elbow, degrees: elbowAngle),
                JointAngle(joint: .shoulder, degrees: shoulderAngle)
            ],
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
