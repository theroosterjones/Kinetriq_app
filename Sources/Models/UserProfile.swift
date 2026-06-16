import Foundation

struct UserProfile: Codable, Equatable, Identifiable {
    let id: String
    var email: String
    var displayName: String?
    var createdAt: Date?
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let user: UserProfile

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

enum PromoCodeKind: String, Codable, Equatable {
    case freeMonth = "free_month"
    case discount
    case unlimited
}

enum AccountEntitlementSource: String, Codable, Equatable {
    case revenueCat = "revenuecat"
    case promoFreeMonth = "promo_free_month"
    case promoDiscount = "promo_discount"
    case manualComp = "manual_comp"
}

struct AccountEntitlement: Codable, Equatable {
    let entitlement: String
    let source: AccountEntitlementSource
    let startsAt: Date
    let expiresAt: Date?
    let active: Bool

    var isCurrentlyActive: Bool {
        guard active else { return false }
        let now = Date()
        guard startsAt <= now else { return false }
        return expiresAt.map { $0 > now } ?? true
    }
}

struct SubscriptionAccessState: Equatable {
    var hasRevenueCatEntitlement: Bool
    var backendEntitlement: AccountEntitlement?
    var developmentUnlocked: Bool

    var hasProAccess: Bool {
        developmentUnlocked || hasRevenueCatEntitlement || (backendEntitlement?.isCurrentlyActive == true)
    }
}
