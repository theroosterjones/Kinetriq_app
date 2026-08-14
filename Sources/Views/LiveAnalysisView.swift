import SwiftUI
import MetalKit
import AVKit
import UIKit
import os.log

private let logger = Logger(subsystem: "com.kevinjones.Kinetriq", category: "LiveAnalysisView")

// MARK: - Live Frame State

/// High-frequency per-frame state (updates ~30–60×/second) kept on a *separate*
/// observable object so that only the small overlay/HUD leaf views re-render each
/// frame. If these lived on `LiveAnalysisViewModel`, the whole `LiveAnalysisView`
/// body — including the exercise `Menu` — would be invalidated every frame, which
/// makes menus and buttons unresponsive because the press gesture is cancelled by
/// the constant view rebuilds.
final class LiveFrameState: ObservableObject {
    @Published var currentInstructions: [OverlayInstruction] = []
    @Published var repCount: Int = 0
    @Published var currentPhase: TempoPhase?
    @Published var trackingWarningVisible = false
    @Published var currentScore: Int?
}

// MARK: - Live Analysis ViewModel

/// Owns the camera service, pose landmarker, and analyzer for the live pipeline.
/// Heavy processing runs on the camera's serial capture queue; UI state is dispatched to main.
///
/// Only *low-frequency* control state lives here as `@Published`. Per-frame data
/// lives on `frameState` (a plain `let`, not `@Published`) so updating it does not
/// invalidate views that observe the view model.
final class LiveAnalysisViewModel: ObservableObject {

    let frameState = LiveFrameState()

    @Published private(set) var isRecording = false
    @Published private(set) var isAuthorized = false
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back
    @Published var overlayMode: OverlayMode = .simple
    @Published var customOverlayOptions: Set<CustomOverlayOption> = []

    let metalRenderer = MetalCameraRenderer()

    private let cameraService = CameraService()
    private let poseLandmarker = PoseLandmarkerService()
    private let overlayRenderer = OverlayRenderer()
    private let metricsCollector = RepMetricsCollector()
    private let customOverlayState = CustomOverlayState()

    private var _analyzer: FrameAnalyzerProtocol?
    private var _recorder: LiveVideoRecorder?
    private let recorderLock = NSLock()
    private var lowTrackingStreak = 0

    init() {
        cameraService.onFrame = { [weak self] pixelBuffer, time in
            self?.processFrame(pixelBuffer: pixelBuffer, time: time)
        }
    }

    // MARK: - Public Interface (called from main thread)

    func setAnalyzer(_ analyzer: FrameAnalyzerProtocol) {
        _analyzer?.reset()
        _analyzer = analyzer
        metricsCollector.reset()
        customOverlayState.reset()
        lowTrackingStreak = 0
        DispatchQueue.main.async {
            self.frameState.trackingWarningVisible = false
            self.frameState.currentScore = nil
        }
    }

    func checkAuthorization() async {
        await cameraService.checkAndRequestAuthorization()
        await MainActor.run { isAuthorized = cameraService.isAuthorized }
    }

    func start(position: AVCaptureDevice.Position = .back) {
        cameraService.configure(position: position)
        cameraService.start()
    }

