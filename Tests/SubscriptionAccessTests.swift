import XCTest
@testable import Kinetriq

final class SubscriptionAccessTests: XCTestCase {

    func testRevenueCatEntitlementGrantsAccess() {
        let state = SubscriptionAccessState(
            hasRevenueCatEntitlement: true,
            backendEntitlement: nil,
            developmentUnlocked: false
        )

        XCTAssertTrue(state.hasProAccess)
    }

    func testActiveBackendEntitlementGrantsAccess() {
        let entitlement = AccountEntitlement(
            entitlement: "kinetriq_pro",
            source: .manualComp,
            startsAt: Date().addingTimeInterval(-60),
            expiresAt: nil,
            active: true
        )
        let state = SubscriptionAccessState(
            hasRevenueCatEntitlement: false,
            backendEntitlement: entitlement,
            developmentUnlocked: false
        )

        XCTAssertTrue(state.hasProAccess)
    }

    func testExpiredBackendEntitlementDoesNotGrantAccess() {
        let entitlement = AccountEntitlement(
            entitlement: "kinetriq_pro",
            source: .promoFreeMonth,
            startsAt: Date().addingTimeInterval(-60 * 60 * 24 * 40),
            expiresAt: Date().addingTimeInterval(-60),
            active: true
        )
        let state = SubscriptionAccessState(
            hasRevenueCatEntitlement: false,
            backendEntitlement: entitlement,
            developmentUnlocked: false
        )

        XCTAssertFalse(state.hasProAccess)
    }

    func testDevelopmentUnlockGrantsAccessWithoutConfiguredBilling() {
        let state = SubscriptionAccessState(
            hasRevenueCatEntitlement: false,
            backendEntitlement: nil,
            developmentUnlocked: true
        )

        XCTAssertTrue(state.hasProAccess)
    }
}
