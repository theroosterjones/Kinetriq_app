import AVFoundation
import CoreVideo

/// Hardware-accelerated video writer using AVAssetWriter.
/// Replaces cv2.VideoWriter + ffmpeg re-encode with a single VideoToolbox pass.
final class VideoWriter {

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var framesWritten: Int = 0

    init(outputURL: URL, width: Int, height: Int, fps: Float,
         transform: CGAffineTransform = .identity) throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 4,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: fps
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform

        let sourceAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: sourceAttrs
        )

        writer.add(videoInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        AnalysisLog.videoWriter.info(
            "Writer ready \(width, privacy: .public)x\(height, privacy: .public) @ \(fps, privacy: .public) fps"
        )
    }

    /// Append a processed frame at the given presentation time.
    /// Returns false if the writer has entered an error state.
    @discardableResult
    func append(pixelBuffer: CVPixelBuffer, at time: CMTime) -> Bool {
        guard writer.status == .writing else {
            if framesWritten == 0 || framesWritten % 100 == 0 {
                let err = self.writer.error?.localizedDescription ?? "none"
                AnalysisLog.videoWriter.error(
                    "Writer not writing status=\(self.writer.status.rawValue, privacy: .public) after \(self.framesWritten, privacy: .public) frames: \(err, privacy: .public)"
                )
            }
            return false
        }

        var waitCount = 0
        while !videoInput.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.005)
            waitCount += 1
            if waitCount > 200 {
                AnalysisLog.videoWriter.error(
                    "Writer timed out waiting for input readiness frame=\(self.framesWritten, privacy: .public)"
                )
                return false
            }
        }

        let success = adaptor.append(pixelBuffer, withPresentationTime: time)
        if success {
            framesWritten += 1
        } else {
            let err = self.writer.error?.localizedDescription ?? "unknown"
            AnalysisLog.videoWriter.error(
                "Append failed frame=\(self.framesWritten, privacy: .public) t=\(CMTimeGetSeconds(time), privacy: .public)s err=\(err, privacy: .public)"
            )
        }
        return success
    }

    /// Finalize the video file. Must be called when all frames are written.
    func finalize() async throws {
        videoInput.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error {
            AnalysisLog.videoWriter.error("Finalize failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        AnalysisLog.videoWriter.info("Finalized \(self.framesWritten, privacy: .public) frames")
    }
}
