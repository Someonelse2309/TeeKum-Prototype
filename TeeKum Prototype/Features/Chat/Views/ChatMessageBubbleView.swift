//
//  ChatMessageBubbleView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI

/// Reusable chat message bubble component rendering incoming and outgoing festival messages.
///
/// Master Specification Guarantees:
/// - Requirement 1 & 2: Incoming (left-aligned with sender initials & color) and Outgoing (right-aligned).
/// - Requirement 3 & 11: Accurate honest delivery states (pending, sent, relayed, delivered, failed).
///   Never presents an intermediary relay ACK as final recipient delivery.
/// - Requirement 4: Tappable to inspect per-recipient delivery and ACK progress.
/// - Requirement 11: Accessible touch targets (>= 44x44pt) and AMOLED #000000 dark aesthetics.
public struct ChatMessageBubbleView: View {
    let message: ChatMessage
    let localColor: MemberColor
    let senderColor: MemberColor
    let onSelectDetails: () -> Void
    
    public init(
        message: ChatMessage,
        localColor: MemberColor,
        senderColor: MemberColor,
        onSelectDetails: @escaping () -> Void
    ) {
        self.message = message
        self.localColor = localColor
        self.senderColor = senderColor
        self.onSelectDetails = onSelectDetails
    }
    
    public var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isLocalSender {
                Spacer(minLength: 40)
                outgoingBubble
            } else {
                incomingBubble
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }
    
    // MARK: - Outgoing Message Bubble
    
    private var outgoingBubble: some View {
        Button {
            onSelectDetails()
        } label: {
            VStack(alignment: .trailing, spacing: 4) {
                // Text Content
                Text(message.text)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                
                // Footer: Timestamp + Delivery State
                HStack(spacing: 4) {
                    Text(message.timestamp.formattedShortTime)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.6))
                    
                    deliveryStateBadge(for: message.deliveryState)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(red: 0.08, green: 0.12, blue: 0.16))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 4,
                    topTrailingRadius: 18
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 4,
                    topTrailingRadius: 18
                )
                .stroke(localAccentColor.opacity(0.4), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your message: \(message.text), sent at \(message.timestamp.formattedShortTime), \(message.deliverySummaryText). Double tap for delivery details.")
    }
    
    // MARK: - Incoming Message Bubble
    
    private var incomingBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Sender Initials Avatar
            ZStack {
                Circle()
                    .fill(senderColor.swiftUIColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                Circle()
                    .stroke(senderColor.swiftUIColor, lineWidth: 1.5)
                    .frame(width: 32, height: 32)
                Text(message.senderInitials)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Header: Sender initials + Timestamp
                HStack(spacing: 6) {
                    Text(message.senderInitials)
                        .font(.caption.bold())
                        .foregroundStyle(senderColor.swiftUIColor)
                    
                    Text(message.timestamp.formattedShortTime)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                
                // Text Content
                Text(message.text)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18
                )
                .stroke(senderColor.swiftUIColor.opacity(0.3), lineWidth: 1)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Message from \(message.senderInitials): \(message.text), received at \(message.timestamp.formattedShortTime)")
    }
    
    // MARK: - Delivery State Badge
    
    @ViewBuilder
    private func deliveryStateBadge(for state: ChatDeliveryState) -> some View {
        switch state {
        case .locallyAccepted:
            HStack(spacing: 3) {
                Image(systemName: "clock")
                Text("Sending...")
            }
            .font(.caption2)
            .foregroundStyle(.gray)
            
        case .forwardedToNextHop:
            HStack(spacing: 3) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                Text("Sent")
            }
            .font(.caption2)
            .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.04)) // Neon Amber
            
        case .relayedByMesh(let hops):
            HStack(spacing: 3) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                Text("Relayed (\(hops)h)")
            }
            .font(.caption2.bold())
            .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0)) // Neon Cyan
            
        case .delivered(let confirmed, let total):
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                if confirmed >= total {
                    Text("All (\(confirmed))")
                } else {
                    Text("\(confirmed)/\(total)")
                }
            }
            .font(.caption2.bold())
            .foregroundStyle(Color(red: 0.19, green: 0.82, blue: 0.35)) // Lime Mint
            
        case .deliveryTimedOut:
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Unconfirmed")
            }
            .font(.caption2.bold())
            .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.04))
            
        case .failed:
            HStack(spacing: 3) {
                Image(systemName: "xmark.circle.fill")
                Text("Failed")
            }
            .font(.caption2.bold())
            .foregroundStyle(Color(red: 1.0, green: 0.18, blue: 0.45)) // Neon Red
        }
    }
    
    private var localAccentColor: Color {
        localColor != .unset ? localColor.swiftUIColor : Color(red: 0.0, green: 0.85, blue: 1.0)
    }
}
