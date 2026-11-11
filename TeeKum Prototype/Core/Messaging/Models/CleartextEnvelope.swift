//
//  CleartextEnvelope.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

public struct CleartextEnvelope: Equatable, Sendable {
    public var version: UInt8
    public var type: PacketType
    public var hopLimit: UInt8
    public var hopCount: UInt8
    public var sessionId: UInt16
    public var sequenceNumber: UInt32
    
    public var memberSlot: UInt8 {
        CleartextEnvelope.memberSlot(from: sequenceNumber)
    }
    
    public var counter: UInt32 {
        CleartextEnvelope.counter(from: sequenceNumber)
    }
    
    public init(
        version: UInt8 = PacketConstants.protocolVersion,
        type: PacketType,
        hopLimit: UInt8 = PacketConstants.defaultHopLimit,
        hopCount: UInt8 = 0,
        sessionId: UInt16,
        sequenceNumber: UInt32
    ) {
        self.version = version
        self.type = type
        self.hopLimit = min(max(1, hopLimit), PacketConstants.maxHopLimit)
        self.hopCount = min(hopCount, self.hopLimit)
        self.sessionId = sessionId
        self.sequenceNumber = sequenceNumber
    }
    
    // MARK: - Sequence Number Partitioning
    
    public static func makeSequenceNumber(memberSlot: UInt8, counter: UInt32) -> UInt32 {
        (UInt32(memberSlot) << 24) | (counter & 0x00FFFFFF)
    }
    
    public static func memberSlot(from sequenceNumber: UInt32) -> UInt8 {
        UInt8((sequenceNumber >> 24) & 0xFF)
    }
    
    public static func counter(from sequenceNumber: UInt32) -> UInt32 {
        sequenceNumber & 0x00FFFFFF
    }
    
    // MARK: - Serialization (10 Bytes)
    
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.cleartextEnvelopeSize)
        
        // Byte 0: version (high 4 bits) | type (low 4 bits)
        let byte0 = ((version & 0x0F) << 4) | (type.rawValue & 0x0F)
        data.append(byte0)
        
        // Byte 1: hopLimit (UInt8)
        data.append(hopLimit)
        
        // Byte 2: hopCount (UInt8)
        data.append(hopCount)
        
        // Bytes 3..5: sessionId (3 bytes, 24-bit big-endian)
        let sid3Bytes: [UInt8] = [
            UInt8((sessionId >> 16) & 0xFF),
            UInt8((sessionId >> 8) & 0xFF),
            UInt8(sessionId & 0xFF)
        ]
        data.append(contentsOf: sid3Bytes)
        
        // Bytes 6..9: sequenceNumber (32-bit big-endian)
        var seqBE = sequenceNumber.bigEndian
        data.append(Data(bytes: &seqBE, count: 4))
        
        return data
    }
    
    public static func deserialize(from data: Data) throws -> CleartextEnvelope {
        guard data.count >= PacketConstants.cleartextEnvelopeSize else {
            throw PacketCodecError.bufferUnderflow
        }
        
        let byte0 = data[data.startIndex]
        let version = (byte0 >> 4) & 0x0F
        guard version == PacketConstants.protocolVersion else {
            throw PacketCodecError.unsupportedVersion(version)
        }
        
        let typeRaw = byte0 & 0x0F
        guard let type = PacketType(rawValue: typeRaw) else {
            throw PacketCodecError.unknownPacketType(typeRaw)
        }
        
        let hopLimit = data[data.startIndex + 1]
        guard hopLimit >= 1 && hopLimit <= PacketConstants.maxHopLimit else {
            throw PacketCodecError.invalidHopLimit(hopLimit)
        }
        
        let hopCount = data[data.startIndex + 2]
        guard hopCount <= hopLimit else {
            throw PacketCodecError.hopCountExceededLimit(count: hopCount, limit: hopLimit)
        }
        
        let b3 = UInt32(data[data.startIndex + 3])
        let b4 = UInt32(data[data.startIndex + 4])
        let b5 = UInt32(data[data.startIndex + 5])
        let sid32 = (b3 << 16) | (b4 << 8) | b5
        let sid16 = UInt16(sid32 & 0xFFFF)
        
        let seq = data.subdata(in: (data.startIndex + 6)..<(data.startIndex + 10)).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        
        return CleartextEnvelope(
            version: version,
            type: type,
            hopLimit: hopLimit,
            hopCount: hopCount,
            sessionId: sid16,
            sequenceNumber: seq
        )
    }
    
    // MARK: - Cryptographic Inputs (10 Bytes AAD)
    
    public func authenticatedAssociatedData() -> Data {
        var aad = Data(capacity: PacketConstants.cleartextEnvelopeSize)
        
        // Byte 0: versionAndType
        let byte0 = ((version & 0x0F) << 4) | (type.rawValue & 0x0F)
        aad.append(byte0)
        
        // Byte 1: hopLimit
        aad.append(hopLimit)
        
        // Byte 2: hopCount masked to 0x00
        aad.append(0x00)
        
        // Bytes 3..5: sessionId (3 bytes)
        let sid3Bytes: [UInt8] = [
            UInt8((sessionId >> 16) & 0xFF),
            UInt8((sessionId >> 8) & 0xFF),
            UInt8(sessionId & 0xFF)
        ]
        aad.append(contentsOf: sid3Bytes)
        
        // Bytes 6..9: sequenceNumber (4 bytes)
        var seqBE = sequenceNumber.bigEndian
        aad.append(Data(bytes: &seqBE, count: 4))
        
        return aad
    }
    
    /// Constructs the deterministic 12-byte (96-bit) AEAD Nonce:
    /// - Bytes 0..2: sessionId (3 bytes)
    /// - Bytes 3..6: sequenceNumber (4 bytes)
    /// - Byte 7: versionAndType (1 byte)
    /// - Bytes 8..11: Protocol Domain Tag "TKM3" ([0x54, 0x4B, 0x4D, 0x33])
    public func constructNonce() -> Data {
        var nonceData = Data(capacity: PacketConstants.nonceSize)
        
        let sid3Bytes: [UInt8] = [
            UInt8((sessionId >> 16) & 0xFF),
            UInt8((sessionId >> 8) & 0xFF),
            UInt8(sessionId & 0xFF)
        ]
        nonceData.append(contentsOf: sid3Bytes)
        
        var seqBE = sequenceNumber.bigEndian
        nonceData.append(Data(bytes: &seqBE, count: 4))
        
        let byte0 = ((version & 0x0F) << 4) | (type.rawValue & 0x0F)
        nonceData.append(byte0)
        
        nonceData.append(contentsOf: PacketConstants.protocolDomainTag)
        return nonceData
    }
}
