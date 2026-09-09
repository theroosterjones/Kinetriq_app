import Foundation

enum TempoDurationFormatter {
    private static let roundUpFractionThreshold = 0.6
    private static let comparisonTolerance = 1e-9

    static func seconds(_ duration: Double) -> Int {
        guard duration.isFinite else { return 0 }

        let nonNegativeDuration = max(0, duration)
        let wholeSeconds = nonNegativeDuration.rounded(.down)
        let fraction = nonNegativeDuration - wholeSeconds
        return Int(wholeSeconds) + (fraction >= roundUpFractionThreshold - comparisonTolerance ? 1 : 0)
    }

    static func string(
        eccentric: Double,
        pauseBottom: Double,
        concentric: Double,
        pauseTop: Double
    ) -> String {
        "\(seconds(eccentric))-\(seconds(pauseBottom))-\(seconds(concentric))-\(seconds(pauseTop))"
    }
}

/// Per-rep metrics capturing ROM peak and tempo phase durations.
struct RepMetric: Codable {
    let repNumber: Int
    let peakFlexionAngle: Float
    let eccentricDuration: Double
    let pauseBottomDuration: Double
    let concentricDuration: Double
    let pauseTopDuration: Double

    var totalDuration: Double {
        eccentricDuration + pauseBottomDuration + concentricDuration + pauseTopDuration
    }

    /// Formatted tempo string (e.g. "3-1-2-1").
    /// All four phases round up only when the fractional seconds are at least 0.6.
    /// A 3.4 s eccentric reads as 3, while a 0.6 s pause reads as 1.
    var tempoString: String {
        TempoDurationFormatter.string(
            eccentric: eccentricDuration,
            pauseBottom: pauseBottomDuration,
            concentric: concentricDuration,
            pauseTop: pauseTopDuration
        )
    }

    /// Eccentric of 1.0 s or faster is treated as lacking control.
    static let fastEccentricThreshold: Double = 1.0

    var lacksEccentricControl: Bool {
        eccentricDuration.isFinite && eccentricDuration <= Self.fastEccentricThreshold
    }
}

/// Collects per-rep metrics from frame-by-frame analysis output.
/// Feed each frame's phase, primary angle, rep count, and timestamp. When a rep completes
/// (repCount increments), the collector finalises phase durations and peak angle for that rep.
final class RepMetricsCollector {

    private(set) var completedReps: [RepMetric] = []

    /// Largest instantaneous jump (in degrees) we'll accept as a real motion sample.
    /// Larger jumps are treated as tracking noise (e.g. MediaPipe snapping the hip
    /// landmark onto machine padding for a frame) and are excluded from peak-angle
    /// tracking so a single bad frame can't poison the rep's ROM score.
    private let maxAngleStepForPeakTracking: Float = 30.0

    private var lastRepCount = 0
    private var currentPeakAngle: Float = .greatestFiniteMagnitude
    private var lastAcceptedAngle: Float?
    private var phaseAccumulators: [TempoPhase: Double] = [:]
    private var currentPhase: TempoPhase?
    private var phaseStartTime: Double?
    private var lastTimestamp: Double?

    /// Call once per frame with the current analysis output.
    ///
    /// Analyzers may pass `.nan` for `angle` when per-frame landmark confidence is too
    /// low to trust the measurement; those frames are skipped for peak-angle tracking
    /// while phase and rep bookkeeping continue normally.
    func update(phase: TempoPhase?, angle: Float, repCount: Int, timestamp: Double) {
        // Track phase durations
        if let phase, phase != currentPhase {
            finalizeCurrentPhase(at: timestamp)
            currentPhase = phase
            phaseStartTime = timestamp
        }

        // Track peak flexion (minimum angle = deepest point), gated against outliers
        if angle.isFinite {
            let accept: Bool
            if let prev = lastAcceptedAngle {
                accept = abs(angle - prev) <= maxAngleStepForPeakTracking
            } else {
                accept = true
            }
            if accept {
                currentPeakAngle = min(currentPeakAngle, angle)
                lastAcceptedAngle = angle
            }
        }

        // Rep just completed — finalize metrics
        if repCount > lastRepCount {
            finalizeCurrentPhase(at: timestamp)

            let metric = RepMetric(
                repNumber: repCount,
                peakFlexionAngle: currentPeakAngle,
                eccentricDuration: phaseAccumulators[.eccentric, default: 0],
                pauseBottomDuration: phaseAccumulators[.pauseBottom, default: 0],
                concentricDuration: phaseAccumulators[.concentric, default: 0],
                pauseTopDuration: phaseAccumulators[.pauseTop, default: 0]
            )
            completedReps.append(metric)

            // Reset for next rep
            currentPeakAngle = .greatestFiniteMagnitude
            lastAcceptedAngle = angle.isFinite ? angle : nil
            phaseAccumulators = [:]
            lastRepCount = repCount
        }

        lastTimestamp = timestamp
    }

