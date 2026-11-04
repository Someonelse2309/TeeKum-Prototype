//
//  ChatMessage.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import Foundation

// MARK: - Delivery States

/// Delivery state for an individual intended recipient of a chat message.
///
/// Implements Requirement 6, 7, and 8:
/// - Track ACK and delivery state separately for each intended recipient.
/// - Never treat a relay ACK as final recipient delivery.
/// - Preserves states: locally accepted, forwarded to next hop, relayed by mesh, delivered to recipient, delivery timed out, failed.
nonisolated public enum RecipientDeliveryState: Equatable, Sendable {
    case locallyAccepted
    case forwardedToNextHop
    case relayedByMesh(hops: UInt8, relayPeerId: String?)
    case deliveredToRecipient(timestamp: Date, rssi: Int8?)
    case deliveryTimedOut
    case failed(reason: String)
    
    public var isDelivered: Bool {
        if case .deliveredToRecipient = self { return true }
        return false
    }
    
    public var isRelayed: Bool {
        if case .relayedByMesh = self { return true }
        return false
    }
    
    public var isTimedOut: Bool {
        if case .deliveryTimedOut = self { return true }
        return false
    }
    
    public var priorityRank: Int {
        switch self {
        case .locallyAccepted: return 0
        case .forwardedToNextHop: return 1
        case .relayedByMesh: return 2
        case .deliveredToRecipient: return 3
        case .deliveryTimedOut: return 3
        case .failed: return 3
        }
    }
}

/// Aggregated delivery state for an entire chat message across all recipients.
nonisolated public enum ChatDeliveryState: Equatable, Sendable {
    case locallyAccepted
    case forwardedToNextHop
    case relayedByMesh(hopCount: UInt8)
    case delivered(confirmedCount: Int, totalRecipients: Int)
    case deliveryTimedOut
    case failed(reason: String)
    
    public var isDelivered: Bool {
        if case .delivered = self { return true }
        return false
    }
    
    public var isRelayed: Bool {
        if case .relayedByMesh = self { return true }
        return false
    }
    
    public var isTimedOut: Bool {
        if case .deliveryTimedOut = self { return true }
        return false
    }
    
    public var priorityRank: Int {
        switch self {
        case .locallyAccepted: return 0
        case .forwardedToNextHop: return 1
        case .relayedByMesh: return 2
        case .delivered: return 3
        case .deliveryTimedOut: return 3
        case .failed: return 3
        }
    }
}

// MARK: - In-Memory Chat Message Model

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
                return "Delivered \(confirmedRecipientCount)/\(totalRecipientCount) (Timed Out)"
            } else {
                return "Delivery Timed Out"
            }
        case .failed(let reason):
            return "Failed: \(reason)"
        }
    }
}

// MARK: - Chat Engine Errors

nonisolated public enum ChatEngineError: Error, LocalizedError, Equatable {
    case invalidTextLength(Int)
    case cooldownActive(remainingSeconds: Double)
    case batteryThrottled(batteryLevel: Float)
    case survivalModeActive
    case noActiveSession
    case queueFull(String)
    case serializationFailed
    case encryptionFailed(String)
    case decryptionFailed(String)
    case duplicateMessage(UInt32)
    case sessionTerminated
    
    public var errorDescription: String? {
        switch self {
        case .invalidTextLength(let count):
            return "Message length is invalid (\(count) bytes). Must be between 1 and 20 UTF-8 bytes."
        case .cooldownActive(let remaining):
            return String(format: "Chat cooldown active. Please wait %.1f seconds.", remaining)
        case .batteryThrottled(let level):
            return String(format: "Chat disabled below 20%% battery (current: %.0f%%). Emergency SOS remains active.", level * 100)
        case .survivalModeActive:
            return "Chat disabled in Festival Survival Mode (<20% battery). Emergency SOS remains active."
        case .noActiveSession:
            return "Cannot send chat message without an active group session."
        case .queueFull(let msg):
            return "Chat queue is full: \(msg)"
        case .serializationFailed:
            return "Failed to serialize chat message payload."
        case .encryptionFailed(let msg):
            return "Failed to encrypt chat message: \(msg)"
        case .decryptionFailed(let msg):
            return "Failed to decrypt chat message: \(msg)"
        case .duplicateMessage(let seq):
            return "Duplicate chat message dropped (sequence \(seq))."
        case .sessionTerminated:
            return "Active session was terminated."
        }
    }
}

// MARK: - Inbound Chat Outcome

nonisolated public enum InboundChatOutcome: Equatable, Sendable {
    case deliveredLocally(message: ChatMessage)
    case deliveredLocallyAndRelayed(message: ChatMessage, nextHopCount: UInt8)
    case ackProcessed(sequenceNumber: UInt32, responderInitials: String, isDelivered: Bool)
    case relayedStranger(sessionId: UInt16, hopCount: UInt8)
    case droppedDuplicate(sequenceNumber: UInt32)
    case droppedSecurityFailed
    case droppedPolicyDisabled
    case droppedHopLimitExceeded
    case droppedSelfEcho
    case droppedMalformed
    
    public var deliveredMessage: ChatMessage? {
        switch self {
        case .deliveredLocally(let message), .deliveredLocallyAndRelayed(let message, _):
            return message
        default:
            return nil
        }
    }
    
    public var isDeliveredLocally: Bool {
        deliveredMessage != nil
    }
}
