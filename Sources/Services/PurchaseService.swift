import Foundation
import RevenueCat

/// Central subscription service wrapping RevenueCat.
///
/// Setup checklist (one-time, before shipping):
///   1. Create a free account at https://app.revenuecat.com
///   2. Add your iOS app (bundle ID: com.kevinjones.KevLines2-0)
///   3. Create one entitlement with identifier "pro"
///   4. Create two subscription products in App Store Connect:
///        • com.kevinjones.kinetriq.monthly  — 7-day free trial
///        • com.kevinjones.kinetriq.annual   — 7-day free trial
///   5. Attach both products to the "pro" entitlement in RevenueCat
///   6. Replace apiKey below with your key from RC → Project Settings → API Keys
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
    @Published var offerings: Offerings? = nil
    @Published var isLoading: Bool = true
    @Published var purchaseError: String? = nil

    // MARK: - Constants

    /// RevenueCat entitlement identifier. Must match what you create in the RC dashboard.
    static let entitlementID = "pro"

    /// TODO: Replace with your RevenueCat iOS API key from app.revenuecat.com
    /// Project Settings → API Keys → "App specific keys" → your iOS key (starts with "appl_")
    static let apiKey = "REVENUECAT_API_KEY_HERE"

    // MARK: - Promo codes

    /// Hardcoded promo codes granting unlimited free access.
    /// Update this list via app update when you need to add or rotate codes.
    private static let validPromoCodes: Set<String> = [
        "KINETRIQ-TRAINER",
        "KINETRIQ-BETA",
        "KINETRIQ-PRESS"
    ]

    private let promoCodeKey = "kinetriq_redeemed_promo"

    // MARK: - Init

    private init() {}

    // MARK: - Configuration

    func configure() {
        Purchases.logLevel = .warning
        Purchases.configure(withAPIKey: Self.apiKey)
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

        guard Self.apiKey != "REVENUECAT_API_KEY_HERE" else {
            // No API key yet — treat as unlocked so the app is testable during development
            isProUser = true
            return
        }

        do {
            let info = try await Purchases.shared.customerInfo()
            isProUser = info.entitlements[Self.entitlementID]?.isActive == true
        } catch {
            // Network unavailable — keep previous state rather than locking the user out
            isProUser = false
        }
    }

    // MARK: - Offerings (loads App Store products + pricing)

    func fetchOfferings() async {
        guard Self.apiKey != "REVENUECAT_API_KEY_HERE" else { return }
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            purchaseError = "Could not load subscription options. Check your connection and try again."
        }
    }

    // MARK: - Purchase

    func purchase(_ package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        isProUser = result.customerInfo.entitlements[Self.entitlementID]?.isActive == true
    }

    // MARK: - Restore

    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        isProUser = info.entitlements[Self.entitlementID]?.isActive == true
        if !isProUser {
            throw RestoreError.noPurchasesFound
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
}
