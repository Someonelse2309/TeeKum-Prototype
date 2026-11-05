//
//  ACKPayload.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

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
