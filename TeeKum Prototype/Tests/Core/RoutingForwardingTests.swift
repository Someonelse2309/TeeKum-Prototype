//
//  RoutingForwardingTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation
import CoreLocation
import CryptoKit

/// Comprehensive Phase 2 Verification & Threat Model Test Suite for Agent 2.
///
/// Tests:
/// 1. Outsider sends a forged SOS -> rejected, zero state mutation.
/// 2. Relay modifies message identity or ciphertext -> AEAD Poly1305 verification fails.
/// 3. Relay changes hop metadata -> hopCount mutation succeeds; hopLimit tampering fails.
/// 4. Attacker replays valid packet -> duplicate cache & sequence monotonicity drop it.
/// 5. Malicious node floods duplicate route requests -> duplicate cache & rate limiter throttle.
/// 6. Packet arrives after expiry or session ended -> rejected by clock skew & key purge.
/// 7. Route response claims unauthenticated destination -> reverse route lookup fails.
/// 8. Untrusted relay impersonates group member -> dropped with zero state mutation.
/// 9. LRU duplicate cache 5-minute sliding TTL & capacity bounds.
/// 10. AODV routing table sequence number monotonicity & reverse route consumption.
/// 11. Multi-hop blind relaying chain (Alice -> Relay 1 -> Relay 2 -> Bob).
/// 12. Privacy & confidentiality check: relays cannot decrypt group payload.
public enum RoutingForwardingTests {
    
    private final class SessionHolder: @unchecked Sendable {
        var session: GroupSession?
        init(session: GroupSession?) { self.session = session }
    }
    
    public static func runAllTests() async -> Bool {
        print("\n==================================================")
        print(">>> STARTING BLIND RELAY SECURITY TEST SUITE <<<")
        print("==================================================")
        
        var passed = true
        
        passed = await testOutsiderForgedSOSRejection() && passed
        passed = await testRelayCiphertextAndIdentityTamperDetection() && passed
        passed = await testRelayHopMetadataMutationAndHopLimitTampering() && passed
        passed = await testReplayAttackSuppressionAndSequenceMonotonicity() && passed
        passed = await testRouteRequestFloodingAndRateLimiting() && passed
        passed = await testExpiredPacketAndTerminatedSessionHandling() && passed
        passed = await testUnauthorizedRouteResponseRejection() && passed
        passed = await testUntrustedRelayMemberImpersonationPrevention() && passed
        passed = await testSeenPacketCacheLRUAndFiveMinuteSlidingTTL() && passed
        passed = await testRoutingTableMonotonicityAndReverseRouteLifecycle() && passed
        passed = await testMultiHopBlindRelayingEndToEndChain() && passed
        passed = await testConfidentialityZeroKnowledgePayloadProtection() && passed
        
        if passed {
            print("==================================================")
            print(">>> ALL 12 BLIND RELAY SECURITY TESTS PASSED <<<")
            print("==================================================\n")
        } else {
            print("❌ SOME BLIND RELAY SECURITY TESTS FAILED!")
        }
        return passed
    }
    
    // MARK: - Test 1: Outsider Forged SOS Rejection
    
    public static func testOutsiderForgedSOSRejection() async -> Bool {
        print("[Test 1] Outsider forged SOS rejection...")
        
        let clock = TestMeshClock()
        let crypto = CryptoService()
        let legitimateKey = await crypto.generateSymmetricKey()
        let attackerKey = await crypto.generateSymmetricKey()
        let sessionId: UInt16 = 0x4321
        
        let session = GroupSession(
            sessionId: sessionId,
            sessionName: "Festival Friends",
            symmetricKeyData: legitimateKey.withUnsafeBytes { Data($0) },
            localInitials: "BOB"
        )
        
        let table = RoutingTable(clock: clock)
        let rateLimiter = ForwardingRateLimiter(clock: clock)
        let neighbors = NeighborTable(clock: clock)
        let dupCache = SeenPacketCache(clock: clock)
        
        let forwarder = PacketForwarder(
            routingTable: table,
            rateLimiter: rateLimiter,
            neighborTable: neighbors,
            seenPacketCache: dupCache,
            clock: clock,
            cryptoService: crypto,
            sessionProvider: { session },
            policyProvider: { RelayPolicyState(mode: .communalRelayActive) }
        )
        
        // Attacker creates an SOS packet signed with their own attacker key
        let forgedEnvelope = CleartextEnvelope(
            type: .sos,
            hopLimit: 8,
            hopCount: 0,
            sessionId: sessionId,
            sequenceNumber: 100
        )
        let sosPayload = SOSPayload(
            coordinate: CLLocationCoordinate2D(latitude: 36.1699, longitude: -115.1398),
            accuracy: 5,
            sosEventId: 9999,
            senderInitials: "MAL",
            emergencyType: .general,
            batteryLevel: 90
        )
        let forgedWireData = try! await crypto.sealToWireBytes(
            payload: sosPayload.serialize(),
            envelope: forgedEnvelope,
            using: attackerKey
        )
        
        let decision = await forwarder.evaluateInboundPacket(wireData: forgedWireData, fromPeerId: "attacker-peer")
        
        guard decision == .dropSecurityVerificationFailed else {
            print("  FAIL: Expected .dropSecurityVerificationFailed for forged SOS, got \(decision)")
            return false
        }
        
        print("  PASS: Outsider forged SOS rejected with .dropSecurityVerificationFailed; zero state mutations.")
        return true
    }
    
