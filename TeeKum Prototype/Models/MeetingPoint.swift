//
//  MeetingPoint.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

/// Action taken regarding a group rendezvous point.
public enum MeetingAction: UInt8, CaseIterable, Codable, Sendable {
    case propose = 0x01
    case accept  = 0x02
    case decline = 0x03
    case cancel  = 0x04
}

/// Member attendance state for the single active meeting point.
public enum AttendanceStatus: UInt8, CaseIterable, Codable, Sendable {
    case attending      = 0x01
    case cantMakeIt     = 0x02
    case atMeetingPoint = 0x09
    
    public var title: String {
        switch self {
        case .attending:      return "I'll be there"
        case .cantMakeIt:     return "Can't make it"
        case .atMeetingPoint: return "Arrived"
        }
    }
}

/// Model representing the single active rendezvous point for a group session.
public struct MeetingPoint: Identifiable, Equatable, Hashable, Sendable {
    /// Unique 32-bit identifier for this meeting instance.
    public let id: UInt32
    
    /// Human-readable label (e.g., "Stage 2 Sound Booth", "Gate 3 Exit").
    public var name: String
    
    /// Geographical coordinate of the rendezvous spot.
    public var coordinate: CLLocationCoordinate2D
    
    /// Target rendezvous time (e.g. 10:15 PM), or nil for immediate meetup.
    public var targetTime: Date?
    
    /// Member ID of the member who created this proposal.
    public let proposerId: UInt32
    
    /// Optional predefined venue landmark identifier (0 if custom map pin).
    public var landmarkId: UInt32?
    
    /// Attendance dictionary mapping member ID to their attendance response.
    public var attendance: [UInt32: AttendanceStatus]
    
    /// Timestamp when proposed.
    public var createdAt: Date
    
    public init(
        id: UInt32 = UInt32.random(in: 1...UInt32.max),
        name: String,
        coordinate: CLLocationCoordinate2D,
        targetTime: Date? = nil,
        proposerId: UInt32,
        landmarkId: UInt32? = nil,
        attendance: [UInt32: AttendanceStatus] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.targetTime = targetTime
        self.proposerId = proposerId
        self.landmarkId = landmarkId
        self.attendance = attendance
        self.createdAt = createdAt
    }
    
    public static func == (lhs: MeetingPoint, rhs: MeetingPoint) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.targetTime == rhs.targetTime &&
        lhs.proposerId == rhs.proposerId &&
        lhs.landmarkId == rhs.landmarkId &&
        lhs.attendance == rhs.attendance
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(proposerId)
    }
}
