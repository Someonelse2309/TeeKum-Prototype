//
//  QRScannerView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI
import AVFoundation
import UIKit

/// Native AVFoundation Camera QR Scanner with pre-permission educational primer,
/// permission denial handling, and simulator fallback.
public struct QRScannerView: View {
    public let onCodeScanned: (String) -> Void
    public let onCancel: (() -> Void)?
    public let isScanning: Bool
    
    @State private var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var manualLinkInput: String = ""
    @State private var isRequestingPermission: Bool = false
    
    public init(onCodeScanned: @escaping (String) -> Void, onCancel: (() -> Void)? = nil, isScanning: Bool = true) {
        self.isScanning = isScanning
        self.onCodeScanned = onCodeScanned
        self.onCancel = onCancel
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            switch authorizationStatus {
            case .authorized:
                #if targetEnvironment(simulator)
                simulatorFallbackView
                #else
                cameraScannerView
                #endif
                
            case .notDetermined:
                permissionPrimerView
                
            case .denied, .restricted:
                permissionDeniedView
                
            @unknown default:
                permissionDeniedView
            }
        }
        .onAppear {
            authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
        .onChange(of: manualLinkInput) { _, newValue in
            if let extracted = GroupSession.extractInviteURL(from: newValue)?.absoluteString,
               extracted != newValue,
               newValue.contains("teekum://") {
                manualLinkInput = extracted
            }
        }
    }
    
    // MARK: - Subviews
    
    #if !targetEnvironment(simulator)
    private var cameraScannerView: some View {
        ZStack {
            AVCaptureScannerRepresentable(isScanning: isScanning) { code in
                onCodeScanned(code)
            }
            .ignoresSafeArea()
            
            // Viewfinder Reticle Overlay
            VStack {
                Text("Align friend's QR code in frame")
                    .font(.footnote.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, 24)
                
                Spacer()
                
                // Viewfinder Box
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.8), lineWidth: 3)
                        .frame(width: 240, height: 240)
                    
                    // Corner accents
                    Image(systemName: "viewfinder")
                        .font(.system(size: 260, weight: .ultraLight))
                        .foregroundStyle(.green)
                }
                .accessibilityLabel("Camera Viewfinder")
                .accessibilityHint("Position the group QR code inside the green square.")
                
                Spacer()
                
                // Fallback manual entry button
                manualEntryAccordion
                    .padding(.bottom, 24)
            }
        }
    }
    #endif
    
    private var simulatorFallbackView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .padding(.top, 40)
            
            Text("Simulator Camera Emulation")
                .font(.headline)
                .foregroundStyle(.white)
            
            Text("Camera hardware is not available on iOS Simulator. Paste a universal invite link (teekum://join#...) or full share message below to join.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.gray)
                .padding(.horizontal)
            
            HStack(spacing: 8) {
                TextField("teekum://join#key=... or paste message", text: $manualLinkInput)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .font(.caption.monospaced())
                
                Button {
                    if let clip = UIPasteboard.general.string {
                        if let extracted = GroupSession.extractInviteURL(from: clip)?.absoluteString {
                            manualLinkInput = extracted
                        } else {
                            manualLinkInput = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                .accessibilityLabel("Paste from Clipboard")
            }
            .padding()
            .background(Color(white: 0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            
            Button {
                let trimmed = manualLinkInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    onCodeScanned(trimmed)
                }
            } label: {
                Text("Join with Invite Link")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .disabled(manualLinkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
            Spacer()
        }
    }
    
    private var permissionPrimerView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            
            VStack(spacing: 8) {
                Text("Scan Friend's QR Code")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                
                Text("TeeKum needs camera access to scan your friend's group barcode in person with zero cell reception.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.gray)
                    .padding(.horizontal, 32)
            }
            
            Button {
                requestCameraPermission()
            } label: {
                Text("Enable Camera")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .disabled(isRequestingPermission)
            
            Spacer()
            
            manualEntryAccordion
                .padding(.bottom, 24)
        }
    }
    
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            
            Text("Camera Access Disabled")
                .font(.title3.bold())
                .foregroundStyle(.white)
            
            Text("To scan group QR codes on-site, please allow camera access in iOS Settings, or paste an invite link below.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.gray)
                .padding(.horizontal, 32)
            
            Button {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            } label: {
                Label("Open iOS Settings", systemImage: "gear")
                    .font(.subheadline.bold())
                    .padding()
                    .background(Color(white: 0.2))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Spacer()
            
            manualEntryAccordion
                .padding(.bottom, 24)
        }
    }
    
    private var manualEntryAccordion: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Paste link or share message...", text: $manualLinkInput)
                        .font(.caption)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                    
                    Button {
                        if let clip = UIPasteboard.general.string {
                            if let extracted = GroupSession.extractInviteURL(from: clip)?.absoluteString {
                                manualLinkInput = extracted
                            } else {
                                manualLinkInput = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    .accessibilityLabel("Paste from Clipboard")
                }
                .padding(12)
                .background(Color(white: 0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                if !manualLinkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Join") {
                        let link = manualLinkInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCodeScanned(link)
                    }
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func requestCameraPermission() {
        isRequestingPermission = true
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                self.isRequestingPermission = false
                self.authorizationStatus = granted ? .authorized : .denied
            }
        }
    }
}

// MARK: - AVCapture UIViewControllerRepresentable

#if !targetEnvironment(simulator)
struct AVCaptureScannerRepresentable: UIViewControllerRepresentable {
    let isScanning: Bool
    let onCodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        context.coordinator.viewController = controller
        return controller
    }
    
    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        if isScanning {
            context.coordinator.hasScanned = false
            uiViewController.startScanning()
        } else { uiViewController.stopScanning() }
    }
    
    static func dismantleUIViewController(_ uiViewController: ScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }
    
    final class Coordinator: NSObject, ScannerViewControllerDelegate {
        let onCodeScanned: (String) -> Void
        weak var viewController: ScannerViewController?
        var hasScanned: Bool = false
        
        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }
        
        func didScanCode(_ code: String) {
            guard !hasScanned, GroupSession.parseInvite(from: code) != nil else { return }
            hasScanned = true
            
            viewController?.stopScanning()
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            onCodeScanned(code)
        }
    }
}

protocol ScannerViewControllerDelegate: AnyObject {
    func didScanCode(_ code: String)
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: ScannerViewControllerDelegate?
    private let sessionController = CameraSessionController()
    private var cameraTask: Task<Void, Never>?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startScanning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }
    
    public func stopScanning() {
        cameraTask?.cancel()
        cameraTask = nil
        Task { await sessionController.stop() }
    }

    func startScanning() {
        cameraTask?.cancel()
        cameraTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await sessionController.configure(delegate: self)
                guard !Task.isCancelled else { return }
                await sessionController.start()
            } catch {
                guard !Task.isCancelled else { return }
                let label = UILabel()
                label.text = "Camera unavailable. Paste an invite link below."
                label.textColor = .white
                label.numberOfLines = 0
                label.frame = view.bounds.insetBy(dx: 24, dy: 24)
                view.addSubview(label)
            }
        }
    }

    private func setupCamera() {
        let preview = sessionController.makePreviewLayer()
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else { return }
        delegate?.didScanCode(stringValue)
    }
}
#endif
