import AVFoundation
import CoreVideo
import os.log

private let logger = Logger(subsystem: "com.kevinjones.Kinetriq", category: "CameraService")

/// Manages an AVCaptureSession and delivers BGRA pixel buffers on a serial queue.
final class CameraService: NSObject, ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var isAuthorized = false

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let outputQueue = DispatchQueue(label: "com.kevinjones.camera.output",
                                           qos: .userInteractive)

    /// Called on outputQueue for every captured frame.
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    /// Portrait dimensions after rotation (set during configure).
    private(set) var captureWidth: Int = 720
    private(set) var captureHeight: Int = 1280

    // MARK: - Authorization

    func checkAndRequestAuthorization() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await MainActor.run { isAuthorized = true }
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run { isAuthorized = granted }
        default:
            await MainActor.run { isAuthorized = false }
        }
    }

    // MARK: - Configuration

    func configure(position: AVCaptureDevice.Position = .back) {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        session.inputs.forEach  { session.removeInput($0)  }
        session.outputs.forEach { session.removeOutput($0) }

        guard let device = preferredCamera(for: position),
              let deviceInput = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(deviceInput) else {
            logger.error("Could not create camera input")
            session.commitConfiguration()
            return
        }
        session.addInput(deviceInput)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(videoOutput) else {
            logger.error("Could not add video output")
            session.commitConfiguration()
            return
        }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            // Rotate to portrait so normalized landmark coords match frame orientation
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if position == .front {
                connection.isVideoMirrored = true
            }
        }

        // After 90° rotation the long axis becomes height
        captureWidth  = 720
        captureHeight = 1280

        session.commitConfiguration()
        logger.info("Camera configured: \(position == .front ? "front" : "back") \(self.captureWidth)×\(self.captureHeight)")
    }

    // MARK: - Start / Stop

    func start() {
        guard !session.isRunning else { return }
        outputQueue.async { [self] in
            session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
        DispatchQueue.main.async { self.isRunning = false }
    }

    // MARK: - Private

    private func preferredCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInWideAngleCamera
        ]
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: position
        ).devices.first
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onFrame?(pixelBuffer, time)
    }
}
