//
//  PacketCodec.swift
//  TeeKum Prototype
//
//  Created by Fantasix Team.
//

import Foundation
import CoreLocation

// MARK: - Safe Binary Buffer Writer

/// Fast, bounds-checked binary buffer builder for fixed-size wire datagrams.
public struct PacketWriter: Sendable {
    public private(set) var data: Data
    
    public init(capacity: Int) {
        self.data = Data(capacity: capacity)
    }
    
    public mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
    }
    
    public mutating func writeUInt16BigEndian(_ value: UInt16) {
        var be = value.bigEndian
        data.append(Data(bytes: &be, count: MemoryLayout<UInt16>.size))
    }
    
    public mutating func writeUInt24BigEndian(_ value: UInt32) {
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }
    
    public mutating func writeUInt32BigEndian(_ value: UInt32) {
        var be = value.bigEndian
        data.append(Data(bytes: &be, count: MemoryLayout<UInt32>.size))
    }
    
    public mutating func writeInt32BigEndian(_ value: Int32) {
        var be = value.bigEndian
        data.append(Data(bytes: &be, count: MemoryLayout<Int32>.size))
    }
    
    public mutating func writeBytes(_ bytes: Data) {
        data.append(bytes)
    }
    
    public mutating func writeZeroPadding(count: Int) {
        data.append(contentsOf: [UInt8](repeating: 0x00, count: count))
    }
}

// MARK: - Safe Binary Buffer Reader

/// Bounds-checked binary stream reader that prevents buffer overflows and underflows.
public struct PacketReader: Sendable {
    private let data: Data
    public private(set) var offset: Int
    
    public init(data: Data) {
        self.data = data
        self.offset = data.startIndex
    }
    
    public var remainingBytes: Int {
        data.endIndex - offset
    }
    
    public mutating func readUInt8() throws -> UInt8 {
        guard remainingBytes >= 1 else { throw PacketCodecError.bufferUnderflow }
        let byte = data[offset]
        offset += 1
        return byte
    }
    
    public mutating func readUInt16BigEndian() throws -> UInt16 {
        guard remainingBytes >= 2 else { throw PacketCodecError.bufferUnderflow }
        let sub = data.subdata(in: offset..<(offset + 2))
        offset += 2
        return sub.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
    }
    
    public mutating func readUInt24BigEndian() throws -> UInt32 {
        guard remainingBytes >= 3 else { throw PacketCodecError.bufferUnderflow }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        offset += 3
        return (b0 << 16) | (b1 << 8) | b2
    }
    
    public mutating func readUInt32BigEndian() throws -> UInt32 {
        guard remainingBytes >= 4 else { throw PacketCodecError.bufferUnderflow }
        let sub = data.subdata(in: offset..<(offset + 4))
        offset += 4
        return sub.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }
    
    public mutating func readInt32BigEndian() throws -> Int32 {
        guard remainingBytes >= 4 else { throw PacketCodecError.bufferUnderflow }
        let sub = data.subdata(in: offset..<(offset + 4))
        offset += 4
        return sub.withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
    }
    
    public mutating func readBytes(count: Int) throws -> Data {
        guard remainingBytes >= count else { throw PacketCodecError.bufferUnderflow }
        let sub = data.subdata(in: offset..<(offset + count))
        offset += count
        return sub
    }
}

// MARK: - Authoritative Packet Codec

/// Authoritative utility for encoding, decoding, quantizing, and validating 56-byte wire datagrams.
public enum PacketCodec: Sendable {
    
    public static let coordinateScalingFactor: Double = 1_000_000.0
    
    // MARK: - Geographic Quantization (~11cm Resolution)
    
    /// Quantizes a latitude or longitude degree into a signed 32-bit big-endian integer.
    public static func quantizeCoordinateDegrees(_ degrees: CLLocationDegrees) -> Int32 {
        Int32((degrees * coordinateScalingFactor).rounded())
    }
    
