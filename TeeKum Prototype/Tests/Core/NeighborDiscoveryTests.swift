//
//  NeighborDiscoveryTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation

/// Self-contained verification suite for TeeKum Phase 2 Mesh Transport & Neighbor Management (Agent 1):
/// 1. NeighborTable registry lifecycle, capabilities, and health tracking
/// 2. Stale neighbor detection and two-stage eviction using injected `TestMeshClock`
/// 3. Link health degradation on packet loss and recovery on success
/// 4. Health-based candidate selection (`selectBestNextHop`)
/// 5. Real-time neighbor event streaming (`AsyncStream<NeighborEvent>`)
/// 6. Multi-lane PriorityOutboxQueue bounds (Urgent: 16, Relay: 32 ring buffer, Coalescing)
/// 7. ForwardingRateLimiter token bucket budgets (Ordinary: 2 pkts/s, SOS: 4 pkts/s)
/// 8. Opaque blind forwarding with dedicated hopCount (+1) mutation and byte preservation
/// 9. Forwarding cancellation and queue purging when relay participation is disabled
/// 10. Explicit next-hop failure reporting to the routing layer
/// 11. 3-node simulated in-memory mesh forwarding (Alice -> Relay -> Bob)
/// 12. Stranger peering without group key assumption and loop prevention
public struct NeighborDiscoveryTests {
    
    public static func runAllTests() async -> Bool {
        print("==================================================")
        print(">>> STARTING MESH TRANSPORT & NEIGHBOR TESTS <<<")
        print("==================================================")
        var passed = true
        
        if !(await testNeighborTableLifecycle()) { passed = false }
        if !(await testNeighborDisconnectionAndEviction()) { passed = false }
        if !(await testNeighborLinkHealthAndDegradation()) { passed = false }
        if !(await testBestNextHopSelection()) { passed = false }
        if !(await testNeighborEventStream()) { passed = false }
        if !testPriorityOutboxQueueBoundsAndLanes() { passed = false }
        if !(await testForwardingRateLimiterOrdinaryBudget()) { passed = false }
        if !(await testForwardingRateLimiterSOSBudget()) { passed = false }
        if !(await testOpaqueBlindForwardingHopMutation()) { passed = false }
        if !(await testForwardingRelayCancellation()) { passed = false }
        if !(await testNextHopFailureReporting()) { passed = false }
        if !(await testSimulatedMultiNodeMeshTopology()) { passed = false }
        if !(await testLoopPreventionAndStrangerPeering()) { passed = false }
        
        if passed {
            print("==================================================")
            print(">>> ALL 13 MESH TRANSPORT & NEIGHBOR TESTS PASSED <<<")
            print("==================================================")
        } else {
            print(">>> SOME MESH TRANSPORT TESTS FAILED! <<<")
        }
        return passed
    }
    
    // MARK: - Test Helpers
    
