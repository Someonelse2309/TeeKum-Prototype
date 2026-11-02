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
    public static let wirePacketSize: Int = 66
    public static let cleartextEnvelopeSize: Int = 8
    public static let encryptedPayloadSize: Int = 30
    public static let authTagSize: Int = 16
    public static let nonceSize: Int = 12
    /// Nonce followed by ciphertext; the authentication tag remains separate.
    public static let sealedPayloadSize: Int = nonceSize + encryptedPayloadSize
    
    public static let protocolVersion: UInt8 = 0x03
    public static let defaultHopLimit: UInt8 = 8
    public static let maxHopLimit: UInt8 = 15
    public static let meetingPointHopLimit: UInt8 = 15
    public static let sosHopLimit: UInt8 = 15
    

}

// MARK: - Packet Type

nonisolated public enum PacketType: UInt8, CaseIterable, Sendable {
    case locationPing  = 0x01
    case sos           = 0x02
    case meetingUpdate = 0x03
    case routeReq      = 0x04
    case routeResp     = 0x05
    case ack           = 0x06
}

// MARK: - Emergency & ACK Enums

nonisolated public enum SOSType: UInt8, CaseIterable, Sendable {
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

nonisolated public enum ACKStatus: UInt8, CaseIterable, Sendable {
    case deliveredToFriend = 0x01
    case relayedByMeshHop  = 0x02
}

// MARK: - Errors

nonisolated public enum PacketCodecError: Error, LocalizedError, Equatable {
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
        }
    }
}

// MARK: - Cleartext Envelope (8 Bytes)

nonisolated public struct CleartextEnvelope: Equatable, Sendable {
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
    
    // MARK: - Serialization (8 Bytes)
    
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.cleartextEnvelopeSize)
        
        // Byte 0: version (high 4 bits) | type (low 4 bits)
        let byte0 = ((version & 0x0F) << 4) | (type.rawValue & 0x0F)
        data.append(byte0)
        
        // Byte 1: hopLimit (high 4 bits) | hopCount (low 4 bits)
        let byte1 = ((hopLimit & 0x0F) << 4) | (hopCount & 0x0F)
        data.append(byte1)
        
        // Bytes 2..3: sessionId (16-bit big-endian)
        var sidBE = sessionId.bigEndian
        data.append(Data(bytes: &sidBE, count: 2))
        
        // Bytes 4..7: sequenceNumber (32-bit big-endian)
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
        
        let byte1 = data[data.startIndex + 1]
        let hopLimit = (byte1 >> 4) & 0x0F
        guard hopLimit >= 1 else {
            throw PacketCodecError.invalidHopLimit(hopLimit)
        }
        
        let hopCount = byte1 & 0x0F
        guard hopCount <= hopLimit else {
            throw PacketCodecError.hopCountExceededLimit(count: hopCount, limit: hopLimit)
        }
        
        let sid = data.subdata(in: (data.startIndex + 2)..<(data.startIndex + 4)).withUnsafeBytes {
            $0.loadUnaligned(as: UInt16.self).bigEndian
        }
        
        let seq = data.subdata(in: (data.startIndex + 4)..<(data.startIndex + 8)).withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).bigEndian
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
    
    // MARK: - Cryptographic Inputs (8 Bytes AAD)
    
    public func authenticatedAssociatedData() -> Data {
        var aad = Data(capacity: PacketConstants.cleartextEnvelopeSize)
        
        let byte0 = ((version & 0x0F) << 4) | (type.rawValue & 0x0F)
        aad.append(byte0)
        
        let maskedByte1 = (hopLimit & 0x0F) << 4
        aad.append(maskedByte1)
        
        var sidBE = sessionId.bigEndian
        aad.append(Data(bytes: &sidBE, count: 2))
        
        var seqBE = sequenceNumber.bigEndian
        aad.append(Data(bytes: &seqBE, count: 4))
        
        return aad
    }
    

}

// MARK: - 66-Byte Wire Packet

nonisolated public struct RawWirePacket: Equatable, Sendable {
    public var envelope: CleartextEnvelope
    /// The wire field contains the 12-byte nonce followed by 30 bytes of ciphertext.
    public var ciphertext: Data
    public var authTag: Data
    
    public init(envelope: CleartextEnvelope, ciphertext: Data, authTag: Data) {
        self.envelope = envelope
        self.ciphertext = ciphertext
        self.authTag = authTag
    }
    
    /// Combines envelope (8B), random nonce (12B), ciphertext (30B), and tag (16B).
    public func toWireData() throws -> Data {
        let envData = envelope.serialize()
        guard envData.count == PacketConstants.cleartextEnvelopeSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.cleartextEnvelopeSize, actual: envData.count)
        }
        guard ciphertext.count == PacketConstants.sealedPayloadSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.sealedPayloadSize, actual: ciphertext.count)
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
    
    /// Parses a 66-byte binary frame from the network.
    public static func fromWireData(_ data: Data) throws -> RawWirePacket {
        guard data.count == PacketConstants.wirePacketSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.wirePacketSize, actual: data.count)
        }
        
        let envData = data.subdata(in: 0..<8)
        let envelope = try CleartextEnvelope.deserialize(from: envData)
        let ciphertext = data.subdata(in: 8..<50)
        let authTag = data.subdata(in: 50..<66)
        
        return RawWirePacket(envelope: envelope, ciphertext: ciphertext, authTag: authTag)
    }
}

