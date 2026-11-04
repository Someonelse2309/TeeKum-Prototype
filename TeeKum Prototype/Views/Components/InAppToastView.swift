//
//  InAppToastView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI

/// Floating top banner toast for real-time festival alerts (Chat, Meeting Points, etc.).
public struct InAppToastView: View {
    let toast: InAppToast
    let onDismiss: () -> Void
    
    public init(toast: InAppToast, onDismiss: @escaping () -> Void) {
        self.toast = toast
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        Button {
            toast.action?()
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(toast.accentColor.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: toast.systemImage)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(toast.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title)
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(toast.accentColor)
                        .lineLimit(1)
                    
                    Text(toast.message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.12))
                    .shadow(color: Color.black.opacity(0.6), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(toast.accentColor.opacity(0.4), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}
