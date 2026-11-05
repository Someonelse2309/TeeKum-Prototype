//
//  RecipientAckBreakdownView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI

/// Detailed inspection sheet presenting honest per-recipient delivery and ACK progress for a chat message.
///
/// Master Specification Guarantees:
/// - Requirement 4 & 7: Separately exposes delivery state for every intended group recipient.
/// - Requirement 6 & 11: Never presents an intermediary relay ACK as final recipient delivery.
/// - Provides exact timestamps, traversed hop count, and direct link signal quality (RSSI).
public struct RecipientAckBreakdownView: View {
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage
    let viewModel: ChatViewModel
    
    public init(message: ChatMessage, viewModel: ChatViewModel) {
        self.message = message
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                List {
                    // MARK: - 1. Message Summary Header
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\"\(message.text)\"")
                                    .font(.headline.bold())
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(message.timestamp.formattedSecondsTime)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.gray)
                            }
                            
                            HStack(spacing: 6) {
                                stateIcon(for: message.deliveryState)
                                Text(message.deliverySummaryText)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(stateColor(for: message.deliveryState))
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Message Information")
                    }
                    
                    // MARK: - 2. Per-Recipient Delivery Progress
                    Section {
                        if message.recipientStates.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(.gray)
                                Text("Broadcast across mesh to all active peers.")
                                    .font(.subheadline)
                                    .foregroundStyle(.gray)
                            }
                            .padding(.vertical, 4)
                        } else {
                            let sortedRecipients = message.recipientStates.keys.sorted()
                            ForEach(sortedRecipients, id: \.self) { recipient in
                                let state = message.recipientStates[recipient] ?? .locallyAccepted
                                recipientRow(recipient: recipient, state: state)
                            }
                        }
                    } header: {
                        Text("Recipient Confirmations (\(message.confirmedRecipientCount)/\(message.totalRecipientCount))")
                    } footer: {
                        Text("TeeKum strictly verifies end-to-end authenticated Poly1305 ACKs. Relayed mesh hops are reported transparently and are never presented as confirmed friend delivery.")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Delivery Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.bold())
                    .foregroundStyle(.white)
                }
            }
        }
    }
    
    // MARK: - Recipient Row
    
    @ViewBuilder
    private func recipientRow(recipient: String, state: RecipientDeliveryState) -> some View {
        let color = viewModel.memberColor(for: recipient)
        
        HStack(spacing: 12) {
            // Recipient Avatar
            ZStack {
                Circle()
                    .fill(color.swiftUIColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                Circle()
                    .stroke(color.swiftUIColor, lineWidth: 1.5)
                    .frame(width: 36, height: 36)
                Text(recipient)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(recipient)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                
                recipientStateDescription(state: state)
                    .font(.caption2)
                    .foregroundStyle(recipientStateColor(state: state))
            }
            
            Spacer()
            
            recipientStateBadge(state: state)
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func recipientStateDescription(state: RecipientDeliveryState) -> some View {
        switch state {
        case .locallyAccepted:
            Text("Pending in Outbox")
        case .forwardedToNextHop:
            Text("Sent over radio (Awaiting confirmation)")
        case .relayedByMesh(let hops, let relayPeer):
            if let peer = relayPeer {
                Text("Relayed via \(peer) (\(hops) \(hops == 1 ? "hop" : "hops")) — Unconfirmed")
            } else {
                Text("Relayed by mesh (\(hops) \(hops == 1 ? "hop" : "hops")) — Unconfirmed")
            }
        case .deliveredToRecipient(let ts, let rssi):
            if let r = rssi {
                Text("Confirmed at \(ts.formattedSecondsTime) • \(r) dBm")
            } else {
                Text("Confirmed at \(ts.formattedSecondsTime)")
            }
        case .deliveryTimedOut:
            Text("No response within 15s timeout window")
        case .failed(let reason):
            Text("Failed: \(reason)")
        }
    }
    
    @ViewBuilder
    private func recipientStateBadge(state: RecipientDeliveryState) -> some View {
        switch state {
        case .locallyAccepted:
            Image(systemName: "clock")
                .foregroundStyle(.gray)
        case .forwardedToNextHop:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.04)) // Neon Amber
        case .relayedByMesh:
            HStack(spacing: 3) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                Text("Relayed")
                    .font(.caption2.bold())
            }
            .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0)) // Neon Cyan
        case .deliveredToRecipient:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                Text("Confirmed")
                    .font(.caption2.bold())
            }
            .foregroundStyle(Color(red: 0.19, green: 0.82, blue: 0.35)) // Lime Mint
        case .deliveryTimedOut:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.04))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.18, blue: 0.45))
        }
    }
    
    private func recipientStateColor(state: RecipientDeliveryState) -> Color {
        switch state {
        case .locallyAccepted:
            return .gray
        case .forwardedToNextHop:
            return Color(red: 1.0, green: 0.84, blue: 0.04)
        case .relayedByMesh:
            return Color(red: 0.0, green: 0.85, blue: 1.0)
        case .deliveredToRecipient:
            return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .deliveryTimedOut:
            return Color(red: 1.0, green: 0.84, blue: 0.04)
        case .failed:
            return Color(red: 1.0, green: 0.18, blue: 0.45)
        }
    }
    
    // MARK: - State Visual Helpers
    
    @ViewBuilder
    private func stateIcon(for state: ChatDeliveryState) -> some View {
        switch state {
        case .locallyAccepted:
            Image(systemName: "clock")
        case .forwardedToNextHop:
            Image(systemName: "antenna.radiowaves.left.and.right")
        case .relayedByMesh:
            Image(systemName: "point.3.connected.trianglepath.dotted")
        case .delivered:
            Image(systemName: "checkmark.circle.fill")
        case .deliveryTimedOut:
            Image(systemName: "exclamationmark.triangle.fill")
        case .failed:
            Image(systemName: "xmark.circle.fill")
        }
    }
    
    private func stateColor(for state: ChatDeliveryState) -> Color {
        switch state {
        case .locallyAccepted:
            return .gray
        case .forwardedToNextHop:
            return Color(red: 1.0, green: 0.84, blue: 0.04)
        case .relayedByMesh:
            return Color(red: 0.0, green: 0.85, blue: 1.0)
        case .delivered:
            return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .deliveryTimedOut:
            return Color(red: 1.0, green: 0.84, blue: 0.04)
        case .failed:
            return Color(red: 1.0, green: 0.18, blue: 0.45)
        }
    }
}
