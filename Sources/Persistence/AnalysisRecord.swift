import Foundation
import SwiftData

/// Where an analysis came from.
enum AnalysisSource: String, Codable, CaseIterable {
    case savedVideo
    case liveCamera

    var displayName: String {
        switch self {
        case .savedVideo: return "Uploaded"
        case .liveCamera: return "Live"
        }
    }
}

/// Exercise vs. assessment. Both land in the same table so the Progress tab, CSV
/// export, and metrics sync each have a single timeline to work against instead of
/// merging two parallel stores.
enum AnalysisKind: String, Codable, CaseIterable {
    case exercise
    case assessment
}

/// Codable mirror of `AssessmentMetrics.subGrades`, which is an array of tuples and
/// therefore not encodable as-is.
struct SubGrade: Codable, Hashable {
    let label: String
    let grade: LetterGrade
}

/// The parts of an analysis result that are read back whole rather than queried or
/// charted. Stored as one JSON blob on the record; the values the Progress tab sorts,
/// filters, and plots are denormalized into columns alongside it.
///
/// This is also the wire format for metrics sync — `SyncService` posts the same shape.
struct AnalysisPayload: Codable {
    var averageAngles: [JointAngle] = []
    var tempoBreakdown: [String: Double] = [:]
    var perRepMetrics: [RepMetric] = []
    var subGrades: [SubGrade] = []
    var details: [String] = []
    var insights: [String] = []
}

/// One completed analysis, exercise or assessment.
///
/// Replaces the unused `WorkoutResult` scaffold: before this existed, every
/// `AnalysisSummary` and `AssessmentMetrics` lived in a SwiftUI `@State` and was
/// discarded when the view dismissed, so the Progress tab had nothing to show and
/// no trend could be computed across sessions.
@Model
final class AnalysisRecord {

    /// Stable identifier shared with the backend row and the media file names.
    /// Named `recordID` rather than `id` so it does not collide with the `id`
    /// that `PersistentModel` already supplies for SwiftUI identity.
    @Attribute(.unique) var recordID: UUID
    var date: Date

    var kindRaw: String
    /// `ExerciseType.rawValue` or `AssessmentType.rawValue`. Stable across renames of
    /// the display name, and what trend queries group by.
    var movementKey: String
    var movementName: String
    var sideRaw: String
    var planeRaw: String?
    var sourceRaw: String

    var duration: Double
    var poseDetectionRate: Double

    // Exercise columns. Zero / nil on assessment records.
    var totalReps: Int
    var finalScore: Int?
    /// Mean of the per-rep peak flexion angles — the depth signal the trend chart plots.
    var meanPeakAngle: Double?
    var meanEccentric: Double?
    var meanConcentric: Double?

    // Assessment columns. Nil on exercise records.
    var gradeRaw: String?
    var leftROM: Double?
    var rightROM: Double?
    var asymmetryDeg: Double?
    var asymmetryFlag: Bool

    var payloadData: Data

    /// File names (not paths) inside `AnalysisStorage.mediaDirectory`. Storing the
    /// name rather than an absolute URL survives the container path changing between
    /// installs and OS upgrades, which would otherwise orphan every video.
    var videoFileName: String?
    var thumbnailFileName: String?

    /// Set once the record's metrics have been accepted by Supabase. Video is never
    /// part of that upload.
    var syncedAt: Date?

    init(
        recordID: UUID = UUID(),
        date: Date = Date(),
        kind: AnalysisKind,
        movementKey: String,
        movementName: String,
        side: BodySide,
        plane: ViewPlane? = nil,
        source: AnalysisSource,
        duration: Double,
        poseDetectionRate: Double,
        totalReps: Int = 0,
        finalScore: Int? = nil,
        meanPeakAngle: Double? = nil,
        meanEccentric: Double? = nil,
        meanConcentric: Double? = nil,
        grade: LetterGrade? = nil,
        leftROM: Double? = nil,
        rightROM: Double? = nil,
        asymmetryDeg: Double? = nil,
        asymmetryFlag: Bool = false,
        payload: AnalysisPayload,
        videoFileName: String? = nil,
        thumbnailFileName: String? = nil
    ) {
        self.recordID = recordID
        self.date = date
        self.kindRaw = kind.rawValue
        self.movementKey = movementKey
        self.movementName = movementName
        self.sideRaw = side.rawValue
        self.planeRaw = plane?.rawValue
        self.sourceRaw = source.rawValue
        self.duration = duration
        self.poseDetectionRate = poseDetectionRate
        self.totalReps = totalReps
        self.finalScore = finalScore
        self.meanPeakAngle = meanPeakAngle
        self.meanEccentric = meanEccentric
        self.meanConcentric = meanConcentric
        self.gradeRaw = grade?.rawValue
        self.leftROM = leftROM
        self.rightROM = rightROM
        self.asymmetryDeg = asymmetryDeg
        self.asymmetryFlag = asymmetryFlag
        self.payloadData = (try? JSONEncoder().encode(payload)) ?? Data()
        self.videoFileName = videoFileName
        self.thumbnailFileName = thumbnailFileName
        self.syncedAt = nil
    }
}

// MARK: - Typed accessors

