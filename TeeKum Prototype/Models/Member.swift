//
//  Member.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

/// Represents a peer member participating in an active TeeKum group session.
public struct Member: Identifiable, Equatable, Hashable, Sendable {
    /// Ephemeral 32-bit member identifier unique within the active session.
    public let id: UInt32
    
    /// Display nickname chosen by the user.
    public var name: String
    
    /// Latest local timestamp when a valid authenticated packet was received from this member.
    public var lastSeen: Date
    
    /// Latest reported geographical coordinate.
    public var coordinate: CLLocationCoordinate2D?
    
    /// Latest reported horizontal accuracy uncertainty radius in meters.
    public var horizontalAccuracy: CLLocationAccuracy?
    
    /// Latest reported festival activity status.
    public var status: UserStatus
    
    /// Latest reported battery percentage (0.0 to 1.0).
    public var batteryLevel: Float?
    
    /// Latest reported magnetic compass heading in degrees (0..<360).
    public var heading: CLLocationDirection?
    
    /// True if currently discovered within direct 1-hop radio range; false if reached via multi-hop relay.
    public var isDirectPeer: Bool
    
    /// Signal strength observed on the direct link in dBm (e.g. -65 dBm), if directly connected.
    public var rssi: Int8?
    
    public init(
        id: UInt32,
        name: String,
        lastSeen: Date = Date(),
        coordinate: CLLocationCoordinate2D? = nil,
        horizontalAccuracy: CLLocationAccuracy? = nil,
        status: UserStatus = UserStatus(code: .available),
        batteryLevel: Float? = nil,
        heading: CLLocationDirection? = nil,
        isDirectPeer: Bool = false,
        rssi: Int8? = nil
    ) {
        self.id = id
        self.name = name
        self.lastSeen = lastSeen
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.status = status
        self.batteryLevel = batteryLevel
        self.heading = heading
        self.isDirectPeer = isDirectPeer
        self.rssi = rssi
    }
    
    /// Determines whether the member's last seen time is older than the given threshold.
    public func isStale(threshold: TimeInterval = 60) -> Bool {
        Date().timeIntervalSince(lastSeen) > threshold
    }
    
    public static func == (lhs: Member, rhs: Member) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.lastSeen == rhs.lastSeen &&
        lhs.coordinate?.latitude == rhs.coordinate?.latitude &&
        lhs.coordinate?.longitude == rhs.coordinate?.longitude &&
        lhs.horizontalAccuracy == rhs.horizontalAccuracy &&
        lhs.status == rhs.status &&
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
        hasher.combine(status)
    }
}