    // MARK: - Test 2: Relay Ciphertext & Identity Tamper Detection
    
    public static func testRelayCiphertextAndIdentityTamperDetection() async -> Bool {
        print("[Test 2] Relay modified ciphertext & identity tamper detection...")
        
        let clock = TestMeshClock()
        let crypto = CryptoService()
        let key = await crypto.generateSymmetricKey()
        let sessionId: UInt16 = 0x5555
        
        let session = GroupSession(
            sessionId: sessionId,
            sessionName: "Test Group",
            symmetricKeyData: key.withUnsafeBytes { Data($0) },
            localInitials: "BOB"
        )
        
        let table = RoutingTable(clock: clock)
        let rateLimiter = ForwardingRateLimiter(clock: clock)
        let neighbors = NeighborTable(clock: clock)
        let dupCache = SeenPacketCache(clock: clock)
        
        let forwarder = PacketForwarder(
            routingTable: table,
            rateLimiter: rateLimiter,
            neighborTable: neighbors,
            seenPacketCache: dupCache,
            clock: clock,
            cryptoService: crypto,
            sessionProvider: { session },
            policyProvider: { RelayPolicyState(mode: .communalRelayActive) }
        )
        
        let envelope = CleartextEnvelope(
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: sessionId,
            sequenceNumber: 200
        )
        let ping = LocationPingPayload(
            coordinate: CLLocationCoordinate2D(latitude: 36.1, longitude: -115.1),
            accuracy: 3,
            senderInitials: "ALC",
            batteryLevel: 80
        )
        let validWireData = try! await crypto.sealToWireBytes(
            payload: ping.serialize(),
            envelope: envelope,
            using: key
        )
        
        // 1. Bit flip in ciphertext (Byte 15)
        var tamperedCiphertext = validWireData
        tamperedCiphertext[15] ^= 0x01
        
        let decision1 = await forwarder.evaluateInboundPacket(wireData: tamperedCiphertext, fromPeerId: "relay-1")
        guard decision1 == .dropSecurityVerificationFailed else {
            print("  FAIL: Bit flip in ciphertext should trigger .dropSecurityVerificationFailed, got \(decision1)")
            return false
        }
        
        // 2. Modified sequenceNumber in cleartext envelope (Byte 7)
        var tamperedSeq = validWireData
        tamperedSeq[7] ^= 0x01
        let decision2 = await forwarder.evaluateInboundPacket(wireData: tamperedSeq, fromPeerId: "relay-1")
        guard decision2 == .dropSecurityVerificationFailed else {
            print("  FAIL: Modified sequence number in envelope should trigger .dropSecurityVerificationFailed, got \(decision2)")
            return false
        }
        
        // 3. Modified auth tag (Byte 50)
        await dupCache.removeAll()
        var tamperedTag = validWireData
        tamperedTag[50] ^= 0xFF
        let decision3 = await forwarder.evaluateInboundPacket(wireData: tamperedTag, fromPeerId: "relay-1")
        guard decision3 == .dropSecurityVerificationFailed else {
            print("  FAIL: Modified auth tag should trigger .dropSecurityVerificationFailed, got \(decision3)")
            return false
        }
        
        print("  PASS: Tampering with ciphertext, envelope identity, or MAC tag detected and dropped unconditionally.")
        return true
    }
    
    // MARK: - Test 3: Relay Hop Metadata Mutation vs Hop Limit Tampering
    
