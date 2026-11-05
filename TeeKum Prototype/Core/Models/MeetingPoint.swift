//
//  MeetingPoint.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

/// Model representing the single active rendezvous point for a group session.
/// Location naming has been redesigned to be dynamic (proposer initials + target time & countdown).
public struct MeetingPoint: Identifiable, Equatable, Hashable, Sendable {
    /// Unique 32-bit identifier for this meeting instance.
    public let id: UInt32
    
    /// Geographical coordinate of the rendezvous spot.
    public var coordinate: CLLocationCoordinate2D
    
    /// Target rendezvous time.
    public var meetupTime: Date
    
    /// Timestamp when proposed.
    public var createdAt: Date
    
    /// Initials of the member who created this proposal (e.g. "DNA").
    public let proposerId: String
    
    /// True if the meetup was requested for immediately ("Right Now").
    public var isRightNow: Bool
    
    /// True if the point is anchored to the proposer's current GPS location.
    public var anchorToProposerGPS: Bool
    
    /// Radius in meters for automatic arrival detection (default: 25 meters).
    public var arrivalRadiusMeters: Double
    
    /// Attendance dictionary mapping member initials to their attendance response.
    public var attendance: [String: AttendanceStatus]
    
    // MARK: - Compatibility & Display Properties
    
    /// Backwards-compatible name property returning the dynamic title.
    public var name: String {
        formattedTitle
    }
    
    /// Clean title describing the rendezvous author (e.g. "DNA's Meetup").
    public var title: String {
        "\(proposerId)'s Meetup"
    }
    
    /// Dynamic display label with countdown (e.g. "DNA's Meetup • 10:30 PM (in 15m)" or "DNA's Meetup • Right Now").
    public var formattedTitle: String {
        "\(title) • \(timeDescription)"
    }
    
    /// Human-readable time description with relative offset.
    public var timeDescription: String {
        if isRightNow {
            return "Right Now"
        }
        
        let clockString = meetupTime.formattedMeetupTime
        
        let diffMinutes = Int(meetupTime.timeIntervalSinceNow / 60)
        if diffMinutes > 0 {
            return "\(clockString) (in \(diffMinutes)m)"
        } else if diffMinutes >= -5 {
            return "\(clockString) (now)"
        } else {
            return "\(clockString) (started)"
        }
    }
    
    /// A rendezvous auto-expires 1 hour (3600 seconds) after the target meetup time.
    public var isExpired: Bool {
        Date().timeIntervalSince(meetupTime) > 3600
    }
    
    // MARK: - Initializer
    
    public init(
        id: UInt32 = UInt32.random(in: 1...UInt32.max),
        coordinate: CLLocationCoordinate2D,
        meetupTime: Date = Date(),
        createdAt: Date = Date(),
        proposerId: String,
        isRightNow: Bool = false,
        anchorToProposerGPS: Bool = false,
        arrivalRadiusMeters: Double = 25.0,
        attendance: [String: AttendanceStatus] = [:]
    ) {
        self.id = id
        self.coordinate = coordinate
        self.meetupTime = meetupTime
        self.createdAt = createdAt
        self.proposerId = InitialsCodec.sanitize(proposerId)
        self.isRightNow = isRightNow
        self.anchorToProposerGPS = anchorToProposerGPS
        self.arrivalRadiusMeters = arrivalRadiusMeters
        self.attendance = attendance
    }
    
    public static func == (lhs: MeetingPoint, rhs: MeetingPoint) -> Bool {
        lhs.id == rhs.id &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.meetupTime == rhs.meetupTime &&
        lhs.createdAt == rhs.createdAt &&
        lhs.proposerId == rhs.proposerId &&
        lhs.isRightNow == rhs.isRightNow &&
        lhs.anchorToProposerGPS == rhs.anchorToProposerGPS &&
        lhs.arrivalRadiusMeters == rhs.arrivalRadiusMeters &&
        lhs.attendance == rhs.attendance
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(meetupTime)
        hasher.combine(createdAt)
        hasher.combine(proposerId)
        hasher.combine(isRightNow)
        hasher.combine(anchorToProposerGPS)
        hasher.combine(arrivalRadiusMeters)
    }
}
