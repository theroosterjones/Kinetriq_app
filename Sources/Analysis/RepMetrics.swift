import Foundation

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
    /// All four phases round DOWN (floor) so durations are never overstated.
    /// A 3.4 s eccentric reads as 3, a 0.9 s pause reads as 0.
    var tempoString: String {
        "\(Int(eccentricDuration.rounded(.down)))-\(Int(pauseBottomDuration.rounded(.down)))-\(Int(concentricDuration.rounded(.down)))-\(Int(pauseTopDuration.rounded(.down)))"
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
    /// All four phases use floor rounding, matching `RepMetric.tempoString`.
    func currentTempoString() -> String {
        guard let t = currentTempo() else { return "--" }
        return "\(Int(t.ecc.rounded(.down)))-\(Int(t.pauseB.rounded(.down)))-\(Int(t.con.rounded(.down)))-\(Int(t.pauseT.rounded(.down)))"
    }

    // MARK: - Scoring

    /// Exercise consistency score (0--100). Nil if fewer than 3 completed reps.
    func computeScore() -> Int? {
        guard completedReps.count >= 3 else { return nil }

        let romScore = romConsistencyScore()
        let tempoScore = tempoConsistencyScore()
        return max(0, min(100, Int((0.6 * Double(romScore) + 0.4 * Double(tempoScore)).rounded())))
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

    /// ROM consistency: 100 - 5 * stddev(peak angles). Lower variance = better.
    private func romConsistencyScore() -> Int {
        let peaks = completedReps.map { $0.peakFlexionAngle }
        let sd = stddev(peaks)
        return max(0, Int((100.0 - 5.0 * Double(sd)).rounded()))
    }

    /// Tempo consistency: 100 - 50 * avg(stddev of each phase duration). Lower variance = better.
    private func tempoConsistencyScore() -> Int {
        let eccSD = stddev(completedReps.map { Float($0.eccentricDuration) })
        let pbSD  = stddev(completedReps.map { Float($0.pauseBottomDuration) })
        let conSD = stddev(completedReps.map { Float($0.concentricDuration) })
        let ptSD  = stddev(completedReps.map { Float($0.pauseTopDuration) })
        let avgSD = Double(eccSD + pbSD + conSD + ptSD) / 4.0
        return max(0, Int((100.0 - 50.0 * avgSD).rounded()))
    }

    private func stddev(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let n = Float(values.count)
        let mean = values.reduce(0, +) / n
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        return sqrt(variance)
    }
}