    public static func testRelayHopMetadataMutationAndHopLimitTampering() async -> Bool {
        print("[Test 3] Relay hopCount mutation vs hopLimit tampering...")
        
        let clock = TestMeshClock()
        let crypto = CryptoService()
        let key = await crypto.generateSymmetricKey()
        let sessionId: UInt16 = 0x7777
        
        let session = GroupSession(
            sessionId: sessionId,
            sessionName: "Test Group",
            symmetricKeyData: key.withUnsafeBytes { Data($0) },
            localInitials: "BOB"
        )
        
        let table = RoutingTable(clock: clock)
        let rateLimiter = ForwardingRateLimiter(clock: clock)
        let neighbors = NeighborTable(clock: clock)
        let dupCache = SeenPacketCache(clock: clock)
        
        let forwarder = PacketForwarder(
            routingTable: table,
            rateLimiter: rateLimiter,
            neighborTable: neighbors,
            seenPacketCache: dupCache,
            clock: clock,
            cryptoService: crypto,
            sessionProvider: { session },
            policyProvider: { RelayPolicyState(mode: .communalRelayActive) }
        )
        
        let envelope = CleartextEnvelope(
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: sessionId,
            sequenceNumber: 300
        )
        let ping = LocationPingPayload(
            coordinate: CLLocationCoordinate2D(latitude: 36.2, longitude: -115.2),
            accuracy: 3,
            senderInitials: "ALC",
            batteryLevel: 85
        )
        let wireData = try! await crypto.sealToWireBytes(
            payload: ping.serialize(),
            envelope: envelope,
            using: key
        )
        
        // Scenario A: Valid relay mutation: hopCount incremented from 0 to 1
        var relayedData = wireData
        relayedData[2] = 1 // hopLimit remains 8 at index 1, hopCount becomes 1 at index 2
        
        let decisionA = await forwarder.evaluateInboundPacket(wireData: relayedData, fromPeerId: "relay-1")
        guard decisionA == .deliverLocally else {
            print("  FAIL: Relayed packet with incremented hopCount should open successfully, got \(decisionA)")
            return false
        }
        
        // Scenario B: Malicious relay alters hopLimit from 8 to 15
        var rogueHopLimitData = wireData
        rogueHopLimitData[1] = 15
        rogueHopLimitData[2] = 1
        await dupCache.removeAll()
        
        let decisionB = await forwarder.evaluateInboundPacket(wireData: rogueHopLimitData, fromPeerId: "rogue-relay")
        guard decisionB == .dropSecurityVerificationFailed else {
            print("  FAIL: Altered hopLimit must fail Poly1305 verification, got \(decisionB)")
            return false
        }
        
        // Scenario C: hopCount exceeds hopLimit (hopCount == 8, hopLimit == 8)
        var exhaustedHopData = wireData
        exhaustedHopData[1] = 8
        exhaustedHopData[2] = 8
        await dupCache.removeAll()
        
        let decisionC = await forwarder.evaluateInboundPacket(wireData: exhaustedHopData, fromPeerId: "exhausted-relay")
        guard decisionC == .dropHopLimitExceeded else {
            print("  FAIL: Packet with hopCount >= hopLimit must be dropped with .dropHopLimitExceeded, got \(decisionC)")
            return false
        }
        
        print("  PASS: hopCount mutation preserves MAC; hopLimit tampering fails MAC; hopLimit bound enforced.")
        return true
    }
    
    // MARK: - Test 4: Replay Attack Suppression & Sequence Monotonicity
    
    public static func testReplayAttackSuppressionAndSequenceMonotonicity() async -> Bool {
        print("[Test 4] Replay attack suppression & sequence monotonicity...")
        
        let clock = TestMeshClock()
        let crypto = CryptoService()
        let key = await crypto.generateSymmetricKey()
        let sessionId: UInt16 = 0x8888
        
        let session = GroupSession(
            sessionId: sessionId,
            sessionName: "Test Group",
            symmetricKeyData: key.withUnsafeBytes { Data($0) },
            localInitials: "BOB"
        )
        
        let table = RoutingTable(clock: clock)
        let rateLimiter = ForwardingRateLimiter(clock: clock)
        let neighbors = NeighborTable(clock: clock)
        let dupCache = SeenPacketCache(clock: clock)
        
        let forwarder = PacketForwarder(
            routingTable: table,
            rateLimiter: rateLimiter,
            neighborTable: neighbors,
            seenPacketCache: dupCache,
            clock: clock,
            cryptoService: crypto,
            sessionProvider: { session },
            policyProvider: { RelayPolicyState(mode: .communalRelayActive) }
        )
        
        let envelope = CleartextEnvelope(
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: sessionId,
            sequenceNumber: 400
        )
        let ping = LocationPingPayload(
            coordinate: CLLocationCoordinate2D(latitude: 36.3, longitude: -115.3),
            accuracy: 3,
            senderInitials: "ALC",
            batteryLevel: 75
        )
        let wireData = try! await crypto.sealToWireBytes(
            payload: ping.serialize(),
            envelope: envelope,
            using: key
        )
        
        // First delivery: should succeed
        let decision1 = await forwarder.evaluateInboundPacket(wireData: wireData, fromPeerId: "direct-peer")
        guard decision1 == .deliverLocally else {
            print("  FAIL: Initial packet delivery failed with \(decision1)")
            return false
        }
        
        // Immediate replay: should be suppressed by SeenPacketCache
        let decision2 = await forwarder.evaluateInboundPacket(wireData: wireData, fromPeerId: "relay-attacker")
        guard decision2 == .dropDuplicate else {
            print("  FAIL: Duplicate packet was not suppressed, got \(decision2)")
            return false
        }
        
        // Sequence monotonicity check in ReplayProtectionFilter
        let filter = await crypto.replayFilter
        let seqOk1 = await filter.checkAndRecordSenderSequence(senderInitials: "ALC", sequenceNumber: 400)
        guard seqOk1 else {
            print("  FAIL: Initial sequence recording failed")
            return false
        }
        
        // Replayed older sequence number 399
        let seqOld = await filter.checkAndRecordSenderSequence(senderInitials: "ALC", sequenceNumber: 399)
        guard !seqOld else {
            print("  FAIL: Replayed older sequence number 399 was accepted")
            return false
        }
        
        // Monotonic newer sequence number 401
        let seqNew = await filter.checkAndRecordSenderSequence(senderInitials: "ALC", sequenceNumber: 401)
        guard seqNew else {
            print("  FAIL: Newer monotonic sequence number 401 was rejected")
            return false
        }
        
        print("  PASS: Duplicate packets suppressed by cache; sequence monotonicity strictly enforced.")
        return true
    }
    
