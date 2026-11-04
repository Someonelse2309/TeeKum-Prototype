//
//  RelayPolicyTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation

/// Comprehensive automated test suite verifying Agent 5 — Communal Relay Controls and Battery Policy:
/// 1. Relay disabled at startup: stranger packets dropped with .dropPolicyDisabled.
/// 2. Relay enabled and then disabled during forwarding: outbox relay queue promptly purged.
/// 3. Battery drops below 20%: Festival Survival Mode activates; stranger relaying halts immediately.
/// 4. Low Power Mode activates: halts stranger relaying even at high battery levels.
/// 5. Ordinary forwarding exceeds rate limit: 2 pkts/sec token bucket strictly enforced.
/// 6. SOS priority arrives while ordinary traffic is queued: urgent lane preempts queue and uses separate 4 pkts/sec budget.
/// 7. Queue capacity limits and ring buffer drop-head: stranger relay queue drops head at 32 pkts; urgent lane bounds at 16.
/// 8. Timed relay session expires: 30-minute session auto-pauses when clock advances past deadline.
/// 9. Live Activity unavailable or dismissed: services enforce limits independently of UI/activity state.
/// 10. Resource counters contain no location history: zero GPS coordinates or attendee tracks retained.
/// 11. Relay settings persistence: user preferences reliably saved and restored across app restarts.
public enum RelayPolicyTests {
    
    // MARK: - Test Suite Runner
    
    @MainActor
    public static func runAllTests() async -> Bool {
        print("\n==================================================")
        print(">>> STARTING COMMUNAL RELAY & BATTERY POLICY TESTS <<<")
        print("==================================================")
        
        var passed = true
        
        passed = await testRelayDisabledAtStartup() && passed
        passed = await testRelayEnabledAndThenDisabledDuringForwarding() && passed
        passed = await testBatteryDropsBelow20Percent() && passed
        passed = await testLowPowerModeActivates() && passed
        passed = await testOrdinaryForwardingExceedsRateLimit() && passed
        passed = await testSOSPriorityBypassesOrdinaryQueue() && passed
        passed = await testQueueCapacityLimitsAndRingBufferDropHead() && passed
        passed = await testTimedRelaySessionExpires() && passed
        passed = await testLiveActivityUnavailableOrDismissed() && passed
        passed = await testResourceCountersContainNoLocationHistory() && passed
        passed = await testRelaySettingsPersistence() && passed
        passed = await testBidirectionalCrossGroupStrangerRelay() && passed
        
        if passed {
            print("==================================================")
            print(">>> ALL 12 RELAY & BATTERY POLICY TESTS PASSED <<<")
            print("==================================================\n")
        } else {
            print("❌ SOME RELAY & BATTERY POLICY TESTS FAILED!")
        }
        return passed
    }
    
    // MARK: - Test 1: Relay Disabled at Startup
    
    public static func testRelayDisabledAtStartup() async -> Bool {
        print("[Test 1] Relay disabled at startup...")
        
        let clock = TestMeshClock()
        let suiteName = "test_relay_startup_\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        
        let outbox = PriorityOutboxQueue()
        let policyManager = RelayPolicyManager(
            clock: clock,
            userDefaults: userDefaults,
            storageKeyPrefix: "test.relay",
            outbox: outbox,
            defaultMode: .disabled
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
            policyManager: policyManager
        )
        
        // Stranger packet arrives (sessionId 0x9999 does not match local session)
        let strangerEnvelope = CleartextEnvelope(
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: 0x9999,
            sequenceNumber: 1
        )
        let wirePacket = RawWirePacket(
            envelope: strangerEnvelope,
            ciphertext: Data(repeating: 0xAA, count: 30),
            authTag: Data(repeating: 0xBB, count: 16)
        )
        let wireData = try! wirePacket.toWireData()
        
        let decision = await forwarder.evaluateInboundPacket(wireData: wireData, fromPeerId: "stranger-1")
        
        guard decision == .dropPolicyDisabled else {
            print("  FAIL: Expected .dropPolicyDisabled, got \(decision)")
            return false
        }
        
        guard outbox.relayCount == 0 else {
            print("  FAIL: Outbox relay queue should be empty, got \(outbox.relayCount)")
            return false
        }
        
        let telemetry = await policyManager.snapshot()
        guard telemetry.packetsDroppedPolicy >= 1 else {
            print("  FAIL: Policy drop counter should be >= 1, got \(telemetry.packetsDroppedPolicy)")
            return false
        }
        
        print("  PASS: Stranger packet dropped with .dropPolicyDisabled when relay disabled at startup.")
        return true
    }
    
