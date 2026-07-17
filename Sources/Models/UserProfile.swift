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

struct SubscriptionAccessState: Equatable {
    var hasRevenueCatEntitlement: Bool
    /// Local convenience unlock for development builds only. It is intentionally
    /// ignored in Release so that Pro access is granted solely through Apple
    /// In-App Purchase (RevenueCat) in shipping builds.
    var developmentUnlocked: Bool

    var hasProAccess: Bool {
        #if DEBUG
        return hasRevenueCatEntitlement || developmentUnlocked
        #else
        return hasRevenueCatEntitlement
        #endif
    }
}
