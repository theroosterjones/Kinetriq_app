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

    /// A session that carries a refresh token can be renewed without asking the
    /// user to sign in again, so it should be treated as still-authenticated while
    /// the access token is refreshed in the background.
    var isRenewable: Bool {
        refreshToken?.isEmpty == false
    }
}

struct SubscriptionAccessState: Equatable {
    var hasRevenueCatEntitlement: Bool
    /// A separate RevenueCat entitlement for the coach tier. Coaches analyze their
    /// own movement too, so it implies Pro — but it is a distinct entitlement, not a
    /// value added to `acceptedEntitlementIDs`, which every existing subscriber
    /// depends on and must not change.
    var hasCoachEntitlement: Bool = false
    /// Local convenience unlock for development builds only. It is intentionally
    /// ignored in Release so that Pro access is granted solely through Apple
    /// In-App Purchase (RevenueCat) in shipping builds.
    var developmentUnlocked: Bool

    var hasProAccess: Bool {
        #if DEBUG
        return hasRevenueCatEntitlement || hasCoachEntitlement || developmentUnlocked
        #else
        return hasRevenueCatEntitlement || hasCoachEntitlement
        #endif
    }

    /// Coach tooling is never opened by the development unlock: the roster talks to
    /// real Supabase tables holding real clients' data, so a debug build must not be
    /// able to walk into it.
    var hasCoachAccess: Bool {
        hasCoachEntitlement
    }
}
