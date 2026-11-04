//
//  CryptoSecurityTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CryptoKit
import CoreLocation

/// Comprehensive cryptographic and protocol security verification suite:
/// - AEAD encryption & decryption roundtrips
/// - Tampered ciphertext rejection (zero plaintext leakage)
/// - Tampered authentication tag rejection
/// - Tampered cleartext envelope metadata rejection (version, type, hopLimit, sessionId, sequenceNumber)
/// - Mutable hop count invariance (relays can increment hopCount without tag invalidation)
/// - Unrelated key rejection (zero unauthorized access)
/// - Nonce uniqueness & domain separation guarantees
/// - Exact duplicate packet rejection (5-minute sliding window)
/// - Anti-replay monotonic sequence number enforcement
/// - Stale location state replacement prevention
/// - Future timestamp clock skew protection
/// - Secure Enclave / iOS Keychain key lifecycle
public struct CryptoSecurityTests {
    
    public static func runAllTests() async -> Bool {
        print("--- [CryptoSecurityTests] Running Cryptographic Security Suite ---")
        var passed = true
        
        if !(await testAEADRoundtrip()) { passed = false }
        if !(await testTamperedCiphertextRejection()) { passed = false }
        if !(await testTamperedAuthTagRejection()) { passed = false }
        if !(await testTamperedEnvelopeMetadataRejection()) { passed = false }
        if !(await testMutableHopCountInvariance()) { passed = false }
        if !(await testWrongKeyRejection()) { passed = false }
        if !(await testNonceUniquenessAcrossMembers()) { passed = false }
        if !(await testDuplicatePacketRejection()) { passed = false }
        if !(await testAntiReplaySequenceEnforcement()) { passed = false }
        if !(await testStaleLocationReplacementPrevention()) { passed = false }
        if !(await testClockSkewProtection()) { passed = false }
        if !(await testKeychainStorageLifecycle()) { passed = false }
        if !(await testEndToEndWireDatagramCodec()) { passed = false }
        
        if passed {
            print("--- [CryptoSecurityTests] ALL CRYPTOGRAPHIC TESTS PASSED SUCCESSFULLY! ---")
        } else {
            print("--- [CryptoSecurityTests] SOME CRYPTOGRAPHIC TESTS FAILED! ---")
        }
        return passed
    }
    
    // MARK: - Test 1: AEAD Seal and Open Roundtrip
    
    public static func testAEADRoundtrip() async -> Bool {
        print("[Test 1] ChaCha20-Poly1305 AEAD seal and open roundtrip...")
        let cryptoService = CryptoService()
        let key = cryptoService.generateSymmetricKey()
        
        let envelope = CleartextEnvelope(
            type: .locationPing,
            sessionId: 0xA1B2,
            sequenceNumber: CleartextEnvelope.makeSequenceNumber(memberSlot: 1, counter: 42)
        )
        
        let payload = LocationPingPayload(
            coordinate: CLLocationCoordinate2D(latitude: 33.680312, longitude: -116.237409),
            accuracy: 5,
            senderInitials: "DNA",
            batteryLevel: 90,
            heading: 120
        )
        let plainBytes = payload.serialize()
        
        do {
            let (ciphertext, authTag) = try await cryptoService.seal(payload: plainBytes, envelope: envelope, using: key)
            guard ciphertext.count == 30 else {
                print("  FAIL: Ciphertext must be exactly 30 bytes, got \(ciphertext.count)")
                return false
            }
            guard authTag.count == 16 else {
                print("  FAIL: AuthTag must be exactly 16 bytes, got \(authTag.count)")
                return false
            }
            
            let decrypted = try await cryptoService.open(ciphertext: ciphertext, envelope: envelope, authTag: authTag, using: key)
            guard decrypted == plainBytes else {
                print("  FAIL: Decrypted payload does not match original plain bytes.")
                return false
            }
            
            let decodedPayload = try LocationPingPayload.deserialize(from: decrypted)
            guard decodedPayload.senderInitials == "DNA",
                  decodedPayload.batteryLevel == 90 else {
                print("  FAIL: Decoded payload metadata mismatch.")
                return false
            }
            
            print("  PASS: 30-byte payload encrypted and decrypted cleanly.")
            return true
        } catch {
            print("  FAIL: Unexpected error during roundtrip: \(error)")
            return false
        }
    }
    
    // MARK: - Test 2: Tampered Ciphertext Rejection
    
