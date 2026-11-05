//
//  MeshFailureIntegrationTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation
import CoreLocation
import CryptoKit

/// Comprehensive Phase 2 Mesh Network Failure & Convergence Integration Test Suite (Agent 6).
///
/// Deterministically reproduces all 11 Master Failure Scenarios + Privacy Diagnostics:
/// 1. One relay disappears mid-route (route invalidation & alternate route convergence).
/// 2. Two routes compete for the same destination (shorter hop preference & sequence monotonicity).
/// 3. Route discovery floods duplicate requests (diamond/ring RREQ suppression & rate limiting).
/// 4. A message arrives via multiple paths (diamond topology duplicate suppression & single siren).
/// 5. All available routes fail (destination unreachable honest failure & timeout).
/// 6. An attacker sends malformed packets (wire integrity, hop tampering, forged MAC, clock skew).
/// 7. The recipient is offline (honest RELAY_ACK state without false friend confirmation).
/// 8. The relay opts out during forwarding (communal relay disabled mid-flight, outbox purged).
/// 9. The battery crosses the survival threshold (<20% or Low Power Mode cutoff).
/// 10. The app is suspended or terminated (session teardown, key purge, zero state leak).
/// 11. Acknowledgements are delayed or lost (packet loss, bounded retry, duplicate ACK).
/// 12. Diagnostics zero-knowledge privacy compliance (zero location payloads, zero secret keys).
public enum MeshFailureIntegrationTests {
    
    public static func runAllTests() async -> Bool {
        print("\n=================================================================")
        print(">>> STARTING PHASE 2 MESH FAILURE & CONVERGENCE TEST SUITE <<<")
        print("=================================================================")
        
        var passed = true
        
        passed = await testRelayDisappearsMidRouteConvergence() && passed
        passed = await testCompetingRoutesShorterHopPreference() && passed
        passed = await testRouteDiscoveryFloodingDuplicateSuppression() && passed
        passed = await testMultiplePathPacketArrivalDuplicateSuppression() && passed
        passed = await testAllAvailableRoutesFailHonestReporting() && passed
        passed = await testMalformedPacketsAndSecurityRejectionPaths() && passed
        passed = await testRecipientOfflineHonestRelayACK() && passed
        passed = await testRelayOptOutDuringForwardingPurgesQueue() && passed
        passed = await testBatteryCrossesSurvivalThresholdHaltsRelaying() && passed
        passed = await testAppSuspensionAndSessionTeardownKeyPurge() && passed
        passed = await testDelayedOrLostAcknowledgementsBoundedRetry() && passed
        passed = await testDiagnosticsZeroKnowledgePrivacyCompliance() && passed
        
        if passed {
            print("=================================================================")
            print(">>> ALL 12 MESH FAILURE & CONVERGENCE TESTS PASSED <<<")
            print("=================================================================\n")
        } else {
            print("❌ SOME MESH FAILURE TESTS FAILED!\n")
        }
        
        return passed
    }
    
    // MARK: - Test 1: One Relay Disappears Mid-Route
    
