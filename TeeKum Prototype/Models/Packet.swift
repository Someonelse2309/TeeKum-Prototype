//
//  Packet.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

// MARK: - Constants

public enum PacketConstants {
    public static let wirePacketSize: Int = 56
    public static let cleartextEnvelopeSize: Int = 10
    public static let encryptedPayloadSize: Int = 30
    public static let authTagSize: Int = 16
    public static let nonceSize: Int = 12
    
    public static let protocolVersion: UInt8 = 0x01
    public static let defaultHopLimit: UInt8 = 8
    public static let maxHopLimit: UInt8 = 15
    
    /// 3-byte protocol domain tag used in nonce construction: 'T', 'K', 'M'
    public static let protocolDomainTag: [UInt8] = [0x54, 0x4B, 0x4D]
}

// MARK: - Packet Type

public enum PacketType: UInt8, CaseIterable, Sendable {
    case locationPing  = 0x01
    case sos           = 0x02
    case meetingUpdate = 0x03
    case routeReq      = 0x04
    case routeResp     = 0x05
    case ack           = 0x06
}

// MARK: - Emergency & ACK Enums

public enum SOSType: UInt8, CaseIterable, Sendable {
    case general   = 0x00
    case medical   = 0x01
    case separated = 0x02
    case security  = 0x03
    
    public var title: String {
        switch self {
        case .general:   return "General Emergency"
        case .medical:   return "Medical Assistance"
        case .separated: return "Lost / Separated"
        case .security:  return "Security Concern"
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
        }
    }
}

// MARK: - Cleartext Envelope (10 Bytes)

public struct CleartextEnvelope: Equatable, Sendable {
    public var version: UInt8
    public var type: PacketType
    public var hopLimit: UInt8
    public var hopCount: UInt8
    public var sessionId: UInt32
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
        sessionId: UInt32,
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
    
    /// Constructs a partitioned sequence number combining an 8-bit member slot
    /// with a 24-bit monotonic packet counter.
    public static func makeSequenceNumber(memberSlot: UInt8, counter: UInt32) -> UInt32 {
        (UInt32(memberSlot) << 24) | (counter & 0x00FFFFFF)
    }
    
    /// Extracts the 8-bit member slot from a 32-bit partitioned sequence number.
    public static func memberSlot(from sequenceNumber: UInt32) -> UInt8 {
        UInt8((sequenceNumber >> 24) & 0xFF)
    }
    
    /// Extracts the 24-bit monotonic counter from a 32-bit partitioned sequence number.
    public static func counter(from sequenceNumber: UInt32) -> UInt32 {
        sequenceNumber & 0x00FFFFFF
    }
    
    // MARK: - Serialization
    