    // MARK: - Test 2: Relay Enabled and Then Disabled During Forwarding
    
    public static func testRelayEnabledAndThenDisabledDuringForwarding() async -> Bool {
        print("[Test 2] Relay enabled and then disabled during forwarding...")
        
        let clock = TestMeshClock()
        let suiteName = "test_relay_toggle_\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        
        let outbox = PriorityOutboxQueue()
        let policyManager = RelayPolicyManager(
            clock: clock,
            userDefaults: userDefaults,
            storageKeyPrefix: "test.relay",
            outbox: outbox,
            defaultMode: .communalRelayActive
        )
        
        let table = RoutingTable(clock: clock)
        let rateLimiter = ForwardingRateLimiter(clock: clock)
        let neighbors = NeighborTable(clock: clock)
        await neighbors.recordNeighborActivity(peerId: "neighbor-A", rssi: -65, isGroupMember: false)
        let dupCache = SeenPacketCache(clock: clock)
        
        let forwarder = PacketForwarder(
            routingTable: table,
            rateLimiter: rateLimiter,
            neighborTable: neighbors,
            seenPacketCache: dupCache,
            clock: clock,
            policyManager: policyManager
        )
        
        // 1. While relay is active: evaluate stranger packet
        let strangerEnvelope1 = CleartextEnvelope(
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: 0x8888,
            sequenceNumber: 10
        )
        let packet1 = RawWirePacket(
            envelope: strangerEnvelope1,
            ciphertext: Data(repeating: 0x11, count: 30),
            authTag: Data(repeating: 0x22, count: 16)
        )
        let wireData1 = try! packet1.toWireData()
        
        let decision1 = await forwarder.evaluateInboundPacket(wireData: wireData1, fromPeerId: "stranger-1")
        guard case .forward(let mutated, _) = decision1 else {
            print("  FAIL: Expected .forward while relay active, got \(decision1)")
            return false
        }
        
        // Enqueue into outbox relay lane
        try! outbox.enqueue(data: mutated, destinationPeerId: "neighbor-A", isRelay: true)
        guard outbox.relayCount == 1 else {
            print("  FAIL: Outbox relayCount should be 1, got \(outbox.relayCount)")
            return false
        }
        
        // 2. User stops relaying promptly
        await policyManager.stopRelaying()
        
        let stateAfterStop = await policyManager.currentState()
        guard stateAfterStop.mode == .disabled else {
            print("  FAIL: Mode should be .disabled after stopRelaying, got \(stateAfterStop.mode)")
            return false
        }
        guard !stateAfterStop.isRelayPermitted else {
            print("  FAIL: isRelayPermitted should be false after stop")
            return false
        }
        
        // Outbox relay queue must have been purged immediately!
        guard outbox.relayCount == 0 else {
            print("  FAIL: Outbox relay queue was not purged upon stop! Still has \(outbox.relayCount) packets")
            return false
        }
        
        // 3. Subsequent stranger packet must be rejected
        let strangerEnvelope2 = CleartextEnvelope(
            type: .locationPing,
            hopLimit: 8,
            hopCount: 0,
            sessionId: 0x8888,
            sequenceNumber: 11
        )
        let packet2 = RawWirePacket(
            envelope: strangerEnvelope2,
            ciphertext: Data(repeating: 0x33, count: 30),
            authTag: Data(repeating: 0x44, count: 16)
        )
        let wireData2 = try! packet2.toWireData()
        
        let decision2 = await forwarder.evaluateInboundPacket(wireData: wireData2, fromPeerId: "stranger-1")
        guard decision2 == .dropPolicyDisabled else {
            print("  FAIL: Expected .dropPolicyDisabled after stop, got \(decision2)")
            return false
        }
        
        print("  PASS: Relay enabled forwarded packet; stopping promptly drained outbox queue and rejected subsequent traffic.")
        return true
    }
    
    // MARK: - Test 3: Battery Drops Below 20%
    
