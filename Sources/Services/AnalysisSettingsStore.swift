import Foundation

/// Persists the user's last-used Analyze configuration so the Analyze tab opens
/// where they left off instead of resetting to defaults every launch.
///
/// Intentionally lightweight (UserDefaults raw values) — no analysis state, just
/// the picker selections. Deep-link requests (`AppRouter.pendingRequest`) still
/// take precedence and overwrite these on appear.
enum AnalysisSettingsStore {

    private static let defaults = UserDefaults.standard

    private enum Key {
        static let category      = "kinetriq.analyze.category"
        static let exercise      = "kinetriq.analyze.exercise"
        static let assessment    = "kinetriq.analyze.assessment"
        static let plane         = "kinetriq.analyze.plane"
        static let side          = "kinetriq.analyze.side"
        static let overlayMode   = "kinetriq.analyze.overlayMode"
        static let customOverlays = "kinetriq.analyze.customOverlays"
    }

    /// Snapshot of every restorable Analyze selection.
    struct Snapshot {
        var category: AnalysisCategory
        var exercise: ExerciseType
        var assessment: AssessmentType
        var plane: ViewPlane
        var side: BodySide
        var overlayMode: OverlayMode
        var customOverlays: Set<CustomOverlayOption>
    }

    /// Loads the saved snapshot, falling back to the supplied defaults for any
    /// missing or invalid value so the UI always has a complete configuration.
    static func load(defaults fallback: Snapshot) -> Snapshot {
        var snapshot = fallback

        if let raw = defaults.string(forKey: Key.category),
           let value = AnalysisCategory(rawValue: raw) {
            snapshot.category = value
        }
        if let raw = defaults.string(forKey: Key.exercise),
           let value = ExerciseType(rawValue: raw) {
            snapshot.exercise = value
        }
        if let raw = defaults.string(forKey: Key.assessment),
           let value = AssessmentType(rawValue: raw) {
            snapshot.assessment = value
        }
        if let raw = defaults.string(forKey: Key.plane),
           let value = ViewPlane(rawValue: raw) {
            snapshot.plane = value
        }
        if let raw = defaults.string(forKey: Key.side),
           let value = BodySide(rawValue: raw) {
            snapshot.side = value
        }
        if let raw = defaults.string(forKey: Key.overlayMode),
           let value = OverlayMode(rawValue: raw) {
            snapshot.overlayMode = value
        }
        if let raws = defaults.array(forKey: Key.customOverlays) as? [String] {
            snapshot.customOverlays = Set(raws.compactMap(CustomOverlayOption.init(rawValue:)))
        }

        return snapshot
    }

    static func save(_ snapshot: Snapshot) {
        defaults.set(snapshot.category.rawValue, forKey: Key.category)
        defaults.set(snapshot.exercise.rawValue, forKey: Key.exercise)
        defaults.set(snapshot.assessment.rawValue, forKey: Key.assessment)
        defaults.set(snapshot.plane.rawValue, forKey: Key.plane)
        defaults.set(snapshot.side.rawValue, forKey: Key.side)
        defaults.set(snapshot.overlayMode.rawValue, forKey: Key.overlayMode)
        defaults.set(snapshot.customOverlays.map(\.rawValue), forKey: Key.customOverlays)
    }
}
