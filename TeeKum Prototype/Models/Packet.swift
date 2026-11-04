//
//  Packet.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

// MARK: - Constants

nonisolated public enum PacketConstants {
    public static var wirePacketSize: Int { TeeKumConfiguration.Network.wirePacketSize }
    public static var cleartextEnvelopeSize: Int { TeeKumConfiguration.Network.cleartextEnvelopeSize }
    public static var encryptedPayloadSize: Int { TeeKumConfiguration.Network.encryptedPayloadSize }
    public static var authTagSize: Int { TeeKumConfiguration.Network.authTagSize }
    public static var nonceSize: Int { TeeKumConfiguration.Network.nonceSize }
    
    public static var protocolVersion: UInt8 { TeeKumConfiguration.Network.protocolVersion }
    public static var defaultHopLimit: UInt8 {
        get { TeeKumConfiguration.Network.defaultHopLimit }
        set { TeeKumConfiguration.Network.defaultHopLimit = newValue }
    }
    public static var chatHopLimit: UInt8 {
        get { TeeKumConfiguration.Network.chatHopLimit }
        set { TeeKumConfiguration.Network.chatHopLimit = newValue }
    }
    public static var uwbHopLimit: UInt8 {
        get { TeeKumConfiguration.Network.uwbHopLimit }
        set { TeeKumConfiguration.Network.uwbHopLimit = newValue }
    }
    public static var maxHopLimit: UInt8 {
        get { TeeKumConfiguration.Network.maxHopLimit }
        set { TeeKumConfiguration.Network.maxHopLimit = newValue }
    }
    public static var meetingPointHopLimit: UInt8 {
        get { TeeKumConfiguration.Network.meetingPointHopLimit }
        set { TeeKumConfiguration.Network.meetingPointHopLimit = newValue }
    }
    public static var sosHopLimit: UInt8 {
        get { TeeKumConfiguration.Network.sosHopLimit }
        set { TeeKumConfiguration.Network.sosHopLimit = newValue }
    }
    
    /// Validates whether a given data buffer size matches the strictly fixed 56-byte wire format.
    public static func isValidWirePacketSize(_ count: Int) -> Bool {
        count == wirePacketSize
    }
    
    /// 4-byte protocol domain tag used in nonce construction: 'T', 'K', 'M', '3'
    public static var protocolDomainTag: [UInt8] { TeeKumConfiguration.Network.protocolDomainTag }
}

// MARK: - Packet Type

public enum PacketType: UInt8, CaseIterable, Sendable {
    case locationPing  = 0x01
    case sos           = 0x02
    case meetingUpdate = 0x03
    case routeReq      = 0x04
    case routeResp     = 0x05
    case ack           = 0x06
    case chatMessage   = 0x07
    case uwbTokenExchange = 0x08
}

// MARK: - Emergency & ACK Enums

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

public enum ACKStatus: UInt8, CaseIterable, Sendable {
    case deliveredToFriend = 0x01
    case relayedByMeshHop  = 0x02
}

// MARK: - Errors

public enum PacketCodecError: Error, LocalizedError, Equatable {
    case invalidPacketSize(expected: Int, actual: Int)
    case unsupportedVersion(UInt8)
    case unknownPacketType(UInt8)
    case invalidHopLimit(UInt8)
    case hopCountExceededLimit(count: UInt8, limit: UInt8)
    case invalidCoordinateRange(latitude: Double, longitude: Double)
    case invalidBatteryLevel(UInt8)
    case payloadSerializationFailed
    case payloadDeserializationFailed
    case bufferUnderflow
    case invalidInitials(String)
    case invalidTextLength(Int)
    case invalidTextEncoding
    