    private static func createValidWirePacket(
        type: PacketType = .locationPing,
        hopLimit: UInt8 = 8,
        hopCount: UInt8 = 0,
        seq: UInt32 = 1,
        sid: UInt16 = 0x1234
    ) -> Data {
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: type,
            hopLimit: hopLimit,
            hopCount: hopCount,
            sessionId: sid,
            sequenceNumber: seq
        )
        let dummyCiphertext = Data(repeating: UInt8(type.rawValue), count: PacketConstants.encryptedPayloadSize)
        let dummyAuthTag = Data(repeating: 0xEE, count: PacketConstants.authTagSize)
        let packet = RawWirePacket(envelope: envelope, ciphertext: dummyCiphertext, authTag: dummyAuthTag)
        return try! packet.toWireData()
    }
    
    // MARK: - Test 1: NeighborTable Lifecycle
    
    public static func testNeighborTableLifecycle() async -> Bool {
        print("[Test 1] NeighborTable: Registry lifecycle, capabilities & telemetry...")
        let clock = TestMeshClock()
        let table = NeighborTable(clock: clock, maxCapacity: 10)
        
        // 1. Initial empty state
        var active = await table.activeNeighbors()
        guard active.isEmpty else {
            print("  FAIL: Table should initially be empty.")
            return false
        }
        
        // 2. Discover new neighbor
        await table.recordNeighborActivity(peerId: "BOB", rssi: -65, isGroupMember: true)
        active = await table.activeNeighbors()
        guard active.count == 1, let bob = active.first else {
            print("  FAIL: Expected 1 active neighbor, got \(active.count).")
            return false
        }
        guard bob.id == "BOB", bob.state == .connected, bob.rssi == -65, bob.isGroupMember else {
            print("  FAIL: Neighbor attributes mismatch.")
            return false
        }
        guard bob.capabilities.contains(.awdlDirect), bob.capabilities.contains(.relayOpaque) else {
            print("  FAIL: Default transport capabilities mismatch.")
            return false
        }
        
        // 3. Register stranger neighbor with custom capabilities
        let customCaps: TransportCapabilities = [.awdlDirect, .bleDirect, .relayOpaque]
        await table.registerOrUpdateNeighbor(
            id: "STRANGER",
            displayName: "Stranger-12",
            state: .connected,
            rssi: -80,
            isGroupMember: false,
            capabilities: customCaps
        )
        
        active = await table.activeNeighbors()
        guard active.count == 2 else {
            print("  FAIL: Expected 2 active neighbors.")
            return false
        }
        
        guard let stranger = await table.neighbor(id: "STRANGER") else {
            print("  FAIL: Stranger not found by ID lookup.")
            return false
        }
        guard stranger.displayName == "Stranger-12", !stranger.isGroupMember, stranger.capabilities == customCaps else {
            print("  FAIL: Stranger metadata mismatch.")
            return false
        }
        
        print("  PASS: NeighborTable lifecycle and capability tracking verified.")
        return true
    }
    
    // MARK: - Test 2: Disconnection & Eviction
    
    public static func testNeighborDisconnectionAndEviction() async -> Bool {
        print("[Test 2] NeighborTable: Disconnection & two-stage eviction with clock...")
        let clock = TestMeshClock()
        let table = NeighborTable(clock: clock, maxCapacity: 10)
        
        await table.recordNeighborActivity(peerId: "NODE_A", rssi: -50, isGroupMember: true)
        await table.recordNeighborActivity(peerId: "NODE_B", rssi: -60, isGroupMember: true)
        
        // Advance clock by 35 seconds (threshold: 30 seconds)
        clock.advance(by: 35)
        
        // Evict stale neighbors
        await table.evictStaleNeighbors(thresholdSeconds: 30)
        
        // Both should now be marked .stale (Stage 1)
        let active = await table.activeNeighbors()
        guard active.isEmpty else {
            print("  FAIL: Active neighbors should be empty after stale eviction, got \(active.count).")
            return false
        }
        
        guard let nodeA = await table.neighbor(id: "NODE_A"), nodeA.state == .stale else {
            print("  FAIL: Node A should be in .stale state.")
            return false
        }
        
        // Refresh NODE_A activity
        await table.recordNeighborActivity(peerId: "NODE_A", rssi: -48, isGroupMember: true)
        guard let nodeARefreshed = await table.neighbor(id: "NODE_A"), nodeARefreshed.state == .connected else {
            print("  FAIL: Node A should have recovered to .connected upon activity.")
            return false
        }
        
        // Advance clock further past 2x threshold (65 seconds elapsed for NODE_B)
        clock.advance(by: 35)
        await table.evictStaleNeighbors(thresholdSeconds: 30)
        
        // NODE_B should be completely purged (Stage 2)
        guard await table.neighbor(id: "NODE_B") == nil else {
            print("  FAIL: Node B should be completely purged from table.")
            return false
        }
        
        // NODE_A explicit disconnect
        await table.removeNeighbor(peerId: "NODE_A")
        guard await table.neighbor(id: "NODE_A") == nil else {
            print("  FAIL: Node A should be removed upon explicit disconnect.")
            return false
        }
        
        print("  PASS: Two-stage eviction and disconnect handling verified.")
        return true
    }
    
    // MARK: - Test 3: Link Health & Degradation
    
    public static func testNeighborLinkHealthAndDegradation() async -> Bool {
        print("[Test 3] NeighborTable: Link health degradation and recovery...")
        let clock = TestMeshClock()
        let table = NeighborTable(clock: clock, maxCapacity: 10)
        
        await table.recordNeighborActivity(peerId: "PEER_1", rssi: -70, isGroupMember: true)
        
        // 1 success
        await table.recordTransmissionOutcome(peerId: "PEER_1", success: true)
        var peer = await table.neighbor(id: "PEER_1")!
        guard peer.state == .connected else {
            print("  FAIL: Expected .connected state.")
            return false
        }
        
        // 2 failures (2 out of 3 failed = 66% loss >= 20% threshold)
        await table.recordTransmissionOutcome(peerId: "PEER_1", success: false)
        await table.recordTransmissionOutcome(peerId: "PEER_1", success: false)
        
        peer = await table.neighbor(id: "PEER_1")!
        guard case let .degraded(lossRatio) = peer.state else {
            print("  FAIL: Expected .degraded state after failures, got \(peer.state).")
            return false
        }
        guard lossRatio > 0.60 else {
            print("  FAIL: Loss ratio mismatch: \(lossRatio).")
            return false
        }
        
        // Recovery: send 25 successful packets to bring loss ratio below 10% (2 / 28 = ~7.1%)
        for _ in 0..<25 {
            await table.recordTransmissionOutcome(peerId: "PEER_1", success: true)
        }
        
        peer = await table.neighbor(id: "PEER_1")!
        guard peer.state == .connected else {
            print("  FAIL: Peer should have recovered to .connected, got \(peer.state).")
            return false
        }
        
        print("  PASS: Packet loss degradation and link health recovery verified.")
        return true
    }
    
    // MARK: - Test 4: Best Next-Hop Selection
    
    public static func testBestNextHopSelection() async -> Bool {
        print("[Test 4] NeighborTable: Health-based best next-hop candidate selection...")
        let clock = TestMeshClock()
        let table = NeighborTable(clock: clock, maxCapacity: 10)
        
        // Peer A: Connected, RSSI -85 dBm (weak)
        await table.registerOrUpdateNeighbor(id: "PEER_A", displayName: nil, state: .connected, rssi: -85, isGroupMember: true)
        
        // Peer B: Connected, RSSI -50 dBm (strong)
        await table.registerOrUpdateNeighbor(id: "PEER_B", displayName: nil, state: .connected, rssi: -50, isGroupMember: true)
        
        // Peer C: Degraded, RSSI -45 dBm
        await table.registerOrUpdateNeighbor(id: "PEER_C", displayName: nil, state: .degraded(packetLossRatio: 0.30), rssi: -45, isGroupMember: true)
        
        // Should pick PEER_B (connected preferred over degraded PEER_C; strong RSSI -50 preferred over -85 PEER_A)
        var best = await table.selectBestNextHop(excluding: [])
        guard best == "PEER_B" else {
            print("  FAIL: Expected PEER_B as best candidate, got \(String(describing: best)).")
            return false
        }
        
        // Exclude PEER_B -> should pick PEER_A (connected preferred over degraded PEER_C)
        best = await table.selectBestNextHop(excluding: ["PEER_B"])
        guard best == "PEER_A" else {
            print("  FAIL: Expected PEER_A when PEER_B is excluded, got \(String(describing: best)).")
            return false
        }
        
        // Exclude PEER_A and PEER_B -> should pick PEER_C (degraded is still reachable fallback)
        best = await table.selectBestNextHop(excluding: ["PEER_A", "PEER_B"])
        guard best == "PEER_C" else {
            print("  FAIL: Expected PEER_C as fallback, got \(String(describing: best)).")
            return false
        }
        
        // Exclude all three -> nil
        best = await table.selectBestNextHop(excluding: ["PEER_A", "PEER_B", "PEER_C"])
        guard best == nil else {
            print("  FAIL: Expected nil when all excluded.")
            return false
        }
        
        print("  PASS: Candidate ranking and exclusion logic verified.")
        return true
    }
    
    // MARK: - Test 5: Real-Time Neighbor Event Stream
    
    public static func testNeighborEventStream() async -> Bool {
        print("[Test 5] NeighborTable: Event streaming (discovered, connected, disconnected)...")
        let clock = TestMeshClock()
        let table = NeighborTable(clock: clock, maxCapacity: 10)
        
        let eventStream = await table.events
        
        // Perform actions in background task
        Task {
            await table.recordNeighborActivity(peerId: "ALICE", rssi: -55, isGroupMember: true)
            await table.setNeighborState(peerId: "ALICE", state: .degraded(packetLossRatio: 0.25))
            await table.removeNeighbor(peerId: "ALICE")
        }
        
        var receivedEvents: [NeighborEvent] = []
        for await event in eventStream {
            receivedEvents.append(event)
            if receivedEvents.count >= 4 { break }
        }
        
        guard receivedEvents.count >= 4 else {
            print("  FAIL: Expected at least 4 events, got \(receivedEvents.count).")
            return false
        }
        
        guard case let .discovered(info1) = receivedEvents[0], info1.id == "ALICE" else {
            print("  FAIL: Expected .discovered event first.")
            return false
        }
        guard case let .connected(info2) = receivedEvents[1], info2.id == "ALICE" else {
            print("  FAIL: Expected .connected event second.")
            return false
        }
        guard case let .stateChanged(pId, _, newState) = receivedEvents[2], pId == "ALICE", case .degraded = newState else {
            print("  FAIL: Expected .stateChanged event third.")
            return false
        }
        guard case let .disconnected(pId2) = receivedEvents[3], pId2 == "ALICE" else {
            print("  FAIL: Expected .disconnected event fourth.")
            return false
        }
        
        print("  PASS: Real-time neighbor event streaming verified.")
        return true
    }
    
    // MARK: - Test 6: PriorityOutboxQueue Bounds & Lanes
    
    public static func testPriorityOutboxQueueBoundsAndLanes() -> Bool {
        print("[Test 6] PriorityOutboxQueue: Bounds (Urgent: 16, Relay: 32) & lane priorities...")
        let queue = PriorityOutboxQueue(maxUrgentCapacity: 16, maxRelayCapacity: 32)
        
        // 1. Fill urgent lane to capacity (16 packets)
        do {
            for i in 1...16 {
                let data = createValidWirePacket(type: .sos, seq: UInt32(i))
                try queue.enqueue(data: data)
            }
            guard queue.urgentCount == 16 else {
                print("  FAIL: Expected 16 urgent packets in queue.")
                return false
            }
            
            // 17th urgent packet must throw queueFull
            let overflowData = createValidWirePacket(type: .sos, seq: 17)
            do {
                try queue.enqueue(data: overflowData)
                print("  FAIL: Queue should have rejected 17th urgent packet.")
                return false
            } catch TransportError.queueFull {
                // Expected backpressure
            }
        } catch {
            print("  FAIL: Unexpected error during urgent queueing: \(error)")
            return false
        }
        
        // 2. Normal location ping coalescing (only 1 ping stored per destination)
        do {
            let ping1 = createValidWirePacket(type: .locationPing, seq: 100)
            let ping2 = createValidWirePacket(type: .locationPing, seq: 101)
            let ping3 = createValidWirePacket(type: .locationPing, seq: 102)
            
            try queue.enqueue(data: ping1, destinationPeerId: "PEER_X")
            try queue.enqueue(data: ping2, destinationPeerId: "PEER_X")
            try queue.enqueue(data: ping3, destinationPeerId: "PEER_X")
            
            guard queue.obsoletePingsCoalesced == 2 else {
                print("  FAIL: Expected 2 coalesced pings, got \(queue.obsoletePingsCoalesced).")
                return false
            }
        } catch {
            print("  FAIL: Ping coalescing error: \(error)")
            return false
        }
        
        // 3. Stranger relay ring buffer (capacity: 32 packets, drop-head on overflow)
        do {
            for i in 1...35 {
                let relayData = createValidWirePacket(type: .locationPing, seq: UInt32(200 + i))
                try queue.enqueue(data: relayData, destinationPeerId: "NEXT_HOP", isRelay: true)
            }
            guard queue.relayCount == 32 else {
                print("  FAIL: Relay count should be capped at 32, got \(queue.relayCount).")
                return false
            }
            guard queue.relayPacketsDroppedOverflow == 3 else {
                print("  FAIL: Expected 3 dropped relay packets on ring buffer overflow, got \(queue.relayPacketsDroppedOverflow).")
                return false
            }
        } catch {
            print("  FAIL: Relay queue error: \(error)")
            return false
        }
        
        // 4. Verify queueDepth snapshot
        let depth = queue.queueDepth
        guard depth.urgentCount == 16, depth.normalCount == 1, depth.relayCount == 32, depth.total == 49 else {
            print("  FAIL: Queue depth snapshot mismatch: \(depth).")
            return false
        }
        
        // 5. Dequeue priority order: Urgent dequeues before Normal and before Relay
        let item1 = queue.dequeue()
        guard let item1 = item1, item1.packetType == .sos else {
            print("  FAIL: Dequeue priority 1 should be urgent SOS.")
            return false
        }
        
        // Drain urgent items
        while queue.urgentCount > 0 {
            _ = queue.dequeue()
        }
        
        // Priority 2: Stranger relay packet (elevated ahead of routine pings to prevent starvation)
        let relayItem = queue.dequeue()
        guard let relayItem = relayItem, relayItem.isRelay else {
            print("  FAIL: Expected stranger relay packet.")
            return false
        }
        
        // Drain remaining relay items
        while queue.relayCount > 0 {
            _ = queue.dequeue()
        }
        
        // Priority 3: Coalesced normal location ping
        let normalItem = queue.dequeue()
        guard let normalItem = normalItem, normalItem.packetType == .locationPing, !normalItem.isRelay else {
            print("  FAIL: Expected normal coalesced ping.")
            return false
        }
        
        // 6. Test clearRelayQueue()
        queue.clearRelayQueue()
        guard queue.relayCount == 0 else {
            print("  FAIL: Relay queue should be empty after clearRelayQueue().")
            return false
        }
        
        print("  PASS: PriorityOutboxQueue bounds, ring buffer drop-head, and ordering verified.")
        return true
    }
    
    // MARK: - Test 7: ForwardingRateLimiter Ordinary Budget
    
    public static func testForwardingRateLimiterOrdinaryBudget() async -> Bool {
        print("[Test 7] ForwardingRateLimiter: Ordinary relay budget (2 pkts/sec)...")
        let clock = TestMeshClock()
        let limiter = ForwardingRateLimiter(
            clock: clock,
            ordinaryCapacity: 4.0,
            ordinaryRefillRate: 2.0
        )
        
        // Consume 4 available tokens
        for _ in 1...4 {
            let allowed = await limiter.consumeOrdinaryToken()
            guard allowed else {
                print("  FAIL: Expected token to be available.")
                return false
            }
        }
        
        // 5th attempt immediately should fail (burst limit reached)
        let fifth = await limiter.consumeOrdinaryToken()
        guard !fifth else {
            print("  FAIL: 5th token should be blocked by rate limiter.")
            return false
        }
        
        // Advance clock by 0.5s -> 1 token refilled (0.5s * 2.0/s = 1.0)
        clock.advance(by: 0.5)
        let refilledOne = await limiter.consumeOrdinaryToken()
        guard refilledOne else {
            print("  FAIL: Expected 1 token after 0.5s refill.")
            return false
        }
        
        // Exhausted again
        let immediateFollowup = await limiter.consumeOrdinaryToken()
        guard !immediateFollowup else {
            print("  FAIL: Followup token should fail.")
            return false
        }
        
        // Advance clock by 1.0s -> 2 tokens refilled
        clock.advance(by: 1.0)
        let token1 = await limiter.consumeOrdinaryToken()
        let token2 = await limiter.consumeOrdinaryToken()
        let token3 = await limiter.consumeOrdinaryToken()
        guard token1 && token2 && !token3 else {
            print("  FAIL: Exactly 2 tokens should have been refilled over 1.0s.")
            return false
        }
        
        print("  PASS: Ordinary forwarding rate limiter verified with deterministic clock.")
        return true
    }
    
    // MARK: - Test 8: ForwardingRateLimiter SOS Budget
    
    public static func testForwardingRateLimiterSOSBudget() async -> Bool {
        print("[Test 8] ForwardingRateLimiter: SOS priority forwarding budget (4 pkts/sec)...")
        let clock = TestMeshClock()
        let limiter = ForwardingRateLimiter(
            clock: clock,
            sosCapacity: 8.0,
            sosRefillRate: 4.0
        )
        
        // Consume 8 SOS tokens
        for _ in 1...8 {
            let allowed = await limiter.consumeSOSToken()
            guard allowed else {
                print("  FAIL: Expected SOS token to be available.")
                return false
            }
        }
        
        // 9th should fail
        let ninth = await limiter.consumeSOSToken()
        guard !ninth else {
            print("  FAIL: 9th SOS token should be blocked.")
            return false
        }
        
        // Advance clock by 1.0s -> 4 tokens refilled (4.0/s)
        clock.advance(by: 1.0)
        for _ in 1...4 {
            let ok = await limiter.consumeSOSToken()
            guard ok else {
                print("  FAIL: Expected SOS token after 1.0s refill.")
                return false
            }
        }
        
        let blocked = await limiter.consumeSOSToken()
        guard !blocked else {
            print("  FAIL: Should be blocked after consuming refilled tokens.")
            return false
        }
        
        print("  PASS: Urgent SOS priority forwarding rate limiter verified.")
        return true
    }
    
    // MARK: - Test 9: Opaque Blind Forwarding Hop Mutation
    
    public static func testOpaqueBlindForwardingHopMutation() async -> Bool {
        print("[Test 9] MeshTransport: Opaque packet forwarding & hopCount mutation...")
        let clock = TestMeshClock()
        let nodeA = SimulatedMeshTransport(peerId: "NODE_A", clock: clock)
        let nodeB = SimulatedMeshTransport(peerId: "NODE_B", clock: clock)
        
        let dummySession = GroupSession(
            sessionId: 0xBEEF,
            sessionName: "Test",
            localInitials: "AL"
        )
        try! await nodeA.start(serviceType: "_teekum._tcp", session: dummySession)
        try! await nodeB.start(serviceType: "_teekum._tcp", session: dummySession)
        
        // Link Node A -> Node B
        await nodeA.link(to: nodeB, rssi: -50)
        
        // Create packet with hopLimit=8, hopCount=0
        let originalPacket = createValidWirePacket(type: .locationPing, hopLimit: 8, hopCount: 0, seq: 42, sid: 0xCAFE)
        let originalCiphertext = originalPacket.subdata(in: 10..<40)
        let originalAuthTag = originalPacket.subdata(in: 40..<56)
        
        // Setup frame collector on Node B
        let nodeBStream = await nodeB.inboundFrames
        
        // Forward from Node A to Node B
        let outcome = try! await nodeA.forwardFrame(originalPacket, to: "NODE_B")
        guard outcome.isSuccess, outcome.destinationPeerId == "NODE_B" else {
            print("  FAIL: Forwarding outcome reported failure.")
            return false
        }
        
        // Await delivery on Node B
        var receivedFrame: InboundFrame?
        for await frame in nodeBStream {
            receivedFrame = frame
            break
        }
        
        guard let frame = receivedFrame else {
            print("  FAIL: Node B did not receive forwarded frame.")
            return false
        }
        
        // Verify frame was mutated correctly:
        // Byte 1: hopLimit must remain 8
        // Byte 2: hopCount must have incremented from 0 to 1
        let hopLimit = frame.rawData[1]
        let hopCount = frame.rawData[2]
        guard hopLimit == 8 else {
            print("  FAIL: hopLimit should remain 8, got \(hopLimit).")
            return false
        }
        guard hopCount == 1 else {
            print("  FAIL: hopCount should be incremented to 1, got \(hopCount).")
            return false
        }
        
        // Ciphertext and Auth Tag must remain 100% byte-identical
        let receivedCiphertext = frame.rawData.subdata(in: 10..<40)
        let receivedAuthTag = frame.rawData.subdata(in: 40..<56)
        guard receivedCiphertext == originalCiphertext else {
            print("  FAIL: Ciphertext corrupted during forwarding.")
            return false
        }
        guard receivedAuthTag == originalAuthTag else {
            print("  FAIL: Auth tag corrupted during forwarding.")
            return false
        }
        
        // Test hop limit exhaustion: attempt forwarding with hopCount=8, hopLimit=8
        let exhaustedPacket = createValidWirePacket(type: .locationPing, hopLimit: 8, hopCount: 8, seq: 43)
        do {
            _ = try await nodeA.forwardFrame(exhaustedPacket, to: "NODE_B")
            print("  FAIL: Packet with exhausted hopCount should be dropped.")
            return false
        } catch PacketCodecError.hopCountExceededLimit(let count, let limit) {
            guard count == 8, limit == 8 else {
                print("  FAIL: Incorrect hop count exception parameters.")
                return false
            }
        } catch {
            print("  FAIL: Unexpected error on hop exhaustion: \(error)")
            return false
        }
        
        print("  PASS: Opaque blind forwarding byte preservation and hop mutation verified.")
        return true
    }
    
    // MARK: - Test 10: Forwarding Relay Cancellation
    
    public static func testForwardingRelayCancellation() async -> Bool {
        print("[Test 10] MeshTransport: Relay cancellation when participation disabled...")
        let clock = TestMeshClock()
        let transport = SimulatedMeshTransport(peerId: "RELAY_NODE", clock: clock)
        let dummySession = GroupSession(
            sessionId: 0x1111,
            sessionName: "Test",
            localInitials: "BO"
        )
        try! await transport.start(serviceType: "_teekum._tcp", session: dummySession)
        
        // Initially permitted
        guard await transport.isRelayPermitted() else {
            print("  FAIL: Relay should initially be enabled.")
            return false
        }
        
        // Disable relay participation
        await transport.setRelayParticipation(enabled: false)
        guard !(await transport.isRelayPermitted()) else {
            print("  FAIL: Relay should report disabled.")
            return false
        }
        
        // Attempting to forward must immediately fail with relayDisabled
        let packet = createValidWirePacket(type: .locationPing, hopLimit: 8, hopCount: 0)
        do {
            _ = try await transport.forwardFrame(packet, to: "ANY_NODE")
            print("  FAIL: Forwarding should fail when relay is disabled.")
            return false
        } catch TransportError.relayDisabled {
            // Expected
        } catch {
            print("  FAIL: Expected relayDisabled error, got \(error).")
            return false
        }
        
        // Re-enable
        await transport.setRelayParticipation(enabled: true)
        guard await transport.isRelayPermitted() else {
            print("  FAIL: Relay should report enabled after re-enabling.")
            return false
        }
        
        print("  PASS: User-controlled relay participation gating verified.")
        return true
    }
    
    // MARK: - Test 11: Explicit Next-Hop Failure Reporting
    
    public static func testNextHopFailureReporting() async -> Bool {
        print("[Test 11] MeshTransport: Next-hop delivery failure reported to routing...")
        let clock = TestMeshClock()
        let transport = SimulatedMeshTransport(peerId: "NODE_SENDER", clock: clock)
        let dummySession = GroupSession(sessionId: 0x2222, sessionName: "Test", localInitials: "AL")
        try! await transport.start(serviceType: "_teekum._tcp", session: dummySession)
        
        let packet = createValidWirePacket(type: .locationPing, hopLimit: 8, hopCount: 0)
        let sendOutcomeStream = await transport.sendOutcomes
        
        // Attempt sending to a non-existent next hop
        var caughtError: TransportError?
        do {
            _ = try await transport.sendFrame(packet, to: "GHOST_PEER")
        } catch let err as TransportError {
            caughtError = err
        } catch {
            print("  FAIL: Expected TransportError.")
            return false
        }
        
        guard case let .peerNotFound(id) = caughtError, id == "GHOST_PEER" else {
            print("  FAIL: Expected peerNotFound('GHOST_PEER'), got \(String(describing: caughtError)).")
            return false
        }
        
        // Verify outcome stream recorded the failure
        var failureOutcome: SendOutcome?
        for await outcome in sendOutcomeStream {
            failureOutcome = outcome
            break
        }
        
        guard let outcome = failureOutcome, !outcome.isSuccess, outcome.destinationPeerId == "GHOST_PEER" else {
            print("  FAIL: Send outcome stream should record failed outcome.")
            return false
        }
        
        print("  PASS: Next-hop delivery failures explicitly reported without being hidden.")
        return true
    }
    
    // MARK: - Test 12: 3-Node Simulated Mesh Topology
    
    public static func testSimulatedMultiNodeMeshTopology() async -> Bool {
        print("[Test 12] SimulatedMeshTransport: 3-Node Mesh (Alice -> Relay B -> Bob)...")
        let clock = TestMeshClock()
        
        // Node 1: Alice (Distressed member)
        let aliceTransport = SimulatedMeshTransport(peerId: "ALICE", clock: clock)
        let session = GroupSession(sessionId: 0xBEEF, sessionName: "Festival", localInitials: "AL")
        try! await aliceTransport.start(serviceType: "_teekum._tcp", session: session)
        
        // Node 2: Relay Bob (Stranger node on different session, opt-in communal relay)
        let relayTransport = SimulatedMeshTransport(peerId: "RELAY_BOB", clock: clock)
        let strangerSession = GroupSession(sessionId: 0x9999, sessionName: "OtherGroup", localInitials: "BO")
        try! await relayTransport.start(serviceType: "_teekum._tcp", session: strangerSession)
        
        // Node 3: Charlie (Alice's friend in group 0xBEEF)
        let charlieTransport = SimulatedMeshTransport(peerId: "CHARLIE", clock: clock)
        let charlieSession = GroupSession(sessionId: 0xBEEF, sessionName: "Festival", localInitials: "CH")
        try! await charlieTransport.start(serviceType: "_teekum._tcp", session: charlieSession)
        
        // Topography: Alice <-> Relay Bob <-> Charlie (Alice and Charlie cannot reach each other directly)
        await aliceTransport.link(to: relayTransport, rssi: -58, isGroupMember: false)
        await relayTransport.link(to: charlieTransport, rssi: -65, isGroupMember: false)
        
        // Alice verifies only Relay Bob is a direct neighbor
        let aliceNeighbors = await aliceTransport.activeNeighbors()
        guard aliceNeighbors.count == 1, aliceNeighbors.first?.id == "RELAY_BOB" else {
            print("  FAIL: Alice should only have RELAY_BOB as direct neighbor.")
            return false
        }
        
        // Relay Bob verifies both Alice and Charlie are direct neighbors
        let relayNeighbors = await relayTransport.activeNeighbors()
        guard relayNeighbors.count == 2 else {
            print("  FAIL: Relay Bob should have 2 neighbors.")
            return false
        }
        
        // Prepare collector streams
        let relayInbound = await relayTransport.inboundFrames
        let charlieInbound = await charlieTransport.inboundFrames
        
        // 1. Alice creates SOS packet (hopLimit: 8, hopCount: 0) and sends to 1-hop Relay Bob
        let originalSOS = createValidWirePacket(type: .sos, hopLimit: 8, hopCount: 0, seq: 1001, sid: 0xBEEF)
        _ = try! await aliceTransport.sendFrame(originalSOS, to: "RELAY_BOB")
        
        // 2. Relay Bob receives frame from Alice
        var frameAtRelay: InboundFrame?
        for await frame in relayInbound {
            frameAtRelay = frame
            break
        }
        guard let frameAtRelay = frameAtRelay else {
            print("  FAIL: Relay Bob did not receive frame.")
            return false
        }
        guard frameAtRelay.sourcePeerId == "ALICE", frameAtRelay.rawData[2] == 0 else {
            print("  FAIL: Frame at relay mismatch.")
            return false
        }
        
        // 3. Relay Bob blindly forwards packet to Charlie
        _ = try! await relayTransport.forwardFrame(frameAtRelay.rawData, to: "CHARLIE")
        
        // 4. Charlie receives packet from Relay Bob
        var frameAtCharlie: InboundFrame?
        for await frame in charlieInbound {
            frameAtCharlie = frame
            break
        }
        guard let frameAtCharlie = frameAtCharlie else {
            print("  FAIL: Charlie did not receive forwarded packet.")
            return false
        }
        
        // Verify multi-hop properties at destination:
        guard frameAtCharlie.sourcePeerId == "RELAY_BOB" else {
            print("  FAIL: Immediate 1-hop source should be RELAY_BOB.")
            return false
        }
        guard frameAtCharlie.rawData[2] == 1 else {
            print("  FAIL: Cumulative hopCount at Charlie should be 1, got \(frameAtCharlie.rawData[2]).")
            return false
        }
        guard let rawPacket = frameAtCharlie.rawPacket else {
            print("  FAIL: Charlie should be able to decode wire packet envelope.")
            return false
        }
        guard rawPacket.envelope.sessionId == 0xBEEF else {
            print("  FAIL: Session ID at Charlie should match Alice's original session (0xBEEF).")
            return false
        }
        guard rawPacket.envelope.sequenceNumber == 1001 else {
            print("  FAIL: Sequence number should be preserved.")
            return false
        }
        
        print("  PASS: 3-Node mesh simulation Alice -> Relay -> Charlie verified successfully.")
        return true
    }
    
    // MARK: - Test 13: Loop Prevention & Stranger Peering
    
    public static func testLoopPreventionAndStrangerPeering() async -> Bool {
        print("[Test 13] MeshTransport: Stranger peering & forwarding loop prevention...")
        let clock = TestMeshClock()
        let transport = SimulatedMeshTransport(peerId: "NODE_LOCAL", clock: clock)
        let session = GroupSession(sessionId: 0x4444, sessionName: "Local", localInitials: "DA")
        try! await transport.start(serviceType: "_teekum._tcp", session: session)
        
        let strangerNode = SimulatedMeshTransport(peerId: "NODE_STRANGER", clock: clock)
        try! await strangerNode.start(serviceType: "_teekum._tcp", session: session)
        
        // Establish stranger peering
        await transport.link(to: strangerNode, rssi: -72, isGroupMember: false)
        
        let neighbors = await transport.activeNeighbors()
        guard let stranger = neighbors.first(where: { $0.id == "NODE_STRANGER" }) else {
            print("  FAIL: Stranger neighbor not discovered.")
            return false
        }
        guard !stranger.isGroupMember else {
            print("  FAIL: Stranger should not be marked as group member.")
            return false
        }
        
        // Maximum hop limit of 8 enforcement (Decision 7 & Prompt Scope)
        // Packet with hopLimit == 0 (invalid) must be rejected
        var invalidHopPacket = createValidWirePacket(type: .locationPing, hopLimit: 8, hopCount: 0)
        invalidHopPacket[1] = 0x00 // hopLimit = 0, hopCount = 0
        do {
            _ = try await transport.forwardFrame(invalidHopPacket, to: "NODE_STRANGER")
            print("  FAIL: Forwarding should reject hopLimit == 0.")
            return false
        } catch PacketCodecError.invalidHopLimit(let limit) {
            guard limit == 0 else {
                print("  FAIL: Expected limit 0 in exception.")
                return false
            }
        } catch {
            print("  FAIL: Unexpected error on invalid hopLimit: \(error)")
            return false
        }
        
        print("  PASS: Stranger peering and loop protection bounds verified.")
        return true
    }
}
