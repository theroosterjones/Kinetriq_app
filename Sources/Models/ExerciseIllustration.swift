import Foundation
import UIKit

/// Everkinetic exercise illustrations, bundled **unmodified** under CC BY-SA 4.0.
///
/// Share-alike attaches to adaptations, so these files ship byte-for-byte as
/// published and are never recoloured, cropped, composited, or drawn over. That
/// constraint is the reason they live in a top-level `Resources/Everkinetic` folder
/// reference rather than an asset catalog: Xcode would compile an asset catalog into
/// its own container format, and keeping the originals as loose files makes it
/// obvious at a glance that nothing was touched. `docs/ContentLibrary.md` has the
/// licensing reasoning.
///
/// If you ever need a different size or crop, that is a new illustration, not an
/// edit of one of these — commission it or license it.
struct ExerciseIllustration: Equatable, Identifiable {

    /// Everkinetic's own numeric id, which is also the file-name stem.
    let everkineticID: String
    /// Everkinetic's title for the exercise, used verbatim in the credit line.
    let title: String
    let sourceURL: URL

    var id: String { everkineticID }

    /// Start position — Everkinetic's "relaxation" frame.
    var startFileName: String { "\(everkineticID)-relaxation" }
    /// End position — Everkinetic's "tension" frame.
    var endFileName: String { "\(everkineticID)-tension" }

    /// The full TASL credit: title, author, source, license, and the statement that
    /// the work is unmodified. Rendered wherever the images appear, not buried in a
    /// settings screen — CC BY-SA requires attribution to be reasonably visible.
    var creditLine: String {
        "\"\(title)\" by Everkinetic, CC BY-SA 4.0 — unmodified"
    }

    // MARK: - Loading

    /// Bundle subdirectory created by the `Resources/Everkinetic` folder reference in
    /// `project.yml`. A folder reference keeps the files as-is rather than flattening
    /// them into the bundle root.
    private static let subdirectory = "Everkinetic"

    static func image(named fileName: String) -> UIImage? {
        guard let url = Bundle.main.url(
            forResource: fileName,
            withExtension: "png",
            subdirectory: subdirectory
        ) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    var startImage: UIImage? { Self.image(named: startFileName) }
    var endImage: UIImage? { Self.image(named: endFileName) }

    /// True when the bundle actually carries both frames, so callers can hide the
    /// illustration UI entirely rather than rendering an empty frame.
    var isAvailable: Bool { startImage != nil && endImage != nil }

    /// The bundled copy of the CC BY-SA 4.0 deed, shipped alongside the images
    /// because the license requires including it or linking to it.
    static var licenseURL: URL? {
        Bundle.main.url(forResource: "LICENSE", withExtension: "md", subdirectory: subdirectory)
    }

    static var licenseText: String? {
        guard let licenseURL else { return nil }
        return try? String(contentsOf: licenseURL, encoding: .utf8)
    }
}

// MARK: - Catalog

extension ExerciseIllustration {

    private static func make(_ id: String, _ title: String, _ slug: String) -> ExerciseIllustration {
        ExerciseIllustration(
            everkineticID: id,
            title: title,
            sourceURL: URL(string: "http://db.everkinetic.com/exercise/\(slug)")!
        )
    }

    static let barbellSquat        = make("0122", "Barbell Squat", "barbell-squat")
    static let barbellDeadlift     = make("0099", "Barbell Dead Lifts", "barbell-dead-lifts")
    static let romanianDeadlift    = make("0118", "Romanian Dead Lift", "romanian-dead-lift")
    static let barbellLunges       = make("0114", "Barbell Lunges", "barbell-lunges")
    static let seatedCableRows     = make("0025", "Seated Cable Rows", "seated-cable-rows")
    static let vBarPullDown        = make("0096", "V Bar Pull Down", "v-bar-pull-down")
    static let seatedMilitaryPress = make("0004", "Seated Military Press", "seated-military-press")
    static let tricepDips          = make("0171", "Tricep Dips using Machine", "tricep-dips")
    static let bicepsCurls         = make("0211", "Biceps Curls with Barbell", "biceps-curls-with-barbell")

    static let all: [ExerciseIllustration] = [
        barbellSquat, barbellDeadlift, romanianDeadlift, barbellLunges,
        seatedCableRows, vBarPullDown, seatedMilitaryPress, tricepDips, bicepsCurls
    ]

    /// The nearest Everkinetic illustration for a Kinetriq exercise.
    ///
    /// Deliberately approximate. Everkinetic has no "hip hinge" drawing, so the
    /// Romanian deadlift stands in for the pattern, and a seated cable row stands in
    /// for the row Kinetriq films from the side. These are reference images for the
    /// movement pattern, not depictions of the exact setup a user is filming.
    static func forExercise(_ type: ExerciseType) -> ExerciseIllustration? {
        switch type {
        case .squat:                        return barbellSquat
        case .deadlift:                     return barbellDeadlift
        case .hipHingeSide, .hipHingeBack:  return romanianDeadlift
        case .lunge:                        return barbellLunges
        case .row:                          return seatedCableRows
        case .latPulldown, .latPulldownFront: return vBarPullDown
        case .overheadPress:                return seatedMilitaryPress
        case .dips:                         return tricepDips
        case .elbowCurl:                    return bicepsCurls
        // Assessments measure range of motion, not a loaded lift. A barbell drawing
        // would misrepresent what the user is being asked to do.
        case .shoulderAssessment:           return nil
        }
    }

    static func forFamily(_ family: MovementFamily) -> ExerciseIllustration? {
        switch family {
        case .squat:          return barbellSquat
        case .hinge:          return romanianDeadlift
        case .lunge:          return barbellLunges
        case .horizontalPull: return seatedCableRows
        case .verticalPull:   return vBarPullDown
        case .press:          return seatedMilitaryPress
        case .dip:            return tricepDips
        case .curl:           return bicepsCurls
        case .assessment:     return nil
        }
    }
}
