//
//  RawWirePacket.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

nonisolated public struct RawWirePacket: Equatable, Sendable {
    public var envelope: CleartextEnvelope
    public var ciphertext: Data
    public var authTag: Data
    
    public init(envelope: CleartextEnvelope, ciphertext: Data, authTag: Data) {
        self.envelope = envelope
        self.ciphertext = ciphertext
        self.authTag = authTag
    }
    
    /// Combines envelope (10B), ciphertext (30B), and auth tag (16B) into exactly 56 bytes.
    public func toWireData() throws -> Data {
        let envData = envelope.serialize()
        guard envData.count == PacketConstants.cleartextEnvelopeSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.cleartextEnvelopeSize, actual: envData.count)
        }
        guard ciphertext.count == PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.encryptedPayloadSize, actual: ciphertext.count)
        }
        guard authTag.count == PacketConstants.authTagSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.authTagSize, actual: authTag.count)
        }
        
        var packet = Data(capacity: PacketConstants.wirePacketSize)
        packet.append(envData)
        packet.append(ciphertext)
        packet.append(authTag)
        return packet
    }
    
    /// Parses a 56-byte binary datagram from the network.
    public static func fromWireData(_ data: Data) throws -> RawWirePacket {
        guard data.count == PacketConstants.wirePacketSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.wirePacketSize, actual: data.count)
        }
        
        let envData = data.subdata(in: 0..<10)
        let envelope = try CleartextEnvelope.deserialize(from: envData)
        let ciphertext = data.subdata(in: 10..<40)
        let authTag = data.subdata(in: 40..<56)
        
        return RawWirePacket(envelope: envelope, ciphertext: ciphertext, authTag: authTag)
    }
}