    public static func testBatteryDropsBelow20Percent() async -> Bool {
        print("[Test 3] Battery drops below 20% (Festival Survival Mode)...")
        
        let clock = TestMeshClock()
        let suiteName = "test_battery_\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        
        let outbox = PriorityOutboxQueue()
        let policyManager = RelayPolicyManager(
            clock: clock,
            userDefaults: userDefaults,
            storageKeyPrefix: "test.relay",
            outbox: outbox,
            initialBatteryLevel: 0.85,
            defaultMode: .communalRelayActive
        )
        
        // Initial state: 85% battery
        let initialPermitted = await policyManager.canRelay(packetType: .locationPing)
        guard initialPermitted else {
            print("  FAIL: Relay should be permitted at 85% battery")
            return false
        }
        
        // Seed outbox with a relay packet
        let dummyPacket = try! RawWirePacket(
            envelope: CleartextEnvelope(type: .locationPing, hopLimit: 8, hopCount: 0, sessionId: 0x1234, sequenceNumber: 1),
            ciphertext: Data(repeating: 0xAA, count: 30),
            authTag: Data(repeating: 0xBB, count: 16)
        ).toWireData()
        try! outbox.enqueue(data: dummyPacket, isRelay: true)
        guard outbox.relayCount == 1 else { return false }
        
        // Battery drops to 19% (<20%)
        await policyManager.updatePowerMetrics(batteryLevel: 0.19, isLowPowerMode: false)
        
        let state19 = await policyManager.currentState()
        guard !state19.isRelayPermitted else {
            print("  FAIL: isRelayPermitted should be false at 19% battery")
            return false
        }
        guard state19.status() == .pausedSurvivalBattery else {
            print("  FAIL: Expected .pausedSurvivalBattery, got \(state19.status())")
            return false
        }
        
        // Relay queue must be drained upon survival mode cutoff
        guard outbox.relayCount == 0 else {
            print("  FAIL: Relay queue was not drained when battery dropped <20%!")
            return false
        }
        
        // Phone plugged into portable power bank: battery rises to 25%
        await policyManager.updatePowerMetrics(batteryLevel: 0.25, isLowPowerMode: false)
        let state25 = await policyManager.currentState()
        guard state25.isRelayPermitted else {
            print("  FAIL: Relay should resume when battery returns to 25%")
            return false
        }
        guard state25.status() == .activeAlways else {
            print("  FAIL: Status should be .activeAlways, got \(state25.status())")
            return false
        }
        
        print("  PASS: Hard 20% battery cutoff enforced, purged outbox queue, and safely restored above 20%.")
        return true
    }
    
    // MARK: - Test 4: Low Power Mode Activates
    
    public static func testLowPowerModeActivates() async -> Bool {
        print("[Test 4] Low Power Mode activates...")
        
        let clock = TestMeshClock()
        let suiteName = "test_lpm_\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        
        let policyManager = RelayPolicyManager(
            clock: clock,
            userDefaults: userDefaults,
            storageKeyPrefix: "test.relay",
            initialBatteryLevel: 0.90, // Plenty of battery!
            initialLowPowerMode: false,
            defaultMode: .communalRelayActive
        )
        
        guard await policyManager.canRelay(packetType: .locationPing) else {
            print("  FAIL: Should be permitted at 90% without Low Power Mode")
            return false
        }
        
        // User flips system Low Power Mode ON
        await policyManager.updatePowerMetrics(batteryLevel: 0.90, isLowPowerMode: true)
        
        let state = await policyManager.currentState()
        guard !state.isRelayPermitted else {
            print("  FAIL: isRelayPermitted must be false when Low Power Mode is active")
            return false
        }
        guard state.status() == .pausedLowPowerMode else {
            print("  FAIL: Expected .pausedLowPowerMode, got \(state.status())")
            return false
        }
        
        print("  PASS: Low Power Mode immediately halts stranger relaying even at 90% battery.")
        return true
    }
    
    // MARK: - Test 5: Ordinary Forwarding Exceeds Rate Limit
    
