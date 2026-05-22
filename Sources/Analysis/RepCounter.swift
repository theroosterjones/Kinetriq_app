import Foundation

/// Generic angle-threshold state machine for counting reps.
/// Ported from the Python row_analyzer rep counting logic.
///
/// A rep completes when the tracked angle transitions:
///   extended (above extendedThreshold) → flexed (below flexedThreshold) → extended
final class RepCounter {

    let extendedThreshold: Float
    let flexedThreshold: Float
    let minimumRepDuration: Double
    let minimumStateDuration: Double

    private(set) var count: Int = 0
    private(set) var state: RepState = .extended
    private var lastStateChangeTime: Double?
    private var lastRepTime: Double?

    init(
        extendedThreshold: Float,
        flexedThreshold: Float,
        minimumRepDuration: Double = 0.35,
        minimumStateDuration: Double = 0.08
    ) {
        self.extendedThreshold = extendedThreshold
        self.flexedThreshold = flexedThreshold
        self.minimumRepDuration = minimumRepDuration
        self.minimumStateDuration = minimumStateDuration
    }

    /// Feed the current angle value. Returns true if a rep just completed.
    @discardableResult
    func update(angle: Float) -> Bool {
        update(angle: angle, timestamp: nil)
    }

    /// Feed current angle plus frame timestamp in seconds.
    /// Timestamp enables minimum-duration guards against jitter/bounce reps.
    @discardableResult
    func update(angle: Float, timestamp: Double?) -> Bool {
        let canChangeState: Bool
        if let timestamp, timestamp.isFinite, let lastStateChangeTime {
            canChangeState = (timestamp - lastStateChangeTime) >= minimumStateDuration
        } else {
            canChangeState = true
        }

        switch state {
        case .extended where angle < flexedThreshold && canChangeState:
            state = .flexed
            if let timestamp, timestamp.isFinite {
                lastStateChangeTime = timestamp
            }
            return false

        case .flexed where angle > extendedThreshold && canChangeState:
            if let timestamp, timestamp.isFinite, let lastRepTime,
               (timestamp - lastRepTime) < minimumRepDuration {
                // Ignore ultra-fast bounce transitions that are unlikely to be real reps.
                state = .extended
                lastStateChangeTime = timestamp
                return false
            }

            count += 1
            state = .extended
            if let timestamp, timestamp.isFinite {
                lastRepTime = timestamp
                lastStateChangeTime = timestamp
            }
            return true

        default:
            return false
        }
    }

    func reset() {
        count = 0
        state = .extended
        lastStateChangeTime = nil
        lastRepTime = nil
    }
}
