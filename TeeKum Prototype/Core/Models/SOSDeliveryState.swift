//
//  SOSDeliveryState.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

/// Honest UX delivery status state machine for Emergency SOS dispatches.
/// Guarantees that the UI never implies an alert reached its final destination
/// when only a nearby intermediary relay has acknowledged it.
///
/// Master Specification States:
/// - LOCAL_SENDING
/// - RELAY_ACK
/// - DELIVERED_TO_FRIEND
/// - SEARCHING_PEERS
public enum SOSDeliveryState: Equatable, Sendable {
    case idle
    case countdown(remainingSeconds: Double)
    case localSending
    case relayedAck(relayHopCount: UInt8, responderId: String)
    case deliveredToFriend(friendId: String, timestamp: Date)
    case searchingPeers
    case failed(reason: String)
    
    public var title: String {
        switch self {
        case .idle:
            return "SOS Ready"
        case let .countdown(seconds):
            return String(format: "Hold for SOS (%.1fs)", seconds)
        case .localSending:
            return "Broadcasting SOS over Radio..."
        case let .relayedAck(hops, _):
            return "Relayed by \(hops) Mesh \(hops == 1 ? "Hop" : "Hops") (Not Yet Friend)"
        case .deliveredToFriend:
            return "Delivered to Friend Devices!"
        case .searchingPeers:
            return "Searching for Nearby Friends / Relays..."
        case let .failed(reason):
            return "SOS Delivery Warning: \(reason)"
        }
    }
    
    public var systemImage: String {
        switch self {
        case .idle:
            return "sos"
        case .countdown:
            return "timer"
        case .localSending:
            return "antenna.radiowaves.left.and.right"
        case .relayedAck:
            return "arrow.triangle.branch"
        case .deliveredToFriend:
            return "checkmark.shield.fill"
        case .searchingPeers:
            return "waveform.badge.magnifyingglass"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
    
    /// True when receipt on the friend device has been verified with cryptographic evidence.
    public var isDelivered: Bool {
        if case .deliveredToFriend = self { return true }
        return false
    }
    
    /// True when only an intermediary relay acknowledged forwarding.
    public var isRelayed: Bool {
        if case .relayedAck = self { return true }
        return false
    }
    
    /// True when attempting discovery or retrying without reachable peers.
    public var isSearchingPeers: Bool {
        if case .searchingPeers = self { return true }
        return false
    }
    
    /// True if transmission failed or retries were exhausted without confirmation.
    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
    
    /// Normalized lifecycle stage of delivery progression.
    public var stage: AcknowledgementStage {
        switch self {
        case .idle, .countdown:
            return .idle
        case .localSending:
            return .localSending
        case .searchingPeers:
            return .searchingPeers
        case .relayedAck:
            return .relayedAck
        case .deliveredToFriend:
            return .deliveredToFriend
        case .failed:
            return .deliveryTimedOut
        }
    }
}

