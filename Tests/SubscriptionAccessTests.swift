import XCTest
@testable import Kinetriq

final class SubscriptionAccessTests: XCTestCase {

    func testRevenueCatEntitlementGrantsAccess() {
        let state = SubscriptionAccessState(
            hasRevenueCatEntitlement: true,
            developmentUnlocked: false
        )

        XCTAssertTrue(state.hasProAccess)
    }

    func testNoEntitlementDoesNotGrantAccessInRelease() {
        let state = SubscriptionAccessState(
            hasRevenueCatEntitlement: false,
            developmentUnlocked: false
        )

        XCTAssertFalse(state.hasProAccess)
    }

    func testDevelopmentUnlockOnlyAppliesInDebugBuilds() {
        let state = SubscriptionAccessState(
            hasRevenueCatEntitlement: false,
            developmentUnlocked: true
        )

        #if DEBUG
        XCTAssertTrue(state.hasProAccess, "Development unlock should grant access in DEBUG builds only.")
        #else
        XCTAssertFalse(state.hasProAccess, "Development unlock must never grant access in Release builds.")
        #endif
    }
}