    public var errorDescription: String? {
        switch self {
        case let .invalidPacketSize(expected, actual):
            return "Invalid packet size: expected \(expected) bytes, got \(actual) bytes."
        case let .unsupportedVersion(v):
            return "Unsupported protocol version: \(v)."
        case let .unknownPacketType(t):
            return "Unknown packet type identifier: \(t)."
        case let .invalidHopLimit(limit):
            return "Invalid hop limit \(limit): must be in range 1...15."
        case let .hopCountExceededLimit(count, limit):
            return "Hop count \(count) exceeded maximum hop limit \(limit)."
        case let .invalidCoordinateRange(lat, lon):
            return "Coordinate outside geographic boundaries: lat=\(lat), lon=\(lon)."
        case let .invalidBatteryLevel(b):
            return "Battery level \(b)% exceeds maximum valid range 0...100%."
        case .payloadSerializationFailed:
            return "Failed to serialize payload to exactly 30 bytes."
        case .payloadDeserializationFailed:
            return "Failed to deserialize 30-byte payload."
        case .bufferUnderflow:
            return "Buffer underflow while reading wire bytes."
        case let .invalidInitials(i):
            return "Invalid 3-letter initials: '\(i)'. Must be exactly 3 uppercase letters A-Z."
        case let .invalidTextLength(len):
            return "Invalid text length: \(len) bytes. Must be between 0 and 20 bytes."
        case .invalidTextEncoding:
            return "Invalid text encoding: string content is not valid UTF-8."
        }
    }
}

// MARK: - Cleartext Envelope (10 Bytes)

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
        guard hopLimit >= 1 else {
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

// MARK: - 56-Byte Wire Packet

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

// MARK: - Decoded Inner Payloads (30 Bytes Each)

/// Type 1: `0x01` — Location Ping Inner Payload (Option B — Pure Telemetry)
///
/// Encrypted 30-Byte Payload Layout:
/// - Bytes 0..3: latitudeRaw (4B signed Int32 big-endian, ~11cm resolution)
/// - Bytes 4..7: longitudeRaw (4B signed Int32 big-endian, ~11cm resolution)
/// - Bytes 8..11: timestamp (4B Unix epoch seconds big-endian)
/// - Byte 12: accuracy (1B horizontal uncertainty radius in meters: 0...255m)
/// - Bytes 13..14: senderInitials (2B Base-27 compressed initials via InitialsCodec)
/// - Byte 15: batteryLevel (1B percentage: 0...100%)
/// - Byte 16: heading (1B compass degrees * 255 / 360, decoded via headingDegrees: 0.0..<360.0°)
/// - Byte 17: colorCode (1B MemberColor code: 0x00...0x08)
/// - Bytes 18..29: reserved (12B zero padding for Phase 3 vertical floor & barometry)
public struct LocationPingPayload: Equatable, Sendable {
    public var coordinate: CLLocationCoordinate2D
    public var timestamp: Date
    public var accuracy: UInt8
    public var senderInitials: String // 1..3 uppercase characters A-Z
    public var batteryLevel: UInt8    // 0...100
    public var heading: UInt8         // 0...255 representing 0..<360 degrees
    public var colorCode: UInt8       // 0x00...0x08 MemberColor code
    
    /// Reconstructed magnetic compass heading in degrees (0..<360).
    public var headingDegrees: CLLocationDirection {
        CLLocationDirection.fromHeadingByte(heading)
    }
    
    /// Primary Initializer (Phase 3 Option B: Pure geographic & sensor telemetry)
    public init(
        coordinate: CLLocationCoordinate2D,
        timestamp: Date = Date(),
        accuracy: UInt8,
        senderInitials: String,
        batteryLevel: UInt8,
        heading: UInt8 = 0,
        colorCode: UInt8 = 0
    ) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.accuracy = accuracy
        self.senderInitials = InitialsCodec.sanitize(senderInitials)
        self.batteryLevel = min(batteryLevel, 100)
        self.heading = heading
        self.colorCode = colorCode
    }
    
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.encryptedPayloadSize)
        let latRaw = coordinate.rawLatitude.bigEndian
        let lonRaw = coordinate.rawLongitude.bigEndian
        let tsRaw = UInt32(timestamp.timeIntervalSince1970).bigEndian
        
        // Bytes 0..3: latitudeRaw (4B signed Int32)
        var lat = latRaw; data.append(Data(bytes: &lat, count: 4))
        // Bytes 4..7: longitudeRaw (4B signed Int32)
        var lon = lonRaw; data.append(Data(bytes: &lon, count: 4))
        // Bytes 8..11: timestamp (4B UInt32 epoch seconds)
        var ts = tsRaw; data.append(Data(bytes: &ts, count: 4))
        // Byte 12: accuracy (1B UInt8)
        data.append(accuracy)
        
        // Bytes 13..14: senderInitials (2B Base-27)
        let initialBytes = InitialsCodec.encode(senderInitials) ?? [0, 0]
        data.append(contentsOf: initialBytes)
        
        // Byte 15: batteryLevel (1B UInt8)
        data.append(min(batteryLevel, 100))
        // Byte 16: heading (1B UInt8)
        data.append(heading)
        // Byte 17: colorCode (1B UInt8)
        data.append(colorCode)
        
        // Bytes 18..29: 12 bytes consolidated reserved zero padding (30 - 18 = 12)
        data.append(Data(repeating: 0, count: 12))
        return data
    }
    
    public static func deserialize(from data: Data) throws -> LocationPingPayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let start = data.startIndex
        let latRaw = data.subdata(in: start..<(start + 4)).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        let lonRaw = data.subdata(in: (start + 4)..<(start + 8)).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        let tsRaw = data.subdata(in: (start + 8)..<(start + 12)).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let accuracy = data[start + 12]
        
        let initialBytes = [data[start + 13], data[start + 14]]
        let initials = InitialsCodec.decode(initialBytes) ?? "UNK"
        
        let battery = data[start + 15]
        let heading = data[start + 16]
        let colorCode = data[start + 17]
        
        let coord = CLLocationCoordinate2D.dequantize(latitudeRaw: latRaw, longitudeRaw: lonRaw)
        guard coord.latitude >= -90.0 && coord.latitude <= 90.0 && coord.longitude >= -180.0 && coord.longitude <= 180.0 else {
            throw PacketCodecError.invalidCoordinateRange(latitude: coord.latitude, longitude: coord.longitude)
        }
        let date = Date(timeIntervalSince1970: TimeInterval(tsRaw))
        
        return LocationPingPayload(
            coordinate: coord,
            timestamp: date,
            accuracy: accuracy,
            senderInitials: initials,
            batteryLevel: min(battery, 100),
            heading: heading,
            colorCode: colorCode
        )
    }
}

