import Foundation
import simd

// MARK: - Assessment Types

enum AssessmentType: String, CaseIterable, Identifiable, Codable {
    case shoulderFlexion    = "Shoulder Flexion"
    case squatAssessment    = "Squat Assessment"
    case hipHingeAssessment = "Hip Hinge Assessment"

    var id: String { rawValue }
}

// MARK: - View Plane

/// Anatomical viewing plane for an assessment.
///
/// - `frontal`: camera placed in front of or behind the subject (frontal/coronal plane).
///   Best for bilateral comparisons like shoulder symmetry, knee valgus/varus, and
///   pelvic level.
/// - `sagittal`: strict 90° side profile (sagittal plane). Best for single-side joint
///   angles like squat depth, hinge angle, or shoulder flexion ROM where the limb
///   moves through the sagittal plane.
enum ViewPlane: String, CaseIterable, Identifiable, Codable {
    case frontal
    case sagittal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frontal:  return "Front/Back"
        case .sagittal: return "Side"
        }
    }
}

// MARK: - Letter Grade

enum LetterGrade: String, Codable, Comparable, CaseIterable {
    case A, B, C, D, F

    static func < (lhs: LetterGrade, rhs: LetterGrade) -> Bool {
        let order: [LetterGrade] = [.A, .B, .C, .D, .F]
        guard let li = order.firstIndex(of: lhs),
              let ri = order.firstIndex(of: rhs) else { return false }
        return li < ri
    }

    /// Grade a value where lower is better (e.g. knee angle for squat depth).
    /// Thresholds are inclusive upper bounds for each grade: A <= t0, B <= t1, etc.
    static func gradeLowerIsBetter(value: Float, a: Float, b: Float, c: Float, d: Float) -> LetterGrade {
        if value <= a { return .A }
        if value <= b { return .B }
        if value <= c { return .C }
        if value <= d { return .D }
        return .F
    }

    /// Grade a value where higher is better (e.g. ROM).
    /// Thresholds are inclusive lower bounds for each grade: A >= t0, B >= t1, etc.
    static func gradeHigherIsBetter(value: Float, a: Float, b: Float, c: Float, d: Float) -> LetterGrade {
        if value >= a { return .A }
        if value >= b { return .B }
        if value >= c { return .C }
        if value >= d { return .D }
        return .F
    }
}

// MARK: - Assessment Metrics

struct AssessmentMetrics {
    let grade: LetterGrade
    let subGrades: [(label: String, grade: LetterGrade)]
    let leftROM: Float?
    let rightROM: Float?
    let asymmetryDeg: Float?
    let asymmetryFlag: Bool
    let details: [String]
}

// MARK: - Assessment Analyzer Protocol

protocol AssessmentAnalyzer: FrameAnalyzerProtocol {
    var assessmentType: AssessmentType { get }
    func currentMetrics() -> AssessmentMetrics
}

// MARK: - Dynamic Color Helpers

extension OverlayColor {
    static func romQuality(grade: LetterGrade) -> OverlayColor {
        switch grade {
        case .A: return .green
        case .B: return .custom(r: 0.6, g: 1.0, b: 0.2, a: 1.0)
        case .C: return .yellow
        case .D: return .orange
        case .F: return .red
        }
    }
}

// MARK: - Grade Hysteresis

/// Stabilises a per-frame letter grade against transient frame-to-frame fluctuations
/// near a threshold boundary. A new grade only "takes hold" once it has been observed
/// for `threshold` consecutive frames.
///
/// Used by every `AssessmentAnalyzer` to prevent the colour-coded skeleton from
/// flickering between two adjacent grades during live preview / overlay rendering.
struct GradeHysteresis {
    private(set) var current: LetterGrade
    private var candidate: LetterGrade
    private var count: Int = 0
    let threshold: Int

    init(initial: LetterGrade = .F, threshold: Int = 5) {
        self.current = initial
        self.candidate = initial
        self.threshold = threshold
    }

    /// Feed the latest per-frame grade. Returns the currently displayed grade
    /// (which may lag the input by up to `threshold - 1` frames).
    @discardableResult
    mutating func update(_ newGrade: LetterGrade) -> LetterGrade {
        if newGrade == current {
            count = 0
            candidate = current
        } else if newGrade == candidate {
            count += 1
            if count >= threshold {
                current = newGrade
                count = 0
            }
        } else {
            candidate = newGrade
            count = 1
        }
        return current
    }
}

// MARK: - Assessment Camera Tips

extension AssessmentType {
    /// Plane-aware setup tip surfaced in the picker UI.
    func cameraSetupTip(for plane: ViewPlane) -> String {
        switch (self, plane) {
        case (.shoulderFlexion, .frontal):
            return "Film from in front or behind. Keep both shoulders, hips, and arms in frame. Raise both arms overhead slowly."
        case (.shoulderFlexion, .sagittal):
            return "Film from a strict side profile of the working arm. Keep the arm and torso fully in frame from hip to wrist. Raise the arm overhead slowly."
        case (.squatAssessment, .frontal):
            return "Film from directly behind (or in front). Keep both hips, knees, and ankles centred and visible. Perform a slow bodyweight squat."
        case (.squatAssessment, .sagittal):
            return "Film from a strict side profile (about 90°). Keep the working leg and torso fully visible from shoulder to ankle. Perform a slow bodyweight squat."
        case (.hipHingeAssessment, .frontal):
            return "Film from directly behind. Keep both shoulders, hips, knees, and ankles in frame. Perform a slow hip hinge."
        case (.hipHingeAssessment, .sagittal):
            return "Film from a strict side profile. Keep shoulder to ankle visible. Perform a slow hip hinge with straight arms."
        }
    }

    /// Plane-aware warning shown when pose tracking is persistently low quality.
    func lowTrackingWarning(for plane: ViewPlane) -> String {
        switch (self, plane) {
        case (.shoulderFlexion, .frontal):
            return "Tracking is unstable. Reposition to a strict front or back profile with both arms and hips clearly visible."
        case (.shoulderFlexion, .sagittal):
            return "Tracking is unstable. Reposition to a strict side profile with the working arm fully visible."
        case (.squatAssessment, .frontal):
            return "Tracking is unstable. Film from directly behind with both hips, knees, and ankles fully visible."
        case (.squatAssessment, .sagittal):
            return "Tracking is unstable. Reposition to a strict side profile with the working leg fully visible from shoulder to ankle."
        case (.hipHingeAssessment, .frontal):
            return "Tracking is unstable. Reposition to a strict rear profile with shoulders, hips, knees, and ankles fully visible."
        case (.hipHingeAssessment, .sagittal):
            return "Tracking is unstable. Reposition to a strict side profile with shoulder to ankle fully visible."
        }
    }
}