    func stop() {
        cameraService.stop()
    }

    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = (cameraPosition == .back) ? .front : .back
        cameraPosition = newPosition
        cameraService.configure(position: newPosition)
    }

    func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("live_\(UUID().uuidString).mp4")
        do {
            let rec = try LiveVideoRecorder(
                outputURL: url,
                width: cameraService.captureWidth,
                height: cameraService.captureHeight
            )
            recorderLock.withLock { _recorder = rec }
            DispatchQueue.main.async { self.isRecording = true }
        } catch {
            logger.error("Failed to start recorder: \(error.localizedDescription)")
        }
    }

    func stopRecording() async -> URL? {
        let rec: LiveVideoRecorder? = recorderLock.withLock {
            let r = _recorder
            _recorder = nil
            return r
        }
        DispatchQueue.main.async { self.isRecording = false }
        guard let rec else { return nil }
        return try? await rec.finalize()
    }

    // MARK: - Frame Processing (runs on camera capture queue)

    private func processFrame(pixelBuffer: CVPixelBuffer, time: CMTime) {
        let timestampMs = Int(CMTimeGetSeconds(time) * 1000)
        let timeSec = CMTimeGetSeconds(time)

        let poseResult = poseLandmarker.detect(pixelBuffer: pixelBuffer, timestampMs: timestampMs)

        let frameAnalysis: FrameAnalysis
        if let poseResult, let analyzer = _analyzer {
            frameAnalysis = analyzer.analyze(landmarks: poseResult)
        } else {
            frameAnalysis = .empty
        }

        // Feed rep metrics collector
        let primaryAngle = frameAnalysis.angles.first?.degrees ?? 0
        metricsCollector.update(
            phase: frameAnalysis.tempoPhase,
            angle: primaryAngle,
            repCount: frameAnalysis.repCount,
            timestamp: timeSec
        )

        // Build final instructions: base overlay + user-selected alignment lines + optional HUD
        var finalInstructions = frameAnalysis.overlayInstructions
        if let poseResult, let exerciseAnalyzer = _analyzer as? ExerciseAnalyzer {
            finalInstructions.append(contentsOf: CustomOverlayBuilder.instructions(
                options: customOverlayOptions,
                landmarks: poseResult,
                side: exerciseAnalyzer.side,
                exerciseType: exerciseAnalyzer.exerciseType,
                state: customOverlayState
            ))
        }
        let mode = overlayMode
        if mode == .fullHUD {
            finalInstructions.append(contentsOf:
                HUDOverlayBuilder.instructions(
                    repCount: frameAnalysis.repCount,
                    collector: metricsCollector))
        }

        // Recording path: apply overlay to a copy, write to file
        let rec: LiveVideoRecorder? = recorderLock.withLock { _recorder }
        if let rec, let copy = clonePixelBuffer(pixelBuffer) {
            overlayRenderer.render(instructions: finalInstructions, onto: copy)
            rec.append(pixelBuffer: copy, at: time)
        }

        // Display path: push raw frame to Metal; SwiftUI Canvas draws overlay
        metalRenderer.update(pixelBuffer: pixelBuffer)

        let reps         = frameAnalysis.repCount
        let phase        = frameAnalysis.tempoPhase
        let hasTracking = poseResult != nil && !finalInstructions.isEmpty
        let score = metricsCollector.computeScore()

        if hasTracking {
            lowTrackingStreak = 0
        } else {
            lowTrackingStreak += 1
        }
        let shouldShowTrackingWarning = lowTrackingStreak >= 20

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameState.currentInstructions = finalInstructions
            self.frameState.repCount = reps
            self.frameState.currentPhase = phase
            self.frameState.trackingWarningVisible = shouldShowTrackingWarning
            self.frameState.currentScore = score
        }
    }

    // MARK: - Pixel Buffer Clone

    private func clonePixelBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(src)
        let h = CVPixelBufferGetHeight(src)
        let fmt = CVPixelBufferGetPixelFormatType(src)
        var dst: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, w, h, fmt, nil, &dst) == kCVReturnSuccess,
              let dst else { return nil }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
            CVPixelBufferUnlockBaseAddress(dst, [])
        }
        if let s = CVPixelBufferGetBaseAddress(src),
           let d = CVPixelBufferGetBaseAddress(dst) {
            memcpy(d, s, CVPixelBufferGetDataSize(src))
        }
        return dst
    }
}

// MARK: - Metal Camera View (UIViewRepresentable)

