import SwiftUI
import UIKit
import PhotosUI
import Photos
import AVKit
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: "com.kevinjones.Kinetriq", category: "ExerciseView")

/// Transferable wrapper so PhotosPicker can prepare and hand us a video file URL.
///
/// Important: `shouldAttemptToOpenInPlace` is intentionally `false`. Some Photos
/// videos that previously loaded successfully fail when we ask for the original
/// file in place; letting Photos prepare/copy the file is slower in rare cases but
/// much more compatible.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .audiovisualContent,
                           shouldAttemptToOpenInPlace: false,
                           exporting: { SentTransferredFile($0.url) },
                           importing: { try Self(url: copyToTemp($0.file)) })
        FileRepresentation(contentType: .movie,
                           shouldAttemptToOpenInPlace: false,
                           exporting: { SentTransferredFile($0.url) },
                           importing: { try Self(url: copyToTemp($0.file)) })
        FileRepresentation(contentType: .quickTimeMovie,
                           shouldAttemptToOpenInPlace: false,
                           exporting: { SentTransferredFile($0.url) },
                           importing: { try Self(url: copyToTemp($0.file)) })
        FileRepresentation(contentType: .mpeg4Movie,
                           shouldAttemptToOpenInPlace: false,
                           exporting: { SentTransferredFile($0.url) },
                           importing: { try Self(url: copyToTemp($0.file)) })
    }
}

/// Last-resort wrapper asking Photos for the original file directly.
struct OriginalPickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .audiovisualContent,
                           shouldAttemptToOpenInPlace: true,
                           exporting: { SentTransferredFile($0.url) },
                           importing: { try Self(url: copyToTemp($0.file)) })
        FileRepresentation(contentType: .movie,
                           shouldAttemptToOpenInPlace: true,
                           exporting: { SentTransferredFile($0.url) },
                           importing: { try Self(url: copyToTemp($0.file)) })
        FileRepresentation(contentType: .quickTimeMovie,
                           shouldAttemptToOpenInPlace: true,
                           exporting: { SentTransferredFile($0.url) },
                           importing: { try Self(url: copyToTemp($0.file)) })
        FileRepresentation(contentType: .mpeg4Movie,
                           shouldAttemptToOpenInPlace: true,
                           exporting: { SentTransferredFile($0.url) },
                           importing: { try Self(url: copyToTemp($0.file)) })
    }
}

private enum VideoLoadError: LocalizedError {
    case selectedItemNotVideo
    case photosAssetUnavailable
    case photosRequestCancelled
    case photosRequestFailed(String)
    case assetExportUnavailable
    case assetExportFailed(String)
    case transferableFailed(String)
    case noUsableFile

    var errorDescription: String? {
        switch self {
        case .selectedItemNotVideo:
            return "The selected item does not appear to be a video. Please choose a video from Photos."
        case .photosAssetUnavailable:
            return "Kinetriq could not access that video from Photos. If the video is stored in iCloud, open it in Photos first so it downloads locally, then try again."
        case .photosRequestCancelled:
            return "The video load was cancelled by Photos. Please try selecting the video again."
        case .photosRequestFailed(let details):
            return "Photos could not prepare this video for analysis. \(details)"
        case .assetExportUnavailable:
            return "This video format could not be prepared for analysis on this device."
        case .assetExportFailed(let details):
            return "Kinetriq could not copy this video into a format it can analyze. \(details)"
        case .transferableFailed(let details):
            return "Photos could not provide a usable video file. \(details)"
        case .noUsableFile:
            return "Kinetriq could not load a usable video file. Try duplicating the video in Photos or exporting it as a regular video, then select the copy."
        }
    }
}

private func copyToTemp(_ file: URL) throws -> URL {
    let ext = file.pathExtension.isEmpty ? "mov" : file.pathExtension
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(ext)
    let scoped = file.startAccessingSecurityScopedResource()
    defer {
        if scoped { file.stopAccessingSecurityScopedResource() }
    }
    try FileManager.default.copyItem(at: file, to: dest)
    return dest
}

private func loadVideoURL(
    from item: PhotosPickerItem,
    statusUpdate: @escaping @MainActor (String) -> Void
) async throws -> URL {
    var failures: [String] = []

    // First try the most compatible path: let Photos prepare/copy the video.
    // This is closest to the previous behavior that worked for the user's clips.
    await statusUpdate("Preparing video file...")
    do {
        if let movie = try await item.loadTransferable(type: PickedMovie.self) {
            return movie.url
        }
    } catch {
        failures.append("prepared file: \(error.localizedDescription)")
    }

    // Then try direct Photos asset access/export.
    await statusUpdate("Accessing video from Photos...")
    if let localIdentifier = item.itemIdentifier {
        do {
            if let url = try await loadVideoURLFromPhotosAsset(
                localIdentifier: localIdentifier,
                statusUpdate: statusUpdate
            ) {
                return url
            }
        } catch VideoLoadError.selectedItemNotVideo {
            throw VideoLoadError.selectedItemNotVideo
        } catch {
            failures.append("Photos asset: \(error.localizedDescription)")
        }
    }

    // Last resort: ask for the original in-place file.
    await statusUpdate("Trying original video file...")
    do {
        if let movie = try await item.loadTransferable(type: OriginalPickedMovie.self) {
            return movie.url
        }
    } catch {
        failures.append("original file: \(error.localizedDescription)")
    }

    if failures.isEmpty {
        throw VideoLoadError.noUsableFile
    }
    throw VideoLoadError.transferableFailed(failures.joined(separator: " | "))
}

