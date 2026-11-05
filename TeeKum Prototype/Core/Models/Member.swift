//
//  Member.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

/// Represents a peer member participating in an active TeeKum group session.
/// Uniquely identified by their 3-letter Base-26 initials (e.g., "DNA", "ALX").
public struct Member: Identifiable, Equatable, Hashable, Sendable {
    /// 3-letter uppercase initials identifying the member.
    public let id: String
    
    /// Display name / initials.
    public var name: String
    
    /// Initials accessor.
    public var initials: String { id }
    
    /// Latest local timestamp when a valid authenticated packet was received from this member.
    public var lastSeen: Date
    
    /// Latest reported geographical coordinate.
    public var coordinate: CLLocationCoordinate2D?
    
    /// Latest reported horizontal accuracy uncertainty radius in meters.
    public var horizontalAccuracy: CLLocationAccuracy?
    
    /// True if the member has an active Emergency SOS broadcast.
    public var isEmergency: Bool
    
    /// Latest reported battery percentage (0.0 to 1.0).
    public var batteryLevel: Float?
    
    /// Latest reported magnetic compass heading in degrees (0..<360).
    public var heading: CLLocationDirection?
    
    /// True if currently discovered within direct 1-hop radio range; false if reached via multi-hop relay.
    public var isDirectPeer: Bool
    
    /// Signal strength observed on the direct link in dBm (e.g. -65 dBm), if directly connected.
    public var rssi: Int8?
    
    /// Chosen or deterministically resolved personal member color.
    public var color: MemberColor
    
    public init(
        id: String,
        name: String? = nil,
        lastSeen: Date = Date(),
        coordinate: CLLocationCoordinate2D? = nil,
        horizontalAccuracy: CLLocationAccuracy? = nil,
        isEmergency: Bool = false,
        batteryLevel: Float? = nil,
        heading: CLLocationDirection? = nil,
        isDirectPeer: Bool = false,
        rssi: Int8? = nil,
        color: MemberColor? = nil
    ) {
        let cleanId = InitialsCodec.sanitize(id)
        self.id = cleanId
        self.name = name ?? cleanId
        self.lastSeen = lastSeen
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.isEmergency = isEmergency
        self.batteryLevel = batteryLevel
        self.heading = heading
        self.isDirectPeer = isDirectPeer
        self.rssi = rssi
        self.color = color ?? MemberColor.deterministicColor(for: cleanId)
    }
    
    /// Determines whether the member's last seen time is older than the given threshold.
    public func isStale(threshold: TimeInterval = TeeKumConfiguration.Timing.stalePeerThreshold) -> Bool {
        Date().timeIntervalSince(lastSeen) > threshold
    }
    
    /// Determines whether the member's last seen time is within the active stale probe recovery window.
    /// Active recovery begins after `stalePeerThreshold` (30s) and expires after `stalePeerThreshold + recoveryTimeout` (90s).
    public func isWithinStaleRecoveryWindow(
        now: Date = Date(),
        staleThreshold: TimeInterval = MeshTimingConfiguration.default.stalePeerThreshold,
        recoveryTimeout: TimeInterval = MeshTimingConfiguration.default.staleRecoveryTimeout
    ) -> Bool {
        let age = now.timeIntervalSince(lastSeen)
        return age > staleThreshold && age <= (staleThreshold + recoveryTimeout)
    }
    
    /// Determines whether the member is eligible for Stage 2 on-demand AODV route discovery.
    /// Stage 2 initiates after `stalePeerThreshold + routeReqDelay` (45s) and within recovery timeout (90s).
    public func isEligibleForStaleRouteDiscovery(
        now: Date = Date(),
        staleThreshold: TimeInterval = MeshTimingConfiguration.default.stalePeerThreshold,
        routeReqDelay: TimeInterval = MeshTimingConfiguration.default.staleRouteReqDelay,
        recoveryTimeout: TimeInterval = MeshTimingConfiguration.default.staleRecoveryTimeout
    ) -> Bool {
        let age = now.timeIntervalSince(lastSeen)
        return age >= (staleThreshold + routeReqDelay) && age <= (staleThreshold + recoveryTimeout)
    }
    
    public static func == (lhs: Member, rhs: Member) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.lastSeen == rhs.lastSeen &&
        lhs.coordinate?.latitude == rhs.coordinate?.latitude &&
        lhs.coordinate?.longitude == rhs.coordinate?.longitude &&
        lhs.horizontalAccuracy == rhs.horizontalAccuracy &&
        lhs.isEmergency == rhs.isEmergency &&
        lhs.batteryLevel == rhs.batteryLevel &&
        lhs.heading == rhs.heading &&
        lhs.isDirectPeer == rhs.isDirectPeer &&
        lhs.rssi == rhs.rssi
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(lastSeen)
        if let coordinate {
            hasher.combine(coordinate.latitude)
            hasher.combine(coordinate.longitude)
        }
        hasher.combine(isEmergency)
    }
}
