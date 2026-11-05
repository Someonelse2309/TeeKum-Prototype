//
//  LocationPingPayload.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

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
