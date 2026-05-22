import Foundation
import simd

/// Shoulder flexion ROM assessment filmed from the **sagittal plane**
/// (a strict 90° side profile of the working arm).
///
/// Single-side analyzer that measures the wrist → shoulder → hip angle as the
/// arm sweeps overhead. Side fallback (à la `RowAnalyzer`) auto-picks the more
/// visible side when the user accidentally films the wrong profile, so a
/// "left side selected, right side facing camera" mistake doesn't yield a
/// useless F result.
///
/// Grading mirrors the bilateral / frontal-plane assessment:
///   - A ≥ 170°
///   - B ≥ 150°
///   - C ≥ 130°
///   - D ≥ 110°
///   - F  < 110°
final class ShoulderFlexionSagittalAssessment: AssessmentAnalyzer {

    let assessmentType: AssessmentType = .shoulderFlexion
    let preferredSide: BodySide

    /// Visibility threshold below which we'll consider falling back to the
    /// opposite side. Same default as `RowAnalyzer`.
    private let minimumPreferredVisibility: Float = 0.35
    /// Required margin the alternate side must beat the preferred side by
    /// before we'll switch. Prevents flapping near the threshold.
    private let visibilityFallbackMargin: Float = 0.20

    var requiredLandmarks: [PoseLandmarkType] {
        [
            .shoulder(preferredSide), .elbow(preferredSide), .wrist(preferredSide), .hip(preferredSide),
            .shoulder(preferredSide.opposite), .elbow(preferredSide.opposite),
            .wrist(preferredSide.opposite), .hip(preferredSide.opposite),
            .ear(preferredSide), .ear(preferredSide.opposite)
        ]
    }

    private let smoother = LandmarkSmoother()
    private var peakROM: Float = 0
    private var activeSideAtPeak: BodySide
    private var romHysteresis = GradeHysteresis()

    init(side: BodySide = .left) {
        self.preferredSide = side
        self.activeSideAtPeak = side
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
        let shoulder = smoother.smooth(key: "\(activeSide)_shoulder", position: rawShoulder, timestamp: ts)
        let elbow    = smoother.smooth(key: "\(activeSide)_elbow",    position: rawElbow,    timestamp: ts)
        let wrist    = smoother.smooth(key: "\(activeSide)_wrist",    position: rawWrist,    timestamp: ts)
        let hip      = smoother.smooth(key: "\(activeSide)_hip",      position: rawHip,      timestamp: ts)
        let ear      = landmarks.position(for: .ear(activeSide))
            .map { smoother.smooth(key: "\(activeSide)_ear", position: $0, timestamp: ts) }

        let w_shoulder = landmarks.worldPosition(for: .shoulder(activeSide)).map { smoother.smooth3D(key: "\(activeSide)_shoulder", position: $0, timestamp: ts) }
        let w_wrist    = landmarks.worldPosition(for: .wrist(activeSide))   .map { smoother.smooth3D(key: "\(activeSide)_wrist",    position: $0, timestamp: ts) }
        let w_hip      = landmarks.worldPosition(for: .hip(activeSide))     .map { smoother.smooth3D(key: "\(activeSide)_hip",      position: $0, timestamp: ts) }

        // ROM = wrist → shoulder → hip angle. Larger means the arm is closer to
        // pointing straight up overhead (true shoulder flexion).
        let rom: Float
        if let ws = w_shoulder, let ww = w_wrist, let wh = w_hip {
            rom = AngleCalculator.angle3D(a: ww, b: ws, c: wh)
        } else {
            rom = AngleCalculator.angle(a: wrist, b: shoulder, c: hip)
        }

        if rom > peakROM {
            peakROM = rom
            activeSideAtPeak = activeSide
        }

        let frameGrade = gradeROM(rom)
        let displayedGrade = romHysteresis.update(frameGrade)
        let romColor = OverlayColor.romQuality(grade: displayedGrade)

        var instructions: [OverlayInstruction] = []

        // Spine reference behind the arm
        instructions.append(contentsOf: SpineOverlay.instructions(
            ear: ear, shoulder: shoulder, hip: hip))

        // Vertical reference at the shoulder so the arm-vs-vertical relationship
        // is visually obvious.
        let plumbTop    = SIMD2<Float>(shoulder.x, shoulder.y - 0.30)
        let plumbBottom = SIMD2<Float>(shoulder.x, shoulder.y + 0.05)
        instructions.append(.line(from: plumbTop, to: plumbBottom, color: .white, width: 1))

        // Arm skeleton (colored by ROM grade)
        instructions.append(.line(from: shoulder, to: elbow, color: romColor, width: 3))
        instructions.append(.line(from: elbow,    to: wrist, color: romColor, width: 3))

        // Joint markers
        instructions.append(.circle(at: shoulder, radius: 12, color: romColor, filled: true))
        instructions.append(.circle(at: elbow,    radius: 10, color: romColor, filled: true))
        instructions.append(.circle(at: wrist,    radius: 8,  color: romColor, filled: true))
        instructions.append(.circle(at: hip,      radius: 8,  color: .cyan,    filled: true))

        // Active-side label so the user can confirm the analyzer chose the
        // correct profile (especially after a side-fallback flip).
        instructions.append(.text(activeSide == .left ? "Left arm" : "Right arm",
            at: SIMD2(shoulder.x + 0.02, shoulder.y - 0.05), color: .white, size: 16))

        instructions.append(.text("\(AngleCalculator.displayDegrees(rom))\u{00B0}",
            at: SIMD2(elbow.x + 0.02, elbow.y), color: .white, size: 18))

        // HUD
        let overall = currentMetrics().grade
        instructions.append(.text(overall.rawValue,
            at: SIMD2(0.85, 0.05), color: OverlayColor.romQuality(grade: overall), size: 36))
        instructions.append(.text("ROM: \(AngleCalculator.displayDegrees(rom))\u{00B0}",
            at: SIMD2(0.02, 0.05), color: romColor, size: 20))
        instructions.append(.text("Peak: \(AngleCalculator.displayDegrees(peakROM))\u{00B0}",
            at: SIMD2(0.02, 0.11), color: .white, size: 18))

        return FrameAnalysis(
            angles: [JointAngle(joint: .shoulder, degrees: rom)],
            repCount: 0,
            repState: .extended,
            tempoPhase: nil,
            overlayInstructions: instructions
        )
    }

