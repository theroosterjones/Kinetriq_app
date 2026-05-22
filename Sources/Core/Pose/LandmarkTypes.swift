import Foundation
import simd

/// Body side for exercise analysis.
enum BodySide: String, CaseIterable, Codable {
    case left, right

    var opposite: BodySide {
        self == .left ? .right : .left
    }
}

/// Maps to MediaPipe Pose Landmarker's 33-point model.
/// Index values match the MediaPipe PoseLandmark enum exactly.
enum PoseLandmarkType: Int, CaseIterable {
    case nose = 0
    case leftEyeInner = 1
    case leftEye = 2
    case leftEyeOuter = 3
    case rightEyeInner = 4
    case rightEye = 5
    case rightEyeOuter = 6
    case leftEar = 7
    case rightEar = 8
    case mouthLeft = 9
    case mouthRight = 10
    case leftShoulder = 11
    case rightShoulder = 12
    case leftElbow = 13
    case rightElbow = 14
    case leftWrist = 15
    case rightWrist = 16
    case leftPinky = 17
    case rightPinky = 18
    case leftIndex = 19
    case rightIndex = 20
    case leftThumb = 21
    case rightThumb = 22
    case leftHip = 23
    case rightHip = 24
    case leftKnee = 25
    case rightKnee = 26
    case leftAnkle = 27
    case rightAnkle = 28
    case leftHeel = 29
    case rightHeel = 30
    case leftFootIndex = 31
    case rightFootIndex = 32

    // MARK: - Side-aware accessors

    static func shoulder(_ side: BodySide) -> PoseLandmarkType {
        side == .left ? .leftShoulder : .rightShoulder
    }
    static func elbow(_ side: BodySide) -> PoseLandmarkType {
        side == .left ? .leftElbow : .rightElbow
    }
    static func wrist(_ side: BodySide) -> PoseLandmarkType {
        side == .left ? .leftWrist : .rightWrist
    }
    static func hip(_ side: BodySide) -> PoseLandmarkType {
        side == .left ? .leftHip : .rightHip
    }
    static func knee(_ side: BodySide) -> PoseLandmarkType {
        side == .left ? .leftKnee : .rightKnee
    }
    static func ankle(_ side: BodySide) -> PoseLandmarkType {
        side == .left ? .leftAnkle : .rightAnkle
    }
    static func ear(_ side: BodySide) -> PoseLandmarkType {
        side == .left ? .leftEar : .rightEar
    }
}

/// A single detected landmark with normalized (0–1) coordinates and confidence.
struct NormalizedLandmark {
    let position: SIMD2<Float>   // x, y in [0, 1]
    let z: Float                  // depth (relative to hip midpoint)
    let visibility: Float         // 0–1 confidence
}

/// Full pose detection result for a single frame.
struct PoseResult {
    let landmarks: [PoseLandmarkType: NormalizedLandmark]
    /// Metric 3D world positions (meters, origin = hip midpoint, y-up).
    /// Empty when the model returns no world landmarks.
    let worldLandmarks: [PoseLandmarkType: SIMD3<Float>]
    let timestamp: Double  // seconds

    /// Normalized 2D screen position (0–1). Used for overlay drawing.
    func position(for type: PoseLandmarkType) -> SIMD2<Float>? {
        landmarks[type]?.position
    }

    /// Landmark visibility confidence (0-1).
    func visibility(for type: PoseLandmarkType) -> Float {
        landmarks[type]?.visibility ?? 0
    }

    /// Metric 3D world position. Used for accurate angle calculations.
    func worldPosition(for type: PoseLandmarkType) -> SIMD3<Float>? {
        worldLandmarks[type]
    }
}