// MARK: - Decoded Inner Payloads (30 Bytes Each)

/// Type 1: `0x01` — Location Ping Inner Payload
nonisolated public struct LocationPingPayload: Equatable, Sendable {
    public var coordinate: CLLocationCoordinate2D
    public var timestamp: Date
    public var accuracy: UInt8
    public var statusCode: StatusCode
    public var targetRefId: UInt32?
    public var senderInitials: String // 3 uppercase characters A-Z
    public var batteryLevel: UInt8    // 0...100
    public var heading: UInt8         // 0...255 representing 0..<360 degrees
    
    public init(
        coordinate: CLLocationCoordinate2D,
        timestamp: Date = Date(),
        accuracy: UInt8,
        statusCode: StatusCode,
        targetRefId: UInt32? = nil,
        senderInitials: String,
        batteryLevel: UInt8,
        heading: UInt8 = 0
    ) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.accuracy = accuracy
        self.statusCode = statusCode
        self.targetRefId = targetRefId
        self.senderInitials = InitialsCodec.sanitize(senderInitials)
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
        
        let initialBytes = InitialsCodec.encode(senderInitials) ?? [0, 0]
        data.append(contentsOf: initialBytes)
        
        data.append(min(batteryLevel, 100))
        data.append(heading)
        
        // 8 bytes reserved zero padding (30 - 22 = 8)
        data.append(Data(repeating: 0, count: 8))
        return data
    }
    
    public static func deserialize(from data: Data) throws -> LocationPingPayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let latRaw = data.subdata(in: 0..<4).withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
        let lonRaw = data.subdata(in: 4..<8).withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
        let tsRaw = data.subdata(in: 8..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        let accuracy = data[12]
        let statusByte = data[13]
        let targetRaw = data.subdata(in: 14..<18).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        
        let initialBytes = [data[18], data[19]]
        let initials = InitialsCodec.decode(initialBytes) ?? "UNK"
        
        let battery = data[20]
        let heading = data[21]
        
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
            senderInitials: initials,
            batteryLevel: min(battery, 100),
            heading: heading
        )
    }
}

/// Type 2: `0x02` — SOS Emergency Inner Payload
nonisolated public struct SOSPayload: Equatable, Sendable {
    public var coordinate: CLLocationCoordinate2D
    public var timestamp: Date
    public var accuracy: UInt8
    public var sosEventId: UInt32
    public var senderInitials: String // 3 uppercase characters
    public var emergencyType: SOSType
    public var sentAt: Date
    public var batteryLevel: UInt8
    
    public init(
        coordinate: CLLocationCoordinate2D,
        timestamp: Date = Date(),
        accuracy: UInt8,
        sosEventId: UInt32 = UInt32.random(in: 1...UInt32.max),
        senderInitials: String,
        emergencyType: SOSType = .general,
        batteryLevel: UInt8,
        sentAt: Date = .now
    ) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.accuracy = accuracy
        self.sosEventId = sosEventId
        self.senderInitials = InitialsCodec.sanitize(senderInitials)
        self.emergencyType = emergencyType
        self.batteryLevel = min(batteryLevel, 100)
        self.sentAt = sentAt
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
        
        let initialBytes = InitialsCodec.encode(senderInitials) ?? [0, 0]
        data.append(contentsOf: initialBytes)
        
        data.append(emergencyType.rawValue)
        data.append(min(batteryLevel, 100))
        
        // Separate transmission time from the GPS measurement's possibly old timestamp.
        var sent = UInt32(sentAt.timeIntervalSince1970).bigEndian
        data.append(Data(bytes: &sent, count: 4))
        data.append(Data(repeating: 0, count: 4))
        return data
    }
    
    public static func deserialize(from data: Data) throws -> SOSPayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let latRaw = data.subdata(in: 0..<4).withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
        let lonRaw = data.subdata(in: 4..<8).withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
        let tsRaw = data.subdata(in: 8..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        let accuracy = data[12]
        let eventId = data.subdata(in: 14..<18).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        
        let initialBytes = [data[18], data[19]]
        let initials = InitialsCodec.decode(initialBytes) ?? "UNK"
        
        let emergencyByte = data[20]
        let battery = data[21]
        
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
            senderInitials: initials,
            emergencyType: emergency,
            batteryLevel: min(battery, 100),
            sentAt: Date(timeIntervalSince1970: TimeInterval(data.subdata(in: 22..<26).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }))
        )
    }
}