    func currentMetrics() -> AssessmentMetrics {
        let romGrade = gradeROM(peakROM)

        // For the sagittal-plane (single-arm) variant we report ROM in the
        // appropriate side slot so the result card surfaces it consistently
        // with the bilateral assessment.
        let leftROM:  Float? = activeSideAtPeak == .left  ? peakROM : nil
        let rightROM: Float? = activeSideAtPeak == .right ? peakROM : nil

        var details: [String] = []
        details.append("Peak ROM (\(activeSideAtPeak == .left ? "L" : "R") arm): \(AngleCalculator.displayDegrees(peakROM))° (\(romGrade.rawValue))")
        if activeSideAtPeak != preferredSide {
            details.append("Auto-switched to \(activeSideAtPeak == .left ? "L" : "R") side based on landmark visibility")
        }

        return AssessmentMetrics(
            grade: romGrade,
            subGrades: [("ROM (\(activeSideAtPeak == .left ? "Left" : "Right"))", romGrade)],
            leftROM: leftROM,
            rightROM: rightROM,
            asymmetryDeg: nil,
            asymmetryFlag: false,
            details: details
        )
    }

    func reset() {
        smoother.reset()
        peakROM = 0
        activeSideAtPeak = preferredSide
        romHysteresis = GradeHysteresis()
    }

    private func gradeROM(_ rom: Float) -> LetterGrade {
        LetterGrade.gradeHigherIsBetter(value: rom, a: 170, b: 150, c: 130, d: 110)
    }

    /// Choose the side with the highest mean visibility across the four key
    /// landmarks (shoulder/elbow/wrist/hip). Sticky toward `preferredSide` —
    /// only switch when the alternate side is meaningfully more visible.
    private func resolvedSide(for landmarks: PoseResult) -> BodySide {
        let preferredScore = visibilityScore(for: preferredSide, landmarks: landmarks)
        let alternateScore = visibilityScore(for: preferredSide.opposite, landmarks: landmarks)

        guard alternateScore > 0 else { return preferredSide }
        if preferredScore < minimumPreferredVisibility,
           alternateScore > preferredScore + visibilityFallbackMargin {
            return preferredSide.opposite
        }
        return preferredSide
    }

    private func visibilityScore(for side: BodySide, landmarks: PoseResult) -> Float {
        let relevant: [PoseLandmarkType] = [
            .shoulder(side), .elbow(side), .wrist(side), .hip(side)
        ]
        let total = relevant.reduce(Float.zero) { $0 + landmarks.visibility(for: $1) }
        return total / Float(relevant.count)
    }
}
