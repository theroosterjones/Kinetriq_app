import SwiftUI

/// Curated, educational catalog of the movements Kinetriq can analyze.
///
/// This is reference/educational data only — it does not drive the analysis
/// pipeline (that still comes from `ExerciseConfig` / `AssessmentConfig`). It
/// powers the redesigned Exercise Library browsing experience and the Home
/// shortcuts. Items that map to a real analyzer expose `exerciseType` so the
/// library can deep-link straight into analysis with fewer taps.
enum ExerciseLibrary {

    enum Category: String, CaseIterable, Identifiable {
        case all = "All"
        case lower = "Lower Body"
        case upper = "Upper Body"
        case assessment = "Assessments"
        var id: String { rawValue }
    }

    struct Item: Identifiable {
        let id = UUID()
        let displayName: String
        let category: Category
        let plane: String          // camera setup, e.g. "Side view"
        let icon: String           // SF Symbol (fallback)
        /// Custom illustrated glyph asset name (template image). Falls back to `icon`.
        let glyph: String?
        let tint: Color
        let summary: String
        let cues: [String]
        /// If set, the library can launch analysis directly for this movement.
        let exerciseType: ExerciseType?
        let assessmentType: AssessmentType?

        init(_ displayName: String,
             category: Category,
             plane: String,
             icon: String,
             glyph: String? = nil,
             tint: Color,
             summary: String,
             cues: [String],
             exerciseType: ExerciseType? = nil,
             assessmentType: AssessmentType? = nil) {
            self.displayName = displayName
            self.category = category
            self.plane = plane
            self.icon = icon
            self.glyph = glyph
            self.tint = tint
            self.summary = summary
            self.cues = cues
            self.exerciseType = exerciseType
            self.assessmentType = assessmentType
        }
    }

    static let all: [Item] = [
        Item("Squat", category: .lower, plane: "Side view", icon: "figure.strengthtraining.functional",
             glyph: "GlyphSquat",
             tint: KColor.accent,
             summary: "Tracks hip and knee angles to measure depth, tempo, and control through the squat pattern.",
             cues: ["Strict 90° side profile", "Full body shoulder-to-ankle in frame", "Even tempo on the way down"],
             exerciseType: .squat),
        Item("Deadlift", category: .lower, plane: "15–30° off side", icon: "figure.strengthtraining.traditional",
             glyph: "GlyphDeadlift",
             tint: KColor.accent,
             summary: "Measures the hip hinge and bar path. Film slightly off-side so the barbell doesn't hide the hip.",
             cues: ["Film 15–30° off true side", "Keep shoulder, hip, knee, ankle visible", "Neutral spine through the pull"],
             exerciseType: .deadlift),
        Item("Lunge", category: .lower, plane: "Side view", icon: "figure.walk",
             glyph: "GlyphLunge",
             tint: KColor.accent,
             summary: "Evaluates front-leg knee tracking and depth for split-stance patterns.",
             cues: ["Side profile of the working leg", "Knee tracks over the foot", "Controlled descent"],
             exerciseType: .lunge),
        Item("Hip Hinge (Side)", category: .lower, plane: "Side view", icon: "figure.cooldown",
             glyph: "GlyphHipHinge",
             tint: KColor.accent,
             summary: "Isolates the hinge to coach hip dominance and a neutral spine.",
             cues: ["Strict side profile", "Hips back, not down", "Flat back throughout"],
             exerciseType: .hipHingeSide),
        Item("Hip Hinge (Back)", category: .lower, plane: "Rear view", icon: "figure.stand",
             glyph: "GlyphHipHinge",
             tint: KColor.accent,
             summary: "Self-calibrating rear-view hinge analysis for symmetry and depth.",
             cues: ["Film directly behind", "Both hips, knees, ankles visible", "Stand centred in frame"],
             exerciseType: .hipHingeBack),
        Item("Row", category: .upper, plane: "Side view", icon: "figure.rower",
             glyph: "GlyphRow",
             tint: KColor.teal,
             summary: "Tracks the pulling elbow path and torso stability for rowing variations.",
             cues: ["Side profile", "Drive the elbow back", "Keep torso still"],
             exerciseType: .row),
        Item("Dips", category: .upper, plane: "Side view", icon: "figure.play",
             glyph: "GlyphDips",
             tint: KColor.teal,
             summary: "Measures elbow and shoulder angles to coach depth and shoulder safety.",
             cues: ["Strict side profile", "Wrist-to-ankle visible", "Controlled depth"],
             exerciseType: .dips),
        Item("Lat Pulldown / Chin Up (Side)", category: .upper, plane: "Side view", icon: "figure.climbing",
             glyph: "GlyphLatPulldown",
             tint: KColor.teal,
             summary: "Side-view pulldown analysis for range of motion and tempo.",
             cues: ["Side profile", "Full range to the chest", "Smooth eccentric"],
             exerciseType: .latPulldown),
        Item("Lat Pulldown / Chin Up (Front)", category: .upper, plane: "Front / rear view", icon: "figure.climbing",
             glyph: "GlyphLatPulldown",
             tint: KColor.teal,
             summary: "Bilateral front view to compare left and right pulling symmetry.",
             cues: ["Film straight on", "Both arms and hips visible", "Even pull on both sides"],
             exerciseType: .latPulldownFront),
        Item("Overhead Press", category: .upper, plane: "Front / rear view", icon: "figure.arms.open",
             glyph: "GlyphOverheadPress",
             tint: KColor.teal,
             summary: "Bilateral overhead pressing analysis for symmetry and lockout.",
             cues: ["Front or back profile", "Both arms in frame", "Full lockout overhead"],
             exerciseType: .overheadPress),
        Item("Elbow (Bicep / Tricep)", category: .upper, plane: "Side view", icon: "dumbbell.fill",
             glyph: "GlyphCurl",
             tint: KColor.teal,
             summary: "Isolation tracking of elbow flexion and extension with tempo.",
             cues: ["Side profile of the arm", "Full range each rep", "Keep the elbow steady"],
             exerciseType: .elbowCurl),
        Item("Shoulder Flexion", category: .assessment, plane: "Front & side", icon: "figure.flexibility",
             glyph: "GlyphShoulder",
             tint: KColor.violet,
             summary: "Letter-graded overhead mobility assessment with left/right comparison.",
             cues: ["Strict front or side profile", "Shoulders and hips level", "Reach as high as comfortable"],
             assessmentType: .shoulderFlexion),
        Item("Squat Assessment", category: .assessment, plane: "Front & side", icon: "figure.strengthtraining.functional",
             glyph: "GlyphSquat",
             tint: KColor.violet,
             summary: "Depth-aware screen grading squat mechanics, lean, and symmetry.",
             cues: ["Front or side profile", "Full body in frame", "Move at a natural pace"],
             assessmentType: .squatAssessment),
        Item("Hip Hinge Assessment", category: .assessment, plane: "Front & side", icon: "figure.cooldown",
             glyph: "GlyphHipHinge",
             tint: KColor.violet,
             summary: "Grades hinge quality, control, and side-to-side balance.",
             cues: ["Front or side profile", "Hips back", "Neutral spine"],
             assessmentType: .hipHingeAssessment),
    ]

    static var featured: [Item] {
        [all[0], all[1], all[11], all[5], all[9]]
    }

    static func filtered(category: Category, query: String) -> [Item] {
        all.filter { item in
            (category == .all || item.category == category) &&
            (query.isEmpty || item.displayName.localizedCaseInsensitiveContains(query)
                || item.summary.localizedCaseInsensitiveContains(query))
        }
    }
}
