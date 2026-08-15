import SwiftUI

/// Lightweight cross-tab navigation router so the Home dashboard and Exercise
/// Library can jump straight into the Workout flow (fewer taps to analyze).
final class AppRouter: ObservableObject {
    enum Tab: Hashable { case home, workout, history, settings }

    @Published var selectedTab: Tab = .home

    /// When set, the Workout screen consumes this on appear to preselect mode
    /// and (optionally) a specific exercise / assessment.
    @Published var pendingRequest: WorkoutRequest?

    struct WorkoutRequest: Equatable {
        enum Mode: Equatable { case savedVideo, liveCamera }
        var mode: Mode = .savedVideo
        var category: AnalysisCategory = .exercise
        var exercise: ExerciseType?
        var assessment: AssessmentType?
    }

    enum WorkoutLaunchMode { case savedVideo, liveCamera, assessment }

    func goToWorkout(_ mode: WorkoutLaunchMode = .savedVideo) {
        switch mode {
        case .savedVideo:
            pendingRequest = WorkoutRequest(mode: .savedVideo, category: .exercise)
        case .liveCamera:
            pendingRequest = WorkoutRequest(mode: .liveCamera, category: .exercise)
        case .assessment:
            pendingRequest = WorkoutRequest(mode: .savedVideo, category: .assessment)
        }
        selectedTab = .workout
    }

    func analyze(exercise: ExerciseType) {
        pendingRequest = WorkoutRequest(mode: .savedVideo, category: .exercise, exercise: exercise)
        selectedTab = .workout
    }

    func analyze(assessment: AssessmentType) {
        pendingRequest = WorkoutRequest(mode: .savedVideo, category: .assessment, assessment: assessment)
        selectedTab = .workout
    }
}