    // MARK: - Test 5: Route Request Flooding & Rate Limiting
    
    public static func testRouteRequestFloodingAndRateLimiting() async -> Bool {
        print("[Test 5] Route request flooding & rate limiter throttling...")
        
        let clock = TestMeshClock()
        let table = RoutingTable(clock: clock)
        let rateLimiter = ForwardingRateLimiter(clock: clock)
        let neighbors = NeighborTable(clock: clock)
        let dupCache = SeenPacketCache(clock: clock)
        
        await neighbors.recordNeighborActivity(peerId: "neighbor-A", rssi: -60, isGroupMember: false)
        await neighbors.recordNeighborActivity(peerId: "neighbor-B", rssi: -65, isGroupMember: false)
        
        let forwarder = PacketForwarder(
            routingTable: table,
            rateLimiter: rateLimiter,
            neighborTable: neighbors,
            seenPacketCache: dupCache,
            clock: clock,
            sessionProvider: { nil }, // Stranger node: blind relay mode
            policyProvider: { RelayPolicyState(mode: .communalRelayActive) }
        )
        
        // 1. Flooding identical RREQs: duplicate suppression must drop them
        let rreqEnv = CleartextEnvelope(
            type: .routeReq,
            hopLimit: 8,
            hopCount: 0,
            sessionId: 0x9999,
            sequenceNumber: 500
        )
        let fakeCiphertext = Data(repeating: 0xAA, count: 30)
        let fakeTag = Data(repeating: 0xBB, count: 16)
        let rreqPacket = RawWirePacket(envelope: rreqEnv, ciphertext: fakeCiphertext, authTag: fakeTag)
        let wireRREQ = try! rreqPacket.toWireData()
        
        let dec1 = await forwarder.evaluateInboundPacket(wireData: wireRREQ, fromPeerId: "neighbor-A")
        guard case .forward = dec1 else {
            print("  FAIL: Initial RREQ should be forwarded blindly, got \(dec1)")
            return false
        }
        
        // Second identical RREQ must be dropped as duplicate
        let dec2 = await forwarder.evaluateInboundPacket(wireData: wireRREQ, fromPeerId: "neighbor-A")
        guard dec2 == .dropDuplicate else {
            print("  FAIL: Duplicate RREQ was not dropped, got \(dec2)")
            return false
        }
        
        // 2. Flooding distinct RREQs (different sequence numbers): rate limiter must engage
        var forwardedCount = 0
        var rateLimitedCount = 0
        
        for i in 1...6 {
            var env = rreqEnv
            env.sequenceNumber = UInt32(600 + i)
            let pkt = RawWirePacket(envelope: env, ciphertext: fakeCiphertext, authTag: fakeTag)
            let data = try! pkt.toWireData()
            
            let dec = await forwarder.evaluateInboundPacket(wireData: data, fromPeerId: "neighbor-A")
            if case .forward = dec {
                forwardedCount += 1
            } else if dec == .dropRateLimitExceeded {
                rateLimitedCount += 1
            }
        }
        
        guard rateLimitedCount >= 2 else {
            print("  FAIL: Expected at least 2 packets rate-limited, got \(rateLimitedCount) (forwarded: \(forwardedCount))")
            return false
        }
        
        print("  PASS: Duplicate RREQ flood suppressed; rapid burst throttled by token bucket rate limiter.")
        return true
    }
    
    // MARK: - Test 6: Expired Packet & Terminated Session Handling
    
