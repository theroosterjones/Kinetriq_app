import XCTest
@testable import Kinetriq

final class CoachTriageTests: XCTestCase {

    private func client(
        name: String,
        daysSinceSession: Int? = 1,
        latestScore: Int? = 80,
        previousScore: Int? = 80,
        asymmetry: Bool = false
    ) -> CoachClient {
        CoachClient(
            clientUserID: name.lowercased(),
            displayName: name,
            status: "active",
            linkedAt: Date().addingTimeInterval(-90 * 86_400),
            lastSessionAt: daysSinceSession.map { Date().addingTimeInterval(-Double($0) * 86_400 - 60) },
            sessionsLast14Days: daysSinceSession == nil ? 0 : 3,
            latestScore: latestScore,
            previousScore: previousScore,
            latestMovement: "Squat",
            openAsymmetryFlag: asymmetry
        )
    }

    // MARK: - Reasons

    func testClientWithNoSessionsNeverStarted() {
        XCTAssertEqual(CoachTriage.reason(for: client(name: "Ada", daysSinceSession: nil)),
                       .neverStarted)
    }

    func testLongSilenceOutranksEverythingElse() {
        let quiet = client(name: "Ada", daysSinceSession: 21, latestScore: 60, previousScore: 80)
        XCTAssertEqual(CoachTriage.reason(for: quiet), .wentQuiet(days: 21))
    }

    func testFallingScoreIsFlagged() {
        let slipping = client(name: "Ada", latestScore: 68, previousScore: 80)
        XCTAssertEqual(CoachTriage.reason(for: slipping), .scoreDropping(points: 12))
    }

    func testSmallScoreDipIsTreatedAsNoise() {
        let jittery = client(name: "Ada", latestScore: 78, previousScore: 80)
        XCTAssertEqual(CoachTriage.reason(for: jittery), .steady)
    }

    func testAsymmetryFlagSurfacesWhenTheScoreIsFine() {
        let flagged = client(name: "Ada", asymmetry: true)
        XCTAssertEqual(CoachTriage.reason(for: flagged), .newAsymmetry)
    }

    func testImprovementIsReported() {
        XCTAssertEqual(CoachTriage.reason(for: client(name: "Ada", latestScore: 90, previousScore: 80)),
                       .improving(points: 10))
    }

    func testASingleSessionHasNothingToCompareAndReadsAsSteady() {
        let firstTimer = client(name: "Ada", latestScore: 72, previousScore: nil)
        XCTAssertEqual(CoachTriage.reason(for: firstTimer), .steady)
    }

    // MARK: - Attention

    func testOnlyProblemsCountAsNeedingAttention() {
        let roster = [
            client(name: "Quiet", daysSinceSession: 30),
            client(name: "Slipping", latestScore: 60, previousScore: 80),
            client(name: "Fine"),
            client(name: "Improving", latestScore: 92, previousScore: 80)
        ]

        let names = CoachTriage.needingAttention(roster).map(\.displayName)
        XCTAssertEqual(Set(names), ["Quiet", "Slipping"])
    }

    // MARK: - Ordering

    func testRosterLeadsWithTheWorstProblems() {
        let roster = [
            client(name: "Fine"),
            client(name: "Improving", latestScore: 92, previousScore: 80),
            client(name: "Slipping", latestScore: 60, previousScore: 80),
            client(name: "Quiet", daysSinceSession: 30),
            client(name: "NeverStarted", daysSinceSession: nil)
        ]

        let order = CoachTriage.sorted(roster).map(\.displayName)
        XCTAssertEqual(order, ["NeverStarted", "Quiet", "Slipping", "Improving", "Fine"])
    }

    func testQuietestClientComesFirstWithinItsBucket() {
        let roster = [
            client(name: "TwoWeeks", daysSinceSession: 14),
            client(name: "TwoMonths", daysSinceSession: 60),
            client(name: "TwelveDays", daysSinceSession: 12)
        ]

        XCTAssertEqual(CoachTriage.sorted(roster).map(\.displayName),
                       ["TwoMonths", "TwoWeeks", "TwelveDays"])
    }

    func testBiggestScoreDropComesFirstWithinItsBucket() {
        let roster = [
            client(name: "Small", latestScore: 74, previousScore: 80),
            client(name: "Large", latestScore: 50, previousScore: 80)
        ]

        XCTAssertEqual(CoachTriage.sorted(roster).map(\.displayName), ["Large", "Small"])
    }

    /// Equal severity must not reshuffle between refreshes.
    func testEqualSeverityFallsBackToAStableAlphabeticalOrder() {
        let roster = [client(name: "Zoe"), client(name: "Adam"), client(name: "Mia")]

        XCTAssertEqual(CoachTriage.sorted(roster).map(\.displayName), ["Adam", "Mia", "Zoe"])
        XCTAssertEqual(CoachTriage.sorted(roster.reversed()).map(\.displayName),
                       ["Adam", "Mia", "Zoe"])
    }

    func testQuietThresholdMatchesTheDocumentedBoundary() {
        let justInside = client(name: "Ada", daysSinceSession: CoachTriage.quietThresholdDays)
        let justOutside = client(name: "Ada", daysSinceSession: CoachTriage.quietThresholdDays - 1)

        XCTAssertEqual(CoachTriage.reason(for: justInside),
                       .wentQuiet(days: CoachTriage.quietThresholdDays))
        XCTAssertEqual(CoachTriage.reason(for: justOutside), .steady)
    }
}
