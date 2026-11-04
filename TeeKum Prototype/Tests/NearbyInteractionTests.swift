//
//  NearbyInteractionTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 04/11/26.
//

import Foundation

/// Exhaustive Test Suite for Ultra-Wideband (UWB) Nearby Interaction,
/// token exchange fragmentation, wire packet roundtrip, and service state transitions.
public enum NearbyInteractionTests {
    
    public static func runAllTests() async -> Bool {
        var passed = true
        print("========================================")
        print("RUNNING NEARBY INTERACTION (UWB) TEST SUITE")
        print("========================================")
        
        if !testUWBTokenExchangePayloadSerialization() { passed = false }
        if !testUWBTokenExchangePayloadAllActions() { passed = false }
        if !testUWBTokenExchangePayloadMalformedLengthRejection() { passed = false }
        if !testMultiFragmentTokenSplittingAndAssembly() { passed = false }
        if !testUWBHopLimitStrictlyDirectLink() { passed = false }
        if await !testNearbyInteractionServiceState() { passed = false }
        
        print("========================================")
        print(passed ? "ALL NEARBY INTERACTION TESTS PASSED!" : "NEARBY INTERACTION TESTS FAILED!")
        print("========================================")
        return passed
    }
    
    // MARK: - Test 1: Wire Payload Serialization & Validation
    
    public static func testUWBTokenExchangePayloadSerialization() -> Bool {
        print("[Test 1] UWBTokenExchangePayload 30-byte serialization and deserialization...")
        let sampleData = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let payload = UWBTokenExchangePayload(
            action: .tokenRequest,
            sequenceId: 42,
            fragmentIndex: 2,
            totalFragments: 5,
            fragmentData: sampleData
        )
        
        let wire = payload.serialize()
        guard wire.count == 30 else {
            print("  FAIL: Expected 30 bytes, got \(wire.count)")
            return false
        }
        
        do {
            let deserialized = try UWBTokenExchangePayload.deserialize(from: wire)
            guard deserialized.action == .tokenRequest,
                  deserialized.sequenceId == 42,
                  deserialized.fragmentIndex == 2,
                  deserialized.totalFragments == 5,
                  deserialized.dataLength == 8,
                  deserialized.fragmentData == sampleData else {
                print("  FAIL: Deserialized payload does not match original fields.")
                return false
            }
            print("  PASS: 30-byte payload roundtrip verified.")
            return true
        } catch {
            print("  FAIL: Deserialization threw: \(error)")
            return false
        }
    }
    
    // MARK: - Test 2: All Actions Coverage
    
    public static func testUWBTokenExchangePayloadAllActions() -> Bool {
        print("[Test 2] UWBTokenExchangePayload all action codes roundtrip...")
        for action in UWBAction.allCases {
            let p = UWBTokenExchangePayload(
                action: action,
                sequenceId: 10,
                fragmentIndex: 0,
                totalFragments: 1,
                fragmentData: Data()
            )
            let wire = p.serialize()
            do {
                let decoded = try UWBTokenExchangePayload.deserialize(from: wire)
                guard decoded.action == action, decoded.dataLength == 0 else {
                    print("  FAIL: Action \(action) failed roundtrip.")
                    return false
                }
            } catch {
                print("  FAIL: Deserializing action \(action) threw: \(error)")
                return false
            }
        }
        print("  PASS: All UWB action codes (.tokenRequest, .tokenResponse, .stopRanging) verified.")
        return true
    }
    
    // MARK: - Test 3: Malformed Length Rejection
    
    public static func testUWBTokenExchangePayloadMalformedLengthRejection() -> Bool {
        print("[Test 3] Rejecting malformed payloads with invalid sizes...")
        let badData = Data(repeating: 0xFF, count: 29) // 29 instead of 30 bytes
        do {
            _ = try UWBTokenExchangePayload.deserialize(from: badData)
            print("  FAIL: Expected error for 29-byte payload, but succeeded.")
            return false
        } catch PacketCodecError.invalidPacketSize(let expected, let actual) {
            guard expected == 30, actual == 29 else {
                print("  FAIL: Unexpected error parameters: expected \(expected), actual \(actual)")
                return false
            }
            print("  PASS: Malformed 29-byte payload correctly rejected.")
            return true
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            return false
        }
    }
    
