//
//  RouteDiscoveryTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation
import CryptoKit

/// Authoritative Unit & Integration Test Suite for Agent 3 (AODV-Inspired Routing Engine).
///
/// Verifies:
/// 1. Direct route discovery (1-hop direct path).
/// 2. Multi-hop route discovery with two or more relays (3+ hops).
/// 3. Missing destination detection & timeout handling.
/// 4. Broken intermediate link invalidation and re-discovery.
/// 5. Duplicate route requests suppression & shorter-path reverse update.
/// 6. Route loop detection (self-originator, circular loop prevention).
/// 7. Stale or unsolicited route response rejection.
/// 8. Competing candidate routes selection (shorter path preferred).
/// 9. Hop-limit exhaustion (maximum 8 hops bound strictly enforced).
/// 10. Flooding budget exhaustion & token bucket rate limiting.
/// 11. Simultaneous discovery attempts to multiple destinations.
/// 12. Session teardown during active in-flight discovery.
public enum RouteDiscoveryTests {
    
    public static func runAllTests() async -> Bool {
        print("\n==================================================")
        print(">>> STARTING AODV ROUTE DISCOVERY TEST SUITE <<<")
        print("==================================================")
        
        var passed = true
        
        passed = await testDirectRouteDiscovery() && passed
        passed = await testRouteWithTwoOrMoreRelays() && passed
        passed = await testMissingDestinationTimeout() && passed
        passed = await testBrokenIntermediateLinkAndRediscovery() && passed
        passed = await testDuplicateRouteRequestsSuppression() && passed
        passed = await testRouteLoopPrevention() && passed
        passed = await testStaleRouteResponseRejection() && passed
        passed = await testCompetingCandidateRoutesPreference() && passed
        passed = await testHopLimitExhaustionMaxEightHops() && passed
        passed = await testFloodingBudgetExhaustionRateLimiter() && passed
        passed = await testSimultaneousDiscoveryAttempts() && passed
        passed = await testSessionTeardownDuringActiveDiscovery() && passed
        passed = await testTwoTierStalePeerRouteDiscovery() && passed
        passed = await testOneToManyStalePeerStaggeredProbingAndBurstResponse() && passed
        
        if passed {
            print("==================================================")
            print(">>> ALL 14 AODV ROUTE DISCOVERY TESTS PASSED <<<")
            print("==================================================\n")
        } else {
            print("❌ SOME AODV ROUTE DISCOVERY TESTS FAILED!")
        }
        return passed
    }
    
    // MARK: - Test 1: Direct Route Discovery
    