/// Type 2: `0x02` — SOS Emergency Inner Payload
public struct SOSPayload: Equatable, Sendable {
    public var coordinate: CLLocationCoordinate2D
    public var timestamp: Date
    public var accuracy: UInt8
    public var sosEventId: UInt32
    public var senderInitials: String // 3 uppercase characters
    public var emergencyType: SOSType
    public var batteryLevel: UInt8
    public var colorCode: UInt8       // 0x00...0x08 MemberColor code
    
    public init(
        coordinate: CLLocationCoordinate2D,
        timestamp: Date = Date(),
        accuracy: UInt8,
        sosEventId: UInt32 = UInt32.random(in: 1...UInt32.max),
        senderInitials: String,
        emergencyType: SOSType = .general,
        batteryLevel: UInt8,
        colorCode: UInt8 = 0
    ) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.accuracy = accuracy
        self.sosEventId = sosEventId
        self.senderInitials = InitialsCodec.sanitize(senderInitials)
        self.emergencyType = emergencyType
        self.batteryLevel = min(batteryLevel, 100)
        self.colorCode = colorCode
    }
    
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.encryptedPayloadSize)
        let latRaw = coordinate.rawLatitude.bigEndian
        let lonRaw = coordinate.rawLongitude.bigEndian
        let tsRaw = UInt32(timestamp.timeIntervalSince1970).bigEndian
        
        var lat = latRaw; data.append(Data(bytes: &lat, count: 4))
        var lon = lonRaw; data.append(Data(bytes: &lon, count: 4))
        var ts = tsRaw; data.append(Data(bytes: &ts, count: 4))
        data.append(accuracy)
        data.append(0x01) // Fixed urgent SOS status marker byte
        
        var eventId = sosEventId.bigEndian
        data.append(Data(bytes: &eventId, count: 4))
        
        let initialBytes = InitialsCodec.encode(senderInitials) ?? [0, 0]
        data.append(contentsOf: initialBytes)
        
        data.append(emergencyType.rawValue)
        data.append(min(batteryLevel, 100))
        data.append(colorCode)
        
        // 7 bytes reserved padding (30 - 23 = 7)
        data.append(Data(repeating: 0, count: 7))
        return data
    }
    
    public static func deserialize(from data: Data) throws -> SOSPayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let latRaw = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        let lonRaw = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        let tsRaw = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let accuracy = data[12]
        let eventId = data.subdata(in: 14..<18).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        let initialBytes = [data[18], data[19]]
        let initials = InitialsCodec.decode(initialBytes) ?? "UNK"
        
        let emergencyByte = data[20]
        let battery = data[21]
        let colorCode = data.count > 22 ? data[22] : 0
        
        let coord = CLLocationCoordinate2D.dequantize(latitudeRaw: latRaw, longitudeRaw: lonRaw)
        guard coord.latitude >= -90.0 && coord.latitude <= 90.0 && coord.longitude >= -180.0 && coord.longitude <= 180.0 else {
            throw PacketCodecError.invalidCoordinateRange(latitude: coord.latitude, longitude: coord.longitude)
        }
        let date = Date(timeIntervalSince1970: TimeInterval(tsRaw))
        let emergency = SOSType(rawValue: emergencyByte) ?? .general
        
        return SOSPayload(
            coordinate: coord,
            timestamp: date,
            accuracy: accuracy,
            sosEventId: eventId,
            senderInitials: initials,
            emergencyType: emergency,
            batteryLevel: min(battery, 100),
            colorCode: colorCode
        )
    }
}

