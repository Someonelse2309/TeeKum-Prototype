//
//  InboundChatOutcome.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import Foundation

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
