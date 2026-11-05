//
//  ByteMeterView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI

/// Compact circular progress indicator and numerical byte counter displaying real-time UTF-8 byte usage.
///
/// Features dynamic color thresholds:
/// - Consumed < 16 Bytes: Neon Cyan (Normal typing)
/// - Consumed 16..19 Bytes: Neon Amber (Approaching wire limit)
/// - Consumed 20 Bytes: Neon Red (Hard wire limit reached)
public struct ByteMeterView: View {
    @Bindable var viewModel: ChatViewModel
    
    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            // Circular progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                    .frame(width: 16, height: 16)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(viewModel.byteUsageRatio))
                    .stroke(
                        viewModel.byteMeterColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 16, height: 16)
                    .animation(.easeOut(duration: 0.15), value: viewModel.byteUsageRatio)
            }
            
            // Text count
            Text("\(viewModel.currentByteCount)/\(ChatViewModel.maxBytes)B")
                .font(.caption2.monospacedDigit().bold())
                .foregroundStyle(viewModel.byteMeterColor)
                .contentTransition(.numericText())
                .animation(.snappy, value: viewModel.currentByteCount)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.5))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(viewModel.byteMeterColor.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.currentByteCount) of \(ChatViewModel.maxBytes) bytes consumed")
    }
}