    /// Serializes envelope to exactly 10 big-endian bytes.
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.cleartextEnvelopeSize)
        
        // Byte 0: version (high 4 bits) | type (low 4 bits)
        let byte0 = ((version & 0x0F) << 4) | (type.rawValue & 0x0F)
        data.append(byte0)
        
        // Byte 1: hopLimit (high 4 bits) | hopCount (low 4 bits)
        let byte1 = ((hopLimit & 0x0F) << 4) | (hopCount & 0x0F)
        data.append(byte1)
        
        // Bytes 2..5: sessionId (32-bit big-endian)
        var sidBE = sessionId.bigEndian
        data.append(Data(bytes: &sidBE, count: 4))
        
        // Bytes 6..9: sequenceNumber (32-bit big-endian)
        var seqBE = sequenceNumber.bigEndian
        data.append(Data(bytes: &seqBE, count: 4))
        
        return data
    }
    
    /// Deserializes 10 big-endian bytes into a `CleartextEnvelope` with rigorous field validation.
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
        
        let byte1 = data[data.startIndex + 1]
        let hopLimit = (byte1 >> 4) & 0x0F
        guard hopLimit >= 1 else {
            throw PacketCodecError.invalidHopLimit(hopLimit)
        }
        
        let hopCount = byte1 & 0x0F
        guard hopCount <= hopLimit else {
            throw PacketCodecError.hopCountExceededLimit(count: hopCount, limit: hopLimit)
        }
        
        let sid = data.subdata(in: (data.startIndex + 2)..<(data.startIndex + 6)).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        
        let seq = data.subdata(in: (data.startIndex + 6)..<(data.startIndex + 10)).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        
        return CleartextEnvelope(
            version: version,
            type: type,
            hopLimit: hopLimit,
            hopCount: hopCount,
            sessionId: sid,
            sequenceNumber: seq
        )
    }
    
    // MARK: - Cryptographic Inputs
    
    /// Constructs Associated Authenticated Data (AAD) for AEAD sealing and verification.
    /// Byte 1 has mutable `hopCount` masked to 0x00, ensuring intermediate relays can
    /// increment `hopCount` without breaking the authentication tag.
    public func authenticatedAssociatedData() -> Data {
        var aad = Data(capacity: PacketConstants.cleartextEnvelopeSize)
        
        // Byte 0: version (high 4 bits) | type (low 4 bits)
        let byte0 = ((version & 0x0F) << 4) | (type.rawValue & 0x0F)
        aad.append(byte0)
        
        // Byte 1: hopLimit authenticated in high 4 bits; hopCount masked to 0x00 in low 4 bits
        let maskedByte1 = (hopLimit & 0x0F) << 4
        aad.append(maskedByte1)
        
        // Bytes 2..5: sessionId (32-bit big-endian)
        var sidBE = sessionId.bigEndian
        aad.append(Data(bytes: &sidBE, count: 4))
        
        // Bytes 6..9: sequenceNumber (32-bit big-endian)
        var seqBE = sequenceNumber.bigEndian
        aad.append(Data(bytes: &seqBE, count: 4))
        
        return aad
    }
    
    /// Constructs the deterministic 12-byte (96-bit) AEAD Nonce:
    /// - Bytes 0..3: sessionId (big-endian)
    /// - Bytes 4..7: sequenceNumber (big-endian)
    /// - Byte 8: versionAndType (Byte 0)
    /// - Bytes 9..11: Protocol Domain Tag "TKM" ([0x54, 0x4B, 0x4D])
    public func constructNonce() -> Data {
        var nonceData = Data(capacity: PacketConstants.nonceSize)
        
        var sidBE = sessionId.bigEndian
        nonceData.append(Data(bytes: &sidBE, count: 4))
        
        var seqBE = sequenceNumber.bigEndian
        nonceData.append(Data(bytes: &seqBE, count: 4))
        
        let byte0 = ((version & 0x0F) << 4) | (type.rawValue & 0x0F)
        nonceData.append(byte0)
        
        nonceData.append(contentsOf: PacketConstants.protocolDomainTag)
        return nonceData
    }
}

// MARK: - 56-Byte Wire Packet

public struct RawWirePacket: Equatable, Sendable {
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

/// Type 1: `0x01` — Location Ping Inner Payload
public struct LocationPingPayload: Equatable, Sendable {
    public var coordinate: CLLocationCoordinate2D
    public var timestamp: Date
    public var accuracy: UInt8
    public var statusCode: StatusCode
    public var targetRefId: UInt32?
    public var senderId: UInt32
    public var batteryLevel: UInt8 // 0...100
    public var heading: UInt8      // 0...255 representing 0..<360 degrees
    