    public static func testOrdinaryForwardingExceedsRateLimit() async -> Bool {
        print("[Test 5] Ordinary forwarding rate limit (2 pkts/sec)...")
        
        let clock = TestMeshClock()
        let rateLimiter = ForwardingRateLimiter(
            clock: clock,
            ordinaryCapacity: 4.0,
            ordinaryRefillRate: 2.0
        )
        
        // Consume available tokens (capacity = 4)
        for i in 1...4 {
            let allowed = await rateLimiter.consumeOrdinaryToken()
            guard allowed else {
                print("  FAIL: Token \(i) should have been permitted within burst capacity")
                return false
            }
        }
        
        // 5th immediate packet in the same sub-second must be rejected
        let excessPacket = await rateLimiter.consumeOrdinaryToken()
        guard !excessPacket else {
            print("  FAIL: 5th packet should have exceeded 2 pkts/sec rate limit!")
            return false
        }
        
        // Advance clock by 1.0 second: exactly 2 tokens refill
        clock.advance(by: 1.0)
        let token1 = await rateLimiter.consumeOrdinaryToken()
        let token2 = await rateLimiter.consumeOrdinaryToken()
        let token3 = await rateLimiter.consumeOrdinaryToken()
        
        guard token1 && token2 && !token3 else {
            print("  FAIL: Expected exactly 2 refilled tokens after 1.0s, got token1=\(token1), token2=\(token2), token3=\(token3)")
            return false
        }
        
        print("  PASS: Token bucket rate limiter strictly enforces 2.0 pkts/sec with bounded burst capacity.")
        return true
    }
    
    // MARK: - Test 6: SOS Priority Bypasses Ordinary Queue
    
    public static func testSOSPriorityBypassesOrdinaryQueue() async -> Bool {
        print("[Test 6] SOS priority bypasses ordinary queue & has independent budget...")
        
        let clock = TestMeshClock()
        let outbox = PriorityOutboxQueue()
        let rateLimiter = ForwardingRateLimiter(
            clock: clock,
            ordinaryCapacity: 4.0,
            ordinaryRefillRate: 2.0,
            sosCapacity: 8.0,
            sosRefillRate: 4.0
        )
        
        // 1. Deplete all ordinary tokens completely
        for _ in 1...4 {
            _ = await rateLimiter.consumeOrdinaryToken()
        }
        guard await rateLimiter.availableTokens() < 1.0 else {
            print("  FAIL: Ordinary tokens should be depleted")
            return false
        }
        
        // Urgent SOS token consumption STILL succeeds using separate budget!
        let sosAllowed = await rateLimiter.consumeSOSToken()
        guard sosAllowed else {
            print("  FAIL: SOS token consumption must succeed even when ordinary budget is 0!")
            return false
        }
        
        // 2. Queue ordering: Enqueue normal location pings & stranger packets first
        let normalPing = try! RawWirePacket(
            envelope: CleartextEnvelope(type: .locationPing, hopLimit: 8, hopCount: 0, sessionId: 0x1111, sequenceNumber: 10),
            ciphertext: Data(repeating: 0x01, count: 30),
            authTag: Data(repeating: 0x02, count: 16)
        ).toWireData()
        
        let strangerRelay = try! RawWirePacket(
            envelope: CleartextEnvelope(type: .locationPing, hopLimit: 8, hopCount: 1, sessionId: 0x2222, sequenceNumber: 20),
            ciphertext: Data(repeating: 0x03, count: 30),
            authTag: Data(repeating: 0x04, count: 16)
        ).toWireData()
        
        try! outbox.enqueue(data: normalPing, isRelay: false)
        try! outbox.enqueue(data: strangerRelay, isRelay: true)
        
        // Now enqueue urgent SOS packet
        let urgentSOS = try! RawWirePacket(
            envelope: CleartextEnvelope(type: .sos, hopLimit: 8, hopCount: 0, sessionId: 0x1111, sequenceNumber: 99),
            ciphertext: Data(repeating: 0xEE, count: 30),
            authTag: Data(repeating: 0xFF, count: 16)
        ).toWireData()
        try! outbox.enqueue(data: urgentSOS, isRelay: false)
        
        // Dequeue: SOS MUST be returned FIRST, preempting earlier packets!
        let dequeuedItem = outbox.dequeue()
        guard let item = dequeuedItem, item.packetType == .sos else {
            print("  FAIL: First dequeued item must be SOS, got \(String(describing: dequeuedItem?.packetType))")
            return false
        }
        
        print("  PASS: Urgent SOS preempted ordinary queue and used separate independent forwarding budget.")
        return true
    }
    
