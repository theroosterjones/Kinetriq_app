import Foundation
import simd

/// Ported from row_analyzer.py.
/// Tracks elbow angle, shoulder angle, spine line, back line, chest marker, and rep count.
final class RowAnalyzer: ExerciseAnalyzer {
    private let minimumPreferredVisibility: Float = 0.35
    private let visibilityFallbackMargin: Float = 0.20

    let exerciseType: ExerciseType = .row
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [
            .shoulder(side), .elbow(side), .wrist(side), .hip(side),
            .shoulder(side.opposite), .ear(side), .ear(side.opposite)
        ]
    }

    private let smoother = LandmarkSmoother()
    // invertPhases: true — rowing (pulling elbow back) closes the joint (angle ↓) = concentric.
    private let repCounter = RepCounter(extendedThreshold: 150, flexedThreshold: 90)
    private let tempoTracker = TempoTracker(invertPhases: true)

    init(side: BodySide) {
        self.side = side
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        let activeSide = resolvedSide(for: landmarks)

        guard let rawShoulder = landmarks.position(for: .shoulder(activeSide)),
              let rawElbow    = landmarks.position(for: .elbow(activeSide)),
              let rawWrist    = landmarks.position(for: .wrist(activeSide)),
              let rawHip      = landmarks.position(for: .hip(activeSide)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let shoulder    = smoother.smooth(key: "\(activeSide)_shoulder", position: rawShoulder, timestamp: ts)
        let elbow       = smoother.smooth(key: "\(activeSide)_elbow",    position: rawElbow,    timestamp: ts)
        let wrist       = smoother.smooth(key: "\(activeSide)_wrist",    position: rawWrist,    timestamp: ts)
        let hip         = smoother.smooth(key: "\(activeSide)_hip",      position: rawHip,      timestamp: ts)
        let ear         = landmarks.position(for: .ear(activeSide))
            .map { smoother.smooth(key: "\(activeSide)_ear", position: $0, timestamp: ts) }
        let oppShoulder = landmarks.position(for: .shoulder(activeSide.opposite)).map {
            smoother.smooth(key: "\(activeSide.opposite)_shoulder", position: $0, timestamp: ts)
        }

        let w_shoulder = landmarks.worldPosition(for: .shoulder(activeSide)).map { smoother.smooth3D(key: "\(activeSide)_shoulder", position: $0, timestamp: ts) }
        let w_elbow    = landmarks.worldPosition(for: .elbow(activeSide))   .map { smoother.smooth3D(key: "\(activeSide)_elbow",    position: $0, timestamp: ts) }
        let w_wrist    = landmarks.worldPosition(for: .wrist(activeSide))   .map { smoother.smooth3D(key: "\(activeSide)_wrist",    position: $0, timestamp: ts) }
        let w_hip      = landmarks.worldPosition(for: .hip(activeSide))     .map { smoother.smooth3D(key: "\(activeSide)_hip",      position: $0, timestamp: ts) }

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

        // Extended forearm line (background)
        instructions.append(.extendedLine(from: wrist, through: elbow, color: .cyan, width: 2))

        // Arm skeleton
        instructions.append(.line(from: shoulder, to: elbow, color: .yellow, width: 3))
        instructions.append(.line(from: elbow, to: wrist, color: .yellow, width: 3))

        // Key joints
        instructions.append(.circle(at: elbow, radius: 10, color: .red, filled: true))
        instructions.append(.circle(at: shoulder, radius: 10, color: .red, filled: true))

        // Angle labels
        let elbowLabel = SIMD2<Float>(elbow.x - 0.05, elbow.y + 0.05)
        let shoulderLabel = SIMD2<Float>(shoulder.x - 0.05, shoulder.y - 0.03)

        instructions.append(.text("Elbow: \(AngleCalculator.displayDegrees(elbowAngle))", at: elbowLabel, color: .white, size: 20))
        instructions.append(.text("Shoulder: \(AngleCalculator.displayDegrees(shoulderAngle))", at: shoulderLabel, color: .white, size: 20))

        if let oppShoulder {
            let chest = (shoulder + oppShoulder) / 2.0
            let chestLabel = SIMD2<Float>(chest.x - 0.03, chest.y - 0.02)

            // Back line (shoulder to opposite shoulder) and chest marker are optional.
            instructions.append(.line(from: shoulder, to: oppShoulder, color: .magenta, width: 3))
            instructions.append(.circle(at: chest, radius: 10, color: .orange, filled: true))
            instructions.append(.circle(at: oppShoulder, radius: 8, color: .green, filled: true))
            instructions.append(.text("Chest", at: chestLabel, color: .white, size: 20))
        }

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)", at: SIMD2(0.02, 0.05), color: .white, size: 24))

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

    private func resolvedSide(for landmarks: PoseResult) -> BodySide {
        let preferredScore = visibilityScore(for: side, landmarks: landmarks)
        let alternateSide = side.opposite
        let alternateScore = visibilityScore(for: alternateSide, landmarks: landmarks)

        guard alternateScore > 0 else { return side }
        if preferredScore < minimumPreferredVisibility,
           alternateScore > preferredScore + visibilityFallbackMargin {
            return alternateSide
        }

        return side
    }

    private func visibilityScore(for side: BodySide, landmarks: PoseResult) -> Float {
        let relevantLandmarks: [PoseLandmarkType] = [
            .shoulder(side), .elbow(side), .wrist(side), .hip(side)
        ]
        let total = relevantLandmarks.reduce(Float.zero) { partial, landmark in
            partial + landmarks.visibility(for: landmark)
        }
        return total / Float(relevantLandmarks.count)
    }
}