/// Type 3: `0x03` — Meeting Update Inner Payload
nonisolated public struct MeetingUpdatePayload: Equatable, Sendable {
    public var coordinate: CLLocationCoordinate2D
    public var meetupTime: Date
    public var action: MeetingAction
    public var attendanceStatus: AttendanceStatus
    public var meetingPointId: UInt32
    public var senderInitials: String // 3 uppercase characters
    public var landmarkId: UInt32?
    public var customLabel: String?
    
    public init(
        coordinate: CLLocationCoordinate2D,
        meetupTime: Date,
        action: MeetingAction,
        attendanceStatus: AttendanceStatus,
        meetingPointId: UInt32,
        senderInitials: String,
        landmarkId: UInt32? = nil,
        customLabel: String? = nil
    ) {
        self.coordinate = coordinate
        self.meetupTime = meetupTime
        self.action = action
        self.attendanceStatus = attendanceStatus
        self.meetingPointId = meetingPointId
        self.senderInitials = InitialsCodec.sanitize(senderInitials)
        self.landmarkId = landmarkId
        self.customLabel = customLabel
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
        
        let initialBytes = InitialsCodec.encode(senderInitials) ?? [0, 0]
        data.append(contentsOf: initialBytes)
        
        var landmark = (landmarkId ?? 0).bigEndian
        data.append(Data(bytes: &landmark, count: 4))
        
        // 6 bytes reserved padding / custom label (30 - 24 = 6)
        if let custom = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            let labelData = custom.data(using: .utf8)?.prefix(6) ?? Data()
            data.append(labelData)
            if labelData.count < 6 {
                data.append(Data(repeating: 0, count: 6 - labelData.count))
            }
        } else {
            data.append(Data(repeating: 0, count: 6))
        }
        return data
    }
    
    public static func deserialize(from data: Data) throws -> MeetingUpdatePayload {
        guard data.count >= PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.bufferUnderflow
        }
        let latRaw = data.subdata(in: 0..<4).withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
        let lonRaw = data.subdata(in: 4..<8).withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
        let tsRaw = data.subdata(in: 8..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        let actionByte = data[12]
        let attendanceByte = data[13]
        let mpId = data.subdata(in: 14..<18).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        
        let initialBytes = [data[18], data[19]]
        let initials = InitialsCodec.decode(initialBytes) ?? "UNK"
        
        let landmarkRaw = data.subdata(in: 20..<24).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        
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
        
        var customLabel: String?
        if landmark == nil {
            let labelBytes = data.subdata(in: 24..<30)
            let trimmedBytes = labelBytes.prefix(while: { $0 != 0 })
            if !trimmedBytes.isEmpty, let str = String(data: trimmedBytes, encoding: .utf8) {
                customLabel = str
            }
        }
        
        return MeetingUpdatePayload(
            coordinate: coord,
            meetupTime: date,
            action: action,
            attendanceStatus: attendance,
            meetingPointId: mpId,
            senderInitials: initials,
            landmarkId: landmark,
            customLabel: customLabel
        )
    }
}

/// Type 4: `0x06` — Delivery ACK Inner Payload
nonisolated public struct ACKPayload: Equatable, Sendable {
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
        let seq = data.subdata(in: 0..<4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        let ackedBytes = [data[4], data[5]]
        let ackedInitials = InitialsCodec.decode(ackedBytes) ?? "UNK"
        
        let tsRaw = data.subdata(in: 6..<10).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        let statusByte = data[10]
        let rssi = Int8(bitPattern: data[11])
        let eventId = data.subdata(in: 12..<16).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        
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
nonisolated public struct RouteReqPayload: Equatable, Sendable {
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
        
        let nonce = data.subdata(in: 4..<8).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        let cost = data[8]
        return RouteReqPayload(originatorInitials: orig, targetInitials: target, discoveryNonce: nonce, routeCost: cost)
    }
}

/// Type 6: `0x05` — Route Response Inner Payload (Phase 2)
nonisolated public struct RouteRespPayload: Equatable, Sendable {
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
        
        let nonce = data.subdata(in: 4..<8).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        let cost = data[8]
        return RouteRespPayload(originatorInitials: orig, targetInitials: target, discoveryNonce: nonce, routeCost: cost)
    }
}
