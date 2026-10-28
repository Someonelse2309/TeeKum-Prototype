//
//  SessionStorageProtocol.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

public enum SessionStorageError: Error, LocalizedError {
    case databaseOpenFailed(String)
    case statementExecutionFailed(String)
    case tableCreationFailed(String)
    case recordNotFound
    
    public var errorDescription: String? {
        switch self {
        case let .databaseOpenFailed(msg):
            return "Failed to open SQLite database: \(msg)"
        case let .statementExecutionFailed(msg):
            return "SQLite execution failed: \(msg)"
        case let .tableCreationFailed(msg):
            return "Failed to initialize session tables: \(msg)"
        case .recordNotFound:
            return "Record not found in ephemeral storage."
        }
    }
}

/// Authoritative contract for the ephemeral crash-recovery store (`libsqlite3`).
/// Used exclusively to restore active group state if iOS temporarily suspends the app
/// in the background while the user opens Camera/Instagram at a concert.
/// Completely wiped clean on session teardown.
public protocol SessionStorageProvider: Actor {
    /// Initializes ephemeral session tables in local Application Support sandbox.
    func openSession(sessionId: UInt32) throws
    
    /// Persists or updates the latest snapshot of a member.
    func saveMember(_ member: Member) throws
    
    /// Retrieves all active member snapshots for the current session upon app relaunch.
    func loadMembers() throws -> [Member]
    
    /// Checks whether an incoming packet sequence number has already been seen in the deduplication window.
    func isDuplicate(sessionId: UInt32, sequenceNumber: UInt32) throws -> Bool
    
    /// Records a packet sequence number into the deduplication store.
    func recordPacket(sessionId: UInt32, sequenceNumber: UInt32) throws
    
    /// Completely deletes all cached coordinates, member snapshots, and packet logs upon leaving the group.
    func purgeSession() throws
}
