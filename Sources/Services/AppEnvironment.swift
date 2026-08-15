import Foundation

enum AppEnvironment {
    static var revenueCatAPIKey: String? {
        configuredString(for: "KinetriqRevenueCatAPIKey", placeholders: ["REVENUECAT_IOS_PUBLIC_SDK_KEY_HERE"])
    }

    static var supabaseURL: URL? {
        guard let rawValue = configuredString(for: "KinetriqSupabaseURL", placeholders: ["SUPABASE_PROJECT_URL_HERE"]) else {
            return nil
        }
        return URL(string: rawValue)
    }

    static var supabaseAnonKey: String? {
        configuredString(for: "KinetriqSupabaseAnonKey", placeholders: ["SUPABASE_ANON_KEY_HERE"])
    }

    static var privacyPolicyURL: URL? {
        configuredURL(for: "KinetriqPrivacyPolicyURL")
    }

    static var termsURL: URL? {
        configuredURL(for: "KinetriqTermsURL")
    }

    static var isSupabaseConfigured: Bool {
        supabaseURL != nil && supabaseAnonKey != nil
    }

    private static func configuredURL(for key: String) -> URL? {
        guard let rawValue = configuredString(for: key, placeholders: []) else { return nil }
        return URL(string: rawValue)
    }

    private static func configuredString(for key: String, placeholders: Set<String>) -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !placeholders.contains(trimmed) else {
            return nil
        }
        return trimmed
    }
}
