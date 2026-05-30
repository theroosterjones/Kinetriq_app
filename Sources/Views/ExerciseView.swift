import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: "com.kevinjones.Kinetriq", category: "ExerciseView")

/// Transferable wrapper so PhotosPicker can hand us a video file URL.
///
/// Multiple FileRepresentations (importing only) are required because Photos may
/// export videos under different UTTypes depending on format and iOS version.
/// Using only .movie causes TransferableSupportError 0 for HEVC and some .mp4
/// recordings. Each representation copies the file to a temp URL so it stays
/// valid after the picker closes. NOTE: exporting closures are intentionally
/// omitted — PhotosPicker only uses the importing pathway.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        // shouldAllowAccessingOriginalFile: true — bypass Photos transcoding and
        // return the raw file directly. This avoids TransferableSupportError 0
        // for formats (ProRes, Cinematic, screen recordings, etc.) that don't
        // neatly map to any single declared UTType.
        FileRepresentation(contentType: .audiovisualContent,
                           shouldAllowAccessingOriginalFile: true,
                           importing: { try Self(url: copyToTemp($0.file)) })
        FileRepresentation(contentType: .movie,
                           shouldAllowAccessingOriginalFile: true,
                           importing: { try Self(url: copyToTemp($0.file)) })
        FileRepresentation(contentType: .quickTimeMovie,
                           shouldAllowAccessingOriginalFile: true,
                           importing: { try Self(url: copyToTemp($0.file)) })
        FileRepresentation(contentType: .mpeg4Movie,
                           shouldAllowAccessingOriginalFile: true,
                           importing: { try Self(url: copyToTemp($0.file)) })
    }
}

private func copyToTemp(_ file: URL) throws -> URL {
    let ext = file.pathExtension.isEmpty ? "mov" : file.pathExtension
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(ext)
    try FileManager.default.copyItem(at: file, to: dest)
    return dest
}

private enum AnalysisMode: String, CaseIterable {
    case savedVideo  = "Saved Video"
    case liveCamera  = "Live Camera"
}

struct ExerciseView: View {
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
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var analyzedVideoURL: URL?
    @State private var analysisSummary: AnalysisSummary?
    @State private var assessmentMetrics: AssessmentMetrics?
    @State private var player: AVPlayer?
    @State private var isLoadingSelectedVideo = false

    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingShareSheet = false

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
            ScrollView {
                VStack(spacing: 20) {
                    modePicker

                    if analysisMode == .savedVideo {
                        categoryPicker
                        exerciseOrAssessmentPicker
                        if analysisCategory == .assessment {
                            assessmentPlanePicker
                        }
                        cameraSetupTipCard
                        sidePicker
                        if analysisCategory == .exercise {
                            overlayModePicker
                        }
                        videoPickerButton
                        loadingVideoSection
                        videoPreview
                        analyzeSection
                        resultsSection
                        exportSection
                    } else {
                        liveCameraButton
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Workout")
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = analyzedVideoURL {
                    ShareSheet(items: [url])
                }
            }
            .onChange(of: selectedVideoItem) { _, newItem in
                Task { await loadVideo(from: newItem) }
            }
        }
    }

    // MARK: - Subviews

