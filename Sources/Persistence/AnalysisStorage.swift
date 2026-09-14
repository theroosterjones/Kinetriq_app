import Foundation
import AVFoundation
import UIKit
import os.log

private let logger = Logger(subsystem: "com.kevinjones.Kinetriq", category: "AnalysisStorage")

/// App-owned media directory for analyzed videos and their thumbnails.
///
/// Analysis output used to be written straight into `FileManager.temporaryDirectory`,
/// which iOS is free to purge at any time. That was fine while results were discarded
/// on dismiss, but a saved history entry pointing at a purged temp file is a broken
/// row. Output now lands here instead, and records store the bare file name so the
/// container path changing between installs doesn't orphan the library.
///
/// Files live in Application Support and are therefore included in device backups.
/// An analyzed upload could in principle be re-derived from the original clip in
/// Photos, but a live recording only ever exists here — losing those on restore would
/// be worse than the backup size. `totalBytes()` and `delete(fileName:)` back the
/// storage readout and swipe-to-delete in the Progress tab.
enum AnalysisStorage {

    // MARK: - Locations

    static var mediaDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Kinetriq/Media", isDirectory: true)
        ensureDirectoryExists(dir)
        return dir
    }

    static func url(forFileName fileName: String) -> URL? {
        let url = mediaDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Destination for a new analysis run. The analysis writes here directly, so a
    /// saved record needs no copy and there is no window where the file is only in
    /// temp.
    static func videoDestination(for id: UUID) -> URL {
        mediaDirectory.appendingPathComponent("analysis_\(id.uuidString).mp4")
    }

    static func videoFileName(for id: UUID) -> String {
        "analysis_\(id.uuidString).mp4"
    }

    // MARK: - Thumbnails

    /// Renders a poster frame for the history list. Returns the file name, or nil if
    /// the frame could not be generated — a missing thumbnail degrades to an icon
    /// rather than failing the save.
    static func makeThumbnail(from videoURL: URL, id: UUID) async -> String? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        // A frame a little way in is more representative than frame zero, which is
        // often the lifter still setting up.
        let target = CMTime(seconds: 1.0, preferredTimescale: 600)

        do {
            let (cgImage, _) = try await generator.image(at: target)
            guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.75) else {
                return nil
            }
            let fileName = "thumb_\(id.uuidString).jpg"
            try data.write(to: mediaDirectory.appendingPathComponent(fileName), options: .atomic)
            return fileName
        } catch {
            logger.error("Thumbnail generation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Importing

    /// Moves a file that was written elsewhere (a live recording finalized into temp)
    /// into the media directory. Falls back to a copy when the move fails, which can
    /// happen across volumes.
    static func adopt(fileAt source: URL, as fileName: String) -> String? {
        let destination = mediaDirectory.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: source, to: destination)
            return fileName
        } catch {
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                return fileName
            } catch {
                logger.error("Could not adopt \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    // MARK: - Housekeeping

    static func delete(fileName: String?) {
        guard let fileName else { return }
        let url = mediaDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    static func totalBytes() -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: mediaDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        return contents.reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
    }

    static var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes(), countStyle: .file)
    }

    /// Removes media that no longer belongs to any record. Cheap insurance against a
    /// save failing after the video was already written.
    static func pruneOrphans(keeping liveFileNames: Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            atPath: mediaDirectory.path
        ) else { return }

        for name in contents where !liveFileNames.contains(name) {
            try? FileManager.default.removeItem(at: mediaDirectory.appendingPathComponent(name))
        }
    }

    // MARK: - Private

    private static func ensureDirectoryExists(_ url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
