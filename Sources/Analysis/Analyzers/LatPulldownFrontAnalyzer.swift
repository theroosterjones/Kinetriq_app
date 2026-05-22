import Foundation
import simd

/// Bilateral lat pulldown / chin-up analyzer filmed from the front or back.
///
/// Tracks both elbow angles (shoulder→elbow→wrist) and both shoulder angles
/// (hip→shoulder→elbow) independently. Rep counting is driven by the average
/// elbow angle. Spine midline and bilateral hip markers are always drawn so
/// posture and torso position are visible throughout the set.
///
/// Film from directly in front of or behind the cable stack / pull-up bar.
/// Keep both arms and both hips visible in frame throughout the rep.
final class LatPulldownFrontAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .latPulldownFront
    // Bilateral — side parameter is not used; stored as .left to satisfy the protocol.
    let side: BodySide = .left

    var requiredLandmarks: [PoseLandmarkType] {
        [
            .shoulder(.left),  .shoulder(.right),
            .elbow(.left),     .elbow(.right),
            .wrist(.left),     .wrist(.right),
            .hip(.left),       .hip(.right)
        ]
    }

    private let smoother     = LandmarkSmoother()
    // invertPhases: true — pulling bar down closes the elbows (angle ↓) = concentric.
    private let repCounter   = RepCounter(extendedThreshold: 150, flexedThreshold: 80)
    private let tempoTracker = TempoTracker(invertPhases: true)

    init(side: BodySide) {
        // side ignored — bilateral analyzer
    }

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
            .map { smoother.smooth(key: "left_ear",  position: $0, timestamp: ts) }
        let rEar = landmarks.position(for: .ear(.right))
            .map { smoother.smooth(key: "right_ear", position: $0, timestamp: ts) }
        let earMid: SIMD2<Float>?
        if let le = lEar, let re = rEar { earMid = (le + re) / 2.0 }
        else { earMid = lEar ?? rEar }

        let wLS = landmarks.worldPosition(for: .shoulder(.left)) .map { smoother.smooth3D(key: "left_shoulder",  position: $0, timestamp: ts) }
        let wRS = landmarks.worldPosition(for: .shoulder(.right)).map { smoother.smooth3D(key: "right_shoulder", position: $0, timestamp: ts) }
        let wLE = landmarks.worldPosition(for: .elbow(.left))    .map { smoother.smooth3D(key: "left_elbow",     position: $0, timestamp: ts) }
        let wRE = landmarks.worldPosition(for: .elbow(.right))   .map { smoother.smooth3D(key: "right_elbow",    position: $0, timestamp: ts) }
        let wLW = landmarks.worldPosition(for: .wrist(.left))    .map { smoother.smooth3D(key: "left_wrist",     position: $0, timestamp: ts) }
        let wRW = landmarks.worldPosition(for: .wrist(.right))   .map { smoother.smooth3D(key: "right_wrist",    position: $0, timestamp: ts) }
        let wLH = landmarks.worldPosition(for: .hip(.left))      .map { smoother.smooth3D(key: "left_hip",       position: $0, timestamp: ts) }
        let wRH = landmarks.worldPosition(for: .hip(.right))     .map { smoother.smooth3D(key: "right_hip",      position: $0, timestamp: ts) }

        // Elbow angles (shoulder→elbow→wrist)
        let lElbowAngle: Float
        if let ws = wLS, let we = wLE, let ww = wLW {
            lElbowAngle = AngleCalculator.angle3D(a: ws, b: we, c: ww)
        } else {
            lElbowAngle = AngleCalculator.angle(a: lShoulder, b: lElbow, c: lWrist)
        }

        let rElbowAngle: Float
        if let ws = wRS, let we = wRE, let ww = wRW {
            rElbowAngle = AngleCalculator.angle3D(a: ws, b: we, c: ww)
        } else {
            rElbowAngle = AngleCalculator.angle(a: rShoulder, b: rElbow, c: rWrist)
        }

        let avgElbowAngle = (lElbowAngle + rElbowAngle) / 2.0

        // Shoulder angles (hip→shoulder→elbow) — measures arm abduction / elevation
        let lShoulderAngle: Float
        if let wh = wLH, let ws = wLS, let we = wLE {
            lShoulderAngle = AngleCalculator.angle3D(a: wh, b: ws, c: we)
        } else {
            lShoulderAngle = AngleCalculator.angle(a: lHip, b: lShoulder, c: lElbow)
        }

        let rShoulderAngle: Float
        if let wh = wRH, let ws = wRS, let we = wRE {
            rShoulderAngle = AngleCalculator.angle3D(a: wh, b: ws, c: we)
        } else {
            rShoulderAngle = AngleCalculator.angle(a: rHip, b: rShoulder, c: rElbow)
        }

        let avgShoulderAngle = (lShoulderAngle + rShoulderAngle) / 2.0

        repCounter.update(angle: avgElbowAngle, timestamp: ts)

        let shoulderMid = (lShoulder + rShoulder) / 2.0
        let hipMid      = (lHip + rHip) / 2.0

        var instructions: [OverlayInstruction] = []

        // Spine overlay (ear midpoint → shoulder midpoint → mid-spine → hip midpoint).
        // Drawn first so arms and joints sit on top.
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: earMid, shoulder: shoulderMid, hip: hipMid))

        // Shoulder girdle and hip baseline
        instructions.append(.line(from: lShoulder, to: rShoulder, color: .yellow, width: 3))
        instructions.append(.line(from: lHip,      to: rHip,      color: .cyan,   width: 3))

        // Left arm
        instructions.append(.line(from: lShoulder, to: lElbow, color: .yellow, width: 3))
        instructions.append(.line(from: lElbow,    to: lWrist, color: .yellow, width: 3))

        // Right arm
        instructions.append(.line(from: rShoulder, to: rElbow, color: .yellow, width: 3))
        instructions.append(.line(from: rElbow,    to: rWrist, color: .yellow, width: 3))

        // Extended forearm lines toward the bar
        instructions.append(.extendedLine(from: lWrist, through: lElbow, color: .cyan, width: 2))
        instructions.append(.extendedLine(from: rWrist, through: rElbow, color: .cyan, width: 2))

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
        instructions.append(.text("L Elbow: \(AngleCalculator.displayDegrees(lElbowAngle))\u{00B0}",
            at: SIMD2(lElbow.x - 0.12, lElbow.y + 0.03), color: .white, size: 18))
        instructions.append(.text("R Elbow: \(AngleCalculator.displayDegrees(rElbowAngle))\u{00B0}",
            at: SIMD2(rElbow.x + 0.02, rElbow.y + 0.03), color: .white, size: 18))

        // Shoulder angle labels
        if lShoulderAngle.isFinite {
            instructions.append(.text("L Shld: \(AngleCalculator.displayDegrees(lShoulderAngle))\u{00B0}",
                at: SIMD2(lShoulder.x - 0.12, lShoulder.y + 0.04), color: .cyan, size: 16))
        }
        if rShoulderAngle.isFinite {
            instructions.append(.text("R Shld: \(AngleCalculator.displayDegrees(rShoulderAngle))\u{00B0}",
                at: SIMD2(rShoulder.x + 0.02, rShoulder.y + 0.04), color: .cyan, size: 16))
        }

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)",
            at: SIMD2(0.02, 0.05), color: .white, size: 24))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .elbow,    degrees: avgElbowAngle),
                JointAngle(joint: .shoulder, degrees: avgShoulderAngle)
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
