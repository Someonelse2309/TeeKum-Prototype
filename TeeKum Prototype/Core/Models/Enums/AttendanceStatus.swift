//
//  AttendanceStatus.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

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
