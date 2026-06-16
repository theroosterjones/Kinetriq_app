import Foundation
import simd

/// Real-time landmark smoother using the 1€ filter algorithm.
///
/// The 1€ filter adapts its cutoff frequency to signal speed:
///   - At rest / lockout: low cutoff → heavy smoothing, no jitter
///   - During reps: high cutoff → minimal lag, stays glued to the joint
///
/// This is strictly better than a fixed-alpha EMA for exercise analysis because
/// each rep has distinct fast phases (concentric/eccentric) and slow phases
/// (pause at top/bottom). The filter adjusts automatically without needing to
/// retune alpha per exercise.
///
/// Reference: Casiez et al., "1€ Filter: A Simple Speed-based Low-pass Filter
///            for Noisy Input in Interactive Systems", CHI 2012.
final class LandmarkSmoother {

    /// Minimum cutoff frequency (Hz). Controls smoothness when the joint is still.
    let minCutoff: Float
    /// Speed coefficient. Higher = cutoff rises faster with motion, more responsive.
    let beta: Float
    /// Derivative cutoff (Hz). Controls stability of the internal speed estimate.
    let dCutoff: Float

    private struct ChannelState {
        var xHat: Float      // filtered value
        var dxHat: Float     // filtered derivative (speed estimate)
        var lastTime: Double
    }

    private struct AnchorState2D {
        var samples: [SIMD2<Float>] = []
        var locked: SIMD2<Float>?
        var releaseFrames = 0
    }

    private struct AnchorState3D {
        var samples: [SIMD3<Float>] = []
        var locked: SIMD3<Float>?
        var releaseFrames = 0
    }

    private var channels: [String: ChannelState] = [:]
    private var anchors2D: [String: AnchorState2D] = [:]
    private var anchors3D: [String: AnchorState3D] = [:]

    /// - Parameters:
    ///   - minCutoff: Smoothness at rest. Lower = smoother but more lag at rest.
    ///                1.0 Hz is a good starting point for body landmarks.
    ///   - beta: Speed responsiveness. Higher = less lag during fast movement.
    ///           0.5 works well for typical exercise tempos (0.5–2 s per phase).
    ///   - dCutoff: Derivative filter cutoff. 1.0 Hz is the standard default.
    init(minCutoff: Float = 1.0, beta: Float = 0.5, dCutoff: Float = 1.0) {
        self.minCutoff = minCutoff
        self.beta      = beta
        self.dCutoff   = dCutoff
    }

    // MARK: - Public (drop-in replacement for old EMA interface)

    /// Smooth a 2D normalised screen position (overlay drawing).
    ///
    /// Pass `landmarks.timestamp` for accurate per-frame dt (required for offline
    /// video which processes faster than real time). Omit for convenience in
    /// real-time contexts where wall-clock time is close enough.
    func smooth(key: String, position: SIMD2<Float>, timestamp: Double? = nil) -> SIMD2<Float> {
        let t = timestamp ?? Date().timeIntervalSince1970
        return SIMD2<Float>(
            filter(key: "\(key)_x", value: position.x, time: t),
            filter(key: "\(key)_y", value: position.y, time: t)
        )
    }

    /// Smooth a 3D world position (angle calculations).
    func smooth3D(key: String, position: SIMD3<Float>, timestamp: Double? = nil) -> SIMD3<Float> {
        let t = timestamp ?? Date().timeIntervalSince1970
        // Use _wx / _wy / _wz keys to stay independent from the 2D _x / _y channels
        return SIMD3<Float>(
            filter(key: "\(key)_wx", value: position.x, time: t),
            filter(key: "\(key)_wy", value: position.y, time: t),
            filter(key: "\(key)_wz", value: position.z, time: t)
        )
    }

