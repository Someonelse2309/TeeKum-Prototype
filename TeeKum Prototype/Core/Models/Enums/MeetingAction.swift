//
//  MeetingAction.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

/// Action taken regarding a group rendezvous point over the mesh.
public enum MeetingAction: UInt8, CaseIterable, Codable, Sendable {
    case propose = 0x01
    case accept  = 0x02
    case decline = 0x03
    case cancel  = 0x04
}