    public init(
        coordinate: CLLocationCoordinate2D,
        timestamp: Date = Date(),
        accuracy: UInt8,
        statusCode: StatusCode,
        targetRefId: UInt32? = nil,
        senderId: UInt32,
        batteryLevel: UInt8,
        heading: UInt8 = 0
    ) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.accuracy = accuracy
        self.statusCode = statusCode
        self.targetRefId = targetRefId
        self.senderId = senderId
        self.batteryLevel = min(batteryLevel, 100)
        self.heading = heading
    }
    
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.encryptedPayloadSize)
        let latRaw = Int32((coordinate.latitude * 1_000_000.0).rounded()).bigEndian
        let lonRaw = Int32((coordinate.longitude * 1_000_000.0).rounded()).bigEndian
        let tsRaw = UInt32(timestamp.timeIntervalSince1970).bigEndian
        
        var lat = latRaw; data.append(Data(bytes: &lat, count: 4))
        var lon = lonRaw; data.append(Data(bytes: &lon, count: 4))
        var ts = tsRaw; data.append(Data(bytes: &ts, count: 4))
        data.append(accuracy)
        data.append(statusCode.rawValue)
        
        var target = (targetRefId ?? 0).bigEndian
        data.append(Data(bytes: &target, count: 4))
        
        var sender = senderId.bigEndian
        data.append(Data(bytes: &sender, count: 4))
        
        data.append(min(batteryLevel, 100))
        data.append(heading)
        
        // 6 bytes reserved zero padding (30 - 24 = 6)
        data.append(Data(repeating: 0, count: 6))
        return data
    }
    
    public static func deserialize(from data: Data) throws -> LocationPingPayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let latRaw = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        let lonRaw = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        let tsRaw = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let accuracy = data[12]
        let statusByte = data[13]
        let targetRaw = data.subdata(in: 14..<18).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let sender = data.subdata(in: 18..<22).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let battery = data[22]
        let heading = data[23]
        
        let lat = Double(latRaw) / 1_000_000.0
        let lon = Double(lonRaw) / 1_000_000.0
        
        guard lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0 else {
            throw PacketCodecError.invalidCoordinateRange(latitude: lat, longitude: lon)
        }
        
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let date = Date(timeIntervalSince1970: TimeInterval(tsRaw))
        let status = StatusCode(rawValue: statusByte) ?? .available
        let target = targetRaw == 0 ? nil : targetRaw
        
        return LocationPingPayload(
            coordinate: coord,
            timestamp: date,
            accuracy: accuracy,
            statusCode: status,
            targetRefId: target,
            senderId: sender,
            batteryLevel: min(battery, 100),
            heading: heading
        )
    }
}

/// Type 2: `0x02` — SOS Emergency Inner Payload
public struct SOSPayload: Equatable, Sendable {
    public var coordinate: CLLocationCoordinate2D
    public var timestamp: Date
    public var accuracy: UInt8
    public var sosEventId: UInt32
    public var senderId: UInt32
    public var emergencyType: SOSType
    public var batteryLevel: UInt8
    
    public init(
        coordinate: CLLocationCoordinate2D,
        timestamp: Date = Date(),
        accuracy: UInt8,
        sosEventId: UInt32 = UInt32.random(in: 1...UInt32.max),
        senderId: UInt32,
        emergencyType: SOSType = .general,
        batteryLevel: UInt8
    ) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.accuracy = accuracy
        self.sosEventId = sosEventId
        self.senderId = senderId
        self.emergencyType = emergencyType
        self.batteryLevel = min(batteryLevel, 100)
    }
    
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.encryptedPayloadSize)
        let latRaw = Int32((coordinate.latitude * 1_000_000.0).rounded()).bigEndian
        let lonRaw = Int32((coordinate.longitude * 1_000_000.0).rounded()).bigEndian
        let tsRaw = UInt32(timestamp.timeIntervalSince1970).bigEndian
        
        var lat = latRaw; data.append(Data(bytes: &lat, count: 4))
        var lon = lonRaw; data.append(Data(bytes: &lon, count: 4))
        var ts = tsRaw; data.append(Data(bytes: &ts, count: 4))
        data.append(accuracy)
        data.append(StatusCode.sos.rawValue)
        
        var eventId = sosEventId.bigEndian
        data.append(Data(bytes: &eventId, count: 4))
        
        var sender = senderId.bigEndian
        data.append(Data(bytes: &sender, count: 4))
        
        data.append(emergencyType.rawValue)
        data.append(min(batteryLevel, 100))
        
        // 6 bytes reserved padding
        data.append(Data(repeating: 0, count: 6))
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
        let sender = data.subdata(in: 18..<22).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let emergencyByte = data[22]
        let battery = data[23]
        
        let lat = Double(latRaw) / 1_000_000.0
        let lon = Double(lonRaw) / 1_000_000.0
        
        guard lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0 else {
            throw PacketCodecError.invalidCoordinateRange(latitude: lat, longitude: lon)
        }
        
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let date = Date(timeIntervalSince1970: TimeInterval(tsRaw))
        let emergency = SOSType(rawValue: emergencyByte) ?? .general
        
        return SOSPayload(
            coordinate: coord,
            timestamp: date,
            accuracy: accuracy,
            sosEventId: eventId,
            senderId: sender,
            emergencyType: emergency,
            batteryLevel: min(battery, 100)
        )
    }
}