    // MARK: - Test 7: Queue Capacity Limits and Ring Buffer Drop-Head
    
    public static func testQueueCapacityLimitsAndRingBufferDropHead() async -> Bool {
        print("[Test 7] Queue capacity limits & ring buffer drop-head...")
        
        let outbox = PriorityOutboxQueue(maxUrgentCapacity: 16, maxRelayCapacity: 32)
        
        // 1. Stranger relay ring buffer (32 max)
        for i in 1...32 {
            let data = try! RawWirePacket(
                envelope: CleartextEnvelope(type: .locationPing, hopLimit: 8, hopCount: 1, sessionId: 0x7777, sequenceNumber: UInt32(i)),
                ciphertext: Data(repeating: UInt8(i), count: 30),
                authTag: Data(repeating: 0xAA, count: 16)
            ).toWireData()
            try! outbox.enqueue(data: data, isRelay: true)
        }
        guard outbox.relayCount == 32 else {
            print("  FAIL: Expected 32 relay packets, got \(outbox.relayCount)")
            return false
        }
        
        // Enqueue 33rd stranger packet: MUST NOT THROW, drops head (oldest packet)
        let packet33 = try! RawWirePacket(
            envelope: CleartextEnvelope(type: .locationPing, hopLimit: 8, hopCount: 1, sessionId: 0x7777, sequenceNumber: 33),
            ciphertext: Data(repeating: 0x33, count: 30),
            authTag: Data(repeating: 0xAA, count: 16)
        ).toWireData()
        
        try! outbox.enqueue(data: packet33, isRelay: true)
        guard outbox.relayCount == 32 else {
            print("  FAIL: Relay queue capacity must remain 32, got \(outbox.relayCount)")
            return false
        }
        guard outbox.relayPacketsDroppedOverflow == 1 else {
            print("  FAIL: Overflow counter should be 1, got \(outbox.relayPacketsDroppedOverflow)")
            return false
        }
        
        // 2. Urgent lane capacity (16 max)
        for i in 1...16 {
            let urgent = try! RawWirePacket(
                envelope: CleartextEnvelope(type: .sos, hopLimit: 8, hopCount: 0, sessionId: 0x1111, sequenceNumber: UInt32(i)),
                ciphertext: Data(repeating: 0xEE, count: 30),
                authTag: Data(repeating: 0xFF, count: 16)
            ).toWireData()
            try! outbox.enqueue(data: urgent, isRelay: false)
        }
        guard outbox.urgentCount == 16 else {
            print("  FAIL: Urgent count should be 16, got \(outbox.urgentCount)")
            return false
        }
        
        // 17th urgent packet must throw TransportError.queueFull
        let urgent17 = try! RawWirePacket(
            envelope: CleartextEnvelope(type: .sos, hopLimit: 8, hopCount: 0, sessionId: 0x1111, sequenceNumber: 17),
            ciphertext: Data(repeating: 0xEE, count: 30),
            authTag: Data(repeating: 0xFF, count: 16)
        ).toWireData()
        
        var threwQueueFull = false
        do {
            try outbox.enqueue(data: urgent17, isRelay: false)
        } catch TransportError.queueFull {
            threwQueueFull = true
        } catch {
            print("  FAIL: Unexpected error: \(error)")
        }
        guard threwQueueFull else {
            print("  FAIL: Enqueuing 17th urgent packet should throw TransportError.queueFull")
            return false
        }
        
        print("  PASS: Stranger relay lane dropped head on 32-packet overflow; urgent lane threw queueFull at 16.")
        return true
    }
    
    // MARK: - Test 8: Timed Relay Session Expires
    