    /// Current in-progress tempo (durations so far for the rep being recorded).
    func currentTempo() -> (ecc: Double, pauseB: Double, con: Double, pauseT: Double)? {
        guard currentPhase != nil else { return nil }
        var accum = phaseAccumulators
        // Include time in the current phase up to now
        if let phase = currentPhase, let start = phaseStartTime, let last = lastTimestamp {
            accum[phase, default: 0] += max(0, last - start)
        }
        return (
            ecc: accum[.eccentric, default: 0],
            pauseB: accum[.pauseBottom, default: 0],
            con: accum[.concentric, default: 0],
            pauseT: accum[.pauseTop, default: 0]
        )
    }

    /// Current in-progress tempo as a formatted string (e.g. "3-1-2-0").
    /// All four phases use the same 0.6-second threshold as `RepMetric.tempoString`.
    func currentTempoString() -> String {
        guard let t = currentTempo() else { return "--" }
        return TempoDurationFormatter.string(
            eccentric: t.ecc,
            pauseBottom: t.pauseB,
            concentric: t.con,
            pauseTop: t.pauseT
        )
    }

    // MARK: - Scoring

    /// Exercise score (0--100). Nil if fewer than 3 completed reps.
    ///
    /// Combines banded ROM consistency (60%) and tempo consistency (40%), then
    /// subtracts a control penalty when eccentrics are 1.0 s or faster. Concentric
    /// slowing across a set is excluded from tempo consistency so fatigue is not punished.
    func computeScore() -> Int? {
        guard completedReps.count >= 3 else { return nil }

        let romScore = romConsistencyScore()
        let tempoScore = tempoConsistencyScore()
        let consistency = 0.6 * Double(romScore) + 0.4 * Double(tempoScore)
        let controlPenalty = fastEccentricPenalty()
        return max(0, min(100, Int((consistency - controlPenalty).rounded())))
    }

    func reset() {
        completedReps.removeAll()
        lastRepCount = 0
        currentPeakAngle = .greatestFiniteMagnitude
        lastAcceptedAngle = nil
        phaseAccumulators = [:]
        currentPhase = nil
        phaseStartTime = nil
        lastTimestamp = nil
    }

    // MARK: - Private

    private func finalizeCurrentPhase(at timestamp: Double) {
        guard let phase = currentPhase, let start = phaseStartTime else { return }
        phaseAccumulators[phase, default: 0] += max(0, timestamp - start)
    }

    /// ROM consistency from peak-angle standard deviation, in discrete bands.
    /// Gaps between listed ranges inherit the next lower band (e.g. 1.6°–1.9° → 90).
    /// Exactly 12° uses the 11–12 band (40); above 15° scores 0.
    private func romConsistencyScore() -> Int {
        let peaks = completedReps.map { $0.peakFlexionAngle }
        return Self.romScore(forPeakAngleStdDev: stddev(peaks))
    }

    static func romScore(forPeakAngleStdDev sd: Float) -> Int {
        guard sd.isFinite, sd >= 0 else { return 0 }
        switch sd {
        case ...1.5:  return 100  // 0–1.5°
        case ...3:    return 90   // 2–3°
        case ...5:    return 80   // 4–5°
        case ...7:    return 70   // 6–7°
        case ...10:   return 50   // 8–10°
        case ...12:   return 40   // 11–12°
        case ...13:   return 30   // 12–13°
        case ...15:   return 20   // 14–15°
        default:      return 0
        }
    }

    /// Tempo consistency from eccentric and pause phases only. Concentric duration
    /// is omitted so a fatiguing set that slows on the way up is not penalized.
    private func tempoConsistencyScore() -> Int {
        let eccSD = stddev(completedReps.map { Float($0.eccentricDuration) })
        let pbSD  = stddev(completedReps.map { Float($0.pauseBottomDuration) })
        let ptSD  = stddev(completedReps.map { Float($0.pauseTopDuration) })
        let avgSD = Double(eccSD + pbSD + ptSD) / 3.0
        return max(0, Int((100.0 - 50.0 * avgSD).rounded()))
    }

    /// Up to 25 points off when every completed rep has an eccentric of 1.0 s or faster.
    private func fastEccentricPenalty() -> Double {
        let fastCount = completedReps.filter(\.lacksEccentricControl).count
        guard !completedReps.isEmpty else { return 0 }
        return (Double(fastCount) / Double(completedReps.count)) * 25.0
    }

    private func stddev(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let n = Float(values.count)
        let mean = values.reduce(0, +) / n
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        return sqrt(variance)
    }
}
