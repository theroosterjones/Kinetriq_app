import Foundation
import os.log

private let logger = Logger(subsystem: "com.kevinjones.Kinetriq", category: "CoachService")

// MARK: - Roster models

/// One client as the roster sees them. Measurements only — there is no video field
/// here because there is no client video anywhere outside the client's own device.
struct CoachClient: Identifiable, Equatable {
    let clientUserID: String
    let displayName: String
    let status: String
    let linkedAt: Date
    let lastSessionAt: Date?
    let sessionsLast14Days: Int
    let latestScore: Int?
    let previousScore: Int?
    let latestMovement: String?
    let openAsymmetryFlag: Bool

    var id: String { clientUserID }

    var daysSinceLastSession: Int? {
        guard let lastSessionAt else { return nil }
        return Calendar.current.dateComponents([.day], from: lastSessionAt, to: Date()).day
    }

    var scoreDelta: Int? {
        guard let latestScore, let previousScore else { return nil }
        return latestScore - previousScore
    }
}

/// One of a client's analyses, read-only.
///
/// Deliberately not an `AnalysisRecord`: these belong to someone else and must never
/// enter this device's SwiftData store, where they would be indistinguishable from the
/// coach's own history and would get queued for re-upload. A plain struct cannot be
/// persisted by accident.
///
/// There is no video field, because `analysis_records` has no video column and there
/// is no storage bucket. Same read the web dashboard makes — see `web/coach/`.
struct CoachClientSession: Identifiable, Equatable {
    let id: String
    let date: Date
    let kind: AnalysisKind
    let movementName: String
    let totalReps: Int
    let score: Int?
    let grade: LetterGrade?
    let meanPeakAngle: Double?
    let poseDetectionRate: Double
    let asymmetryDeg: Double?
    let asymmetryFlag: Bool
    let insights: [String]
    let details: [String]
    let reps: [RepMetric]

    /// Average tempo across the set, formatted like the per-rep strings ("3-1-2-1").
    /// Averaged before rounding, matching `AnalysisRecord.averageTempoString`.
    var averageTempoString: String? {
        guard !reps.isEmpty else { return nil }
        let n = Double(reps.count)
        return TempoDurationFormatter.string(
            eccentric: reps.reduce(0) { $0 + $1.eccentricDuration } / n,
            pauseBottom: reps.reduce(0) { $0 + $1.pauseBottomDuration } / n,
            concentric: reps.reduce(0) { $0 + $1.concentricDuration } / n,
            pauseTop: reps.reduce(0) { $0 + $1.pauseTopDuration } / n
        )
    }

    var summaryLine: String {
        switch kind {
        case .exercise:
            var parts = ["\(totalReps) rep\(totalReps == 1 ? "" : "s")"]
            if let score { parts.append("score \(score)") }
            if let tempo = averageTempoString { parts.append("tempo \(tempo)") }
            return parts.joined(separator: " · ")
        case .assessment:
            var parts: [String] = []
            if let grade { parts.append("grade \(grade.rawValue)") }
            if let asymmetryDeg { parts.append("\(Int(asymmetryDeg))° asymmetry") }
            return parts.isEmpty ? "Assessment" : parts.joined(separator: " · ")
        }
    }
}

/// Why a client surfaced at the top of the queue. The roster shows exactly one of
/// these per client so the list reads as a work queue rather than a dashboard.
enum TriageReason: Equatable {
    case neverStarted
    case wentQuiet(days: Int)
    case scoreDropping(points: Int)
    case newAsymmetry
    case improving(points: Int)
    case steady

    var isAttention: Bool {
        switch self {
        case .neverStarted, .wentQuiet, .scoreDropping, .newAsymmetry: return true
        case .improving, .steady: return false
        }
    }

    var label: String {
        switch self {
        case .neverStarted:                return "Hasn't started"
        case .wentQuiet(let days):         return "Quiet \(days) days"
        case .scoreDropping(let points):   return "Down \(points) pts"
        case .newAsymmetry:                return "Asymmetry flagged"
        case .improving(let points):       return "Up \(points) pts"
        case .steady:                      return "On track"
        }
    }

    var icon: String {
        switch self {
        case .neverStarted:   return "person.crop.circle.badge.questionmark"
        case .wentQuiet:      return "moon.zzz.fill"
        case .scoreDropping:  return "arrow.down.right.circle.fill"
        case .newAsymmetry:   return "arrow.left.arrow.right"
        case .improving:      return "arrow.up.right.circle.fill"
        case .steady:         return "checkmark.circle.fill"
        }
    }
}