struct MetalCameraView: UIViewRepresentable {
    let renderer: MetalCameraRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.backgroundColor = .black
        renderer.setup(view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

// MARK: - Overlay Canvas (SwiftUI Canvas drawing OverlayInstructions)

extension OverlayColor {
    var swiftUIColor: Color {
        let (r, g, b, a) = rgba
        return Color(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }
}

struct OverlayCanvas: View {
    let instructions: [OverlayInstruction]

    var body: some View {
        Canvas { context, size in
            for instruction in instructions {
                draw(instruction, in: context, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ instruction: OverlayInstruction,
                      in context: GraphicsContext,
                      size: CGSize) {
        switch instruction {

        case let .line(from, to, color, width):
            var path = Path()
            path.move(to: point(from, size))
            path.addLine(to: point(to, size))
            context.stroke(path, with: .color(color.swiftUIColor), lineWidth: CGFloat(width))

        case let .extendedLine(from, through, color, width):
            let fromPx = SIMD2<Float>(Float(from.x * Float(size.width)), Float(from.y * Float(size.height)))
            let throughPx = SIMD2<Float>(Float(through.x * Float(size.width)), Float(through.y * Float(size.height)))
            let (start, end) = AngleCalculator.extendLineToFrame(
                p1: fromPx,
                p2: throughPx,
                width: Float(size.width),
                height: Float(size.height)
            )
            var path = Path()
            path.move(to: CGPoint(x: CGFloat(start.x), y: CGFloat(start.y)))
            path.addLine(to: CGPoint(x: CGFloat(end.x), y: CGFloat(end.y)))
            context.stroke(path, with: .color(color.swiftUIColor), lineWidth: CGFloat(width))

        case let .circle(at, radius, color, filled):
            let center = point(at, size)
            let r = CGFloat(radius)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            if filled {
                context.fill(Path(ellipseIn: rect), with: .color(color.swiftUIColor))
            } else {
                context.stroke(Path(ellipseIn: rect), with: .color(color.swiftUIColor),
                               lineWidth: 2)
            }

        case let .text(str, at, color, fontSize):
            let pos = point(at, size)
            context.draw(
                Text(str)
                    .font(.system(size: CGFloat(fontSize), weight: .bold, design: .monospaced))
                    .foregroundStyle(color.swiftUIColor),
                at: pos,
                anchor: .topLeading
            )
        }
    }

    private func point(_ normalized: SIMD2<Float>, _ size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(normalized.x) * size.width,
                y: CGFloat(normalized.y) * size.height)
    }
}

// MARK: - Per-frame leaf views
//
// These observe `LiveFrameState` (the high-frequency object) so only they redraw
// each frame. Keeping them separate from `LiveAnalysisView` is what allows the
// exercise dropdown, segmented pickers, and record button to stay responsive.

private struct LiveOverlayCanvas: View {
    @ObservedObject var frameState: LiveFrameState

    var body: some View {
        OverlayCanvas(instructions: frameState.currentInstructions)
            .ignoresSafeArea()
    }
}

private struct LiveRepCountLabel: View {
    @ObservedObject var frameState: LiveFrameState

    var body: some View {
        Text("\(frameState.repCount)")
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}

private struct LivePhaseLabel: View {
    @ObservedObject var frameState: LiveFrameState

    var body: some View {
        Text(frameState.currentPhase?.rawValue.capitalized ?? "—")
            .font(.caption.weight(.medium))
            .foregroundStyle(.cyan)
            .multilineTextAlignment(.trailing)
    }
}

private struct LiveTrackingWarning: View {
    @ObservedObject var frameState: LiveFrameState
    let text: String

    var body: some View {
        if frameState.trackingWarningVisible {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.yellow.opacity(0.9))
                .clipShape(Capsule())
                .padding(.bottom, 8)
        }
    }
}

// MARK: - Live Analysis View

struct LiveAnalysisView: View {

    @StateObject private var viewModel = LiveAnalysisViewModel()

    @State private var analysisCategory: AnalysisCategory = .exercise
    @State private var selectedExerciseType: ExerciseType = .squat
    @State private var selectedAssessmentType: AssessmentType = .shoulderFlexion
    @State private var selectedAssessmentPlane: ViewPlane = AssessmentConfig.all.first(
        where: { $0.type == .shoulderFlexion }
    )?.defaultPlane ?? .frontal
    @State private var selectedSide: BodySide = .left
    @State private var showPermissionAlert = false
    @State private var savedVideoURL: URL?
    @State private var showShareSheet = false

    private var selectedExercise: ExerciseConfig {
        ExerciseConfig.all.first { $0.type == selectedExerciseType } ?? ExerciseConfig.all[0]
    }

    private var selectedAssessment: AssessmentConfig {
        AssessmentConfig.all.first { $0.type == selectedAssessmentType } ?? AssessmentConfig.all[0]
    }

    private var isAssessmentMode: Bool { analysisCategory == .assessment }

    private var currentRequiresSideSelection: Bool {
        if isAssessmentMode {
            return selectedAssessment.requiresSideSelection(plane: selectedAssessmentPlane)
        }
        return selectedExercise.requiresSideSelection
    }

    private var currentCameraSetupTip: String {
        if isAssessmentMode {
            return selectedAssessmentType.cameraSetupTip(for: selectedAssessmentPlane)
        }
        return selectedExerciseType.cameraSetupTip
    }

    private var currentTrackingWarning: String {
        if isAssessmentMode {
            return selectedAssessmentType.lowTrackingWarning(for: selectedAssessmentPlane)
        }
        return selectedExerciseType.lowTrackingWarning
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MetalCameraView(renderer: viewModel.metalRenderer)
                .ignoresSafeArea()

            LiveOverlayCanvas(frameState: viewModel.frameState)

            VStack(spacing: 0) {
                topBar
                Spacer()
                trackingWarningBanner
                bottomBar
            }
        }
        .navigationTitle("Live Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { setup() }
        .onDisappear { viewModel.stop() }
        .alert("Camera Access Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow camera access in Settings to use live form analysis.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = savedVideoURL { ShareSheet(items: [url]) }
        }
        .onChange(of: selectedExerciseType)    { _, _ in reconfigure() }
        .onChange(of: selectedAssessmentType)  { _, newType in
            // Snap plane to the new assessment's default if the previous plane
            // isn't supported. Always reconfigure afterwards.
            if let cfg = AssessmentConfig.all.first(where: { $0.type == newType }),
               !cfg.supportedPlanes.contains(selectedAssessmentPlane) {
                selectedAssessmentPlane = cfg.defaultPlane
            }
            reconfigure()
        }
        .onChange(of: selectedAssessmentPlane) { _, _ in reconfigure() }
        .onChange(of: selectedSide)            { _, _ in reconfigure() }
        .onChange(of: analysisCategory)        { _, _ in reconfigure() }
    }

    // MARK: - Sub-views

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Category", selection: $analysisCategory) {
                    ForEach(AnalysisCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                .pickerStyle(.segmented)

                if isAssessmentMode {
                    Menu {
                        ForEach(AssessmentType.allCases) { type in
                            Button {
                                selectedAssessmentType = type
                            } label: {
                                if selectedAssessmentType == type {
                                    Label(type.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(type.rawValue)
                                }
                            }
                        }
                    } label: {
                        dropdownLabel(text: selectedAssessmentType.rawValue)
                    }

                    let supportedPlanes = selectedAssessment.supportedPlanes
                    if supportedPlanes.count > 1 {
                        Picker("Plane", selection: $selectedAssessmentPlane) {
                            ForEach(supportedPlanes) { plane in
                                Text(plane.displayName).tag(plane)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } else {
                    Menu {
                        ForEach(ExerciseConfig.all, id: \.type) { exercise in
                            Button {
                                selectedExerciseType = exercise.type
                            } label: {
                                if selectedExerciseType == exercise.type {
                                    Label(exercise.displayName, systemImage: "checkmark")
                                } else {
                                    Text(exercise.displayName)
                                }
                            }
                        }
                    } label: {
                        dropdownLabel(text: selectedExercise.displayName)
                    }
                }

                if currentRequiresSideSelection {
                    Picker("Side", selection: $selectedSide) {
                        Text("Left").tag(BodySide.left)
                        Text("Right").tag(BodySide.right)
                    }
                    .pickerStyle(.segmented)
                }

                if !isAssessmentMode {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Overlay")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Overlay", selection: $viewModel.overlayMode) {
                            ForEach(OverlayMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if !viewModel.isRecording {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isAssessmentMode ? "Setup" : "Before recording")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(currentCameraSetupTip)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }
            }

            VStack(spacing: 8) {
                Button {
                    viewModel.switchCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.white.opacity(0.25))
                        .clipShape(Circle())
                }
                .accessibilityLabel(viewModel.cameraPosition == .back ? "Switch to front camera" : "Switch to back camera")

                if !isAssessmentMode {
                    Menu {
                        ForEach(CustomOverlayOption.allCases) { option in
                            Toggle(option.rawValue, isOn: liveOverlayBinding(for: option))
                        }
                    } label: {
                        Image(systemName: "line.diagonal")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.white.opacity(0.25))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Custom overlay options")
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    /// Large, obviously-tappable label for the exercise/assessment dropdown menus.
    /// The whole row (full width, 44pt min height) is the hit target, so users no
    /// longer have to land on just the small text to open the picker.
    private func dropdownLabel(text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var trackingWarningBanner: some View {
        LiveTrackingWarning(frameState: viewModel.frameState, text: currentTrackingWarning)
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            if isAssessmentMode {
                // Assessment mode: show live grade
                VStack(alignment: .leading, spacing: 2) {
                    Text("GRADE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("—")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(minWidth: 80, alignment: .leading)
            } else {
                // Exercise mode: rep counter
                VStack(alignment: .leading, spacing: 2) {
                    Text("REPS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LiveRepCountLabel(frameState: viewModel.frameState)
                }
                .frame(minWidth: 80, alignment: .leading)
            }

            Spacer()

            // Record / Stop button
            Button {
                Task { await toggleRecording() }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 72, height: 72)
                    if viewModel.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.red)
                            .frame(width: 26, height: 26)
                    } else {
                        Circle()
                            .fill(.red)
                            .frame(width: 54, height: 54)
                    }
                }
            }

            Spacer()

            if isAssessmentMode {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ASSESSMENT")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Live")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.cyan)
                }
                .frame(minWidth: 80, alignment: .trailing)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PHASE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LivePhaseLabel(frameState: viewModel.frameState)
                }
                .frame(minWidth: 80, alignment: .trailing)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func setup() {
        Task {
            await viewModel.checkAuthorization()
            guard viewModel.isAuthorized else {
                showPermissionAlert = true
                return
            }
            reconfigure()
            viewModel.start()
        }
    }

    private func reconfigure() {
        let analyzer: FrameAnalyzerProtocol
        if isAssessmentMode {
            analyzer = selectedAssessment.makeAnalyzer(
                side: selectedSide,
                plane: selectedAssessmentPlane
            )
        } else {
            analyzer = selectedExercise.makeAnalyzer(side: selectedSide)
        }
        viewModel.setAnalyzer(analyzer)
    }

    private func toggleRecording() async {
        if viewModel.isRecording {
            if let url = await viewModel.stopRecording() {
                savedVideoURL = url
                showShareSheet = true
            }
        } else {
            viewModel.startRecording()
        }
    }

    private func liveOverlayBinding(for option: CustomOverlayOption) -> Binding<Bool> {
        Binding(
            get: { viewModel.customOverlayOptions.contains(option) },
            set: { isSelected in
                if isSelected {
                    viewModel.customOverlayOptions.insert(option)
                } else {
                    viewModel.customOverlayOptions.remove(option)
                }
            }
        )
    }
}