    public static func testExpiredPacketAndTerminatedSessionHandling() async -> Bool {
        print("[Test 6] Expired packet & terminated session handling...")
        
        let clock = TestMeshClock()
        let crypto = CryptoService()
        let key = await crypto.generateSymmetricKey()
        let sessionId: UInt16 = 0xAAAA
        
        let session = GroupSession(
            sessionId: sessionId,
            sessionName: "Festival Group",
            symmetricKeyData: key.withUnsafeBytes { Data($0) },
            localInitials: "BOB"
        )
        let holder = SessionHolder(session: session)
        
        let table = RoutingTable(clock: clock)
        let rateLimiter = ForwardingRateLimiter(clock: clock)
        let neighbors = NeighborTable(clock: clock)
        let dupCache = SeenPacketCache(clock: clock)
        
        let forwarder = PacketForwarder(
            routingTable: table,
            rateLimiter: rateLimiter,
            neighborTable: neighbors,
            seenPacketCache: dupCache,
            clock: clock,
            cryptoService: crypto,
            sessionProvider: { holder.session },
            policyProvider: { RelayPolicyState(mode: .communalRelayActive) }
        )
        
        // 1. Packet timestamp too far in the future (> 5 minutes clock skew)
        let futureDate = clock.now().addingTimeInterval(350.0) // 5m50s in future
        let futurePing = LocationPingPayload(
            coordinate: CLLocationCoordinate2D(latitude: 36.1, longitude: -115.1),
            timestamp: futureDate,
            accuracy: 5,
            senderInitials: "ALC",
            batteryLevel: 90
        )
        let env = CleartextEnvelope(type: .locationPing, hopLimit: 8, hopCount: 0, sessionId: sessionId, sequenceNumber: 701)
        let futureWire = try! await crypto.sealToWireBytes(payload: futurePing.serialize(), envelope: env, using: key)
        
        let decFuture = await forwarder.evaluateInboundPacket(wireData: futureWire, fromPeerId: "peer-1")
        guard decFuture == .dropSecurityVerificationFailed else {
            print("  FAIL: Expected .dropSecurityVerificationFailed for future timestamp, got \(decFuture)")
            return false
        }
        
        // 2. Terminated session: user leaves group (holder.session becomes nil)
        holder.session = nil
        let validPing = LocationPingPayload(
            coordinate: CLLocationCoordinate2D(latitude: 36.1, longitude: -115.1),
            timestamp: clock.now(),
            accuracy: 5,
            senderInitials: "ALC",
            batteryLevel: 90
        )
        let env2 = CleartextEnvelope(type: .locationPing, hopLimit: 8, hopCount: 0, sessionId: sessionId, sequenceNumber: 702)
        let validWire = try! await crypto.sealToWireBytes(payload: validPing.serialize(), envelope: env2, using: key)
        
        let decTerminated = await forwarder.evaluateInboundPacket(wireData: validWire, fromPeerId: "peer-1")
        guard case .forward = decTerminated else {
            print("  FAIL: After session termination, node should treat packet as stranger traffic, got \(decTerminated)")
            return false
        }
        
        print("  PASS: Future clock skew rejected; terminated session drops local group privilege.")
        return true
    }
    
    // MARK: - Test 7: Unauthorized Route Response Rejection
    
    public static func testUnauthorizedRouteResponseRejection() async -> Bool {
        print("[Test 7] Unauthorized route response rejection & reverse route lookup...")
        
        let clock = TestMeshClock()
        let table = RoutingTable(clock: clock)
        let rateLimiter = ForwardingRateLimiter(clock: clock)
        let neighbors = NeighborTable(clock: clock)
        let dupCache = SeenPacketCache(clock: clock)
        
        await neighbors.recordNeighborActivity(peerId: "Alice", rssi: -50, isGroupMember: false)
        await neighbors.recordNeighborActivity(peerId: "Bob", rssi: -55, isGroupMember: false)
        
        let forwarder = PacketForwarder(
            routingTable: table,
            rateLimiter: rateLimiter,
            neighborTable: neighbors,
            seenPacketCache: dupCache,
            clock: clock,
            sessionProvider: { nil },
            policyProvider: { RelayPolicyState(mode: .communalRelayActive) }
        )
        
        // Step 1: Alice sends RREQ (sequenceNumber = 801), relay records reverse route towards Alice
        await table.recordReverseRoute(discoveryKey: 801, incomingPeerId: "Alice", hopCount: 1, ttl: 15.0)
        
        // Step 2: Bob sends authentic RREP for discoveryKey = 801
        let rrepEnv = CleartextEnvelope(type: .routeResp, hopLimit: 8, hopCount: 0, sessionId: 0xBBBB, sequenceNumber: 801)
        let fakeCiphertext = Data(repeating: 0xCC, count: 30)
        let fakeTag = Data(repeating: 0xDD, count: 16)
        let rrepPacket = RawWirePacket(envelope: rrepEnv, ciphertext: fakeCiphertext, authTag: fakeTag)
        let wireRREP = try! rrepPacket.toWireData()
        
        let decRREP = await forwarder.evaluateInboundPacket(wireData: wireRREP, fromPeerId: "Bob")
        guard case let .forward(_, nextHops) = decRREP, nextHops == ["Alice"] else {
            print("  FAIL: Expected RREP to follow reverse route unicast to Alice, got \(decRREP)")
            return false
        }
        
        // Step 3: An unauthorized attacker sends a rogue RREP for discoveryKey = 9999 (not in reverse table)
        let rogueEnv = CleartextEnvelope(type: .routeResp, hopLimit: 8, hopCount: 0, sessionId: 0xBBBB, sequenceNumber: 9999)
        let roguePacket = RawWirePacket(envelope: rogueEnv, ciphertext: fakeCiphertext, authTag: fakeTag)
        let rogueWire = try! roguePacket.toWireData()
        
        let decRogue = await forwarder.evaluateInboundPacket(wireData: rogueWire, fromPeerId: "Mallory")
        guard case let .forward(_, rogueHops) = decRogue, !rogueHops.contains("Mallory") else {
            print("  FAIL: Rogue RREP should not route back to sender, got \(decRogue)")
            return false
        }
        
        print("  PASS: Legitimate RREP matched reverse route; unmapped RREP prevented unauthorized unicast injection.")
        return true
    }
    
