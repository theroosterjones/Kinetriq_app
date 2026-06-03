import Foundation
import RevenueCat
import StoreKit

/// Central subscription service wrapping RevenueCat.
///
/// Setup checklist (one-time, before shipping):
///   1. Create a free account at https://app.revenuecat.com
///   2. Add your iOS app (bundle ID: com.kevinjones.KevLines2-0)
///   3. Create one entitlement named/identified "Kinetriq Pro"
///   4. Create two subscription products in App Store Connect:
///        • monthly — 7-day free trial
///        • yearly  — 7-day free trial
///   5. Attach both products to the "Kinetriq Pro" entitlement in RevenueCat
///
/// Promo codes:
///   Add codes to `validPromoCodes`. Codes are stored in the app binary —
///   suitable for trainers, testers, and press; rotate codes via an app update
///   if you ever need to revoke access.
@MainActor
final class PurchaseService: ObservableObject {

    static let shared = PurchaseService()

    // MARK: - Published state

    @Published var isProUser: Bool = false
    @Published var customerInfo: CustomerInfo? = nil
    @Published var offerings: Offerings? = nil
    @Published var isLoading: Bool = true
    @Published var purchaseError: String? = nil

    // MARK: - Constants

    /// Primary RevenueCat entitlement identifier. Must match the RevenueCat dashboard.
    static let entitlementID = "Kinetriq Pro"

    /// Backward-compatible accepted entitlement identifiers while the dashboard setup is being finalized.
    private static let acceptedEntitlementIDs = ["Kinetriq Pro", "pro"]

    static let monthlyProductID = "monthly"
    static let yearlyProductID = "yearly"

    /// RevenueCat public SDK API key for the Kinetriq project.
    static let apiKey = "test_XThbuzBuYTjDTmgSbflRaPedBiT"
    private static let placeholderAPIKey = "REVENUECAT_API_KEY_HERE"

    // MARK: - Promo codes

    /// Hardcoded promo codes granting unlimited free access.
    /// Update this list via app update when you need to add or rotate codes.
    private static let validPromoCodes: Set<String> = [
        "KINETRIQ-TRAINER",
        "KINETRIQ-BETA",
        "KINETRIQ-PRESS"
    ]

    private let promoCodeKey = "kinetriq_redeemed_promo"
    private var isRevenueCatConfigured = false

    // MARK: - Init

    private init() {}

    var hasConfiguredAPIKey: Bool {
        Self.apiKey != Self.placeholderAPIKey
    }

    // MARK: - Configuration

    func configure() {
        guard hasConfiguredAPIKey else {
            // Development mode until a real RevenueCat key is provided.
            isProUser = true
            isLoading = false
            return
        }

        guard !isRevenueCatConfigured else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Self.apiKey)
        isRevenueCatConfigured = true
        Task { await refreshStatus() }
    }

    // MARK: - Status refresh

    func refreshStatus() async {
        isLoading = true
        defer { isLoading = false }

        // Promo code bypass takes precedence over RC subscription check
        if hasRedeemedPromoCode() {
            isProUser = true
            return
        }

        guard hasConfiguredAPIKey else {
            // No API key yet — treat as unlocked so the app is testable during development
            isProUser = true
            return
        }

        do {
            let info = try await Purchases.shared.customerInfo()
            updateSubscriptionStatus(from: info)
        } catch {
            // Network unavailable — keep previous state rather than locking the user out
            isProUser = false
        }
    }

    // MARK: - Offerings (loads App Store products + pricing)

    func fetchOfferings() async {
        guard hasConfiguredAPIKey else { return }
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            purchaseError = "Could not load subscription options. Check your connection and try again."
        }
    }

    // MARK: - Purchase

    func purchase(_ package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        updateSubscriptionStatus(from: result.customerInfo)
    }

    // MARK: - Restore

    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        updateSubscriptionStatus(from: info)
        if !isProUser {
            throw RestoreError.noPurchasesFound
        }
    }

    func updateSubscriptionStatus(from info: CustomerInfo) {
        customerInfo = info
        isProUser = Self.acceptedEntitlementIDs.contains { entitlementID in
            info.entitlements[entitlementID]?.isActive == true
        }
    }

    enum RestoreError: LocalizedError {
        case noPurchasesFound
        var errorDescription: String? {
            "No previous purchases found for this Apple ID."
        }
    }

    // MARK: - Promo codes

    /// Returns true and unlocks the app if `code` is in the valid set.
    @discardableResult
    func redeemPromoCode(_ code: String) -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Self.validPromoCodes.contains(normalized) else { return false }
        UserDefaults.standard.set(normalized, forKey: promoCodeKey)
        isProUser = true
        return true
    }

    func hasRedeemedPromoCode() -> Bool {
        guard let stored = UserDefaults.standard.string(forKey: promoCodeKey) else { return false }
        return Self.validPromoCodes.contains(stored)
    }

    func redeemedPromoCode() -> String? {
        UserDefaults.standard.string(forKey: promoCodeKey)
    }

    // MARK: - App Store offer codes

    /// Presents Apple's native offer-code redemption sheet.
    ///
    /// Use this for real App Store subscription offer codes configured in
    /// App Store Connect. RevenueCat will reflect the resulting entitlement
    /// after the App Store processes the redemption.
    func presentAppStoreOfferCodeRedemption() {
        SKPaymentQueue.default().presentCodeRedemptionSheet()
    }
}