extension AnalysisRecord {

    var kind: AnalysisKind { AnalysisKind(rawValue: kindRaw) ?? .exercise }
    var side: BodySide { BodySide(rawValue: sideRaw) ?? .left }
    var plane: ViewPlane? { planeRaw.flatMap(ViewPlane.init(rawValue:)) }
    var source: AnalysisSource { AnalysisSource(rawValue: sourceRaw) ?? .savedVideo }
    var grade: LetterGrade? { gradeRaw.flatMap(LetterGrade.init(rawValue:)) }

    var exerciseType: ExerciseType? {
        kind == .exercise ? ExerciseType(rawValue: movementKey) : nil
    }

    var assessmentType: AssessmentType? {
        kind == .assessment ? AssessmentType(rawValue: movementKey) : nil
    }

    var payload: AnalysisPayload {
        (try? JSONDecoder().decode(AnalysisPayload.self, from: payloadData)) ?? AnalysisPayload()
    }

    var perRepMetrics: [RepMetric] { payload.perRepMetrics }

    var videoURL: URL? { videoFileName.flatMap(AnalysisStorage.url(forFileName:)) }
    var thumbnailURL: URL? { thumbnailFileName.flatMap(AnalysisStorage.url(forFileName:)) }

    /// Average tempo across the set, formatted like the per-rep strings ("3-1-2-1").
    var averageTempoString: String? {
        let reps = perRepMetrics
        guard !reps.isEmpty else { return nil }
        let n = Double(reps.count)
        return TempoDurationFormatter.string(
            eccentric: reps.reduce(0) { $0 + $1.eccentricDuration } / n,
            pauseBottom: reps.reduce(0) { $0 + $1.pauseBottomDuration } / n,
            concentric: reps.reduce(0) { $0 + $1.concentricDuration } / n,
            pauseTop: reps.reduce(0) { $0 + $1.pauseTopDuration } / n
        )
    }

    /// Short line used in the history list and share text.
    var summaryLine: String {
        switch kind {
        case .exercise:
            var parts = ["\(totalReps) rep\(totalReps == 1 ? "" : "s")"]
            if let finalScore { parts.append("score \(finalScore)") }
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

// MARK: - Building records from analysis output

extension AnalysisRecord {

    /// Builds a record from a completed exercise analysis.
    static func exercise(
        summary: AnalysisSummary,
        exerciseType: ExerciseType,
        side: BodySide,
        source: AnalysisSource,
        insights: [String],
        recordID: UUID = UUID(),
        date: Date = Date()
    ) -> AnalysisRecord {
        let reps = summary.perRepMetrics
        let peaks = reps.map(\.peakFlexionAngle).filter { $0.isFinite && $0 < 1000 }

        var payload = AnalysisPayload()
        payload.averageAngles = summary.averageAngles
        payload.tempoBreakdown = Dictionary(
            uniqueKeysWithValues: summary.tempoBreakdown.map { ($0.key.rawValue, $0.value) }
        )
        payload.perRepMetrics = reps
        payload.insights = insights

        return AnalysisRecord(
            recordID: recordID,
            date: date,
            kind: .exercise,
            movementKey: exerciseType.rawValue,
            movementName: ExerciseConfig.all.first { $0.type == exerciseType }?.displayName
                ?? exerciseType.rawValue,
            side: side,
            source: source,
            duration: summary.duration,
            poseDetectionRate: Double(summary.poseDetectionRate),
            totalReps: summary.totalReps,
            finalScore: summary.finalScore,
            meanPeakAngle: peaks.isEmpty
                ? nil
                : Double(peaks.reduce(0, +) / Float(peaks.count)),
            meanEccentric: reps.isEmpty
                ? nil
                : reps.reduce(0) { $0 + $1.eccentricDuration } / Double(reps.count),
            meanConcentric: reps.isEmpty
                ? nil
                : reps.reduce(0) { $0 + $1.concentricDuration } / Double(reps.count),
            payload: payload
        )
    }

    /// Builds a record from a completed assessment.
    static func assessment(
        metrics: AssessmentMetrics,
        assessmentType: AssessmentType,
        plane: ViewPlane,
        side: BodySide,
        source: AnalysisSource,
        duration: Double,
        poseDetectionRate: Float,
        insights: [String],
        recordID: UUID = UUID(),
        date: Date = Date()
    ) -> AnalysisRecord {
        var payload = AnalysisPayload()
        payload.subGrades = metrics.subGrades.map { SubGrade(label: $0.label, grade: $0.grade) }
        payload.details = metrics.details
        payload.insights = insights

        return AnalysisRecord(
            recordID: recordID,
            date: date,
            kind: .assessment,
            movementKey: assessmentType.rawValue,
            movementName: assessmentType.rawValue,
            side: side,
            plane: plane,
            source: source,
            duration: duration,
            poseDetectionRate: Double(poseDetectionRate),
            grade: metrics.grade,
            leftROM: metrics.leftROM.map(Double.init),
            rightROM: metrics.rightROM.map(Double.init),
            asymmetryDeg: metrics.asymmetryDeg.map(Double.init),
            asymmetryFlag: metrics.asymmetryFlag,
            payload: payload
        )
    }
}
