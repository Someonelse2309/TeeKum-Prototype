//
//  ChatMessagePayload.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import Foundation

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