    private var modePicker: some View {
        Picker("Mode", selection: $analysisMode) {
            ForEach(AnalysisMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $analysisCategory) {
            ForEach(AnalysisCategory.allCases, id: \.self) { cat in
                Text(cat.rawValue).tag(cat)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var liveCameraButton: some View {
        NavigationLink(destination: LiveAnalysisView()) {
            Label("Start Live Analysis", systemImage: "camera.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.indigo)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var exerciseOrAssessmentPicker: some View {
        if analysisCategory == .exercise {
            Picker("Exercise", selection: $selectedExerciseType) {
                ForEach(ExerciseType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal)
        } else {
            Picker("Assessment", selection: $selectedAssessmentType) {
                ForEach(AssessmentType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal)
            .onChange(of: selectedAssessmentType) { _, newType in
                // When the assessment changes, snap the plane back to that
                // assessment's default rather than carrying over the previous
                // selection (which may not be supported).
                if let cfg = AssessmentConfig.all.first(where: { $0.type == newType }) {
                    if !cfg.supportedPlanes.contains(selectedAssessmentPlane) {
                        selectedAssessmentPlane = cfg.defaultPlane
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var assessmentPlanePicker: some View {
        let supported = selectedAssessment.supportedPlanes
        if supported.count > 1 {
            Picker("Plane", selection: $selectedAssessmentPlane) {
                ForEach(supported) { plane in
                    Text(plane.displayName).tag(plane)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var cameraSetupTipCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "camera.aperture")
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 4) {
                Text("Camera setup tip")
                    .font(.subheadline.weight(.semibold))
                Text(currentCameraSetupTip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var sidePicker: some View {
        if currentRequiresSideSelection {
            Picker("Side", selection: $selectedSide) {
                Text("Left").tag(BodySide.left)
                Text("Right").tag(BodySide.right)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }
    }

    private var overlayModePicker: some View {
        Picker("Overlay", selection: $overlayMode) {
            ForEach(OverlayMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var videoPickerButton: some View {
        PhotosPicker(
            selection: $selectedVideoItem,
            matching: .videos
        ) {
            Label("Select Video", systemImage: "video.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var loadingVideoSection: some View {
        if isLoadingSelectedVideo {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading video...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var videoPreview: some View {
        if let player {
            VideoPlayer(player: player)
                .frame(height: 300)
                .cornerRadius(12)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var analyzeSection: some View {
        if selectedVideoURL != nil {
            Button {
                Task { await analyzeVideo() }
            } label: {
                analyzeButtonLabel
            }
            .disabled(processor.isProcessing)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var analyzeButtonLabel: some View {
        if processor.isProcessing {
            VStack(spacing: 8) {
                ProgressView(value: processor.progress)
                Text("Analyzing... \(Int(processor.progress * 100))%")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.3))
            .cornerRadius(12)
        } else {
            Label(analyzedVideoURL != nil ? "Re-Analyze" : "Analyze Form",
                  systemImage: "figure.run")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if let metrics = assessmentMetrics, analysisCategory == .assessment {
            assessmentResultsCard(metrics)
        } else if let summary = analysisSummary {
            exerciseResultsCard(summary)
        }
    }

    private func exerciseResultsCard(_ summary: AnalysisSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results")
                .font(.headline)

            if selectedExerciseType == .shoulderAssessment {
                if let tilt = summary.averageAngles.first(where: { $0.joint == .shoulder }) {
                    let absTilt = abs(tilt.degrees)
                    let elevSide = tilt.degrees >= 0 ? "Left" : "Right"
                    Text("\(elevSide) shoulder elevated  \(String(format: "%.1f", absTilt))° avg")
                }
            } else {
                Text("Reps: \(summary.totalReps)")
            }

            if let score = summary.finalScore {
                Text("Score: \(score)/100")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(score >= 80 ? .green : score >= 60 ? .yellow : .red)
            }

            Text("Duration: \(String(format: "%.1f", summary.duration))s")

            trackingRateRow(rate: summary.poseDetectionRate)

            ForEach(summary.averageAngles, id: \.joint) { angle in
                if selectedExerciseType == .shoulderAssessment, angle.joint == .shoulder {
                } else {
                    Text("Avg \(angle.joint.rawValue): \(Int(angle.degrees))\u{00B0}")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func assessmentResultsCard(_ metrics: AssessmentMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Assessment Results")
                    .font(.headline)
                Spacer()
                Text(metrics.grade.rawValue)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(gradeColor(metrics.grade))
            }

            if let rate = analysisSummary?.poseDetectionRate {
                trackingRateRow(rate: rate)
            }

            ForEach(metrics.subGrades, id: \.label) { sub in
                HStack {
                    Text(sub.label)
                        .font(.subheadline)
                    Spacer()
                    Text(sub.grade.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(gradeColor(sub.grade))
                }
            }

            if let left = metrics.leftROM, let right = metrics.rightROM {
                HStack {
                    Text("Left: \(Int(left))°")
                    Spacer()
                    Text("Right: \(Int(right))°")
                }
                .font(.subheadline)
            }

            if metrics.asymmetryFlag, let asymm = metrics.asymmetryDeg {
                Text("Asymmetry: \(Int(asymm))° difference")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(metrics.details, id: \.self) { detail in
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    /// Colour-coded tracking quality row. Shows % of frames where MediaPipe detected a person.
    /// Red < 40%, yellow 40–69%, green ≥ 70%. Helps diagnose missing overlays without Console.
    @ViewBuilder
    private func trackingRateRow(rate: Float) -> some View {
        let pct = Int((rate * 100).rounded())
        let color: Color = pct >= 70 ? .green : pct >= 40 ? .yellow : .red
        HStack(spacing: 4) {
            Image(systemName: pct >= 70 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(color)
                .imageScale(.small)
            Text("Pose tracked: \(pct)% of frames")
                .font(.caption)
                .foregroundStyle(pct >= 70 ? .secondary : color)
            if pct < 40 {
                Text("— improve framing or lighting")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func gradeColor(_ grade: LetterGrade) -> Color {
        switch grade {
        case .A: return .green
        case .B: return Color(red: 0.6, green: 1.0, blue: 0.2)
        case .C: return .yellow
        case .D: return .orange
        case .F: return .red
        }
    }

    @ViewBuilder
    private var exportSection: some View {
        if analyzedVideoURL != nil {
            Button {
                showingShareSheet = true
            } label: {
                Label("Export Analyzed Video", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    private func loadVideo(from item: PhotosPickerItem?) async {
        await MainActor.run {
            isLoadingSelectedVideo = true
            // Clear previous selection/results so state reflects current loading operation.
            selectedVideoURL = nil
            analyzedVideoURL = nil
            analysisSummary = nil
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
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                await MainActor.run {
                    errorMessage = "Could not load video from Photos."
                    showingError = true
                }
                return
            }
            await MainActor.run {
                selectedVideoURL = movie.url
                analyzedVideoURL = nil
                analysisSummary = nil
                player = AVPlayer(url: movie.url)
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
                overlayMode: analysisCategory == .exercise ? overlayMode : .simple
            )

            let outputAsset = AVURLAsset(url: outputURL)
            let outputDuration = CMTimeGetSeconds(outputAsset.duration)
            logger.info("Output video duration: \(outputDuration)s at \(outputURL.lastPathComponent)")

            let metrics = assessmentAnalyzerRef?.currentMetrics()

            await MainActor.run {
                analysisSummary = summary
                assessmentMetrics = metrics
                analyzedVideoURL = outputURL
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
}

/// UIKit share sheet wrapper for exporting the analyzed video.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