/// Type 3: `0x03` — Meeting Update Inner Payload (Redesigned 30-Byte Fixed Format)
public struct MeetingUpdatePayload: Equatable, Sendable {
    public var coordinate: CLLocationCoordinate2D
    public var meetupTime: Date
    public var createdAt: Date
    public var action: MeetingAction
    public var attendanceStatus: AttendanceStatus
    public var meetingPointId: UInt32
    public var senderInitials: String // 1-3 uppercase characters
    public var arrivalRadiusMeters: UInt8 // default: 25 meters
    public var flags: UInt8 // Bit 0: isRightNow, Bit 1: anchorToProposerGPS
    
    public var isRightNow: Bool {
        (flags & 0x01) != 0
    }
    
    public var anchorToProposerGPS: Bool {
        (flags & 0x02) != 0
    }
    
    public init(
        coordinate: CLLocationCoordinate2D,
        meetupTime: Date = Date(),
        createdAt: Date = Date(),
        action: MeetingAction,
        attendanceStatus: AttendanceStatus,
        meetingPointId: UInt32,
        senderInitials: String,
        arrivalRadiusMeters: UInt8 = 25,
        flags: UInt8 = 0
    ) {
        self.coordinate = coordinate
        self.meetupTime = meetupTime
        self.createdAt = createdAt
        self.action = action
        self.attendanceStatus = attendanceStatus
        self.meetingPointId = meetingPointId
        self.senderInitials = InitialsCodec.sanitize(senderInitials)
        self.arrivalRadiusMeters = max(5, min(100, arrivalRadiusMeters))
        self.flags = flags
    }
    