/// Turns a roster into a work queue.
///
/// This is the coach-tier wedge. Platforms with distribution do scheduling and
/// billing; they cannot tell a trainer which of forty clients to look at on a
/// Tuesday, because they have no measurements to reason about. Kinetriq does, so the
/// roster leads with triage instead of a reverse-chronological feed of clips —
/// reviewing every video is exactly the work a busy coach does not have time for.
enum CoachTriage {

    /// No session in this long and the client has effectively stopped.
    static let quietThresholdDays = 10

    /// Score swings smaller than this are session-to-session noise, matching the
    /// threshold `TrendInsights` uses.
    static let scoreChangeThreshold = TrendInsights.scoreChangeThreshold

    static func reason(for client: CoachClient) -> TriageReason {
        guard client.lastSessionAt != nil else { return .neverStarted }

        if let days = client.daysSinceLastSession, days >= quietThresholdDays {
            return .wentQuiet(days: days)
        }
        if let delta = client.scoreDelta, delta <= -scoreChangeThreshold {
            return .scoreDropping(points: abs(delta))
        }
        if client.openAsymmetryFlag {
            return .newAsymmetry
        }
        if let delta = client.scoreDelta, delta >= scoreChangeThreshold {
            return .improving(points: delta)
        }
        return .steady
    }

    /// Severity order: never started, then quiet longest, then falling furthest, then
    /// asymmetry, then everyone who is fine.
    private static func rank(_ reason: TriageReason) -> Int {
        switch reason {
        case .neverStarted:  return 0
        case .wentQuiet:     return 1
        case .scoreDropping: return 2
        case .newAsymmetry:  return 3
        case .improving:     return 4
        case .steady:        return 5
        }
    }