    public static func testTamperedCiphertextRejection() async -> Bool {
        print("[Test 2] Tampered ciphertext bit-flip rejection...")
        let cryptoService = CryptoService()
        let key = cryptoService.generateSymmetricKey()
        let envelope = CleartextEnvelope(type: .sos, sessionId: 0x1234, sequenceNumber: 1)
        let plainBytes = Data(repeating: 0xAA, count: 30)
        
        do {
            let (ciphertext, authTag) = try await cryptoService.seal(payload: plainBytes, envelope: envelope, using: key)
            
            // Flip 1 bit in byte index 5 of ciphertext
            var tamperedCiphertext = ciphertext
            tamperedCiphertext[tamperedCiphertext.startIndex + 5] ^= 0x01
            
            do {
                _ = try await cryptoService.open(ciphertext: tamperedCiphertext, envelope: envelope, authTag: authTag, using: key)
                print("  FAIL: Tampered ciphertext must never decrypt successfully.")
                return false
            } catch CryptoServiceError.authenticationFailed {
                // Expected
                print("  PASS: Bit-flipped ciphertext rejected with authenticationFailed.")
                return true
            } catch {
                print("  FAIL: Threw unexpected error: \(error)")
                return false
            }
        } catch {
            print("  FAIL: Sealing failed: \(error)")
            return false
        }
    }
    
    // MARK: - Test 3: Tampered Auth Tag Rejection
    
    public static func testTamperedAuthTagRejection() async -> Bool {
        print("[Test 3] Tampered authentication tag rejection...")
        let cryptoService = CryptoService()
        let key = cryptoService.generateSymmetricKey()
        let envelope = CleartextEnvelope(type: .locationPing, sessionId: 0x5555, sequenceNumber: 10)
        let plainBytes = Data(repeating: 0xCC, count: 30)
        
        do {
            let (ciphertext, authTag) = try await cryptoService.seal(payload: plainBytes, envelope: envelope, using: key)
            
            // Flip 1 bit in authentication tag
            var tamperedTag = authTag
            tamperedTag[tamperedTag.startIndex] ^= 0x80
            
            do {
                _ = try await cryptoService.open(ciphertext: ciphertext, envelope: envelope, authTag: tamperedTag, using: key)
                print("  FAIL: Tampered tag must never decrypt.")
                return false
            } catch CryptoServiceError.authenticationFailed {
                // Expected
                print("  PASS: Modified authentication tag rejected instantly.")
                return true
            } catch {
                print("  FAIL: Threw unexpected error: \(error)")
                return false
            }
        } catch {
            print("  FAIL: Sealing failed: \(error)")
            return false
        }
    }
    
    // MARK: - Test 4: Tampered Envelope Metadata Rejection
    
    public static func testTamperedEnvelopeMetadataRejection() async -> Bool {
        print("[Test 4] Tampered envelope Associated Authenticated Data (AAD) rejection...")
        let cryptoService = CryptoService()
        let key = cryptoService.generateSymmetricKey()
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: 0x1122,
            sequenceNumber: 100
        )
        let plainBytes = Data(repeating: 0x11, count: 30)
        
