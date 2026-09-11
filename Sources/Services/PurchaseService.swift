import Foundation
import RevenueCat
import StoreKit

@MainActor
final class PurchaseService: ObservableObject {

    static let shared = PurchaseService()

    @Published private(set) var hasRevenueCatEntitlement = false
    @Published private(set) var hasCoachEntitlement = false
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var offerings: Offerings?
    @Published private(set) var isLoading = true
    @Published var purchaseError: String?

    /// Identifiers that unlock Pro, live one first.
    ///
    /// The entitlement configured in RevenueCat is **`Kinetriq Pro`** — every current
    /// subscriber on both platforms is unlocked by that string alone, so it is load-bearing,
    /// not legacy, and removing it revokes Pro for everyone at once. `kinetriq_pro` is the
    /// intended rename and is accepted ahead of time so that switch needs no client release;
    /// `pro` predates both. Keep Android's `proEntitlementIds` in step with this list.
    static let acceptedEntitlementIDs = ["Kinetriq Pro", "kinetriq_pro", "pro"]

    /// Identifiers that unlock the **coach** tier: the client roster and invite codes.
    ///
    /// Deliberately a separate list. Adding a coach identifier to
    /// `acceptedEntitlementIDs` would work today and become impossible to unpick
    /// later, because that array is what every existing Pro subscriber is unlocked by.
    static let acceptedCoachEntitlementIDs = ["Kinetriq Coach", "kinetriq_coach"]

    /// App Store product identifiers, as registered in App Store Connect. The `kevink`
    /// spelling and the missing `.pro` segment are both real — verified against live
    /// `CustomerInfo`, which reports `com.kevinkjones.kinetriq.monthly` / `.annual`.
    static let monthlyProductID = "com.kevinkjones.kinetriq.monthly"
    static let yearlyProductID = "com.kevinkjones.kinetriq.annual"

