//
//  QRCodeView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

/// Native CoreImage QR Code Generator and Presenter.
/// Follows strict security rules: does not expose secret keys to logs, analytics,
/// or raw display text.
public struct QRCodeView: View {
    public let url: URL
    public let title: String
    public let subtitle: String?
    public let keyFingerprint: String?
    
    @State private var qrImage: UIImage?
    
    public init(
        url: URL,
        title: String,
        subtitle: String? = nil,
        keyFingerprint: String? = nil
    ) {
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.keyFingerprint = keyFingerprint
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .frame(width: 240, height: 240)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                
                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 216, height: 216)
                        .accessibilityLabel("Group invitation QR code for \(title)")
                        .accessibilityHint("Friends can scan this QR code on-site using TeeKum without cell service.")
                } else {
                    ProgressView()
                        .frame(width: 216, height: 216)
                }
            }
            .padding(.vertical, 8)
            
            // Safe key fingerprint display (never the full 256-bit secret)
            if let fingerprint = keyFingerprint {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Key Fingerprint: 0x\(fingerprint.uppercased())")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.gray)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(white: 0.12))
                .clipShape(Capsule())
            }
            
            // ShareLink for sending over AirDrop, iMessage, WhatsApp
            ShareLink(
                item: url,
                subject: Text("Join \(title) on TeeKum"),
                message: Text("Join my offline concert group on TeeKum: \(title)")
            ) {
                Label("Share Invite Link", systemImage: "square.and.arrow.up")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.18))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task {
            generateQRCode()
        }
    }
    
    private func generateQRCode() {
        let string = url.absoluteString
        guard let data = string.data(using: .utf8) else { return }
        
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let output = filter.outputImage else { return }
        
        // Nearest-neighbor scaling for high-contrast crisp pixels
        let targetSize: CGFloat = 432
        let scale = targetSize / output.extent.size.width
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        if let cgImage = context.createCGImage(transformed, from: transformed.extent) {
            self.qrImage = UIImage(cgImage: cgImage)
        }
    }
}