    /// Worst first, then most severe within a bucket, then alphabetically so the
    /// order is stable between refreshes.
    static func sorted(_ clients: [CoachClient]) -> [CoachClient] {
        clients.sorted { lhs, rhs in
            let lhsReason = reason(for: lhs)
            let rhsReason = reason(for: rhs)
            let lhsRank = rank(lhsReason)
            let rhsRank = rank(rhsReason)
            if lhsRank != rhsRank { return lhsRank < rhsRank }

            switch (lhsReason, rhsReason) {
            case let (.wentQuiet(a), .wentQuiet(b)) where a != b:
                return a > b
            case let (.scoreDropping(a), .scoreDropping(b)) where a != b:
                return a > b
            default:
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    static func needingAttention(_ clients: [CoachClient]) -> [CoachClient] {
        clients.filter { reason(for: $0).isAttention }
    }
}

// MARK: - Service

/// Talks to the coaching RPCs in `supabase/schema.sql`.
///
/// Everything here goes through `rest/v1/rpc/...` rather than table reads: invite
/// creation enforces the client limit, redemption needs to read a row the redeemer
/// cannot see, and the roster is an aggregate that would otherwise be a dozen
/// round trips.
@MainActor
final class CoachService: ObservableObject {

    static let shared = CoachService()

    @Published private(set) var clients: [CoachClient] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasCoachRecord = false
    @Published var errorMessage: String?

    /// Kept separate from `errorMessage` because the roster screen renders that one as a
    /// banner: a client history that fails to load must not surface as a roster-wide
    /// failure the user sees after navigating back.
    @Published private(set) var sessionsErrorMessage: String?

    private init() {}

    var isAvailable: Bool {
        AppEnvironment.isSupabaseConfigured && AuthService.shared.session != nil
    }

    // MARK: Roster

    func refreshRoster() async {
        guard isAvailable, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rows: [RosterRow] = try await rpc("coach_roster", body: EmptyBody())
            clients = CoachTriage.sorted(rows.map(\.asClient))
            hasCoachRecord = true
        } catch let error as CoachError {
            if case .requestFailed(_, let detail) = error, detail?.contains("NOT_A_COACH") == true {
                hasCoachRecord = false
            } else {
                errorMessage = Self.userFacingMessage(for: error)
            }
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    /// Creates the caller's `coaches` row. Idempotent: re-running just updates names.
    func ensureCoachRecord(displayName: String?, businessName: String?) async {
        guard isAvailable, let session = AuthService.shared.session else { return }

        struct CoachRow: Encodable {
            let user_id: String
            let display_name: String?
            let business_name: String?
        }

        do {
            try await postUpsert(
                path: "coaches",
                body: [CoachRow(
                    user_id: session.user.id,
                    display_name: displayName,
                    business_name: businessName
                )]
            )
            hasCoachRecord = true
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    // MARK: Invites

    /// Returns a code the coach reads out or texts to the client.
    func createInvite(label: String?) async -> String? {
        guard isAvailable else { return nil }
        errorMessage = nil

        struct Args: Encodable { let label: String? }

        do {
            // The function returns a bare string, which PostgREST sends as a JSON scalar.
            let code: String = try await rpc("create_coach_invite", body: Args(label: label))
            return code
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return nil
        }
    }

    /// The client half: links this account to whoever issued the code.
    func redeemInvite(code: String) async -> String? {
        guard isAvailable else { return nil }
        errorMessage = nil

        struct Args: Encodable { let invite_code: String }
        struct Result: Decodable { let coach_name: String? }

        do {
            let rows: [Result] = try await rpc(
                "redeem_coach_invite",
                body: Args(invite_code: code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
            )
            return rows.first?.coach_name ?? "your coach"
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return nil
        }
    }

    // MARK: Client history

    /// One client's sessions, newest first, with per-rep detail embedded.
    ///
    /// A table read rather than an RPC: the "Coaches read linked client analyses"
    /// policy already scopes this to actively linked clients, and the roster RPC
    /// deliberately returns aggregates. The explicit `user_id` filter is redundant with
    /// that policy and stays anyway, so a policy edit cannot quietly widen it.
    ///
    /// Returns nil only when a request actually failed, so the caller can tell "nothing
    /// yet" from "couldn't load"; `sessionsErrorMessage` carries the reason. A build with
    /// no backend configured has nothing to ask for and returns an empty history instead,
    /// because reporting a network failure there would be a lie the user can't act on.
    func fetchSessions(for clientUserID: String, limit: Int = 50) async -> [CoachClientSession]? {
        sessionsErrorMessage = nil

        guard isAvailable,
              let baseURL = AppEnvironment.supabaseURL,
              let anonKey = AppEnvironment.supabaseAnonKey else { return [] }

        await AuthService.shared.refreshSessionIfNeeded()
        guard let session = AuthService.shared.session else { return [] }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/analysis_records"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "*,analysis_reps(*)"),
            URLQueryItem(name: "user_id", value: "eq.\(clientUserID)"),
            URLQueryItem(name: "order", value: "recorded_at.desc"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CoachError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let detail = (try? JSONDecoder().decode(PostgrestErrorPayload.self, from: data))?.message
                throw CoachError.requestFailed(status: http.statusCode, detail: detail)
            }

            let decoder = JSONDecoder()
            // Postgres timestamps carry microseconds, which Foundation's `.iso8601`
            // rejects — the trap that broke Sign in with Apple in 3.5.3.
            decoder.dateDecodingStrategy = ISO8601Timestamp.decodingStrategy
            let rows = try decoder.decode([RemoteAnalysisRecord].self, from: data)
            return rows.map(\.asClientSession)
        } catch {
            sessionsErrorMessage = Self.userFacingMessage(for: error)
            logger.error("Client history failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Ends a link. Either side may do this; the policy allows both.
    func removeClient(_ client: CoachClient) async {
        guard isAvailable,
              let baseURL = AppEnvironment.supabaseURL,
              let anonKey = AppEnvironment.supabaseAnonKey,
              let session = AuthService.shared.session else { return }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/coach_clients"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "coach_user_id", value: "eq.\(session.user.id)"),
            URLQueryItem(name: "client_user_id", value: "eq.\(client.clientUserID)")
        ]
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        _ = try? await URLSession.shared.data(for: request)
        await refreshRoster()
    }

    // MARK: - Transport

    private struct EmptyBody: Encodable {}

    private func rpc<Body: Encodable, Response: Decodable>(
        _ function: String,
        body: Body
    ) async throws -> Response {
        guard let baseURL = AppEnvironment.supabaseURL,
              let anonKey = AppEnvironment.supabaseAnonKey else {
            throw CoachError.notConfigured
        }

        await AuthService.shared.refreshSessionIfNeeded()
        guard let session = AuthService.shared.session else {
            throw CoachError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/\(function)"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CoachError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(PostgrestErrorPayload.self, from: data))?.message
            throw CoachError.requestFailed(status: http.statusCode, detail: detail)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = ISO8601Timestamp.decodingStrategy
        return try decoder.decode(Response.self, from: data)
    }

    private func postUpsert<Body: Encodable>(path: String, body: [Body]) async throws {
        guard let baseURL = AppEnvironment.supabaseURL,
              let anonKey = AppEnvironment.supabaseAnonKey,
              let session = AuthService.shared.session else {
            throw CoachError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/\(path)"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CoachError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(PostgrestErrorPayload.self, from: data))?.message
            throw CoachError.requestFailed(status: http.statusCode, detail: detail)
        }
    }

    enum CoachError: LocalizedError {
        case notConfigured
        case invalidResponse
        case requestFailed(status: Int, detail: String?)
    }

    /// The RPCs raise named exceptions (`INVITE_EXPIRED`, `CLIENT_LIMIT_REACHED`)
    /// rather than prose, so the wording lives here where it can be edited without a
    /// migration.
    static func userFacingMessage(for error: Error) -> String {
        if let coachError = error as? CoachError {
            switch coachError {
            case .notConfigured:
                return withReference("Coaching features aren't available right now.", "COACH-CONFIG")
            case .invalidResponse:
                return withReference("The server returned an unexpected response.", "COACH-RESP")
            case .requestFailed(let status, let detail):
                let detail = detail ?? ""
                if detail.contains("INVITE_NOT_FOUND") {
                    return withReference("That code doesn't match an invite. Check for typos and try again.", "COACH-INVITE-404")
                }
                if detail.contains("INVITE_ALREADY_USED") {
                    return withReference("That invite has already been used. Ask your coach for a new code.", "COACH-INVITE-USED")
                }
                if detail.contains("INVITE_EXPIRED") {
                    return withReference("That invite has expired. Ask your coach for a new code.", "COACH-INVITE-EXP")
                }
                if detail.contains("INVITE_SELF") {
                    return withReference("That's your own invite code — send it to your client instead.", "COACH-INVITE-SELF")
                }
                if detail.contains("CLIENT_LIMIT_REACHED") {
                    return withReference("You've reached the client limit for your plan. Remove a client or upgrade to add more.", "COACH-LIMIT")
                }
                if detail.contains("NOT_A_COACH") {
                    return withReference("This account isn't set up as a coach yet.", "COACH-NOTCOACH")
                }
                return withReference("Something went wrong talking to your roster. Please try again.", "COACH-\(status)")
            }
        }
        if let urlError = error as? URLError {
            return withReference("You appear to be offline. Check your connection and try again.", "NET-\(urlError.errorCode)")
        }
        let nsError = error as NSError
        return withReference("Something went wrong. Please try again.", "\(nsError.domain)-\(nsError.code)")
    }

    private static func withReference(_ message: String, _ reference: String) -> String {
        "\(message)\n\nError code: \(reference)"
    }
}

private struct PostgrestErrorPayload: Decodable {
    let message: String?
}

/// Reuses the restore path's lenient row decoder rather than declaring a second one.
///
/// Both jobs are the same job — reading `analysis_records` written by some other build
/// of the app — and the only difference is where the result goes. A coach's copy stops
/// at a plain struct; the owner's copy becomes an `AnalysisRecord`.
extension RemoteAnalysisRecord {

    var asClientSession: CoachClientSession {
        CoachClientSession(
            id: id,
            date: recorded_at,
            kind: kind.flatMap(AnalysisKind.init(rawValue:)) ?? .exercise,
            movementName: movement_name ?? movement_key ?? "Session",
            totalReps: total_reps ?? 0,
            score: score,
            grade: grade.flatMap(LetterGrade.init(rawValue:)),
            meanPeakAngle: mean_peak_angle_deg,
            poseDetectionRate: pose_detection_rate ?? 0,
            asymmetryDeg: asymmetry_deg,
            asymmetryFlag: asymmetry_flag ?? false,
            insights: insights ?? [],
            details: details ?? [],
            reps: (analysis_reps ?? [])
                .sorted { $0.rep_number < $1.rep_number }
                .map(\.metric)
        )
    }
}

/// Wire shape of one `coach_roster()` row.
private struct RosterRow: Decodable {
    let client_user_id: String
    let display_name: String?
    let status: String
    let linked_at: Date
    let last_session_at: Date?
    let sessions_last_14_days: Int
    let latest_score: Int?
    let previous_score: Int?
    let latest_movement: String?
    let open_asymmetry_flag: Bool

    var asClient: CoachClient {
        CoachClient(
            clientUserID: client_user_id,
            displayName: display_name ?? "Client",
            status: status,
            linkedAt: linked_at,
            lastSessionAt: last_session_at,
            sessionsLast14Days: sessions_last_14_days,
            latestScore: latest_score,
            previousScore: previous_score,
            latestMovement: latest_movement,
            openAsymmetryFlag: open_asymmetry_flag
        )
    }
}
