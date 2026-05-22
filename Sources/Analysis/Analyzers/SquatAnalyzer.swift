import Foundation
import simd

/// Ported from FitnessAnalyzer.analyze_squat() in app.py.
/// Tracks knee angle with rep counting.
final class SquatAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .squat
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [.shoulder(side), .hip(side), .knee(side), .ankle(side), .ear(side)]
    }

    private let smoother = LandmarkSmoother()
    private let repCounter = RepCounter(extendedThreshold: 150, flexedThreshold: 100)
    private let tempoTracker = TempoTracker()

    /// Minimum per-landmark visibility the hip/knee/ankle chain must meet for the
    /// measured knee angle to be considered trustworthy.
    ///
    /// Pendulum squats, leg press machines, and other fixtures frequently occlude
    /// the hip landmark, causing MediaPipe to snap it onto padding. Without this
    /// gate those frames feed corrupt angles into the rep counter and the peak
    /// angle collector, tanking the consistency score.
    private let minVertexVisibility: Float = 0.5
    private var lastValidKneeAngle: Float?

    init(side: BodySide) {
        self.side = side
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawHip   = landmarks.position(for: .hip(side)),
              let rawKnee  = landmarks.position(for: .knee(side)),
              let rawAnkle = landmarks.position(for: .ankle(side)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let hip   = smoother.smooth(key: "\(side)_hip",   position: rawHip,   timestamp: ts)
        let knee  = smoother.smooth(key: "\(side)_knee",  position: rawKnee,  timestamp: ts)
        let ankle = smoother.smooth(key: "\(side)_ankle", position: rawAnkle, timestamp: ts)

        let shoulder = landmarks.position(for: .shoulder(side))
            .map { smoother.smooth(key: "\(side)_shoulder", position: $0, timestamp: ts) }
        let ear = landmarks.position(for: .ear(side))
            .map { smoother.smooth(key: "\(side)_ear", position: $0, timestamp: ts) }

        let w_shoulder = landmarks.worldPosition(for: .shoulder(side)).map { smoother.smooth3D(key: "\(side)_shoulder", position: $0, timestamp: ts) }
        let w_hip   = landmarks.worldPosition(for: .hip(side))  .map { smoother.smooth3D(key: "\(side)_hip",   position: $0, timestamp: ts) }
        let w_knee  = landmarks.worldPosition(for: .knee(side)) .map { smoother.smooth3D(key: "\(side)_knee",  position: $0, timestamp: ts) }
        let w_ankle = landmarks.worldPosition(for: .ankle(side)).map { smoother.smooth3D(key: "\(side)_ankle", position: $0, timestamp: ts) }

        let measuredKneeAngle: Float
        if let wh = w_hip, let wk = w_knee, let wa = w_ankle {
            measuredKneeAngle = AngleCalculator.angle3D(a: wh, b: wk, c: wa)
        } else {
            measuredKneeAngle = AngleCalculator.angle(a: hip, b: knee, c: ankle)
        }

        let minVis = min(
            landmarks.visibility(for: .hip(side)),
            landmarks.visibility(for: .knee(side)),
            landmarks.visibility(for: .ankle(side))
        )
        let isConfident = minVis >= minVertexVisibility && measuredKneeAngle.isFinite

        // Only trustworthy measurements drive rep counting and tempo classification.
        // Low-confidence frames are skipped entirely so one bad hip frame can't
        // spuriously flip rep state or poison the velocity window.
        if isConfident {
            repCounter.update(angle: measuredKneeAngle, timestamp: ts)
            lastValidKneeAngle = measuredKneeAngle
        }

        // Display path uses the last trusted angle to avoid flicker when tracking dips.
        let kneeAngle = isConfident ? measuredKneeAngle : (lastValidKneeAngle ?? measuredKneeAngle)

        // Emitted angle is NaN when not confident so RepMetricsCollector excludes the
        // frame from peak-angle tracking (phase/rep bookkeeping still proceeds).
        let emittedKneeAngle: Float = isConfident ? measuredKneeAngle : .nan
        let tempoPhase: TempoPhase? = isConfident
            ? tempoTracker.update(angle: measuredKneeAngle, timestamp: ts)
            : tempoTracker.currentPhase

        var instructions: [OverlayInstruction] = []

        // Spine overlay (drawn first so it sits behind joint labels)
        if let shoulder {
            instructions.append(contentsOf: SpineOverlay.instructions(
                ear: ear, shoulder: shoulder, hip: hip))
        }

        // Skeleton
        if let shoulder {
            instructions.append(.line(from: shoulder, to: hip, color: .green, width: 3))
        }
        instructions.append(.line(from: hip, to: knee, color: .green, width: 3))
        instructions.append(.line(from: knee, to: ankle, color: .green, width: 3))

        // Key joints
        instructions.append(.circle(at: knee, radius: 12, color: .red, filled: true))
        instructions.append(.circle(at: hip, radius: 10, color: .yellow, filled: true))
        instructions.append(.circle(at: ankle, radius: 10, color: .yellow, filled: true))
        if let shoulder {
            instructions.append(.circle(at: shoulder, radius: 10, color: .yellow, filled: true))
        }

        // Hip angle (shoulder→hip→knee) — display only, no effect on rep/tempo logic
        let hipAngle: Float?
        if let ws = w_shoulder, let wh = w_hip, let wk = w_knee {
            let a = AngleCalculator.angle3D(a: ws, b: wh, c: wk)
            hipAngle = a.isFinite ? a : nil
        } else if let s = shoulder {
            let a = AngleCalculator.angle(a: s, b: hip, c: knee)
            hipAngle = a.isFinite ? a : nil
        } else {
            hipAngle = nil
        }

        // Angle labels
        instructions.append(.text("Knee: \(AngleCalculator.displayDegrees(kneeAngle))°",
            at: SIMD2(knee.x - 0.05, knee.y + 0.05), color: .white, size: 20))
        if let hipAngle {
            instructions.append(.text("Hip: \(AngleCalculator.displayDegrees(hipAngle))°",
                at: SIMD2(hip.x + 0.02, hip.y - 0.04), color: .cyan, size: 18))
        }

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)",
            at: SIMD2(0.02, 0.05), color: .white, size: 24))

        return FrameAnalysis(
            angles: [JointAngle(joint: .knee, degrees: emittedKneeAngle)],
            repCount: repCounter.count,
            repState: repCounter.state,
            tempoPhase: tempoPhase,
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
        repCounter.reset()
        tempoTracker.reset()
        lastValidKneeAngle = nil
    }
}