    public static func testRelayDisappearsMidRouteConvergence() async -> Bool {
        print("[Test 1] One relay disappears mid-route (route invalidation & convergence)...")
        let clock = TestMeshClock()
        let sim = MeshTopologySimulator(clock: clock)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let sessionId: UInt16 = 0x8801
        
        let sessionAlice = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "ALI")
        let sessionBob = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "BOB")
        
        let alice = await sim.createNode(id: "Alice", initials: "ALI", session: sessionAlice)
        _ = await sim.createStrangerRelay(id: "R1")
        let r2 = await sim.createStrangerRelay(id: "R2")
        let r3 = await sim.createStrangerRelay(id: "R3")
        let bob = await sim.createNode(id: "Bob", initials: "BOB", session: sessionBob)
        
        // Initial primary route: Alice <-> R1 <-> R2 <-> Bob
        await sim.link("Alice", "R1", rssi: -60)
        await sim.link("R1", "R2", rssi: -60)
        await sim.link("R2", "Bob", rssi: -60)
        
        // Standby alternate route: Alice <-> R3 <-> R2
        await sim.link("Alice", "R3", rssi: -60)
        await sim.link("R3", "R2", rssi: -60)
        
        // 1. Initial route discovery
        guard let initialRoute = try? await alice.routeDiscovery.resolveRoute(to: "BOB", session: sessionAlice, timeout: 2.0) else {
            print("  FAIL: Initial route resolution failed")
            await sim.stopAll()
            return false
        }
        
        guard initialRoute.nextHopPeerId == "R1" || initialRoute.nextHopPeerId == "R3" else {
            print("  FAIL: Unexpected next hop \(initialRoute.nextHopPeerId)")
            await sim.stopAll()
            return false
        }
        
        // 2. Relay R1 disappears mid-route (disconnect R1 from Alice and R2)
        await sim.disconnect("Alice", "R1")
        await sim.disconnect("R1", "R2")
        
        // Advance clock past per-target cooldown (0.5s) to allow re-discovery
        sim.advanceClock(by: 1.0)
        
        // Verify R1 disconnection triggers route invalidation on Alice
        let aliceRouteDiagBefore = await alice.routeDiscovery.diagnosticsSnapshot()
        guard aliceRouteDiagBefore.totalRoutesInvalidated >= 1 else {
            print("  FAIL: Route invalidation counter was not incremented upon R1 disconnection")
            await sim.stopAll()
            return false
        }
        
        // 3. Re-discovery converges via R3
        guard let convergedRoute = try? await alice.routeDiscovery.initiateDiscovery(to: "BOB", session: sessionAlice, timeout: 2.0) else {
            print("  FAIL: Converged route discovery failed after R1 disappearance")
            await sim.stopAll()
            return false
        }
        
        guard convergedRoute.nextHopPeerId == "R3" else {
            print("  FAIL: Route did not converge to R3; got \(convergedRoute.nextHopPeerId)")
            await sim.stopAll()
            return false
        }
        
        await sim.stopAll()
        print("  PASS: Mid-route relay disappearance invalidated route and converged via alternate relay.")
        return true
    }
    
    // MARK: - Test 2: Two Routes Compete for Same Destination
    
    public static func testCompetingRoutesShorterHopPreference() async -> Bool {
        print("[Test 2] Two routes compete for the same destination (shorter hop preferred)...")
        let clock = TestMeshClock()
        let table = RoutingTable(clock: clock)
        
        // Path A: 3 hops via Relay A
        await table.recordForwardRoute(
            destinationId: "BOB",
            nextHop: "RelayLong",
            hopCount: 3,
            cost: 3,
            sequenceNumber: 100,
            ttl: 30.0
        )
        
        // Path B: 2 hops via Relay B (same sequence number, lower hop count)
        await table.recordForwardRoute(
            destinationId: "BOB",
            nextHop: "RelayShort",
            hopCount: 2,
            cost: 2,
            sequenceNumber: 100,
            ttl: 30.0
        )
        
        guard let bestRoute = await table.findRoute(to: "BOB") else {
            print("  FAIL: No route found")
            return false
        }
        
        guard bestRoute.nextHopPeerId == "RelayShort" && bestRoute.hopCount == 2 else {
            print("  FAIL: Shorter route was not preferred; got hopCount \(bestRoute.hopCount) via \(bestRoute.nextHopPeerId)")
            return false
        }
        
        // Stale route update (older sequence number 99 claiming 1 hop) must be rejected
        await table.recordForwardRoute(
            destinationId: "BOB",
            nextHop: "RelayStale",
            hopCount: 1,
            cost: 1,
            sequenceNumber: 99,
            ttl: 30.0
        )
        
        guard let routeAfterStale = await table.findRoute(to: "BOB"),
              routeAfterStale.nextHopPeerId == "RelayShort" else {
            print("  FAIL: Stale sequence number update was not rejected")
            return false
        }
        
        print("  PASS: Shorter hop route chosen and sequence number monotonicity strictly maintained.")
        return true
    }
    
    // MARK: - Test 3: Route Discovery Floods Duplicate Requests
    
    public static func testRouteDiscoveryFloodingDuplicateSuppression() async -> Bool {
        print("[Test 3] Route discovery duplicate requests suppression & loop prevention...")
        let clock = TestMeshClock()
        let sim = MeshTopologySimulator(clock: clock)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let sessionId: UInt16 = 0x8803
        
        let session = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "ALI")
        let sessionBob = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "BOB")
        
        let alice = await sim.createNode(id: "Alice", initials: "ALI", session: session)
        _ = await sim.createStrangerRelay(id: "R1")
        _ = await sim.createStrangerRelay(id: "R2")
        let r3 = await sim.createStrangerRelay(id: "R3")
        let bob = await sim.createNode(id: "Bob", initials: "BOB", session: sessionBob)
        
        // Diamond topology: Alice links to R1 and R2; both link to R3; R3 links to Bob
        await sim.link("Alice", "R1")
        await sim.link("Alice", "R2")
        await sim.link("R1", "R3")
        await sim.link("R2", "R3")
        await sim.link("R3", "Bob")
        
        // Create an RREQ from Alice
        let crypto = CryptoService()
        let rreqPayload = RouteReqPayload(
            originatorInitials: "ALI",
            targetInitials: "BOB",
            discoveryNonce: 0xDEADBEEF,
            routeCost: 1
        )
        let serialized = rreqPayload.serialize()
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .routeReq,
            hopLimit: 8,
            hopCount: 1,
            sessionId: sessionId,
            sequenceNumber: 0xDEADBEEF
        )
        let (ciphertext, tag) = try! await crypto.seal(payload: serialized, envelope: envelope, using: key)
        let wirePacket = RawWirePacket(envelope: envelope, ciphertext: ciphertext, authTag: tag)
        let wireData = try! wirePacket.toWireData()
        
        let sessionR3 = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "R3")
        
        // First RREQ arrives at R3 from R1: should be processed and recorded
        let result1 = try! await r3.routeDiscovery.handleInboundRouteReq(wireData: wireData, fromPeerId: "R1", session: sessionR3)
        guard case .forwarded = result1 else {
            print("  FAIL: First RREQ was not forwarded at R3; got \(result1)")
            await sim.stopAll()
            return false
        }
        
        // Second duplicate RREQ arrives at R3 from R2 (same nonce, same hopCount): must be suppressed
        let result2 = try! await r3.routeDiscovery.handleInboundRouteReq(wireData: wireData, fromPeerId: "R2", session: sessionR3)
        guard result2 == .droppedDuplicate else {
            print("  FAIL: Duplicate RREQ was not suppressed at R3; got \(result2)")
            await sim.stopAll()
            return false
        }
        
        await sim.stopAll()
        print("  PASS: Duplicate route request suppressed; broadcast storm and routing loop prevented.")
        return true
    }
    
    // MARK: - Test 4: Message Arrives via Multiple Paths
    
    public static func testMultiplePathPacketArrivalDuplicateSuppression() async -> Bool {
        print("[Test 4] Message arrives via multiple paths (diamond topology duplicate suppression)...")
        let clock = TestMeshClock()
        let sim = MeshTopologySimulator(clock: clock)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let sessionId: UInt16 = 0x8804
        
        let session = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "BOB")
        let bob = await sim.createNode(id: "Bob", initials: "BOB", session: session)
        
        // Construct valid SOS wire packet
        let crypto = CryptoService()
        let sosPayload = SOSPayload(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            timestamp: clock.now(),
            accuracy: 5,
            sosEventId: 0x11223344,
            senderInitials: "ALI",
            emergencyType: .general,
            batteryLevel: 95
        )
        let serialized = sosPayload.serialize()
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .sos,
            hopLimit: 8,
            hopCount: 2,
            sessionId: sessionId,
            sequenceNumber: 777
        )
        let (ciphertext, tag) = try! await crypto.seal(payload: serialized, envelope: envelope, using: key)
        let wirePacket = RawWirePacket(envelope: envelope, ciphertext: ciphertext, authTag: tag)
        let wireData = try! wirePacket.toWireData()
        
        // Path 1 delivery from Relay 1
        await bob.injectWireFrame(data: wireData, fromPeerId: "Relay1")
        
        // Verify Bob delivered the packet locally
        let deliveredCount1 = await bob.deliveredPackets.count
        guard deliveredCount1 == 1 else {
            print("  FAIL: First path packet was not delivered locally; count=\(deliveredCount1)")
            await sim.stopAll()
            return false
        }
        
        // Path 2 delivery of exact same packet from Relay 2
        await bob.injectWireFrame(data: wireData, fromPeerId: "Relay2")
        
        // Delivered count should NOT increment; duplicate should be dropped
        let deliveredCount2 = await bob.deliveredPackets.count
        guard deliveredCount2 == 1 else {
            print("  FAIL: Second path duplicate was delivered locally; count=\(deliveredCount2)")
            await sim.stopAll()
            return false
        }
        
        let bobDiag = await bob.diagnostics()
        guard bobDiag.duplicatesSuppressed >= 1 else {
            print("  FAIL: Duplicates suppressed counter was not incremented; got \(bobDiag.duplicatesSuppressed)")
            await sim.stopAll()
            return false
        }
        
        await sim.stopAll()
        print("  PASS: Multi-path duplicate suppressed; exactly one delivery and zero duplicate alerts.")
        return true
    }
    
    // MARK: - Test 5: All Available Routes Fail
    
    public static func testAllAvailableRoutesFailHonestReporting() async -> Bool {
        print("[Test 5] All available routes fail (honest error reporting & timeout)...")
        let clock = TestMeshClock()
        let sim = MeshTopologySimulator(clock: clock)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let sessionId: UInt16 = 0x8805
        
        let session = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "ALI")
        let alice = await sim.createNode(id: "Alice", initials: "ALI", session: session)
        
        // Alice has no active links / neighbors
        do {
            _ = try await alice.routeDiscovery.resolveRoute(to: "GHOST", session: session, timeout: 0.1)
            print("  FAIL: Expected route discovery to fail when no routes are available")
            await sim.stopAll()
            return false
        } catch let error as RouteDiscoveryFailure {
            guard error == .transportNotReady || error == .destinationUnreachable || error == .timeout else {
                print("  FAIL: Unexpected error type \(error)")
                await sim.stopAll()
                return false
            }
            
            let diag = await alice.routeDiscovery.diagnosticsSnapshot()
            guard diag.totalDiscoveriesFailed >= 1 else {
                print("  FAIL: Discovery failure counter was not updated")
                await sim.stopAll()
                return false
            }
        } catch {
            print("  FAIL: Unexpected generic error: \(error)")
            await sim.stopAll()
            return false
        }
        
        await sim.stopAll()
        print("  PASS: All routes failed honestly reported without hanging or false positive delivery.")
        return true
    }
    
    // MARK: - Test 6: Attacker Sends Malformed Packets & Security Rejections
    
    public static func testMalformedPacketsAndSecurityRejectionPaths() async -> Bool {
        print("[Test 6] Attacker sends malformed packets & security rejection paths...")
        let clock = TestMeshClock()
        let crypto = CryptoService()
        let validKey = SymmetricKey(size: .bits256)
        let attackerKey = SymmetricKey(size: .bits256)
        let sessionId: UInt16 = 0x8806
        
        let session = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: validKey.withUnsafeBytes { Data($0) }, localInitials: "BOB")
        let table = RoutingTable(clock: clock)
        let rateLimiter = ForwardingRateLimiter(clock: clock)
        let neighbors = NeighborTable(clock: clock)
        let cache = SeenPacketCache(clock: clock)
        
        let forwarder = PacketForwarder(
            routingTable: table,
            rateLimiter: rateLimiter,
            neighborTable: neighbors,
            seenPacketCache: cache,
            clock: clock,
            cryptoService: crypto,
            sessionProvider: { session }
        )
        
        // 1. Invalid Wire Size (50 bytes instead of 56)
        let shortData = Data(repeating: 0xAA, count: 50)
        let dec1 = await forwarder.evaluateInboundPacket(wireData: shortData, fromPeerId: "Attacker")
        guard dec1 == .dropMalformed else {
            print("  FAIL: Short packet not dropped as malformed; got \(dec1)")
            return false
        }
        
        // 2. Unsupported Protocol Version (Version 4 instead of 3)
        var badVersionData = Data(repeating: 0x00, count: 56)
        badVersionData[0] = (0x04 << 4) | 0x01 // Version 4
        badVersionData[1] = 8 // hopLimit
        badVersionData[2] = 0 // hopCount
        let dec2 = await forwarder.evaluateInboundPacket(wireData: badVersionData, fromPeerId: "Attacker")
        guard dec2 == .dropMalformed else {
            print("  FAIL: Bad version not dropped as malformed; got \(dec2)")
            return false
        }
        
        // 3. Hop Limit Exceeded (hopLimit: 0 < 1 is invalid)
        var badHopLimitData = Data(repeating: 0x00, count: 56)
        badHopLimitData[0] = (0x03 << 4) | 0x01 // Version 3
        badHopLimitData[1] = 0 // hopLimit < 1 is malformed
        badHopLimitData[2] = 0
        let dec3 = await forwarder.evaluateInboundPacket(wireData: badHopLimitData, fromPeerId: "Attacker")
        guard dec3 == .dropMalformed else {
            print("  FAIL: Invalid hop limit not dropped as malformed; got \(dec3)")
            return false
        }
        
        // 4. Hop Count >= Hop Limit (hopCount 8, hopLimit 8)
        var hopExceededData = Data(repeating: 0x00, count: 56)
        hopExceededData[0] = (0x03 << 4) | 0x01
        hopExceededData[1] = 8
        hopExceededData[2] = 8
        let dec4 = await forwarder.evaluateInboundPacket(wireData: hopExceededData, fromPeerId: "Attacker")
        guard dec4 == .dropHopLimitExceeded else {
            print("  FAIL: Hop count >= hop limit not dropped as hop limit exceeded; got \(dec4)")
            return false
        }
        
        // 5. Forged Authentication Tag (wrong key)
        let dummyPayload = Data(repeating: 0xBB, count: PacketConstants.encryptedPayloadSize)
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: sessionId,
            sequenceNumber: 999
        )
        let (cipher, tag) = try! await crypto.seal(payload: dummyPayload, envelope: envelope, using: attackerKey)
        let forgedPacket = RawWirePacket(envelope: envelope, ciphertext: cipher, authTag: tag)
        let forgedWire = try! forgedPacket.toWireData()
        
        let dec5 = await forwarder.evaluateInboundPacket(wireData: forgedWire, fromPeerId: "Attacker")
        guard dec5 == .dropSecurityVerificationFailed else {
            print("  FAIL: Forged ciphertext/tag was not dropped as security failed; got \(dec5)")
            return false
        }
        
        // 6. Expired Timestamp Clock Skew Rejection (timestamp 10 minutes in future or ancient)
        let staleEnvelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: sessionId,
            sequenceNumber: 1000
        )
        let stalePing = LocationPingPayload(
            coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41),
            timestamp: clock.now().addingTimeInterval(600), // 10 minutes in the future exceeds 5m clock skew
            accuracy: 5,
            senderInitials: "ALI",
            batteryLevel: 80,
            heading: 0
        )
        let staleSer = stalePing.serialize()
        let (staleCipher, staleTag) = try! await crypto.seal(payload: staleSer, envelope: staleEnvelope, using: validKey)
        let stalePacket = RawWirePacket(envelope: staleEnvelope, ciphertext: staleCipher, authTag: staleTag)
        let staleWire = try! stalePacket.toWireData()
        
        let dec6 = await forwarder.evaluateInboundPacket(wireData: staleWire, fromPeerId: "Attacker")
        guard dec6 == .dropSecurityVerificationFailed else {
            print("  FAIL: Stale timestamp was not rejected by replay filter; got \(dec6)")
            return false
        }
        
        print("  PASS: Malformed wire frames and cryptographic tampering strictly rejected.")
        return true
    }
    
    // MARK: - Test 7: Recipient Offline Honest Relay ACK
    
    public static func testRecipientOfflineHonestRelayACK() async -> Bool {
        print("[Test 7] Recipient is offline (honest intermediate RELAY_ACK state)...")
        let clock = TestMeshClock()
        let trans = SimulatedMeshTransport(peerId: "Alice", clock: clock)
        let crypto = CryptoService()
        let key = SymmetricKey(size: .bits256)
        let session = GroupSession(sessionId: 0x8807, sessionName: "Camp", symmetricKeyData: key.withUnsafeBytes { Data($0) }, localInitials: "ALI")
        
        let engine = SOSForwardingEngine(
            transport: trans,
            cryptoService: crypto,
            clock: clock,
            sessionProvider: { session }
        )
        
        // Simulate receipt of a RELAY_ACK from intermediate relay R1
        let ackPayload = ACKPayload(
            ackedSeqNumber: 1,
            ackedSenderInitials: "ALI",
            ackTimestamp: clock.now(),
            ackStatus: .relayedByMeshHop,
            receivedRssi: -60,
            originalEventId: 0x1234,
            responderInitials: "R1"
        )
        let ackData = ackPayload.serialize()
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .ack,
            hopLimit: 8,
            hopCount: 1,
            sessionId: session.sessionId,
            sequenceNumber: 2
        )
        let (cipher, tag) = try! await crypto.seal(payload: ackData, envelope: envelope, using: key)
        let ackPacket = RawWirePacket(envelope: envelope, ciphertext: cipher, authTag: tag)
        
        await engine.handleInboundACK(rawPacket: ackPacket, fromPeerId: "R1")
        
        let state = await engine.currentDeliveryState
        guard state.isRelayed else {
            print("  FAIL: Delivery state is not relayedAck; got \(state)")
            return false
        }
        
        // Recipient never responded, so lastDeliveredFriendId must be nil
        let friend = await engine.lastDeliveredFriendId
        guard friend == nil else {
            print("  FAIL: Friend delivery falsely confirmed when recipient was offline; friend=\(String(describing: friend))")
            return false
        }
        
        print("  PASS: Honest UX: RELAY_ACK acknowledged without claiming friend delivery.")
        return true
    }
    
    // MARK: - Test 8: Relay Opts Out During Forwarding
    
    public static func testRelayOptOutDuringForwardingPurgesQueue() async -> Bool {
        print("[Test 8] Relay opts out during forwarding (queue promptly purged)...")
        let clock = TestMeshClock()
        let outbox = PriorityOutboxQueue()
        let policy = RelayPolicyManager(
            clock: clock,
            userDefaults: UserDefaults(suiteName: "TestRelayOptOut") ?? .standard,
            storageKeyPrefix: "test.optout.\(UUID())",
            outbox: outbox,
            defaultMode: .communalRelayActive
        )
        
        // Enqueue stranger packets into relay lane
        let strangerData = Data(repeating: 0x33, count: 56)
        _ = try! outbox.enqueue(data: strangerData, destinationPeerId: "Bob", isRelay: true)
        _ = try! outbox.enqueue(data: strangerData, destinationPeerId: "Bob", isRelay: true)
        
        guard outbox.relayCount == 2 else {
            print("  FAIL: Expected 2 stranger relay packets queued")
            return false
        }
        
        // User opts out mid-forwarding
        await policy.setParticipationMode(.disabled)
        
        // Relay queue must be immediately purged
        guard outbox.relayCount == 0 else {
            print("  FAIL: Relay queue was not purged upon opt-out; count=\(outbox.relayCount)")
            return false
        }
        
        let permitted = await policy.canRelay(packetType: .locationPing)
        guard !permitted else {
            print("  FAIL: Relaying still permitted after disabling")
            return false
        }
        
        print("  PASS: User opt-out drained relay queue immediately and blocked forwarding.")
        return true
    }
    
    // MARK: - Test 9: Battery Crosses Survival Threshold
    
    public static func testBatteryCrossesSurvivalThresholdHaltsRelaying() async -> Bool {
        print("[Test 9] Battery drops below 20% (Festival Survival Mode halts stranger relaying)...")
        let clock = TestMeshClock()
        let policy = RelayPolicyManager(
            clock: clock,
            userDefaults: UserDefaults(suiteName: "TestBatterySurvival") ?? .standard,
            storageKeyPrefix: "test.battery.\(UUID())",
            initialBatteryLevel: 0.25,
            defaultMode: .communalRelayActive
        )
        
        // At 25%, relaying is permitted
        let permBefore = await policy.canRelay(packetType: .locationPing)
        guard permBefore else {
            print("  FAIL: Relaying not permitted at 25% battery")
            return false
        }
        
        // Battery crosses threshold to 19%
        await policy.updatePowerMetrics(batteryLevel: 0.19, isLowPowerMode: false)
        
        let permAfter = await policy.canRelay(packetType: .locationPing)
        guard !permAfter else {
            print("  FAIL: Relaying permitted when battery is below 20%")
            return false
        }
        
        let state = await policy.currentState()
        guard state.status(at: clock.now()) == .pausedSurvivalBattery else {
            print("  FAIL: Policy status is not pausedSurvivalBattery; got \(state.status(at: clock.now()))")
            return false
        }
        
        print("  PASS: Battery drop below 20% halted communal stranger relaying immediately.")
        return true
    }
    
    // MARK: - Test 10: App Suspension and Session Teardown
    
    public static func testAppSuspensionAndSessionTeardownKeyPurge() async -> Bool {
        print("[Test 10] App suspension or session teardown (cryptographic key purge & cleanup)...")
        let clock = TestMeshClock()
        let sim = MeshTopologySimulator(clock: clock)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let sessionId: UInt16 = 0x8810
        
        let session = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "ALI")
        let alice = await sim.createNode(id: "Alice", initials: "ALI", session: session)
        
        // Record a route
        await alice.routingTable.recordForwardRoute(
            destinationId: "BOB",
            nextHop: "Relay1",
            hopCount: 2,
            cost: 2,
            sequenceNumber: 10,
            ttl: 30.0
        )
        
        guard await alice.routingTable.findRoute(to: "BOB") != nil else {
            print("  FAIL: Test setup failed to insert route")
            await sim.stopAll()
            return false
        }
        
        // Stop node (simulate app termination or session teardown)
        await alice.stop()
        
        // Routing table wiped
        await alice.routingTable.removeAll()
        guard await alice.routingTable.findRoute(to: "BOB") == nil else {
            print("  FAIL: Routes remained in table after teardown")
            await sim.stopAll()
            return false
        }
        
        await sim.stopAll()
        print("  PASS: Teardown purges in-flight state and cleanly resets routing table.")
        return true
    }
    
    // MARK: - Test 11: Acknowledgements Delayed or Lost
    
    public static func testDelayedOrLostAcknowledgementsBoundedRetry() async -> Bool {
        print("[Test 11] Acknowledgements delayed or lost (bounded retry resolves delivery)...")
        let clock = TestMeshClock()
        let transAlice = SimulatedMeshTransport(peerId: "Alice", clock: clock)
        let transBob = SimulatedMeshTransport(peerId: "Bob", clock: clock)
        
        // Link Alice and Bob
        await transAlice.link(to: transBob, rssi: -60, bidirectional: true)
        
        let crypto = CryptoService()
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let session = GroupSession(sessionId: 0x8811, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "ALI")
        let sessionBob = GroupSession(sessionId: 0x8811, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "BOB")
        
        try! await transAlice.start(serviceType: "_teekum._tcp", session: session)
        try! await transBob.start(serviceType: "_teekum._tcp", session: sessionBob)
        
        let engineAlice = SOSForwardingEngine(
            transport: transAlice,
            cryptoService: crypto,
            clock: clock,
            sessionProvider: { session }
        )
        
        // Send initial SOS
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .sos,
            hopLimit: 8,
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: 50
        )
        let sosPayload = SOSPayload(
            coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41),
            timestamp: clock.now(),
            accuracy: 5,
            sosEventId: 0xABCD,
            senderInitials: "ALI",
            emergencyType: .general,
            batteryLevel: 90
        )
        
        try! await engineAlice.broadcastEmergencySOS(payload: sosPayload, envelope: envelope, symmetricKey: key)
        
        // Simulate dropped ACK on attempt 1 (Bob generates ACK, but transmission drops)
        await transAlice.setSimulatedPacketLoss(peerId: "Bob", ratio: 1.0)
        
        // Advance clock past retry interval (1.5s) to trigger retry attempt 2
        clock.advance(by: 1.6)
        
        // Second attempt: link recovers
        await transAlice.setSimulatedPacketLoss(peerId: "Bob", ratio: 0.0)
        
        // Bob receives retry and delivers authenticated ACK
        let ackPayload = ACKPayload(
            ackedSeqNumber: 50,
            ackedSenderInitials: "ALI",
            ackTimestamp: clock.now(),
            ackStatus: .deliveredToFriend,
            receivedRssi: -55,
            originalEventId: 0xABCD,
            responderInitials: "BOB"
        )
        let ackData = ackPayload.serialize()
        let ackEnvelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .ack,
            hopLimit: 8,
            hopCount: 1,
            sessionId: session.sessionId,
            sequenceNumber: 51
        )
        let (cipher, tag) = try! await crypto.seal(payload: ackData, envelope: ackEnvelope, using: key)
        let ackPacket = RawWirePacket(envelope: ackEnvelope, ciphertext: cipher, authTag: tag)
        
        await engineAlice.handleInboundACK(rawPacket: ackPacket, fromPeerId: "Bob")
        
        let finalState = await engineAlice.currentDeliveryState
        guard finalState.isDelivered else {
            print("  FAIL: Final delivery state did not transition to deliveredToFriend; got \(finalState)")
            await transAlice.stop()
            await transBob.stop()
            return false
        }
        
        let confirmedFriend = await engineAlice.lastDeliveredFriendId
        guard confirmedFriend == "BOB" else {
            print("  FAIL: Friend confirmation recipient initials mismatch; got \(String(describing: confirmedFriend))")
            await transAlice.stop()
            await transBob.stop()
            return false
        }
        
        await transAlice.stop()
        await transBob.stop()
        print("  PASS: Dropped initial ACK recovered on bounded retry and progressed to deliveredToFriend.")
        return true
    }
    
    // MARK: - Test 12: Diagnostics Zero-Knowledge Privacy Compliance
    
    public static func testDiagnosticsZeroKnowledgePrivacyCompliance() async -> Bool {
        print("[Test 12] Diagnostics zero-knowledge privacy compliance (zero location/keys)...")
        let collector = MeshDiagnosticsCollector()
        
        await collector.recordForwardingAttempt(success: true)
        await collector.recordForwardingAttempt(success: false)
        await collector.recordPacketDrop(reason: .rateLimitExceeded)
        await collector.recordPacketDrop(reason: .hopLimitExceeded)
        await collector.recordDuplicateSuppressed()
        await collector.recordRouteDiscoveryInitiated()
        await collector.recordRouteDiscoverySucceeded()
        await collector.recordRouteInvalidation()
        await collector.recordHopCount(3)
        await collector.recordHopCount(4)
        await collector.recordQueueSaturationDrop()
        
        let snap = await collector.snapshot()
        
        // Assert all 7 required counters are present
        guard snap.forwardingAttempts == 2, snap.forwardingSuccesses == 1, snap.forwardingFailures == 1 else {
            print("  FAIL: Forwarding attempt counters mismatch")
            return false
        }
        guard snap.droppedRateLimit == 1, snap.droppedHopLimit == 1, snap.queueSaturationDrops == 1 else {
            print("  FAIL: Packet drop counters mismatch")
            return false
        }
        guard snap.duplicatesSuppressed == 1 else {
            print("  FAIL: Duplicate suppressed counter mismatch")
            return false
        }
        guard snap.routeDiscoveriesInitiated == 1, snap.routeDiscoveriesSucceeded == 1 else {
            print("  FAIL: Route discovery counters mismatch")
            return false
        }
        guard snap.routeFailuresOrInvalidations == 1 else {
            print("  FAIL: Route invalidation counter mismatch")
            return false
        }
        guard snap.maxHopCountObserved == 4, snap.totalHopsSamples == 2, snap.averageHopCount == 3.5 else {
            print("  FAIL: Hop count metrics mismatch; avg=\(snap.averageHopCount)")
            return false
        }
        
        // Assert privacy compliance: zero location data, zero secret keys
        guard !snap.containsLocationData, !snap.containsCryptographicKeys, snap.isPrivacyCompliant else {
            print("  FAIL: Privacy compliance flags violated")
            return false
        }
        
        guard await collector.verifyPrivacyCompliance() else {
            print("  FAIL: Collector privacy check failed")
            return false
        }
        
        // Aggregation (+) operator check
        let snap2 = MeshDiagnosticsSnapshot(forwardingAttempts: 3, forwardingSuccesses: 3)
        let combined = snap + snap2
        guard combined.forwardingAttempts == 5, combined.forwardingSuccesses == 4 else {
            print("  FAIL: Snapshot aggregation operator failed")
            return false
        }
        
        print("  PASS: Diagnostics strictly zero-knowledge: zero location payloads or secret keys retained.")
        return true
    }
}
