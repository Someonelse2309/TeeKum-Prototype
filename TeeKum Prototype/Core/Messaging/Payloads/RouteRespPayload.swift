//
//  RouteRespPayload.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation

/// Type 6: `0x05` — Route Response Inner Payload (Phase 2)
public struct RouteRespPayload: Equatable, Sendable {
    public var originatorInitials: String
    public var targetInitials: String
    public var discoveryNonce: UInt32
    public var routeCost: UInt8
    
    public init(
        originatorInitials: String,
        targetInitials: String,
        discoveryNonce: UInt32,
        routeCost: UInt8
    ) {
        self.originatorInitials = InitialsCodec.sanitize(originatorInitials)
        self.targetInitials = InitialsCodec.sanitize(targetInitials)
        self.discoveryNonce = discoveryNonce
        self.routeCost = routeCost
    }
    
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.encryptedPayloadSize)
        let origBytes = InitialsCodec.encode(originatorInitials) ?? [0, 0]
        data.append(contentsOf: origBytes)
        
        let targetBytes = InitialsCodec.encode(targetInitials) ?? [0, 0]
        data.append(contentsOf: targetBytes)
        
        var nonce = discoveryNonce.bigEndian
        data.append(Data(bytes: &nonce, count: 4))
        data.append(routeCost)
        
        // 21 bytes reserved (30 - 9 = 21)
        data.append(Data(repeating: 0, count: 21))
        return data
    }
    
    public static func deserialize(from data: Data) throws -> RouteRespPayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let origBytes = [data[0], data[1]]
        let orig = InitialsCodec.decode(origBytes) ?? "UNK"
        
        let targetBytes = [data[2], data[3]]
        let target = InitialsCodec.decode(targetBytes) ?? "UNK"
        
        let nonce = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let cost = data[8]
        return RouteRespPayload(originatorInitials: orig, targetInitials: target, discoveryNonce: nonce, routeCost: cost)
    }
}
