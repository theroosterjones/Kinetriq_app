import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.kevinjones.Kinetriq", category: "SyncService")

/// Uploads analysis **measurements** to Supabase so history survives a reinstall and
/// can later be read by a coach.
///
/// Video never takes this path. Analyzed clips stay in the app container on the
/// device; what leaves is joint angles, rep counts, tempo, scores, and grades. The
/// backing tables have no video column by design — see the comment above
/// `analysis_records` in `supabase/schema.sql`.
///
/// These are the app's first `rest/v1` calls. Everything before this spoke only to
/// `auth/v1` and one Edge Function.
@MainActor
final class SyncService: ObservableObject {

    static let shared = SyncService()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastErrorMessage: String?

    /// Sessions pulled down by the most recent restore, so Settings can confirm that
    /// something actually came back rather than leaving the user guessing.
    @Published private(set) var lastRestoredCount = 0

    /// User-facing opt-out. Defaults to on, but a coach handling client video may
    /// reasonably want nothing at all leaving the device, and saying no should cost
    /// them nothing but cross-device history.
    private static let enabledKey = "kinetriq.sync.enabled"

    var isEnabledByUser: Bool {
        get {
            UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            objectWillChange.send()
        }
    }

    /// Sync requires a real backend session. When Supabase isn't configured the app
    /// mints a local development session, and there is nothing to talk to.
    var isAvailable: Bool {
        AppEnvironment.isSupabaseConfigured && AuthService.shared.session != nil
    }

    private init() {}

    // MARK: - Public entry points

    /// Uploads everything not yet accepted by the backend. Safe to call often —
    /// it no-ops when there is nothing pending, and upserts are idempotent.
    func syncPending(context: ModelContext) async {
        guard isEnabledByUser, isAvailable, !isSyncing else { return }

        let pending = AnalysisLibrary.fetchUnsynced(from: context)
        guard !pending.isEmpty else { return }

        await upload(pending, context: context)
    }

    /// Re-uploads the whole library. Used by the manual "Sync now" action, which is
    /// also the recovery path if a device was offline for a long stretch.
    func syncAll(context: ModelContext) async {
        guard isEnabledByUser, isAvailable, !isSyncing else { return }
        await upload(AnalysisLibrary.fetchAll(from: context), context: context)
        // A failed upload almost always means a rejected token or an unreachable
        // backend, so pulling immediately after would fail the same way and replace
        // the message the user needs to see.
        guard lastErrorMessage == nil else { return }
        await restore(context: context)
    }

    // MARK: - Restore

    /// Set once a restore has completed for a given user, so a genuinely empty
    /// history isn't re-fetched on every launch.
    private static func restoreKey(for userID: String) -> String {
        "kinetriq.sync.restored.\(userID)"
    }

    /// Pulls down measurements this device does not have.
    ///
    /// Without this, sync was write-only: a user who reinstalled — or signed in on a
    /// second device — saw an empty Progress tab while every row sat in Postgres. To
    /// someone who just paid, that reads as data loss.
    ///
    /// **Video does not come back**, because it never went up. Restored sessions carry
    /// their measurements and no clip, and the UI says so rather than presenting a
    /// broken player.
    func restoreIfNeeded(context: ModelContext) async {
        guard isEnabledByUser, isAvailable, !isSyncing,
              let userID = AuthService.shared.session?.user.id else { return }

        let alreadyRestored = UserDefaults.standard.bool(forKey: Self.restoreKey(for: userID))
        // A fresh install has an empty store, which is the case worth catching. Once a
        // restore has run, only an explicit "Sync now" pulls again.
        guard !alreadyRestored || AnalysisLibrary.isEmpty(in: context) else { return }

        await restore(context: context)
    }

    /// Page size for the download. Each row carries its reps embedded, so these are
    /// larger than the upload batches.
    private static let restorePageSize = 100

    /// Hard stop on paging. Nobody has 5,000 analyzed sets, so hitting this means the
    /// server is ignoring `offset` and the loop would otherwise never end.
    private static let restoreMaxPages = 50

