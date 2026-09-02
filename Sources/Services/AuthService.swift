import Foundation
import CryptoKit

@MainActor
final class AuthService: ObservableObject {

    static let shared = AuthService()

    @Published private(set) var session: AuthSession?
    @Published private(set) var isLoading = false
    @Published var authError: String?

    private let sessionKey = "kinetriq.auth.session"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {
        decoder.dateDecodingStrategy = ISO8601Timestamp.decodingStrategy
        encoder.dateEncodingStrategy = .iso8601
        restoreSession()
    }

    var isAuthenticated: Bool {
        guard let session else { return false }
        // Stay signed in across launches: a session with a refresh token is
        // considered authenticated even if the access token has expired, because
        // it will be renewed silently in the background.
        return !session.isExpired || session.isRenewable
    }

    var currentUserID: String? {
        session?.user.id
    }

    var currentEmail: String? {
        session?.user.email
    }

    var isConfigured: Bool {
        AppEnvironment.isSupabaseConfigured
    }

    func bootstrap() {
        restoreSession()
        // Renew the access token from the stored refresh token so returning users
        // land straight in the app instead of the login screen.
        Task { await refreshSessionIfNeeded() }
    }

    /// Renews the access token using the stored refresh token. Called on launch and
    /// when the app returns to the foreground so a signed-in user is never forced
    /// to re-enter credentials. Only a definitive rejection of the refresh token
    /// (HTTP 4xx) signs the user out; transient/network/server errors keep the
    /// existing session so offline launches don't kick the user to login.
    func refreshSessionIfNeeded(force: Bool = false) async {
        guard isConfigured,
              let current = session,
              let refreshToken = current.refreshToken, !refreshToken.isEmpty,
              let baseURL = AppEnvironment.supabaseURL,
              let anonKey = AppEnvironment.supabaseAnonKey else {
            return
        }

        // Refresh when expired, missing an expiry, or within a 5-minute safety window.
        let needsRefresh = force || (current.expiresAt.map { $0.timeIntervalSinceNow < 300 } ?? true)
        guard needsRefresh else { return }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("auth/v1/token"),
            resolvingAgainstBaseURL: false
        )
        components?.percentEncodedQuery = "grant_type=refresh_token"
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["refresh_token": refreshToken])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            if (200..<300).contains(httpResponse.statusCode) {
                if let refreshed = try? decoder.decode(SupabaseAuthResponse.self, from: data).authSession {
                    session = refreshed
                    persist(refreshed)
                    await PurchaseService.shared.identify(appUserID: refreshed.user.id)
                }
            } else if (400..<500).contains(httpResponse.statusCode) {
                // Refresh token revoked/expired — a fresh login is required.
                clearSession()
                await PurchaseService.shared.logOut()
            }
            // 5xx: leave the session intact and try again next launch/foreground.
        } catch {
            // Offline or transient failure — keep the session and retry later.
        }
    }

    func signIn(email: String, password: String) async {
        guard isConfigured else {
            createDevelopmentSession(email: email)
            return
        }

        await performAuthRequest(
            path: "token",
            query: "grant_type=password",
            body: ["email": email, "password": password]
        )
    }

    func signUp(email: String, password: String) async {
        guard isConfigured else {
            createDevelopmentSession(email: email)
            return
        }

        await performAuthRequest(
            path: "signup",
            query: nil,
            body: ["email": email, "password": password],
            isSignUp: true
        )
    }

    /// Completes a Sign in with Apple flow by exchanging the Apple identity token
    /// for a Supabase session (or a local dev session when Supabase isn't configured).
    ///
    /// - Parameters:
    ///   - idTokenData: `ASAuthorizationAppleIDCredential.identityToken`.
    ///   - rawNonce: the un-hashed nonce that was hashed into the Apple request.
    ///   - fullName: name components Apple returns only on first authorization.
    func signInWithApple(idTokenData: Data?, rawNonce: String, fullName: PersonNameComponents?) async {
        guard let idTokenData, let idToken = String(data: idTokenData, encoding: .utf8) else {
            authError = "Apple sign-in did not return a valid identity token."
            return
        }

        guard isConfigured else {
            createDevelopmentSessionForApple(fullName: fullName)
            return
        }

        await performAuthRequest(
            path: "token",
            query: "grant_type=id_token",
            body: ["provider": "apple", "id_token": idToken, "nonce": rawNonce]
        )
    }

    func sendPasswordReset(email: String) async {
        guard isConfigured else {
            authError = "Password reset requires Supabase configuration."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await supabaseRequest(
                path: "recover",
                method: "POST",
                bearerToken: nil,
                body: ["email": email]
            )
            authError = "Password reset email sent."
        } catch {
            authError = Self.userFacingMessage(for: error)
        }
    }

    func signOut() async {
        let accessToken = session?.accessToken
        clearSession()
        await PurchaseService.shared.logOut()

        guard isConfigured, let accessToken else { return }
        try? await supabaseRequest(path: "logout", method: "POST", bearerToken: accessToken, body: EmptyBody())
    }

    func requestAccountDeletion() async {
        guard isConfigured, let session else {
            authError = "Account deletion requires a logged-in Supabase user."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await edgeFunctionRequest(
                functionName: "delete-account",
                bearerToken: session.accessToken,
                body: ["user_id": session.user.id]
            )
            await signOut()
        } catch {
            authError = "Account deletion request failed. Configure the Supabase delete-account Edge Function before launch."
        }
    }

    private func performAuthRequest(path: String, query: String?, body: [String: String], isSignUp: Bool = false) async {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            let data = try await supabaseRequest(path: path, query: query, method: "POST", bearerToken: nil, body: body)
            let response = try AuthResponseParser.decode(data)

            // When email confirmation is enabled, sign-up returns a user with no
            // session (no access_token) until the address is confirmed. Surface a
            // helpful message instead of a raw JSON decode failure.
            guard let session = response.authSession else {
                if isSignUp {
                    authError = "Account created. Check your email for a confirmation link, then sign in."
                } else {
                    authError = "Please confirm your email before signing in. Check your inbox for the confirmation link."
                }
                return
            }

            self.session = session
            persist(session)
            await PurchaseService.shared.identify(appUserID: session.user.id)
        } catch {
            authError = Self.userFacingMessage(for: error)
        }
    }

    private func createDevelopmentSession(email: String) {
        let userID = "dev-\(email.lowercased().replacingOccurrences(of: "@", with: "-at-"))"
        let user = UserProfile(id: userID, email: email, displayName: nil, createdAt: Date())
        let session = AuthSession(
            accessToken: "development-token",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 365),
            user: user
        )
        self.session = session
        persist(session)
        Task { await PurchaseService.shared.identify(appUserID: userID) }
    }

    private func createDevelopmentSessionForApple(fullName: PersonNameComponents?) {
        let name = fullName.flatMap {
            PersonNameComponentsFormatter().string(from: $0).trimmingCharacters(in: .whitespaces)
        }
        let email = "apple-dev-user@kinetriq.local"
        let user = UserProfile(
            id: "dev-apple-user",
            email: email,
            displayName: name?.isEmpty == false ? name : nil,
            createdAt: Date()
        )
        let session = AuthSession(
            accessToken: "development-token",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 365),
            user: user
        )
        self.session = session
        persist(session)
        Task { await PurchaseService.shared.identify(appUserID: user.id) }
    }

    // MARK: - Sign in with Apple nonce helpers

    /// Cryptographically random nonce used to bind the Apple credential to this request.
    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if status == errSecSuccess {
                if random < charset.count {
                    result.append(charset[Int(random) % charset.count])
                    remaining -= 1
                }
            } else {
                // Fallback that still yields a usable nonce if SecRandom fails.
                result.append(charset.randomElement()!)
                remaining -= 1
            }
        }
        return result
    }

    /// SHA-256 hash (hex) of the nonce, which is what Apple expects in the request.
    static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    private func restoreSession() {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let restored = try? decoder.decode(AuthSession.self, from: data) else {
            clearSession()
            return
        }
        // Keep the session if the access token is still valid, or if it can be
        // renewed from a refresh token. Only discard a truly dead session (expired
        // with no way to renew) so users aren't forced to log in every launch.
        guard !restored.isExpired || restored.isRenewable else {
            clearSession()
            return
        }
        session = restored
    }

    private func persist(_ session: AuthSession) {
        guard let data = try? encoder.encode(session) else { return }
        UserDefaults.standard.set(data, forKey: sessionKey)
    }

    private func clearSession() {
        session = nil
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    @discardableResult
    private func supabaseRequest<Body: Encodable>(
        path: String,
        query: String? = nil,
        method: String,
        bearerToken: String?,
        body: Body
    ) async throws -> Data {
        guard let baseURL = AppEnvironment.supabaseURL,
              let anonKey = AppEnvironment.supabaseAnonKey else {
            throw AuthServiceError.notConfigured
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("auth/v1/\(path)"), resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = query

        guard let url = components?.url else {
            throw AuthServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

        return try await send(request)
    }

    @discardableResult
    private func edgeFunctionRequest<Body: Encodable>(
        functionName: String,
        bearerToken: String,
        body: Body
    ) async throws -> Data {
        guard let baseURL = AppEnvironment.supabaseURL,
              let anonKey = AppEnvironment.supabaseAnonKey else {
            throw AuthServiceError.notConfigured
        }

        let url = baseURL.appendingPathComponent("functions/v1/\(functionName)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AuthServiceError.requestFailed(Self.friendlyMessage(from: data, statusCode: httpResponse.statusCode))
        }
        return data
    }

    /// Converts Supabase/GoTrue error payloads into human-readable text. Handles
    /// both the legacy `{"error","error_description"}` and newer
    /// `{"code","error_code","msg"}` shapes, and never surfaces raw JSON.
    ///
    /// Every returned string ends with a short, screenshot-able reference code so a
    /// user can send it in for troubleshooting while still seeing plain-language
    /// guidance about what to do next.
    static func friendlyMessage(from data: Data, statusCode: Int) -> String {
        let payload = try? JSONDecoder().decode(SupabaseErrorPayload.self, from: data)
        let code = payload?.errorCode ?? payload?.error
        let rawMessage = payload?.msg ?? payload?.errorDescription ?? payload?.message
        let reference = "AUTH-\(statusCode)" + (code.map { "-\($0)" } ?? "")

        let message: String
        switch code {
        case "over_email_send_rate_limit", "over_request_rate_limit", "over_sms_send_rate_limit":
            message = "Too many attempts right now. Please wait a minute and try again."
        case "invalid_credentials", "invalid_grant":
            message = "Incorrect email or password. Please double-check and try again."
        case "email_not_confirmed":
            message = "Please confirm your email before signing in. Check your inbox for the confirmation link."
        case "user_already_exists", "email_exists":
            message = "An account with this email already exists. Try signing in instead."
        case "weak_password":
            message = "Please choose a stronger password of at least 6 characters."
        case "validation_failed", "email_address_invalid":
            message = "Please enter a valid email address and password."
        default:
            if statusCode == 429 {
                message = "Too many attempts right now. Please wait a minute and try again."
            } else if statusCode >= 500 {
                message = "The sign-in server is having trouble right now. Please try again in a few minutes."
            } else if let rawMessage, !rawMessage.isEmpty {
                message = rawMessage
            } else {
                message = "Something went wrong while signing in. Please try again."
            }
        }
        return withReference(message, reference)
    }

    /// Maps any thrown error into user-facing guidance plus a screenshot-able code.
    /// HTTP failures already carry a friendly message + code (see `friendlyMessage`),
    /// so this mainly covers connectivity and configuration problems.
    static func userFacingMessage(for error: Error) -> String {
        if let authError = error as? AuthServiceError {
            switch authError {
            case .requestFailed(let message):
                return message
            case .notConfigured:
                return withReference("Sign-in is temporarily unavailable. Please try again later.", "AUTH-CONFIG")
            case .invalidURL:
                return withReference("Sign-in is temporarily unavailable. Please try again later.", "AUTH-URL")
            case .invalidResponse:
                return withReference("The server returned an unexpected response. Please try again.", "AUTH-RESP")
            }
        }
        if let urlError = error as? URLError {
            return withReference(friendlyNetworkMessage(urlError), "NET-\(urlError.errorCode)")
        }
        if error is DecodingError {
            return withReference("Something went wrong while signing in. Please try again.", "AUTH-DECODE")
        }
        let nsError = error as NSError
        return withReference(error.localizedDescription, "\(nsError.domain)-\(nsError.code)")
    }

    private static func friendlyNetworkMessage(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "You appear to be offline. Check your internet connection and try again."
        case .timedOut:
            return "The request timed out. Please check your connection and try again."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Couldn't reach the sign-in server. Please try again in a few minutes."
        default:
            return "A network problem occurred. Please try again."
        }
    }

    /// Appends a short reference code and screenshot prompt to a plain-language message.
    private static func withReference(_ message: String, _ reference: String) -> String {
        "\(message)\n\nError code: \(reference)\nPlease screenshot this and send it to support if it keeps happening."
    }
}

private struct SupabaseErrorPayload: Decodable {
    let error: String?
    let errorCode: String?
    let errorDescription: String?
    let msg: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorCode = "error_code"
        case errorDescription = "error_description"
        case msg
        case message
    }
}

