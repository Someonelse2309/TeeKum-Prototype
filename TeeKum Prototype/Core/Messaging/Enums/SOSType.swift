//
//  SOSType.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

public enum SOSType: UInt8, CaseIterable, Sendable {
    case general    = 0x00
    case medical    = 0x01
    case separated  = 0x02
    case security   = 0x03
    case inactivity = 0x04
    
    public var title: String {
        switch self {
        case .general:    return "General Emergency"
        case .medical:    return "Medical Assistance"
        case .separated:  return "Lost / Separated"
        case .security:   return "Security Concern"
        case .inactivity: return "Inactivity / Man Down"
        }
    }
}
