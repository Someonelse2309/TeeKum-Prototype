//
//  Status.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

/// 1-byte compact coded status hash transmitted over the air.
/// Localized display strings and icons are rendered entirely on the receiver.
public enum StatusCode: UInt8, CaseIterable, Codable, Sendable {
    /// Default idle state / green indicator
    case available       = 0x00
    /// Urgent emergency siren / high-priority event
    case sos             = 0x01
    /// On My Way
    case omw             = 0x02
    /// User is separated or disoriented
    case lost            = 0x03
    /// Roaming the festival grounds
    case exploring       = 0x04
    /// Asking friends to hold position
    case wait            = 0x05
    /// Asking friends to navigate toward this user
    case comeToMe        = 0x06
    /// Navigating toward a specific friend or landmark
    case goingTo         = 0x07
    /// Rendezvous meeting cancelled
    case cancelMeeting   = 0x08
    /// Reached the agreed rendezvous landmark
    case atMeetingPoint  = 0x09
    /// At bar / purchasing drinks
    case gettingDrinks   = 0x0A
    /// Waiting in restroom / toilet queue
    case restroom        = 0x0B
    /// Getting food or merchandise
    case foodMerch       = 0x0C
    /// At first aid / medical tent
    case medical         = 0x0D
    
    /// User-facing short title.
    public var title: String {
        switch self {
        case .available:       return "Available"
        case .sos:             return "Emergency SOS"
        case .omw:             return "On My Way"
        case .lost:            return "I'm Lost"
        case .exploring:       return "Exploring"
        case .wait:            return "Wait for Me"
        case .comeToMe:        return "Come to Me"
        case .goingTo:         return "Going to..."
        case .cancelMeeting:   return "Meeting Cancelled"
        case .atMeetingPoint:  return "At Meeting Point"
        case .gettingDrinks:   return "Getting Drinks"
        case .restroom:        return "In Restroom Line"
        case .foodMerch:       return "Food & Merch"
        case .medical:         return "Medical / First Aid"
        }
    }
    
    /// Visual SF Symbol representation.
    public var systemImage: String {
        switch self {
        case .available:       return "checkmark.circle.fill"
        case .sos:             return "exclamationmark.triangle.fill"
        case .omw:             return "figure.walk"
        case .lost:            return "questionmark.circle.fill"
        case .exploring:       return "safari.fill"
        case .wait:            return "hand.raised.fill"
        case .comeToMe:        return "arrow.triangle.pull"
        case .goingTo:         return "arrow.triangle.turn.up.right.diamond.fill"
        case .cancelMeeting:   return "xmark.circle.fill"
        case .atMeetingPoint:  return "mappin.circle.fill"
        case .gettingDrinks:   return "wineglass.fill"
        case .restroom:        return "figure.dress.line.vertical.figure"
        case .foodMerch:       return "fork.knife"
        case .medical:         return "cross.case.fill"
        }
    }
    
    /// Quick emoji for map pins and status chips.
    public var emoji: String {
        switch self {
        case .available:       return "🟢"
        case .sos:             return "🚨"
        case .omw:             return "🏃"
        case .lost:            return "❓"
        case .exploring:       return "🧭"
        case .wait:            return "✋"
        case .comeToMe:        return "👉"
        case .goingTo:         return "🎯"
        case .cancelMeeting:   return "❌"
        case .atMeetingPoint:  return "📍"
        case .gettingDrinks:   return "🍻"
        case .restroom:        return "🚻"
        case .foodMerch:       return "🍔"
        case .medical:         return "🩹"
        }
    }
    
    /// True if the status represents a safety emergency requiring immediate UI escalation.
    public var isEmergency: Bool {
        self == .sos || self == .medical
    }
}

/// Represents the active user status with an optional target entity reference.
public struct UserStatus: Equatable, Hashable, Codable, Sendable {
    /// 1-byte status hash.
    public var code: StatusCode
    
    /// Optional 32-bit ID pointing to a target friend or meeting point (used with `goingTo`).
    public var targetRefId: UInt32?
    
    /// Local timestamp when status was updated.
    public var updatedAt: Date
    
    public init(code: StatusCode = .available, targetRefId: UInt32? = nil, updatedAt: Date = Date()) {
        self.code = code
        self.targetRefId = targetRefId
        self.updatedAt = updatedAt
    }
}
