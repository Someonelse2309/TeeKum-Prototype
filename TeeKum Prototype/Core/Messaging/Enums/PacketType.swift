//
//  PacketType.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

public enum PacketType: UInt8, CaseIterable, Sendable {
    case locationPing     = 0x01
    case sos              = 0x02
    case meetingUpdate    = 0x03
    case routeReq         = 0x04
    case routeResp        = 0x05
    case ack              = 0x06
    case chatMessage      = 0x07
    case uwbTokenExchange = 0x08
}