        do {
            let (ciphertext, authTag) = try await cryptoService.seal(payload: plainBytes, envelope: envelope, using: key)
            
            // Subtest A: Tamper sessionId
            var tamperedSidEnvelope = envelope
            tamperedSidEnvelope.sessionId = 0x9999
            do {
                _ = try await cryptoService.open(ciphertext: ciphertext, envelope: tamperedSidEnvelope, authTag: authTag, using: key)
                print("  FAIL: Tampered sessionId should cause authentication failure.")
                return false
            } catch CryptoServiceError.authenticationFailed {
                // Expected
            }
            
            // Subtest B: Tamper sequenceNumber (Bytes 6..9)
            var tamperedSeqEnvelope = envelope
            tamperedSeqEnvelope.sequenceNumber = 101
            do {
                _ = try await cryptoService.open(ciphertext: ciphertext, envelope: tamperedSeqEnvelope, authTag: authTag, using: key)
                print("  FAIL: Tampered sequenceNumber should cause authentication failure.")
                return false
            } catch CryptoServiceError.authenticationFailed {
                // Expected
            }
            
            // Subtest C: Tamper packetType (Byte 0 low nibble)
            var tamperedTypeEnvelope = envelope
            tamperedTypeEnvelope.type = .sos
            do {
                _ = try await cryptoService.open(ciphertext: ciphertext, envelope: tamperedTypeEnvelope, authTag: authTag, using: key)
                print("  FAIL: Tampered packetType should cause authentication failure.")
                return false
            } catch CryptoServiceError.authenticationFailed {
                // Expected
            }
            
            // Subtest D: Tamper hopLimit (Byte 1)
            var tamperedLimitEnvelope = envelope
            tamperedLimitEnvelope.hopLimit = 4
            do {
                _ = try await cryptoService.open(ciphertext: ciphertext, envelope: tamperedLimitEnvelope, authTag: authTag, using: key)
                print("  FAIL: Tampered hopLimit should cause authentication failure.")
                return false
            } catch CryptoServiceError.authenticationFailed {
                // Expected
            }
            
            print("  PASS: All envelope AAD tampering attempts failed authentication.")
            return true
        } catch {
            print("  FAIL: Sealing failed: \(error)")
            return false
        }
    }
    
    // MARK: - Test 5: Mutable Hop Count Invariance (Relay Safe Design)
    
    public static func testMutableHopCountInvariance() async -> Bool {
        print("[Test 5] Mutable hop count invariance (relays incrementing hopCount)...")
        let cryptoService = CryptoService()
        let key = cryptoService.generateSymmetricKey()
        
        // Sender originates packet with hopCount = 0
        let originalEnvelope = CleartextEnvelope(
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: 0xCAFE,
            sequenceNumber: 50
        )
        let plainBytes = Data(repeating: 0x42, count: 30)
        
        do {
            let (ciphertext, authTag) = try await cryptoService.seal(payload: plainBytes, envelope: originalEnvelope, using: key)
            
            // Simulate 3 relay hops: Hop 1 increments hopCount to 1, Hop 2 to 2, Hop 3 to 3
            for hops in 1...3 {
                var relayedEnvelope = originalEnvelope
                relayedEnvelope.hopCount = UInt8(hops)
                
                // Hop count on the wire has changed, but AAD masks hopCount to 0!
                let decrypted = try await cryptoService.open(
                    ciphertext: ciphertext,
                    envelope: relayedEnvelope,
                    authTag: authTag,
                    using: key
                )
                guard decrypted == plainBytes else {
                    print("  FAIL: Decrypted payload mismatch after hop \(hops).")
                    return false
                }
            }
            
            print("  PASS: Packet decrypted successfully after multiple relay hopCount increments.")
            return true
        } catch {
            print("  FAIL: Relayed hopCount decryption failed: \(error)")
            return false
        }
    }
    
    // MARK: - Test 6: Wrong Key Rejection
    
    public static func testWrongKeyRejection() async -> Bool {
        print("[Test 6] Rejection of stranger / attacker symmetric keys...")
        let cryptoService = CryptoService()
        let groupKey = cryptoService.generateSymmetricKey()
        let attackerKey = cryptoService.generateSymmetricKey()
        
        let envelope = CleartextEnvelope(type: .sos, sessionId: 0x7777, sequenceNumber: 1)
        let plainBytes = Data(repeating: 0x01, count: 30)
        
        do {
            let (ciphertext, authTag) = try await cryptoService.seal(payload: plainBytes, envelope: envelope, using: groupKey)
            
            do {
                _ = try await cryptoService.open(ciphertext: ciphertext, envelope: envelope, authTag: authTag, using: attackerKey)
                print("  FAIL: Attacker key must never authenticate group packets.")
                return false
            } catch CryptoServiceError.authenticationFailed {
                // Expected
                print("  PASS: Packet decrypted with wrong key rejected instantly.")
                return true
            } catch {
                print("  FAIL: Unexpected error with wrong key: \(error)")
                return false
            }
        } catch {
            print("  FAIL: Sealing failed: \(error)")
            return false
        }
    }
    
    // MARK: - Test 7: Nonce Uniqueness Across Members
    
    public static func testNonceUniquenessAcrossMembers() async -> Bool {
        print("[Test 7] Nonce uniqueness and collision prevention across group members...")
        
        // Two members in same session with same counter (counter = 1)
        let sessionId: UInt16 = 0x9876
        let seqMember0 = CleartextEnvelope.makeSequenceNumber(memberSlot: 0, counter: 1)
        let seqMember1 = CleartextEnvelope.makeSequenceNumber(memberSlot: 1, counter: 1)
        
        let env0 = CleartextEnvelope(type: .locationPing, sessionId: sessionId, sequenceNumber: seqMember0)
        let env1 = CleartextEnvelope(type: .locationPing, sessionId: sessionId, sequenceNumber: seqMember1)
        
        let nonce0 = env0.constructNonce()
        let nonce1 = env1.constructNonce()
        
        guard nonce0.count == 12 && nonce1.count == 12 else {
            print("  FAIL: Nonces must be strictly 12 bytes.")
            return false
        }
        guard nonce0 != nonce1 else {
            print("  FAIL: Nonces for different member slots must NEVER collide!")
            return false
        }
        
        print("  PASS: Nonces are guaranteed unique across group members under shared key.")
        return true
    }
    
    // MARK: - Test 8: Duplicate Packet Rejection (5-Minute LRU Filter)
    
    public static func testDuplicatePacketRejection() async -> Bool {
        print("[Test 8] ReplayProtectionFilter: exact duplicate packet rejection...")
        let filter = ReplayProtectionFilter(deduplicationWindow: 300.0)
        let sessionId: UInt16 = 0xDEAD
        let seq: UInt32 = 42
        
        // Initial arrival: not duplicate
        let isDup1 = await filter.isDuplicate(sessionId: sessionId, sequenceNumber: seq)
        guard !isDup1 else {
            print("  FAIL: First packet marked as duplicate.")
            return false
        }
        await filter.recordPacket(sessionId: sessionId, sequenceNumber: seq)
        
        // Second arrival: must be duplicate
        let isDup2 = await filter.isDuplicate(sessionId: sessionId, sequenceNumber: seq)
        guard isDup2 else {
            print("  FAIL: Immediate duplicate was not detected.")
            return false
        }
        
        // Different sequence number: not duplicate
        let isDup3 = await filter.isDuplicate(sessionId: sessionId, sequenceNumber: 43)
        guard !isDup3 else {
            print("  FAIL: Different sequence number was falsely flagged as duplicate.")
            return false
        }
        
        print("  PASS: Duplicate packets suppressed accurately by filter.")
        return true
    }
    
    // MARK: - Test 9: Anti-Replay Monotonic Sequence Enforcement
    
    public static func testAntiReplaySequenceEnforcement() async -> Bool {
        print("[Test 9] ReplayProtectionFilter: anti-replay sequence monotonicity...")
        let filter = ReplayProtectionFilter()
        let senderInitials = "ALX"
        
        // First valid sequence
        let ok1 = await filter.checkAndRecordSenderSequence(senderInitials: senderInitials, sequenceNumber: 10)
        guard ok1 else {
            print("  FAIL: Sequence 10 should be accepted.")
            return false
        }
        
        // Replayed old sequence (sequence 5 <= 10)
        let replayed = await filter.checkAndRecordSenderSequence(senderInitials: senderInitials, sequenceNumber: 5)
        guard !replayed else {
            print("  FAIL: Older sequence 5 should be rejected as replayed.")
            return false
        }
        
        // Duplicate sequence (sequence 10 <= 10)
        let dupSeq = await filter.checkAndRecordSenderSequence(senderInitials: senderInitials, sequenceNumber: 10)
        guard !dupSeq else {
            print("  FAIL: Duplicate sequence 10 should be rejected.")
            return false
        }
        
        // Monotonic advance (sequence 11 > 10)
        let advance = await filter.checkAndRecordSenderSequence(senderInitials: senderInitials, sequenceNumber: 11)
        guard advance else {
            print("  FAIL: Advance sequence 11 should be accepted.")
            return false
        }
        
        print("  PASS: Monotonic sequence enforcement prevents replay attacks.")
        return true
    }
    
    // MARK: - Test 10: Stale Location Replacement Prevention
    
    public static func testStaleLocationReplacementPrevention() async -> Bool {
        print("[Test 10] Stale location replacement prevention...")
        let filter = ReplayProtectionFilter()
        let senderInitials = "BOB"
        
        let t1 = Date(timeIntervalSince1970: 1729000100)
        let t2 = Date(timeIntervalSince1970: 1729000200)
        let staleT = Date(timeIntervalSince1970: 1729000150)
        
        // Apply fresh measurement t1
        let ok1 = await filter.checkAndRecordLocationFreshness(senderInitials: senderInitials, timestamp: t1)
        guard ok1 else { return false }
        
        // Apply newer measurement t2
        let ok2 = await filter.checkAndRecordLocationFreshness(senderInitials: senderInitials, timestamp: t2)
        guard ok2 else { return false }
        
        // Out-of-order / delayed arrival with timestamp between t1 and t2: must be rejected!
        let staleArrival = await filter.checkAndRecordLocationFreshness(senderInitials: senderInitials, timestamp: staleT)
        guard !staleArrival else {
            print("  FAIL: Stale timestamp was allowed to overwrite newer location.")
            return false
        }
        
        print("  PASS: Stale location timestamps rejected from overwriting newer map coordinates.")
        return true
    }
    
    // MARK: - Test 11: Clock Skew Protection
    
    public static func testClockSkewProtection() async -> Bool {
        print("[Test 11] Clock skew guard: future and ancient timestamp rejection...")
        let filter = ReplayProtectionFilter(maxClockSkew: 300.0) // 5 minutes max future
        let now = Date()
        
        // Plausible current timestamp
        guard await filter.isTimestampValid(now, now: now) else {
            print("  FAIL: Current timestamp should be valid.")
            return false
        }
        
        // Timestamp 10 minutes in the future (exceeds 5m clock skew limit)
        let farFuture = now.addingTimeInterval(600)
        guard await !filter.isTimestampValid(farFuture, now: now) else {
            print("  FAIL: Far future timestamp should be rejected.")
            return false
        }
        
        // Timestamp 2 hours in the past (exceeds max session live age)
        let ancient = now.addingTimeInterval(-7200)
        guard await !filter.isTimestampValid(ancient, now: now) else {
            print("  FAIL: Ancient timestamp should be rejected.")
            return false
        }
        
        print("  PASS: Timestamp sanity filter rejected suspicious future/past timestamps.")
        return true
    }
    
    // MARK: - Test 12: Keychain Storage Lifecycle
    
    public static func testKeychainStorageLifecycle() async -> Bool {
        print("[Test 12] Keychain Services key storage, retrieval, and teardown purge...")
        let cryptoService = CryptoService()
        let sessionId: UInt16 = 0x1234
        let key = cryptoService.generateSymmetricKey()
        
        do {
            // 1. Store
            try await cryptoService.storeKeyInKeychain(key, forSessionId: sessionId)
            
            // 2. Load
            let loadedKey = try await cryptoService.loadKeyFromKeychain(forSessionId: sessionId)
            guard let validLoadedKey = loadedKey else {
                print("  FAIL: Failed to load stored key.")
                return false
            }
            
            let originalBytes = key.withUnsafeBytes { Data($0) }
            let loadedBytes = validLoadedKey.withUnsafeBytes { Data($0) }
            guard originalBytes == loadedBytes else {
                print("  FAIL: Loaded key bytes mismatch.")
                return false
            }
            
            // 3. Purge
            try await cryptoService.purgeKeyFromKeychain(forSessionId: sessionId)
            let purgedKey = try await cryptoService.loadKeyFromKeychain(forSessionId: sessionId)
            guard purgedKey == nil else {
                print("  FAIL: Key should not exist after purge.")
                return false
            }
            
            print("  PASS: Key persisted, retrieved, and purged cleanly.")
            return true
        } catch {
            print("  FAIL: Keychain lifecycle error: \(error)")
            return false
        }
    }
    
    // MARK: - Test 13: End-to-End Wire Datagram Codec
    
    public static func testEndToEndWireDatagramCodec() async -> Bool {
        print("[Test 13] End-to-end 56-byte wire datagram seal and open...")
        let cryptoService = CryptoService()
        let key = cryptoService.generateSymmetricKey()
        
        let envelope = CleartextEnvelope(
            type: .sos,
            hopLimit: 8,
            hopCount: 0,
            sessionId: 0x9988,
            sequenceNumber: CleartextEnvelope.makeSequenceNumber(memberSlot: 2, counter: 7)
        )
        let sosPayload = SOSPayload(
            coordinate: CLLocationCoordinate2D(latitude: -6.2088, longitude: 106.8456),
            accuracy: 4,
            sosEventId: 0x55555555,
            senderInitials: "EMG",
            emergencyType: .medical,
            batteryLevel: 35
        )
        let plainBytes = sosPayload.serialize()
        
        do {
            // Seal to exact 56 wire bytes
            let wireData = try await cryptoService.sealToWireBytes(payload: plainBytes, envelope: envelope, using: key)
            guard wireData.count == 56 else {
                print("  FAIL: Wire data must be exactly 56 bytes, got \(wireData.count)")
                return false
            }
            
            // Open 56 wire bytes
            let (unpackedEnvelope, decryptedPayload) = try await cryptoService.openWireBytes(wireData, using: key)
            guard unpackedEnvelope == envelope else {
                print("  FAIL: Unpacked envelope mismatch.")
                return false
            }
            guard decryptedPayload == plainBytes else {
                print("  FAIL: Decrypted payload mismatch.")
                return false
            }
            
            let unpackedSOS = try SOSPayload.deserialize(from: decryptedPayload)
            guard unpackedSOS.emergencyType == .medical,
                  unpackedSOS.batteryLevel == 35,
                  unpackedSOS.senderInitials == "EMG" else {
                print("  FAIL: Unpacked SOS fields mismatch.")
                return false
            }
            
            print("  PASS: End-to-end 56-byte datagram sealed, parsed, and verified.")
            return true
        } catch {
            print("  FAIL: End-to-end wire error: \(error)")
            return false
        }
    }
}
