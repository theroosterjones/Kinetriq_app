import AVFoundation
import UIKit
import MediaPipeTasksVision

/// Wraps the MediaPipe Pose Landmarker iOS SDK.
/// Call `detect(pixelBuffer:timestampMs:)` for each video frame.
final class PoseLandmarkerService {

    enum ModelType: String {
        case lite = "pose_landmarker_lite"
        case full = "pose_landmarker_full"
        case heavy = "pose_landmarker_heavy"
    }

    private let modelType: ModelType
    private let config: AnalysisConfig
    private var poseLandmarker: PoseLandmarker?

    /// Avoid logging every frame when the model never loaded (would flood Console).
    private var loggedNilLandmarker = false
    /// Sample first few hard failures so Console stays readable without per-frame cost.
    private var mpImageFailureLogCount = 0
    private var detectFailureLogCount = 0

    init(config: AnalysisConfig = .default) {
        self.config = config
        self.modelType = config.modelType
        setupLandmarker()
    }

    /// Tears down the current PoseLandmarker and re-creates it before each saved-video run.
    ///
    /// MediaPipe video mode requires strictly monotonically increasing timestamps across
    /// all `detect()` calls on the same instance. Re-using one instance across multiple
    /// analyses causes every frame of the second run to be rejected (timestamps restart
    /// from 0, which is less than the final timestamp of the previous run), producing
    /// silent 0% detection. Re-creating the instance resets that internal counter.
    ///
    /// The model binary is already mapped into memory after the first init, so subsequent
    /// inits are fast (no disk I/O).
    func resetForNewSession() {
        poseLandmarker = nil
        setupLandmarker()
        mpImageFailureLogCount = 0
        detectFailureLogCount = 0
        loggedNilLandmarker = false
        AnalysisLog.pose.info("PoseLandmarker reset for new session")
    }

    // MARK: - Setup

    private func setupLandmarker() {
        guard let modelPath = Bundle.main.path(
            forResource: modelType.rawValue,
            ofType: "task"
        ) else {
            AnalysisLog.pose.error("Missing \(self.modelType.rawValue, privacy: .public).task in app bundle")
            return
        }

        AnalysisLog.pose.info("Model path \(modelPath, privacy: .public)")

        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .video
        options.minPoseDetectionConfidence = config.minDetectionConfidence
        options.minTrackingConfidence = config.minTrackingConfidence
        options.numPoses = 1

        do {
            poseLandmarker = try PoseLandmarker(options: options)
            AnalysisLog.pose.info("PoseLandmarker initialized")
        } catch {
            AnalysisLog.pose.error("PoseLandmarker init failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Detection

    /// Run pose detection on a single video frame.
    func detect(pixelBuffer: CVPixelBuffer, timestampMs: Int) -> PoseResult? {
        guard let poseLandmarker else {
            if !loggedNilLandmarker {
                AnalysisLog.pose.error("PoseLandmarker nil — model not loaded (further messages suppressed)")
                loggedNilLandmarker = true
            }
            return nil
        }

        let mpImage: MPImage
        do {
            mpImage = try MPImage(pixelBuffer: pixelBuffer)
        } catch {
            if mpImageFailureLogCount < 3 {
                AnalysisLog.pose.error(
                    "MPImage failed at \(timestampMs, privacy: .public)ms: \(error.localizedDescription, privacy: .public) (sample \(self.mpImageFailureLogCount + 1)/3)"
                )
            }
            mpImageFailureLogCount += 1
            return nil
        }

        let result: PoseLandmarkerResult
        do {
            result = try poseLandmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)
        } catch {
            if detectFailureLogCount < 3 {
                AnalysisLog.pose.error(
                    "detect() threw at \(timestampMs, privacy: .public)ms: \(error.localizedDescription, privacy: .public) (sample \(self.detectFailureLogCount + 1)/3)"
                )
            }
            detectFailureLogCount += 1
            return nil
        }

        // No landmarks: silent here — VideoProcessor aggregates poseMiss vs poseOkEmptyOverlay.
        guard let poseLandmarks = result.landmarks.first else { return nil }

        // 2D normalized landmarks (for overlay drawing)
        var landmarks: [PoseLandmarkType: NormalizedLandmark] = [:]
        for (index, lm) in poseLandmarks.enumerated() {
            guard let type = PoseLandmarkType(rawValue: index) else { continue }
            landmarks[type] = NormalizedLandmark(
                position: SIMD2<Float>(lm.x, lm.y),
                z: lm.z,
                visibility: lm.visibility?.floatValue ?? 0
            )
        }

        // 3D world landmarks in metric space (for accurate angle calculations)
        var worldLandmarks: [PoseLandmarkType: SIMD3<Float>] = [:]
        if let worldList = result.worldLandmarks.first {
            for (index, wlm) in worldList.enumerated() {
                guard let type = PoseLandmarkType(rawValue: index) else { continue }
                worldLandmarks[type] = SIMD3<Float>(wlm.x, wlm.y, wlm.z)
            }
        }

        return PoseResult(
            landmarks: landmarks,
            worldLandmarks: worldLandmarks,
            timestamp: Double(timestampMs) / 1000.0
        )
    }
}
