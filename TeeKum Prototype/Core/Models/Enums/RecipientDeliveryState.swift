//
//  RecipientDeliveryState.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import Foundation

/// Delivery state for an individual intended recipient of a chat message.
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