private func loadVideoURLFromPhotosAsset(
    localIdentifier: String,
    statusUpdate: @escaping @MainActor (String) -> Void
) async throws -> URL? {
    try await withCheckedThrowingContinuation { continuation in
        let results = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = results.firstObject else {
            continuation.resume(returning: nil)
            return
        }

        guard asset.mediaType == .video else {
            continuation.resume(throwing: VideoLoadError.selectedItemNotVideo)
            return
        }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
            if let error = info?[PHImageErrorKey] as? Error {
                continuation.resume(throwing: VideoLoadError.photosRequestFailed(error.localizedDescription))
                return
            }

            if (info?[PHImageCancelledKey] as? Bool) == true {
                continuation.resume(throwing: VideoLoadError.photosRequestCancelled)
                return
            }

            guard let avAsset else {
                continuation.resume(throwing: VideoLoadError.photosAssetUnavailable)
                return
            }

            Task {
                do {
                    let url = try await temporaryVideoURL(from: avAsset, statusUpdate: statusUpdate)
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private func temporaryVideoURL(
    from asset: AVAsset,
    statusUpdate: @escaping @MainActor (String) -> Void
) async throws -> URL {
    if let urlAsset = asset as? AVURLAsset {
        await statusUpdate("Copying video for analysis...")
        return try copyToTemp(urlAsset.url)
    }

    await statusUpdate("Preparing video for analysis...")
    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
        throw VideoLoadError.assetExportUnavailable
    }

    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mov")
    export.outputURL = outputURL
    export.outputFileType = .mov
    export.shouldOptimizeForNetworkUse = false

    try await withCheckedThrowingContinuation { continuation in
        export.exportAsynchronously {
            switch export.status {
            case .completed:
                continuation.resume(returning: ())
            case .cancelled:
                continuation.resume(throwing: VideoLoadError.photosRequestCancelled)
            case .failed:
                continuation.resume(throwing: VideoLoadError.assetExportFailed(
                    export.error?.localizedDescription ?? "Unknown export failure."
                ))
            default:
                continuation.resume(throwing: VideoLoadError.assetExportFailed("Export ended with status \(export.status.rawValue)."))
            }
        }
    }

    return outputURL
}

private enum AnalysisMode: String, CaseIterable {
    case savedVideo  = "Saved Video"
    case liveCamera  = "Live Camera"
}

struct ExerciseView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var processor = VideoProcessor()

    @State private var analysisMode: AnalysisMode = .savedVideo
    @State private var analysisCategory: AnalysisCategory = .exercise
    @State private var selectedExerciseType: ExerciseType = .squat
    @State private var selectedAssessmentType: AssessmentType = .shoulderFlexion
    @State private var selectedAssessmentPlane: ViewPlane = AssessmentConfig.all.first(
        where: { $0.type == .shoulderFlexion }
    )?.defaultPlane ?? .frontal
    @State private var selectedSide: BodySide = .left
    @State private var overlayMode: OverlayMode = .fullHUD
    @State private var customOverlayOptions: Set<CustomOverlayOption> = []
    @State private var showCustomOverlays = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var analyzedVideoURL: URL?
    @State private var analyzedOverlayMode: OverlayMode?
    @State private var analysisSummary: AnalysisSummary?
    @State private var assessmentMetrics: AssessmentMetrics?
    @State private var player: AVPlayer?
    @State private var isLoadingSelectedVideo = false
    @State private var videoLoadingStatus = "Loading video..."

    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var sharePayload: SharePayload?
    @State private var showingFullScreenAnalyzedVideo = false

    // Content-export preset selections.
    @State private var showingExportOptions = false
    @State private var exportOverlayStyle: OverlayMode = .fullHUD
    @State private var exportCropReels = false
    @State private var isPreparingExport = false

    @State private var hasRestoredSettings = false

    private var selectedExercise: ExerciseConfig {
        ExerciseConfig.all.first { $0.type == selectedExerciseType } ?? ExerciseConfig.all[0]
    }

    private var selectedAssessment: AssessmentConfig {
        AssessmentConfig.all.first { $0.type == selectedAssessmentType } ?? AssessmentConfig.all[0]
    }

    private var currentRequiresSideSelection: Bool {
        if analysisCategory == .exercise {
            return selectedExercise.requiresSideSelection
        }
        return selectedAssessment.requiresSideSelection(plane: selectedAssessmentPlane)
    }

    private var currentCameraSetupTip: String {
        if analysisCategory == .exercise {
            return selectedExerciseType.cameraSetupTip
        }
        return selectedAssessmentType.cameraSetupTip(for: selectedAssessmentPlane)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KScreenBackground()
                ScrollView {
                    VStack(spacing: KSpacing.lg) {
                        modePicker

                        if analysisMode == .savedVideo {
                            setupCard
                            cameraTipBanner
                            videoHero
                            loadingVideoSection
                            analyzeSection
                            resultsSection
                            shareActionsSection
                        } else {
                            liveCameraHero
                        }
                    }
                    .padding(.horizontal, KSpacing.screenH)
                    .padding(.top, KSpacing.xs)
                    .padding(.bottom, KSpacing.xxl)
                }
            }
            .navigationTitle("Analyze")
            .navigationBarTitleDisplayMode(.large)
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: payload.items)
            }
            .sheet(isPresented: $showingExportOptions) {
                exportOptionsSheet
            }
            .fullScreenCover(isPresented: $showingFullScreenAnalyzedVideo) {
                if let url = analyzedVideoURL {
                    FullScreenVideoPlayer(url: url)
                }
            }
            .onChange(of: selectedVideoItem) { _, newItem in
                Task { await loadVideo(from: newItem) }
            }
            .onAppear {
                restoreSettingsIfNeeded()
                consumePendingRequest()
            }
            .onChange(of: router.pendingRequest) { _, _ in consumePendingRequest() }
            .onChange(of: analysisCategory) { _, _ in persistSettings() }
            .onChange(of: selectedExerciseType) { _, _ in persistSettings() }
            .onChange(of: selectedAssessmentType) { _, _ in persistSettings() }
            .onChange(of: selectedAssessmentPlane) { _, _ in persistSettings() }
            .onChange(of: selectedSide) { _, _ in persistSettings() }
            .onChange(of: overlayMode) { _, _ in persistSettings() }
            .onChange(of: customOverlayOptions) { _, _ in persistSettings() }
        }
    }

    // MARK: - Remember last analysis settings

    private func restoreSettingsIfNeeded() {
        guard !hasRestoredSettings else { return }
        hasRestoredSettings = true

        let fallback = AnalysisSettingsStore.Snapshot(
            category: analysisCategory,
            exercise: selectedExerciseType,
            assessment: selectedAssessmentType,
            plane: selectedAssessmentPlane,
            side: selectedSide,
            overlayMode: overlayMode,
            customOverlays: customOverlayOptions
        )
        let restored = AnalysisSettingsStore.load(defaults: fallback)

        analysisCategory = restored.category
        selectedExerciseType = restored.exercise
        selectedAssessmentType = restored.assessment
        selectedSide = restored.side
        overlayMode = restored.overlayMode
        customOverlayOptions = restored.customOverlays

        // Clamp the restored plane to one the assessment actually supports.
        if let cfg = AssessmentConfig.all.first(where: { $0.type == restored.assessment }) {
            selectedAssessmentPlane = cfg.supportedPlanes.contains(restored.plane)
                ? restored.plane
                : cfg.defaultPlane
        } else {
            selectedAssessmentPlane = restored.plane
        }
    }

    private func persistSettings() {
        guard hasRestoredSettings else { return }
        AnalysisSettingsStore.save(.init(
            category: analysisCategory,
            exercise: selectedExerciseType,
            assessment: selectedAssessmentType,
            plane: selectedAssessmentPlane,
            side: selectedSide,
            overlayMode: overlayMode,
            customOverlays: customOverlayOptions
        ))
    }

    // MARK: - Deep link from Home / Library

    private func consumePendingRequest() {
        guard let req = router.pendingRequest else { return }
        analysisMode = req.mode == .liveCamera ? .liveCamera : .savedVideo
        analysisCategory = req.category
        if let ex = req.exercise { selectedExerciseType = ex }
        if let asmt = req.assessment {
            selectedAssessmentType = asmt
            if let cfg = AssessmentConfig.all.first(where: { $0.type == asmt }),
               !cfg.supportedPlanes.contains(selectedAssessmentPlane) {
                selectedAssessmentPlane = cfg.defaultPlane
            }
        }
        router.pendingRequest = nil
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        Picker("Mode", selection: $analysisMode.animation(.snappy)) {
            ForEach(AnalysisMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, KSpacing.xs)
    }

    // MARK: - Setup card (all configuration in one calm surface)

    private var setupCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.md) {
                fieldLabel("Category")
                Picker("Category", selection: $analysisCategory.animation(.snappy)) {
                    ForEach(AnalysisCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                .pickerStyle(.segmented)

                Divider().overlay(KColor.separator)

                exerciseOrAssessmentPicker

                if analysisCategory == .assessment {
                    assessmentPlanePicker
                }

                if currentRequiresSideSelection {
                    fieldLabel("Working side")
                    Picker("Side", selection: $selectedSide) {
                        Text("Left").tag(BodySide.left)
                        Text("Right").tag(BodySide.right)
                    }
                    .pickerStyle(.segmented)
                }

                if analysisCategory == .exercise {
                    Divider().overlay(KColor.separator)
                    fieldLabel("Overlay")
                    Picker("Overlay", selection: $overlayMode) {
                        ForEach(OverlayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    customOverlayDisclosure
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Eyebrow(text: text)
    }

    @ViewBuilder
    private var exerciseOrAssessmentPicker: some View {
        HStack {
            fieldLabel(analysisCategory == .exercise ? "Exercise" : "Assessment")
            Spacer()
            if analysisCategory == .exercise {
                Picker("Exercise", selection: $selectedExerciseType) {
                    ForEach(ExerciseConfig.all, id: \.type) { exercise in
                        Text(exercise.displayName).tag(exercise.type)
                    }
                }
                .pickerStyle(.menu)
                .tint(KColor.accent)
            } else {
                Picker("Assessment", selection: $selectedAssessmentType) {
                    ForEach(AssessmentType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .tint(KColor.accent)
                .onChange(of: selectedAssessmentType) { _, newType in
                    if let cfg = AssessmentConfig.all.first(where: { $0.type == newType }) {
                        if !cfg.supportedPlanes.contains(selectedAssessmentPlane) {
                            selectedAssessmentPlane = cfg.defaultPlane
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var assessmentPlanePicker: some View {
        let supported = selectedAssessment.supportedPlanes
        if supported.count > 1 {
            fieldLabel("Plane")
            Picker("Plane", selection: $selectedAssessmentPlane) {
                ForEach(supported) { plane in
                    Text(plane.displayName).tag(plane)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var customOverlayDisclosure: some View {
        VStack(alignment: .leading, spacing: KSpacing.xs) {
            Button {
                withAnimation(.snappy) { showCustomOverlays.toggle() }
            } label: {
                HStack {
                    Image(systemName: "line.diagonal")
                        .foregroundStyle(KColor.accent)
                    Text("Alignment overlays")
                        .font(KFont.callout)
                        .foregroundStyle(KColor.textPrimary)
                    if !customOverlayOptions.isEmpty {
                        KPill(text: "\(customOverlayOptions.count)", tint: KColor.accent, filled: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(KColor.textTertiary)
                        .rotationEffect(.degrees(showCustomOverlays ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if showCustomOverlays {
                ForEach(CustomOverlayOption.allCases) { option in
                    Toggle(isOn: overlayBinding(for: option)) {
                        Text(option.rawValue)
                            .font(KFont.subheadline)
                            .foregroundStyle(KColor.textSecondary)
                    }
                    .tint(KColor.accent)
                }
            }
        }
    }

    private func overlayBinding(for option: CustomOverlayOption) -> Binding<Bool> {
        Binding(
            get: { customOverlayOptions.contains(option) },
            set: { isOn in
                if isOn { customOverlayOptions.insert(option) }
                else { customOverlayOptions.remove(option) }
            }
        )
    }

    // MARK: - Camera tip

    private var cameraTipBanner: some View {
        InfoBanner(icon: "camera.aperture",
                   title: "Camera setup",
                   message: currentCameraSetupTip,
                   tint: KColor.accent)
    }

    // MARK: - Video hero / upload dropzone

    @ViewBuilder
    private var videoHero: some View {
        if let player {
            VStack(spacing: KSpacing.sm) {
                ZStack(alignment: .topLeading) {
                    VideoPlayer(player: player)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: KRadius.md, style: .continuous))
                    if analyzedVideoURL != nil {
                        KPill(text: "Analyzed", tint: KColor.teal, filled: true)
                            .padding(KSpacing.sm)
                    }
                }
                HStack(spacing: KSpacing.sm) {
                    PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                            .font(KFont.callout)
                            .foregroundStyle(KColor.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(KColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
                    }
                    if analyzedVideoURL != nil {
                        Button {
                            showingFullScreenAnalyzedVideo = true
                        } label: {
                            Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(KFont.callout)
                                .foregroundStyle(KColor.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(KColor.surfaceSunken, in: RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                VStack(spacing: KSpacing.sm) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(KColor.accent)
                    Text("Select a video")
                        .font(KFont.headline)
                        .foregroundStyle(KColor.textPrimary)
                    Text("Choose a clip from your library to analyze")
                        .font(KFont.caption)
                        .foregroundStyle(KColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(KColor.surface, in: RoundedRectangle(cornerRadius: KRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KRadius.md, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                        .foregroundStyle(KColor.accent.opacity(0.5))
                )
            }
        }
    }

    @ViewBuilder
    private var loadingVideoSection: some View {
        if isLoadingSelectedVideo {
            HStack(spacing: KSpacing.sm) {
                ProgressView().tint(KColor.accent)
                Text(videoLoadingStatus)
                    .font(KFont.subheadline)
                    .foregroundStyle(KColor.textSecondary)
                Spacer()
            }
            .padding(KSpacing.md)
            .background(KColor.surface, in: RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
        }
    }

    // MARK: - Analyze CTA

    @ViewBuilder
    private var analyzeSection: some View {
        if selectedVideoURL != nil {
            if processor.isProcessing {
                KCard {
                    VStack(spacing: KSpacing.sm) {
                        HStack {
                            Text("Analyzing movement")
                                .font(KFont.callout)
                                .foregroundStyle(KColor.textPrimary)
                            Spacer()
                            Text("\(Int(processor.progress * 100))%")
                                .font(KFont.callout)
                                .foregroundStyle(KColor.accent)
                                .monospacedDigit()
                        }
                        ProgressTrack(value: Double(processor.progress))
                    }
                }
            } else {
                Button {
                    Task { await analyzeVideo() }
                } label: {
                    Label(analyzedVideoURL != nil ? "Re-analyze" : "Analyze form",
                          systemImage: "waveform.path.ecg")
                }
                .buttonStyle(KPrimaryButtonStyle(
                    gradient: LinearGradient(colors: [KColor.success, KColor.teal],
                                             startPoint: .leading, endPoint: .trailing)
                ))
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        if let metrics = assessmentMetrics, analysisCategory == .assessment {
            AssessmentReportCard(metrics: metrics,
                                 trackingRate: analysisSummary?.poseDetectionRate)
        } else if let summary = analysisSummary {
            exerciseResultsCard(summary)
        }
    }

    private func exerciseResultsCard(_ summary: AnalysisSummary) -> some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.md) {
                SectionHeader("Form Analysis", eyebrow: "Results")

                if selectedExerciseType == .shoulderAssessment,
                   let tilt = summary.averageAngles.first(where: { $0.joint == .shoulder }) {
                    let absTilt = abs(tilt.degrees)
                    let elevSide = tilt.degrees >= 0 ? "Left" : "Right"
                    InfoBanner(icon: "figure.stand",
                               title: "Shoulder elevation",
                               message: "\(elevSide) shoulder elevated \(String(format: "%.1f", absTilt))° on average.",
                               tint: KColor.violet)
                } else {
                    HStack(spacing: KSpacing.md) {
                        if let score = summary.finalScore {
                            ScoreRing(value: score, size: 116, lineWidth: 11)
                        }
                        VStack(spacing: KSpacing.sm) {
                            HStack(spacing: KSpacing.sm) {
                                StatTile(icon: "number", value: "\(summary.totalReps)", label: "Reps", tint: KColor.accent)
                                StatTile(icon: "timer", value: String(format: "%.1fs", summary.duration), label: "Duration", tint: KColor.teal)
                            }
                        }
                    }
                }

                if !summary.averageAngles.isEmpty {
                    Eyebrow(text: "Average joint angles")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: KSpacing.xs) {
                            ForEach(summary.averageAngles, id: \.joint) { angle in
                                if !(selectedExerciseType == .shoulderAssessment && angle.joint == .shoulder) {
                                    MetricChip(label: angle.joint.rawValue.capitalized,
                                               value: "\(Int(angle.degrees))°",
                                               tint: KColor.textPrimary)
                                }
                            }
                        }
                    }
                }

                if let avgTempo = averageTempoString(summary.perRepMetrics) {
                    Divider().overlay(KColor.separator)
                    HStack(spacing: KSpacing.xs) {
                        Image(systemName: "metronome")
                            .foregroundStyle(KColor.teal)
                            .imageScale(.small)
                        Text("Average tempo")
                            .font(KFont.caption)
                            .foregroundStyle(KColor.textSecondary)
                        Spacer()
                        Text(avgTempo)
                            .font(KFont.callout)
                            .foregroundStyle(KColor.textPrimary)
                            .monospacedDigit()
                    }
                    Text("Eccentric – pause – concentric – pause (seconds)")
                        .font(.system(size: 11))
                        .foregroundStyle(KColor.textTertiary)
                }

                perRepTable(summary.perRepMetrics)

                CoachingSection(
                    insights: CoachingInsights.exercise(summary: summary, exerciseType: selectedExerciseType),
                    copyHeader: "Kinetriq — \(selectedExercise.displayName) form analysis"
                )

                trackingRow(rate: summary.poseDetectionRate)
            }
        }
    }

    // MARK: - Per-rep breakdown table

    @ViewBuilder
    private func perRepTable(_ reps: [RepMetric]) -> some View {
        if !reps.isEmpty {
            Divider().overlay(KColor.separator)
            Eyebrow(text: "Per-rep breakdown")
            VStack(spacing: 0) {
                HStack {
                    Text("Rep")
                        .frame(width: 44, alignment: .leading)
                    Text("Tempo")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Peak")
                        .frame(width: 56, alignment: .trailing)
                }
                .font(KFont.micro)
                .foregroundStyle(KColor.textTertiary)
                .padding(.vertical, KSpacing.xs)

                ForEach(reps, id: \.repNumber) { rep in
                    HStack {
                        Text("\(rep.repNumber)")
                            .frame(width: 44, alignment: .leading)
                            .foregroundStyle(KColor.textSecondary)
                        Text(rep.tempoString)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(KColor.textPrimary)
                        Text(peakAngleText(rep.peakFlexionAngle))
                            .frame(width: 56, alignment: .trailing)
                            .foregroundStyle(KColor.textPrimary)
                    }
                    .font(KFont.callout)
                    .monospacedDigit()
                    .padding(.vertical, 7)
                    .background(
                        rep.repNumber % 2 == 0
                            ? Color.clear
                            : KColor.surfaceSunken.opacity(0.6)
                    )
                }
            }
        }
    }

    private func peakAngleText(_ angle: Float) -> String {
        guard angle.isFinite, angle < 1000 else { return "—" }
        return "\(Int(angle.rounded()))°"
    }

    /// Average per-rep tempo across the set, formatted "ecc-pause-con-pause".
    private func averageTempoString(_ reps: [RepMetric]) -> String? {
        guard !reps.isEmpty else { return nil }
        let n = Double(reps.count)
        let ecc = reps.reduce(0) { $0 + $1.eccentricDuration } / n
        let pauseB = reps.reduce(0) { $0 + $1.pauseBottomDuration } / n
        let con = reps.reduce(0) { $0 + $1.concentricDuration } / n
        let pauseT = reps.reduce(0) { $0 + $1.pauseTopDuration } / n
        return TempoDurationFormatter.string(
            eccentric: ecc, pauseBottom: pauseB, concentric: con, pauseTop: pauseT
        )
    }

    // MARK: - Tracking quality row

    @ViewBuilder
    private func trackingRow(rate: Float) -> some View {
        let pct = Int((rate * 100).rounded())
        let color: Color = pct >= 70 ? KColor.success : pct >= 40 ? KColor.warning : KColor.danger
        HStack(spacing: KSpacing.xs) {
            Image(systemName: pct >= 70 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(color)
                .imageScale(.small)
            Text("Pose tracked \(pct)% of frames")
                .font(KFont.caption)
                .foregroundStyle(pct >= 70 ? KColor.textSecondary : color)
            if pct < 40 {
                Text("— improve framing or lighting")
                    .font(KFont.caption)
                    .foregroundStyle(KColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Share / export actions

    @ViewBuilder
    private var shareActionsSection: some View {
        if analysisSummary != nil || assessmentMetrics != nil {
            VStack(spacing: KSpacing.sm) {
                Button {
                    Task { await shareSummaryImage() }
                } label: {
                    Label("Share summary image", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(KSecondaryButtonStyle(tint: KColor.accent))

                if analyzedVideoURL != nil {
                    Button {
                        exportOverlayStyle = analyzedOverlayMode ?? overlayMode
                        exportCropReels = false
                        showingExportOptions = true
                    } label: {
                        Label("Export analyzed video", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(KSecondaryButtonStyle(tint: KColor.amber))
                }
            }
        }
    }

    // MARK: - Content export preset sheet

    private var exportOptionsSheet: some View {
        NavigationStack {
            ZStack {
                KScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: KSpacing.lg) {
                        if analysisCategory == .exercise {
                            KCard {
                                VStack(alignment: .leading, spacing: KSpacing.sm) {
                                    Eyebrow(text: "Overlay style")
                                    Picker("Overlay style", selection: $exportOverlayStyle) {
                                        ForEach(OverlayMode.allCases, id: \.self) { mode in
                                            Text(mode == .simple ? "Simple (clean)" : "Full HUD (detailed)")
                                                .tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    Text(exportOverlayStyle == .simple
                                         ? "Skeleton and alignment lines only — a clean look for sharing."
                                         : "Adds rep counter, score, and per-rep tempo history.")
                                        .font(KFont.caption)
                                        .foregroundStyle(KColor.textSecondary)
                                    if let analyzed = analyzedOverlayMode, exportOverlayStyle != analyzed {
                                        Label("The clip will be re-rendered with this overlay style.",
                                              systemImage: "wand.and.stars")
                                            .font(KFont.caption)
                                            .foregroundStyle(KColor.accent)
                                    }
                                }
                            }
                        }

                        KCard {
                            VStack(alignment: .leading, spacing: KSpacing.sm) {
                                Toggle(isOn: $exportCropReels) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Crop to 9:16")
                                            .font(KFont.callout)
                                            .foregroundStyle(KColor.textPrimary)
                                        Text("Vertical format for Reels, TikTok, and Stories.")
                                            .font(KFont.caption)
                                            .foregroundStyle(KColor.textSecondary)
                                    }
                                }
                                .tint(KColor.accent)
                            }
                        }

                        Button {
                            Task { await prepareAndShareExport() }
                        } label: {
                            if isPreparingExport {
                                HStack(spacing: KSpacing.xs) {
                                    ProgressView().tint(.white)
                                    Text(processor.isProcessing
                                         ? "Rendering \(Int(processor.progress * 100))%"
                                         : "Preparing…")
                                }
                            } else {
                                Label("Prepare & share", systemImage: "square.and.arrow.up")
                            }
                        }
                        .buttonStyle(KPrimaryButtonStyle())
                        .disabled(isPreparingExport)
                    }
                    .padding(.horizontal, KSpacing.screenH)
                    .padding(.vertical, KSpacing.lg)
                }
            }
            .navigationTitle("Export options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingExportOptions = false }
                        .disabled(isPreparingExport)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Live camera hero

    private var liveCameraHero: some View {
        VStack(spacing: KSpacing.md) {
            VStack(spacing: KSpacing.sm) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Live form coaching")
                    .font(KFont.title2)
                    .foregroundStyle(.white)
                Text("Real-time skeleton overlay, reps, and tempo as you move.")
                    .font(KFont.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, KSpacing.xl)
            .background(KColor.tealGradient, in: RoundedRectangle(cornerRadius: KRadius.lg, style: .continuous))
            .shadow(color: KColor.teal.opacity(0.3), radius: 20, x: 0, y: 12)

            NavigationLink {
                LiveAnalysisView()
            } label: {
                Label("Start live analysis", systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(KPrimaryButtonStyle(
                gradient: LinearGradient(colors: [KColor.teal, Color(hex: 0x16A4D8)],
                                         startPoint: .leading, endPoint: .trailing)
            ))
        }
    }

    // MARK: - Actions

    private func loadVideo(from item: PhotosPickerItem?) async {
        await MainActor.run {
            isLoadingSelectedVideo = true
            videoLoadingStatus = "Accessing video from Photos..."
            // Clear previous selection/results so state reflects current loading operation.
            selectedVideoURL = nil
            analyzedVideoURL = nil
            analyzedOverlayMode = nil
            analysisSummary = nil
            assessmentMetrics = nil
            player = nil
        }

        guard let item else {
            await MainActor.run { isLoadingSelectedVideo = false }
            return
        }

        defer {
            Task { @MainActor in
                isLoadingSelectedVideo = false
            }
        }

        do {
            let url = try await loadVideoURL(from: item) { status in
                videoLoadingStatus = status
            }
            await MainActor.run {
                selectedVideoURL = url
                analyzedVideoURL = nil
                analysisSummary = nil
                assessmentMetrics = nil
                player = AVPlayer(url: url)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load video: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func analyzeVideo() async {
        guard let inputURL = selectedVideoURL else { return }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("analyzed_\(UUID().uuidString).mp4")

        let analyzer: FrameAnalyzerProtocol
        let assessmentAnalyzerRef: AssessmentAnalyzer?

        if analysisCategory == .assessment {
            let aa = selectedAssessment.makeAnalyzer(side: selectedSide, plane: selectedAssessmentPlane)
            analyzer = aa
            assessmentAnalyzerRef = aa
        } else {
            analyzer = selectedExercise.makeAnalyzer(side: selectedSide)
            assessmentAnalyzerRef = nil
        }

        do {
            let summary = try await processor.process(
                inputURL: inputURL,
                outputURL: outputURL,
                analyzer: analyzer,
                overlayMode: analysisCategory == .exercise ? overlayMode : .simple,
                customOverlayOptions: analysisCategory == .exercise ? customOverlayOptions : []
            )

            let outputAsset = AVURLAsset(url: outputURL)
            let outputDuration = CMTimeGetSeconds(outputAsset.duration)
            logger.info("Output video duration: \(outputDuration)s at \(outputURL.lastPathComponent)")

            let metrics = assessmentAnalyzerRef?.currentMetrics()

            await MainActor.run {
                analysisSummary = summary
                assessmentMetrics = metrics
                analyzedVideoURL = outputURL
                analyzedOverlayMode = analysisCategory == .exercise ? overlayMode : .simple
                player = AVPlayer(url: outputURL)
            }
        } catch {
            let ns = error as NSError
            AnalysisLog.ui.error(
                "analyzeVideo failed domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public) \(error.localizedDescription, privacy: .public)"
            )
            await MainActor.run {
                errorMessage = "Analysis failed: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    // MARK: - Share summary image

    @MainActor
    private func shareSummaryImage() async {
        guard let model = makeShareCardModel() else { return }
        guard let url = SummaryImageRenderer.renderPNG(model) else {
            errorMessage = "Could not create the summary image."
            showingError = true
            return
        }
        sharePayload = SharePayload(items: [url])
    }

    private func makeShareCardModel() -> SummaryShareCardModel? {
        let date = Date().formatted(date: .abbreviated, time: .omitted)

        if analysisCategory == .assessment, let metrics = assessmentMetrics {
            var stats: [SummaryShareCardModel.Stat] = []
            if let left = metrics.leftROM, let right = metrics.rightROM {
                stats.append(.init(label: "Left ROM", value: "\(Int(left))°"))
                stats.append(.init(label: "Right ROM", value: "\(Int(right))°"))
                if let asymm = metrics.asymmetryDeg {
                    stats.append(.init(label: "Asymmetry", value: "\(Int(asymm))°"))
                }
            } else {
                stats = metrics.subGrades.prefix(3).map {
                    .init(label: $0.label, value: $0.grade.rawValue)
                }
            }
            let insights = CoachingInsights
                .assessment(metrics: metrics, trackingRate: analysisSummary?.poseDetectionRate)
                .map(\.text)
            return SummaryShareCardModel(
                categoryLabel: "Assessment",
                title: selectedAssessmentType.rawValue,
                headline: .grade(metrics.grade),
                stats: stats,
                insights: insights,
                dateText: date
            )
        }

        guard let summary = analysisSummary else { return nil }
        let headline: SummaryShareCardModel.Headline = summary.finalScore
            .map { .score($0) } ?? .reps(summary.totalReps)
        var stats: [SummaryShareCardModel.Stat] = [
            .init(label: "Reps", value: "\(summary.totalReps)"),
            .init(label: "Duration", value: String(format: "%.0fs", summary.duration))
        ]
        if let avgTempo = averageTempoString(summary.perRepMetrics) {
            stats.append(.init(label: "Avg tempo", value: avgTempo))
        } else {
            stats.append(.init(label: "Tracking", value: "\(Int((summary.poseDetectionRate * 100).rounded()))%"))
        }
        let insights = CoachingInsights
            .exercise(summary: summary, exerciseType: selectedExerciseType)
            .map(\.text)
        return SummaryShareCardModel(
            categoryLabel: "Form Analysis",
            title: selectedExercise.displayName,
            headline: headline,
            stats: stats,
            insights: insights,
            dateText: date
        )
    }

    // MARK: - Content export preset

    private func prepareAndShareExport() async {
        guard let analyzedURL = analyzedVideoURL else { return }
        await MainActor.run { isPreparingExport = true }
        defer { Task { @MainActor in isPreparingExport = false } }

        do {
            var workingURL = analyzedURL

            // Re-render the overlay if the chosen style differs from the analyzed clip.
            if analysisCategory == .exercise,
               let analyzedMode = analyzedOverlayMode,
               exportOverlayStyle != analyzedMode,
               let inputURL = selectedVideoURL {
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("export_\(UUID().uuidString).mp4")
                let analyzer = selectedExercise.makeAnalyzer(side: selectedSide)
                _ = try await processor.process(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    analyzer: analyzer,
                    overlayMode: exportOverlayStyle,
                    customOverlayOptions: customOverlayOptions
                )
                workingURL = outputURL
            }

            if exportCropReels {
                workingURL = try await VideoExportService.cropToReels(sourceURL: workingURL)
            }

            await MainActor.run {
                showingExportOptions = false
                sharePayload = SharePayload(items: [workingURL])
            }
        } catch {
            await MainActor.run {
                showingExportOptions = false
                errorMessage = "Export failed: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

/// Identifiable wrapper so a single `.sheet(item:)` can present any share content.
struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - Coaching insights section (shared by exercise + assessment cards)

struct CoachingSection: View {
    let insights: [CoachingInsight]
    let copyHeader: String
    @State private var copied = false

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: KSpacing.sm) {
                Divider().overlay(KColor.separator)
                HStack {
                    Eyebrow(text: "Coaching")
                    Spacer()
                    Button {
                        UIPasteboard.general.string = CoachingInsights.clipboardText(insights, header: copyHeader)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(KFont.caption)
                            .foregroundStyle(copied ? KColor.success : KColor.accent)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(insights) { insight in
                    HStack(alignment: .top, spacing: KSpacing.xs) {
                        Image(systemName: insight.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(tint(insight.tone))
                            .frame(width: 18)
                            .padding(.top, 1)
                        Text(insight.text)
                            .font(KFont.caption)
                            .foregroundStyle(KColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func tint(_ tone: InsightTone) -> Color {
        switch tone {
        case .positive: return KColor.success
        case .caution: return KColor.warning
        case .info: return KColor.accent
        }
    }
}

// MARK: - Assessment report card (clinical, scannable)

private struct AssessmentReportCard: View {
    let metrics: AssessmentMetrics
    let trackingRate: Float?

    var body: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.md) {
                HStack(alignment: .center, spacing: KSpacing.md) {
                    GradeBadge(grade: metrics.grade, size: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: "Assessment report")
                        Text(overallLabel)
                            .font(KFont.title2)
                            .foregroundStyle(KColor.textPrimary)
                        Text(verdict)
                            .font(KFont.caption)
                            .foregroundStyle(KColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                if !metrics.subGrades.isEmpty {
                    Divider().overlay(KColor.separator)
                    Eyebrow(text: "Breakdown")
                    ForEach(metrics.subGrades, id: \.label) { sub in
                        HStack {
                            Image(systemName: sub.grade <= .B ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(KColor.grade(sub.grade))
                                .imageScale(.small)
                            Text(sub.label)
                                .font(KFont.subheadline)
                                .foregroundStyle(KColor.textPrimary)
                            Spacer()
                            KPill(text: sub.grade.rawValue, tint: KColor.grade(sub.grade), filled: true)
                        }
                    }
                }

                if let left = metrics.leftROM, let right = metrics.rightROM {
                    Divider().overlay(KColor.separator)
                    Eyebrow(text: "Range of motion")
                    romComparison(left: left, right: right)
                    if metrics.asymmetryFlag, let asymm = metrics.asymmetryDeg {
                        InfoBanner(icon: "arrow.left.arrow.right",
                                   title: "Asymmetry detected",
                                   message: "\(Int(asymm))° difference between sides — worth a closer look.",
                                   tint: KColor.warning)
                    }
                }

                if !metrics.details.isEmpty {
                    Divider().overlay(KColor.separator)
                    Eyebrow(text: "Recommendations")
                    ForEach(metrics.details, id: \.self) { detail in
                        HStack(alignment: .top, spacing: KSpacing.xs) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(KColor.accent)
                                .padding(.top, 1)
                            Text(detail)
                                .font(KFont.caption)
                                .foregroundStyle(KColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                CoachingSection(
                    insights: CoachingInsights.assessment(metrics: metrics, trackingRate: trackingRate),
                    copyHeader: "Kinetriq — assessment report"
                )

                if let rate = trackingRate {
                    Divider().overlay(KColor.separator)
                    trackingRow(rate: rate)
                }

                Text("For general fitness and educational purposes only — not medical advice. Consult a qualified professional for diagnosis or treatment.")
                    .font(.system(size: 11))
                    .foregroundStyle(KColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var overallLabel: String {
        switch metrics.grade {
        case .A: return "Excellent"
        case .B: return "Good"
        case .C: return "Fair"
        case .D: return "Limited"
        case .F: return "Needs work"
        }
    }

    private var verdict: String {
        metrics.grade <= .B ? "Movement meets quality standards." : "Mobility or control limitations present."
    }

    private func romComparison(left: Float, right: Float) -> some View {
        let maxV = Double(max(left, right, 1))
        return VStack(spacing: KSpacing.xs) {
            romRow(label: "Left", value: left, fraction: Double(left) / maxV, tint: KColor.accent)
            romRow(label: "Right", value: right, fraction: Double(right) / maxV, tint: KColor.teal)
        }
    }

    private func romRow(label: String, value: Float, fraction: Double, tint: Color) -> some View {
        HStack(spacing: KSpacing.sm) {
            Text(label)
                .font(KFont.caption)
                .foregroundStyle(KColor.textSecondary)
                .frame(width: 42, alignment: .leading)
            ProgressTrack(value: fraction, tint: tint)
            Text("\(Int(value))°")
                .font(KFont.callout)
                .foregroundStyle(KColor.textPrimary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func trackingRow(rate: Float) -> some View {
        let pct = Int((rate * 100).rounded())
        let color: Color = pct >= 70 ? KColor.success : pct >= 40 ? KColor.warning : KColor.danger
        HStack(spacing: KSpacing.xs) {
            Image(systemName: pct >= 70 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(color)
                .imageScale(.small)
            Text("Pose tracked \(pct)% of frames")
                .font(KFont.caption)
                .foregroundStyle(pct >= 70 ? KColor.textSecondary : color)
            Spacer(minLength: 0)
        }
    }
}

/// UIKit share sheet wrapper for exporting the analyzed video.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct FullScreenVideoPlayer: View {
    @Environment(\.dismiss) private var dismiss

    private let player: AVPlayer

    init(url: URL) {
        self.player = AVPlayer(url: url)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onAppear { player.play() }
                .onDisappear { player.pause() }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white, .black.opacity(0.65))
                    .padding()
            }
            .accessibilityLabel("Close full screen video")
        }
    }
}
