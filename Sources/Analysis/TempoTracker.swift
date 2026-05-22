import Foundation
import CoreMedia

/// Tracks exercise tempo by classifying the primary joint angle's movement into phases:
///   eccentric → pauseBottom → concentric → pauseTop → (repeat)
///
/// Uses angular velocity (first derivative of angle over time) to determine direction of movement.
final class TempoTracker {

    /// Degrees-per-second below which we consider movement "paused".
    let velocityThreshold: Float

    /// Separate lower threshold for entering pause to avoid chatter near ROM endpoints.
    let pauseVelocityThreshold: Float

    /// Number of samples to use for velocity smoothing.
    let windowSize: Int

    /// Minimum seconds a phase must last before switching again (debounce).
    let minimumPhaseDuration: Double

    /// When true, the concentric phase corresponds to the joint *closing* (angle decreasing)
    /// rather than opening. Use for exercises like bicep curls, rows, and lat pulldowns where
    /// the "working" pull/curl motion decreases the tracked joint angle.
    ///
    /// - false (default): angle ↓ = eccentric, angle ↑ = concentric  (squat, deadlift, OHP)
    /// - true:            angle ↓ = concentric, angle ↑ = eccentric  (curl, row, lat pulldown)
    let invertPhases: Bool

    private(set) var currentPhase: TempoPhase = .pauseTop
    private var lastMovingPhase: TempoPhase = .concentric
    private var lastTransitionTime: Double?

    private struct Sample {
        let angle: Float
        let time: Double  // seconds
    }

    private var samples: [Sample] = []

    init(
        velocityThreshold: Float = 15.0,
        pauseVelocityThreshold: Float = 8.0,
        windowSize: Int = 5,
        minimumPhaseDuration: Double = 0.12,
        invertPhases: Bool = false
    ) {
        self.velocityThreshold = velocityThreshold
        self.pauseVelocityThreshold = min(pauseVelocityThreshold, velocityThreshold)
        self.windowSize = windowSize
        self.minimumPhaseDuration = minimumPhaseDuration
        self.invertPhases = invertPhases
    }

    /// Feed the current primary angle and frame timestamp. Returns the detected phase.
    @discardableResult
    func update(angle: Float, time: CMTime) -> TempoPhase {
        update(angle: angle, timestamp: CMTimeGetSeconds(time))
    }

    /// Feed current angle and wall-clock frame timestamp in seconds.
    @discardableResult
    func update(angle: Float, timestamp timeSec: Double) -> TempoPhase {
        guard timeSec.isFinite else { return currentPhase }
        samples.append(Sample(angle: angle, time: timeSec))

        // Keep only the most recent samples
        if samples.count > windowSize {
            samples.removeFirst(samples.count - windowSize)
        }

        guard samples.count >= 2 else { return currentPhase }

        let velocity = computeAngularVelocity()
        let absVelocity = abs(velocity)
        var desiredPhase = currentPhase

        if velocity < -velocityThreshold {
            // Angle decreasing = joint closing.
            // Default: eccentric (e.g., lowering into squat).
            // Inverted: concentric (e.g., curling up, pulling bar down).
            desiredPhase = invertPhases ? .concentric : .eccentric
        } else if velocity > velocityThreshold {
            // Angle increasing = joint opening.
            // Default: concentric (e.g., standing from squat).
            // Inverted: eccentric (e.g., lowering curl, releasing bar back up).
            desiredPhase = invertPhases ? .eccentric : .concentric
        } else if absVelocity <= pauseVelocityThreshold {
            // Enter pause only when truly near-zero, not just slightly slower.
            desiredPhase = (lastMovingPhase == .eccentric) ? .pauseBottom : .pauseTop
        } else {
            // Deadband between thresholds: hold phase to suppress noise-driven toggles.
            desiredPhase = currentPhase
        }

        let canTransition: Bool
        if let lastTransitionTime {
            canTransition = (timeSec - lastTransitionTime) >= minimumPhaseDuration
        } else {
            canTransition = true
        }

        if desiredPhase != currentPhase && canTransition {
            currentPhase = desiredPhase
            if desiredPhase == .eccentric || desiredPhase == .concentric {
                lastMovingPhase = desiredPhase
            }
            lastTransitionTime = timeSec
        }

        return currentPhase
    }

    func reset() {
        samples.removeAll()
        currentPhase   = .pauseTop
        lastMovingPhase = .concentric
        lastTransitionTime = nil
    }

    // MARK: - Private

    /// Linear regression slope of angle over time (degrees per second).
    private func computeAngularVelocity() -> Float {
        guard samples.count >= 2 else { return 0 }

        let n = Float(samples.count)
        var sumT: Float = 0, sumA: Float = 0, sumTA: Float = 0, sumTT: Float = 0
        let t0 = samples[0].time

        for s in samples {
            let t = Float(s.time - t0)
            sumT += t
            sumA += s.angle
            sumTA += t * s.angle
            sumTT += t * t
        }

        let denom = n * sumTT - sumT * sumT
        guard abs(denom) > 1e-6 else { return 0 }

        return (n * sumTA - sumT * sumA) / denom
    }
}
