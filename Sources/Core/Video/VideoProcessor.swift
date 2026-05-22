import AVFoundation
import CoreVideo

/// Orchestrates the full local pipeline: read -> pose -> analyze -> overlay -> write.
final class VideoProcessor: ObservableObject {

    @Published var progress: Float = 0
    @Published var isProcessing = false

    private let poseLandmarker: PoseLandmarkerService
    private let overlayRenderer: OverlayRenderer

    init(
        poseLandmarker: PoseLandmarkerService = PoseLandmarkerService(),
        overlayRenderer: OverlayRenderer = OverlayRenderer()
    ) {
        self.poseLandmarker = poseLandmarker
        self.overlayRenderer = overlayRenderer
    }

    func process(
        inputURL: URL,
        outputURL: URL,
        analyzer: FrameAnalyzerProtocol,
        overlayMode: OverlayMode = .simple
    ) async throws -> AnalysisSummary {
        await MainActor.run {
            isProcessing = true
            progress = 0
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        let reader = try VideoReader(url: inputURL)

        // Reader emits already-rotated buffers in display orientation, so the
        // writer dimensions must match `outputWidth/Height` and the rotation
        // transform must be identity to avoid double-rotation on playback.
        let writer = try VideoWriter(
            outputURL: outputURL,
            width: reader.outputWidth,
            height: reader.outputHeight,
            fps: reader.fps,
            transform: reader.outputTransform
        )

        let analyzerName = AnalysisLog.analyzerLabel(analyzer)
        AnalysisLog.pipeline.info(
            "Analyze start input=\(inputURL.lastPathComponent, privacy: .public) output=\(outputURL.lastPathComponent, privacy: .public) analyzer=\(analyzerName, privacy: .public) overlayMode=\(String(describing: overlayMode), privacy: .public) size=\(reader.outputWidth, privacy: .public)x\(reader.outputHeight, privacy: .public) native=\(reader.nativeWidth, privacy: .public)x\(reader.nativeHeight, privacy: .public) frames≈\(reader.estimatedFrameCount, privacy: .public) duration=\(CMTimeGetSeconds(reader.duration), privacy: .public)s"
        )

        analyzer.reset()

        let result: AnalysisSummary = try await Task.detached(priority: .userInitiated) {
            [poseLandmarker, overlayRenderer] in

            poseLandmarker.resetForNewSession()

            var allFrameResults: [FrameAnalysis] = []
            var poseDetections = 0
            var poseMissFrames = 0
            var framesPoseOkEmptyOverlay = 0
            var writeFailures = 0
            let metricsCollector = RepMetricsCollector()

            while let (pixelBuffer, time) = reader.nextFrame() {
                let timestampMs = Int(CMTimeGetSeconds(time) * 1000)
                let timeSec = CMTimeGetSeconds(time)

                let poseResult = poseLandmarker.detect(
                    pixelBuffer: pixelBuffer,
                    timestampMs: timestampMs
                )

                let frameResult: FrameAnalysis
                if let poseResult {
                    frameResult = analyzer.analyze(landmarks: poseResult)
                    poseDetections += 1
                    if frameResult.overlayInstructions.isEmpty {
                        framesPoseOkEmptyOverlay += 1
                    }
                } else {
                    poseMissFrames += 1
                    frameResult = FrameAnalysis.empty
                }
                allFrameResults.append(frameResult)

                // Feed rep metrics collector
                let primaryAngle = frameResult.angles.first?.degrees ?? 0
                metricsCollector.update(
                    phase: frameResult.tempoPhase,
                    angle: primaryAngle,
                    repCount: frameResult.repCount,
                    timestamp: timeSec
                )

                // Build final instruction list: base overlay + optional HUD
                var finalInstructions = frameResult.overlayInstructions
                if overlayMode == .fullHUD {
                    finalInstructions.append(contentsOf:
                        HUDOverlayBuilder.instructions(
                            repCount: frameResult.repCount,
                            collector: metricsCollector))
                }

                overlayRenderer.render(
                    instructions: finalInstructions,
                    onto: pixelBuffer
                )

                if !writer.append(pixelBuffer: pixelBuffer, at: time) {
                    if writeFailures == 0 {
                        AnalysisLog.pipeline.error(
                            "First writer append failure frame=\(allFrameResults.count, privacy: .public) t=\(CMTimeGetSeconds(time), privacy: .public)s — check VideoWriter logs"
                        )
                    }
                    writeFailures += 1
                    if writeFailures > 5 {
                        AnalysisLog.pipeline.error("Too many write failures — stopping pipeline early")
                        break
                    }
                }

                if allFrameResults.count % 10 == 0 {
                    let p = reader.progress
                    await MainActor.run { [p] in
                        self.progress = p
                    }
                }
            }

            do {
                try await writer.finalize()
            } catch {
                AnalysisLog.pipeline.error(
                    "Writer finalize failed: \(error.localizedDescription, privacy: .public)"
                )
                throw error
            }

            let totalFrames = allFrameResults.count
            let detPct = totalFrames > 0 ? Int(Float(poseDetections) / Float(totalFrames) * 100) : 0
            AnalysisLog.pipeline.info(
                "Analyze done frames=\(totalFrames, privacy: .public) poseHits=\(poseDetections, privacy: .public) (\(detPct, privacy: .public)%) poseMiss=\(poseMissFrames, privacy: .public) poseOkEmptyOverlay=\(framesPoseOkEmptyOverlay, privacy: .public) writeFailures=\(writeFailures, privacy: .public)"
            )

            await MainActor.run {
                self.progress = 1.0
            }

            let detectionRate = totalFrames > 0 ? Float(poseDetections) / Float(totalFrames) : 0
            return AnalysisSummary(
                from: allFrameResults,
                duration: CMTimeGetSeconds(reader.duration),
                repMetrics: metricsCollector.completedReps,
                score: metricsCollector.computeScore(),
                poseDetectionRate: detectionRate
            )
        }.value

        return result
    }
}
