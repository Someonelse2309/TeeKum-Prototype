//
//  SOSPayload.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

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
