//
//  ACKStatus.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

public enum ACKStatus: UInt8, CaseIterable, Sendable {
    case deliveredToFriend = 0x01
    case relayedByMeshHop  = 0x02
}
