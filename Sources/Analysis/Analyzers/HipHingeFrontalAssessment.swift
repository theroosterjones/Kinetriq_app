import Foundation
import simd

/// Hip hinge quality assessment filmed from the **frontal plane** (typically
/// directly behind the subject, but front works equally well — both expose the
/// bilateral metrics this analyzer cares about).
///
/// Sub-metrics graded:
///   - **Hip Level** — pelvic tilt: lateral elevation of one hip relative to the
///     other, expressed as the angle of the inter-hip line from horizontal. A
///     hinge with a level pelvis suggests balanced hip mobility and glute drive.
///   - **Shoulder Level** — upper-body lateral lean: angle of the shoulder line
///     from horizontal. A tilted shoulder line during a hinge usually indicates
///     a compensatory rotation through the thoracic spine.
///   - **Knee Tracking** — worst-case medial / lateral knee deviation
///     (valgus / varus) measured as a percentage of hip width. Tracks each knee
///     against the hip→ankle line independently.
///
/// Overall grade = worst sub-metric (weakest-link model).
final class HipHingeFrontalAssessment: AssessmentAnalyzer {

    let assessmentType: AssessmentType = .hipHingeAssessment

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

    /// Worst-observed (largest) absolute hip tilt across the clip, in degrees.
    private var worstHipTilt: Float = 0
    /// Worst-observed shoulder tilt across the clip, in degrees.
    private var worstShoulderTilt: Float = 0
    /// Worst-observed knee tracking deviation across the clip, as % of hip width.
    private var worstKneeTracking: Float = 0

    /// "High side" sticky labels — captured from the worst-tilt frame so the
    /// summary report can name the side rather than just the magnitude.
    private var hipHighSide: BodySide?
    private var shoulderHighSide: BodySide?

    private var hipHysteresis      = GradeHysteresis()
    private var shoulderHysteresis = GradeHysteresis()
    private var kneeHysteresis     = GradeHysteresis()

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

        let lEar = landmarks.position(for: .ear(.left))
            .map { smoother.smooth(key: "left_ear", position: $0, timestamp: ts) }
        let rEar = landmarks.position(for: .ear(.right))
            .map { smoother.smooth(key: "right_ear", position: $0, timestamp: ts) }

        let wLS = landmarks.worldPosition(for: .shoulder(.left)) .map { smoother.smooth3D(key: "left_shoulder",  position: $0, timestamp: ts) }
        let wRS = landmarks.worldPosition(for: .shoulder(.right)).map { smoother.smooth3D(key: "right_shoulder", position: $0, timestamp: ts) }
        let wLH = landmarks.worldPosition(for: .hip(.left))      .map { smoother.smooth3D(key: "left_hip",       position: $0, timestamp: ts) }
        let wRH = landmarks.worldPosition(for: .hip(.right))     .map { smoother.smooth3D(key: "right_hip",      position: $0, timestamp: ts) }

        // Hip tilt: angle of the inter-hip line from horizontal, signed so the
        // sign tells us *which* side is high. 3D when available — projecting
        // x and z together flattens out any small sagittal misalignment of
        // the camera, leaving the true frontal-plane tilt.
        let hipTiltDeg = signedTilt(left: lHip, right: rHip, wLeft: wLH, wRight: wRH)
        let shoulderTiltDeg = signedTilt(left: lShoulder, right: rShoulder, wLeft: wLS, wRight: wRS)

        // Knee tracking offset, normalised by hip width to be scale-invariant.
        let lKneePct = kneeTrackingPercent(hip: lHip, knee: lKnee, ankle: lAnkle, hipWidth: abs(rHip.x - lHip.x))
        let rKneePct = kneeTrackingPercent(hip: rHip, knee: rKnee, ankle: rAnkle, hipWidth: abs(rHip.x - lHip.x))
        let worstFrameKneeAbs = max(abs(lKneePct), abs(rKneePct))

        // Update best/worst trackers with sticky "high side" labels.
        let absHip = abs(hipTiltDeg)
        if absHip > worstHipTilt {
            worstHipTilt = absHip
            hipHighSide = hipTiltDeg >= 0 ? .right : .left
        }
        let absShoulder = abs(shoulderTiltDeg)
        if absShoulder > worstShoulderTilt {
            worstShoulderTilt = absShoulder
            shoulderHighSide = shoulderTiltDeg >= 0 ? .right : .left
        }
        worstKneeTracking = max(worstKneeTracking, worstFrameKneeAbs)