private struct EmptyBody: Encodable {}

/// Parses GoTrue `/auth/v1/token` JSON. Isolated from `AuthService` so tests can
/// cover the decode path without hopping onto the main-actor singleton.
enum AuthResponseParser {
    static func decode(_ data: Data) throws -> SupabaseAuthResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = ISO8601Timestamp.decodingStrategy
        return try decoder.decode(SupabaseAuthResponse.self, from: data)
    }
}

/// GoTrue/Supabase timestamps include microseconds (`2026-08-27T06:46:52.624123Z`).
/// Foundation's built-in `.iso8601` strategy rejects fractional seconds and the
/// failure surfaces as NSCocoaErrorDomain 4864 after a successful HTTP 200.
enum ISO8601Timestamp {
    static var decodingStrategy: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parse(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date, got \(raw)"
            )
        }
    }

    static func parse(_ string: String) -> Date? {
        fractional.date(from: string) ?? internet.date(from: string)
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct SupabaseAuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let user: SupabaseUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }

    /// Returns a session only when Supabase issued an access token. A `nil`
    /// result means sign-up succeeded but email confirmation is still pending.
    var authSession: AuthSession? {
        guard let accessToken, let user else { return nil }
        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
            user: UserProfile(id: user.id, email: user.email ?? "", displayName: nil, createdAt: user.createdAt)
        )
    }
}

struct SupabaseUser: Decodable {
    let id: String
    let email: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case createdAt = "created_at"
    }
}

private enum AuthServiceError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured yet."
        case .invalidURL:
            return "Supabase URL is invalid."
        case .invalidResponse:
            return "Supabase returned an invalid response."
        case .requestFailed(let message):
            return message
        }
    }
}