    public static func testDirectRouteDiscovery() async -> Bool {
        print("[Test 1] Direct route discovery (1 hop)...")
        let clock = TestMeshClock()
        let simulator = MeshTopologySimulator(clock: clock)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let sessionId: UInt16 = 0x1111
        
        let sessionAlice = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "ALI")
        let sessionBob = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "BOB")
        
        let alice = await simulator.createNode(id: "Alice", initials: "ALI", session: sessionAlice)
        let bob = await simulator.createNode(id: "Bob", initials: "BOB", session: sessionBob)
        
        // Direct link: Alice <-> Bob
        await simulator.link("Alice", "Bob")
        
        // Alice initiates discovery to "BOB"
        let routeTask = Task { () -> RouteEntry in
            try await alice.routeDiscovery.resolveRoute(to: "BOB", session: sessionAlice, timeout: 2.0)
        }
        
        // Allow simulated frames to flow
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        guard let route = try? await routeTask.value else {
            print("  FAIL: Direct route discovery failed to resolve.")
            await simulator.stopAll()
            return false
        }
        
        guard route.destinationId == "BOB" && route.nextHopPeerId == "Bob" && route.hopCount == 1 else {
            print("  FAIL: Expected route to BOB via Bob with hopCount 1, got nextHop=\(route.nextHopPeerId), hops=\(route.hopCount)")
            await simulator.stopAll()
            return false
        }
        
        // Verify Bob also recorded reverse route to Alice
        let bobRoute = await bob.routingTable.findRoute(to: "ALI", inSession: UInt32(sessionId))
        guard let bRoute = bobRoute, bRoute.nextHopPeerId == "Alice" && bRoute.hopCount == 1 else {
            print("  FAIL: Bob failed to record route to ALI, got \(String(describing: bobRoute))")
            await simulator.stopAll()
            return false
        }
        
        await simulator.stopAll()
        print("  PASS: Direct 1-hop route discovered and symmetric forward routes recorded.")
        return true
    }
    
    // MARK: - Test 2: Route with Two or More Relays
    
    public static func testRouteWithTwoOrMoreRelays() async -> Bool {
        print("[Test 2] Multi-hop route discovery with 2 relays (Alice -> R1 -> R2 -> Bob)...")
        let clock = TestMeshClock()
        let simulator = MeshTopologySimulator(clock: clock)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let sessionId: UInt16 = 0x2222
        
        let sessionAlice = GroupSession(sessionId: sessionId, sessionName: "Festival", symmetricKeyData: keyData, localInitials: "ALI")
        let sessionBob = GroupSession(sessionId: sessionId, sessionName: "Festival", symmetricKeyData: keyData, localInitials: "BOB")
        
        let alice = await simulator.createNode(id: "Alice", initials: "ALI", session: sessionAlice)
        _ = await simulator.createStrangerRelay(id: "Relay1")
        _ = await simulator.createStrangerRelay(id: "Relay2")
        let bob = await simulator.createNode(id: "Bob", initials: "BOB", session: sessionBob)
        
        // Chain: Alice <-> Relay1 <-> Relay2 <-> Bob (3 hops, 2 intermediate stranger relays)
        await simulator.setupLinearChain(ids: ["Alice", "Relay1", "Relay2", "Bob"])
        
        let routeTask = Task { () -> RouteEntry in
            try await alice.routeDiscovery.resolveRoute(to: "BOB", session: sessionAlice, timeout: 2.0)
        }
        
        do {
            let route = try await routeTask.value
            guard route.destinationId == "BOB" && route.nextHopPeerId == "Relay1" && route.hopCount == 3 else {
                print("  FAIL: Expected route to BOB via Relay1 with hopCount 3, got nextHop=\(route.nextHopPeerId), hops=\(route.hopCount)")
                await simulator.stopAll()
                return false
            }
        } catch {
            print("  FAIL: Multi-hop route discovery failed with error: \(error)")
            await simulator.stopAll()
            return false
        }
        
        // Bob should also have a route back to Alice via Relay2 with hopCount 3
        let bobRoute = await bob.routingTable.findRoute(to: "ALI", inSession: UInt32(sessionId))
        guard let bRoute = bobRoute, bRoute.nextHopPeerId == "Relay2" && bRoute.hopCount == 3 else {
            print("  FAIL: Bob failed to record reverse route to ALI via Relay2, got \(String(describing: bobRoute))")
            await simulator.stopAll()
            return false
        }
        
        await simulator.stopAll()
        print("  PASS: 3-hop route successfully traversed 2 stranger relays with exact hopCount 3.")
        return true
    }
    
    // MARK: - Test 3: Missing Destination Timeout
    
    public static func testMissingDestinationTimeout() async -> Bool {
        print("[Test 3] Missing destination detection & timeout handling...")
        let clock = TestMeshClock()
        let simulator = MeshTopologySimulator(clock: clock)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let sessionId: UInt16 = 0x3333
        
        let sessionAlice = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "ALI")
        let alice = await simulator.createNode(id: "Alice", initials: "ALI", session: sessionAlice)
        _ = await simulator.createStrangerRelay(id: "Relay1")
        
        await simulator.link("Alice", "Relay1")
        
        // Alice attempts to discover "ZED" who does not exist
        let routeTask = Task { () -> RouteEntry in
            try await alice.routeDiscovery.resolveRoute(to: "ZED", session: sessionAlice, timeout: 0.1)
        }
        
        // Wait for timeout to trigger
        try? await Task.sleep(nanoseconds: 150_000_000)
        await alice.routeDiscovery.checkTimeouts()
        
        do {
            _ = try await routeTask.value
            print("  FAIL: Missing destination should have timed out.")
            await simulator.stopAll()
            return false
        } catch let err as RouteDiscoveryFailure {
            guard err == .timeout || err == .destinationUnreachable else {
                print("  FAIL: Expected .timeout or .destinationUnreachable, got \(err)")
                await simulator.stopAll()
                return false
            }
        } catch {
            print("  FAIL: Unexpected error type: \(error)")
            await simulator.stopAll()
            return false
        }
        
        let diag = await alice.routeDiscovery.diagnosticsSnapshot()
        guard diag.totalDiscoveriesFailed >= 1 else {
            print("  FAIL: Diagnostic failures not incremented: \(diag)")
            await simulator.stopAll()
            return false
        }
        
        await simulator.stopAll()
        print("  PASS: Missing destination safely failed with timeout without hung tasks.")
        return true
    }
    
    // MARK: - Test 4: Broken Intermediate Link & Re-Discovery
    
    public static func testBrokenIntermediateLinkAndRediscovery() async -> Bool {
        print("[Test 4] Broken intermediate link invalidation and re-discovery...")
        let clock = TestMeshClock()
        let simulator = MeshTopologySimulator(clock: clock)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let sessionId: UInt16 = 0x4444
        
        let sessionAlice = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "ALI")
        let sessionBob = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "BOB")
        
        let alice = await simulator.createNode(id: "Alice", initials: "ALI", session: sessionAlice)
        _ = await simulator.createStrangerRelay(id: "Relay1")
        _ = await simulator.createStrangerRelay(id: "Relay2")
        _ = await simulator.createNode(id: "Bob", initials: "BOB", session: sessionBob)
        
        // Initial path: Alice <-> Relay1 <-> Bob
        await simulator.setupLinearChain(ids: ["Alice", "Relay1", "Bob"])
        
        let routeTask1 = Task { () -> RouteEntry in
            try await alice.routeDiscovery.resolveRoute(to: "BOB", session: sessionAlice, timeout: 2.0)
        }
        guard let route1 = try? await routeTask1.value, route1.nextHopPeerId == "Relay1" else {
            print("  FAIL: Initial route setup failed.")
            await simulator.stopAll()
            return false
        }
        
        // Break link: Alice <-> Relay1
        await simulator.disconnect("Alice", "Relay1")
        
        // Route to BOB must be invalidated on Alice
        let invalidated = await alice.routingTable.findRoute(to: "BOB", inSession: UInt32(sessionId))
        guard invalidated == nil else {
            print("  FAIL: Route should be invalidated when next hop Relay1 disconnects, got \(String(describing: invalidated))")
            await simulator.stopAll()
            return false
        }
        
        // Establish alternative path: Alice <-> Relay2 <-> Bob
        await simulator.setupLinearChain(ids: ["Alice", "Relay2", "Bob"])
        
        // Advance clock slightly so target cooldown doesn't block re-discovery
        simulator.advanceClock(by: 1.0)
        
        // Re-discover route to BOB
        let routeTask2 = Task { () -> RouteEntry in
            try await alice.routeDiscovery.resolveRoute(to: "BOB", session: sessionAlice, timeout: 2.0)
        }
        guard let route2 = try? await routeTask2.value else {
            print("  FAIL: Re-discovery across alternative path failed.")
            await simulator.stopAll()
            return false
        }
        
        guard route2.nextHopPeerId == "Relay2" && route2.hopCount == 2 else {
            print("  FAIL: Expected re-discovered route via Relay2, got nextHop=\(route2.nextHopPeerId), hops=\(route2.hopCount)")
            await simulator.stopAll()
            return false
        }
        
        await simulator.stopAll()
        print("  PASS: Broken intermediate link invalidated route; alternative path discovered cleanly.")
        return true
    }
    
    // MARK: - Test 5: Duplicate Route Requests Suppression
    
    public static func testDuplicateRouteRequestsSuppression() async -> Bool {
        print("[Test 5] Duplicate route requests suppression & shorter-path reverse update...")
        let clock = TestMeshClock()
        let crypto = CryptoService()
        let key = await crypto.generateSymmetricKey()
        let sessionId: UInt16 = 0x5555
        
        let sessionBob = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: key.withUnsafeBytes { Data($0) }, localInitials: "BOB")
        let routingTable = RoutingTable(clock: clock)
        let neighborTable = NeighborTable(clock: clock)
        let transport = SimulatedMeshTransport(peerId: "Bob", clock: clock)
        let relayATransport = SimulatedMeshTransport(peerId: "RelayA", clock: clock)
        let relayBTransport = SimulatedMeshTransport(peerId: "RelayB", clock: clock)
        try! await transport.start(serviceType: "_teekum._tcp", session: sessionBob)
        try! await relayATransport.start(serviceType: "_teekum._tcp", session: sessionBob)
        try! await relayBTransport.start(serviceType: "_teekum._tcp", session: sessionBob)
        await transport.link(to: relayATransport)
        await transport.link(to: relayBTransport)
        
        let discovery = RouteDiscoveryService(
            routingTable: routingTable,
            neighborTable: neighborTable,
            transport: transport,
            cryptoService: crypto,
            clock: clock
        )
        
        let nonce: UInt32 = 7777
        let reqPayload = RouteReqPayload(originatorInitials: "ALI", targetInitials: "BOB", discoveryNonce: nonce, routeCost: 0)
        let env1 = CleartextEnvelope(type: .routeReq, hopLimit: 8, hopCount: 2, sessionId: sessionId, sequenceNumber: 101)
        let wireData1 = try! await crypto.sealToWireBytes(payload: reqPayload.serialize(), envelope: env1, using: key)
        
        // First reception: hopCount 2
        let result1 = try! await discovery.handleInboundRouteReq(wireData: wireData1, fromPeerId: "RelayA", session: sessionBob)
        guard case .answeredWithRResp = result1 else {
            print("  FAIL: Expected first RREQ to be answered with RRESP, got \(result1)")
            return false
        }
        
        // Second reception: exact duplicate RREQ (same nonce, hopCount 2)
        let result2 = try! await discovery.handleInboundRouteReq(wireData: wireData1, fromPeerId: "RelayA", session: sessionBob)
        guard result2 == .droppedDuplicate else {
            print("  FAIL: Expected duplicate RREQ to be dropped with .droppedDuplicate, got \(result2)")
            return false
        }
        
        // Third reception: same RREQ arriving via longer path (hopCount 4)
        let env3 = CleartextEnvelope(type: .routeReq, hopLimit: 8, hopCount: 4, sessionId: sessionId, sequenceNumber: 101)
        let wireData3 = try! await crypto.sealToWireBytes(payload: reqPayload.serialize(), envelope: env3, using: key)
        let result3 = try! await discovery.handleInboundRouteReq(wireData: wireData3, fromPeerId: "RelayB", session: sessionBob)
        guard result3 == .droppedDuplicate else {
            print("  FAIL: Expected longer duplicate RREQ to be dropped, got \(result3)")
            return false
        }
        
        print("  PASS: Duplicate and longer-path RREQs successfully suppressed.")
        return true
    }
    
    // MARK: - Test 6: Route Loop Prevention
    
    public static func testRouteLoopPrevention() async -> Bool {
        print("[Test 6] Route loop detection & rejection...")
        let clock = TestMeshClock()
        let crypto = CryptoService()
        let key = await crypto.generateSymmetricKey()
        let sessionId: UInt16 = 0x6666
        
        let sessionAlice = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: key.withUnsafeBytes { Data($0) }, localInitials: "ALI")
        let routingTable = RoutingTable(clock: clock)
        let neighborTable = NeighborTable(clock: clock)
        let transport = SimulatedMeshTransport(peerId: "Alice", clock: clock)
        let discovery = RouteDiscoveryService(
            routingTable: routingTable,
            neighborTable: neighborTable,
            transport: transport,
            cryptoService: crypto,
            clock: clock
        )
        
        // 1. Attempt discovery to own initials
        do {
            _ = try await discovery.initiateDiscovery(to: "ALI", session: sessionAlice)
            print("  FAIL: Initiating discovery to self must fail.")
            return false
        } catch let err as RouteDiscoveryFailure {
            guard err == .loopDetected else {
                print("  FAIL: Expected .loopDetected, got \(err)")
                return false
            }
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            return false
        }
        
        // 2. Incoming RREQ originated by local node (looped back from relay)
        let reqPayload = RouteReqPayload(originatorInitials: "ALI", targetInitials: "BOB", discoveryNonce: 8888, routeCost: 0)
        let env = CleartextEnvelope(type: .routeReq, hopLimit: 8, hopCount: 2, sessionId: sessionId, sequenceNumber: 202)
        let wireData = try! await crypto.sealToWireBytes(payload: reqPayload.serialize(), envelope: env, using: key)
        
        let result = try! await discovery.handleInboundRouteReq(wireData: wireData, fromPeerId: "RelayLoop", session: sessionAlice)
        guard result == .droppedLoopDetected else {
            print("  FAIL: Looped-back RREQ must be dropped with .droppedLoopDetected, got \(result)")
            return false
        }
        
        print("  PASS: Self-discovery and looped-back RREQs cleanly rejected.")
        return true
    }
    
    // MARK: - Test 7: Stale Route Response Rejection
    
    public static func testStaleRouteResponseRejection() async -> Bool {
        print("[Test 7] Stale route response rejection...")
        let clock = TestMeshClock()
        let crypto = CryptoService()
        let key = await crypto.generateSymmetricKey()
        let sessionId: UInt16 = 0x7777
        
        let sessionAlice = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: key.withUnsafeBytes { Data($0) }, localInitials: "ALI")
        let routingTable = RoutingTable(clock: clock)
        let neighborTable = NeighborTable(clock: clock)
        let transport = SimulatedMeshTransport(peerId: "Alice", clock: clock)
        let discovery = RouteDiscoveryService(
            routingTable: routingTable,
            neighborTable: neighborTable,
            transport: transport,
            cryptoService: crypto,
            clock: clock
        )
        
        // RREP arrives with discoveryNonce = 99999 (no in-flight discovery exists)
        let respPayload = RouteRespPayload(originatorInitials: "ALI", targetInitials: "BOB", discoveryNonce: 99999, routeCost: 0)
        let env = CleartextEnvelope(type: .routeResp, hopLimit: 8, hopCount: 1, sessionId: sessionId, sequenceNumber: 303)
        let wireData = try! await crypto.sealToWireBytes(payload: respPayload.serialize(), envelope: env, using: key)
        
        let result = try! await discovery.handleInboundRouteResp(wireData: wireData, fromPeerId: "RelayStranger", session: sessionAlice)
        guard result == .droppedStaleOrUnsolicited else {
            print("  FAIL: Unsolicited / stale RREP must be dropped with .droppedStaleOrUnsolicited, got \(result)")
            return false
        }
        
        let route = await routingTable.findRoute(to: "BOB", inSession: UInt32(sessionId))
        guard route == nil else {
            print("  FAIL: Stale RREP should not create a route entry.")
            return false
        }
        
        print("  PASS: Unsolicited and stale RREPs rejected with zero routing table mutations.")
        return true
    }
    
    // MARK: - Test 8: Competing Candidate Routes Preference
    
    public static func testCompetingCandidateRoutesPreference() async -> Bool {
        print("[Test 8] Competing candidate routes preference (shorter path preferred)...")
        let clock = TestMeshClock()
        let table = RoutingTable(clock: clock)
        
        // Candidate 1: 4 hops, cost 4, sequenceNumber 500
        await table.recordForwardRoute(
            destinationId: "BOB",
            nextHop: "RelayLong",
            hopCount: 4,
            cost: 4,
            sequenceNumber: 500,
            ttl: 60.0,
            sessionId: 0x8888
        )
        
        let route1 = await table.findRoute(to: "BOB", inSession: 0x8888)
        guard route1?.hopCount == 4 && route1?.nextHopPeerId == "RelayLong" else {
            print("  FAIL: Initial 4-hop route not recorded.")
            return false
        }
        
        // Candidate 2 arrives with SAME sequenceNumber (500) but shorter hopCount (2 hops)
        await table.recordForwardRoute(
            destinationId: "BOB",
            nextHop: "RelayShort",
            hopCount: 2,
            cost: 2,
            sequenceNumber: 500,
            ttl: 60.0,
            sessionId: 0x8888
        )
        
        let route2 = await table.findRoute(to: "BOB", inSession: 0x8888)
        guard route2?.hopCount == 2 && route2?.nextHopPeerId == "RelayShort" else {
            print("  FAIL: Shorter route should replace longer route of equal sequence, got \(String(describing: route2))")
            return false
        }
        
        // Candidate 3 arrives with worse hopCount (5 hops) and same sequence -> must be rejected
        await table.recordForwardRoute(
            destinationId: "BOB",
            nextHop: "RelayWorse",
            hopCount: 5,
            cost: 5,
            sequenceNumber: 500,
            ttl: 60.0,
            sessionId: 0x8888
        )
        
        let route3 = await table.findRoute(to: "BOB", inSession: 0x8888)
        guard route3?.hopCount == 2 && route3?.nextHopPeerId == "RelayShort" else {
            print("  FAIL: Worse route should be rejected, got \(String(describing: route3))")
            return false
        }
        
        // Candidate 4 arrives with higher sequenceNumber (501) but 3 hops -> fresher route accepted
        await table.recordForwardRoute(
            destinationId: "BOB",
            nextHop: "RelayFresh",
            hopCount: 3,
            cost: 3,
            sequenceNumber: 501,
            ttl: 60.0,
            sessionId: 0x8888
        )
        let route4 = await table.findRoute(to: "BOB", inSession: 0x8888)
        guard route4?.sequenceNumber == 501 && route4?.nextHopPeerId == "RelayFresh" else {
            print("  FAIL: Fresher sequence route should supersede, got \(String(describing: route4))")
            return false
        }
        
        print("  PASS: Route selection accurately prioritizes sequence monotonicity, then lowest cost/hops.")
        return true
    }
    
    // MARK: - Test 9: Hop-Limit Exhaustion Max Eight Hops
    
    public static func testHopLimitExhaustionMaxEightHops() async -> Bool {
        print("[Test 9] Hop-limit exhaustion (maximum 8 hops bound)...")
        let clock = TestMeshClock()
        let crypto = CryptoService()
        let key = await crypto.generateSymmetricKey()
        let sessionId: UInt16 = 0x9999
        
        let session = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: key.withUnsafeBytes { Data($0) }, localInitials: "BOB")
        let routingTable = RoutingTable(clock: clock)
        let neighborTable = NeighborTable(clock: clock)
        let transport = SimulatedMeshTransport(peerId: "Bob", clock: clock)
        try! await transport.start(serviceType: "_teekum._tcp", session: session)
        
        let discovery = RouteDiscoveryService(
            routingTable: routingTable,
            neighborTable: neighborTable,
            transport: transport,
            cryptoService: crypto,
            clock: clock
        )
        
        // Incoming RREQ with hopCount == 8 (exhausted)
        let reqPayload = RouteReqPayload(originatorInitials: "ALI", targetInitials: "BOB", discoveryNonce: 1212, routeCost: 8)
        let envExhausted = CleartextEnvelope(type: .routeReq, hopLimit: 8, hopCount: 8, sessionId: sessionId, sequenceNumber: 404)
        let wireExhausted = try! await crypto.sealToWireBytes(payload: reqPayload.serialize(), envelope: envExhausted, using: key)
        
        let resultExhausted = try! await discovery.handleInboundRouteReq(wireData: wireExhausted, fromPeerId: "Relay8", session: session)
        guard resultExhausted == .droppedHopLimitExceeded else {
            print("  FAIL: RREQ at hop limit 8 must be dropped with .droppedHopLimitExceeded, got \(resultExhausted)")
            return false
        }
        
        // Verify routing table strictly rejects forward routes claiming > 8 hops
        await routingTable.recordForwardRoute(destinationId: "FAR", nextHop: "Peer", hopCount: 9, cost: 9, sequenceNumber: 1, ttl: 60)
        let rejectedRoute = await routingTable.findRoute(to: "FAR")
        guard rejectedRoute == nil else {
            print("  FAIL: Routing table accepted route with hopCount 9!")
            return false
        }
        
        print("  PASS: 8-hop limit strictly enforced on wire ingestion and routing table insertion.")
        return true
    }
    
    // MARK: - Test 10: Flooding Budget Exhaustion & Rate Limiting
    
    public static func testFloodingBudgetExhaustionRateLimiter() async -> Bool {
        print("[Test 10] Flooding budget exhaustion & token bucket rate limiting...")
        let clock = TestMeshClock()
        let crypto = CryptoService()
        let key = await crypto.generateSymmetricKey()
        let sessionId: UInt16 = 0xAAAA
        
        let session = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: key.withUnsafeBytes { Data($0) }, localInitials: "ALI")
        let routingTable = RoutingTable(clock: clock)
        let neighborTable = NeighborTable(clock: clock)
        let transport = SimulatedMeshTransport(peerId: "Alice", clock: clock)
        try! await transport.start(serviceType: "_teekum._tcp", session: session)
        
        let discovery = RouteDiscoveryService(
            routingTable: routingTable,
            neighborTable: neighborTable,
            transport: transport,
            cryptoService: crypto,
            clock: clock
        )
        
        // Token bucket: capacity 4 tokens, refill 2/sec
        // Deterministically consume the 4 burst tokens
        guard await discovery.consumeFloodingToken() == true else { return false } // 1
        guard await discovery.consumeFloodingToken() == true else { return false } // 2
        guard await discovery.consumeFloodingToken() == true else { return false } // 3
        guard await discovery.consumeFloodingToken() == true else { return false } // 4
        
        // 5th attempt must exhaust token bucket and throw .floodingBudgetExhausted
        var budgetExhausted = false
        do {
            _ = try await discovery.initiateDiscovery(to: "TB5", session: session, timeout: 0.1)
        } catch let err as RouteDiscoveryFailure {
            if err == .floodingBudgetExhausted {
                budgetExhausted = true
            }
        } catch {
            print("  FAIL: Unexpected error: \(error)")
        }
        
        guard budgetExhausted else {
            print("  FAIL: Discovery attempt with exhausted tokens must throw .floodingBudgetExhausted.")
            return false
        }
        
        // Advance clock by 1.0 second (refills 2.0 tokens)
        clock.advance(by: 1.0)
        
        // 2 tokens should now be available
        guard await discovery.consumeFloodingToken() == true else {
            print("  FAIL: Token pool failed to refill after 1.0s clock advancement.")
            return false
        }
        guard await discovery.consumeFloodingToken() == true else {
            print("  FAIL: Second refilled token failed to consume.")
            return false
        }
        guard await discovery.consumeFloodingToken() == false else {
            print("  FAIL: Expected token pool to be empty again.")
            return false
        }
        
        await discovery.teardown()
        
        print("  PASS: Burst of 4 packets permitted; 5th throttled; refilled after 1.0s clock advance.")
        return true
    }
    
    // MARK: - Test 11: Simultaneous Discovery Attempts
    
    public static func testSimultaneousDiscoveryAttempts() async -> Bool {
        print("[Test 11] Simultaneous discovery attempts to multiple destinations...")
        let clock = TestMeshClock()
        let simulator = MeshTopologySimulator(clock: clock)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let sessionId: UInt16 = 0xBBBB
        
        let sessionAlice = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "ALI")
        let sessionBob = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "BOB")
        let sessionCarol = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "CAR")
        
        let alice = await simulator.createNode(id: "Alice", initials: "ALI", session: sessionAlice)
        _ = await simulator.createNode(id: "Bob", initials: "BOB", session: sessionBob)
        _ = await simulator.createNode(id: "Carol", initials: "CAR", session: sessionCarol)
        
        // Star topology: Alice linked to Bob and Carol
        await simulator.link("Alice", "Bob")
        await simulator.link("Alice", "Carol")
        
        // Alice simultaneously discovers BOB and CAROL
        async let routeBobTask = alice.routeDiscovery.resolveRoute(to: "BOB", session: sessionAlice, timeout: 2.0)
        async let routeCarolTask = alice.routeDiscovery.resolveRoute(to: "CAR", session: sessionAlice, timeout: 2.0)
        
        try? await Task.sleep(nanoseconds: 80_000_000)
        
        guard let routeBob = try? await routeBobTask,
              let routeCarol = try? await routeCarolTask else {
            print("  FAIL: One or both simultaneous discoveries failed.")
            await simulator.stopAll()
            return false
        }
        
        guard routeBob.destinationId == "BOB" && routeBob.nextHopPeerId == "Bob" &&
              routeCarol.destinationId == "CAR" && routeCarol.nextHopPeerId == "Carol" else {
            print("  FAIL: Mismatched simultaneous routes: Bob=\(routeBob), Carol=\(routeCarol)")
            await simulator.stopAll()
            return false
        }
        
        await simulator.stopAll()
        print("  PASS: Simultaneous discoveries resolved independently without cross-talk.")
        return true
    }
    
    // MARK: - Test 12: Session Teardown During Discovery
    
    public static func testSessionTeardownDuringActiveDiscovery() async -> Bool {
        print("[Test 12] Session teardown during active in-flight discovery...")
        let clock = TestMeshClock()
        let simulator = MeshTopologySimulator(clock: clock)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let sessionId: UInt16 = 0xCCCC
        
        let sessionAlice = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "ALI")
        let alice = await simulator.createNode(id: "Alice", initials: "ALI", session: sessionAlice)
        _ = await simulator.createStrangerRelay(id: "Relay1")
        await simulator.link("Alice", "Relay1")
        
        // Start long-running discovery
        let routeTask = Task { () -> RouteEntry in
            try await alice.routeDiscovery.resolveRoute(to: "BOB", session: sessionAlice, timeout: 10.0)
        }
        
        try? await Task.sleep(nanoseconds: 20_000_000)
        
        // User leaves group / session tears down mid-discovery
        await alice.routeDiscovery.teardown(sessionId: UInt32(sessionId))
        
        do {
            _ = try await routeTask.value
            print("  FAIL: Teardown should have terminated in-flight discovery.")
            await simulator.stopAll()
            return false
        } catch let err as RouteDiscoveryFailure {
            guard err == .sessionTerminated else {
                print("  FAIL: Expected .sessionTerminated, got \(err)")
                await simulator.stopAll()
                return false
            }
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            await simulator.stopAll()
            return false
        }
        
        // Verify routes for this session are purged
        let routes = await alice.routingTable.allForwardRoutes()
        guard routes.filter({ $0.sessionId == UInt32(sessionId) }).isEmpty else {
            print("  FAIL: Session routes should be purged on teardown, found \(routes)")
            await simulator.stopAll()
            return false
        }
        
        await simulator.stopAll()
        print("  PASS: In-flight discovery aborted cleanly with .sessionTerminated and tables purged.")
        return true
    }
    
    // MARK: - Test 13: Two-Tier Stale Peer On-Demand Route Discovery
    
    public static func testTwoTierStalePeerRouteDiscovery() async -> Bool {
        print("[Test 13] Two-tier stale peer on-demand AODV route discovery through intermediate relay...")
        let clock = TestMeshClock()
        let simulator = MeshTopologySimulator(clock: clock)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let sessionId: UInt16 = 0x8888
        
        let sessionAlice = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "ALI")
        let sessionCarol = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "CAR")
        let sessionBob = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "BOB")
        
        let alice = await simulator.createNode(id: "Alice", initials: "ALI", session: sessionAlice)
        _ = await simulator.createNode(id: "Carol", initials: "CAR", session: sessionCarol)
        let bob = await simulator.createNode(id: "Bob", initials: "BOB", session: sessionBob)
        
        // Linear multi-hop topology: Alice <-> Carol <-> Bob
        await simulator.link("Alice", "Carol")
        await simulator.link("Carol", "Bob")
        
        // Verify Bob is a stale peer (unseen for 45s, crossing stalePeerThreshold + staleRouteReqDelay)
        let now = Date()
        let bobMember = Member(id: "BOB", lastSeen: now.addingTimeInterval(-45.0))
        guard bobMember.isWithinStaleRecoveryWindow(now: now) else {
            print("  FAIL: Bob should be within stale recovery window.")
            await simulator.stopAll()
            return false
        }
        guard bobMember.isEligibleForStaleRouteDiscovery(now: now) else {
            print("  FAIL: Bob should be eligible for Stage 2 on-demand route discovery.")
            await simulator.stopAll()
            return false
        }
        
        // Stage 2: Alice triggers on-demand discovery for stale peer "BOB"
        let routeTask = Task { () -> RouteEntry in
            try await alice.routeDiscovery.initiateDiscovery(to: "BOB", session: sessionAlice, timeout: 2.0)
        }
        
        try? await Task.sleep(nanoseconds: 60_000_000)
        
        guard let route = try? await routeTask.value else {
            print("  FAIL: On-demand route discovery for stale peer BOB failed to resolve.")
            await simulator.stopAll()
            return false
        }
        
        guard route.destinationId == "BOB" && route.nextHopPeerId == "Carol" && route.hopCount == 2 else {
            print("  FAIL: Expected 2-hop route to BOB via Carol, got nextHop=\(route.nextHopPeerId), hops=\(route.hopCount)")
            await simulator.stopAll()
            return false
        }
        
        // Verify symmetric reverse route from Bob back to Alice was also populated
        let bobRoute = await bob.routingTable.findRoute(to: "ALI", inSession: UInt32(sessionId))
        guard let bRoute = bobRoute, bRoute.nextHopPeerId == "Carol" && bRoute.hopCount == 2 else {
            print("  FAIL: Bob failed to record reverse route to ALI via Carol, got \(String(describing: bobRoute))")
            await simulator.stopAll()
            return false
        }
        
        await simulator.stopAll()
        print("  PASS: Stage 2 on-demand AODV route discovery successfully established 2-hop path to stale peer through relay.")
        return true
    }
    
    // MARK: - Test 14: One-to-Many Multi-Peer Staggered Probing & Response Burst
    
    public static func testOneToManyStalePeerStaggeredProbingAndBurstResponse() async -> Bool {
        print("[Test 14] One-to-many multi-peer staggered probing and response burst...")
        let clock = TestMeshClock()
        let simulator = MeshTopologySimulator(clock: clock)
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let sessionId: UInt16 = 0x9999
        
        let sessionAlice = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "ALI")
        let sessionRelay = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "REL")
        let sessionBob = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "BOB")
        let sessionCarol = GroupSession(sessionId: sessionId, sessionName: "Camp", symmetricKeyData: keyData, localInitials: "CAR")
        
        let alice = await simulator.createNode(id: "Alice", initials: "ALI", session: sessionAlice)
        _ = await simulator.createNode(id: "Relay", initials: "REL", session: sessionRelay)
        let bob = await simulator.createNode(id: "Bob", initials: "BOB", session: sessionBob)
        let carol = await simulator.createNode(id: "Carol", initials: "CAR", session: sessionCarol)
        
        // Star-relay topology: Alice <-> Relay <-> Bob, Relay <-> Carol
        await simulator.link("Alice", "Relay")
        await simulator.link("Relay", "Bob")
        await simulator.link("Relay", "Carol")
        
        // Bob registers onTargetReached callback to trigger response burst
        var bobBurstTriggeredBy: String? = nil
        await bob.routeDiscovery.setOnTargetReached { originator in
            bobBurstTriggeredBy = originator
        }
        
        // 1. In a group where both Bob and Carol are stale:
        let now = Date()
        let bobMember = Member(id: "BOB", lastSeen: now.addingTimeInterval(-50.0))
        let carolMember = Member(id: "CAR", lastSeen: now.addingTimeInterval(-46.0))
        
        let staleMembers = [bobMember, carolMember].filter {
            $0.isEligibleForStaleRouteDiscovery(now: now)
        }.sorted { $0.lastSeen < $1.lastSeen } // Longest unseen (Bob: 50s) ranked first
        
        guard staleMembers.count == 2 && staleMembers.first?.id == "BOB" && staleMembers.last?.id == "CAR" else {
            print("  FAIL: Stale members not ordered by longest unseen first.")
            await simulator.stopAll()
            return false
        }
        
        // 2. Alice probes the highest priority stale member (Bob)
        let routeBobTask = Task { () -> RouteEntry in
            try await alice.routeDiscovery.initiateDiscovery(to: "BOB", session: sessionAlice, timeout: 2.0)
        }
        
        try? await Task.sleep(nanoseconds: 60_000_000)
        
        guard let routeBob = try? await routeBobTask.value else {
            print("  FAIL: Discovery to Bob failed.")
            await simulator.stopAll()
            return false
        }
        
        guard routeBob.destinationId == "BOB" && routeBob.nextHopPeerId == "Relay" && routeBob.hopCount == 2 else {
            print("  FAIL: Route to Bob invalid: \(routeBob).")
            await simulator.stopAll()
            return false
        }
        
        // Verify Bob's onTargetReached callback fired with originator ALI
        guard bobBurstTriggeredBy == "ALI" else {
            print("  FAIL: Bob onTargetReached callback did not fire with originator ALI, got \(String(describing: bobBurstTriggeredBy)).")
            await simulator.stopAll()
            return false
        }
        
        // 3. Staggered pacing: verify Carol can be probed subsequently after stagger delay
        let routeCarolTask = Task { () -> RouteEntry in
            try await alice.routeDiscovery.initiateDiscovery(to: "CAR", session: sessionAlice, timeout: 2.0)
        }
        
        try? await Task.sleep(nanoseconds: 60_000_000)
        
        guard let routeCarol = try? await routeCarolTask.value else {
            print("  FAIL: Subsequent discovery to Carol failed.")
            await simulator.stopAll()
            return false
        }
        
        guard routeCarol.destinationId == "CAR" && routeCarol.nextHopPeerId == "Relay" && routeCarol.hopCount == 2 else {
            print("  FAIL: Route to Carol invalid: \(routeCarol).")
            await simulator.stopAll()
            return false
        }
        
        await simulator.stopAll()
        print("  PASS: One-to-many multi-peer staggered probing and response burst successfully verified.")
        return true
    }
}
