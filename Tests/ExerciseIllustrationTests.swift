import XCTest
@testable import Kinetriq

final class ExerciseIllustrationTests: XCTestCase {

    // MARK: - Catalog

    func testEveryExerciseExceptAssessmentsHasAnIllustration() {
        for type in ExerciseType.allCases where type != .shoulderAssessment {
            XCTAssertNotNil(ExerciseIllustration.forExercise(type),
                            "No illustration mapped for \(type.rawValue)")
        }
    }

    /// A barbell drawing would misrepresent a range-of-motion assessment.
    func testAssessmentsHaveNoIllustration() {
        XCTAssertNil(ExerciseIllustration.forExercise(.shoulderAssessment))
        XCTAssertNil(ExerciseIllustration.forFamily(.assessment))
    }

    func testEveryMovementFamilyExceptAssessmentHasAnIllustration() {
        let families: [MovementFamily] = [.squat, .hinge, .lunge, .horizontalPull,
                                          .verticalPull, .press, .dip, .curl]
        for family in families {
            XCTAssertNotNil(ExerciseIllustration.forFamily(family),
                            "No illustration mapped for \(family.rawValue)")
        }
    }

    func testBothHipHingeVariantsShareTheHingeIllustration() {
        XCTAssertEqual(ExerciseIllustration.forExercise(.hipHingeSide),
                       ExerciseIllustration.forExercise(.hipHingeBack))
    }

    func testCatalogEntriesAreUnique() {
        let ids = ExerciseIllustration.all.map(\.everkineticID)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate Everkinetic id in the catalog")
    }

    func testEveryMappedIllustrationIsListedInTheCredits() {
        let credited = Set(ExerciseIllustration.all.map(\.everkineticID))
        for type in ExerciseType.allCases {
            guard let illustration = ExerciseIllustration.forExercise(type) else { continue }
            XCTAssertTrue(credited.contains(illustration.everkineticID),
                          "\(illustration.title) is used but missing from the credits list")
        }
    }

    // MARK: - Attribution

    /// CC BY-SA needs title, author, license, and whether the work was modified.
    func testCreditLineCarriesEverythingTheLicenseRequires() {
        for illustration in ExerciseIllustration.all {
            let credit = illustration.creditLine
            XCTAssertTrue(credit.contains(illustration.title), credit)
            XCTAssertTrue(credit.contains("Everkinetic"), credit)
            XCTAssertTrue(credit.contains("CC BY-SA 4.0"), credit)
            XCTAssertTrue(credit.contains("unmodified"), credit)
        }
    }

    func testSourceURLsPointAtEverkinetic() {
        for illustration in ExerciseIllustration.all {
            XCTAssertEqual(illustration.sourceURL.host, "db.everkinetic.com")
        }
    }

    func testFileNamesFollowEverkineticsOwnNaming() {
        let squat = ExerciseIllustration.barbellSquat
        XCTAssertEqual(squat.startFileName, "0122-relaxation")
        XCTAssertEqual(squat.endFileName, "0122-tension")
    }

    // MARK: - Lesson attachment

    func testOnlyPositionFaultsCanCarryAnIllustration() {
        // Tempo and tracking faults have nothing a still image can show.
        XCTAssertFalse(TechniqueLesson.illustratableFaults.contains(.rushedEccentric))
        XCTAssertFalse(TechniqueLesson.illustratableFaults.contains(.acceleratingTempo))
        XCTAssertFalse(TechniqueLesson.illustratableFaults.contains(.lowTracking))
        XCTAssertFalse(TechniqueLesson.illustratableFaults.contains(.tooFewReps))

        XCTAssertTrue(TechniqueLesson.illustratableFaults.contains(.inconsistentDepth))
        XCTAssertTrue(TechniqueLesson.illustratableFaults.contains(.rangeBelowPersonalBest))
    }

    func testTempoLessonsNeverPickUpAnImage() {
        for family in [MovementFamily.squat, .hinge, .curl] {
            for fault in [MovementFault.rushedEccentric, .acceleratingTempo] {
                let lesson = TechniqueLibrary.lesson(for: fault, family: family)
                XCTAssertNil(lesson?.illustrationAsset,
                             "\(fault.rawValue)/\(family.rawValue) should stay text-only")
                XCTAssertNil(lesson?.attribution)
            }
        }
    }

    /// Also proves the illustrations are actually bundled. KinetriqTests is a hosted
    /// test bundle (`TEST_HOST` is the app), so `Bundle.main` is the app bundle and a
    /// missing folder reference in the generated project must fail here rather than skip
    /// — that stale-project case is exactly what this catches.
    func testPositionLessonsCarryAnImageAndItsCredit() throws {
        let lesson = try XCTUnwrap(TechniqueLibrary.lesson(for: .inconsistentDepth, family: .squat))

        XCTAssertEqual(lesson.illustrationAsset, ExerciseIllustration.barbellSquat.endFileName)
        // An image must never appear without its credit line.
        XCTAssertNotNil(lesson.attribution)
        XCTAssertTrue(try XCTUnwrap(lesson.attribution).contains("CC BY-SA 4.0"))
    }

    func testEveryBundledIllustrationLoadsBothFrames() throws {
        for illustration in ExerciseIllustration.all {
            XCTAssertNotNil(illustration.startImage, "\(illustration.everkineticID) start missing")
            XCTAssertNotNil(illustration.endImage, "\(illustration.everkineticID) end missing")
        }
    }

    func testTheLicenseTextShipsWithTheImages() throws {
        let text = try XCTUnwrap(ExerciseIllustration.licenseText)
        XCTAssertTrue(text.contains("Attribution-ShareAlike 4.0 International"))
    }
}
