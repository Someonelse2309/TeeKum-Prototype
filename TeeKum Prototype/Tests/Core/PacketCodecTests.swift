//
//  PacketCodecTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation
import CryptoKit

/// Exhaustive Test Suite for Packet Serialization, Deserialization, and Boundary Verification.
public enum PacketCodecTests {
    
    public static func runAllTests() -> Bool {
        var passed = true
        print("========================================")
        print("RUNNING PROTOCOL V3 PACKET CODEC TEST SUITE (56-BYTE)")
        print("========================================")
        
        if !testEnvelopeSerializationRoundtrip() { passed = false }
        if !testEnvelopeValidationAndErrors() { passed = false }
        if !testSequenceNumberPartitioning() { passed = false }
        if !testWirePacketLayoutAndSizeValidation() { passed = false }
        if !testLocationPingQuantization() { passed = false }
        if !testCoordinateBoundaryValues() { passed = false }
        if !testSOSPayloadRoundtrip() { passed = false }
        if !testMeetingUpdatePayloadRoundtrip() { passed = false }
        if !testACKPayloadRoundtrip() { passed = false }
        if !testRouteReqPayloadRoundtrip() { passed = false }
        if !testRouteRespPayloadRoundtrip() { passed = false }
        if !testDeterministicTestVector() { passed = false }
        if !testInitialsCodecBase26() { passed = false }
        if !testMemberColorPayloadRoundtripAndInitialsHashFallback() { passed = false }
        if !testChatMessagePayloadSerializationRoundtrip() { passed = false }
        if !testChatMessagePayloadUTF8EncodingAndMultiByte() { passed = false }
        if !testChatMessagePayloadMalformedInputsAndValidation() { passed = false }
        if !testChatMessageWirePacketRoundtripAndCryptoAEAD() { passed = false }
        if !testLocationPingOptionBContiguousPackingAndRegression() { passed = false }
        if !testAllExistingPacketTypesRegression() { passed = false }
        
        print("========================================")
        print(passed ? "ALL CODEC TESTS PASSED SUCCESSFULLY!" : "CODEC TESTS FAILED!")
        print("========================================")
        return passed
    }
    
    // MARK: - Test 1: CleartextEnvelope Serialization & Deserialization
    
    public static func testEnvelopeSerializationRoundtrip() -> Bool {
        print("[Test 1] CleartextEnvelope 10-byte serialization and deserialization...")
        let original = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .locationPing,
            hopLimit: 8,
            hopCount: 2,
            sessionId: 0xBEEF,
            sequenceNumber: 1337
        )
        
        let data = original.serialize()
        guard data.count == 10 else {
            print("  FAIL: Expected 10 bytes, got \(data.count)")
            return false
        }
        