    private func restore(context: ModelContext) async {
        isSyncing = true
        lastErrorMessage = nil
        defer { isSyncing = false }

        await AuthService.shared.refreshSessionIfNeeded()
        guard let session = AuthService.shared.session else { return }

        var existingIDs = Set(AnalysisLibrary.fetchAll(from: context).map(\.recordID))
        var offset = 0
        var restoredCount = 0

        for _ in 0..<Self.restoreMaxPages {
            let page: [RemoteAnalysisRecord]
            do {
                page = try await fetchPage(
                    offset: offset,
                    token: session.accessToken,
                    userID: session.user.id
                )
            } catch {
                lastErrorMessage = Self.userFacingMessage(for: error)
                logger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
                return
            }

            for remote in page {
                guard let remoteID = remote.recordID,
                      !existingIDs.contains(remoteID),
                      let record = remote.makeRecord() else { continue }
                // Already on the server by definition, so don't queue it for upload.
                record.syncedAt = Date()
                context.insert(record)
                existingIDs.insert(remoteID)
                restoredCount += 1
            }

            if page.count < Self.restorePageSize { break }
            offset += Self.restorePageSize
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: Self.restoreKey(for: session.user.id))
            lastSyncedAt = Date()
            lastRestoredCount = restoredCount
            if restoredCount > 0 {
                logger.info("Restored \(restoredCount, privacy: .public) sessions from the account")
            }
        } catch {
            lastErrorMessage = Self.userFacingMessage(for: error)
        }
    }

    /// Fetches one page of records with their reps embedded, so a session and its
    /// per-rep detail arrive together rather than in N+1 requests.
    private func fetchPage(
        offset: Int,
        token: String,
        userID: String
    ) async throws -> [RemoteAnalysisRecord] {
        guard let baseURL = AppEnvironment.supabaseURL,
              let anonKey = AppEnvironment.supabaseAnonKey else {
            throw SyncError.notConfigured
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/analysis_records"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "*,analysis_reps(*)"),
            // Redundant with RLS, but an explicit filter means a policy change can
            // never quietly widen what this device pulls down.
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "order", value: "recorded_at.desc"),
            URLQueryItem(name: "limit", value: "\(Self.restorePageSize)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]

        guard let url = components?.url else { throw SyncError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(PostgrestError.self, from: data))?.message
            throw SyncError.requestFailed(status: http.statusCode, detail: detail)
        }

        let decoder = JSONDecoder()
        // Postgres timestamps carry microseconds. Foundation's `.iso8601` rejects
        // fractional seconds — the same trap that broke Sign in with Apple in 3.5.3.
        decoder.dateDecodingStrategy = ISO8601Timestamp.decodingStrategy
        return try decoder.decode([RemoteAnalysisRecord].self, from: data)
    }

    // MARK: - Upload

    /// Upload in batches so one very large history doesn't become one very large
    /// request that times out and retries forever.
    private static let batchSize = 25

    private func upload(_ records: [AnalysisRecord], context: ModelContext) async {
        isSyncing = true
        lastErrorMessage = nil
        defer { isSyncing = false }

        // The access token may have expired while the app was backgrounded; a 401
        // here would otherwise look like a sync failure.
        await AuthService.shared.refreshSessionIfNeeded()

        guard let session = AuthService.shared.session else { return }
        let token = session.accessToken
        let userID = session.user.id

        for batch in records.chunked(into: Self.batchSize) {
            let recordPayloads = batch.map {
                AnalysisRecordPayload(record: $0, userID: userID)
            }
            let repPayloads = batch.flatMap { record in
                record.perRepMetrics.map {
                    AnalysisRepPayload(record: record, rep: $0, userID: userID)
                }
            }

            do {
                try await postUpsert(path: "analysis_records", body: recordPayloads, token: token)
                if !repPayloads.isEmpty {
                    try await postUpsert(path: "analysis_reps", body: repPayloads, token: token)
                }

                let now = Date()
                for record in batch { record.syncedAt = now }
                try? context.save()
                lastSyncedAt = now
            } catch {
                lastErrorMessage = Self.userFacingMessage(for: error)
                logger.error("Sync batch failed: \(error.localizedDescription, privacy: .public)")
                // Stop on the first failure rather than hammering a backend that is
                // down or a token that is bad. The next foreground will try again.
                return
            }
        }
    }

    private func postUpsert<Body: Encodable>(
        path: String,
        body: [Body],
        token: String
    ) async throws {
        guard let baseURL = AppEnvironment.supabaseURL,
              let anonKey = AppEnvironment.supabaseAnonKey else {
            throw SyncError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/\(path)"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // `merge-duplicates` makes this an upsert on the primary key, so a retried
        // batch updates the existing rows instead of failing on a conflict.
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(PostgrestError.self, from: data))?.message
            throw SyncError.requestFailed(status: http.statusCode, detail: detail)
        }
    }

    // MARK: - Errors

    enum SyncError: LocalizedError {
        case notConfigured
        case invalidResponse
        case requestFailed(status: Int, detail: String?)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Progress sync is not configured."
            case .invalidResponse:
                return "The server returned an unexpected response."
            case .requestFailed(let status, let detail):
                return detail ?? "The server rejected the upload (HTTP \(status))."
            }
        }
    }

    /// Plain-language message plus a screenshot-able code, matching the pattern
    /// `AuthService` and `PurchaseService` already use.
    static func userFacingMessage(for error: Error) -> String {
        if let syncError = error as? SyncError {
            switch syncError {
            case .notConfigured:
                return withReference("Progress sync isn't available right now.", "SYNC-CONFIG")
            case .invalidResponse:
                return withReference("The server returned an unexpected response.", "SYNC-RESP")
            case .requestFailed(let status, _):
                if status == 401 || status == 403 {
                    return withReference("Your session expired. Sign out and back in to resume syncing.", "SYNC-\(status)")
                }
                return withReference("Your progress couldn't be saved to your account. It's still on this device and will retry automatically.", "SYNC-\(status)")
            }
        }
        if let urlError = error as? URLError {
            return withReference("You appear to be offline. Progress is saved on this device and will sync later.", "NET-\(urlError.errorCode)")
        }
        let nsError = error as NSError
        return withReference("Your progress couldn't be saved to your account right now.", "\(nsError.domain)-\(nsError.code)")
    }

    private static func withReference(_ message: String, _ reference: String) -> String {
        "\(message)\n\nError code: \(reference)"
    }
}

