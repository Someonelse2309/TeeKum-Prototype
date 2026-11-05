//
//  ChatDeliveryState.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import Foundation

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
