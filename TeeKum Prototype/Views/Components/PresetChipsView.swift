//
//  PresetChipsView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI

/// Horizontal carousel of 1-tap quick preset chips for swift communication in noisy festival environments.
///
/// Pre-validated standard presets (Decision D17 & Option B Status Retirement):
/// - "Beer line" (9 bytes)
/// - "At Main Stage" (13 bytes)
/// - "Restroom" (8 bytes)
/// - "Where are you?" (14 bytes)
/// - "On my way" (9 bytes)
/// - "Lost" (4 bytes)
public struct PresetChipsView: View {
    @Bindable var viewModel: ChatViewModel
    
    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChatMessagePayload.standardPresets, id: \.self) { preset in
                    Button {
                        viewModel.applyPreset(preset)
                    } label: {
                        HStack(spacing: 4) {
                            presetIcon(for: preset)
                                .font(.caption2)
                            Text(preset)
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(Color.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .disabled(!viewModel.isChatAvailable)
                    .accessibilityLabel("Quick preset: \(preset)")
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    @ViewBuilder
    private func presetIcon(for preset: String) -> some View {
        switch preset {
        case ChatMessagePayload.presetBeerLine:
            Image(systemName: "mug.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.04)) // Neon Amber
        case ChatMessagePayload.presetAtMainStage:
            Image(systemName: "music.note")
                .foregroundStyle(Color(red: 0.69, green: 0.32, blue: 0.87)) // Electric Purple
        case ChatMessagePayload.presetRestroom:
            Image(systemName: "figure.walk")
                .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0)) // Neon Cyan
        case ChatMessagePayload.presetWhereAreYou:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83)) // Bright Teal
        case ChatMessagePayload.presetOnMyWay:
            Image(systemName: "figure.run")
                .foregroundStyle(Color(red: 0.19, green: 0.82, blue: 0.35)) // Lime Mint
        case ChatMessagePayload.presetLost:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.18, blue: 0.45)) // Neon Pink
        default:
            Image(systemName: "sparkles")
                .foregroundStyle(.white)
        }
    }
}