    /// Stabilize an expected-stationary 2D anchor such as a planted wrist or foot.
    ///
    /// The anchor locks after several close samples and ignores small MediaPipe jitter.
    /// If the landmark genuinely relocates for consecutive frames, it unlocks and
    /// re-establishes at the new position.
    func stabilizeAnchor(
        key: String,
        position: SIMD2<Float>,
        stableRadius: Float = 0.018,
        releaseRadius: Float = 0.055,
        requiredSamples: Int = 5,
        requiredReleaseFrames: Int = 5
    ) -> SIMD2<Float> {
        var state = anchors2D[key] ?? AnchorState2D()
        defer { anchors2D[key] = state }

        if let locked = state.locked {
            if simd_distance(position, locked) > releaseRadius {
                state.releaseFrames += 1
                if state.releaseFrames >= requiredReleaseFrames {
                    state = AnchorState2D(samples: [position], locked: nil, releaseFrames: 0)
                    return position
                }
            } else {
                state.releaseFrames = 0
            }
            return locked
        }

        state.samples.append(position)
        if state.samples.count > requiredSamples {
            state.samples.removeFirst(state.samples.count - requiredSamples)
        }

        let average = state.samples.reduce(SIMD2<Float>.zero, +) / Float(state.samples.count)
        let maxDistance = state.samples.map { simd_distance($0, average) }.max() ?? 0
        if state.samples.count >= requiredSamples, maxDistance <= stableRadius {
            state.locked = average
            return average
        }

        return average
    }

    /// Stabilize an expected-stationary 3D anchor for angle calculations.
    func stabilizeAnchor3D(
        key: String,
        position: SIMD3<Float>,
        stableRadius: Float = 0.025,
        releaseRadius: Float = 0.10,
        requiredSamples: Int = 5,
        requiredReleaseFrames: Int = 5
    ) -> SIMD3<Float> {
        var state = anchors3D[key] ?? AnchorState3D()
        defer { anchors3D[key] = state }

        if let locked = state.locked {
            if simd_distance(position, locked) > releaseRadius {
                state.releaseFrames += 1
                if state.releaseFrames >= requiredReleaseFrames {
                    state = AnchorState3D(samples: [position], locked: nil, releaseFrames: 0)
                    return position
                }
            } else {
                state.releaseFrames = 0
            }
            return locked
        }

        state.samples.append(position)
        if state.samples.count > requiredSamples {
            state.samples.removeFirst(state.samples.count - requiredSamples)
        }

        let average = state.samples.reduce(SIMD3<Float>.zero, +) / Float(state.samples.count)
        let maxDistance = state.samples.map { simd_distance($0, average) }.max() ?? 0
        if state.samples.count >= requiredSamples, maxDistance <= stableRadius {
            state.locked = average
            return average
        }

        return average
    }

    func reset() {
        channels.removeAll()
        anchors2D.removeAll()
        anchors3D.removeAll()
    }

    // MARK: - 1€ Filter Core

    private func filter(key: String, value: Float, time: Double) -> Float {
        guard let prev = channels[key] else {
            channels[key] = ChannelState(xHat: value, dxHat: 0, lastTime: time)
            return value
        }

        // Clamp dt to avoid division-by-zero on duplicate timestamps
        let dt = max(Float(time - prev.lastTime), 1e-6)

        // Low-pass filter the derivative with a fixed cutoff
        let dx    = (value - prev.xHat) / dt
        let aD    = alpha(cutoff: dCutoff, dt: dt)
        let dxHat = aD * dx + (1 - aD) * prev.dxHat

        // Raise the cutoff proportional to smoothed speed → less lag during fast motion
        let fcAdaptive = minCutoff + beta * abs(dxHat)

        // Filter the value with the adaptive cutoff
        let aV   = alpha(cutoff: fcAdaptive, dt: dt)
        let xHat = aV * value + (1 - aV) * prev.xHat

        channels[key] = ChannelState(xHat: xHat, dxHat: dxHat, lastTime: time)
        return xHat
    }

    /// Alpha coefficient for a first-order low-pass filter.
    private func alpha(cutoff: Float, dt: Float) -> Float {
        let tau = 1.0 / (2.0 * Float.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }
}
