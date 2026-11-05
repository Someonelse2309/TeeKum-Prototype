//
//  MeetingTimePreset.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

/// Rapid 1-tap presets for selecting when to meet at the festival.
public enum MeetingTimePreset: Int, CaseIterable, Identifiable, Sendable {
    case rightNow = 0
    case in15Mins = 15
    case in30Mins = 30
    case in1Hour  = 60
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .rightNow: return "Right Now"
        case .in15Mins: return "In 15m"
        case .in30Mins: return "In 30m"
        case .in1Hour:  return "In 1h"
        }
    }
    
    public func targetDate(from base: Date = Date()) -> Date {
        base.addingTimeInterval(TimeInterval(rawValue * 60))
    }
}
