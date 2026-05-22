import AVFoundation
import CoreVideo

/// Hardware-accelerated video frame reader using AVAssetReader.
///
/// iPhone-recorded videos store pixel buffers in native storage orientation and rely on
/// `preferredTransform` so QuickTime / Photos display upright. MediaPipe ignores that
/// metadata, so we must feed pixels that match **what the user sees** in those apps.
///
/// **Implementation:** we route decoding through `AVMutableVideoComposition` +
/// `AVAssetReaderVideoCompositionOutput`. AVFoundation applies the same transform math
/// as playback, producing upright BGRA frames—no manual Core Image rotation (which
/// mixed coordinate systems and produced upside-down, mirrored, or left/right–swapped
/// output relative to the saved clip). Writers keep `outputTransform = .identity`.
final class VideoReader {

    /// Native pixel dimensions (decoder buffer before display transform). For logs only.
    let nativeWidth: Int
    let nativeHeight: Int

    /// Dimensions of each frame returned by `nextFrame()` (display-oriented pixels).
    let displayWidth: Int
    let displayHeight: Int

    var outputWidth: Int { displayWidth }
    var outputHeight: Int { displayHeight }

    /// Writers use `.identity` — orientation is already baked by the video composition.
    var outputTransform: CGAffineTransform { .identity }

    let fps: Float
    let duration: CMTime
    let estimatedFrameCount: Int

    /// The source track’s preferred transform (diagnostics).
    let preferredTransform: CGAffineTransform

    private let reader: AVAssetReader
    private let output: AVAssetReaderVideoCompositionOutput

    private(set) var currentTime: CMTime = .zero
    private var frameIndex: Int = 0

    private var retainedSampleBuffer: CMSampleBuffer?

    init(url: URL) throws {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw VideoReaderError.noVideoTrack
        }

        let nativeSize = videoTrack.naturalSize
        nativeWidth = Int(nativeSize.width)
        nativeHeight = Int(nativeSize.height)

        let transform = videoTrack.preferredTransform
        preferredTransform = transform

        // Bounding box of the transformed natural rect → render size (matches AVPlayer).
        let transformedVideoRect = CGRect(origin: .zero, size: nativeSize).applying(transform)
        let renderSize = CGSize(
            width: abs(transformedVideoRect.width),
            height: abs(transformedVideoRect.height)
        )
        displayWidth = Int(renderSize.width.rounded())
        displayHeight = Int(renderSize.height.rounded())

        fps = videoTrack.nominalFrameRate
        duration = asset.duration
        let fpsForEstimate = fps > 0 ? fps : 30
        estimatedFrameCount = Int(Float(CMTimeGetSeconds(duration)) * fpsForEstimate)

        // Shift composed output so the rotated rect sits in +x,+y (standard composition recipe).
        let translateToPositiveOrigin = CGAffineTransform(
            translationX: -transformedVideoRect.origin.x,
            y: -transformedVideoRect.origin.y
        )
        let combinedTransform = transform.concatenating(translateToPositiveOrigin)

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoReaderError.compositionFailed
        }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: asset.duration),
            of: videoTrack,
            at: .zero
        )

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(combinedTransform, at: .zero)

        let mainInstruction = AVMutableVideoCompositionInstruction()
        mainInstruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        mainInstruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        let nominal = videoTrack.nominalFrameRate
        let timescale: Int32 = nominal > 0 ? max(1, Int32(nominal.rounded())) : 30
        videoComposition.frameDuration = CMTime(value: 1, timescale: timescale)
        videoComposition.instructions = [mainInstruction]

        reader = try AVAssetReader(asset: composition)

        output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [compositionVideoTrack],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        output.videoComposition = videoComposition
        output.alwaysCopiesSampleData = true

        reader.add(output)
        reader.startReading()

        AnalysisLog.videoReader.info(
            "Composition decode \(self.nativeWidth, privacy: .public)x\(self.nativeHeight, privacy: .public) native → \(self.displayWidth, privacy: .public)x\(self.displayHeight, privacy: .public) display \(self.fps, privacy: .public) fps \(CMTimeGetSeconds(self.duration), privacy: .public)s ~\(self.estimatedFrameCount, privacy: .public) frames"
        )
    }

    /// Decoded frame in display orientation (matches Photos / QuickTime).
    func nextFrame() -> (pixelBuffer: CVPixelBuffer, time: CMTime)? {
        guard reader.status == .reading else {
            if reader.status == .failed {
                let err = self.reader.error?.localizedDescription ?? "unknown"
                AnalysisLog.videoReader.error(
                    "AVAssetReader failed at frame \(self.frameIndex, privacy: .public): \(err, privacy: .public)"
                )
            } else {
                AnalysisLog.videoReader.info(
                    "Reader ended status=\(String(describing: self.reader.status), privacy: .public) frame=\(self.frameIndex, privacy: .public)"
                )
            }
            return nil
        }

        guard let sampleBuffer = output.copyNextSampleBuffer() else {
            if reader.status == .failed {
                let err = self.reader.error?.localizedDescription ?? "unknown"
                AnalysisLog.videoReader.error(
                    "Reader failed after \(self.frameIndex, privacy: .public) frames: \(err, privacy: .public)"
                )
            } else {
                AnalysisLog.videoReader.info("Finished reading \(self.frameIndex, privacy: .public) frames")
            }
            return nil
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            AnalysisLog.videoReader.error("Frame \(self.frameIndex, privacy: .public): no image buffer in sample")
            return nil
        }

        retainedSampleBuffer = sampleBuffer
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        currentTime = pts
        frameIndex += 1

        return (pixelBuffer, pts)
    }

    var progress: Float {
        guard estimatedFrameCount > 0 else { return 0 }
        return Float(frameIndex) / Float(estimatedFrameCount)
    }

    enum VideoReaderError: Error, LocalizedError {
        case noVideoTrack
        case compositionFailed

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "No video track found in asset."
            case .compositionFailed: return "Could not create a mutable composition track."
            }
        }
    }
}