    public init(
        coordinate: CLLocationCoordinate2D,
        meetupTime: Date = Date(),
        createdAt: Date = Date(),
        action: MeetingAction,
        attendanceStatus: AttendanceStatus,
        meetingPointId: UInt32,
        senderInitials: String,
        arrivalRadiusMeters: UInt8 = 25,
        isRightNow: Bool = false,
        anchorToProposerGPS: Bool = false
    ) {
        var computedFlags: UInt8 = 0
        if isRightNow { computedFlags |= 0x01 }
        if anchorToProposerGPS { computedFlags |= 0x02 }
        self.init(
            coordinate: coordinate,
            meetupTime: meetupTime,
            createdAt: createdAt,
            action: action,
            attendanceStatus: attendanceStatus,
            meetingPointId: meetingPointId,
            senderInitials: senderInitials,
            arrivalRadiusMeters: arrivalRadiusMeters,
            flags: computedFlags
        )
    }
    
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.encryptedPayloadSize)
        let latRaw = coordinate.rawLatitude.bigEndian
        let lonRaw = coordinate.rawLongitude.bigEndian
        let meetupTsRaw = UInt32(meetupTime.timeIntervalSince1970).bigEndian
        let createdTsRaw = UInt32(createdAt.timeIntervalSince1970).bigEndian
        
        var lat = latRaw; data.append(Data(bytes: &lat, count: 4))
        var lon = lonRaw; data.append(Data(bytes: &lon, count: 4))
        var mts = meetupTsRaw; data.append(Data(bytes: &mts, count: 4))
        var cts = createdTsRaw; data.append(Data(bytes: &cts, count: 4))
        data.append(action.rawValue)
        data.append(attendanceStatus.rawValue)
        
        var mpId = meetingPointId.bigEndian
        data.append(Data(bytes: &mpId, count: 4))
        
        let initialBytes = InitialsCodec.encode(senderInitials) ?? [0, 0]
        data.append(contentsOf: initialBytes)
        
        data.append(arrivalRadiusMeters)
        data.append(flags)
        
        // 4 bytes reserved for future protocol revisions
        data.append(Data(repeating: 0, count: 4))
        return data
    }
    
    public static func deserialize(from data: Data) throws -> MeetingUpdatePayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let latRaw = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        let lonRaw = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        let meetupTsRaw = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let createdTsRaw = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let actionByte = data[16]
        let attendanceByte = data[17]
        let mpId = data.subdata(in: 18..<22).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        let initialBytes = [data[22], data[23]]
        let initials = InitialsCodec.decode(initialBytes) ?? "UNK"
        
        let arrivalRadius = data[24]
        let flagsByte = data[25]
        
        let coord = CLLocationCoordinate2D.dequantize(latitudeRaw: latRaw, longitudeRaw: lonRaw)
        guard coord.latitude >= -90.0 && coord.latitude <= 90.0 && coord.longitude >= -180.0 && coord.longitude <= 180.0 else {
            throw PacketCodecError.invalidCoordinateRange(latitude: coord.latitude, longitude: coord.longitude)
        }
        let meetupDate = Date(timeIntervalSince1970: TimeInterval(meetupTsRaw))
        let createdDate = Date(timeIntervalSince1970: TimeInterval(createdTsRaw))
        let action = MeetingAction(rawValue: actionByte) ?? .propose
        let attendance = AttendanceStatus(rawValue: attendanceByte) ?? .attending
        
        return MeetingUpdatePayload(
            coordinate: coord,
            meetupTime: meetupDate,
            createdAt: createdDate,
            action: action,
            attendanceStatus: attendance,
            meetingPointId: mpId,
            senderInitials: initials,
            arrivalRadiusMeters: arrivalRadius,
            flags: flagsByte
        )
    }
}

/// Type 4: `0x06` — Delivery ACK Inner Payload
public struct ACKPayload: Equatable, Sendable {
    public var ackedSeqNumber: UInt32
    public var ackedSenderInitials: String // 3 uppercase characters
    public var ackTimestamp: Date
    public var ackStatus: ACKStatus
    public var receivedRssi: Int8
    public var originalEventId: UInt32
    public var responderInitials: String   // 3 uppercase characters
    