        // Per-frame grades for the colored skeleton (with hysteresis).
        let hipGrade      = LetterGrade.gradeLowerIsBetter(value: absHip,            a: 3,  b: 6,  c: 10, d: 15)
        let shoulderGrade = LetterGrade.gradeLowerIsBetter(value: absShoulder,       a: 3,  b: 6,  c: 10, d: 15)
        let kneeGrade     = LetterGrade.gradeLowerIsBetter(value: worstFrameKneeAbs, a: 5,  b: 10, c: 15, d: 25)

        let displayHip      = hipHysteresis.update(hipGrade)
        let displayShoulder = shoulderHysteresis.update(shoulderGrade)
        let displayKnee     = kneeHysteresis.update(kneeGrade)

        let hipColor      = OverlayColor.romQuality(grade: displayHip)
        let shoulderColor = OverlayColor.romQuality(grade: displayShoulder)
        let kneeColor     = OverlayColor.romQuality(grade: displayKnee)

        let shoulderMid = (lShoulder + rShoulder) / 2.0
        let hipMid      = (lHip + rHip) / 2.0
        let earMid: SIMD2<Float>?
        if let le = lEar, let re = rEar { earMid = (le + re) / 2.0 }
        else { earMid = lEar ?? rEar }

        var instructions: [OverlayInstruction] = []

