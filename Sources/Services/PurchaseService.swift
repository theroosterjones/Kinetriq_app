import Foundation
import RevenueCat
import StoreKit

@MainActor
final class PurchaseService: ObservableObject {

    static let shared = PurchaseService()

    @Published private(set) var hasRevenueCatEntitlement = false
    @Published private(set) var backendEntitlement: AccountEntitlement?
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var offerings: Offerings?
    @Published private(set) var isLoading = true
    @Published var purchaseError: String?

    static let entitlementID = "kinetriq_pro"
    static let acceptedEntitlementIDs = ["kinetriq_pro", "pro", "Kinetriq Pro"]

    static let monthlyProductID = "com.kevinjones.kinetriq.pro.monthly"
    static let yearlyProductID = "com.kevinjones.kinetriq.pro.yearly"

    private var isRevenueCatConfigured = false

    private init() {
        backendEntitlement = PromoRedemptionService.shared.activeEntitlement
    }

    var hasConfiguredAPIKey: Bool {
        AppEnvironment.revenueCatAPIKey != nil
    }

    var developmentUnlocked: Bool {
        !hasConfiguredAPIKey
    }

    var accessState: SubscriptionAccessState {
        SubscriptionAccessState(
            hasRevenueCatEntitlement: hasRevenueCatEntitlement,
            backendEntitlement: backendEntitlement,
            developmentUnlocked: developmentUnlocked
        )
    }

    var hasProAccess: Bool {
        accessState.hasProAccess
    }

    var isProUser: Bool {
        hasProAccess
    }

    func configure() {
        guard let apiKey = AppEnvironment.revenueCatAPIKey else {
            hasRevenueCatEntitlement = false
            isLoading = false
            return
        }

        guard !isRevenueCatConfigured else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
        isRevenueCatConfigured = true
        Task { await refreshStatus() }
    }

    func identify(appUserID: String) async {
        guard isRevenueCatConfigured else {
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await Purchases.shared.logIn(appUserID)
            updateSubscriptionStatus(from: result.customerInfo)
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func logOut() async {
        PromoRedemptionService.shared.clearCachedEntitlement()
        backendEntitlement = nil

        guard isRevenueCatConfigured else {
            hasRevenueCatEntitlement = false
            return
        }

        do {
            let info = try await Purchases.shared.logOut()
            updateSubscriptionStatus(from: info)
        } catch {
            hasRevenueCatEntitlement = false
        }
    }

    func refreshStatus() async {
        backendEntitlement = PromoRedemptionService.shared.activeEntitlement

        guard isRevenueCatConfigured else {
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let info = try await Purchases.shared.customerInfo()
            updateSubscriptionStatus(from: info)
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func fetchOfferings() async {
        guard isRevenueCatConfigured else { return }
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            purchaseError = "Could not load subscription options. Check your connection and try again."
        }
    }

    func purchase(_ package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        updateSubscriptionStatus(from: result.customerInfo)
    }

    func restorePurchases() async throws {
        guard isRevenueCatConfigured else {
            throw RestoreError.revenueCatNotConfigured
        }

        let info = try await Purchases.shared.restorePurchases()
        updateSubscriptionStatus(from: info)
        if !hasProAccess {
            throw RestoreError.noPurchasesFound
        }
    }

    @discardableResult
    func redeemPromoCode(_ code: String, authSession: AuthSession?) async -> Bool {
        let redeemed = await PromoRedemptionService.shared.redeem(code: code, authSession: authSession)
        backendEntitlement = PromoRedemptionService.shared.activeEntitlement
        if redeemed {
            await refreshStatus()
        } else {
            purchaseError = PromoRedemptionService.shared.redemptionError
        }
        return redeemed
    }

    func hasRedeemedPromoCode() -> Bool {
        backendEntitlement?.isCurrentlyActive == true
    }

    func redeemedPromoCode() -> String? {
        PromoRedemptionService.shared.lastRedeemedCode
    }

    func updateSubscriptionStatus(from info: CustomerInfo) {
        customerInfo = info
        hasRevenueCatEntitlement = Self.acceptedEntitlementIDs.contains { entitlementID in
            info.entitlements[entitlementID]?.isActive == true
        }
    }

    func presentAppStoreOfferCodeRedemption() {
        SKPaymentQueue.default().presentCodeRedemptionSheet()
    }

    enum RestoreError: LocalizedError {
        case revenueCatNotConfigured
        case noPurchasesFound

        var errorDescription: String? {
            switch self {
            case .revenueCatNotConfigured:
                return "RevenueCat is not configured yet."
            case .noPurchasesFound:
                return "No previous purchases found for this Apple ID."
            }
        }
    }
}
