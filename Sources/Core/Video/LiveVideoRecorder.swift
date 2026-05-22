import AVFoundation
import CoreMedia
import os.log

private let logger = Logger(subsystem: "com.kevinjones.Kinetriq", category: "LiveVideoRecorder")

/// Writes CVPixelBuffers (with overlay already applied) to an H.264 MP4 file in real time.
final class LiveVideoRecorder {

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor

    private var startTime: CMTime?
    private var lastTime: CMTime = .negativeInfinity

    let outputURL: URL

    // MARK: - Init

    init(outputURL: URL, width: Int, height: Int) throws {
        self.outputURL = outputURL
        try? FileManager.default.removeItem(at: outputURL)

        writer = try AVAssetWriter(url: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 4,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 30
            ]
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        writer.add(input)
        writer.startWriting()
        logger.info("LiveVideoRecorder started → \(outputURL.lastPathComponent)")
    }

    // MARK: - Append

    /// Append a frame. Must be called sequentially (serial camera queue).
    func append(pixelBuffer: CVPixelBuffer, at time: CMTime) {
        if startTime == nil {
            startTime = time
            writer.startSession(atSourceTime: time)
        }

        guard time > lastTime else { return }
        lastTime = time

        guard input.isReadyForMoreMediaData else {
            logger.debug("Input busy at \(CMTimeGetSeconds(time), format: .fixed(precision: 2))s — dropping frame")
            return
        }

        if !adaptor.append(pixelBuffer, withPresentationTime: time) {
            logger.error("Append failed: \(self.writer.error?.localizedDescription ?? "unknown")")
        }
    }

    // MARK: - Finalize

    /// Finalizes the file and returns its URL. Throws if the writer encountered an error.
    func finalize() async throws -> URL {
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error {
            logger.error("Finalize failed: \(error.localizedDescription)")
            throw error
        }
        logger.info("LiveVideoRecorder finalized: \(self.outputURL.lastPathComponent)")
        return outputURL
    }
}