// MARK: - Wire format

private struct PostgrestError: Decodable {
    let message: String?
}

/// Row shape for `analysis_records`. Snake-case keys match the SQL columns.
struct AnalysisRecordPayload: Encodable {
    let id: String
    let user_id: String
    let recorded_at: Date
    let kind: String
    let movement_key: String
    let movement_name: String
    let side: String
    let plane: String?
    let source: String
    let duration_seconds: Double
    let pose_detection_rate: Double
    let total_reps: Int
    let score: Int?
    let mean_peak_angle_deg: Double?
    let mean_eccentric_seconds: Double?
    let mean_concentric_seconds: Double?
    let grade: String?
    let left_rom_deg: Double?
    let right_rom_deg: Double?
    let asymmetry_deg: Double?
    let asymmetry_flag: Bool
    let average_angles: [JointAngle]
    let tempo_breakdown: [String: Double]
    let sub_grades: [SubGrade]
    let details: [String]
    let insights: [String]
    let app_version: String?

    init(record: AnalysisRecord, userID: String) {
        let payload = record.payload
        self.id = record.recordID.uuidString
        self.user_id = userID
        self.recorded_at = record.date
        self.kind = record.kindRaw
        self.movement_key = record.movementKey
        self.movement_name = record.movementName
        self.side = record.sideRaw
        self.plane = record.planeRaw
        self.source = record.sourceRaw
        self.duration_seconds = record.duration
        self.pose_detection_rate = record.poseDetectionRate
        self.total_reps = record.totalReps
        self.score = record.finalScore
        self.mean_peak_angle_deg = record.meanPeakAngle
        self.mean_eccentric_seconds = record.meanEccentric
        self.mean_concentric_seconds = record.meanConcentric
        self.grade = record.gradeRaw
        self.left_rom_deg = record.leftROM
        self.right_rom_deg = record.rightROM
        self.asymmetry_deg = record.asymmetryDeg
        self.asymmetry_flag = record.asymmetryFlag
        self.average_angles = payload.averageAngles
        self.tempo_breakdown = payload.tempoBreakdown
        self.sub_grades = payload.subGrades
        self.details = payload.details
        self.insights = payload.insights
        self.app_version = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}

/// A record as it comes back from PostgREST, with its reps embedded.
///
/// Deliberately separate from `AnalysisRecordPayload` rather than making that type
/// `Codable`. The upload side is lossless because the device has everything; the
/// download side has to cope with rows written by an older or newer build, so every
/// field here is optional and defaulted. One type doing both jobs would quietly make
/// the upload side lenient too.
struct RemoteAnalysisRecord: Decodable {
    let id: String
    let recorded_at: Date
    let kind: String?
    let movement_key: String?
    let movement_name: String?
    let side: String?
    let plane: String?
    let source: String?
    let duration_seconds: Double?
    let pose_detection_rate: Double?
    let total_reps: Int?
    let score: Int?
    let mean_peak_angle_deg: Double?
    let mean_eccentric_seconds: Double?
    let mean_concentric_seconds: Double?
    let grade: String?
    let left_rom_deg: Double?
    let right_rom_deg: Double?
    let asymmetry_deg: Double?
    let asymmetry_flag: Bool?
    let average_angles: [JointAngle]?
    let tempo_breakdown: [String: Double]?
    let sub_grades: [SubGrade]?
    let details: [String]?
    let insights: [String]?
    let analysis_reps: [RemoteAnalysisRep]?

