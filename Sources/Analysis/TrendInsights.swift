import Foundation

/// One session reduced to the handful of numbers that mean something across a
/// training block.
///
/// Kept free of SwiftData so the heuristics below can be unit-tested against plain
/// values, the same way `CoachingInsights` is tested against `AnalysisSummary`.
struct TrendSample {
    let date: Date
    let kind: AnalysisKind
    let totalReps: Int
    let score: Int?
    let meanPeakAngle: Double?
    let meanEccentric: Double?
    let meanConcentric: Double?
    let asymmetryDeg: Double?
    let grade: LetterGrade?

    init(
        date: Date,
        kind: AnalysisKind,
        totalReps: Int = 0,
        score: Int? = nil,
        meanPeakAngle: Double? = nil,
        meanEccentric: Double? = nil,
        meanConcentric: Double? = nil,
        asymmetryDeg: Double? = nil,
        grade: LetterGrade? = nil
    ) {
        self.date = date
        self.kind = kind
        self.totalReps = totalReps
        self.score = score
        self.meanPeakAngle = meanPeakAngle
        self.meanEccentric = meanEccentric
        self.meanConcentric = meanConcentric
        self.asymmetryDeg = asymmetryDeg
        self.grade = grade
    }

    init(record: AnalysisRecord) {
        self.init(
            date: record.date,
            kind: record.kind,
            totalReps: record.totalReps,
            score: record.finalScore,
            meanPeakAngle: record.meanPeakAngle,
            meanEccentric: record.meanEccentric,
            meanConcentric: record.meanConcentric,
            asymmetryDeg: record.asymmetryDeg,
            grade: record.grade
        )
    }
}

/// Cross-session coaching, generated from history rather than from one set.
///
/// This is the half of the product that a single-session analyzer cannot do, and the
/// reason persistence was worth building: `CoachingInsights` can say a set was
/// consistent, but only history can say whether depth has been slipping for a month.
///
/// Thresholds are deliberately blunt. With the five or ten sessions a real user will
/// have, a fitted slope or a significance test would imply precision the data does
/// not contain, so these compare first against last and require the change to be
/// larger than the measurement's own noise before saying anything.
enum TrendInsights {

    /// Below this many sessions, there is no trend — just two data points.
    static let minimumSessions = 3

    /// A score swing smaller than this is inside normal session-to-session variation.
    static let scoreChangeThreshold = 5

    /// Peak-angle changes below this are within the noise of camera placement.
    static let angleChangeThresholdDegrees = 5.0

    /// Asymmetry changes below this are not worth reporting either way.
    static let asymmetryChangeThresholdDegrees = 3.0

    /// Gap after which the next session is worth acknowledging as a return.
    static let layoffDays = 14

    /// - Parameter samples: one movement's history, **oldest first**.
    static func insights(for samples: [TrendSample], movementName: String) -> [CoachingInsight] {
        guard samples.count >= minimumSessions else {
            return sparseHistoryInsight(samples: samples, movementName: movementName)
        }

        var insights: [CoachingInsight] = []

        if let scoreInsight = scoreTrend(samples, movementName: movementName) {
            insights.append(scoreInsight)
        }
        if let best = personalBest(samples) {
            insights.append(best)
        }
        if let depth = depthTrend(samples) {
            insights.append(depth)
        }
        if let control = eccentricTrend(samples) {
            insights.append(control)
        }
        if let asymmetry = asymmetryTrend(samples) {
            insights.append(asymmetry)
        }
        if let cadence = cadence(samples, movementName: movementName) {
            insights.append(cadence)
        }

        return Array(insights.prefix(4))
    }

    // MARK: - Heuristics

    /// Encourages a second and third session rather than pretending to see a trend.
    private static func sparseHistoryInsight(
        samples: [TrendSample],
        movementName: String
    ) -> [CoachingInsight] {
        guard !samples.isEmpty else { return [] }
        let remaining = minimumSessions - samples.count
        return [CoachingInsight(
            tone: .info,
            icon: "chart.line.uptrend.xyaxis",
            text: "\(samples.count) \(movementName) session\(samples.count == 1 ? "" : "s") saved. \(remaining) more and Kinetriq can start comparing depth, tempo, and score across the block."
        )]
    }

    private static func scoreTrend(
        _ samples: [TrendSample],
        movementName: String
    ) -> CoachingInsight? {
        let scores = samples.compactMap(\.score)
        guard scores.count >= minimumSessions,
              let first = scores.first,
              let last = scores.last else { return nil }

        let delta = last - first

        if delta >= scoreChangeThreshold {
            return CoachingInsight(
                tone: .positive,
                icon: "arrow.up.right.circle.fill",
                text: "Consistency is up \(delta) points across your last \(scores.count) \(movementName.lowercased()) sessions — \(first) to \(last)."
            )
        }
        if delta <= -scoreChangeThreshold {
            return CoachingInsight(
                tone: .caution,
                icon: "arrow.down.right.circle.fill",
                text: "Consistency has slipped \(abs(delta)) points across your last \(scores.count) \(movementName.lowercased()) sessions — \(first) to \(last). Worth checking whether load or fatigue changed."
            )
        }
        return CoachingInsight(
            tone: .positive,
            icon: "equal.circle.fill",
            text: "Consistency is holding steady around \(Int(Double(scores.reduce(0, +)) / Double(scores.count))) across your last \(scores.count) sessions."
        )
    }

