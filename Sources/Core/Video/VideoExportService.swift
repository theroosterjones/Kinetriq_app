import AVFoundation
import CoreGraphics

/// Content-export presets applied to an already-analyzed clip before sharing.
struct ContentExportPreset: Equatable {
    /// Re-render the overlay at a different density (only relevant for exercises).
    var overlayMode: OverlayMode
    /// Center-crop to a vertical 9:16 frame for Reels / TikTok / Stories.
    var cropToReels: Bool
}

enum VideoExportError: LocalizedError {
    case noVideoTrack
    case cannotCreateExportSession
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The video has no playable track to export."
        case .cannotCreateExportSession:
            return "This device could not prepare the video for export."
        case .exportFailed(let details):
            return "Export failed. \(details)"
        }
    }
}

/// Post-processes an analyzed clip for sharing — currently a center 9:16 crop for
/// vertical social formats. The overlays are already baked into the source clip,
/// so this is a pure transform/export step.
enum VideoExportService {

    /// Produces a center-cropped 9:16 copy of `sourceURL`.
    static func cropToReels(sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw VideoExportError.noVideoTrack }

        let (naturalSize, preferredTransform) = try await track.load(.naturalSize, .preferredTransform)
        let duration = try await asset.load(.duration)

        // Oriented (display) size after applying the track's preferred transform.
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        guard orientedSize.width > 0, orientedSize.height > 0 else { throw VideoExportError.noVideoTrack }

        let targetAspect: CGFloat = 9.0 / 16.0
        var targetW: CGFloat
        var targetH: CGFloat
        if orientedSize.width / orientedSize.height >= targetAspect {
            targetH = orientedSize.height
            targetW = (targetH * targetAspect).rounded()
        } else {
            targetW = orientedSize.width
            targetH = (targetW / targetAspect).rounded()
        }
        // H.264 requires even dimensions.
        let renderSize = CGSize(width: evenValue(targetW), height: evenValue(targetH))

        // Fill the render frame (scale is 1 for a pure crop since one axis matches).
        let fillScale = max(renderSize.width / orientedSize.width,
                            renderSize.height / orientedSize.height)
        let centerTx = (renderSize.width - orientedSize.width * fillScale) / 2
        let centerTy = (renderSize.height - orientedSize.height * fillScale) / 2

        let finalTransform = preferredTransform
            .concatenating(CGAffineTransform(translationX: -transformedRect.origin.x,
                                             y: -transformedRect.origin.y))
            .concatenating(CGAffineTransform(scaleX: fillScale, y: fillScale))
            .concatenating(CGAffineTransform(translationX: centerTx, y: centerTy))

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(finalTransform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.instructions = [instruction]
        let fps = try await track.load(.nominalFrameRate)
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps > 0 ? fps.rounded() : 30))

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoExportError.cannotCreateExportSession
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinetriq_reels_\(UUID().uuidString).mp4")
        export.outputURL = outputURL
        export.outputFileType = .mp4
        export.videoComposition = videoComposition
        export.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            export.exportAsynchronously {
                switch export.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed, .cancelled:
                    continuation.resume(throwing: VideoExportError.exportFailed(
                        export.error?.localizedDescription ?? "Unknown export error."))
                default:
                    continuation.resume(throwing: VideoExportError.exportFailed(
                        "Export ended with status \(export.status.rawValue)."))
                }
            }
        }

        return outputURL
    }

    private static func evenValue(_ value: CGFloat) -> CGFloat {
        let rounded = value.rounded()
        return rounded.truncatingRemainder(dividingBy: 2) == 0 ? rounded : rounded + 1
    }
}
