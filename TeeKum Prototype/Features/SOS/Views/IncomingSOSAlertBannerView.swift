//
//  IncomingSOSAlertBannerView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 04/11/26.
//

import SwiftUI

/// Top floating banner rendering an active incoming emergency SOS or Inactivity/Man-Down alert.
public struct IncomingSOSAlertBannerView: View {
    public let alert: IncomingSOSAlert
    public let onDismiss: () -> Void
    public let onTap: (() -> Void)?
    
    public init(
        alert: IncomingSOSAlert,
        onDismiss: @escaping () -> Void,
        onTap: (() -> Void)? = nil
    ) {
        self.alert = alert
        self.onDismiss = onDismiss
        self.onTap = onTap
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alert.emergencyType == .inactivity ? "figure.fall" : "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(.yellow)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(alert.emergencyType == .inactivity ? "MAN DOWN" : "EMERGENCY SOS")
                        .font(.caption2.bold())
                        .foregroundStyle(alert.emergencyType == .inactivity ? .black : .red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(alert.emergencyType == .inactivity ? Color.yellow : Color.white)
                        .clipShape(Capsule())
                    
                    Text(alert.senderName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                
                Text(alert.emergencyType == .inactivity
                     ? "⚠️ Immobile for >3m • Battery \(alert.batteryLevel)%"
                     : "\(alert.emergencyType.title) • Battery \(alert.batteryLevel)%")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            
            Spacer()
            
            Button("Dismiss", action: onDismiss)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 0.85, green: 0.1, blue: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .shadow(color: .red.opacity(0.5), radius: 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}