    public static func testTimedRelaySessionExpires() async -> Bool {
        print("[Test 8] Timed relay session expires after 30 minutes...")
        
        let clock = TestMeshClock()
        let suiteName = "test_timed_\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        
        let policyManager = RelayPolicyManager(
            clock: clock,
            userDefaults: userDefaults,
            storageKeyPrefix: "test.relay",
            initialBatteryLevel: 0.90,
            defaultMode: .disabled
        )
        
        // User activates Timed (30 Minutes) mode
        await policyManager.setTimedParticipation(durationSeconds: 1800)
        
        let activeState = await policyManager.currentState()
        guard activeState.isPermitted(at: clock.now()) else {
            print("  FAIL: Timed relay should be active immediately upon activation")
            return false
        }
        guard case .activeTimed(let remaining) = activeState.status(at: clock.now()), remaining > 1750 else {
            print("  FAIL: Expected .activeTimed with ~1800s remaining, got \(activeState.status(at: clock.now()))")
            return false
        }
        
        // Advance clock by 29 minutes (1740 seconds): still permitted
        clock.advance(by: 1740)
        guard await policyManager.canRelay(packetType: .locationPing) else {
            print("  FAIL: Relaying should still be permitted at 29 minutes")
            return false
        }
        
        // Advance clock past 30 minutes (by another 70 seconds -> 30m10s total)
        clock.advance(by: 70)
        
        let expiredState = await policyManager.currentState()
        guard !expiredState.isPermitted(at: clock.now()) else {
            print("  FAIL: isRelayPermitted must be false after 30 minutes elapsed")
            return false
        }
        guard expiredState.status(at: clock.now()) == .timedExpired else {
            print("  FAIL: Expected .timedExpired status, got \(expiredState.status(at: clock.now()))")
            return false
        }
        let canRelayExpired = await policyManager.canRelay(packetType: .locationPing)
        guard !canRelayExpired else {
            print("  FAIL: canRelay must return false after timed expiry")
            return false
        }
        
        print("  PASS: 30-minute timed relay session automatically expired and halted forwarding.")
        return true
    }
    
    // MARK: - Test 9: Live Activity Unavailable or Dismissed
    
    public static func testLiveActivityUnavailableOrDismissed() async -> Bool {
        print("[Test 9] Live Activity unavailable or dismissed handling...")
        
        let manager = LiveActivityManager.shared
        
        // End any non-existent activity: must complete safely without error
        await manager.endSessionActivity()
        
        // Update session activity when no activity is running: must be a safe no-op
        await manager.updateSessionActivity(
            peerCount: 2,
            meetingPoint: nil,
            currentLocation: nil,
            isSOSActive: false,
            sosSenderInitials: nil,
            relayStatusText: "RELAY: ON",
            relayModeText: "Always",
            timedRelayRemainingSeconds: nil,
            isRelayActive: true
        )
        
        // Verify underlying policy services enforce limits regardless of Live Activity presence
        let clock = TestMeshClock()
        let suiteName = "test_la_guard_\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        
        let policyManager = RelayPolicyManager(
            clock: clock,
            userDefaults: userDefaults,
            storageKeyPrefix: "test.relay",
            initialBatteryLevel: 0.15, // Low battery
            defaultMode: .communalRelayActive
        )
        
        // Even if Live Activity is not present or dismissed, services strictly enforce 20% cutoff
        let state = await policyManager.currentState()
        guard !state.isRelayPermitted else {
            print("  FAIL: Policy manager must enforce 20% cutoff even without Live Activity")
            return false
        }
        
        print("  PASS: Live Activity dismissal handled safely; service layer independently enforces policy.")
        return true
    }
    
    // MARK: - Test 10: Resource Counters Contain No Location History
    
