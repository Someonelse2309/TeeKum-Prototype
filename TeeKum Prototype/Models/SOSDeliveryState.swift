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
nonisolated public enum SOSDeliveryState: Equatable, Sendable {
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
}

/// Represents an authenticated emergency SOS received from a verified group member.
nonisolated public struct IncomingSOSAlert: Identifiable, Equatable, Sendable {
    /// 32-bit unique emergency event identifier.
    public let id: UInt32
    
    /// Initials of the sender in distress (e.g. "DNA").
    public let senderInitials: String
    
    /// Local display name of the member in distress.
    public var senderName: String
    
    /// Backward-compatibility sender identifier.
    public var senderId: String { senderInitials }
    
    /// Specific category of emergency (`general`, `medical`, `separated`, `security`).
    public let emergencyType: SOSType
    
    /// Freshest known coordinate reported by the sender.
    public let coordinate: CLLocationCoordinate2D
    
    /// Accuracy uncertainty radius in meters at measurement time.
    public let accuracy: UInt8
    
    /// Hardware measurement timestamp of coordinate (honest age).
    public let timestamp: Date
    
    /// Reported battery percentage of sender device (0...100).
    public let batteryLevel: UInt8
    
    /// Local timestamp when this alert was first received and verified.
    public let receivedAt: Date
    
    public init(
        id: UInt32,
        senderInitials: String,
        senderName: String? = nil,
        emergencyType: SOSType,
        coordinate: CLLocationCoordinate2D,
        accuracy: UInt8,
        timestamp: Date,
        batteryLevel: UInt8,
        receivedAt: Date = Date()
    ) {
        let cleanInitials = InitialsCodec.sanitize(senderInitials)
        self.id = id
        self.senderInitials = cleanInitials
        self.senderName = senderName ?? cleanInitials
        self.emergencyType = emergencyType
        self.coordinate = coordinate
        self.accuracy = accuracy
        self.timestamp = timestamp
        self.batteryLevel = batteryLevel
        self.receivedAt = receivedAt
    }
    
    public static func == (lhs: IncomingSOSAlert, rhs: IncomingSOSAlert) -> Bool {
        lhs.id == rhs.id &&
        lhs.senderInitials == rhs.senderInitials &&
        lhs.senderName == rhs.senderName &&
        lhs.emergencyType == rhs.emergencyType &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.accuracy == rhs.accuracy &&
        lhs.timestamp == rhs.timestamp &&
        lhs.batteryLevel == rhs.batteryLevel
    }
}
