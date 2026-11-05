//
//  IncomingSOSAlert.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

/// Represents an authenticated emergency SOS received from a verified group member.
public struct IncomingSOSAlert: Identifiable, Equatable, Sendable {
    /// 32-bit unique emergency event identifier.
    public let id: UInt32
    
    /// Initials of the sender in distress (e.g. "DNA").
    public let senderInitials: String
    
    /// Local display name of the member in distress.
    public var senderName: String
    
    /// Specific category of emergency (`general`, `medical`, `separated`, `security`, `inactivity`).
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