    public init(
        ackedSeqNumber: UInt32,
        ackedSenderInitials: String,
        ackTimestamp: Date = Date(),
        ackStatus: ACKStatus,
        receivedRssi: Int8,
        originalEventId: UInt32,
        responderInitials: String
    ) {
        self.ackedSeqNumber = ackedSeqNumber
        self.ackedSenderInitials = InitialsCodec.sanitize(ackedSenderInitials)
        self.ackTimestamp = ackTimestamp
        self.ackStatus = ackStatus
        self.receivedRssi = receivedRssi
        self.originalEventId = originalEventId
        self.responderInitials = InitialsCodec.sanitize(responderInitials)
    }
    
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.encryptedPayloadSize)
        var seq = ackedSeqNumber.bigEndian
        data.append(Data(bytes: &seq, count: 4))
        
        let ackedBytes = InitialsCodec.encode(ackedSenderInitials) ?? [0, 0]
        data.append(contentsOf: ackedBytes)
        
        var ts = UInt32(ackTimestamp.timeIntervalSince1970).bigEndian
        data.append(Data(bytes: &ts, count: 4))
        
        data.append(ackStatus.rawValue)
        
        var rssi = receivedRssi
        data.append(Data(bytes: &rssi, count: 1))
        
        var eventId = originalEventId.bigEndian
        data.append(Data(bytes: &eventId, count: 4))
        
        let respBytes = InitialsCodec.encode(responderInitials) ?? [0, 0]
        data.append(contentsOf: respBytes)
        
        // 12 bytes reserved padding (30 - 18 = 12)
        data.append(Data(repeating: 0, count: 12))
        return data
    }
    
    public static func deserialize(from data: Data) throws -> ACKPayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let seq = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let ackedBytes = [data[4], data[5]]
        let ackedInitials = InitialsCodec.decode(ackedBytes) ?? "UNK"
        
        let tsRaw = data.subdata(in: 6..<10).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let statusByte = data[10]
        let rssi = Int8(bitPattern: data[11])
        let eventId = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        let respBytes = [data[16], data[17]]
        let respInitials = InitialsCodec.decode(respBytes) ?? "UNK"
        
        let date = Date(timeIntervalSince1970: TimeInterval(tsRaw))
        let status = ACKStatus(rawValue: statusByte) ?? .deliveredToFriend
        
        return ACKPayload(
            ackedSeqNumber: seq,
            ackedSenderInitials: ackedInitials,
            ackTimestamp: date,
            ackStatus: status,
            receivedRssi: rssi,
            originalEventId: eventId,
            responderInitials: respInitials
        )
    }
}

/// Type 5: `0x04` — Route Request Inner Payload (Phase 2)
public struct RouteReqPayload: Equatable, Sendable {
    public var originatorInitials: String
    public var targetInitials: String
    public var discoveryNonce: UInt32
    public var routeCost: UInt8
    
    public init(
        originatorInitials: String,
        targetInitials: String,
        discoveryNonce: UInt32 = UInt32.random(in: 1...UInt32.max),
        routeCost: UInt8 = 0
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
    
    public static func deserialize(from data: Data) throws -> RouteReqPayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let origBytes = [data[0], data[1]]
        let orig = InitialsCodec.decode(origBytes) ?? "UNK"
        
        let targetBytes = [data[2], data[3]]
        let target = InitialsCodec.decode(targetBytes) ?? "UNK"
        
        let nonce = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let cost = data[8]
        return RouteReqPayload(originatorInitials: orig, targetInitials: target, discoveryNonce: nonce, routeCost: cost)
    }
}

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

// MARK: - Type 7: 0x07 — Group Chat Message Inner Payload (Phase 3)

/// Type 7: `0x07` — Group Chat Message Inner Payload (Phase 3)
///
/// Encrypted 30-Byte Payload Layout:
/// - Bytes 0..1: senderInitials (2B Base-27 compressed via InitialsCodec)
/// - Bytes 2..5: timestamp (4B Unix epoch seconds big-endian)
/// - Byte 6: textLength (1B, exact UTF-8 byte count: 0...20)
/// - Bytes 7..26: textContent (20B UTF-8 direct bytes, zero-padded for unused bytes)
/// - Bytes 27..29: reserved (3B zero padding: 0x000000)
public struct ChatMessagePayload: Equatable, Sendable {
    public static let maxTextBytes: Int = 20
    public static let reservedBytesCount: Int = 3
    
    // MARK: - Festival Preset Quick-Tap Chips (Independent Status Transmission)
    public static let presetBeerLine = "Beer line"
    public static let presetAtMainStage = "At Main Stage"
    public static let presetRestroom = "Restroom"
    public static let presetWhereAreYou = "Where are you?"
    public static let presetOnMyWay = "On my way"
    public static let presetLost = "Lost"
    
