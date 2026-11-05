//
//  MeetingUpdatePayload.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

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