    /// Only fires when the most recent session is the best one and there is enough
    /// history for that to mean something.
    private static func personalBest(_ samples: [TrendSample]) -> CoachingInsight? {
        let scores = samples.compactMap(\.score)
        guard scores.count >= minimumSessions,
              let last = scores.last,
              let best = scores.max(),
              last == best,
              scores.dropLast().allSatisfy({ $0 < last }) else { return nil }

        return CoachingInsight(
            tone: .positive,
            icon: "rosette",
            text: "That was your most consistent set of this movement so far at \(last)/100."
        )
    }

    /// Peak flexion angle is the depth signal: a *smaller* angle is a deeper rep.
    private static func depthTrend(_ samples: [TrendSample]) -> CoachingInsight? {
        let peaks = samples.compactMap(\.meanPeakAngle)
        guard peaks.count >= minimumSessions,
              let first = peaks.first,
              let last = peaks.last else { return nil }

        let delta = last - first
        guard abs(delta) >= angleChangeThresholdDegrees else { return nil }

        if delta < 0 {
            return CoachingInsight(
                tone: .positive,
                icon: "arrow.down.to.line",
                text: "You're getting \(Int(abs(delta).rounded()))° deeper than when you started — peak angle moved from \(Int(first.rounded()))° to \(Int(last.rounded()))°."
            )
        }
        return CoachingInsight(
            tone: .caution,
            icon: "arrow.up.to.line",
            text: "Depth has dropped \(Int(delta.rounded()))° across these sessions — peak angle moved from \(Int(first.rounded()))° to \(Int(last.rounded()))°. That is normal as load climbs, but worth knowing."
        )
    }

    /// Control on the lowering phase, tracked across sessions rather than within one.
    private static func eccentricTrend(_ samples: [TrendSample]) -> CoachingInsight? {
        let eccentrics = samples.compactMap(\.meanEccentric)
        guard eccentrics.count >= minimumSessions,
              let first = eccentrics.first,
              let last = eccentrics.last else { return nil }

        // Rushing now, controlled before.
        if last <= RepMetric.fastEccentricThreshold, first > RepMetric.fastEccentricThreshold {
            return CoachingInsight(
                tone: .caution,
                icon: "hare.fill",
                text: "Your eccentric has shortened to \(String(format: "%.1f", last))s from \(String(format: "%.1f", first))s. The lowering phase is where control shows up — slow it back down."
            )
        }

        // Genuinely steady tempo across the block is worth saying out loud.
        let mean = eccentrics.reduce(0, +) / Double(eccentrics.count)
        let variance = eccentrics.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(eccentrics.count)
        if mean > RepMetric.fastEccentricThreshold, variance.squareRoot() <= 0.4 {
            return CoachingInsight(
                tone: .positive,
                icon: "metronome.fill",
                text: "Eccentric time is holding at about \(String(format: "%.1f", mean))s session after session — that is genuinely repeatable control."
            )
        }
        return nil
    }

    private static func asymmetryTrend(_ samples: [TrendSample]) -> CoachingInsight? {
        let values = samples.compactMap(\.asymmetryDeg)
        guard values.count >= minimumSessions,
              let first = values.first,
              let last = values.last else { return nil }

        let delta = last - first
        guard abs(delta) >= asymmetryChangeThresholdDegrees else { return nil }

        if delta < 0 {
            return CoachingInsight(
                tone: .positive,
                icon: "equal.circle.fill",
                text: "Left-to-right difference narrowed from \(Int(first.rounded()))° to \(Int(last.rounded()))° across these assessments."
            )
        }
        return CoachingInsight(
            tone: .caution,
            icon: "arrow.left.arrow.right",
            text: "Left-to-right difference widened from \(Int(first.rounded()))° to \(Int(last.rounded()))°. Worth addressing before adding load."
        )
    }

    /// Notes a return after a layoff, which changes how the other numbers should be read.
    private static func cadence(_ samples: [TrendSample], movementName: String) -> CoachingInsight? {
        guard samples.count >= 2 else { return nil }
        let recent = samples.suffix(2)
        guard let previous = recent.first, let latest = recent.last else { return nil }

        let gapDays = Calendar.current.dateComponents(
            [.day],
            from: previous.date,
            to: latest.date
        ).day ?? 0

        guard gapDays >= layoffDays else { return nil }

        return CoachingInsight(
            tone: .info,
            icon: "calendar",
            text: "This was your first \(movementName.lowercased()) session in \(gapDays) days — expect the numbers to take a session or two to settle."
        )
    }
}
