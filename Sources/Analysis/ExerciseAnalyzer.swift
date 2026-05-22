import Foundation
import simd

// MARK: - Exercise Types

enum ExerciseType: String, CaseIterable, Identifiable, Codable {
    case squat = "Squat"
    case deadlift = "Deadlift"
    case lunge = "Lunge"
    case hipHingeSide = "Hip Hinge (Side)"
    case hipHingeBack = "Hip Hinge (Back)"
    case row = "Row"
    case latPulldown = "Lat Pulldown"
    case latPulldownFront = "Lat Pulldown (Front)"
    case overheadPress = "Overhead Press"
    case elbowCurl = "Elbow (Bicep/Tricep)"
    case shoulderAssessment = "Shoulder Assessment"

    var id: String { rawValue }
}

// MARK: - Overlay Mode

enum OverlayMode: String, CaseIterable {
    case simple = "Simple"
    case fullHUD = "Full HUD"
}

// MARK: - Rep State

enum RepState: String {
    case extended
    case flexed
}

// MARK: - Tempo Phase

enum TempoPhase: String, Codable {
    case eccentric    // lowering / lengthening
    case pauseBottom  // hold at bottom
    case concentric   // lifting / shortening
    case pauseTop     // hold at top
}

// MARK: - Joint Angle

enum JointType: String, Codable {
    case knee, hip, elbow, shoulder, spine
}

struct JointAngle: Codable {
    let joint: JointType
    let degrees: Float
}

// MARK: - Overlay Instructions

enum OverlayInstruction {
    case line(from: SIMD2<Float>, to: SIMD2<Float>, color: OverlayColor, width: Float)
    case extendedLine(from: SIMD2<Float>, through: SIMD2<Float>, color: OverlayColor, width: Float)
    case circle(at: SIMD2<Float>, radius: Float, color: OverlayColor, filled: Bool)
    case text(String, at: SIMD2<Float>, color: OverlayColor, size: Float)
}

enum OverlayColor {
    case white, red, green, blue, yellow, cyan, magenta, orange
    case custom(r: Float, g: Float, b: Float, a: Float)

    var rgba: (Float, Float, Float, Float) {
        switch self {
        case .white:   return (1, 1, 1, 1)
        case .red:     return (1, 0, 0, 1)
        case .green:   return (0, 1, 0, 1)
        case .blue:    return (0, 0, 1, 1)
        case .yellow:  return (1, 1, 0, 1)
        case .cyan:    return (0, 1, 1, 1)
        case .magenta: return (1, 0, 1, 1)
        case .orange:  return (1, 0.65, 0, 1)
        case .custom(let r, let g, let b, let a):
            return (r, g, b, a)
        }
    }

    /// Canonical colour for the spine polyline (ear → shoulder → mid-spine → hip).
    /// Distinct from the limb skeleton (yellow/green), joint markers (red/orange),
    /// and reference grids (white/cyan/magenta) so the spine is immediately
    /// readable across every analyzer.
    ///
    /// Tweak the RGB here to retune every spine line in the app at once.
    static let spine: OverlayColor = .custom(r: 0.65, g: 0.35, b: 1.0, a: 1.0)
}

// MARK: - Frame Analysis Result

struct FrameAnalysis {
    let angles: [JointAngle]
    let repCount: Int
    let repState: RepState
    let tempoPhase: TempoPhase?
    let overlayInstructions: [OverlayInstruction]

    static let empty = FrameAnalysis(
        angles: [],
        repCount: 0,
        repState: .extended,
        tempoPhase: nil,
        overlayInstructions: []
    )
}

// MARK: - Analysis Summary (per-video)

struct AnalysisSummary {
    let totalReps: Int
    let averageAngles: [JointAngle]
    let duration: Double
    let tempoBreakdown: [TempoPhase: Double]
    let perRepMetrics: [RepMetric]
    let finalScore: Int?
    /// Fraction of frames where MediaPipe successfully detected a person (0–1).
    /// Low values explain missing overlays/reps without needing Console logs.
    let poseDetectionRate: Float

