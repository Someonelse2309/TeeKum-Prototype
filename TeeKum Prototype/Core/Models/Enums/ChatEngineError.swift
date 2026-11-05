//
//  ChatEngineError.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import Foundation

nonisolated public enum ChatEngineError: Error, LocalizedError, Equatable, Sendable {
    case invalidTextLength(Int)
    case cooldownActive(remainingSeconds: Double)
    case batteryThrottled(batteryLevel: Float)
    case survivalModeActive
    case noActiveSession
    case queueFull(String)
    case serializationFailed
    case encryptionFailed(String)
    case decryptionFailed(String)
    case duplicateMessage(UInt32)
    case sessionTerminated
    
    public var errorDescription: String? {
        switch self {
        case .invalidTextLength(let count):
            return "Message length is invalid (\(count) bytes). Must be between 1 and 20 UTF-8 bytes."
        case .cooldownActive(let remaining):
            return String(format: "Chat cooldown active. Please wait %.1f seconds.", remaining)
        case .batteryThrottled(let level):
            return String(format: "Chat disabled below 20%% battery (current: %.0f%%). Emergency SOS remains active.", level * 100)
        case .survivalModeActive:
            return "Chat disabled in Festival Survival Mode (<20% battery). Emergency SOS remains active."
        case .noActiveSession:
            return "Cannot send chat message without an active group session."
        case .queueFull(let msg):
            return "Chat queue is full: \(msg)"
        case .serializationFailed:
            return "Failed to serialize chat message payload."
        case .encryptionFailed(let msg):
            return "Failed to encrypt chat message: \(msg)"
        case .decryptionFailed(let msg):
            return "Failed to decrypt chat message: \(msg)"
        case .duplicateMessage(let seq):
            return "Duplicate chat message dropped (sequence \(seq))."
        case .sessionTerminated:
            return "Active session was terminated."
        }
    }
}