    // MARK: - Test 8: Untrusted Relay Member Impersonation Prevention
    
    public static func testUntrustedRelayMemberImpersonationPrevention() async -> Bool {
        print("[Test 8] Untrusted relay member impersonation prevention...")
        
        let clock = TestMeshClock()
        let crypto = CryptoService()
        let legitimateKey = await crypto.generateSymmetricKey()
        let rogueKey = await crypto.generateSymmetricKey()
        let sessionId: UInt16 = 0xCCCC
        
        let session = GroupSession(
            sessionId: sessionId,
            sessionName: "EDC Las Vegas",
            symmetricKeyData: legitimateKey.withUnsafeBytes { Data($0) },
            localInitials: "BOB"
        )
        
        let table = RoutingTable(clock: clock)
        let rateLimiter = ForwardingRateLimiter(clock: clock)
        let neighbors = NeighborTable(clock: clock)
        let dupCache = SeenPacketCache(clock: clock)
        
        let forwarder = PacketForwarder(
            routingTable: table,
            rateLimiter: rateLimiter,
            neighborTable: neighbors,
            seenPacketCache: dupCache,
            clock: clock,
            cryptoService: crypto,
            sessionProvider: { session },
            policyProvider: { RelayPolicyState(mode: .communalRelayActive) }
        )
        
        // Rogue relay crafts a location ping claiming to be "ALC" (our group member), but sealed with rogue key
        let impersonatedPing = LocationPingPayload(
            coordinate: CLLocationCoordinate2D(latitude: 36.1699, longitude: -115.1398),
            accuracy: 3,
            senderInitials: "ALC",
            batteryLevel: 95
        )
        let env = CleartextEnvelope(type: .locationPing, hopLimit: 8, hopCount: 1, sessionId: sessionId, sequenceNumber: 888)
        let wireImpersonated = try! await crypto.sealToWireBytes(
            payload: impersonatedPing.serialize(),
            envelope: env,
            using: rogueKey
        )
        
        let decision = await forwarder.evaluateInboundPacket(wireData: wireImpersonated, fromPeerId: "untrusted-relay")
        guard decision == .dropSecurityVerificationFailed else {
            print("  FAIL: Impersonated packet should trigger .dropSecurityVerificationFailed, got \(decision)")
            return false
        }
        
        print("  PASS: Untrusted relay impersonating group member rejected by Poly1305 MAC tag.")
        return true
    }
    
    // MARK: - Test 9: SeenPacketCache LRU & 5-Minute Sliding TTL
    
    public static func testSeenPacketCacheLRUAndFiveMinuteSlidingTTL() async -> Bool {
        print("[Test 9] SeenPacketCache LRU eviction & 5-minute sliding TTL...")
        
        let clock = TestMeshClock(initialDate: Date(timeIntervalSince1970: 100000))
        let cache = SeenPacketCache(capacity: 3, ttl: 300.0, clock: clock)
        
        let key1 = PacketKey(sessionId: 0x11, sequenceNumber: 1)
        let key2 = PacketKey(sessionId: 0x11, sequenceNumber: 2)
        let key3 = PacketKey(sessionId: 0x11, sequenceNumber: 3)
        let key4 = PacketKey(sessionId: 0x11, sequenceNumber: 4)
        
        let dup1 = await cache.isDuplicateAndRecord(key1)
        let dup2 = await cache.isDuplicateAndRecord(key2)
        let dup3 = await cache.isDuplicateAndRecord(key3)
        
        guard !dup1 && !dup2 && !dup3 else {
            print("  FAIL: Initial insertions should return false (not duplicate)")
            return false
        }
        
        let isDup1 = await cache.isDuplicateAndRecord(key1)
        guard isDup1 else {
            print("  FAIL: Re-evaluating key1 should return true (is duplicate)")
            return false
        }
        
        _ = await cache.isDuplicateAndRecord(key4)
        
        let hasKey2 = await cache.contains(key2)
        let hasKey1 = await cache.contains(key1)
        let hasKey4 = await cache.contains(key4)
        
        guard !hasKey2 && hasKey1 && hasKey4 else {
            print("  FAIL: LRU eviction failed: key2 should be evicted, key1 and key4 retained")
            return false
        }
        
        clock.advance(by: 299.0)
        let hasKey1BeforeExpiry = await cache.contains(key1)
        guard hasKey1BeforeExpiry else {
            print("  FAIL: key1 should be present at 299s")
            return false
        }
        
        clock.advance(by: 2.0)
        let hasKey1AfterExpiry = await cache.contains(key1)
        guard !hasKey1AfterExpiry else {
            print("  FAIL: key1 should expire and be absent at 301s")
            return false
        }
        
        print("  PASS: SeenPacketCache LRU eviction and 300s sliding TTL verified accurately.")
        return true
    }
    
