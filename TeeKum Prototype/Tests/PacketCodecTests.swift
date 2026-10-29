//
//  PacketCodecTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

/// Exhaustive Test Suite for Packet Serialization, Deserialization, and Boundary Verification.
public enum PacketCodecTests {
    
    public static func runAllTests() -> Bool {
        var passed = true
        print("========================================")
        print("RUNNING PROTOCOL V2 PACKET CODEC TEST SUITE (56-BYTE)")
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
        
        // 2. Unsupported protocol version (e.g. 0x01 when 0x02 is required)
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
        let invalidTypeData = Data([0x2F, 0x08, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
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
        let zeroHopLimitData = Data([0x21, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
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
        let hopCountExceededData = Data([0x21, 0x03, 0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
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
            statusCode: .gettingDrinks,
            targetRefId: 0xCAFEBABE,
            senderInitials: "DNA",
            batteryLevel: 85,
            heading: 180
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
                  decoded.statusCode == .gettingDrinks,
                  decoded.targetRefId == 0xCAFEBABE,
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
                statusCode: .available,
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
            action: .accept,
            attendanceStatus: .attending,
            meetingPointId: 0x55556666,
            senderInitials: "SAM",
            landmarkId: 0x00000001
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
                  decoded.landmarkId == 0x00000001 else {
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
        // Envelope: version=2, type=1 (locationPing) -> byte0 = 0x21
        // hopLimit=8, hopCount=0 -> byte1 = 0x80
        // sessionId = 0x0102 -> bytes 2..3 = [0x01, 0x02]
        // sequenceNumber = 0x0A0B0C0D -> bytes 4..7 = [0x0A, 0x0B, 0x0C, 0x0D]
        let envelope = CleartextEnvelope(
            version: 0x02,
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: 0x0102,
            sequenceNumber: 0x0A0B0C0D
        )
        let envBytes = envelope.serialize()
        let expectedEnvHex = "2108000001020a0b0c0d"
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
        
        // Nonce test vector: sessionId (3B) + sequenceNumber (4B) + byte0 (1B) + "TKM2" (4B)
        let nonceBytes = envelope.constructNonce()
        let expectedNonceHex = "0001020a0b0c0d21544b4d32"
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
}
