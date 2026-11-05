//
//  CryptoServiceProtocol.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CryptoKit

public enum CryptoServiceError: Error, LocalizedError {
    case encryptionFailed(String)
    case authenticationFailed
    case keyGenerationFailed
    case keychainSaveFailed(OSStatus)
    case keychainLoadFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
    case keyNotFound
    case invalidKeySize(expected: Int, actual: Int)
    
    public var errorDescription: String? {
        switch self {
        case let .encryptionFailed(reason):
            return "Encryption failed: \(reason)"
        case .authenticationFailed:
            return "Tamper verification failed: authentication tag does not match Associated Authenticated Data."
        case .keyGenerationFailed:
            return "Failed to generate secure symmetric key."
        case let .keychainSaveFailed(status):
            return "Keychain item addition failed with OSStatus \(status)."
        case let .keychainLoadFailed(status):
            return "Keychain retrieval failed with OSStatus \(status)."
        case let .keychainDeleteFailed(status):
            return "Keychain deletion failed with OSStatus \(status)."
        case .keyNotFound:
            return "Requested symmetric key not found in iOS Keychain."
        case let .invalidKeySize(expected, actual):
            return "Invalid symmetric key size: expected \(expected) bytes, got \(actual) bytes."
        }
    }
}

/// Authoritative contract for cryptographic operations and secure key storage.
/// Implemented as a Swift `actor` to safeguard key material in memory.
public protocol CryptoServiceProvider: Actor {
    /// Active replay and deduplication protection filter.
    var replayFilter: ReplayProtectionFilter { get }
    
    /// Seals 30 bytes of private inner payload using authenticated symmetric encryption,
    /// binding the 10-byte cleartext envelope as Associated Authenticated Data (AAD).
    func seal(
        payload: Data,
        envelope: CleartextEnvelope,
        using key: SymmetricKey
    ) throws -> (ciphertext: Data, authTag: Data)
    
    /// Seals an inner payload directly to a 56-byte binary datagram ready for radio transmission.
    func sealToWireBytes(
        payload: Data,
        envelope: CleartextEnvelope,
        using key: SymmetricKey
    ) throws -> Data
    
    /// Verifies the 16-byte Poly1305 / AES-GCM tag against the 10-byte envelope AAD and decrypts the 30-byte payload.
    /// Throws `CryptoServiceError.authenticationFailed` if tampered by a third party.
    func open(
        ciphertext: Data,
        envelope: CleartextEnvelope,
        authTag: Data,
        using key: SymmetricKey
    ) throws -> Data
    
    /// Generates a cryptographically secure 256-bit symmetric key.
    func generateSymmetricKey() -> SymmetricKey
    
    /// Persists the symmetric session key into the iOS Keychain backed by the Secure Enclave.
    func storeKeyInKeychain(_ key: SymmetricKey, forSessionId sessionId: UInt16) throws
    
    /// Reads the symmetric session key from the iOS Keychain.
    func loadKeyFromKeychain(forSessionId sessionId: UInt16) throws -> SymmetricKey?
    
    /// Permanently purges the session key from the iOS Keychain upon leaving or teardown.
    func purgeKeyFromKeychain(forSessionId sessionId: UInt16) throws
}