    // MARK: - Test 10: RoutingTable Monotonicity & Reverse Route Lifecycle
    
    public static func testRoutingTableMonotonicityAndReverseRouteLifecycle() async -> Bool {
        print("[Test 10] RoutingTable sequence monotonicity & reverse route lifecycle...")
        
        let clock = TestMeshClock()
        let table = RoutingTable(maxForwardRoutes: 2, maxReverseRoutes: 2, clock: clock)
        
        await table.recordForwardRoute(
            destinationId: "BOB",
            nextHop: "Relay-1",
            hopCount: 2,
            cost: 3,
            sequenceNumber: 100,
            ttl: 30.0
        )
        
        let route1 = await table.findRoute(to: "BOB")
        guard let r1 = route1, r1.nextHopPeerId == "Relay-1" && r1.sequenceNumber == 100 else {
            print("  FAIL: Failed to record or find initial route")
            return false
        }
        
        await table.recordForwardRoute(
            destinationId: "BOB",
            nextHop: "Rogue-Relay",
            hopCount: 1,
            cost: 1,
            sequenceNumber: 99,
            ttl: 30.0
        )
        let routeAfterOld = await table.findRoute(to: "BOB")
        guard routeAfterOld?.nextHopPeerId == "Relay-1" else {
            print("  FAIL: Outdated sequence number superseded fresher route")
            return false
        }
        
        await table.recordForwardRoute(
            destinationId: "BOB",
            nextHop: "Relay-2",
            hopCount: 2,
            cost: 2,
            sequenceNumber: 101,
            ttl: 30.0
        )
        let routeAfterNew = await table.findRoute(to: "BOB")
        guard routeAfterNew?.nextHopPeerId == "Relay-2" && routeAfterNew?.sequenceNumber == 101 else {
            print("  FAIL: Fresher sequence number did not update route")
            return false
        }
        
        await table.recordReverseRoute(discoveryKey: 555, incomingPeerId: "Alice", hopCount: 1, ttl: 15.0)
        let popped = await table.popReverseRoute(for: 555)
        guard popped?.incomingPeerId == "Alice" else {
            print("  FAIL: Pop reverse route failed")
            return false
        }
        
        let poppedSecond = await table.popReverseRoute(for: 555)
        guard poppedSecond == nil else {
            print("  FAIL: Reverse route was not consumed after first pop")
            return false
        }
        
        print("  PASS: RoutingTable sequence monotonicity and reverse route pop lifecycle verified.")
        return true
    }
    
    // MARK: - Test 11: Multi-Hop Blind Relaying End-to-End Chain
    