/// Type 3: `0x03` — Meeting Update Inner Payload
public struct MeetingUpdatePayload: Equatable, Sendable {
    public var coordinate: CLLocationCoordinate2D
    public var meetupTime: Date
    public var action: MeetingAction
    public var attendanceStatus: AttendanceStatus
    public var meetingPointId: UInt32
    public var senderId: UInt32
    public var landmarkId: UInt32?
    
    public init(
        coordinate: CLLocationCoordinate2D,
        meetupTime: Date,
        action: MeetingAction,
        attendanceStatus: AttendanceStatus,
        meetingPointId: UInt32,
        senderId: UInt32,
        landmarkId: UInt32? = nil
    ) {
        self.coordinate = coordinate
        self.meetupTime = meetupTime
        self.action = action
        self.attendanceStatus = attendanceStatus
        self.meetingPointId = meetingPointId
        self.senderId = senderId
        self.landmarkId = landmarkId
    }
    
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.encryptedPayloadSize)
        let latRaw = Int32((coordinate.latitude * 1_000_000.0).rounded()).bigEndian
        let lonRaw = Int32((coordinate.longitude * 1_000_000.0).rounded()).bigEndian
        let tsRaw = UInt32(meetupTime.timeIntervalSince1970).bigEndian
        
        var lat = latRaw; data.append(Data(bytes: &lat, count: 4))
        var lon = lonRaw; data.append(Data(bytes: &lon, count: 4))
        var ts = tsRaw; data.append(Data(bytes: &ts, count: 4))
        data.append(action.rawValue)
        data.append(attendanceStatus.rawValue)
        
        var mpId = meetingPointId.bigEndian
        data.append(Data(bytes: &mpId, count: 4))
        
        var sender = senderId.bigEndian
        data.append(Data(bytes: &sender, count: 4))
        
        var landmark = (landmarkId ?? 0).bigEndian
        data.append(Data(bytes: &landmark, count: 4))
        
        // 4 bytes reserved padding
        data.append(Data(repeating: 0, count: 4))
        return data
    }
    
    public static func deserialize(from data: Data) throws -> MeetingUpdatePayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let latRaw = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        let lonRaw = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        let tsRaw = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let actionByte = data[12]
        let attendanceByte = data[13]
        let mpId = data.subdata(in: 14..<18).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let sender = data.subdata(in: 18..<22).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let landmarkRaw = data.subdata(in: 22..<26).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        let lat = Double(latRaw) / 1_000_000.0
        let lon = Double(lonRaw) / 1_000_000.0
        
        guard lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0 else {
            throw PacketCodecError.invalidCoordinateRange(latitude: lat, longitude: lon)
        }
        
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let date = Date(timeIntervalSince1970: TimeInterval(tsRaw))
        let action = MeetingAction(rawValue: actionByte) ?? .propose
        let attendance = AttendanceStatus(rawValue: attendanceByte) ?? .attending
        let landmark = landmarkRaw == 0 ? nil : landmarkRaw
        
        return MeetingUpdatePayload(
            coordinate: coord,
            meetupTime: date,
            action: action,
            attendanceStatus: attendance,
            meetingPointId: mpId,
            senderId: sender,
            landmarkId: landmark
        )
    }
}

/// Type 4: `0x06` — Delivery ACK Inner Payload
public struct ACKPayload: Equatable, Sendable {
    public var ackedSeqNumber: UInt32
    public var ackedSenderId: UInt32
    public var ackTimestamp: Date
    public var ackStatus: ACKStatus
    public var receivedRssi: Int8
    public var originalEventId: UInt32
    public var responderId: UInt32
    
