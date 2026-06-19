import Foundation

/// Visual tone for a coaching insight. Mapped to color/icon in the view layer so
/// this stays UI-framework agnostic alongside the rest of the analysis code.
enum InsightTone {
    case positive
    case caution
    case info
}

/// A single plain-language coaching takeaway derived from an analysis result.
struct CoachingInsight: Identifiable {
    let id = UUID()
    let tone: InsightTone
    /// SF Symbol name suggested for this insight.
    let icon: String
    let text: String
}

/// Generates 2–4 plain-language insights from existing analysis results.
///
/// Pure post-processing over `AnalysisSummary` / `AssessmentMetrics` — it never
/// touches the pipeline, so it can be regenerated cheaply for display and copy.
enum CoachingInsights {

    /// Insights for a completed exercise analysis.
    static func exercise(summary: AnalysisSummary, exerciseType: ExerciseType) -> [CoachingInsight] {
        var insights: [CoachingInsight] = []

        // 1. Score headline (only meaningful with ≥3 reps).
        if let score = summary.finalScore {
            if score >= 80 {
                insights.append(CoachingInsight(
                    tone: .positive, icon: "checkmark.seal.fill",
                    text: "Strong, repeatable form — consistency score \(score)/100."))
            } else if score >= 60 {
                insights.append(CoachingInsight(
                    tone: .info, icon: "chart.bar.fill",
                    text: "Decent consistency at \(score)/100. Tightening tempo and depth from rep to rep will push this higher."))
            } else {
                insights.append(CoachingInsight(
                    tone: .caution, icon: "exclamationmark.triangle.fill",
                    text: "Consistency score \(score)/100 — reps varied noticeably. Slow down and aim to make every rep look the same."))
            }
        } else if summary.totalReps > 0 {
            insights.append(CoachingInsight(
                tone: .info, icon: "number",
                text: "Counted \(summary.totalReps) rep\(summary.totalReps == 1 ? "" : "s"). Record at least 3 clean reps to unlock a consistency score."))
        }

        // 2. Tempo drift across the set.
        if let drift = tempoDrift(reps: summary.perRepMetrics) {
            insights.append(drift)
        }

        // 3. Depth / ROM consistency.
        if let rom = romConsistency(reps: summary.perRepMetrics) {
            insights.append(rom)
        }

        // 4. Tracking quality caveat.
        if let tracking = trackingInsight(rate: summary.poseDetectionRate) {
            insights.append(tracking)
        }

        return cap(insights)
    }

    /// Insights for a completed assessment.
    static func assessment(metrics: AssessmentMetrics, trackingRate: Float?) -> [CoachingInsight] {
        var insights: [CoachingInsight] = []

        // 1. Overall grade headline.
        if metrics.grade <= .B {
            insights.append(CoachingInsight(
                tone: .positive, icon: "checkmark.seal.fill",
                text: "Overall grade \(metrics.grade.rawValue) — movement meets quality standards."))
        } else {
            insights.append(CoachingInsight(
                tone: .caution, icon: "exclamationmark.triangle.fill",
                text: "Overall grade \(metrics.grade.rawValue) — mobility or control limitations are showing up."))
        }

        // 2. Asymmetry flag.
        if metrics.asymmetryFlag, let asymm = metrics.asymmetryDeg {
            insights.append(CoachingInsight(
                tone: .caution, icon: "arrow.left.arrow.right",
                text: "\(Int(asymm))° side-to-side difference — worth addressing before loading the movement."))
        } else if metrics.leftROM != nil, metrics.rightROM != nil {
            insights.append(CoachingInsight(
                tone: .positive, icon: "equal.circle.fill",
                text: "Left and right ranges are well balanced."))
        }

        // 3. Weakest sub-grade as a focus area.
        if let weakest = metrics.subGrades.max(by: { $0.grade < $1.grade }), weakest.grade > .B {
            insights.append(CoachingInsight(
                tone: .info, icon: "scope",
                text: "Biggest focus area: \(weakest.label) (graded \(weakest.grade.rawValue))."))
        }

        // 4. Tracking quality caveat.
        if let rate = trackingRate, let tracking = trackingInsight(rate: rate) {
            insights.append(tracking)
        }

        return cap(insights)
    }

    /// Plain-text rendering suitable for the clipboard / sharing.
    static func clipboardText(_ insights: [CoachingInsight], header: String? = nil) -> String {
        var lines: [String] = []
        if let header { lines.append(header) }
        lines.append(contentsOf: insights.map { "• \($0.text)" })
        lines.append("— via Kinetriq")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private heuristics

    /// At most four insights keeps the card scannable.
    private static func cap(_ insights: [CoachingInsight]) -> [CoachingInsight] {
        Array(insights.prefix(4))
    }

    /// Detects whether the lifting pace drifted between the first and second half
    /// of the set (a common fatigue / rushing tell).
    private static func tempoDrift(reps: [RepMetric]) -> CoachingInsight? {
        guard reps.count >= 4 else { return nil }

        let mid = reps.count / 2
        let firstHalf = Array(reps.prefix(mid))
        let secondHalf = Array(reps.suffix(reps.count - mid))

        func activeAverage(_ slice: [RepMetric]) -> Double {
            guard !slice.isEmpty else { return 0 }
            let total = slice.reduce(0.0) { $0 + $1.eccentricDuration + $1.concentricDuration }
            return total / Double(slice.count)
        }

        let early = activeAverage(firstHalf)
        let late = activeAverage(secondHalf)
        guard early > 0.3 else { return nil }

        let change = (late - early) / early
        if change <= -0.25 {
            return CoachingInsight(
                tone: .caution, icon: "hare.fill",
                text: "Your reps sped up \(Int(abs(change) * 100))% by the end of the set — keep the tempo controlled as you fatigue.")
        } else if change >= 0.25 {
            return CoachingInsight(
                tone: .info, icon: "tortoise.fill",
                text: "Your reps slowed \(Int(change * 100))% toward the end — likely fatigue. Stop a rep before form breaks down.")
        }
        return CoachingInsight(
            tone: .positive, icon: "metronome.fill",
            text: "Tempo stayed steady across the whole set — great control.")
    }

    /// Reports how consistent peak depth/range was across reps.
    private static func romConsistency(reps: [RepMetric]) -> CoachingInsight? {
        let peaks = reps.map { $0.peakFlexionAngle }.filter { $0.isFinite }
        guard peaks.count >= 3 else { return nil }

        let mean = peaks.reduce(0, +) / Float(peaks.count)
        let variance = peaks.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(peaks.count)
        let sd = sqrt(variance)

        if sd <= 6 {
            return CoachingInsight(
                tone: .positive, icon: "arrow.up.and.down.circle.fill",
                text: "Depth was very consistent — peak angle held within \(Int(sd.rounded()))° across reps.")
        } else if sd >= 14 {
            return CoachingInsight(
                tone: .caution, icon: "arrow.up.and.down.circle.fill",
                text: "Depth varied by about \(Int(sd.rounded()))° between reps — aim to hit the same range every time.")
        }
        return nil
    }

    private static func trackingInsight(rate: Float) -> CoachingInsight? {
        let pct = Int((rate * 100).rounded())
        if pct < 70 {
            return CoachingInsight(
                tone: .caution, icon: "video.slash.fill",
                text: "Pose was tracked only \(pct)% of frames, so these numbers are approximate — refilm with better framing or lighting for a sharper read.")
        }
        return nil
    }
}
