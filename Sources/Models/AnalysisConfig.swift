import Foundation

/// Global configuration for analysis parameters.
/// Centralizes values that were previously hardcoded across Python analyzers.
struct AnalysisConfig {
    /// MediaPipe pose detection confidence threshold (0–1).
    var minDetectionConfidence: Float = 0.35

    /// MediaPipe pose tracking confidence threshold (0–1).
    var minTrackingConfidence: Float = 0.35

    /// EMA smoothing alpha for landmark positions.
    /// 0.7 matches the Python analyzers. Lower = smoother but more lag.
    var smoothingAlpha: Float = 0.7

    /// Angular velocity threshold (degrees/sec) for tempo phase classification.
    var tempoVelocityThreshold: Float = 15.0

    /// Number of samples in the tempo tracker's sliding window.
    var tempoWindowSize: Int = 5

    /// MediaPipe model variant to use.
    var modelType: PoseLandmarkerService.ModelType = .full

    static let `default` = AnalysisConfig()
}