        // Spine overlay (drawn first so it sits behind joint markers).
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: earMid, shoulder: shoulderMid, hip: hipMid))

        // Horizontal reference through the hip midpoint to make the tilt obvious.
        let refLeft  = SIMD2<Float>(hipMid.x - 0.18, hipMid.y)
        let refRight = SIMD2<Float>(hipMid.x + 0.18, hipMid.y)
        instructions.append(.line(from: refLeft, to: refRight, color: .white, width: 1))

        // Shoulder girdle and hip line, both colored by their respective tilt grade.
        instructions.append(.line(from: lShoulder, to: rShoulder, color: shoulderColor, width: 4))
        instructions.append(.line(from: lHip,      to: rHip,      color: hipColor,      width: 4))

        // Spine reference and legs.
        instructions.append(.line(from: shoulderMid, to: hipMid, color: .green, width: 2))
        instructions.append(.line(from: lHip,  to: lKnee,  color: kneeColor, width: 3))
        instructions.append(.line(from: lKnee, to: lAnkle, color: kneeColor, width: 3))
        instructions.append(.line(from: rHip,  to: rKnee,  color: kneeColor, width: 3))
        instructions.append(.line(from: rKnee, to: rAnkle, color: kneeColor, width: 3))

        // Hip→ankle plumb references for visualising knee deviation.
        instructions.append(.line(from: lHip, to: lAnkle, color: .magenta, width: 1))
        instructions.append(.line(from: rHip, to: rAnkle, color: .magenta, width: 1))

        // Joint markers
        instructions.append(.circle(at: lShoulder, radius: 10, color: shoulderColor, filled: true))
        instructions.append(.circle(at: rShoulder, radius: 10, color: shoulderColor, filled: true))
        instructions.append(.circle(at: lHip,      radius: 12, color: hipColor,      filled: true))
        instructions.append(.circle(at: rHip,      radius: 12, color: hipColor,      filled: true))
        instructions.append(.circle(at: lKnee,     radius: 10, color: kneeColor,     filled: true))
        instructions.append(.circle(at: rKnee,     radius: 10, color: kneeColor,     filled: true))
        instructions.append(.circle(at: lAnkle,    radius: 8,  color: .orange,       filled: true))
        instructions.append(.circle(at: rAnkle,    radius: 8,  color: .orange,       filled: true))

        // Side labels
        instructions.append(.text("L", at: SIMD2(lShoulder.x - 0.05, lShoulder.y - 0.05), color: .white, size: 18))
        instructions.append(.text("R", at: SIMD2(rShoulder.x + 0.02, rShoulder.y - 0.05), color: .white, size: 18))

        // HUD
        let overall = currentMetrics().grade
        instructions.append(.text(overall.rawValue,
            at: SIMD2(0.85, 0.05), color: OverlayColor.romQuality(grade: overall), size: 36))
        instructions.append(.text("Hip tilt: \(String(format: "%.1f", absHip))\u{00B0}",
            at: SIMD2(0.02, 0.05), color: hipColor, size: 18))
        instructions.append(.text("Shoulder tilt: \(String(format: "%.1f", absShoulder))\u{00B0}",
            at: SIMD2(0.02, 0.11), color: shoulderColor, size: 18))
        instructions.append(.text("Knee track: \(String(format: "%.0f", worstFrameKneeAbs))%",
            at: SIMD2(0.02, 0.17), color: kneeColor, size: 18))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .hip,      degrees: hipTiltDeg),
                JointAngle(joint: .shoulder, degrees: shoulderTiltDeg)
            ],
            repCount: 0,
            repState: .extended,
            tempoPhase: nil,
            overlayInstructions: instructions
        )
    }

    func currentMetrics() -> AssessmentMetrics {
        let hipGrade      = LetterGrade.gradeLowerIsBetter(value: worstHipTilt,      a: 3, b: 6, c: 10, d: 15)
        let shoulderGrade = LetterGrade.gradeLowerIsBetter(value: worstShoulderTilt, a: 3, b: 6, c: 10, d: 15)
        let kneeGrade     = LetterGrade.gradeLowerIsBetter(value: worstKneeTracking, a: 5, b: 10, c: 15, d: 25)
        let overall       = max(hipGrade, max(shoulderGrade, kneeGrade))

        var details: [String] = []
        if let high = hipHighSide {
            details.append("Worst hip tilt: \(String(format: "%.1f", worstHipTilt))° (\(high == .left ? "L" : "R") hip high) (\(hipGrade.rawValue))")
        } else {
            details.append("Worst hip tilt: \(String(format: "%.1f", worstHipTilt))° (\(hipGrade.rawValue))")
        }
        if let high = shoulderHighSide {
            details.append("Worst shoulder tilt: \(String(format: "%.1f", worstShoulderTilt))° (\(high == .left ? "L" : "R") shoulder high) (\(shoulderGrade.rawValue))")
        } else {
            details.append("Worst shoulder tilt: \(String(format: "%.1f", worstShoulderTilt))° (\(shoulderGrade.rawValue))")
        }
        details.append("Worst knee tracking: \(String(format: "%.0f", worstKneeTracking))% (\(kneeGrade.rawValue))")

        return AssessmentMetrics(
            grade: overall,
            subGrades: [
                ("Hip Level", hipGrade),
                ("Shoulder Level", shoulderGrade),
                ("Knee Tracking", kneeGrade)
            ],
            leftROM: nil,
            rightROM: nil,
            asymmetryDeg: nil,
            asymmetryFlag: false,
            details: details
        )
    }

    func reset() {
        smoother.reset()
        worstHipTilt = 0
        worstShoulderTilt = 0
        worstKneeTracking = 0
        hipHighSide = nil
        shoulderHighSide = nil
        hipHysteresis      = GradeHysteresis()
        shoulderHysteresis = GradeHysteresis()
        kneeHysteresis     = GradeHysteresis()
    }

    /// Signed angle (deg) of the right-minus-left vector from horizontal. Positive
    /// when the right landmark is below the left (i.e. the left side is "high").
    /// Falls back to 2D when world landmarks aren't available.
    private func signedTilt(left l: SIMD2<Float>, right r: SIMD2<Float>,
                            wLeft wl: SIMD3<Float>?, wRight wr: SIMD3<Float>?) -> Float {
        if let wl, let wr {
            let dy = wr.y - wl.y
            let hDist = sqrt(pow(wr.x - wl.x, 2) + pow(wr.z - wl.z, 2))
            return atan2(dy, max(hDist, 1e-6)) * (180.0 / .pi)
        } else {
            // 2D screen y grows downward, so negate to match world-space convention
            // (positive = right side higher).
            return -(atan2(r.y - l.y, r.x - l.x) * (180.0 / .pi))
        }
    }

    /// Knee tracking offset as a percentage of hip width. Negative = valgus (medial),
    /// positive = varus (lateral). Returns 0 when hip width is degenerate.
    private func kneeTrackingPercent(hip: SIMD2<Float>, knee: SIMD2<Float>,
                                     ankle: SIMD2<Float>, hipWidth: Float) -> Float {
        guard hipWidth > 1e-4 else { return 0 }
        let mid = (hip + ankle) / 2.0
        return ((knee.x - mid.x) / hipWidth) * 100.0
    }
}