    public init(
        ackedSeqNumber: UInt32,
        ackedSenderId: UInt32,
        ackTimestamp: Date = Date(),
        ackStatus: ACKStatus,
        receivedRssi: Int8,
        originalEventId: UInt32,
        responderId: UInt32
    ) {
        self.ackedSeqNumber = ackedSeqNumber
        self.ackedSenderId = ackedSenderId
        self.ackTimestamp = ackTimestamp
        self.ackStatus = ackStatus
        self.receivedRssi = receivedRssi
        self.originalEventId = originalEventId
        self.responderId = responderId
    }
    
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.encryptedPayloadSize)
        var seq = ackedSeqNumber.bigEndian
        data.append(Data(bytes: &seq, count: 4))
        
        var sender = ackedSenderId.bigEndian
        data.append(Data(bytes: &sender, count: 4))
        
        var ts = UInt32(ackTimestamp.timeIntervalSince1970).bigEndian
        data.append(Data(bytes: &ts, count: 4))
        
        data.append(ackStatus.rawValue)
        
        var rssi = receivedRssi
        data.append(Data(bytes: &rssi, count: 1))
        
        var eventId = originalEventId.bigEndian
        data.append(Data(bytes: &eventId, count: 4))
        
        var resp = responderId.bigEndian
        data.append(Data(bytes: &resp, count: 4))
        
        // 8 bytes reserved padding
        data.append(Data(repeating: 0, count: 8))
        return data
    }
    
    public static func deserialize(from data: Data) throws -> ACKPayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let seq = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let sender = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let tsRaw = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let statusByte = data[12]
        let rssi = Int8(bitPattern: data[13])
        let eventId = data.subdata(in: 14..<18).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let resp = data.subdata(in: 18..<22).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        let date = Date(timeIntervalSince1970: TimeInterval(tsRaw))
        let status = ACKStatus(rawValue: statusByte) ?? .deliveredToFriend
        
        return ACKPayload(
            ackedSeqNumber: seq,
            ackedSenderId: sender,
            ackTimestamp: date,
            ackStatus: status,
            receivedRssi: rssi,
            originalEventId: eventId,
            responderId: resp
        )
    }
}

/// Type 5: `0x04` — Route Request Inner Payload (Phase 2)
public struct RouteReqPayload: Equatable, Sendable {
    public var originatorId: UInt32
    public var targetMemberId: UInt32
    public var discoveryNonce: UInt32
    public var routeCost: UInt8
    
    public init(
        originatorId: UInt32,
        targetMemberId: UInt32,
        discoveryNonce: UInt32 = UInt32.random(in: 1...UInt32.max),
        routeCost: UInt8 = 0
    ) {
        self.originatorId = originatorId
        self.targetMemberId = targetMemberId
        self.discoveryNonce = discoveryNonce
        self.routeCost = routeCost
    }
    
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.encryptedPayloadSize)
        var orig = originatorId.bigEndian; data.append(Data(bytes: &orig, count: 4))
        var target = targetMemberId.bigEndian; data.append(Data(bytes: &target, count: 4))
        var nonce = discoveryNonce.bigEndian; data.append(Data(bytes: &nonce, count: 4))
        data.append(routeCost)
        // 17 bytes reserved (30 - 13 = 17)
        data.append(Data(repeating: 0, count: 17))
        return data
    }
    
    public static func deserialize(from data: Data) throws -> RouteReqPayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let orig = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let target = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let nonce = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let cost = data[12]
        return RouteReqPayload(originatorId: orig, targetMemberId: target, discoveryNonce: nonce, routeCost: cost)
    }
}

/// Type 6: `0x05` — Route Response Inner Payload (Phase 2)
public struct RouteRespPayload: Equatable, Sendable {
    public var originatorId: UInt32
    public var targetMemberId: UInt32
    public var discoveryNonce: UInt32
    public var routeCost: UInt8
    
    public init(
        originatorId: UInt32,
        targetMemberId: UInt32,
        discoveryNonce: UInt32,
        routeCost: UInt8
    ) {
        self.originatorId = originatorId
        self.targetMemberId = targetMemberId
        self.discoveryNonce = discoveryNonce
        self.routeCost = routeCost
    }
    
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.encryptedPayloadSize)
        var orig = originatorId.bigEndian; data.append(Data(bytes: &orig, count: 4))
        var target = targetMemberId.bigEndian; data.append(Data(bytes: &target, count: 4))
        var nonce = discoveryNonce.bigEndian; data.append(Data(bytes: &nonce, count: 4))
        data.append(routeCost)
        // 17 bytes reserved (30 - 13 = 17)
        data.append(Data(repeating: 0, count: 17))
        return data
    }
    
    public static func deserialize(from data: Data) throws -> RouteRespPayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let orig = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        let target = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let nonce = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let cost = data[12]
        return RouteRespPayload(originatorId: UInt32(orig), targetMemberId: target, discoveryNonce: nonce, routeCost: cost)
    }
}
