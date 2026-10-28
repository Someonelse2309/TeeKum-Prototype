//
//  PacketCodecTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

/// Self-contained verification suite for the 56-Byte Wire Packet Codec,
/// coordinate quantization, boundary values, error conditions, and deterministic vectors.
public struct PacketCodecTests {
    
    public static func runAllTests() -> Bool {
        print("--- [PacketCodecTests] Running Verification Suite ---")
        var passed = true
        
        passed = passed && testEnvelopeCodec()
        passed = passed && testEnvelopeValidationAndErrors()
        passed = passed && testSequenceNumberPartitioning()
        passed = passed && testWirePacketLayoutAndSizeValidation()
        passed = passed && testLocationPingQuantization()
        passed = passed && testCoordinateBoundaryValues()
        passed = passed && testCoordinateOutOfRangeValidation()
        passed = passed && testSOSPayloadCodec()
        passed = passed && testMeetingUpdatePayloadCodec()
        passed = passed && testACKPayloadCodec()
        passed = passed && testPhase2RoutePayloads()
        passed = passed && testDeterministicTestVector()
        passed = passed && testServerlessInviteURL()
        
        if passed {
            print("--- [PacketCodecTests] ALL TESTS PASSED SUCCESSFULLY! ---")
        } else {
            print("--- [PacketCodecTests] SOME TESTS FAILED! ---")
        }
        return passed
    }
    
    // MARK: - Test 1: Cleartext Envelope Codec
    