    // MARK: - Test 4: Multi-Fragment Token Splitting & Assembly
    
    public static func testMultiFragmentTokenSplittingAndAssembly() -> Bool {
        print("[Test 4] Multi-fragment token chunking (297 bytes across 25-byte fragments)...")
        // Simulate a 297-byte raw archived NIDiscoveryToken payload
        var originalTokenData = Data()
        for i in 0..<297 {
            originalTokenData.append(UInt8(i % 256))
        }
        
        let chunkSize = UWBTokenExchangePayload.maxFragmentDataBytes // 25 bytes
        let totalCount = UInt8(ceil(Double(originalTokenData.count) / Double(chunkSize)))
        guard totalCount == 12 else {
            print("  FAIL: Expected 12 fragments for 297 bytes, got \(totalCount)")
            return false
        }
        
        var fragments: [UWBTokenExchangePayload] = []
        for idx in 0..<totalCount {
            let start = Int(idx) * chunkSize
            let end = min(start + chunkSize, originalTokenData.count)
            let chunk = originalTokenData.subdata(in: start..<end)
            
            let p = UWBTokenExchangePayload(
                action: .tokenRequest,
                sequenceId: 99,
                fragmentIndex: idx,
                totalFragments: totalCount,
                fragmentData: chunk
            )
            fragments.append(p)
        }
        
        // Serialize and deserialize all wire frames
        var wirePackets: [Data] = []
        for f in fragments {
            let wire = f.serialize()
            guard wire.count == 30 else {
                print("  FAIL: Fragment wire size \(wire.count) != 30")
                return false
            }
            wirePackets.append(wire)
        }
        
        // Reassemble fragments in receiver buffer
        var assembledData = Data()
        for wire in wirePackets {
            do {
                let decoded = try UWBTokenExchangePayload.deserialize(from: wire)
                assembledData.append(decoded.fragmentData)
            } catch {
                print("  FAIL: Reassembly decode failed: \(error)")
                return false
            }
        }
        
        guard assembledData.count == originalTokenData.count, assembledData == originalTokenData else {
            print("  FAIL: Reassembled data did not match original token bytes.")
            return false
        }
        print("  PASS: 12-fragment token chunking and byte-perfect reassembly verified.")
        return true
    }
    
    // MARK: - Test 5: Hop Limit & Direct Link Invariant
    
    public static func testUWBHopLimitStrictlyDirectLink() -> Bool {
        print("[Test 5] UWB direct 1-hop limit enforcement...")
        guard PacketConstants.uwbHopLimit == 1 else {
            print("  FAIL: PacketConstants.uwbHopLimit = \(PacketConstants.uwbHopLimit), expected 1")
            return false
        }
        print("  PASS: UWB hop limit strictly enforced to 1.")
        return true
    }
    
    // MARK: - Test 6: NearbyInteractionService State
    
    @MainActor
    public static func testNearbyInteractionServiceState() async -> Bool {
        print("[Test 6] NearbyInteractionService initialization and state machine...")
        let service = NearbyInteractionService.shared
        
        if service.isSupported {
            guard service.rangingState == .idle || service.rangingState == .active else {
                print("  FAIL: Supported service has unexpected state: \(service.rangingState)")
                return false
            }
            print("  PASS: Service active on supported hardware.")
        } else {
            guard service.rangingState == .unsupported else {
                print("  FAIL: Unsupported service should be in .unsupported state, got \(service.rangingState)")
                return false
            }
            print("  PASS: Service gracefully reported .unsupported on hardware without U1/U2.")
        }
        return true
    }
}