    var recordID: UUID? { UUID(uuidString: id) }

    /// Rebuilds the local model. Returns nil only when the row is unusable — a bad
    /// UUID or a missing movement key — because a partial record in the Progress tab
    /// is worse than an absent one.
    func makeRecord() -> AnalysisRecord? {
        guard let recordID,
              let movementKey = movement_key,
              !movementKey.isEmpty else { return nil }

        var payload = AnalysisPayload()
        payload.averageAngles = average_angles ?? []
        payload.tempoBreakdown = tempo_breakdown ?? [:]
        payload.subGrades = sub_grades ?? []
        payload.details = details ?? []
        payload.insights = insights ?? []
        payload.perRepMetrics = (analysis_reps ?? [])
            .sorted { $0.rep_number < $1.rep_number }
            .map(\.metric)

        return AnalysisRecord(
            recordID: recordID,
            date: recorded_at,
            kind: kind.flatMap(AnalysisKind.init(rawValue:)) ?? .exercise,
            movementKey: movementKey,
            movementName: movement_name ?? movementKey,
            side: side.flatMap(BodySide.init(rawValue:)) ?? .left,
            plane: plane.flatMap(ViewPlane.init(rawValue:)),
            source: source.flatMap(AnalysisSource.init(rawValue:)) ?? .savedVideo,
            duration: duration_seconds ?? 0,
            poseDetectionRate: pose_detection_rate ?? 0,
            totalReps: total_reps ?? 0,
            finalScore: score,
            meanPeakAngle: mean_peak_angle_deg,
            meanEccentric: mean_eccentric_seconds,
            meanConcentric: mean_concentric_seconds,
            grade: grade.flatMap(LetterGrade.init(rawValue:)),
            leftROM: left_rom_deg,
            rightROM: right_rom_deg,
            asymmetryDeg: asymmetry_deg,
            asymmetryFlag: asymmetry_flag ?? false,
            payload: payload
            // videoFileName and thumbnailFileName stay nil: video never synced, so
            // there is nothing on this device to point at.
        )
    }
}

struct RemoteAnalysisRep: Decodable {
    let rep_number: Int
    let peak_flexion_angle_deg: Double?
    let eccentric_seconds: Double?
    let pause_bottom_seconds: Double?
    let concentric_seconds: Double?
    let pause_top_seconds: Double?

    var metric: RepMetric {
        RepMetric(
            repNumber: rep_number,
            // Restores the collector's "never measured" sentinel that upload nils out,
            // so downstream code keeps treating it as absent rather than as 0°.
            peakFlexionAngle: peak_flexion_angle_deg.map(Float.init) ?? .greatestFiniteMagnitude,
            eccentricDuration: eccentric_seconds ?? 0,
            pauseBottomDuration: pause_bottom_seconds ?? 0,
            concentricDuration: concentric_seconds ?? 0,
            pauseTopDuration: pause_top_seconds ?? 0
        )
    }
}

/// Row shape for `analysis_reps`.
struct AnalysisRepPayload: Encodable {
    let record_id: String
    let user_id: String
    let rep_number: Int
    let peak_flexion_angle_deg: Double?
    let eccentric_seconds: Double
    let pause_bottom_seconds: Double
    let concentric_seconds: Double
    let pause_top_seconds: Double

    init(record: AnalysisRecord, rep: RepMetric, userID: String) {
        self.record_id = record.recordID.uuidString
        self.user_id = userID
        self.rep_number = rep.repNumber
        // `.greatestFiniteMagnitude` is the collector's "never measured" sentinel and
        // is not valid JSON, so it must not reach the encoder.
        self.peak_flexion_angle_deg = (rep.peakFlexionAngle.isFinite && rep.peakFlexionAngle < 1000)
            ? Double(rep.peakFlexionAngle)
            : nil
        self.eccentric_seconds = rep.eccentricDuration.isFinite ? rep.eccentricDuration : 0
        self.pause_bottom_seconds = rep.pauseBottomDuration.isFinite ? rep.pauseBottomDuration : 0
        self.concentric_seconds = rep.concentricDuration.isFinite ? rep.concentricDuration : 0
        self.pause_top_seconds = rep.pauseTopDuration.isFinite ? rep.pauseTopDuration : 0
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
