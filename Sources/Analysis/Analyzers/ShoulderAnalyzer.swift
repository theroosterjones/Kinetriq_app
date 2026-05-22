import Foundation
import simd

/// Bilateral shoulder elevation/depression assessment filmed from behind (posterior/frontal plane).
///
/// Measures the tilt of the shoulder girdle relative to horizontal, identifying which side is
/// elevated or depressed, and compares against the pelvis as a reference baseline.
/// No rep counting — this is a postural assessment, not a rep-based exercise.
final class ShoulderAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .shoulderAssessment
    // Bilateral — side is not applicable, stored as .left to satisfy the protocol.
    let side: BodySide = .left

    var requiredLandmarks: [PoseLandmarkType] {
        [
            .shoulder(.left), .shoulder(.right),
            .elbow(.left), .elbow(.right),
            .wrist(.left), .wrist(.right),
            .hip(.left), .hip(.right)
        ]
    }

    private let smoother = LandmarkSmoother()

    init(side: BodySide) {
        // side parameter ignored — this analyzer always uses both sides
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawLeftShoulder  = landmarks.position(for: .shoulder(.left)),
              let rawRightShoulder = landmarks.position(for: .shoulder(.right)),
              let rawLeftElbow     = landmarks.position(for: .elbow(.left)),
              let rawRightElbow    = landmarks.position(for: .elbow(.right)),
              let rawLeftWrist     = landmarks.position(for: .wrist(.left)),
              let rawRightWrist    = landmarks.position(for: .wrist(.right)),
              let rawLeftHip       = landmarks.position(for: .hip(.left)),
              let rawRightHip      = landmarks.position(for: .hip(.right)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let leftShoulder  = smoother.smooth(key: "left_shoulder",  position: rawLeftShoulder,  timestamp: ts)
        let rightShoulder = smoother.smooth(key: "right_shoulder", position: rawRightShoulder, timestamp: ts)
        let leftElbow     = smoother.smooth(key: "left_elbow",     position: rawLeftElbow,     timestamp: ts)
        let rightElbow    = smoother.smooth(key: "right_elbow",    position: rawRightElbow,    timestamp: ts)
        let leftWrist     = smoother.smooth(key: "left_wrist",     position: rawLeftWrist,     timestamp: ts)
        let rightWrist    = smoother.smooth(key: "right_wrist",    position: rawRightWrist,    timestamp: ts)
        let leftHip       = smoother.smooth(key: "left_hip",       position: rawLeftHip,       timestamp: ts)
        let rightHip      = smoother.smooth(key: "right_hip",      position: rawRightHip,      timestamp: ts)

        // Ears are optional — used only as the cervical anchor of the spine
        // overlay. Falls back to either available side, or no cervical extension.
        let leftEar = landmarks.position(for: .ear(.left))
            .map { smoother.smooth(key: "left_ear", position: $0, timestamp: ts) }
        let rightEar = landmarks.position(for: .ear(.right))
            .map { smoother.smooth(key: "right_ear", position: $0, timestamp: ts) }
        let earMid: SIMD2<Float>?
        if let le = leftEar, let re = rightEar { earMid = (le + re) / 2.0 }
        else { earMid = leftEar ?? rightEar }

        let wLeftShoulder  = landmarks.worldPosition(for: .shoulder(.left)) .map { smoother.smooth3D(key: "left_shoulder",  position: $0, timestamp: ts) }
        let wRightShoulder = landmarks.worldPosition(for: .shoulder(.right)).map { smoother.smooth3D(key: "right_shoulder", position: $0, timestamp: ts) }
        let wLeftHip       = landmarks.worldPosition(for: .hip(.left))      .map { smoother.smooth3D(key: "left_hip",       position: $0, timestamp: ts) }
        let wRightHip      = landmarks.worldPosition(for: .hip(.right))     .map { smoother.smooth3D(key: "right_hip",      position: $0, timestamp: ts) }

        // Shoulder tilt angle from horizontal.
        // 3D version: uses metric y (up = positive) and accounts for depth (z).
        //   Positive = right shoulder higher; negative = left shoulder higher.
        // 2D fallback: screen-space atan2 (y-down), sign convention flipped for label consistency.
        let shoulderTiltDeg: Float
        let using3D: Bool
        if let wl = wLeftShoulder, let wr = wRightShoulder {
            let dy = wr.y - wl.y
            let horizontalDist = sqrt(pow(wr.x - wl.x, 2) + pow(wr.z - wl.z, 2))
            shoulderTiltDeg = atan2(dy, horizontalDist) * (180.0 / .pi)
            using3D = true
        } else {
            // Screen-space fallback: positive = left elevated (y-down coords)
            shoulderTiltDeg = -(atan2(rightShoulder.y - leftShoulder.y,
                                      rightShoulder.x - leftShoulder.x) * (180.0 / .pi))
            using3D = false
        }

        // Hip tilt for baseline reference (same 3D/2D logic)
        let hipTiltDeg: Float
        if let wl = wLeftHip, let wr = wRightHip {
            let dy = wr.y - wl.y
            let horizontalDist = sqrt(pow(wr.x - wl.x, 2) + pow(wr.z - wl.z, 2))
            hipTiltDeg = atan2(dy, horizontalDist) * (180.0 / .pi)
        } else {
            hipTiltDeg = -(atan2(rightHip.y - leftHip.y,
                                  rightHip.x - leftHip.x) * (180.0 / .pi))
        }

        let shoulderMid = (leftShoulder + rightShoulder) / 2.0
        let hipMid      = (leftHip + rightHip) / 2.0

        // Elbow deviation from the shoulder→wrist guide line.
        // Report as % of shoulder-wrist segment length for side-to-side comparability.
        func elbowDeviationPercent(shoulder: SIMD2<Float>, elbow: SIMD2<Float>, wrist: SIMD2<Float>) -> Float {
            let line = wrist - shoulder
            let lineLen = simd_length(line)
            guard lineLen > 1e-6 else { return 0 }

            let pointVec = elbow - shoulder
            let area2 = abs(line.x * pointVec.y - line.y * pointVec.x) // 2D cross magnitude
            let distance = area2 / lineLen
            return (distance / lineLen) * 100.0
        }

        let leftElbowDevPct = elbowDeviationPercent(shoulder: leftShoulder, elbow: leftElbow, wrist: leftWrist)
        let rightElbowDevPct = elbowDeviationPercent(shoulder: rightShoulder, elbow: rightElbow, wrist: rightWrist)

        var instructions: [OverlayInstruction] = []

        // Spine overlay (ear midpoint → shoulder midpoint → mid-spine → hip midpoint).
        // Drawn first so reference lines and the shoulder girdle sit on top of it.
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: earMid, shoulder: shoulderMid, hip: hipMid))

        // Horizontal reference line through shoulder midpoint
        let refLeft  = SIMD2<Float>(shoulderMid.x - 0.18, shoulderMid.y)
        let refRight = SIMD2<Float>(shoulderMid.x + 0.18, shoulderMid.y)
        instructions.append(.line(from: refLeft, to: refRight, color: .white, width: 1))

        // Pelvis / hip level line (reference baseline)
        instructions.append(.line(from: leftHip, to: rightHip, color: .cyan, width: 2))

        // Shoulder girdle line (primary measurement)
        instructions.append(.line(from: leftShoulder, to: rightShoulder, color: .yellow, width: 4))

        // Shoulder-to-wrist guide lines help assess whether elbows drift off the arm path.
        instructions.append(.line(from: leftShoulder, to: leftWrist, color: .magenta, width: 2))
        instructions.append(.line(from: rightShoulder, to: rightWrist, color: .magenta, width: 2))

        // Optional arm segment lines for clearer elbow positioning.
        instructions.append(.line(from: leftShoulder, to: leftElbow, color: .blue, width: 2))
        instructions.append(.line(from: leftElbow, to: leftWrist, color: .blue, width: 2))
        instructions.append(.line(from: rightShoulder, to: rightElbow, color: .blue, width: 2))
        instructions.append(.line(from: rightElbow, to: rightWrist, color: .blue, width: 2))

        // Joint circles — shoulders, elbows, wrists, hips
        instructions.append(.circle(at: leftShoulder,  radius: 12, color: .red,    filled: true))
        instructions.append(.circle(at: rightShoulder, radius: 12, color: .blue,   filled: true))
        instructions.append(.circle(at: leftElbow,     radius: 9,  color: .white,  filled: true))
        instructions.append(.circle(at: rightElbow,    radius: 9,  color: .white,  filled: true))
        instructions.append(.circle(at: leftWrist,     radius: 8,  color: .orange, filled: true))
        instructions.append(.circle(at: rightWrist,    radius: 8,  color: .orange, filled: true))
        instructions.append(.circle(at: leftHip,       radius: 8,  color: .orange, filled: true))
        instructions.append(.circle(at: rightHip,      radius: 8,  color: .orange, filled: true))

        // Side labels
        instructions.append(.text("L", at: SIMD2(leftShoulder.x  - 0.05, leftShoulder.y  - 0.05), color: .red,  size: 20))
        instructions.append(.text("R", at: SIMD2(rightShoulder.x + 0.02, rightShoulder.y - 0.05), color: .blue, size: 20))

        // HUD — which side is elevated and by how much
        // Positive = right elevated (both 3D and normalised-2D fallback share this convention now)
        let absTilt = abs(shoulderTiltDeg)
        let elevatedSide = shoulderTiltDeg >= 0 ? "R elevated" : "L elevated"
        let modeTag = using3D ? "" : " (2D)"
        instructions.append(.text("\(elevatedSide)  \(String(format: "%.1f", absTilt))\u{00B0}\(modeTag)",
                                  at: SIMD2(0.02, 0.05), color: .white, size: 22))
        instructions.append(.text("Hip ref: \(String(format: "%.1f", hipTiltDeg))\u{00B0}",
                                  at: SIMD2(0.02, 0.11), color: .cyan,  size: 18))
        instructions.append(.text("L dev: \(String(format: "%.1f", leftElbowDevPct))%   R dev: \(String(format: "%.1f", rightElbowDevPct))%",
                                  at: SIMD2(0.02, 0.17), color: .magenta, size: 18))

        return FrameAnalysis(
            angles: [JointAngle(joint: .shoulder, degrees: shoulderTiltDeg)],
            repCount: 0,
            repState: .extended,
            tempoPhase: nil,
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
    }
}