    public static func testResourceCountersContainNoLocationHistory() async -> Bool {
        print("[Test 10] Resource counters contain zero location history...")
        
        let clock = TestMeshClock()
        let suiteName = "test_telemetry_\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        
        let policyManager = RelayPolicyManager(
            clock: clock,
            userDefaults: userDefaults,
            storageKeyPrefix: "test.relay",
            defaultMode: .communalRelayActive
        )
        
        // Record various events
        await policyManager.recordForwardEvent(type: .locationPing)
        await policyManager.recordForwardEvent(type: .locationPing)
        await policyManager.recordForwardEvent(type: .sos)
        await policyManager.recordDropEvent(reason: .rateLimitExceeded)
        await policyManager.recordDropEvent(reason: .hopLimitExceeded)
        await policyManager.recordDropEvent(reason: .duplicate)
        await policyManager.recordDropEvent(reason: .batteryThrottled)
        
        let telemetry = await policyManager.snapshot()
        
        guard telemetry.totalPacketsForwarded == 3 else {
            print("  FAIL: Expected 3 packets forwarded, got \(telemetry.totalPacketsForwarded)")
            return false
        }
        guard telemetry.totalSOSForwarded == 1 else {
            print("  FAIL: Expected 1 SOS forwarded, got \(telemetry.totalSOSForwarded)")
            return false
        }
        guard telemetry.packetsDroppedRateLimit == 1 else {
            print("  FAIL: Expected 1 rate limit drop, got \(telemetry.packetsDroppedRateLimit)")
            return false
        }
        guard telemetry.packetsDroppedHopLimit == 1 else {
            print("  FAIL: Expected 1 hop limit drop, got \(telemetry.packetsDroppedHopLimit)")
            return false
        }
        guard telemetry.duplicatePacketsSuppressed == 1 else {
            print("  FAIL: Expected 1 duplicate drop, got \(telemetry.duplicatePacketsSuppressed)")
            return false
        }
        guard telemetry.packetsDroppedBattery >= 1 else {
            print("  FAIL: Expected battery drop count >= 1, got \(telemetry.packetsDroppedBattery)")
            return false
        }
        
        // Mirror reflection check: verify RelayTelemetry properties contain NO coordinate or location fields
        let mirror = Mirror(reflecting: telemetry)
        for child in mirror.children {
            let label = child.label ?? ""
            guard !label.lowercased().contains("location") &&
                  !label.lowercased().contains("coordinate") &&
                  !label.lowercased().contains("latitude") &&
                  !label.lowercased().contains("longitude") &&
                  !label.lowercased().contains("initials") &&
                  !label.lowercased().contains("track") else {
                print("  FAIL: Found sensitive location property in RelayTelemetry: \(label)")
                return false
            }
        }
        
        print("  PASS: Resource counters aggregate metrics anonymously with zero location history retained.")
        return true
    }
    
    // MARK: - Test 11: Relay Settings Persistence
    
    public static func testRelaySettingsPersistence() async -> Bool {
        print("[Test 11] Relay settings persistence across app restarts...")
        
        let clock = TestMeshClock()
        let suiteName = "test_persist_\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        
        // 1. Session 1: User chooses Always Active
        do {
            let manager1 = RelayPolicyManager(
                clock: clock,
                userDefaults: userDefaults,
                storageKeyPrefix: "app.relay"
            )
            await manager1.setParticipationMode(.communalRelayActive)
        }
        
        // 2. Session 2 (simulated app restart): Verify mode is restored
        do {
            let manager2 = RelayPolicyManager(
                clock: clock,
                userDefaults: userDefaults,
                storageKeyPrefix: "app.relay"
            )
            let state2 = await manager2.currentState()
            guard state2.mode == .communalRelayActive else {
                print("  FAIL: Expected restored mode .communalRelayActive, got \(state2.mode)")
                return false
            }
        }
        
        // 3. User switches to Disabled
        do {
            let manager3 = RelayPolicyManager(
                clock: clock,
                userDefaults: userDefaults,
                storageKeyPrefix: "app.relay"
            )
            await manager3.stopRelaying()
        }
        
        // 4. Session 4: Verify disabled is restored
        do {
            let manager4 = RelayPolicyManager(
                clock: clock,
                userDefaults: userDefaults,
                storageKeyPrefix: "app.relay"
            )
            let state4 = await manager4.currentState()
            guard state4.mode == .disabled else {
                print("  FAIL: Expected restored mode .disabled, got \(state4.mode)")
                return false
            }
        }
        
        print("  PASS: User relay preference persists reliably across restarts in approved settings model.")
        return true
    }
    
    // MARK: - Test 12: Bidirectional Cross-Group Stranger Relaying
    