    public static let standardPresets: [String] = [
        presetBeerLine,
        presetAtMainStage,
        presetRestroom,
        presetWhereAreYou,
        presetOnMyWay,
        presetLost
    ]
    
    public var senderInitials: String // 1..3 uppercase characters A-Z
    public var timestamp: Date
    public var text: String           // Capped at 20 UTF-8 bytes
    
    public init(senderInitials: String, timestamp: Date = Date(), text: String) {
        self.senderInitials = InitialsCodec.sanitize(senderInitials)
        self.timestamp = timestamp
        self.text = text
    }
    
    /// Checks whether the text length does not exceed the 20-byte wire allocation.
    public var isTextLengthValid: Bool {
        text.utf8.count <= Self.maxTextBytes
    }
    
    /// Serializes the chat payload to exactly 30 bytes.
    /// Throws PacketCodecError.invalidTextLength if text exceeds 20 UTF-8 bytes.
    public func serialize() throws -> Data {
        guard isTextLengthValid else {
            throw PacketCodecError.invalidTextLength(text.utf8.count)
        }
        return serializeUnchecked()
    }
    
    /// Serializes without throwing, clamping text to at most 20 UTF-8 bytes if needed.
    public func serializeUnchecked() -> Data {
        var data = Data(capacity: PacketConstants.encryptedPayloadSize)
        
        // Bytes 0..1: senderInitials (2B Base-27)
        let initialBytes = InitialsCodec.encode(senderInitials) ?? [0, 0]
        data.append(contentsOf: initialBytes)
        
        // Bytes 2..5: timestamp (4B Unix epoch seconds)
        var ts = UInt32(timestamp.timeIntervalSince1970).bigEndian
        data.append(Data(bytes: &ts, count: 4))
        
        // Byte 6: textLength (1B, 0..20)
        let rawUtf8 = Array(text.utf8.prefix(Self.maxTextBytes))
        data.append(UInt8(rawUtf8.count))
        
        // Bytes 7..26: textContent (20B UTF-8, zero-padded)
        data.append(contentsOf: rawUtf8)
        if rawUtf8.count < Self.maxTextBytes {
            data.append(Data(repeating: 0, count: Self.maxTextBytes - rawUtf8.count))
        }
        
        // Bytes 27..29: reserved (3B padding: 0x000000)
        data.append(Data(repeating: 0, count: Self.reservedBytesCount))
        
        return data
    }
    
    /// Deserializes a 30-byte payload into ChatMessagePayload.
    /// Validates buffer size, text length (<= 20 bytes), and UTF-8 text encoding.
    public static func deserialize(from data: Data) throws -> ChatMessagePayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        
        let start = data.startIndex
        let initialBytes = [data[start], data[start + 1]]
        let initials = InitialsCodec.decode(initialBytes) ?? "UNK"
        
        let tsRaw = data.subdata(in: (start + 2)..<(start + 6)).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        let date = Date(timeIntervalSince1970: TimeInterval(tsRaw))
        
        let rawLen = data[start + 6]
        guard rawLen <= UInt8(Self.maxTextBytes) else {
            throw PacketCodecError.invalidTextLength(Int(rawLen))
        }
        let len = Int(rawLen)
        
        let textBytes = data.subdata(in: (start + 7)..<(start + 7 + len))
        guard let text = String(data: textBytes, encoding: .utf8) else {
            throw PacketCodecError.invalidTextEncoding
        }
        
