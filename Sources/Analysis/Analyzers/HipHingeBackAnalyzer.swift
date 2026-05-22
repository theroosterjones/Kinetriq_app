import Foundation
import simd

/// Bilateral hip hinge exercise filmed from behind.
/// Evaluates left/right symmetry (hip tilt, shoulder tilt, knee tracking) AND counts
/// reps + tempo using a self-calibrating trunk-height signal.
///
/// **Why self-calibration?**
/// From the back view the hinge is a depth (Z-axis) movement that doesn't produce a
/// clean 2D angle. Instead, as the person hinges forward their shoulders appear to drop
/// toward hip height in screen space. The rep counter uses `hipMid.y − shoulderMid.y`
/// (trunk height) as the signal — large when standing, smaller when hinged. Because the
/// exact range depends on filming distance and body proportions, fixed thresholds are
/// unreliable. Instead the counter observes the first 3 reps, averages the observed
/// standing (top) and hinged (bottom) positions, then locks precise thresholds for all
/// subsequent reps.
///
/// Until 3 reps are completed the counter uses dynamic 65 %/35 % thresholds of the
/// running observed range, so reps are still counted during the calibration window.
final class HipHingeBackAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .hipHingeBack
    let side: BodySide = .left  // bilateral — side parameter unused

    var requiredLandmarks: [PoseLandmarkType] {
        [
            .shoulder(.left), .shoulder(.right),
            .hip(.left),      .hip(.right),
            .knee(.left),     .knee(.right),
            .ankle(.left),    .ankle(.right),
            .ear(.left),      .ear(.right)
        ]
    }

    private let smoother = LandmarkSmoother()

    // MARK: - Rep counting & tempo (self-calibrating trunk-height signal)

    /// TempoTracker thresholds tuned for a normalised screen-coord signal × 100.
    /// The signal velocity for a typical 1–2 s hinge is ~10–30 pseudo-°/s.
    private let tempoTracker = TempoTracker(
        velocityThreshold: 8.0, pauseVelocityThreshold: 4.0)

    private var repState: RepState = .extended
    private(set) var repCount: Int = 0

    /// Running extremes across all frames (for bootstrap calibration).
    private var rollingMin: Float = .greatestFiniteMagnitude
    private var rollingMax: Float = -.greatestFiniteMagnitude

    /// Track the minimum trunk height within the current flexed (hinged) phase.
    private var currentRepMin: Float = .greatestFiniteMagnitude

    /// Observed bottom and top positions from completed reps (for calibration).
    private var observedMins:  [Float] = []
    private var observedMaxes: [Float] = []

    /// Locked thresholds after 3 reps. Nil = still using dynamic thresholds.
    private var lockedExtended: Float?
    private var lockedFlexed:   Float?
    private let calibReps = 3

    init(side: BodySide) {
        // side ignored
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawLS = landmarks.position(for: .shoulder(.left)),
              let rawRS = landmarks.position(for: .shoulder(.right)),
              let rawLH = landmarks.position(for: .hip(.left)),
              let rawRH = landmarks.position(for: .hip(.right)),
              let rawLK = landmarks.position(for: .knee(.left)),
              let rawRK = landmarks.position(for: .knee(.right)),
              let rawLA = landmarks.position(for: .ankle(.left)),
              let rawRA = landmarks.position(for: .ankle(.right)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let lShoulder = smoother.smooth(key: "left_shoulder",  position: rawLS, timestamp: ts)
        let rShoulder = smoother.smooth(key: "right_shoulder", position: rawRS, timestamp: ts)
        let lHip      = smoother.smooth(key: "left_hip",       position: rawLH, timestamp: ts)
        let rHip      = smoother.smooth(key: "right_hip",      position: rawRH, timestamp: ts)
        let lKnee     = smoother.smooth(key: "left_knee",      position: rawLK, timestamp: ts)
        let rKnee     = smoother.smooth(key: "right_knee",     position: rawRK, timestamp: ts)
        let lAnkle    = smoother.smooth(key: "left_ankle",     position: rawLA, timestamp: ts)
        let rAnkle    = smoother.smooth(key: "right_ankle",    position: rawRA, timestamp: ts)

        let wLS = landmarks.worldPosition(for: .shoulder(.left)) .map { smoother.smooth3D(key: "left_shoulder",  position: $0, timestamp: ts) }
        let wRS = landmarks.worldPosition(for: .shoulder(.right)).map { smoother.smooth3D(key: "right_shoulder", position: $0, timestamp: ts) }
        let wLH = landmarks.worldPosition(for: .hip(.left))      .map { smoother.smooth3D(key: "left_hip",       position: $0, timestamp: ts) }
        let wRH = landmarks.worldPosition(for: .hip(.right))     .map { smoother.smooth3D(key: "right_hip",      position: $0, timestamp: ts) }

        // Hip tilt (lateral pelvic shift in the frontal plane)
        let hipTiltDeg: Float
        if let wl = wLH, let wr = wRH {
            let dy = wr.y - wl.y
            let hDist = sqrt(pow(wr.x - wl.x, 2) + pow(wr.z - wl.z, 2))
            hipTiltDeg = atan2(dy, hDist) * (180.0 / .pi)
        } else {
            hipTiltDeg = -(atan2(rHip.y - lHip.y, rHip.x - lHip.x) * (180.0 / .pi))
        }

        // Shoulder tilt — upper-body lateral lean
        let shoulderTiltDeg: Float
        if let wl = wLS, let wr = wRS {
            let dy = wr.y - wl.y
            let hDist = sqrt(pow(wr.x - wl.x, 2) + pow(wr.z - wl.z, 2))
            shoulderTiltDeg = atan2(dy, hDist) * (180.0 / .pi)
        } else {
            shoulderTiltDeg = -(atan2(rShoulder.y - lShoulder.y,
                                      rShoulder.x - lShoulder.x) * (180.0 / .pi))
        }

        // Knee tracking: compare each knee's x offset relative to its hip and ankle midpoint.
        // Negative = knee caves inward (valgus); positive = knee flares outward (varus).
        func kneeOffset(hip: SIMD2<Float>, knee: SIMD2<Float>, ankle: SIMD2<Float>) -> Float {
            let mid = (hip + ankle) / 2.0
            return (knee.x - mid.x)
        }
        let lKneeOff = kneeOffset(hip: lHip, knee: lKnee, ankle: lAnkle)
        let rKneeOff = kneeOffset(hip: rHip, knee: rKnee, ankle: rAnkle)

        // Normalise by hip width so the metric is scale-independent (as % of hip width)
        let hipWidth = abs(rHip.x - lHip.x)
        let lKneePct = hipWidth > 1e-4 ? (lKneeOff / hipWidth) * 100.0 : 0
        let rKneePct = hipWidth > 1e-4 ? (rKneeOff / hipWidth) * 100.0 : 0

        let shoulderMid = (lShoulder + rShoulder) / 2.0
        let hipMid      = (lHip + rHip) / 2.0

        let lEar = landmarks.position(for: .ear(.left))
            .map { smoother.smooth(key: "left_ear", position: $0, timestamp: ts) }
        let rEar = landmarks.position(for: .ear(.right))
            .map { smoother.smooth(key: "right_ear", position: $0, timestamp: ts) }
        let earMid: SIMD2<Float>?
        if let le = lEar, let re = rEar { earMid = (le + re) / 2.0 }
        else { earMid = lEar ?? rEar }

        var instructions: [OverlayInstruction] = []

        // Spine overlay using bilateral midpoints
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: earMid, shoulder: shoulderMid, hip: hipMid))

        // Horizontal reference through hip midpoint
        let refLeft  = SIMD2<Float>(hipMid.x - 0.18, hipMid.y)
        let refRight = SIMD2<Float>(hipMid.x + 0.18, hipMid.y)
        instructions.append(.line(from: refLeft, to: refRight, color: .white, width: 1))

        // Shoulder girdle
        instructions.append(.line(from: lShoulder, to: rShoulder, color: .yellow, width: 4))

        // Spine reference
        instructions.append(.line(from: shoulderMid, to: hipMid, color: .green, width: 2))

        // Hip level line (primary tilt assessment)
        instructions.append(.line(from: lHip, to: rHip, color: .cyan, width: 4))

        // Leg lines
        instructions.append(.line(from: lHip,  to: lKnee,  color: .green, width: 3))
        instructions.append(.line(from: lKnee, to: lAnkle, color: .green, width: 3))
        instructions.append(.line(from: rHip,  to: rKnee,  color: .green, width: 3))
        instructions.append(.line(from: rKnee, to: rAnkle, color: .green, width: 3))

        // Knee tracking guide lines (hip→ankle plumb)
        instructions.append(.line(from: lHip, to: lAnkle, color: .magenta, width: 1))
        instructions.append(.line(from: rHip, to: rAnkle, color: .magenta, width: 1))

        // Joint circles
        instructions.append(.circle(at: lShoulder, radius: 10, color: .red,    filled: true))
        instructions.append(.circle(at: rShoulder, radius: 10, color: .blue,   filled: true))
        instructions.append(.circle(at: lHip,      radius: 12, color: .cyan,   filled: true))
        instructions.append(.circle(at: rHip,      radius: 12, color: .cyan,   filled: true))
        instructions.append(.circle(at: lKnee,     radius: 10, color: .yellow, filled: true))
        instructions.append(.circle(at: rKnee,     radius: 10, color: .yellow, filled: true))
        instructions.append(.circle(at: lAnkle,    radius: 8,  color: .orange, filled: true))
        instructions.append(.circle(at: rAnkle,    radius: 8,  color: .orange, filled: true))

        // Side labels
        instructions.append(.text("L", at: SIMD2(lShoulder.x - 0.05, lShoulder.y - 0.05), color: .red,  size: 20))
        instructions.append(.text("R", at: SIMD2(rShoulder.x + 0.02, rShoulder.y - 0.05), color: .blue, size: 20))

        // MARK: Rep counting via self-calibrating trunk-height signal

        // Signal: hipMid.y − shoulderMid.y (screen y-down).
        // LARGE = standing (shoulders well above hips). SMALL = hinged forward.
        let trunkHeight = hipMid.y - shoulderMid.y

        // Update observed range across all frames.
        rollingMin = min(rollingMin, trunkHeight)
        rollingMax = max(rollingMax, trunkHeight)

        // Compute effective thresholds (locked after calibReps, dynamic before).
        let range = rollingMax - rollingMin
        let extThr: Float
        let flxThr: Float
        if let le = lockedExtended, let lf = lockedFlexed {
            extThr = le
            flxThr = lf
        } else if range >= 0.04 {
            extThr = rollingMin + range * 0.65
            flxThr = rollingMin + range * 0.35
        } else {
            extThr = .nan  // not enough range observed yet
            flxThr = .nan
        }

        // State machine: standing → hinged → standing = 1 rep.
        if extThr.isFinite && flxThr.isFinite {
            switch repState {
            case .extended where trunkHeight < flxThr:
                repState = .flexed
                currentRepMin = trunkHeight

            case .flexed where trunkHeight > extThr:
                repState = .extended
                repCount += 1
                observedMins.append(currentRepMin)
                observedMaxes.append(trunkHeight)
                currentRepMin = .greatestFiniteMagnitude
                // Lock calibration after first calibReps reps.
                if observedMins.count == calibReps, lockedExtended == nil {
                    let avgMax = observedMaxes.prefix(calibReps).reduce(0, +) / Float(calibReps)
                    let avgMin = observedMins.prefix(calibReps).reduce(0, +) / Float(calibReps)
                    let calRange = avgMax - avgMin
                    if calRange > 0.02 {
                        lockedExtended = avgMin + calRange * 0.65
                        lockedFlexed   = avgMin + calRange * 0.35
                    }
                }

            case .flexed:
                // Still descending — track deepest point for this rep.
                currentRepMin = min(currentRepMin, trunkHeight)

            default:
                break
            }
        }

        // Tempo: scale trunk height to pseudo-°range so TempoTracker velocity is meaningful.
        // Decreasing signal = hinging forward = eccentric; increasing = standing = concentric.
        let tempoPhase = tempoTracker.update(angle: trunkHeight * 100, timestamp: ts)

        // MARK: HUD
        let isCalibrating = lockedExtended == nil
        let hipElevated  = hipTiltDeg    >= 0 ? "R hip high"      : "L hip high"
        let shoulderNote = shoulderTiltDeg >= 0 ? "R shoulder high" : "L shoulder high"

        instructions.append(.text("Reps: \(repCount)",
            at: SIMD2(0.02, 0.05), color: .white, size: 24))
        instructions.append(.text(isCalibrating ? "Calibrating…" : "Tracking",
            at: SIMD2(0.02, 0.11), color: isCalibrating ? .orange : .green, size: 16))
        instructions.append(.text("Hip: \(hipElevated)  \(String(format: "%.1f", abs(hipTiltDeg)))\u{00B0}",
            at: SIMD2(0.02, 0.17), color: .white,  size: 18))
        instructions.append(.text("Shoulder: \(String(format: "%.1f", abs(shoulderTiltDeg)))\u{00B0}  \(shoulderNote)",
            at: SIMD2(0.02, 0.23), color: .yellow, size: 16))

        let lKneeTag = lKneePct < -8 ? "valgus" : (lKneePct > 8 ? "varus" : "OK")
        let rKneeTag = rKneePct < -8 ? "valgus" : (rKneePct > 8 ? "varus" : "OK")
        instructions.append(.text("L knee: \(lKneeTag)   R knee: \(rKneeTag)",
            at: SIMD2(0.02, 0.29), color: .cyan, size: 16))

        return FrameAnalysis(
            angles: [JointAngle(joint: .hip, degrees: hipTiltDeg)],
            repCount: repCount,
            repState: repState,
            tempoPhase: tempoPhase,
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
        tempoTracker.reset()
        repState = .extended
        repCount = 0
        currentRepMin = .greatestFiniteMagnitude
        rollingMin = .greatestFiniteMagnitude
        rollingMax = -.greatestFiniteMagnitude
        observedMins.removeAll()
        observedMaxes.removeAll()
        lockedExtended = nil
        lockedFlexed = nil
    }
}
