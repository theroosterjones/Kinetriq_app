import Foundation

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
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        restoreSession()
    }

    var isAuthenticated: Bool {
        session?.isExpired == false
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
            body: ["email": email, "password": password]
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
            authError = error.localizedDescription
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

    private func performAuthRequest(path: String, query: String?, body: [String: String]) async {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            let data = try await supabaseRequest(path: path, query: query, method: "POST", bearerToken: nil, body: body)
            let response = try decoder.decode(SupabaseAuthResponse.self, from: data)
            let session = response.authSession
            self.session = session
            persist(session)
            await PurchaseService.shared.identify(appUserID: session.user.id)
        } catch {
            authError = error.localizedDescription
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

    private func restoreSession() {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let restored = try? decoder.decode(AuthSession.self, from: data),
              !restored.isExpired else {
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
            let message = String(data: data, encoding: .utf8) ?? "Request failed."
            throw AuthServiceError.requestFailed(message)
        }
        return data
    }
}

private struct EmptyBody: Encodable {}

private struct SupabaseAuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let user: SupabaseUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }

    var authSession: AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
            user: UserProfile(id: user.id, email: user.email ?? "", displayName: nil, createdAt: user.createdAt)
        )
    }
}

private struct SupabaseUser: Decodable {
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
