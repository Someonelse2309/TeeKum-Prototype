//
//  ChatMessage.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import Foundation

/// Strictly in-memory model representing a sent or received group chat message.
///
/// Master Specification Guarantees:
/// 1. Ephemeral: Stored strictly in memory (bounded to 50 latest messages). Zero disk persistence.
/// 2. Multi-Recipient ACK Tracking: Tracks individual delivery status for each intended recipient.
/// 3. Honest UX: Clearly distinguishes intermediary mesh relays from actual recipient delivery.
nonisolated public struct ChatMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sequenceNumber: UInt32
    public let senderInitials: String
    public let text: String
    public let timestamp: Date
    public var confirmedResponders: Set<String>
    public var recipientStates: [String: RecipientDeliveryState]
    public var deliveryState: ChatDeliveryState
    public let isLocalSender: Bool
    
    public init(
        id: UUID = UUID(),
        sequenceNumber: UInt32,
        senderInitials: String,
        text: String,
        timestamp: Date = Date(),
        confirmedResponders: Set<String> = [],
        recipientStates: [String: RecipientDeliveryState] = [:],
        deliveryState: ChatDeliveryState = .locallyAccepted,
        isLocalSender: Bool
    ) {
        self.id = id
        self.sequenceNumber = sequenceNumber
        self.senderInitials = InitialsCodec.sanitize(senderInitials)
        self.text = text
        self.timestamp = timestamp
        self.confirmedResponders = confirmedResponders
        self.recipientStates = recipientStates
        self.deliveryState = deliveryState
        self.isLocalSender = isLocalSender
    }
    
    /// Number of intended recipients who have confirmed receipt.
    public var confirmedRecipientCount: Int {
        recipientStates.values.filter { $0.isDelivered }.count
    }
    
    /// Total number of tracked intended recipients.
    public var totalRecipientCount: Int {
        max(1, recipientStates.count)
    }
    
    /// User-facing honest delivery summary string.
    public var deliverySummaryText: String {
        switch deliveryState {
        case .locallyAccepted:
            return "Sending..."
        case .forwardedToNextHop:
            return "Sent over Radio"
        case .relayedByMesh(let hops):
            return "Relayed by \(hops) \(hops == 1 ? "Hop" : "Hops") (Unconfirmed)"
        case .delivered(let confirmed, let total):
            if confirmed >= total {
                return "Delivered to All (\(confirmed)/\(total))"
            } else {
                return "Delivered \(confirmed)/\(total)"
            }
        case .deliveryTimedOut:
            if confirmedRecipientCount > 0 {
                return "Delivered \(confirmedRecipientCount)/\(totalRecipientCount) (Unconfirmed)"
            } else {
                return "Delivery Unconfirmed"
            }
        case .failed(let reason):
            return "Failed: \(reason)"
        }
    }
}

