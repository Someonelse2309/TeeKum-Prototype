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

/// Official venue landmark presets for festival coordination.
public struct LandmarkPreset: Identifiable, Sendable {
    public let id: UInt32
    public let name: String
    public let coordinate: CLLocationCoordinate2D
    
    public init(id: UInt32, name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
    }
}

public enum VenueLandmark {
    public static let presets: [LandmarkPreset] = [
        LandmarkPreset(id: 1, name: "Main Stage Sound Booth", coordinate: CLLocationCoordinate2D(latitude: 33.6822, longitude: -116.2355)),
        LandmarkPreset(id: 2, name: "Gate 3 Exit", coordinate: CLLocationCoordinate2D(latitude: 33.6845, longitude: -116.2380)),
        LandmarkPreset(id: 3, name: "First Aid / Medical Tent", coordinate: CLLocationCoordinate2D(latitude: 33.6810, longitude: -116.2340)),
        LandmarkPreset(id: 4, name: "Water Refill Station A", coordinate: CLLocationCoordinate2D(latitude: 33.6830, longitude: -116.2370)),
        LandmarkPreset(id: 5, name: "Food Truck Plaza", coordinate: CLLocationCoordinate2D(latitude: 33.6795, longitude: -116.2360)),
        LandmarkPreset(id: 6, name: "Merch Stand North", coordinate: CLLocationCoordinate2D(latitude: 33.6850, longitude: -116.2350))
    ]
    
    public static func preset(for id: UInt32?) -> LandmarkPreset? {
        guard let id = id else { return nil }
        return presets.first(where: { $0.id == id })
    }
    
    public static func preset(for name: String) -> LandmarkPreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return presets.first(where: { $0.name.lowercased() == trimmed })
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
    
    /// Initials of the member who created this proposal (e.g. "DNA").
    public let proposerId: String
    
    /// Optional predefined venue landmark identifier (0 if custom map pin).
    public var landmarkId: UInt32?
    
    /// Attendance dictionary mapping member initials to their attendance response.
    public var attendance: [String: AttendanceStatus]
    
    /// Timestamp when proposed.
    public var createdAt: Date
    
    public init(
        id: UInt32 = UInt32.random(in: 1...UInt32.max),
        name: String,
        coordinate: CLLocationCoordinate2D,
        targetTime: Date? = nil,
        proposerId: String,
        landmarkId: UInt32? = nil,
        attendance: [String: AttendanceStatus] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.targetTime = targetTime
        self.proposerId = InitialsCodec.sanitize(proposerId)
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
        lhs.attendance == rhs.attendance &&
        lhs.createdAt == rhs.createdAt
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(targetTime)
        hasher.combine(proposerId)
        hasher.combine(landmarkId)
        hasher.combine(createdAt)
    }
}