    /// Coach tiers, priced by roster size.
    ///
    /// The coach pays for the seats, not the clients — that is how every coaching
    /// platform with real adoption prices it, and asking a trainer to chase fifteen
    /// clients for $5 each is how a coach tier dies. Client limits are enforced
    /// server-side in `create_coach_invite`; `coaches.client_limit` is the source of
    /// truth and is written by the RevenueCat webhook. The mapping below is only used
    /// to label the paywall before a purchase exists.
    ///
    /// These must be created in App Store Connect under the same `kevink` spelling as
    /// the products above before the coach tier can ship.
    enum CoachTier: String, CaseIterable, Identifiable {
        case starter
        case pro
        case studio

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .starter: return "Coach Starter"
            case .pro:     return "Coach Pro"
            case .studio:  return "Coach Studio"
            }
        }

        var clientLimit: Int {
            switch self {
            case .starter: return 5
            case .pro:     return 15
            case .studio:  return 40
            }
        }

        var monthlyProductID: String { "com.kevinkjones.kinetriq.coach.\(rawValue).monthly" }
        var annualProductID: String { "com.kevinkjones.kinetriq.coach.\(rawValue).annual" }

        static func matching(productID: String) -> CoachTier? {
            allCases.first {
                productID == $0.monthlyProductID || productID == $0.annualProductID
            }
        }
    }

    private var isRevenueCatConfigured = false

    /// Number of gated status lookups in flight. Launch and sign-in can overlap, so
    /// this tracks a count rather than a bare flag — otherwise the first one to
    /// finish clears `isLoading` while another is still resolving and the gate
    /// decides too early.
    private var inFlightStatusRequests = 0

    private init() {}

    private func beginStatusRequest() {
        inFlightStatusRequests += 1
        isLoading = true
    }

    private func endStatusRequest() {
        inFlightStatusRequests = max(0, inFlightStatusRequests - 1)
        if inFlightStatusRequests == 0 {
            isLoading = false
        }
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
            hasCoachEntitlement: hasCoachEntitlement,
            developmentUnlocked: developmentUnlocked
        )
    }

    var hasProAccess: Bool {
        accessState.hasProAccess
    }

    var hasCoachAccess: Bool {
        accessState.hasCoachAccess
    }

    /// Roster size the current coach subscription allows, inferred from the active
    /// product. The authoritative limit lives in `coaches.client_limit` and is
    /// enforced by Postgres; this only drives on-device labelling ("12 of 15").
    var coachTier: CoachTier? {
        guard hasCoachEntitlement, let info = customerInfo else { return nil }
        for entitlementID in Self.acceptedCoachEntitlementIDs {
            if let entitlement = info.entitlements[entitlementID], entitlement.isActive,
               let tier = CoachTier.matching(productID: entitlement.productIdentifier) {
                return tier
            }
        }
        return nil
    }

    var isProUser: Bool {
        hasProAccess
    }

    /// Configures RevenueCat, seeding it with the signed-in Supabase user ID when
    /// one is already known.
    ///
    /// Passing the ID here rather than following up with a separate `identify`
    /// call matters on a first launch after install or sign-out, where RevenueCat
    /// would otherwise start from an anonymous app user ID: the anonymous status
    /// fetch and the `logIn` would race, and whichever finished first would clear
    /// `isLoading` and win the write to `hasRevenueCatEntitlement`. A subscriber
    /// could then see the gate paywall for a moment before the stream corrected it.
    func configure(initialAppUserID: String? = nil) {
        guard let apiKey = AppEnvironment.revenueCatAPIKey else {
            hasRevenueCatEntitlement = false
            hasCoachEntitlement = false
            isLoading = false
            return
        }

        guard !isRevenueCatConfigured else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey, appUserID: initialAppUserID)
        isRevenueCatConfigured = true
        Task { await refreshStatus(showsLoadingGate: true) }
        observeCustomerInfo()
    }

    /// Continuously mirror RevenueCat's customer info so entitlement changes
    /// (e.g. a just-completed purchase) always propagate to `hasProAccess` on the
    /// main actor, even if a purchase callback delivers info before the entitlement
    /// has fully propagated. This is what reliably dismisses the paywall after a buy.
    private func observeCustomerInfo() {
        Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.updateSubscriptionStatus(from: info)
            }
        }
    }

    func identify(appUserID: String) async {
        guard isRevenueCatConfigured else {
            isLoading = false
            return
        }

        beginStatusRequest()
        defer { endStatusRequest() }

        do {
            let result = try await Purchases.shared.logIn(appUserID)
            updateSubscriptionStatus(from: result.customerInfo)
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func logOut() async {
        guard isRevenueCatConfigured else {
            hasRevenueCatEntitlement = false
            hasCoachEntitlement = false
            return
        }

        do {
            let info = try await Purchases.shared.logOut()
            updateSubscriptionStatus(from: info)
        } catch {
            hasRevenueCatEntitlement = false
            hasCoachEntitlement = false
        }
    }

    /// Re-reads entitlements from RevenueCat.
    ///
    /// `showsLoadingGate` must stay `false` for anything that runs *from* the
    /// paywall (recovery, offer-code redemption) or from foregrounding. The gate in
    /// `ContentView` swaps the paywall out for the loading view while `isLoading` is
    /// true, which cancels the paywall's `.task` and lets it re-fire when the paywall
    /// comes back — so a gated refresh started there tears down the view that started
    /// it and loops forever. Only the launch lookup in `configure()` raises the gate;
    /// sign-in raises it through `identify(appUserID:)` instead.
    func refreshStatus(showsLoadingGate: Bool = false) async {
        guard isRevenueCatConfigured else {
            isLoading = false
            return
        }

        if showsLoadingGate { beginStatusRequest() }
        defer { if showsLoadingGate { endStatusRequest() } }

        do {
            let info = try await Purchases.shared.customerInfo()
            updateSubscriptionStatus(from: info)
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private var didAttemptSilentRecovery = false

    /// Recovers Pro access for a returning subscriber whose active Apple-ID
    /// subscription isn't yet linked to the current RevenueCat app user ID
    /// (e.g. it was purchased before logging in, or under a previous session).
    ///
    /// Called when the paywall appears: first a cheap `customerInfo` refresh, then
    /// — only if still locked out — a one-time silent restore that transfers the
    /// Apple-ID purchase onto this user so they don't have to see the paywall
    /// again. Errors are swallowed; the manual "Restore Purchases" button remains
    /// as an explicit fallback.
    func recoverEntitlementsIfNeeded() async {
        guard isRevenueCatConfigured else {
            isLoading = false
            return
        }

        await refreshStatus()

        guard !hasProAccess, !didAttemptSilentRecovery else { return }
        didAttemptSilentRecovery = true

        do {
            let info = try await Purchases.shared.restorePurchases()
            updateSubscriptionStatus(from: info)
        } catch {
            // Silent by design — surfaced only through the manual Restore button.
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

    func updateSubscriptionStatus(from info: CustomerInfo) {
        customerInfo = info
        hasRevenueCatEntitlement = Self.acceptedEntitlementIDs.contains { entitlementID in
            info.entitlements[entitlementID]?.isActive == true
        }
        hasCoachEntitlement = Self.acceptedCoachEntitlementIDs.contains { entitlementID in
            info.entitlements[entitlementID]?.isActive == true
        }
    }

    func presentAppStoreOfferCodeRedemption() {
        SKPaymentQueue.default().presentCodeRedemptionSheet()
    }

    /// Turns a StoreKit / RevenueCat error into plain-language guidance plus a
    /// screenshot-able reference code. Returns `nil` when the user simply
    /// cancelled, so callers can silently dismiss instead of showing an alert.
    static func userFacingMessage(for error: Error) -> String? {
        if let restoreError = error as? RestoreError {
            let reference: String
            switch restoreError {
            case .revenueCatNotConfigured: reference = "IAP-CONFIG"
            case .noPurchasesFound: reference = "IAP-NORESTORE"
            }
            return withReference(restoreError.errorDescription ?? "Something went wrong.", reference)
        }

        let nsError = error as NSError
        if nsError.domain == ErrorCode.errorDomain, let code = ErrorCode(rawValue: nsError.code) {
            let message: String
            switch code {
            case .purchaseCancelledError:
                return nil
            case .storeProblemError:
                message = "The App Store had a problem completing your request. Please try again in a moment."
            case .purchaseNotAllowedError:
                message = "Purchases aren't allowed on this device. Check Screen Time or restrictions, then try again."
            case .paymentPendingError:
                message = "Your purchase is pending approval (for example, Ask to Buy). You'll get access as soon as it's approved."
            case .productAlreadyPurchasedError:
                message = "You're already subscribed on this Apple ID. Tap Restore Purchases to unlock access."
            case .receiptAlreadyInUseError, .receiptInUseByOtherSubscriberError:
                message = "This subscription is already active on a different account. Sign in with that account or contact support."
            case .networkError, .offlineConnectionError:
                message = "Couldn't reach the App Store. Check your internet connection and try again."
            case .productNotAvailableForPurchaseError:
                message = "This subscription isn't available right now. Please try again later."
            case .configurationError, .invalidAppleSubscriptionKeyError, .invalidCredentialsError:
                message = "Subscriptions are temporarily unavailable. Please try again later."
            default:
                message = "We couldn't complete your request. Please try again."
            }
            return withReference(message, "IAP-\(code.rawValue) (\(code))")
        }

        if let urlError = error as? URLError {
            return withReference("Couldn't reach the App Store. Check your connection and try again.", "NET-\(urlError.errorCode)")
        }

        return withReference(error.localizedDescription, "\(nsError.domain)-\(nsError.code)")
    }

    private static func withReference(_ message: String, _ reference: String) -> String {
        "\(message)\n\nError code: \(reference)\nPlease screenshot this and send it to support if it keeps happening."
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