        return ChatMessagePayload(senderInitials: initials, timestamp: date, text: text)
    }
    
    /// Strict deserialization that also validates exact 30-byte size and that all reserved
    /// bytes (Bytes 27..29) and unused text padding bytes are zeroed.
    public static func deserializeStrict(from data: Data) throws -> ChatMessagePayload {
        guard data.count == PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.encryptedPayloadSize, actual: data.count)
        }
        guard hasValidReservedPadding(in: data) else {
            throw PacketCodecError.payloadDeserializationFailed
        }
        return try deserialize(from: data)
    }
    
    /// Validates whether reserved bytes (Bytes 27..29) and unused text padding bytes are 0x00.
    public static func hasValidReservedPadding(in data: Data) -> Bool {
        guard data.count >= PacketConstants.encryptedPayloadSize else { return false }
        let start = data.startIndex
        let rawLen = Int(data[start + 6])
        guard rawLen <= Self.maxTextBytes else { return false }
        
        // Unused text content padding (from 7 + rawLen up to index 26)
        for i in (start + 7 + rawLen)..<(start + 27) {
            if data[i] != 0 { return false }
        }
        // 3 reserved bytes (27, 28, 29)
        for i in (start + 27)..<(start + 30) {
            if data[i] != 0 { return false }
        }
        return true
    }
    
    /// Helper to clamp arbitrary input text to the largest valid UTF-8 boundary <= 20 bytes.
    public static func clampTo20Bytes(_ input: String) -> String {
        var accumulated = ""
        for char in input {
            let candidate = accumulated + String(char)
            if candidate.utf8.count <= maxTextBytes {
                accumulated = candidate
            } else {
                break
            }
        }
        return accumulated
    }
}

// MARK: - UWB Action & Token Exchange Payload

public enum UWBAction: UInt8, CaseIterable, Sendable {
    case tokenRequest  = 0x01
    case tokenResponse = 0x02
    case stopRanging   = 0x03
}

/// 30-byte fixed-size encrypted payload for exchanging serialized Apple Ultra-Wideband NIDiscoveryToken fragments.
public struct UWBTokenExchangePayload: Equatable, Sendable {
    public static let payloadSize: Int = 30
    public static let maxFragmentDataBytes: Int = 25
    
    public var action: UWBAction
    public var sequenceId: UInt8
    public var fragmentIndex: UInt8
    public var totalFragments: UInt8
    public var dataLength: UInt8
    public var fragmentData: Data // Up to 25 bytes
    
    public init(
        action: UWBAction,
        sequenceId: UInt8,
        fragmentIndex: UInt8,
        totalFragments: UInt8,
        fragmentData: Data = Data()
    ) {
        self.action = action
        self.sequenceId = sequenceId
        self.fragmentIndex = fragmentIndex
        self.totalFragments = totalFragments
        let len = min(Self.maxFragmentDataBytes, fragmentData.count)
        self.dataLength = UInt8(len)
        self.fragmentData = fragmentData.prefix(len)
    }
    
    /// Serializes to exactly 30 bytes.
    public func serialize() -> Data {
        var data = Data(capacity: Self.payloadSize)
        data.append(action.rawValue)
        data.append(sequenceId)
        data.append(fragmentIndex)
        data.append(totalFragments)
        data.append(dataLength)
        data.append(fragmentData)
        
        let paddingNeeded = Self.payloadSize - data.count
        if paddingNeeded > 0 {
            data.append(Data(repeating: 0, count: paddingNeeded))
        }
        return data
    }
    
    /// Deserializes from exactly 30 bytes.
    public static func deserialize(from data: Data) throws -> UWBTokenExchangePayload {
        guard data.count == Self.payloadSize else {
            throw PacketCodecError.invalidPacketSize(expected: Self.payloadSize, actual: data.count)
        }
        let start = data.startIndex
        guard let action = UWBAction(rawValue: data[start]) else {
            throw PacketCodecError.payloadDeserializationFailed
        }
        let sequenceId = data[start + 1]
        let fragmentIndex = data[start + 2]
        let totalFragments = data[start + 3]
        let dataLength = data[start + 4]
        
        guard Int(dataLength) <= Self.maxFragmentDataBytes else {
            throw PacketCodecError.payloadDeserializationFailed
        }
        
        let chunkEnd = start + 5 + Int(dataLength)
        let fragmentData = data.subdata(in: (start + 5)..<chunkEnd)
        
        return UWBTokenExchangePayload(
            action: action,
            sequenceId: sequenceId,
            fragmentIndex: fragmentIndex,
            totalFragments: totalFragments,
            fragmentData: fragmentData
        )
    }
}
