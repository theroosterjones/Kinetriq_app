import Foundation

/// Persisted workout result that can be saved to SwiftData.
struct WorkoutResult: Codable, Identifiable {
    let id: UUID
    let exerciseType: ExerciseType
    let side: BodySide
    let date: Date
    let totalReps: Int
    let duration: Double
    let averageAngles: [JointAngle]
    let tempoBreakdown: [String: Double]  // TempoPhase.rawValue → seconds
    let perRepMetrics: [RepMetric]
    let finalScore: Int?
    let inputVideoURL: String?
    let outputVideoURL: String?

    init(from summary: AnalysisSummary, exerciseType: ExerciseType, side: BodySide,
         inputVideoURL: URL? = nil, outputVideoURL: URL? = nil) {
        self.id = UUID()
        self.exerciseType = exerciseType
        self.side = side
        self.date = Date()
        self.totalReps = summary.totalReps
        self.duration = summary.duration
        self.averageAngles = summary.averageAngles
        self.tempoBreakdown = Dictionary(
            uniqueKeysWithValues: summary.tempoBreakdown.map { ($0.key.rawValue, $0.value) }
        )
        self.perRepMetrics = summary.perRepMetrics
        self.finalScore = summary.finalScore
        self.inputVideoURL = inputVideoURL?.path
        self.outputVideoURL = outputVideoURL?.path
    }
}