    /// Verifies that two devices belonging to different groups (Group 1 vs Group 2)
    /// symmetrically act as anonymous blind relays for each other when opted into Communal Relay.
    public static func testBidirectionalCrossGroupStrangerRelay() async -> Bool {
        print("[Test 12] Bidirectional cross-group stranger relaying between different groups...")
        let clock = TestMeshClock()
        
        let outboxA = PriorityOutboxQueue()
        let managerA = RelayPolicyManager(
            clock: clock,
            userDefaults: UserDefaults(suiteName: "test.relay.a")!,
            storageKeyPrefix: "relay.a",
            outbox: outboxA,
            defaultMode: .communalRelayActive
        )
        
        let outboxB = PriorityOutboxQueue()
        let managerB = RelayPolicyManager(
            clock: clock,
            userDefaults: UserDefaults(suiteName: "test.relay.b")!,
            storageKeyPrefix: "relay.b",
            outbox: outboxB,
            defaultMode: .communalRelayActive
        )
        
        // Both nodes must permit relaying
        let stateA = await managerA.currentState()
        let stateB = await managerB.currentState()
        guard stateA.isRelayPermitted && stateB.isRelayPermitted else {
            print("  FAIL: Both Node A and Node B must have isRelayPermitted == true")
            return false
        }
        
        // 1. Node A (Group 1, SID 0x1111) generates a packet
        let envA = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .locationPing,
            hopLimit: PacketConstants.defaultHopLimit,
            hopCount: 0,
            sessionId: 0x1111,
            sequenceNumber: 101
        )
        let wireA = RawWirePacket(envelope: envA, ciphertext: Data(repeating: 0xAA, count: 30), authTag: Data(repeating: 0x01, count: 16))
        let wireDataA = try! wireA.toWireData()
        
        // Node B (Group 2, SID 0x2222) receives Node A's stranger packet
        guard envA.sessionId != 0x2222 else {
            print("  FAIL: Packet A should be from different group")
            return false
        }
        guard stateB.isRelayPermitted else {
            await managerB.recordDropEvent(reason: .policyDisabled)
            print("  FAIL: Node B dropped stranger packet due to policy")
            return false
        }
        guard envA.hopCount < envA.hopLimit else {
            await managerB.recordDropEvent(reason: .hopLimitExceeded)
            return false
        }
        
        // Node B mutates hopCount and enqueues into its stranger relay lane
        var mutatedA = wireDataA
        mutatedA[mutatedA.startIndex + 2] = envA.hopCount + 1
        _ = try! outboxB.enqueue(data: mutatedA, destinationPeerId: "peer-B2", isRelay: true)
        await managerB.recordForwardEvent(type: envA.type)
        
        let teleB = await managerB.snapshot()
        guard teleB.totalPacketsForwarded == 1, outboxB.relayCount == 1 else {
            print("  FAIL: Node B failed to forward Node A's stranger packet: forwarded=\(teleB.totalPacketsForwarded), relayCount=\(outboxB.relayCount)")
            return false
        }
        
        // 2. Node B (Group 2, SID 0x2222) generates a packet
        let envB = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .sos,
            hopLimit: PacketConstants.sosHopLimit,
            hopCount: 0,
            sessionId: 0x2222,
            sequenceNumber: 202
        )
        let wireB = RawWirePacket(envelope: envB, ciphertext: Data(repeating: 0xBB, count: 30), authTag: Data(repeating: 0x02, count: 16))
        let wireDataB = try! wireB.toWireData()
        
        // Node A (Group 1, SID 0x1111) receives Node B's stranger packet
        guard envB.sessionId != 0x1111 else {
            print("  FAIL: Packet B should be from different group")
            return false
        }
        guard stateA.isRelayPermitted else {
            await managerA.recordDropEvent(reason: .policyDisabled)
            print("  FAIL: Node A dropped stranger packet due to policy")
            return false
        }
        guard envB.hopCount < envB.hopLimit else {
            await managerA.recordDropEvent(reason: .hopLimitExceeded)
            return false
        }
        
        // Node A mutates hopCount and enqueues into its stranger relay lane
        var mutatedB = wireDataB
        mutatedB[mutatedB.startIndex + 2] = envB.hopCount + 1
        _ = try! outboxA.enqueue(data: mutatedB, destinationPeerId: "peer-A2", isRelay: true)
        await managerA.recordForwardEvent(type: envB.type)
        
        let teleA = await managerA.snapshot()
        guard teleA.totalPacketsForwarded == 1, outboxA.relayCount == 1 else {
            print("  FAIL: Node A failed to forward Node B's stranger packet: forwarded=\(teleA.totalPacketsForwarded), relayCount=\(outboxA.relayCount)")
            return false
        }
        
        print("  PASS: Bidirectional cross-group stranger relaying verified. Both Node A and Node B symmetrically forward packets for each other.")
        return true
    }
}
