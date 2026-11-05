//
//  PacketCodecError.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

public enum PacketCodecError: Error, LocalizedError, Equatable, Sendable {
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
