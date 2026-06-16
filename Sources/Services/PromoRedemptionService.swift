import Foundation

@MainActor
final class PromoRedemptionService: ObservableObject {

    static let shared = PromoRedemptionService()

    @Published private(set) var activeEntitlement: AccountEntitlement?
    @Published private(set) var lastRedeemedCode: String?
    @Published var redemptionError: String?

    private let entitlementKey = "kinetriq.account.entitlement"
    private let redeemedCodeKey = "kinetriq.promo.last_code"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        restoreCachedEntitlement()
    }

    func redeem(code: String, authSession: AuthSession?) async -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            redemptionError = "Enter a promo code."
            return false
        }

        if AppEnvironment.isSupabaseConfigured {
            guard let authSession else {
                redemptionError = "Sign in before redeeming a promo code."
                return false
            }
            return await redeemWithBackend(code: normalized, authSession: authSession)
        }

        return redeemDevelopmentCode(normalized)
    }

    func clearCachedEntitlement() {
        activeEntitlement = nil
        lastRedeemedCode = nil
        UserDefaults.standard.removeObject(forKey: entitlementKey)
        UserDefaults.standard.removeObject(forKey: redeemedCodeKey)
    }

    private func redeemWithBackend(code: String, authSession: AuthSession) async -> Bool {
        guard let baseURL = AppEnvironment.supabaseURL,
              let anonKey = AppEnvironment.supabaseAnonKey else {
            redemptionError = "Supabase is not configured."
            return false
        }

        do {
            let url = baseURL.appendingPathComponent("functions/v1/redeem-promo-code")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(PromoRedeemRequest(code: code))

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                redemptionError = String(data: data, encoding: .utf8) ?? "Promo code could not be redeemed."
                return false
            }

            let decoded = try decoder.decode(PromoRedeemResponse.self, from: data)
            guard decoded.entitlement.isCurrentlyActive else {
                redemptionError = "That promo code is not active."
                return false
            }

            persist(entitlement: decoded.entitlement, code: code)
            return true
        } catch {
            redemptionError = error.localizedDescription
            return false
        }
    }

    private func redeemDevelopmentCode(_ code: String) -> Bool {
        guard let entitlement = Self.developmentEntitlement(for: code) else {
            redemptionError = "Code not recognized."
            return false
        }

        persist(entitlement: entitlement, code: code)
        return true
    }

    private func persist(entitlement: AccountEntitlement, code: String) {
        activeEntitlement = entitlement
        lastRedeemedCode = code
        if let data = try? encoder.encode(entitlement) {
            UserDefaults.standard.set(data, forKey: entitlementKey)
        }
        UserDefaults.standard.set(code, forKey: redeemedCodeKey)
        redemptionError = nil
    }

    private func restoreCachedEntitlement() {
        if let data = UserDefaults.standard.data(forKey: entitlementKey),
           let entitlement = try? decoder.decode(AccountEntitlement.self, from: data),
           entitlement.isCurrentlyActive {
            activeEntitlement = entitlement
        }
        lastRedeemedCode = UserDefaults.standard.string(forKey: redeemedCodeKey)
    }

    private static func developmentEntitlement(for code: String) -> AccountEntitlement? {
        let now = Date()
        switch code {
        case "KINETRIQ-MONTH":
            return AccountEntitlement(
                entitlement: PurchaseService.entitlementID,
                source: .promoFreeMonth,
                startsAt: now,
                expiresAt: Calendar.current.date(byAdding: .month, value: 1, to: now),
                active: true
            )
        case "KINETRIQ-DISCOUNT":
            return AccountEntitlement(
                entitlement: PurchaseService.entitlementID,
                source: .promoDiscount,
                startsAt: now,
                expiresAt: Calendar.current.date(byAdding: .month, value: 1, to: now),
                active: true
            )
        case "KINETRIQ-COMP":
            return AccountEntitlement(
                entitlement: PurchaseService.entitlementID,
                source: .manualComp,
                startsAt: now,
                expiresAt: nil,
                active: true
            )
        default:
            return nil
        }
    }
}

private struct PromoRedeemRequest: Encodable {
    let code: String
}

private struct PromoRedeemResponse: Decodable {
    let entitlement: AccountEntitlement
}