    /// Dequantizes a signed 32-bit integer back to high-precision double degrees.
    public static func dequantizeCoordinate(latitudeRaw: Int32, longitudeRaw: Int32) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: Double(latitudeRaw) / coordinateScalingFactor,
            longitude: Double(longitudeRaw) / coordinateScalingFactor
        )
    }
    
    // MARK: - Compass Heading Quantization (0..<360 Degrees -> 0..255)
    
    /// Quantizes compass heading (0..<360 degrees) into a single byte.
    public static func quantizeHeading(_ heading: CLLocationDirection) -> UInt8 {
        let normalized = (heading.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        return UInt8(min(255, max(0, Int((normalized * 255.0 / 360.0).rounded()))))
    }
    
    /// Reconstructs compass heading in degrees from a quantized 1-byte value.
    public static func dequantizeHeading(_ byte: UInt8) -> CLLocationDirection {
        Double(byte) * 360.0 / 255.0
    }
    
    // MARK: - Timestamp Quantization (Unix Epoch Seconds)
    
    public static func quantizeTimestamp(_ date: Date) -> UInt32 {
        UInt32(max(0, date.timeIntervalSince1970))
    }
    
    public static func dequantizeTimestamp(_ epochSeconds: UInt32) -> Date {
        Date(timeIntervalSince1970: TimeInterval(epochSeconds))
    }
    
    // MARK: - 10-Byte Cleartext Envelope Serialization
    
    public static func encodeEnvelope(_ envelope: CleartextEnvelope) -> Data {
        var writer = PacketWriter(capacity: PacketConstants.cleartextEnvelopeSize)
        
        // Byte 0: version (high 4 bits) | type (low 4 bits)
        let byte0 = ((envelope.version & 0x0F) << 4) | (envelope.type.rawValue & 0x0F)
        writer.writeUInt8(byte0)
        
        // Byte 1: hopLimit
        writer.writeUInt8(envelope.hopLimit)
        
        // Byte 2: hopCount
        writer.writeUInt8(envelope.hopCount)
        
        // Bytes 3..5: 24-bit session ID
        writer.writeUInt24BigEndian(UInt32(envelope.sessionId))
        
        // Bytes 6..9: 32-bit sequence number
        writer.writeUInt32BigEndian(envelope.sequenceNumber)
        
        return writer.data
    }
    
    public static func decodeEnvelope(from data: Data) throws -> CleartextEnvelope {
        guard data.count >= PacketConstants.cleartextEnvelopeSize else {
            throw PacketCodecError.bufferUnderflow
        }
        
        var reader = PacketReader(data: data)
        let byte0 = try reader.readUInt8()
        let version = (byte0 >> 4) & 0x0F
        guard version == PacketConstants.protocolVersion else {
            throw PacketCodecError.unsupportedVersion(version)
        }
        
        let typeRaw = byte0 & 0x0F
        guard let type = PacketType(rawValue: typeRaw) else {
            throw PacketCodecError.unknownPacketType(typeRaw)
        }
        
        let hopLimit = try reader.readUInt8()
        guard hopLimit >= 1 else {
            throw PacketCodecError.invalidHopLimit(hopLimit)
        }
        
        let hopCount = try reader.readUInt8()
        guard hopCount <= hopLimit else {
            throw PacketCodecError.hopCountExceededLimit(count: hopCount, limit: hopLimit)
        }
        
        let sid24 = try reader.readUInt24BigEndian()
        let sessionId = UInt16(sid24 & 0xFFFF)
        let sequenceNumber = try reader.readUInt32BigEndian()
        
        return CleartextEnvelope(
            version: version,
            type: type,
            hopLimit: hopLimit,
            hopCount: hopCount,
            sessionId: sessionId,
            sequenceNumber: sequenceNumber
        )
    }
    
    // MARK: - 56-Byte Wire Packet Slicing
    
    public static func assembleWirePacket(
        envelope: CleartextEnvelope,
        ciphertext: Data,
        authTag: Data
    ) throws -> Data {
        guard ciphertext.count == PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.encryptedPayloadSize, actual: ciphertext.count)
        }
        guard authTag.count == PacketConstants.authTagSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.authTagSize, actual: authTag.count)
        }
        
        var writer = PacketWriter(capacity: PacketConstants.wirePacketSize)
        writer.writeBytes(encodeEnvelope(envelope))
        writer.writeBytes(ciphertext)
        writer.writeBytes(authTag)
        return writer.data
    }
    
    public static func disassembleWirePacket(_ data: Data) throws -> RawWirePacket {
        guard data.count == PacketConstants.wirePacketSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.wirePacketSize, actual: data.count)
        }
        
        let envData = data.subdata(in: 0..<PacketConstants.cleartextEnvelopeSize)
        let ciphertext = data.subdata(in: PacketConstants.cleartextEnvelopeSize..<(PacketConstants.cleartextEnvelopeSize + PacketConstants.encryptedPayloadSize))
        let authTag = data.subdata(in: (PacketConstants.cleartextEnvelopeSize + PacketConstants.encryptedPayloadSize)..<PacketConstants.wirePacketSize)
        
        let envelope = try decodeEnvelope(from: envData)
        return RawWirePacket(envelope: envelope, ciphertext: ciphertext, authTag: authTag)
    }
}