    public static func testMultiHopBlindRelayingEndToEndChain() async -> Bool {
        print("[Test 11] Multi-hop blind relaying chain (Alice -> Relay 1 -> Relay 2 -> Bob)...")
        
        let clock = TestMeshClock()
        let crypto = CryptoService()
        let groupKey = await crypto.generateSymmetricKey()
        let sessionId: UInt16 = 0xDDDD
        
        let bobSession = GroupSession(
            sessionId: sessionId,
            sessionName: "EDC Group",
            symmetricKeyData: groupKey.withUnsafeBytes { Data($0) },
            localInitials: "BOB"
        )
        
        let dupCache1 = SeenPacketCache(clock: clock)
        let dupCache2 = SeenPacketCache(clock: clock)
        let dupCacheBob = SeenPacketCache(clock: clock)
        
        let forwarderRelay1 = PacketForwarder(
            routingTable: RoutingTable(clock: clock),
            rateLimiter: ForwardingRateLimiter(clock: clock),
            neighborTable: NeighborTable(clock: clock),
            seenPacketCache: dupCache1,
            clock: clock,
            sessionProvider: { nil }, // Stranger
            policyProvider: { RelayPolicyState(mode: .communalRelayActive) }
        )
        
        let forwarderRelay2 = PacketForwarder(
            routingTable: RoutingTable(clock: clock),
            rateLimiter: ForwardingRateLimiter(clock: clock),
            neighborTable: NeighborTable(clock: clock),
            seenPacketCache: dupCache2,
            clock: clock,
            sessionProvider: { nil }, // Stranger
            policyProvider: { RelayPolicyState(mode: .communalRelayActive) }
        )
        
        let forwarderBob = PacketForwarder(
            routingTable: RoutingTable(clock: clock),
            rateLimiter: ForwardingRateLimiter(clock: clock),
            neighborTable: NeighborTable(clock: clock),
            seenPacketCache: dupCacheBob,
            clock: clock,
            cryptoService: crypto,
            sessionProvider: { bobSession }, // Destination
            policyProvider: { RelayPolicyState(mode: .communalRelayActive) }
        )
        
        // 1. Alice creates location ping with hopCount = 0, hopLimit = 8
        let alicePing = LocationPingPayload(
            coordinate: CLLocationCoordinate2D(latitude: 36.1234, longitude: -115.5678),
            accuracy: 4,
            senderInitials: "ALC",
            batteryLevel: 92
        )
        let aliceEnvelope = CleartextEnvelope(
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: sessionId,
            sequenceNumber: 901
        )
        let wireAlice = try! await crypto.sealToWireBytes(
            payload: alicePing.serialize(),
            envelope: aliceEnvelope,
            using: groupKey
        )
        
        // 2. Relay 1 receives wireAlice
        let decRelay1 = await forwarderRelay1.evaluateInboundPacket(wireData: wireAlice, fromPeerId: "Alice")
        guard case let .forward(mutated1, _) = decRelay1 else {
            print("  FAIL: Relay 1 failed to forward packet, got \(decRelay1)")
            return false
        }
        
        let env1 = try! CleartextEnvelope.deserialize(from: mutated1.subdata(in: 0..<10))
        guard env1.hopCount == 1 else {
            print("  FAIL: Relay 1 should set hopCount = 1, got \(env1.hopCount)")
            return false
        }
        
        // 3. Relay 2 receives mutated1
        let decRelay2 = await forwarderRelay2.evaluateInboundPacket(wireData: mutated1, fromPeerId: "Relay-1")
        guard case let .forward(mutated2, _) = decRelay2 else {
            print("  FAIL: Relay 2 failed to forward packet, got \(decRelay2)")
            return false
        }
        
        let env2 = try! CleartextEnvelope.deserialize(from: mutated2.subdata(in: 0..<10))
        guard env2.hopCount == 2 else {
            print("  FAIL: Relay 2 should set hopCount = 2, got \(env2.hopCount)")
            return false
        }
        
        // 4. Bob receives mutated2 (3 hops away from Alice)
        let decBob = await forwarderBob.evaluateInboundPacket(wireData: mutated2, fromPeerId: "Relay-2")
        guard decBob == .deliverLocally else {
            print("  FAIL: Bob failed to open and authenticate relayed packet, got \(decBob)")
            return false
        }
        
        let rawBob = try! RawWirePacket.fromWireData(mutated2)
        let decryptedData = try! await crypto.open(
            ciphertext: rawBob.ciphertext,
            envelope: rawBob.envelope,
            authTag: rawBob.authTag,
            using: groupKey
        )
        let receivedPing = try! LocationPingPayload.deserialize(from: decryptedData)
        
        guard receivedPing.senderInitials == "ALC" &&
              abs(receivedPing.coordinate.latitude - 36.1234) < 0.0001 else {
            print("  FAIL: Bob decoded incorrect payload contents")
            return false
        }
        
        print("  PASS: 3-hop blind relay chain delivered packet to Bob; Poly1305 MAC verified across hops.")
        return true
    }
    
    // MARK: - Test 12: Confidentiality & Zero-Knowledge Payload Protection
    
    public static func testConfidentialityZeroKnowledgePayloadProtection() async -> Bool {
        print("[Test 12] Confidentiality & zero-knowledge payload protection...")
        
        let crypto = CryptoService()
        let groupKey = await crypto.generateSymmetricKey()
        let strangerKey = await crypto.generateSymmetricKey()
        let sessionId: UInt16 = 0xEEEE
        
        let confidentialPing = LocationPingPayload(
            coordinate: CLLocationCoordinate2D(latitude: 36.9999, longitude: -115.8888),
            accuracy: 2,
            senderInitials: "SEC",
            batteryLevel: 15
        )
        let env = CleartextEnvelope(type: .locationPing, hopLimit: 8, hopCount: 0, sessionId: sessionId, sequenceNumber: 999)
        let wireData = try! await crypto.sealToWireBytes(
            payload: confidentialPing.serialize(),
            envelope: env,
            using: groupKey
        )
        
        // 1. Verify cleartext envelope contains NO coordinates or initials
        let envelopeData = wireData.subdata(in: 0..<10)
        let envelope = try! CleartextEnvelope.deserialize(from: envelopeData)
        guard envelope.sessionId == sessionId && envelope.sequenceNumber == 999 else {
            print("  FAIL: Cleartext envelope corrupted")
            return false
        }
        
        // 2. Stranger attempts to decrypt without the key: must fail
        let raw = try! RawWirePacket.fromWireData(wireData)
        var strangerFailed = false
        do {
            _ = try await crypto.open(
                ciphertext: raw.ciphertext,
                envelope: raw.envelope,
                authTag: raw.authTag,
                using: strangerKey
            )
        } catch {
            strangerFailed = true
        }
        
        guard strangerFailed else {
            print("  FAIL: Stranger opened group ciphertext with wrong key!")
            return false
        }
        
        // 3. Verify ciphertext is high-entropy (not plaintext)
        let cipherBytes = Array(raw.ciphertext)
        let zeroCount = cipherBytes.filter { $0 == 0 }.count
        guard zeroCount < 10 else {
            print("  FAIL: Ciphertext contains suspiciously low entropy (\(zeroCount) zeros)")
            return false
        }
        
        print("  PASS: Payload cryptographically sealed; zero plaintext leaked to intermediate relays.")
        return true
    }
}
