import Foundation
import os

/// Unified subsystem for saved-video and analysis diagnostics.
/// Uses `Logger` only (no file I/O) so the analysis loop stays fast.
enum AnalysisLog {

    static let subsystem = "com.kevinjones.KevLines2-0"

    static let pipeline = Logger(subsystem: subsystem, category: "Pipeline")
    static let pose = Logger(subsystem: subsystem, category: "Pose")
    static let videoReader = Logger(subsystem: subsystem, category: "VideoReader")
    static let videoWriter = Logger(subsystem: subsystem, category: "VideoWriter")
    static let ui = Logger(subsystem: subsystem, category: "ExerciseUI")

    /// Stable label for Instruments / Console filtering (not called per frame).
    static func analyzerLabel(_ analyzer: FrameAnalyzerProtocol) -> String {
        String(describing: type(of: analyzer))
    }
}
