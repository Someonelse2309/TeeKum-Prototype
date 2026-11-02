@preconcurrency import AVFoundation

/// AVFoundation requires a shared session reference for its main-thread preview and serial
/// capture control. This handle is the sole bridge; configuration/start/stop stay in the actor.
private nonisolated final class CameraSessionHandle: @unchecked Sendable {
    let session = AVCaptureSession()
}

actor CameraSessionController {
    nonisolated private let handle = CameraSessionHandle()
    private var metadataOutput: AVCaptureMetadataOutput?
    private weak var delegate: (any AVCaptureMetadataOutputObjectsDelegate & Sendable)?

    @MainActor
    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        AVCaptureVideoPreviewLayer(session: handle.session)
    }

    func configure(delegate: any AVCaptureMetadataOutputObjectsDelegate & Sendable) throws {
        self.delegate = delegate
        guard metadataOutput == nil else { return }
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        let input = try AVCaptureDeviceInput(device: device)
        let session = handle.session
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let output = AVCaptureMetadataOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else { return }
        session.addInput(input)
        session.addOutput(output)
        output.metadataObjectTypes = [.qr]
        metadataOutput = output
    }

    func start() {
        guard let metadataOutput else { return }
        metadataOutput.setMetadataObjectsDelegate(delegate, queue: .main)
        if !handle.session.isRunning { handle.session.startRunning() }
    }

    func stop() {
        metadataOutput?.setMetadataObjectsDelegate(nil, queue: nil)
        if handle.session.isRunning { handle.session.stopRunning() }
    }
}
