import Foundation

/// Configuration for each exercise type, centralizing thresholds and landmark requirements.
struct ExerciseConfig {
    let type: ExerciseType
    let displayName: String
    let requiresSideSelection: Bool
    let defaultSide: BodySide

    /// Create the appropriate analyzer for this exercise.
    func makeAnalyzer(side: BodySide) -> ExerciseAnalyzer {
        switch type {
        case .squat:              return SquatAnalyzer(side: side)
        case .deadlift:           return DeadliftAnalyzer(side: side)
        case .lunge:              return LungeAnalyzer(side: side)
        case .hipHingeSide:       return HipHingeSideAnalyzer(side: side)
        case .hipHingeBack:       return HipHingeBackAnalyzer(side: side)
        case .row:                return RowAnalyzer(side: side)
        case .latPulldown:        return LatPulldownAnalyzer(side: side)
        case .latPulldownFront:   return LatPulldownFrontAnalyzer(side: side)
        case .overheadPress:      return OverheadPressAnalyzer(side: side)
        case .elbowCurl:          return ElbowAnalyzer(side: side)
        case .shoulderAssessment: return ShoulderAnalyzer(side: side)
        }
    }

    static let all: [ExerciseConfig] = [
        ExerciseConfig(type: .squat,              displayName: "Squat",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .deadlift,           displayName: "Deadlift",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .lunge,              displayName: "Lunge",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .hipHingeSide,       displayName: "Hip Hinge (Side)",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .hipHingeBack,       displayName: "Hip Hinge (Back)",
                       requiresSideSelection: false, defaultSide: .left),
        ExerciseConfig(type: .row,                displayName: "Barbell Row",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .latPulldown,        displayName: "Lat Pulldown/Chin Up (Side)",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .latPulldownFront,   displayName: "Lat Pulldown/Chin Up (Front)",
                       requiresSideSelection: false, defaultSide: .left),
        ExerciseConfig(type: .overheadPress,      displayName: "Overhead Press",
                       requiresSideSelection: false, defaultSide: .left),
        ExerciseConfig(type: .elbowCurl,          displayName: "Elbow (Bicep/Tricep)",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .shoulderAssessment, displayName: "Shoulder Assessment",
                       requiresSideSelection: false, defaultSide: .left),
    ]
}

// MARK: - Analysis Category

enum AnalysisCategory: String, CaseIterable {
    case exercise = "Exercises"
    case assessment = "Assessments"
}

// MARK: - Assessment Configuration

struct AssessmentConfig {
    let type: AssessmentType
    let displayName: String
    /// Planes (front/back vs side) supported by this assessment, in display order.
    let supportedPlanes: [ViewPlane]
    /// The plane chosen by default when the user first selects this assessment.
    let defaultPlane: ViewPlane
    let defaultSide: BodySide

    /// Sagittal-plane variants always need a side; frontal-plane bilateral variants
    /// look at both sides simultaneously and don't.
    func requiresSideSelection(plane: ViewPlane) -> Bool {
        plane == .sagittal
    }

    func makeAnalyzer(side: BodySide, plane: ViewPlane) -> AssessmentAnalyzer {
        switch (type, plane) {
        case (.shoulderFlexion, .frontal):
            return ShoulderFlexionAssessment()
        case (.shoulderFlexion, .sagittal):
            return ShoulderFlexionSagittalAssessment(side: side)
        case (.squatAssessment, .frontal):
            return SquatAssessmentAnalyzer()
        case (.squatAssessment, .sagittal):
            return SquatSagittalAssessment(side: side)
        case (.hipHingeAssessment, .frontal):
            return HipHingeFrontalAssessment()
        case (.hipHingeAssessment, .sagittal):
            return HipHingeAssessmentAnalyzer(side: side)
        }
    }

    static let all: [AssessmentConfig] = [
        AssessmentConfig(
            type: .shoulderFlexion, displayName: "Shoulder Flexion",
            supportedPlanes: [.frontal, .sagittal], defaultPlane: .frontal,
            defaultSide: .left
        ),
        AssessmentConfig(
            type: .squatAssessment, displayName: "Squat Assessment",
            supportedPlanes: [.frontal, .sagittal], defaultPlane: .frontal,
            defaultSide: .left
        ),
        AssessmentConfig(
            type: .hipHingeAssessment, displayName: "Hip Hinge Assessment",
            supportedPlanes: [.frontal, .sagittal], defaultPlane: .sagittal,
            defaultSide: .left
        ),
    ]
}

// MARK: - Camera Setup Guidance

extension ExerciseType {
    /// Short setup guidance shown before analysis starts.
    var cameraSetupTip: String {
        switch self {
        case .squat, .lunge, .hipHingeSide:
            return "Use a strict side profile (about 90°). Keep the full working side visible from shoulder to ankle."
        case .deadlift:
            return "Film at a slight forward angle (15–30° off true side) so the barbell doesn't block your hip. Keep shoulder, hip, knee, and ankle all visible."
        case .row, .latPulldown, .elbowCurl:
            return "Use a strict side profile (about 90°). Keep the full working side visible from shoulder to ankle."
        case .latPulldownFront:
            return "Film from directly in front of or behind the cable stack / pull-up bar. Keep both arms and both hips fully visible throughout the set."
        case .overheadPress:
            return "Use a front or back profile. Keep both arms and hips fully visible in frame throughout the lift."
        case .hipHingeBack:
            return "Film from directly behind. Keep both hips, knees, and ankles fully visible. Stand centred in frame."
        case .shoulderAssessment:
            return "Use a strict front or back profile. Keep both shoulders and both hips fully visible and level in frame."
        }
    }

    /// Non-blocking warning shown when pose tracking quality is persistently low.
    var lowTrackingWarning: String {
        switch self {
        case .squat, .lunge, .hipHingeSide:
            return "Tracking is unstable. Reposition camera to a strict side profile and keep your full body in frame."
        case .deadlift:
            return "Tracking lost — the barbell may be blocking your hip. Try a slight forward angle (15–30° off the side) and ensure shoulder, hip, knee, and ankle are all visible."
        case .row, .latPulldown, .elbowCurl:
            return "Tracking is unstable. Reposition camera to a strict side profile and keep your full body in frame."
        case .latPulldownFront:
            return "Tracking is unstable. Film from directly in front of or behind the bar and ensure both arms and hips stay within the camera frame."
        case .overheadPress:
            return "Tracking is unstable. Use a front or back profile and ensure both arms stay within the camera frame."
        case .hipHingeBack:
            return "Tracking is unstable. Film from directly behind with hips, knees, and ankles all visible."
        case .shoulderAssessment:
            return "Tracking is unstable. Use a strict front/back profile with both shoulders and hips clearly visible."
        }
    }
}