    public static func testEnvelopeCodec() -> Bool {
        print("[Test 1] CleartextEnvelope 10-byte serialization/deserialization...")
        let original = CleartextEnvelope(
            version: 0x01,
            type: .locationPing,
            hopLimit: 8,
            hopCount: 2,
            sessionId: 0xDEADBEEF,
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
            print("  PASS: Envelope serialized and deserialized accurately.")
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
        let shortData = Data([0x11, 0x80, 0x12, 0x34])
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
        
        // 2. Unsupported protocol version (e.g. 0x02)
        let invalidVersionData = Data([0x21, 0x80, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
        do {
            _ = try CleartextEnvelope.deserialize(from: invalidVersionData)
            print("  FAIL: Should have thrown unsupportedVersion.")
            return false
        } catch PacketCodecError.unsupportedVersion(let v) where v == 2 {
            // Expected
        } catch {
            print("  FAIL: Wrong error for invalid version: \(error)")
            return false
        }
        
        // 3. Unknown packet type (e.g. 0x00 or 0x0F)
        let invalidTypeData = Data([0x1F, 0x80, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
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
        let zeroHopLimitData = Data([0x11, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
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
        let hopCountExceededData = Data([0x11, 0x35, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
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
            sessionId: 0x12345678,
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
        // Real-world venue coordinate (Empire Polo Club, Indio, CA - Coachella)
        let coordinate = CLLocationCoordinate2D(latitude: 33.680312, longitude: -116.237409)
        let timestamp = Date(timeIntervalSince1970: 1729000000)
        
        let payload = LocationPingPayload(
            coordinate: coordinate,
            timestamp: timestamp,
            accuracy: 8,
            statusCode: .gettingDrinks,
            targetRefId: 0xCAFEBABE,
            senderId: 0x11223344,
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
            
            // Int32 precision is 1e-6 degrees (~11cm at equator)
            guard latDiff < 0.000002 && lonDiff < 0.000002 else {
                print("  FAIL: Quantization precision loss excessive: latDiff=\(latDiff), lonDiff=\(lonDiff)")
                return false
            }
            guard decoded.accuracy == 8,
                  decoded.statusCode == .gettingDrinks,
                  decoded.targetRefId == 0xCAFEBABE,
                  decoded.senderId == 0x11223344,
                  decoded.batteryLevel == 85,
                  decoded.heading == 180 else {
                print("  FAIL: Metadata mismatch on decoded payload.")
                return false
            }
            print("  PASS: Coordinates quantized and dequantized with <11cm resolution.")
            return true
        } catch {
            print("  FAIL: Exception caught: \(error)")
            return false
        }
    }
    
    // MARK: - Test 6: Coordinate Boundary Values (Equator, Prime Meridian, Poles)
    
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
                senderId: 0x1,
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
                print("  FAIL: Exception deserializing boundary coordinate: \(error)")
                return false
            }
        }
        
        print("  PASS: Boundary coordinates round-trip with high fidelity.")
        return true
    }
    
    // MARK: - Test 7: Coordinate Out-of-Range Validation
    
    public static func testCoordinateOutOfRangeValidation() -> Bool {
        print("[Test 7] Coordinate out-of-range rejection...")
        
        // Encode raw Int32 representing latitude 91.0 degrees (91_000_000)
        var invalidData = Data(capacity: 30)
        var invalidLat = Int32(91_000_000).bigEndian
        var validLon = Int32(0).bigEndian
        var ts = UInt32(1700000000).bigEndian
        invalidData.append(Data(bytes: &invalidLat, count: 4))
        invalidData.append(Data(bytes: &validLon, count: 4))
        invalidData.append(Data(bytes: &ts, count: 4))
        invalidData.append(Data(repeating: 0, count: 18)) // remaining 18 bytes
        
        do {
            _ = try LocationPingPayload.deserialize(from: invalidData)
            print("  FAIL: Should have thrown invalidCoordinateRange for latitude 91.0.")
            return false
        } catch PacketCodecError.invalidCoordinateRange(let lat, _) where lat > 90.0 {
            // Expected
        } catch {
            print("  FAIL: Wrong error for latitude out of range: \(error)")
            return false
        }
        
        // Encode raw Int32 representing longitude -181.0 degrees (-181_000_000)
        var invalidLonData = Data(capacity: 30)
        var validLat = Int32(0).bigEndian
        var invalidLon = Int32(-181_000_000).bigEndian
        invalidLonData.append(Data(bytes: &validLat, count: 4))
        invalidLonData.append(Data(bytes: &invalidLon, count: 4))
        invalidLonData.append(Data(bytes: &ts, count: 4))
        invalidLonData.append(Data(repeating: 0, count: 18))
        
        do {
            _ = try LocationPingPayload.deserialize(from: invalidLonData)
            print("  FAIL: Should have thrown invalidCoordinateRange for longitude -181.0.")
            return false
        } catch PacketCodecError.invalidCoordinateRange(_, let lon) where lon < -180.0 {
            // Expected
        } catch {
            print("  FAIL: Wrong error for longitude out of range: \(error)")
            return false
        }
        
        print("  PASS: Out-of-bounds geographic coordinates rejected properly.")
        return true
    }
    
    // MARK: - Test 8: SOS Payload Codec
    
    public static func testSOSPayloadCodec() -> Bool {
        print("[Test 8] SOSPayload urgent emergency serialization...")
        let coordinate = CLLocationCoordinate2D(latitude: -6.2088, longitude: 106.8456)
        let timestamp = Date(timeIntervalSince1970: 1729000100)
        let payload = SOSPayload(
            coordinate: coordinate,
            timestamp: timestamp,
            accuracy: 5,
            sosEventId: 0x99887766,
            senderId: 0xAABBCCDD,
            emergencyType: .medical,
            batteryLevel: 42
        )
        
        let data = payload.serialize()
        guard data.count == 30 else {
            print("  FAIL: Expected 30 bytes, got \(data.count)")
            return false
        }
        
        do {
            let decoded = try SOSPayload.deserialize(from: data)
            guard decoded.emergencyType == .medical,
                  decoded.sosEventId == 0x99887766,
                  decoded.senderId == 0xAABBCCDD,
                  decoded.batteryLevel == 42 else {
                print("  FAIL: SOS decoded payload fields do not match.")
                return false
            }
            print("  PASS: SOS urgent payload serialized and deserialized accurately.")
            return true
        } catch {
            print("  FAIL: Exception caught: \(error)")
            return false
        }
    }
    
    // MARK: - Test 9: Meeting Update Codec
    
    public static func testMeetingUpdatePayloadCodec() -> Bool {
        print("[Test 9] MeetingUpdatePayload rendezvous proposal & attendance...")
        let coordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let meetupTime = Date(timeIntervalSince1970: 1729005000)
        let payload = MeetingUpdatePayload(
            coordinate: coordinate,
            meetupTime: meetupTime,
            action: .accept,
            attendanceStatus: .attending,
            meetingPointId: 0x55554444,
            senderId: 0x12345678,
            landmarkId: 0x00000002
        )
        
        let data = payload.serialize()
        guard data.count == 30 else {
            print("  FAIL: Expected 30 bytes, got \(data.count)")
            return false
        }
        
        do {
            let decoded = try MeetingUpdatePayload.deserialize(from: data)
            guard decoded.action == .accept,
                  decoded.attendanceStatus == .attending,
                  decoded.meetingPointId == 0x55554444,
                  decoded.senderId == 0x12345678,
                  decoded.landmarkId == 0x00000002 else {
                print("  FAIL: Meeting update fields do not match.")
                return false
            }
            print("  PASS: Meeting update payload verified.")
            return true
        } catch {
            print("  FAIL: Exception caught: \(error)")
            return false
        }
    }
    
    // MARK: - Test 10: Delivery ACK Codec
    
    public static func testACKPayloadCodec() -> Bool {
        print("[Test 10] ACKPayload receipt confirmation...")
        let ackTimestamp = Date(timeIntervalSince1970: 1729000200)
        let payload = ACKPayload(
            ackedSeqNumber: 101,
            ackedSenderId: 0x11112222,
            ackTimestamp: ackTimestamp,
            ackStatus: .deliveredToFriend,
            receivedRssi: -68,
            originalEventId: 0x99887766,
            responderId: 0x33334444
        )
        
        let data = payload.serialize()
        guard data.count == 30 else {
            print("  FAIL: Expected 30 bytes, got \(data.count)")
            return false
        }
        
        do {
            let decoded = try ACKPayload.deserialize(from: data)
            guard decoded.ackedSeqNumber == 101,
                  decoded.ackedSenderId == 0x11112222,
                  decoded.ackStatus == .deliveredToFriend,
                  decoded.receivedRssi == -68,
                  decoded.originalEventId == 0x99887766,
                  decoded.responderId == 0x33334444 else {
                print("  FAIL: ACK decoded fields do not match.")
                return false
            }
            print("  PASS: Delivery ACK payload verified.")
            return true
        } catch {
            print("  FAIL: Exception caught: \(error)")
            return false
        }
    }
    
    // MARK: - Test 11: Phase 2 Route Payloads (RouteReq & RouteResp)
    
    public static func testPhase2RoutePayloads() -> Bool {
        print("[Test 11] Phase 2 RouteReq & RouteResp payload codecs...")
        let req = RouteReqPayload(originatorId: 0x1111, targetMemberId: 0x2222, discoveryNonce: 0x3333, routeCost: 2)
        let reqData = req.serialize()
        guard reqData.count == 30 else {
            print("  FAIL: RouteReq must be 30 bytes, got \(reqData.count)")
            return false
        }
        
        do {
            let decodedReq = try RouteReqPayload.deserialize(from: reqData)
            guard decodedReq.originatorId == 0x1111,
                  decodedReq.targetMemberId == 0x2222,
                  decodedReq.discoveryNonce == 0x3333,
                  decodedReq.routeCost == 2 else {
                print("  FAIL: RouteReq decoded fields mismatch.")
                return false
            }
        } catch {
            print("  FAIL: RouteReq deserialization failed: \(error)")
            return false
        }
        
        let resp = RouteRespPayload(originatorId: 0x1111, targetMemberId: 0x2222, discoveryNonce: 0x3333, routeCost: 3)
        let respData = resp.serialize()
        guard respData.count == 30 else {
            print("  FAIL: RouteResp must be 30 bytes, got \(respData.count)")
            return false
        }
        do {
            let decodedResp = try RouteRespPayload.deserialize(from: respData)
            guard decodedResp.originatorId == 0x1111,
                  decodedResp.targetMemberId == 0x2222,
                  decodedResp.discoveryNonce == 0x3333,
                  decodedResp.routeCost == 3 else {
                print("  FAIL: RouteResp decoded fields mismatch.")
                return false
            }
        } catch {
            print("  FAIL: RouteResp deserialization failed: \(error)")
            return false
        }
        
        print("  PASS: Phase 2 Route discovery payloads serialized and verified.")
        return true
    }
    
    // MARK: - Test 12: Deterministic Test Vector
    
    public static func testDeterministicTestVector() -> Bool {
        print("[Test 12] Deterministic test vector serialization...")
        // Known fixed inputs:
        // Envelope: version=1, type=1 (locationPing) -> byte0 = 0x11
        // hopLimit=8, hopCount=0 -> byte1 = 0x80
        // sessionId = 0x01020304 -> bytes 2..5 = [0x01, 0x02, 0x03, 0x04]
        // sequenceNumber = 0x0A0B0C0D -> bytes 6..9 = [0x0A, 0x0B, 0x0C, 0x0D]
        let envelope = CleartextEnvelope(
            version: 0x01,
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: 0x01020304,
            sequenceNumber: 0x0A0B0C0D
        )
        let envBytes = envelope.serialize()
        let expectedEnvHex = "1180010203040a0b0c0d"
        let actualEnvHex = envBytes.map { String(format: "%02x", $0) }.joined()
        guard actualEnvHex == expectedEnvHex else {
            print("  FAIL: Envelope test vector mismatch: expected \(expectedEnvHex), got \(actualEnvHex)")
            return false
        }
        
        // AAD test vector: masked hopCount must be 0x80
        let aadBytes = envelope.authenticatedAssociatedData()
        let actualAadHex = aadBytes.map { String(format: "%02x", $0) }.joined()
        guard actualAadHex == expectedEnvHex else {
            print("  FAIL: AAD test vector mismatch: expected \(expectedEnvHex), got \(actualAadHex)")
            return false
        }
        
        // Nonce test vector: sessionId (4B) + sequenceNumber (4B) + byte0 (1B) + "TKM" (3B)
        // [0x01, 0x02, 0x03, 0x04, 0x0A, 0x0B, 0x0C, 0x0D, 0x11, 0x54, 0x4B, 0x4D]
        let nonceBytes = envelope.constructNonce()
        let expectedNonceHex = "010203040a0b0c0d11544b4d"
        let actualNonceHex = nonceBytes.map { String(format: "%02x", $0) }.joined()
        guard actualNonceHex == expectedNonceHex else {
            print("  FAIL: Nonce test vector mismatch: expected \(expectedNonceHex), got \(actualNonceHex)")
            return false
        }
        
        print("  PASS: Deterministic envelope, AAD, and Nonce vectors verified bit-for-bit.")
        return true
    }
    
    // MARK: - Test 13: Serverless Invite Link & QR String
    
    public static func testServerlessInviteURL() -> Bool {
        print("[Test 13] Serverless invite link (teekum://join#key=...) generation and parsing...")
        let keyData = Data((0..<32).map { UInt8($0) })
        let session = GroupSession(
            sessionId: 0xABCDEF01,
            sessionName: "Summer Fest Crew",
            symmetricKeyData: keyData,
            localMemberName: "Nicho",
            isHost: true
        )
        
        let url = session.inviteURL()
        guard let invite = GroupSession.parseInvite(from: url) else {
            print("  FAIL: Failed to parse generated invite URL: \(url)")
            return false
        }
        
        guard invite.sessionId == 0xABCDEF01,
              invite.sessionName == "Summer Fest Crew",
              invite.keyData == keyData else {
            print("  FAIL: Decoded invite fields do not match original.")
            return false
        }
        
        print("  PASS: Serverless URL fragment invite accurately generated and parsed.")
        return true
    }
}