    init(from frames: [FrameAnalysis], duration: Double,
         repMetrics: [RepMetric] = [], score: Int? = nil,
         poseDetectionRate: Float = 1.0) {
        totalReps = frames.last?.repCount ?? 0
        self.duration = duration
        self.perRepMetrics = repMetrics
        self.finalScore = score
        self.poseDetectionRate = poseDetectionRate

        var angleSums: [JointType: (sum: Float, count: Int)] = [:]
        for frame in frames {
            for angle in frame.angles {
                let existing = angleSums[angle.joint, default: (0, 0)]
                angleSums[angle.joint] = (existing.sum + angle.degrees, existing.count + 1)
            }
        }
        averageAngles = angleSums.map { JointAngle(joint: $0.key, degrees: $0.value.sum / Float($0.value.count)) }

        let frameDuration = frames.isEmpty ? 0 : duration / Double(frames.count)
        var breakdown: [TempoPhase: Double] = [:]
        for frame in frames {
            if let phase = frame.tempoPhase {
                breakdown[phase, default: 0] += frameDuration
            }
        }
        tempoBreakdown = breakdown
    }
}

// MARK: - Base Analyzer Protocol

/// Shared interface for both exercise analyzers and assessment analyzers.
/// Allows VideoProcessor and LiveAnalysisViewModel to operate on either type.
protocol FrameAnalyzerProtocol: AnyObject {
    var requiredLandmarks: [PoseLandmarkType] { get }
    func analyze(landmarks: PoseResult) -> FrameAnalysis
    func reset()
}

// MARK: - Exercise Analyzer Protocol

protocol ExerciseAnalyzer: FrameAnalyzerProtocol {
    var exerciseType: ExerciseType { get }
    var side: BodySide { get }
}

// MARK: - HUD Overlay Builder

/// Generates Full HUD overlay instructions (rep counter, current tempo, per-rep tempo
/// history, and score) from `RepMetricsCollector` state. Called by the pipeline after
/// the analyzer produces its base FrameAnalysis.
///
/// Everything is anchored to a right-side column so it can't collide with analyzer-
/// specific HUD labels (most of which draw at x ≈ 0.02 on the left).
enum HUDOverlayBuilder {

    /// Left edge of the HUD column, in normalized frame coordinates.
    private static let columnX: Float = 0.64
    /// Vertical spacing between per-rep tempo list entries.
    private static let listRowSpacing: Float = 0.032
    /// Maximum number of completed reps to show in the tempo history list.
    private static let maxHistoryRows: Int = 6

    static func instructions(repCount: Int, collector: RepMetricsCollector) -> [OverlayInstruction] {
        var hud: [OverlayInstruction] = []

        // Large rep counter at the top of the column.
        hud.append(.text("Rep \(repCount)",
            at: SIMD2(columnX, 0.03), color: .white, size: 28))

        // Score directly below, colored by threshold.
        if let score = collector.computeScore() {
            let scoreColor: OverlayColor
            if score >= 80 { scoreColor = .green }
            else if score >= 60 { scoreColor = .yellow }
            else { scoreColor = .red }
            hud.append(.text("Score: \(score)",
                at: SIMD2(columnX, 0.085), color: scoreColor, size: 20))
        } else {
            hud.append(.text("Score: --",
                at: SIMD2(columnX, 0.085), color: .white, size: 20))
        }

        // In-progress tempo — present for every exercise whenever the tempo tracker
        // has classified at least one phase. Labeled "Now" so it's obvious this is
        // the live counter and the list below is the per-rep history.
        hud.append(.text("Now: \(collector.currentTempoString())",
            at: SIMD2(columnX, 0.13), color: .cyan, size: 16))

        // Per-rep tempo history — newest at the top, older reps scrolling down.
        let recent = Array(collector.completedReps.suffix(maxHistoryRows).reversed())
        if !recent.isEmpty {
            hud.append(.text("History",
                at: SIMD2(columnX, 0.17), color: .white, size: 13))
            for (i, rep) in recent.enumerated() {
                let y = 0.205 + Float(i) * listRowSpacing
                hud.append(.text("Rep \(rep.repNumber):  \(rep.tempoString)",
                    at: SIMD2(columnX, y), color: .white, size: 14))
            }
        }

        return hud
    }
}