        do {
            let decoded = try CleartextEnvelope.deserialize(from: data)
            guard decoded == original else {
                print("  FAIL: Decoded envelope does not match original.")
                return false
            }
            print("  PASS: 10-byte envelope serialized and deserialized accurately.")
            return true
        } catch {
            print("  FAIL: Exception caught: \(error)")
            return false
        }
    }
    
    // MARK: - Test 2: Envelope Validation & Error Handling
    
    public static func testEnvelopeValidationAndErrors() -> Bool {
        print("[Test 2] CleartextEnvelope validation and error handling...")
        
        // 1. Buffer underflow (<10 bytes)
        let shortData = Data([0x21, 0x08, 0x00, 0x00, 0x12, 0x34])
        do {
            _ = try CleartextEnvelope.deserialize(from: shortData)
            print("  FAIL: Should have thrown bufferUnderflow for short data.")
            return false
        } catch PacketCodecError.bufferUnderflow {
            // Expected
        } catch {
            print("  FAIL: Wrong error for short data: \(error)")
            return false
        }
        
        // 2. Unsupported protocol version (e.g. 0x01 when 0x03 is required)
        let invalidVersionData = Data([0x11, 0x08, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
        do {
            _ = try CleartextEnvelope.deserialize(from: invalidVersionData)
            print("  FAIL: Should have thrown unsupportedVersion.")
            return false
        } catch PacketCodecError.unsupportedVersion(let v) where v == 1 {
            // Expected
        } catch {
            print("  FAIL: Wrong error for invalid version: \(error)")
            return false
        }
        
        // 3. Unknown packet type (e.g. 0x0F)
        let invalidTypeData = Data([0x3F, 0x08, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
        do {
            _ = try CleartextEnvelope.deserialize(from: invalidTypeData)
            print("  FAIL: Should have thrown unknownPacketType.")
            return false
        } catch PacketCodecError.unknownPacketType(let t) where t == 0x0F {
            // Expected
        } catch {
            print("  FAIL: Wrong error for invalid type: \(error)")
            return false
        }
        
        // 4. Invalid hop limit (0)
        let zeroHopLimitData = Data([0x31, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
        do {
            _ = try CleartextEnvelope.deserialize(from: zeroHopLimitData)
            print("  FAIL: Should have thrown invalidHopLimit.")
            return false
        } catch PacketCodecError.invalidHopLimit(let l) where l == 0 {
            // Expected
        } catch {
            print("  FAIL: Wrong error for zero hop limit: \(error)")
            return false
        }
        
        // 5. Hop count exceeding hop limit (count=5, limit=3)
        let hopCountExceededData = Data([0x31, 0x03, 0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
        do {
            _ = try CleartextEnvelope.deserialize(from: hopCountExceededData)
            print("  FAIL: Should have thrown hopCountExceededLimit.")
            return false
        } catch PacketCodecError.hopCountExceededLimit(let count, let limit) where count == 5 && limit == 3 {
            // Expected
        } catch {
            print("  FAIL: Wrong error for hop count exceeding limit: \(error)")
            return false
        }
        
        print("  PASS: All envelope validation checks rejected malformed headers accurately.")
        return true
    }
    
    // MARK: - Test 3: Sequence Number Partitioning
    
    public static func testSequenceNumberPartitioning() -> Bool {
        print("[Test 3] Sequence number partitioning (memberSlot + monotonic counter)...")
        
        // Case A: Member slot 3, counter 100
        let seqA = CleartextEnvelope.makeSequenceNumber(memberSlot: 3, counter: 100)
        guard CleartextEnvelope.memberSlot(from: seqA) == 3 else {
            print("  FAIL: memberSlot mismatch: expected 3, got \(CleartextEnvelope.memberSlot(from: seqA))")
            return false
        }
        guard CleartextEnvelope.counter(from: seqA) == 100 else {
            print("  FAIL: counter mismatch: expected 100, got \(CleartextEnvelope.counter(from: seqA))")
            return false
        }
        
        // Case B: Boundary values - slot 255 (0xFF), max 24-bit counter 16,777,215 (0x00FFFFFF)
        let maxCounter: UInt32 = 0x00FFFFFF
        let seqB = CleartextEnvelope.makeSequenceNumber(memberSlot: 255, counter: maxCounter)
        guard CleartextEnvelope.memberSlot(from: seqB) == 255 else {
            print("  FAIL: memberSlot mismatch for boundary.")
            return false
        }
        guard CleartextEnvelope.counter(from: seqB) == maxCounter else {
            print("  FAIL: counter mismatch for max 24-bit value.")
            return false
        }
        guard seqB == 0xFFFFFFFF else {
            print("  FAIL: Packed 32-bit sequence should be 0xFFFFFFFF, got 0x\(String(format: "%08X", seqB))")
            return false
        }
        
        // Case C: Disjointness guarantee
        let seqMember0 = CleartextEnvelope.makeSequenceNumber(memberSlot: 0, counter: 1)
        let seqMember1 = CleartextEnvelope.makeSequenceNumber(memberSlot: 1, counter: 1)
        guard seqMember0 != seqMember1 else {
            print("  FAIL: Sequences for different members must never collide.")
            return false
        }
        
        print("  PASS: Sequence number partitioning correctly isolates member counter spaces.")
        return true
    }
    
    // MARK: - Test 4: Raw 56-Byte Wire Packet Layout & Size Enforcement
    
    public static func testWirePacketLayoutAndSizeValidation() -> Bool {
        print("[Test 4] RawWirePacket 56-byte layout and size validation...")
        let envelope = CleartextEnvelope(
            type: .sos,
            sessionId: 0x1234,
            sequenceNumber: 42
        )
        let dummyCiphertext = Data(repeating: 0xAA, count: 30)
        let dummyAuthTag = Data(repeating: 0xBB, count: 16)
        
        let packet = RawWirePacket(envelope: envelope, ciphertext: dummyCiphertext, authTag: dummyAuthTag)
        
        do {
            let wireData = try packet.toWireData()
            guard wireData.count == 56 else {
                print("  FAIL: Expected exactly 56 bytes, got \(wireData.count)")
                return false
            }
            
            let parsed = try RawWirePacket.fromWireData(wireData)
            guard parsed == packet else {
                print("  FAIL: Parsed wire packet does not match original.")
                return false
            }
            
            // Reject short packet (55 bytes)
            let shortWire = wireData.prefix(55)
            do {
                _ = try RawWirePacket.fromWireData(shortWire)
                print("  FAIL: Should have rejected 55-byte packet.")
                return false
            } catch PacketCodecError.invalidPacketSize(let exp, let act) where exp == 56 && act == 55 {
                // Expected
            }
            
            // Reject long packet (57 bytes)
            var longWire = wireData
            longWire.append(0x00)
            do {
                _ = try RawWirePacket.fromWireData(longWire)
                print("  FAIL: Should have rejected 57-byte packet.")
                return false
            } catch PacketCodecError.invalidPacketSize(let exp, let act) where exp == 56 && act == 57 {
                // Expected
            }
            
            print("  PASS: Exact 56-byte wire packet layout enforced.")
            return true
        } catch {
            print("  FAIL: Exception caught: \(error)")
            return false
        }
    }
    
    // MARK: - Test 5: Location Ping Quantization & Precision (~11cm)
    
    public static func testLocationPingQuantization() -> Bool {
        print("[Test 5] LocationPingPayload Int32 quantization precision...")
        let coordinate = CLLocationCoordinate2D(latitude: 33.680312, longitude: -116.237409)
        let timestamp = Date(timeIntervalSince1970: 1729000000)
        
        let payload = LocationPingPayload(
            coordinate: coordinate,
            timestamp: timestamp,
            accuracy: 8,
            senderInitials: "DNA",
            batteryLevel: 85,
            heading: 180,
            colorCode: 0
        )
        
        let data = payload.serialize()
        guard data.count == 30 else {
            print("  FAIL: Expected 30 bytes, got \(data.count)")
            return false
        }
        
        do {
            let decoded = try LocationPingPayload.deserialize(from: data)
            let latDiff = abs(decoded.coordinate.latitude - coordinate.latitude)
            let lonDiff = abs(decoded.coordinate.longitude - coordinate.longitude)
            
            guard latDiff < 0.000002 && lonDiff < 0.000002 else {
                print("  FAIL: Quantization precision loss excessive: latDiff=\(latDiff), lonDiff=\(lonDiff)")
                return false
            }
            guard decoded.accuracy == 8,
                  decoded.senderInitials == "DNA",
                  decoded.batteryLevel == 85,
                  decoded.heading == 180 else {
                print("  FAIL: Metadata mismatch on decoded payload.")
                return false
            }
            print("  PASS: Coordinates quantized and initials decoded with <11cm resolution.")
            return true
        } catch {
            print("  FAIL: Exception caught: \(error)")
            return false
        }
    }
    
    // MARK: - Test 6: Coordinate Boundary Values
    
    public static func testCoordinateBoundaryValues() -> Bool {
        print("[Test 6] Coordinate boundary values (0.0, -90.0, 90.0, -180.0, 180.0)...")
        let boundaryCoords = [
            CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
            CLLocationCoordinate2D(latitude: -90.0, longitude: -180.0),
            CLLocationCoordinate2D(latitude: 90.0, longitude: 180.0),
            CLLocationCoordinate2D(latitude: -90.0, longitude: 180.0),
            CLLocationCoordinate2D(latitude: 90.0, longitude: -180.0)
        ]
        
        for coord in boundaryCoords {
            let payload = LocationPingPayload(
                coordinate: coord,
                accuracy: 5,
                senderInitials: "ALE",
                batteryLevel: 50
            )
            let data = payload.serialize()
            guard data.count == 30 else { return false }
            do {
                let decoded = try LocationPingPayload.deserialize(from: data)
                let latDiff = abs(decoded.coordinate.latitude - coord.latitude)
                let lonDiff = abs(decoded.coordinate.longitude - coord.longitude)
                guard latDiff < 0.000002 && lonDiff < 0.000002 else {
                    print("  FAIL: Boundary coordinate quantization failed for \(coord)")
                    return false
                }
            } catch {
                print("  FAIL: Failed deserializing boundary coordinate: \(error)")
                return false
            }
        }
        print("  PASS: Boundary coordinates preserved safely.")
        return true
    }
    
    // MARK: - Test 7: SOS Payload Roundtrip
    
    public static func testSOSPayloadRoundtrip() -> Bool {
        print("[Test 7] SOSPayload roundtrip serialization...")
        let coord = CLLocationCoordinate2D(latitude: 33.681122, longitude: -116.236544)
        let payload = SOSPayload(
            coordinate: coord,
            timestamp: Date(timeIntervalSince1970: 1729000500),
            accuracy: 4,
            sosEventId: 0x98765432,
            senderInitials: "BOB",
            emergencyType: .medical,
            batteryLevel: 42
        )
        
        let data = payload.serialize()
        guard data.count == 30 else {
            print("  FAIL: SOS payload size expected 30 bytes, got \(data.count)")
            return false
        }
        
        do {
            let decoded = try SOSPayload.deserialize(from: data)
            guard decoded.sosEventId == 0x98765432,
                  decoded.senderInitials == "BOB",
                  decoded.emergencyType == .medical,
                  decoded.batteryLevel == 42 else {
                print("  FAIL: SOS decoded payload fields mismatch.")
                return false
            }
            print("  PASS: SOSPayload serialized and deserialized accurately.")
            return true
        } catch {
            print("  FAIL: SOS deserialization failed: \(error)")
            return false
        }
    }
    
    // MARK: - Test 8: Meeting Update Payload Roundtrip
    
    public static func testMeetingUpdatePayloadRoundtrip() -> Bool {
        print("[Test 8] MeetingUpdatePayload roundtrip serialization...")
        let coord = CLLocationCoordinate2D(latitude: 33.682200, longitude: -116.235500)
        let payload = MeetingUpdatePayload(
            coordinate: coord,
            meetupTime: Date(timeIntervalSince1970: 1729003600),
            createdAt: Date(timeIntervalSince1970: 1729000000),
            action: .accept,
            attendanceStatus: .attending,
            meetingPointId: 0x55556666,
            senderInitials: "SAM",
            arrivalRadiusMeters: 25,
            isRightNow: false,
            anchorToProposerGPS: true
        )
        
        let data = payload.serialize()
        guard data.count == 30 else {
            print("  FAIL: MeetingUpdate payload size expected 30 bytes, got \(data.count)")
            return false
        }
        
        do {
            let decoded = try MeetingUpdatePayload.deserialize(from: data)
            guard decoded.meetingPointId == 0x55556666,
                  decoded.senderInitials == "SAM",
                  decoded.action == .accept,
                  decoded.attendanceStatus == .attending,
                  decoded.arrivalRadiusMeters == 25,
                  decoded.anchorToProposerGPS == true,
                  decoded.isRightNow == false else {
                print("  FAIL: MeetingUpdate decoded payload fields mismatch.")
                return false
            }
            print("  PASS: MeetingUpdatePayload serialized and deserialized accurately.")
            return true
        } catch {
            print("  FAIL: MeetingUpdate deserialization failed: \(error)")
            return false
        }
    }
    
    // MARK: - Test 9: ACK Payload Roundtrip
    
    public static func testACKPayloadRoundtrip() -> Bool {
        print("[Test 9] ACKPayload roundtrip serialization...")
        let payload = ACKPayload(
            ackedSeqNumber: 0x00000005,
            ackedSenderInitials: "SAM",
            ackTimestamp: Date(timeIntervalSince1970: 1729000100),
            ackStatus: .deliveredToFriend,
            receivedRssi: -65,
            originalEventId: 0x99998888,
            responderInitials: "DNA"
        )
        
        let data = payload.serialize()
        guard data.count == 30 else {
            print("  FAIL: ACK payload size expected 30 bytes, got \(data.count)")
            return false
        }
        
        do {
            let decoded = try ACKPayload.deserialize(from: data)
            guard decoded.ackedSeqNumber == 0x00000005,
                  decoded.ackedSenderInitials == "SAM",
                  decoded.ackStatus == .deliveredToFriend,
                  decoded.receivedRssi == -65,
                  decoded.originalEventId == 0x99998888,
                  decoded.responderInitials == "DNA" else {
                print("  FAIL: ACK decoded payload fields mismatch.")
                return false
            }
            print("  PASS: ACKPayload serialized and verified.")
            return true
        } catch {
            print("  FAIL: ACK deserialization failed: \(error)")
            return false
        }
    }
    
    // MARK: - Tests 10 & 11: Route Discovery Payloads
    
    public static func testRouteReqPayloadRoundtrip() -> Bool {
        print("[Test 10] RouteReqPayload roundtrip...")
        let payload = RouteReqPayload(
            originatorInitials: "DNA",
            targetInitials: "BOB",
            discoveryNonce: 0x12345678,
            routeCost: 3
        )
        let data = payload.serialize()
        guard data.count == 30 else { return false }
        do {
            let decoded = try RouteReqPayload.deserialize(from: data)
            guard decoded.originatorInitials == "DNA",
                  decoded.targetInitials == "BOB",
                  decoded.discoveryNonce == 0x12345678,
                  decoded.routeCost == 3 else {
                return false
            }
            return true
        } catch {
            return false
        }
    }
    
    public static func testRouteRespPayloadRoundtrip() -> Bool {
        print("[Test 11] RouteRespPayload roundtrip...")
        let payload = RouteRespPayload(
            originatorInitials: "DNA",
            targetInitials: "BOB",
            discoveryNonce: 0x12345678,
            routeCost: 3
        )
        let data = payload.serialize()
        guard data.count == 30 else { return false }
        do {
            let decoded = try RouteRespPayload.deserialize(from: data)
            guard decoded.originatorInitials == "DNA",
                  decoded.targetInitials == "BOB",
                  decoded.discoveryNonce == 0x12345678,
                  decoded.routeCost == 3 else {
                return false
            }
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Test 12: Deterministic Test Vector
    
    public static func testDeterministicTestVector() -> Bool {
        print("[Test 12] Deterministic test vector serialization...")
        // Known fixed inputs:
        // Envelope: version=3, type=1 (locationPing) -> byte0 = 0x31
        // hopLimit=8, hopCount=0 -> byte1 = 0x08, byte2 = 0x00
        // sessionId = 0x0102 -> bytes 3..5 = [0x00, 0x01, 0x02]
        // sequenceNumber = 0x0A0B0C0D -> bytes 6..9 = [0x0A, 0x0B, 0x0C, 0x0D]
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: 0x0102,
            sequenceNumber: 0x0A0B0C0D
        )
        let envBytes = envelope.serialize()
        let expectedEnvHex = "3108000001020a0b0c0d"
        let actualEnvHex = envBytes.map { String(format: "%02x", $0) }.joined()
        guard actualEnvHex == expectedEnvHex else {
            print("  FAIL: Envelope test vector mismatch: expected \(expectedEnvHex), got \(actualEnvHex)")
            return false
        }
        
        // AAD test vector: masked hopCount must be 0x00 at Byte 2
        let aadBytes = envelope.authenticatedAssociatedData()
        let actualAadHex = aadBytes.map { String(format: "%02x", $0) }.joined()
        guard actualAadHex == expectedEnvHex else {
            print("  FAIL: AAD test vector mismatch: expected \(expectedEnvHex), got \(actualAadHex)")
            return false
        }
        
        // Nonce test vector: sessionId (3B) + sequenceNumber (4B) + byte0 (1B) + "TKM3" (4B)
        let nonceBytes = envelope.constructNonce()
        let expectedNonceHex = "0001020a0b0c0d31544b4d33"
        let actualNonceHex = nonceBytes.map { String(format: "%02x", $0) }.joined()
        guard actualNonceHex == expectedNonceHex else {
            print("  FAIL: Nonce test vector mismatch: expected \(expectedNonceHex), got \(actualNonceHex)")
            return false
        }
        
        print("  PASS: Deterministic envelope, AAD, and Nonce vectors verified bit-for-bit.")
        return true
    }
    
    // MARK: - Test 13: 1 to 3-Letter Initials Codec
    
    public static func testInitialsCodecBase26() -> Bool {
        print("[Test 13] InitialsCodec 1-to-3 letter encoding and decoding...")
        
        // 1. Single letter: "A" -> 1*729 = 729 -> [2, 217]
        guard let aBytes = InitialsCodec.encode("A") else {
            print("  FAIL: Encoding 'A' returned nil")
            return false
        }
        guard aBytes.count == 2, InitialsCodec.decode(aBytes) == "A" else {
            print("  FAIL: Roundtrip for 'A' failed")
            return false
        }
        
        // Single letter: "Z"
        guard let zBytes = InitialsCodec.encode("Z"), InitialsCodec.decode(zBytes) == "Z" else {
            print("  FAIL: Roundtrip for 'Z' failed")
            return false
        }
        
        // 2. Two letters: "AB" -> 1*729 + 2*27 = 783 -> [3, 15]
        guard let abBytes = InitialsCodec.encode("AB") else {
            print("  FAIL: Encoding 'AB' returned nil")
            return false
        }
        guard abBytes.count == 2, InitialsCodec.decode(abBytes) == "AB" else {
            print("  FAIL: Roundtrip for 'AB' failed")
            return false
        }
        
        // Two letters: "ZZ"
        guard let zzBytes = InitialsCodec.encode("ZZ"), InitialsCodec.decode(zzBytes) == "ZZ" else {
            print("  FAIL: Roundtrip for 'ZZ' failed")
            return false
        }
        
        // 3. Three letters: "DNA"
        guard let dnaBytes = InitialsCodec.encode("DNA") else {
            print("  FAIL: Encoding 'DNA' returned nil")
            return false
        }
        guard dnaBytes.count == 2, InitialsCodec.decode(dnaBytes) == "DNA" else {
            print("  FAIL: Roundtrip for 'DNA' failed")
            return false
        }
        
        // Boundary AAA
        guard let aaaBytes = InitialsCodec.encode("AAA"), InitialsCodec.decode(aaaBytes) == "AAA" else { return false }
        
        // Boundary ZZZ (max 19,682 <= 65,535)
        guard let zzzBytes = InitialsCodec.encode("ZZZ"), InitialsCodec.decode(zzzBytes) == "ZZZ" else { return false }
        
        // 4. Invalid inputs
        guard InitialsCodec.encode("") == nil else { return false }
        guard InitialsCodec.encode("ABCD") == nil else { return false }
        guard InitialsCodec.encode("123") == nil else { return false }
        guard InitialsCodec.decode([0, 0]) == nil else { return false } // Out of bounds (< 729)
        guard InitialsCodec.decode([0xFF, 0xFF]) == nil else { return false } // Out of bounds (> 19,682)
        
        // 5. Sanitization
        guard InitialsCodec.sanitize("d") == "D" else { return false }
        guard InitialsCodec.sanitize("ab") == "AB" else { return false }
        guard InitialsCodec.sanitize("Alex") == "ALE" else { return false }
        guard InitialsCodec.sanitize(" d-n.a! ") == "DNA" else { return false }
        
        print("  PASS: InitialsCodec 1, 2, and 3-letter arithmetic, bounds, and roundtrips verified.")
        return true
    }
    
    // MARK: - Test 14: MemberColor Payload Serialization & Deterministic Initials Fallback
    
    public static func testMemberColorPayloadRoundtripAndInitialsHashFallback() -> Bool {
        print("[Test 14] MemberColor 1-byte wire serialization and deterministic hash fallback...")
        
        // 1. LocationPingPayload roundtrip with explicit MemberColor
        let coord = CLLocationCoordinate2D(latitude: 37.774929, longitude: -122.419416)
        let ping = LocationPingPayload(
            coordinate: coord,
            timestamp: Date(timeIntervalSince1970: 1730000000),
            accuracy: 8,
            senderInitials: "NIC",
            batteryLevel: 88,
            heading: 120,
            colorCode: MemberColor.neonPink.rawValue
        )
        
        let pingData = ping.serialize()
        guard pingData.count == 30 else {
            print("  FAIL: LocationPing serialized count must be exactly 30 bytes, got \(pingData.count)")
            return false
        }
        
        // Byte 17 must contain MemberColor.neonPink.rawValue (0x01) in Option B layout
        guard pingData[17] == MemberColor.neonPink.rawValue else {
            print("  FAIL: Byte 17 expected \(MemberColor.neonPink.rawValue), got \(pingData[17])")
            return false
        }
        
        do {
            let decodedPing = try LocationPingPayload.deserialize(from: pingData)
            guard decodedPing.colorCode == MemberColor.neonPink.rawValue else {
                print("  FAIL: Decoded ping colorCode expected \(MemberColor.neonPink.rawValue), got \(decodedPing.colorCode)")
                return false
            }
            let resolvedColor = MemberColor.resolve(code: decodedPing.colorCode, initials: decodedPing.senderInitials)
            guard resolvedColor == .neonPink else {
                print("  FAIL: Resolved MemberColor expected .neonPink, got \(resolvedColor)")
                return false
            }
        } catch {
            print("  FAIL: Deserialization of LocationPing with color failed: \(error)")
            return false
        }
        
        // 2. SOSPayload roundtrip with explicit MemberColor
        let sos = SOSPayload(
            coordinate: coord,
            timestamp: Date(timeIntervalSince1970: 1730000010),
            accuracy: 5,
            sosEventId: 0xCAFEBABE,
            senderInitials: "ALX",
            emergencyType: .medical,
            batteryLevel: 65,
            colorCode: MemberColor.electricPurple.rawValue
        )
        
        let sosData = sos.serialize()
        guard sosData.count == 30 else {
            print("  FAIL: SOS serialized count must be exactly 30 bytes, got \(sosData.count)")
            return false
        }
        guard sosData[22] == MemberColor.electricPurple.rawValue else {
            print("  FAIL: SOS Byte 22 expected \(MemberColor.electricPurple.rawValue), got \(sosData[22])")
            return false
        }
        
        do {
            let decodedSOS = try SOSPayload.deserialize(from: sosData)
            guard decodedSOS.colorCode == MemberColor.electricPurple.rawValue else {
                print("  FAIL: Decoded SOS colorCode expected \(MemberColor.electricPurple.rawValue), got \(decodedSOS.colorCode)")
                return false
            }
            let resolvedColor = MemberColor.resolve(code: decodedSOS.colorCode, initials: decodedSOS.senderInitials)
            guard resolvedColor == .electricPurple else {
                print("  FAIL: Resolved SOS color expected .electricPurple, got \(resolvedColor)")
                return false
            }
        } catch {
            print("  FAIL: Deserialization of SOS with color failed: \(error)")
            return false
        }
        
        // 3. Backward Compatibility: Legacy zero-padded packet (colorCode == 0x00)
        let legacyPing = LocationPingPayload(
            coordinate: coord,
            timestamp: Date(timeIntervalSince1970: 1730000000),
            accuracy: 8,
            senderInitials: "DNA",
            batteryLevel: 90,
            heading: 0,
            colorCode: 0 // Legacy 0x00
        )
        let legacyData = legacyPing.serialize()
        guard legacyData[17] == 0x00 else {
            print("  FAIL: Legacy ping Byte 17 should be 0x00")
            return false
        }
        
        do {
            let decodedLegacy = try LocationPingPayload.deserialize(from: legacyData)
            guard decodedLegacy.colorCode == 0 else {
                print("  FAIL: Legacy color code expected 0")
                return false
            }
            // Must deterministically resolve based on initials "DNA"
            let resolvedLegacy = MemberColor.resolve(code: decodedLegacy.colorCode, initials: decodedLegacy.senderInitials)
            let expectedDNAColor = MemberColor.deterministicColor(for: "DNA")
            guard resolvedLegacy == expectedDNAColor && resolvedLegacy != .unset else {
                print("  FAIL: Legacy resolution expected \(expectedDNAColor), got \(resolvedLegacy)")
                return false
            }
        } catch {
            print("  FAIL: Legacy deserialization failed: \(error)")
            return false
        }
        
        // 4. Deterministic Hashing Invariance & Stability
        let color1 = MemberColor.deterministicColor(for: "NIC")
        let color2 = MemberColor.deterministicColor(for: "NIC")
        guard color1 == color2 else {
            print("  FAIL: Deterministic hashing is non-deterministic for 'NIC'")
            return false
        }
        
        // 5. Selectable Palette Integrity (8 distinct colors, pure Red excluded)
        let selectable = MemberColor.selectableColors
        guard selectable.count == 8 else {
            print("  FAIL: Expected exactly 8 selectable colors, got \(selectable.count)")
            return false
        }
        guard !selectable.contains(.unset) else {
            print("  FAIL: Selectable palette should not contain .unset")
            return false
        }
        
        print("  PASS: MemberColor payload roundtrip, legacy backward compatibility, and deterministic hashing verified.")
        return true
    }
    
    // MARK: - Test 15: ChatMessagePayload Serialization & Deserialization Roundtrip
    
    public static func testChatMessagePayloadSerializationRoundtrip() -> Bool {
        print("[Test 15] ChatMessagePayload 30-byte serialization and roundtrip...")
        
        let testCases: [(initials: String, text: String)] = [
            ("NIC", ""), // 0 bytes text
            ("A", "H"), // 1 byte text
            ("AB", "Stage 2"), // 7 bytes text
            ("DNA", "Beer? Stage 2 - OMW"), // 19 bytes text
            ("ALX", "12345678901234567890"), // exactly 20 bytes text
            ("SAM", ChatMessagePayload.presetBeerLine), // 9 bytes
            ("BOB", ChatMessagePayload.presetAtMainStage), // 13 bytes
            ("CHA", ChatMessagePayload.presetRestroom), // 8 bytes
            ("DAN", ChatMessagePayload.presetWhereAreYou), // 14 bytes
            ("EVE", ChatMessagePayload.presetOnMyWay), // 9 bytes
            ("FRANK", ChatMessagePayload.presetLost) // 4 bytes (initials sanitized to FRA)
        ]
        
        let timestamp = Date(timeIntervalSince1970: 1730005000)
        
        for (initials, text) in testCases {
            let payload = ChatMessagePayload(
                senderInitials: initials,
                timestamp: timestamp,
                text: text
            )
            
            do {
                let data = try payload.serialize()
                guard data.count == PacketConstants.encryptedPayloadSize else {
                    print("  FAIL: ChatMessagePayload serialized count must be exactly 30 bytes, got \(data.count)")
                    return false
                }
                
                // Verify byte 6 contains exact text length in bytes
                let expectedLen = UInt8(text.utf8.count)
                guard data[6] == expectedLen else {
                    print("  FAIL: Byte 6 expected length \(expectedLen), got \(data[6])")
                    return false
                }
                
                // Verify bytes 27..29 are zero padding
                guard data[27] == 0 && data[28] == 0 && data[29] == 0 else {
                    print("  FAIL: Reserved bytes 27..29 must be zero padding")
                    return false
                }
                
                // Verify unused text bytes are zero-padded
                for i in (7 + Int(expectedLen))..<27 {
                    guard data[i] == 0 else {
                        print("  FAIL: Unused text byte at index \(i) was not zero-padded")
                        return false
                    }
                }
                
                let decoded = try ChatMessagePayload.deserialize(from: data)
                let expectedInitials = InitialsCodec.sanitize(initials)
                guard decoded.senderInitials == expectedInitials else {
                    print("  FAIL: Decoded initials '\(decoded.senderInitials)' != expected '\(expectedInitials)'")
                    return false
                }
                guard abs(decoded.timestamp.timeIntervalSince1970 - timestamp.timeIntervalSince1970) < 1.0 else {
                    print("  FAIL: Timestamp mismatch")
                    return false
                }
                guard decoded.text == text else {
                    print("  FAIL: Decoded text '\(decoded.text)' != expected '\(text)'")
                    return false
                }
            } catch {
                print("  FAIL: Serialization or deserialization threw: \(error)")
                return false
            }
        }
        
        print("  PASS: ChatMessagePayload 30-byte roundtrip verified across ASCII, presets, and boundaries.")
        return true
    }
    
    // MARK: - Test 16: ChatMessagePayload UTF-8 Multi-Byte Encoding & Emoji Clamping
    
    public static func testChatMessagePayloadUTF8EncodingAndMultiByte() -> Bool {
        print("[Test 16] ChatMessagePayload UTF-8 multi-byte encoding and byte-boundary clamping...")
        
        let ts = Date(timeIntervalSince1970: 1730006000)
        
        // 1. Accented characters (2-byte UTF-8): "Café 10" -> C(1)+a(1)+f(1)+é(2)+ (1)+1(1)+0(1) = 8 bytes
        let cafePayload = ChatMessagePayload(senderInitials: "ALX", timestamp: ts, text: "Café 10")
        do {
            let data = try cafePayload.serialize()
            guard data[6] == 8 else {
                print("  FAIL: Expected 8 UTF-8 bytes for 'Café 10', got \(data[6])")
                return false
            }
            let decoded = try ChatMessagePayload.deserialize(from: data)
            guard decoded.text == "Café 10" else {
                print("  FAIL: Decoded accented text mismatch")
                return false
            }
        } catch {
            print("  FAIL: Accented UTF-8 test failed: \(error)")
            return false
        }
        
        // 2. Standard 4-byte emoji: "Beer 🍺" -> B(1)+e(1)+e(1)+r(1)+ (1)+🍺(4) = 9 bytes
        let emojiPayload = ChatMessagePayload(senderInitials: "NIC", timestamp: ts, text: "Beer 🍺")
        do {
            let data = try emojiPayload.serialize()
            guard data[6] == 9 else {
                print("  FAIL: Expected 9 UTF-8 bytes for 'Beer 🍺', got \(data[6])")
                return false
            }
            let decoded = try ChatMessagePayload.deserialize(from: data)
            guard decoded.text == "Beer 🍺" else {
                print("  FAIL: Decoded emoji text mismatch")
                return false
            }
        } catch {
            print("  FAIL: Emoji UTF-8 test failed: \(error)")
            return false
        }
        
        // 3. Exactly 5 emojis (5 * 4 = 20 bytes): "🍺🎉🎸🍕🎪"
        let maxEmojiPayload = ChatMessagePayload(senderInitials: "BOB", timestamp: ts, text: "🍺🎉🎸🍕🎪")
        do {
            guard maxEmojiPayload.text.utf8.count == 20 else {
                print("  FAIL: 5 emojis must equal exactly 20 bytes")
                return false
            }
            let data = try maxEmojiPayload.serialize()
            guard data[6] == 20 else {
                print("  FAIL: Expected 20 UTF-8 bytes, got \(data[6])")
                return false
            }
            let decoded = try ChatMessagePayload.deserialize(from: data)
            guard decoded.text == "🍺🎉🎸🍕🎪" else {
                print("  FAIL: Decoded 20-byte emoji sequence mismatch")
                return false
            }
        } catch {
            print("  FAIL: 20-byte emoji test failed: \(error)")
            return false
        }
        
        // 4. Clamping helper: clampTo20Bytes should not bisect multi-byte code points
        // 18 ASCII characters + 4-byte emoji = 22 bytes -> clamped must be 18 ASCII chars
        let longMixed = "123456789012345678🍺"
        let clamped = ChatMessagePayload.clampTo20Bytes(longMixed)
        guard clamped.utf8.count <= 20 else {
            print("  FAIL: Clamped UTF-8 bytes > 20: \(clamped.utf8.count)")
            return false
        }
        guard clamped == "123456789012345678" else {
            print("  FAIL: Clamped text should have excluded partial emoji: '\(clamped)'")
            return false
        }
        
        // 6 emojis (24 bytes) -> clamped to 5 emojis (20 bytes)
        let sixEmojis = "🍺🎉🎸🍕🎪🔥"
        let clampedEmojis = ChatMessagePayload.clampTo20Bytes(sixEmojis)
        guard clampedEmojis.utf8.count == 20 && clampedEmojis == "🍺🎉🎸🍕🎪" else {
            print("  FAIL: Clamped 6 emojis expected 5 emojis (20B), got '\(clampedEmojis)'")
            return false
        }
        
        print("  PASS: UTF-8 multi-byte encoding, emoji byte counts, and boundary clamping verified.")
        return true
    }
    
    // MARK: - Test 17: ChatMessagePayload Malformed Inputs & Bounds Validation
    
    public static func testChatMessagePayloadMalformedInputsAndValidation() -> Bool {
        print("[Test 17] ChatMessagePayload malformed inputs and error handling...")
        
        let validPayload = ChatMessagePayload(senderInitials: "DNA", text: "Hello")
        let validData = validPayload.serializeUnchecked()
        
        // 1. Buffer underflow: data count < 30 bytes
        let shortData = validData.prefix(29)
        do {
            _ = try ChatMessagePayload.deserialize(from: shortData)
            print("  FAIL: Short data (<30 bytes) should throw bufferUnderflow")
            return false
        } catch PacketCodecError.bufferUnderflow {
            // Expected
        } catch {
            print("  FAIL: Unexpected error for buffer underflow: \(error)")
            return false
        }
        
        // 2. Length field exceeding 20 bytes (e.g. data[6] = 21)
        var invalidLenData = validData
        invalidLenData[6] = 21
        do {
            _ = try ChatMessagePayload.deserialize(from: invalidLenData)
            print("  FAIL: Text length 21 should throw invalidTextLength")
            return false
        } catch PacketCodecError.invalidTextLength(let len) where len == 21 {
            // Expected
        } catch {
            print("  FAIL: Unexpected error for invalid text length: \(error)")
            return false
        }
        
        // Length field = 255
        invalidLenData[6] = 255
        do {
            _ = try ChatMessagePayload.deserialize(from: invalidLenData)
            print("  FAIL: Text length 255 should throw invalidTextLength")
            return false
        } catch PacketCodecError.invalidTextLength(let len) where len == 255 {
            // Expected
        } catch {
            print("  FAIL: Unexpected error for invalid text length 255: \(error)")
            return false
        }
        
        // 3. Malformed UTF-8 text bytes
        // Set text length = 2, and put an invalid UTF-8 sequence [0xFF, 0x00]
        var malformedUtf8Data = validData
        malformedUtf8Data[6] = 2
        malformedUtf8Data[7] = 0xFF
        malformedUtf8Data[8] = 0x00
        do {
            _ = try ChatMessagePayload.deserialize(from: malformedUtf8Data)
            print("  FAIL: Malformed UTF-8 bytes should throw invalidTextEncoding")
            return false
        } catch PacketCodecError.invalidTextEncoding {
            // Expected
        } catch {
            print("  FAIL: Unexpected error for malformed UTF-8: \(error)")
            return false
        }
        
        // 4. Serialization with text exceeding 20 bytes throws invalidTextLength
        let longText = "This text is definitely way longer than twenty bytes!"
        let oversizedPayload = ChatMessagePayload(senderInitials: "NIC", text: longText)
        do {
            _ = try oversizedPayload.serialize()
            print("  FAIL: Oversized text serialization should throw invalidTextLength")
            return false
        } catch PacketCodecError.invalidTextLength(let count) where count == longText.utf8.count {
            // Expected
        } catch {
            print("  FAIL: Unexpected error for oversized serialization: \(error)")
            return false
        }
        
        // 5. serializeUnchecked clamps oversized text to at most 20 bytes
        let clampedSerialized = oversizedPayload.serializeUnchecked()
        guard clampedSerialized.count == 30 else {
            print("  FAIL: serializeUnchecked count should be 30 bytes")
            return false
        }
        guard clampedSerialized[6] == 20 else {
            print("  FAIL: serializeUnchecked byte 6 should be clamped to 20, got \(clampedSerialized[6])")
            return false
        }
        
        // 6. Strict deserialization rejects corrupted reserved padding (Bytes 27..29)
        var corruptedReservedData = validData
        corruptedReservedData[27] = 0xAA
        guard !ChatMessagePayload.hasValidReservedPadding(in: corruptedReservedData) else {
            print("  FAIL: hasValidReservedPadding should be false when byte 27 is corrupted")
            return false
        }
        do {
            _ = try ChatMessagePayload.deserializeStrict(from: corruptedReservedData)
            print("  FAIL: deserializeStrict should reject corrupted reserved padding")
            return false
        } catch PacketCodecError.payloadDeserializationFailed {
            // Expected
        } catch {
            print("  FAIL: Unexpected error for strict deserialization: \(error)")
            return false
        }
        
        // 7. Strict deserialization rejects non-zero unused text padding
        // For text "Hello" (length 5), byte 15 is unused and should be 0
        var corruptedUnusedPadding = validData
        corruptedUnusedPadding[15] = 0x01
        guard !ChatMessagePayload.hasValidReservedPadding(in: corruptedUnusedPadding) else {
            print("  FAIL: hasValidReservedPadding should be false when unused padding is corrupted")
            return false
        }
        
        print("  PASS: All malformed, underflow, oversized, and reserved padding errors rejected safely.")
        return true
    }
    
    // MARK: - Test 18: Chat Wire Packet Layout & ChaCha20-Poly1305 AEAD Cryptography
    
    public static func testChatMessageWirePacketRoundtripAndCryptoAEAD() -> Bool {
        print("[Test 18] Chat wire packet 56-byte layout and ChaCha20-Poly1305 AEAD sealing...")
        
        let key = SymmetricKey(size: .bits256)
        let sessionId: UInt16 = 0xCAFE
        let sequenceNumber: UInt32 = CleartextEnvelope.makeSequenceNumber(memberSlot: 5, counter: 101)
        
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .chatMessage,
            hopLimit: 8,
            hopCount: 0,
            sessionId: sessionId,
            sequenceNumber: sequenceNumber
        )
        
        // 1. Verify envelope serialization: byte 0 must be 0x37 (version 3 | type 7)
        let envData = envelope.serialize()
        guard envData.count == 10 else {
            print("  FAIL: Envelope must be 10 bytes, got \(envData.count)")
            return false
        }
        guard envData[0] == 0x37 else {
            print("  FAIL: Expected byte 0 to be 0x37, got 0x\(String(format: "%02X", envData[0]))")
            return false
        }
        
        // 2. Nonce test: domain tag "TKM3" and type 0x37
        let nonce = envelope.constructNonce()
        guard nonce.count == 12 else {
            print("  FAIL: Nonce must be 12 bytes")
            return false
        }
        guard nonce[7] == 0x37 else {
            print("  FAIL: Nonce byte 7 must be 0x37")
            return false
        }
        
        // 3. Seal ChatMessagePayload using ChaChaPoly
        let chat = ChatMessagePayload(senderInitials: "SAM", text: "Beer line")
        guard let plainPayload = try? chat.serialize() else {
            print("  FAIL: Chat serialization failed")
            return false
        }
        
        let aad = envelope.authenticatedAssociatedData()
        guard aad.count == 10, aad[0] == 0x37, aad[2] == 0x00 else {
            print("  FAIL: AAD malformed for chat packet")
            return false
        }
        
        do {
            let chachaNonce = try ChaChaPoly.Nonce(data: nonce)
            let sealed = try ChaChaPoly.seal(plainPayload, using: key, nonce: chachaNonce, authenticating: aad)
            
            guard sealed.ciphertext.count == 30 else {
                print("  FAIL: Ciphertext must be 30 bytes, got \(sealed.ciphertext.count)")
                return false
            }
            guard sealed.tag.count == 16 else {
                print("  FAIL: Auth tag must be 16 bytes, got \(sealed.tag.count)")
                return false
            }
            
            // 4. Form 56-byte RawWirePacket
            let rawPacket = RawWirePacket(envelope: envelope, ciphertext: sealed.ciphertext, authTag: sealed.tag)
            let wireBytes = try rawPacket.toWireData()
            guard wireBytes.count == 56 else {
                print("  FAIL: Total wire packet must be exactly 56 bytes, got \(wireBytes.count)")
                return false
            }
            
            // 5. Parse 56 bytes back
            let parsedRaw = try RawWirePacket.fromWireData(wireBytes)
            guard parsedRaw.envelope.type == .chatMessage else {
                print("  FAIL: Parsed envelope type should be .chatMessage")
                return false
            }
            guard parsedRaw.envelope.sessionId == sessionId else {
                print("  FAIL: SessionId mismatch")
                return false
            }
            
            // 6. Simulate mesh relay hop: mutate hopCount to 1
            var relayedEnvelope = parsedRaw.envelope
            relayedEnvelope.hopCount = 1
            
            // Decrypt with mutated hopCount: AAD normalizes hopCount to 0x00, so opening succeeds
            let relayedAAD = relayedEnvelope.authenticatedAssociatedData()
            let openedBox = try ChaChaPoly.SealedBox(nonce: chachaNonce, ciphertext: parsedRaw.ciphertext, tag: parsedRaw.authTag)
            let decryptedData = try ChaChaPoly.open(openedBox, using: key, authenticating: relayedAAD)
            
            guard decryptedData == plainPayload else {
                print("  FAIL: Decrypted payload != original plain bytes")
                return false
            }
            
            let decodedChat = try ChatMessagePayload.deserialize(from: decryptedData)
            guard decodedChat.senderInitials == "SAM", decodedChat.text == "Beer line" else {
                print("  FAIL: Decoded chat fields mismatch")
                return false
            }
            
            // 7. Tampering verification: mutate hopLimit in cleartext envelope
            var tamperedEnvelope = relayedEnvelope
            tamperedEnvelope.hopLimit = 15 // Attacker altered hopLimit
            let tamperedAAD = tamperedEnvelope.authenticatedAssociatedData()
            do {
                _ = try ChaChaPoly.open(openedBox, using: key, authenticating: tamperedAAD)
                print("  FAIL: Tampered hopLimit should have failed MAC verification")
                return false
            } catch {
                // Expected Poly1305 MAC failure
            }
            
            print("  PASS: 56-byte chat wire packet, AEAD authentication, hop masking, and tamper rejection verified.")
            return true
        } catch {
            print("  FAIL: Exception in AEAD roundtrip: \(error)")
            return false
        }
    }
    
    // MARK: - Test 19: LocationPing Option B Contiguous Packing & Reserved Padding
    
    public static func testLocationPingOptionBContiguousPackingAndRegression() -> Bool {
        print("[Test 19] LocationPing Option B contiguous packing and 12-byte reserved padding...")
        
        let coord = CLLocationCoordinate2D(latitude: 37.774929, longitude: -122.419416)
        let ts = Date(timeIntervalSince1970: 1730007000)
        
        let ping = LocationPingPayload(
            coordinate: coord,
            timestamp: ts,
            accuracy: 6,
            senderInitials: "DNA",
            batteryLevel: 92,
            heading: 240,
            colorCode: MemberColor.skyBlue.rawValue
        )
        
        let data = ping.serialize()
        guard data.count == 30 else {
            print("  FAIL: Option B LocationPing serialized size must be exactly 30 bytes, got \(data.count)")
            return false
        }
        
        // Verify byte positions:
        // Byte 12: accuracy = 6
        guard data[12] == 6 else {
            print("  FAIL: Byte 12 expected accuracy 6, got \(data[12])")
            return false
        }
        // Bytes 13..14: senderInitials "DNA"
        let initialBytes = [data[13], data[14]]
        guard InitialsCodec.decode(initialBytes) == "DNA" else {
            print("  FAIL: Bytes 13..14 initials mismatch")
            return false
        }
        // Byte 15: battery = 92
        guard data[15] == 92 else {
            print("  FAIL: Byte 15 expected battery 92, got \(data[15])")
            return false
        }
        // Byte 16: heading = 240
        guard data[16] == 240 else {
            print("  FAIL: Byte 16 expected heading 240, got \(data[16])")
            return false
        }
        // Byte 17: colorCode = skyBlue
        guard data[17] == MemberColor.skyBlue.rawValue else {
            print("  FAIL: Byte 17 expected colorCode \(MemberColor.skyBlue.rawValue), got \(data[17])")
            return false
        }
        // Bytes 18..29: exactly 12 contiguous zero bytes reserved
        let reservedSlice = data.subdata(in: 18..<30)
        guard reservedSlice.count == 12 && reservedSlice.allSatisfy({ $0 == 0 }) else {
            print("  FAIL: Bytes 18..29 must be 12 zero reserved bytes")
            return false
        }
        
        do {
            let decoded = try LocationPingPayload.deserialize(from: data)
            guard abs(decoded.coordinate.latitude - coord.latitude) < 0.000002,
                  abs(decoded.coordinate.longitude - coord.longitude) < 0.000002,
                  decoded.accuracy == 6,
                  decoded.senderInitials == "DNA",
                  decoded.batteryLevel == 92,
                  decoded.heading == 240,
                  decoded.colorCode == MemberColor.skyBlue.rawValue else {
                print("  FAIL: Decoded Option B fields mismatch")
                return false
            }
            
            // Check underflow
            let truncated = data.prefix(29)
            do {
                _ = try LocationPingPayload.deserialize(from: truncated)
                print("  FAIL: Truncated location ping should throw bufferUnderflow")
                return false
            } catch PacketCodecError.bufferUnderflow {
                // Expected
            }
            
            print("  PASS: Option B contiguous packing (Bytes 0..17) and 12-byte reserved block verified.")
            return true
        } catch {
            print("  FAIL: Deserialization failed: \(error)")
            return false
        }
    }
    
    // MARK: - Test 20: Regression Test for All 8 Packet Types
    
    public static func testAllExistingPacketTypesRegression() -> Bool {
        print("[Test 20] Regression test for all 8 PacketTypes (0x01..0x08)...")
        
        // 1. Verify PacketType raw values are distinct and contiguous 0x01..0x08
        let allTypes = PacketType.allCases
        guard allTypes.count == 8 else {
            print("  FAIL: Expected exactly 8 PacketTypes, got \(allTypes.count)")
            return false
        }
        
        let expectedRawValues: [PacketType: UInt8] = [
            .locationPing: 0x01,
            .sos: 0x02,
            .meetingUpdate: 0x03,
            .routeReq: 0x04,
            .routeResp: 0x05,
            .ack: 0x06,
            .chatMessage: 0x07,
            .uwbTokenExchange: 0x08
        ]
        
        for (pType, expectedRaw) in expectedRawValues {
            guard pType.rawValue == expectedRaw else {
                print("  FAIL: PacketType \(pType) rawValue expected 0x\(String(format: "%02X", expectedRaw)), got 0x\(String(format: "%02X", pType.rawValue))")
                return false
            }
        }
        
        // 2. Verify CleartextEnvelope byte0 for all 8 types with protocol version 3
        let expectedByte0Values: [PacketType: UInt8] = [
            .locationPing: 0x31,
            .sos: 0x32,
            .meetingUpdate: 0x33,
            .routeReq: 0x34,
            .routeResp: 0x35,
            .ack: 0x36,
            .chatMessage: 0x37,
            .uwbTokenExchange: 0x38
        ]
        
        for (pType, expectedByte0) in expectedByte0Values {
            let env = CleartextEnvelope(
                version: PacketConstants.protocolVersion,
                type: pType,
                sessionId: 0x1234,
                sequenceNumber: 1
            )
            let envData = env.serialize()
            guard envData[0] == expectedByte0 else {
                print("  FAIL: Envelope byte 0 for \(pType) expected 0x\(String(format: "%02X", expectedByte0)), got 0x\(String(format: "%02X", envData[0]))")
                return false
            }
            
            do {
                let parsedEnv = try CleartextEnvelope.deserialize(from: envData)
                guard parsedEnv.type == pType else {
                    print("  FAIL: Parsed envelope type mismatch for \(pType)")
                    return false
                }
            } catch {
                print("  FAIL: Failed deserializing envelope for \(pType): \(error)")
                return false
            }
        }
        
        print("  PASS: All 8 PacketTypes, byte 0 encodings, and envelope codecs verified.")
        return true
    }
}
