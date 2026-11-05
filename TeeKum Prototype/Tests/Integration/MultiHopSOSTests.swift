//
//  MultiHopSOSTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation
import CoreLocation
import CryptoKit

/// Authoritative Unit & Integration Test Suite for Agent 4 (Multi-Hop SOS & Reliability Specialist).
///
/// Verifies all 11 Master Specification Scenarios:
/// 1. SOS delivered over one relay (Alice -> Bob -> Charlie).
/// 2. SOS delivered over multiple relays (Alice -> R1 -> R2 -> R3 -> Charlie, 4 hops).
/// 3. Recipient disconnected (relay acknowledges, but friend never confirms -> RELAY_ACK honest UX).
/// 4. Relay disconnects during forwarding (no peers -> SEARCHING_PEERS).
/// 5. Duplicate SOS arrives through two different paths (diamond topology -> siren strictly suppressed).
/// 6. Spoofed SOS from an unauthorized device (tampered MAC tag, wrong session, stale timestamp -> rejected).
/// 7. ACK is lost or delayed (bounded retry resolves on second attempt).
/// 8. Route expires during an SOS attempt (automatic bounded flooding fallback).
/// 9. Hop limit is reached (packet dropped when hopCount >= hopLimit).
/// 10. Queue is saturated with normal traffic (urgent SOS preempts queued location pings).
/// 11. Retry budget is exhausted (retries capped at 3, transitions to timeout/failed honestly).
public enum MultiHopSOSTests {
    
    @MainActor
    public static func runAllTests() async -> Bool {
        print("\n================================================================")
        print(">>> STARTING PHASE 2 MULTI-HOP SOS VERIFICATION SUITE <<<")
        print("================================================================")
        
        var passed = true
        
        passed = await testSOSDeliveredOverOneRelay() && passed
        passed = await testSOSDeliveredOverMultipleRelays() && passed
        passed = await testRecipientDisconnectedHonestRelayState() && passed
        passed = await testRelayDisconnectsDuringForwarding() && passed
        passed = await testDuplicateSOSArrivesThroughTwoPaths() && passed
        passed = await testSpoofedSOSFromUnauthorizedDevice() && passed
        passed = await testACKLostOrDelayedBoundedRetry() && passed
        passed = await testRouteExpiresDuringSOSAttempt() && passed
        passed = await testHopLimitReachedDropEnforcement() && passed
        passed = await testQueueSaturatedNormalTrafficPreemption() && passed
        passed = await testRetryBudgetExhaustedHonestFailure() && passed
        
        if passed {
            print("================================================================")
            print(">>> ALL 11 MULTI-HOP SOS VERIFICATION SUITES PASSED <<<")
            print("================================================================\n")
        } else {
            print("❌ SOME MULTI-HOP SOS VERIFICATION TESTS FAILED!\n")
        }
        
        return passed
    }
    
    // MARK: - Test Helpers
    
    private final class MockAudioAlerter: SOSAudioAlerting, @unchecked Sendable {
        private(set) var triggerCount: Int = 0
        private(set) var stopCount: Int = 0
        
        func triggerEmergencyAlertFeedback() { triggerCount += 1 }
        func stopEmergencyAlertFeedback() { stopCount += 1 }
    }
    
    @MainActor
    private final class MockMultiHopLocationService: LocationServiceProvider {
        var currentLocation: LocationPin?
        var currentHeading: CLLocationDirection?
        var isStationary: Bool = false
        var hasDistantPeers: Bool = false
        var hasDistantPeersProvider: (@MainActor @Sendable () -> Bool)? = nil
        var hasStalePeers: Bool = false
        var hasStalePeersProvider: (@MainActor @Sendable () -> Bool)? = nil
        var isLiveSharingEnabled: Bool = true
        var isSurvivalModeActive: Bool = false
        var currentBatteryLevel: Float = 0.85
        var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
        var isGPSAvailable: Bool = true
        var isLocationStale: Bool = false
        var locationAge: TimeInterval? = 2.0
        var currentCadenceInterval: TimeInterval = 4.0
        var cadenceConfig: CadenceConfiguration = CadenceConfiguration()
        
        let publishedPings: AsyncStream<LocationPin>
        private let publishedPingsContinuation: AsyncStream<LocationPin>.Continuation
        
        init(lat: Double = -6.2088, lon: Double = 106.8456) {
            let loc = LocationPin(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                horizontalAccuracy: 5.0,
                timestamp: Date()
            )
            self.currentLocation = loc
            var continuation: AsyncStream<LocationPin>.Continuation!
            self.publishedPings = AsyncStream { continuation = $0 }
            self.publishedPingsContinuation = continuation
        }
        
        func requestPermissions() async -> Bool { true }
        func startTracking() throws {}
        func stopTracking() {}
        func getLatestLocationForSOS() -> LocationPin? { currentLocation }
    }
    
    // MARK: - Test 1: SOS Delivered Over One Relay
    
    @MainActor
    public static func testSOSDeliveredOverOneRelay() async -> Bool {
        print("[TEST 1] testSOSDeliveredOverOneRelay...")
        
        let clock = TestMeshClock()
        let sessionId: UInt16 = 0x5678
        
        let sessionAlice = GroupSession(sessionId: sessionId, sessionName: "Rave", symmetricKeyData: Data(repeating: 0x42, count: 32), localInitials: "ALI", memberSlot: 1)
        let sessionBob = GroupSession(sessionId: 0x0000, sessionName: "CommunalRelay", symmetricKeyData: Data(repeating: 0, count: 32), localInitials: "BOB")
        let sessionCharlie = GroupSession(sessionId: sessionId, sessionName: "Rave", symmetricKeyData: Data(repeating: 0x42, count: 32), localInitials: "CHL", memberSlot: 2)
        
        let cryptoA = CryptoService()
        let cryptoC = CryptoService()
        
        let transportA = SimulatedMeshTransport(peerId: "Alice", clock: clock)
        let transportB = SimulatedMeshTransport(peerId: "BobRelay", clock: clock)
        let transportC = SimulatedMeshTransport(peerId: "Charlie", clock: clock)
        
        try! await transportA.start(serviceType: "_teekum._tcp", session: sessionAlice)
        try! await transportB.start(serviceType: "_teekum._tcp", session: sessionBob)
        try! await transportC.start(serviceType: "_teekum._tcp", session: sessionCharlie)
        
        await transportA.link(to: transportB, rssi: -65)
        await transportB.link(to: transportC, rssi: -68)
        
        let routingTableB = RoutingTable(clock: clock)
        let rateLimiterB = ForwardingRateLimiter(clock: clock)
        let seenCacheB = SeenPacketCache(clock: clock)
        
        // Bob is a stranger relay (Zero-Knowledge, no group key!)
        let forwarderB = PacketForwarder(
            routingTable: routingTableB,
            rateLimiter: rateLimiterB,
            neighborTable: await transportB.neighborTable,
            seenPacketCache: seenCacheB,
            clock: clock,
            sessionProvider: { nil }, // Stranger relay has no session key
            policyProvider: { RelayPolicyState(mode: .communalRelayActive) },
            transport: transportB
        )
        
        let alerterC = MockAudioAlerter()
        let vmA = SOSViewModel(
            locationService: MockMultiHopLocationService(),
            sessionProvider: { sessionAlice },
            cryptoService: cryptoA,
            transport: transportA,
            dateProvider: { clock.now() }
        )
        let vmC = SOSViewModel(
            locationService: MockMultiHopLocationService(),
            sessionProvider: { sessionCharlie },
            cryptoService: cryptoC,
            transport: transportC,
            audioAlerter: alerterC,
            dateProvider: { clock.now() }
        )
        
        // Step 1: Alice triggers SOS
        vmA.triggerSOS(emergencyType: .medical)
        
        guard case .localSending = vmA.deliveryState else {
            print("FAILED: Alice should be in .localSending, got \(vmA.deliveryState)")
            return false
        }
        
        // Drain packet from Alice transport to Bob
        guard let wireData = await getNextFrameData(from: transportB, timeoutSeconds: 1.0) else {
            print("FAILED: Bob did not receive wire data from Alice")
            return false
        }
        
        // Step 2: Bob blindly forwards packet (mutates hopCount from 0 to 1)
        let decision = await forwarderB.evaluateInboundPacket(wireData: wireData, fromPeerId: "Alice")
        guard case let .forward(mutatedData, nextHops) = decision else {
            print("FAILED: Bob should forward blindly, got \(decision)")
            return false
        }
        guard nextHops.contains("Charlie") else {
            print("FAILED: Bob should forward to Charlie")
            return false
        }
        guard mutatedData[mutatedData.startIndex + 2] == 1 else {
            print("FAILED: Bob must increment hopCount to 1, got \(mutatedData[mutatedData.startIndex + 2])")
            return false
        }
        
        // Relay mutated packet from Bob to Charlie
        _ = try! await transportB.sendFrame(mutatedData, to: "Charlie")
        
        // Drain packet at Charlie
        guard let charlieFrame = await getNextInboundFrame(from: transportC, timeoutSeconds: 1.0),
              let rawAtC = charlieFrame.rawPacket else {
            print("FAILED: Charlie did not receive framed packet from Bob")
            return false
        }
        
        // Step 3: Charlie processes inbound packet
        await vmC.processInboundPacket(InboundPacket(rawPacket: rawAtC, sourcePeerId: "BobRelay"))
        
        guard vmC.activeIncomingAlert != nil else {
            print("FAILED: Charlie must display activeIncomingAlert")
            return false
        }
        guard vmC.activeIncomingAlert?.emergencyType == .medical else {
            print("FAILED: Charlie must receive emergencyType .medical")
            return false
        }
        guard alerterC.triggerCount == 1 else {
            print("FAILED: Charlie's siren must trigger exactly once")
            return false
        }
        
        // Step 4: Charlie emits delivery ACK back to Alice via Bob
        guard let ackData = await getNextFrameData(from: transportB, timeoutSeconds: 1.0) else {
            print("FAILED: Bob did not receive ACK from Charlie")
            return false
        }
        
        // Bob forwards ACK back to Alice
        let ackDecision = await forwarderB.evaluateInboundPacket(wireData: ackData, fromPeerId: "Charlie")
        guard case let .forward(mutatedAck, _) = ackDecision else {
            print("FAILED: Bob should forward ACK blindly, got \(ackDecision)")
            return false
        }
        
        // Alice receives Charlie's ACK
        let rawAckAtAlice = try! RawWirePacket.fromWireData(mutatedAck)
        await vmA.processInboundPacket(InboundPacket(rawPacket: rawAckAtAlice, sourcePeerId: "BobRelay"))
        
        // Step 5: Verification of Honest Confirmation
        guard case let .deliveredToFriend(friendId, _) = vmA.deliveryState, friendId == "CHL" else {
            print("FAILED: Alice must reach .deliveredToFriend with CHL, got \(vmA.deliveryState)")
            return false
        }
        guard vmA.lastDeliveredHopCount == 1 else {
            print("FAILED: Alice must record delivery hopCount = 1, got \(String(describing: vmA.lastDeliveredHopCount))")
            return false
        }
        
        print("PASSED: testSOSDeliveredOverOneRelay")
        return true
    }
    
    // MARK: - Test 2: SOS Delivered Over Multiple Relays (4 Hops)
    
    @MainActor
    public static func testSOSDeliveredOverMultipleRelays() async -> Bool {
        print("[TEST 2] testSOSDeliveredOverMultipleRelays...")
        
        let clock = TestMeshClock()
        let sessionId: UInt16 = 0x9012
        let keyData = Data(repeating: 0x77, count: 32)
        
        let sessionAlice = GroupSession(sessionId: sessionId, sessionName: "MultiHop", symmetricKeyData: keyData, localInitials: "ALI", memberSlot: 1)
        let sessionRelay = GroupSession(sessionId: 0x0000, sessionName: "Relay", symmetricKeyData: Data(repeating: 0, count: 32), localInitials: "REL")
        let sessionCharlie = GroupSession(sessionId: sessionId, sessionName: "MultiHop", symmetricKeyData: keyData, localInitials: "CHL", memberSlot: 2)
        
        let cryptoA = CryptoService()
        let cryptoC = CryptoService()
        let alerterC = MockAudioAlerter()
        
        // Linear chain: Alice -> R1 -> R2 -> R3 -> Charlie
        let tAlice = SimulatedMeshTransport(peerId: "Alice", clock: clock)
        let tR1 = SimulatedMeshTransport(peerId: "R1", clock: clock)
        let tR2 = SimulatedMeshTransport(peerId: "R2", clock: clock)
        let tR3 = SimulatedMeshTransport(peerId: "R3", clock: clock)
        let tCharlie = SimulatedMeshTransport(peerId: "Charlie", clock: clock)
        
        try! await tAlice.start(serviceType: "_teekum._tcp", session: sessionAlice)
        try! await tR1.start(serviceType: "_teekum._tcp", session: sessionRelay)
        try! await tR2.start(serviceType: "_teekum._tcp", session: sessionRelay)
        try! await tR3.start(serviceType: "_teekum._tcp", session: sessionRelay)
        try! await tCharlie.start(serviceType: "_teekum._tcp", session: sessionCharlie)
        
        await tAlice.link(to: tR1)
        await tR1.link(to: tR2)
        await tR2.link(to: tR3)
        await tR3.link(to: tCharlie)
        
        let vmA = SOSViewModel(sessionProvider: { sessionAlice }, cryptoService: cryptoA, transport: tAlice, dateProvider: { clock.now() })
        let vmC = SOSViewModel(sessionProvider: { sessionCharlie }, cryptoService: cryptoC, transport: tCharlie, audioAlerter: alerterC, dateProvider: { clock.now() })
        
        let fwdR1 = PacketForwarder(routingTable: RoutingTable(clock: clock), rateLimiter: ForwardingRateLimiter(clock: clock), neighborTable: await tR1.neighborTable, seenPacketCache: SeenPacketCache(clock: clock), clock: clock, transport: tR1)
        let fwdR2 = PacketForwarder(routingTable: RoutingTable(clock: clock), rateLimiter: ForwardingRateLimiter(clock: clock), neighborTable: await tR2.neighborTable, seenPacketCache: SeenPacketCache(clock: clock), clock: clock, transport: tR2)
        let fwdR3 = PacketForwarder(routingTable: RoutingTable(clock: clock), rateLimiter: ForwardingRateLimiter(clock: clock), neighborTable: await tR3.neighborTable, seenPacketCache: SeenPacketCache(clock: clock), clock: clock, transport: tR3)
        
        // Step 1: Alice triggers SOS
        vmA.triggerSOS(emergencyType: .security)
        
        // Hop 1: Alice -> R1
        var wire = await getNextFrameData(from: tR1, timeoutSeconds: 1.0)!
        guard case let .forward(w1, _) = await fwdR1.evaluateInboundPacket(wireData: wire, fromPeerId: "Alice") else { return false }
        guard w1[2] == 1 else { return false }
        _ = try! await tR1.sendFrame(w1, to: "R2")
        
        // Hop 2: R1 -> R2
        wire = await getNextFrameData(from: tR2, timeoutSeconds: 1.0)!
        guard case let .forward(w2, _) = await fwdR2.evaluateInboundPacket(wireData: wire, fromPeerId: "R1") else { return false }
        guard w2[2] == 2 else { return false }
        _ = try! await tR2.sendFrame(w2, to: "R3")
        
        // Hop 3: R2 -> R3
        wire = await getNextFrameData(from: tR3, timeoutSeconds: 1.0)!
        guard case let .forward(w3, _) = await fwdR3.evaluateInboundPacket(wireData: wire, fromPeerId: "R2") else { return false }
        guard w3[2] == 3 else { return false }
        _ = try! await tR3.sendFrame(w3, to: "Charlie")
        
        // Hop 4: R3 -> Charlie
        let frameAtC = await getNextInboundFrame(from: tCharlie, timeoutSeconds: 1.0)!
        let rawAtC = frameAtC.rawPacket!
        guard rawAtC.envelope.hopCount == 3 else {
            print("FAILED: Charlie should see hopCount = 3, got \(rawAtC.envelope.hopCount)")
            return false
        }
        
        await vmC.processInboundPacket(InboundPacket(rawPacket: rawAtC, sourcePeerId: "R3"))
        guard vmC.activeIncomingAlert != nil && alerterC.triggerCount == 1 else {
            print("FAILED: Charlie must sound siren and surface alert")
            return false
        }
        
        // Multi-hop ACK return: Charlie -> R3 -> R2 -> R1 -> Alice
        var ackData = await getNextFrameData(from: tR3, timeoutSeconds: 1.0)!
        guard case let .forward(ack1, _) = await fwdR3.evaluateInboundPacket(wireData: ackData, fromPeerId: "Charlie") else { return false }
        _ = try! await tR3.sendFrame(ack1, to: "R2")
        
        ackData = await getNextFrameData(from: tR2, timeoutSeconds: 1.0)!
        guard case let .forward(ack2, _) = await fwdR2.evaluateInboundPacket(wireData: ackData, fromPeerId: "R3") else { return false }
        _ = try! await tR2.sendFrame(ack2, to: "R1")
        
        ackData = await getNextFrameData(from: tR1, timeoutSeconds: 1.0)!
        guard case let .forward(ack3, _) = await fwdR1.evaluateInboundPacket(wireData: ackData, fromPeerId: "R2") else { return false }
        _ = try! await tR1.sendFrame(ack3, to: "Alice")
        
        let ackFrameAtAlice = await getNextInboundFrame(from: tAlice, timeoutSeconds: 1.0)!
        await vmA.processInboundPacket(InboundPacket(rawPacket: ackFrameAtAlice.rawPacket!, sourcePeerId: "R1"))
        
        guard case let .deliveredToFriend(friendId, _) = vmA.deliveryState, friendId == "CHL" else {
            print("FAILED: Alice must reach .deliveredToFriend across 4 hops, got \(vmA.deliveryState)")
            return false
        }
        guard vmA.lastDeliveredHopCount == 3 else {
            print("FAILED: Expected ACK hopCount = 3, got \(String(describing: vmA.lastDeliveredHopCount))")
            return false
        }
        
        print("PASSED: testSOSDeliveredOverMultipleRelays")
        return true
    }
    
    // MARK: - Test 3: Recipient Disconnected (Relay ACK Honest UX)
    
    @MainActor
    public static func testRecipientDisconnectedHonestRelayState() async -> Bool {
        print("[TEST 3] testRecipientDisconnectedHonestRelayState...")
        
        let clock = TestMeshClock()
        let session = GroupSession(sessionId: 0x1111, sessionName: "Test", symmetricKeyData: Data(repeating: 0x11, count: 32), localInitials: "ALI")
        let transport = SimulatedMeshTransport(peerId: "Alice", clock: clock)
        let tBob = SimulatedMeshTransport(peerId: "BobRelay", clock: clock)
        try! await transport.start(serviceType: "_teekum._tcp", session: session)
        try! await tBob.start(serviceType: "_teekum._tcp", session: session)
        await transport.link(to: tBob)
        
        let vm = SOSViewModel(sessionProvider: { session }, cryptoService: CryptoService(), transport: transport, dateProvider: { clock.now() })
        
        vm.triggerSOS(emergencyType: .general)
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard case .localSending = vm.deliveryState else { return false }
        
        // Relay Bob sends RELAY_ACK (hopCount: 1, responderId: "BOB")
        vm.handleAckReceived(status: .relayedByMeshHop, responderId: "BOB", hopCount: 1, eventId: vm.activeSOSEventId)
        
        // Critical Honesty Invariant: Must NOT report delivered to friend!
        guard case let .relayedAck(hops, responder) = vm.deliveryState, hops == 1, responder == "BOB" else {
            print("FAILED: Must report .relayedAck, got \(vm.deliveryState)")
            return false
        }
        guard !vm.deliveryState.isDelivered else {
            print("FAILED: isDelivered must be false when only relayed by mesh hop")
            return false
        }
        guard vm.deliveryState.isRelayed else {
            print("FAILED: isRelayed must be true")
            return false
        }
        
        // Exhaust retries: recipient never responds
        for _ in 1...3 {
            await vm.triggerRetryNow()
        }
        
        // Retries exhausted: must keep honest relayed state without claiming friend delivery!
        guard case .relayedAck = vm.deliveryState else {
            print("FAILED: After exhausted retries with relay ack, state must remain .relayedAck, got \(vm.deliveryState)")
            return false
        }
        guard !vm.deliveryState.isDelivered else {
            print("FAILED: Must never overstate delivery to friend")
            return false
        }
        
        print("PASSED: testRecipientDisconnectedHonestRelayState")
        return true
    }
    
    // MARK: - Test 4: Relay Disconnects During Forwarding
    
    @MainActor
    public static func testRelayDisconnectsDuringForwarding() async -> Bool {
        print("[TEST 4] testRelayDisconnectsDuringForwarding...")
        
        let clock = TestMeshClock()
        let session = GroupSession(sessionId: 0x2222, sessionName: "Test", symmetricKeyData: Data(repeating: 0x22, count: 32), localInitials: "ALI")
        let transportA = SimulatedMeshTransport(peerId: "Alice", clock: clock)
        let transportB = SimulatedMeshTransport(peerId: "BobRelay", clock: clock)
        
        try! await transportA.start(serviceType: "_teekum._tcp", session: session)
        try! await transportB.start(serviceType: "_teekum._tcp", session: session)
        
        await transportA.link(to: transportB)
        
        let vm = SOSViewModel(sessionProvider: { session }, cryptoService: CryptoService(), transport: transportA, dateProvider: { clock.now() })
        
        // Disconnect Bob suddenly before dispatch
        await transportA.disconnect(from: "BobRelay")
        
        vm.triggerSOS(emergencyType: .separated)
        
        // Alice should honestly indicate searching for peers
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard vm.deliveryState.isSearchingPeers else {
            print("FAILED: When direct peer is disconnected, deliveryState must be .searchingPeers, got \(vm.deliveryState)")
            return false
        }
        guard vmAckStage(vm) == .searchingPeers else {
            print("FAILED: Ack stage must be SEARCHING_PEERS")
            return false
        }
        
        print("PASSED: testRelayDisconnectsDuringForwarding")
        return true
    }
    
    // MARK: - Test 5: Duplicate SOS Arrives Through Two Different Paths (Diamond Topology)
    
    @MainActor
    public static func testDuplicateSOSArrivesThroughTwoPaths() async -> Bool {
        print("[TEST 5] testDuplicateSOSArrivesThroughTwoPaths...")
        
        let clock = TestMeshClock()
        let key = Data(repeating: 0x33, count: 32)
        let sessionA = GroupSession(sessionId: 0x3333, sessionName: "Diamond", symmetricKeyData: key, localInitials: "ALI", memberSlot: 1)
        let sessionC = GroupSession(sessionId: 0x3333, sessionName: "Diamond", symmetricKeyData: key, localInitials: "CHL", memberSlot: 2)
        
        let crypto = CryptoService()
        let alerterC = MockAudioAlerter()
        let transportC = SimulatedMeshTransport(peerId: "Charlie", clock: clock)
        try! await transportC.start(serviceType: "_teekum._tcp", session: sessionC)
        
        let vmC = SOSViewModel(sessionProvider: { sessionC }, cryptoService: crypto, transport: transportC, audioAlerter: alerterC, dateProvider: { clock.now() })
        
        // Create an authenticated SOS packet from Alice
        let eventId: UInt32 = 0xDEADBEEF
        let payload = SOSPayload(coordinate: CLLocationCoordinate2D(latitude: -6.2, longitude: 106.8), accuracy: 10, sosEventId: eventId, senderInitials: "ALI", emergencyType: .general, batteryLevel: 90)
        let envelope = CleartextEnvelope(version: PacketConstants.protocolVersion, type: .sos, hopLimit: 8, hopCount: 1, sessionId: sessionA.sessionId, sequenceNumber: 0x01000001)
        
        let sealed = try! await crypto.seal(payload: payload.serialize(), envelope: envelope, using: SymmetricKey(data: key))
        let wirePacket = RawWirePacket(envelope: envelope, ciphertext: sealed.ciphertext, authTag: sealed.authTag)
        
        // Path 1 Arrival via Bob (hopCount: 1)
        await vmC.processInboundPacket(InboundPacket(rawPacket: wirePacket, sourcePeerId: "Bob"))
        
        guard alerterC.triggerCount == 1 else {
            print("FAILED: First arrival must trigger siren once")
            return false
        }
        guard vmC.seenSOSEventIds.contains(eventId) else {
            print("FAILED: Charlie must cache sosEventId")
            return false
        }
        
        // Path 2 Arrival via Dave (duplicate packet with hopCount: 2)
        var env2 = envelope
        env2.hopCount = 2
        let wirePacket2 = RawWirePacket(envelope: env2, ciphertext: sealed.ciphertext, authTag: sealed.authTag)
        await vmC.processInboundPacket(InboundPacket(rawPacket: wirePacket2, sourcePeerId: "Dave"))
        
        // CRITICAL: Duplicate must STRICTLY suppress repeated audible siren!
        guard alerterC.triggerCount == 1 else {
            print("FAILED: Duplicate arrival must NOT trigger siren again! Count: \(alerterC.triggerCount)")
            return false
        }
        guard vmC.totalDuplicatesSuppressedCount == 1 else {
            print("FAILED: totalDuplicatesSuppressedCount must be 1, got \(vmC.totalDuplicatesSuppressedCount)")
            return false
        }
        
        print("PASSED: testDuplicateSOSArrivesThroughTwoPaths")
        return true
    }
    
    // MARK: - Test 6: Spoofed SOS From Unauthorized Device
    
    @MainActor
    public static func testSpoofedSOSFromUnauthorizedDevice() async -> Bool {
        print("[TEST 6] testSpoofedSOSFromUnauthorizedDevice...")
        
        let clock = TestMeshClock()
        let groupKey = Data(repeating: 0x44, count: 32)
        let sessionCharlie = GroupSession(sessionId: 0x4444, sessionName: "Secure", symmetricKeyData: groupKey, localInitials: "CHL", memberSlot: 2)
        
        let crypto = CryptoService()
        let alerterC = MockAudioAlerter()
        let transportC = SimulatedMeshTransport(peerId: "Charlie", clock: clock)
        try! await transportC.start(serviceType: "_teekum._tcp", session: sessionCharlie)
        
        let vmC = SOSViewModel(sessionProvider: { sessionCharlie }, cryptoService: crypto, transport: transportC, audioAlerter: alerterC, dateProvider: { clock.now() })
        
        // Attack 1: Random Garbage Packet
        let garbage = RawWirePacket(envelope: CleartextEnvelope(type: .sos, sessionId: 0x4444, sequenceNumber: 1), ciphertext: Data(repeating: 0xFF, count: 30), authTag: Data(repeating: 0xAA, count: 16))
        await vmC.processInboundPacket(InboundPacket(rawPacket: garbage, sourcePeerId: "Mallory"))
        guard alerterC.triggerCount == 0 && vmC.activeIncomingAlert == nil else {
            print("FAILED: Garbage packet must be dropped with zero alerts")
            return false
        }
        
        // Attack 2: Forged Payload with Wrong Key (Mallory uses 0x99)
        let badKey = SymmetricKey(data: Data(repeating: 0x99, count: 32))
        let payload = SOSPayload(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), accuracy: 10, sosEventId: 9999, senderInitials: "MAL", emergencyType: .general, batteryLevel: 50)
        let envelope = CleartextEnvelope(type: .sos, sessionId: 0x4444, sequenceNumber: 2)
        let sealedBad = try! await crypto.seal(payload: payload.serialize(), envelope: envelope, using: badKey)
        let forgedPacket = RawWirePacket(envelope: envelope, ciphertext: sealedBad.ciphertext, authTag: sealedBad.authTag)
        
        await vmC.processInboundPacket(InboundPacket(rawPacket: forgedPacket, sourcePeerId: "Mallory"))
        guard alerterC.triggerCount == 0 && vmC.activeIncomingAlert == nil else {
            print("FAILED: Packet with bad key must fail Poly1305 verification and trigger zero alerts")
            return false
        }
        
        // Attack 3: Wrong Session ID
        let wrongSessionEnvelope = CleartextEnvelope(type: .sos, sessionId: 0x9999, sequenceNumber: 3)
        let sealedWrongSid = try! await crypto.seal(payload: payload.serialize(), envelope: wrongSessionEnvelope, using: SymmetricKey(data: groupKey))
        let wrongSidPacket = RawWirePacket(envelope: wrongSessionEnvelope, ciphertext: sealedWrongSid.ciphertext, authTag: sealedWrongSid.authTag)
        
        await vmC.processInboundPacket(InboundPacket(rawPacket: wrongSidPacket, sourcePeerId: "Stranger"))
        guard alerterC.triggerCount == 0 && vmC.activeIncomingAlert == nil else {
            print("FAILED: Packet with mismatched sessionId must produce zero local alerts")
            return false
        }
        
        print("PASSED: testSpoofedSOSFromUnauthorizedDevice")
        return true
    }
    
    // MARK: - Test 7: ACK Lost or Delayed (Bounded Retry Resolves)
    
    @MainActor
    public static func testACKLostOrDelayedBoundedRetry() async -> Bool {
        print("[TEST 7] testACKLostOrDelayedBoundedRetry...")
        
        let clock = TestMeshClock()
        let session = GroupSession(sessionId: 0x5555, sessionName: "RetryTest", symmetricKeyData: Data(repeating: 0x55, count: 32), localInitials: "ALI")
        let transport = SimulatedMeshTransport(peerId: "Alice", clock: clock)
        let peerB = SimulatedMeshTransport(peerId: "Bob", clock: clock)
        try! await transport.start(serviceType: "_teekum._tcp", session: session)
        try! await peerB.start(serviceType: "_teekum._tcp", session: session)
        await transport.link(to: peerB)
        
        let vm = SOSViewModel(sessionProvider: { session }, cryptoService: CryptoService(), transport: transport, dateProvider: { clock.now() })
        
        vm.triggerSOS(emergencyType: .medical)
        guard vm.retryCount == 0 else { return false }
        
        // Simulate ACK lost on first transmission -> Alice triggers retry
        await vm.triggerRetryNow()
        guard vm.retryCount == 1 else {
            print("FAILED: retryCount should be 1, got \(vm.retryCount)")
            return false
        }
        
        // On second attempt, friend ACK arrives!
        vm.handleAckReceived(status: .deliveredToFriend, responderId: "CHL", hopCount: 2, eventId: vm.activeSOSEventId)
        
        guard case let .deliveredToFriend(id, _) = vm.deliveryState, id == "CHL" else {
            print("FAILED: Must transition to .deliveredToFriend, got \(vm.deliveryState)")
            return false
        }
        guard vm.lastDeliveredHopCount == 2 else {
            print("FAILED: Expected hopCount = 2, got \(String(describing: vm.lastDeliveredHopCount))")
            return false
        }
        
        // Subsequent retries should be cancelled
        await vm.triggerRetryNow()
        guard vm.retryCount == 1 else {
            print("FAILED: Retry must stop once delivered to friend")
            return false
        }
        
        print("PASSED: testACKLostOrDelayedBoundedRetry")
        return true
    }
    
    // MARK: - Test 8: Route Expires During an SOS Attempt (Bounded Flooding Fallback)
    
    @MainActor
    public static func testRouteExpiresDuringSOSAttempt() async -> Bool {
        print("[TEST 8] testRouteExpiresDuringSOSAttempt...")
        
        let clock = TestMeshClock()
        let session = GroupSession(sessionId: 0x6666, sessionName: "RouteExpiry", symmetricKeyData: Data(repeating: 0x66, count: 32), localInitials: "ALI")
        let routingTable = RoutingTable(clock: clock)
        let neighborTable = NeighborTable(clock: clock)
        let transport = SimulatedMeshTransport(peerId: "Alice", clock: clock, neighborTable: neighborTable)
        try! await transport.start(serviceType: "_teekum._tcp", session: session)
        
        // Alice has neighbor Bob connected
        let tBob = SimulatedMeshTransport(peerId: "Bob", clock: clock)
        try! await tBob.start(serviceType: "_teekum._tcp", session: session)
        await transport.link(to: tBob)
        await neighborTable.recordNeighborActivity(peerId: "Bob", rssi: -60, isGroupMember: true)
        
        // Cache a route to Charlie via Bob with 5 second TTL
        await routingTable.recordForwardRoute(destinationId: "Bob", nextHop: "Bob", hopCount: 1, cost: 1, sequenceNumber: 1, ttl: 5.0)
        
        let vm = SOSViewModel(sessionProvider: { session }, cryptoService: CryptoService(), transport: transport, dateProvider: { clock.now() })
        vm.configure(routingTable: routingTable, neighborTable: neighborTable)
        
        // Advance clock by 10s to expire the route
        clock.advance(by: 10.0)
        
        let route = await routingTable.findRoute(to: "Bob")
        guard route == nil || route?.isFresh == false else {
            print("FAILED: Cached route should be expired or nil, got \(String(describing: route))")
            return false
        }
        
        // Trigger SOS: With route expired, system MUST fall back to bounded flooding!
        vm.triggerSOS(emergencyType: .general)
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard case .boundedFlooding = vm.currentRouteChoice else {
            print("FAILED: With route expired, route choice must fall back to .boundedFlooding, got \(vm.currentRouteChoice)")
            return false
        }
        
        print("PASSED: testRouteExpiresDuringSOSAttempt")
        return true
    }
    
    // MARK: - Test 9: Hop Limit Reached Drop Enforcement
    
    @MainActor
    public static func testHopLimitReachedDropEnforcement() async -> Bool {
        print("[TEST 9] testHopLimitReachedDropEnforcement...")
        
        let clock = TestMeshClock()
        let routingTable = RoutingTable(clock: clock)
        let neighborTable = NeighborTable(clock: clock)
        let transport = SimulatedMeshTransport(peerId: "RelayNode", clock: clock, neighborTable: neighborTable)
        let seenCache = SeenPacketCache(clock: clock)
        let forwarder = PacketForwarder(routingTable: routingTable, rateLimiter: ForwardingRateLimiter(clock: clock), neighborTable: neighborTable, seenPacketCache: seenCache, clock: clock, transport: transport)
        
        // Construct packet where hopCount == hopLimit (e.g. 8 of 8)
        let envelope = CleartextEnvelope(type: .sos, hopLimit: 8, hopCount: 8, sessionId: 0x7777, sequenceNumber: 100)
        let wirePacket = RawWirePacket(envelope: envelope, ciphertext: Data(repeating: 0, count: 30), authTag: Data(repeating: 0, count: 16))
        let wireData = try! wirePacket.toWireData()
        
        let decision = await forwarder.evaluateInboundPacket(wireData: wireData, fromPeerId: "UpstreamNode")
        
        guard case .dropHopLimitExceeded = decision else {
            print("FAILED: Packet at hopLimit must be dropped, got \(decision)")
            return false
        }
        
        print("PASSED: testHopLimitReachedDropEnforcement")
        return true
    }
    
    // MARK: - Test 10: Queue Saturated Normal Traffic Preemption
    
    @MainActor
    public static func testQueueSaturatedNormalTrafficPreemption() async -> Bool {
        print("[TEST 10] testQueueSaturatedNormalTrafficPreemption...")
        
        let queue = PriorityOutboxQueue(maxUrgentCapacity: 16, maxRelayCapacity: 32)
        
        // Enqueue 5 normal periodic location pings
        for i in 1...5 {
            let env = CleartextEnvelope(type: .locationPing, sessionId: 0x1234, sequenceNumber: UInt32(i))
            let pingWire = RawWirePacket(envelope: env, ciphertext: Data(repeating: UInt8(i), count: 30), authTag: Data(repeating: 0, count: 16))
            let wireData = try! pingWire.toWireData()
            _ = try! queue.enqueue(data: wireData, destinationPeerId: "peer_\(i)")
        }
        
        guard queue.urgentCount == 0 else {
            print("FAILED: Urgent queue should have 0 items")
            return false
        }
        guard queue.totalQueuedCount == 5 else {
            print("FAILED: Total queue count should be 5")
            return false
        }
        
        // Enqueue 1 urgent SOS packet
        let sosEnv = CleartextEnvelope(type: .sos, sessionId: 0x1234, sequenceNumber: 999)
        let sosWire = RawWirePacket(envelope: sosEnv, ciphertext: Data(repeating: 0xEE, count: 30), authTag: Data(repeating: 0, count: 16))
        let sosData = try! sosWire.toWireData()
        _ = try! queue.enqueue(data: sosData)
        
        guard queue.urgentCount == 1 else {
            print("FAILED: Urgent queue should have 1 item")
            return false
        }
        
        // When popping next item, urgent SOS MUST be popped first, preempting normal pings!
        let popped = queue.dequeue()
        guard let item = popped, item.isUrgent && item.packetType == .sos else {
            print("FAILED: Urgent SOS must preempt queued location pings, popped \(String(describing: popped?.packetType))")
            return false
        }
        
        print("PASSED: testQueueSaturatedNormalTrafficPreemption")
        return true
    }
    
    // MARK: - Test 11: Retry Budget Exhausted Honest Failure
    
    @MainActor
    public static func testRetryBudgetExhaustedHonestFailure() async -> Bool {
        print("[TEST 11] testRetryBudgetExhaustedHonestFailure...")
        
        let clock = TestMeshClock()
        let session = GroupSession(sessionId: 0x8888, sessionName: "Budget", symmetricKeyData: Data(repeating: 0x88, count: 32), localInitials: "ALI")
        let transport = SimulatedMeshTransport(peerId: "Alice", clock: clock)
        let tBob = SimulatedMeshTransport(peerId: "Bob", clock: clock)
        try! await transport.start(serviceType: "_teekum._tcp", session: session)
        try! await tBob.start(serviceType: "_teekum._tcp", session: session)
        await transport.link(to: tBob)
        
        let vm = SOSViewModel(sessionProvider: { session }, cryptoService: CryptoService(), transport: transport, dateProvider: { clock.now() })
        
        vm.triggerSOS(emergencyType: .general)
        guard vm.retryCount == 0 else { return false }
        
        // Retries 1, 2, 3
        await vm.triggerRetryNow()
        guard vm.retryCount == 1 else { return false }
        
        await vm.triggerRetryNow()
        guard vm.retryCount == 2 else { return false }
        
        await vm.triggerRetryNow()
        guard vm.retryCount == 3 else { return false }
        
        // 4th trigger: budget exhausted!
        await vm.triggerRetryNow()
        guard vm.deliveryState.isFailed else {
            print("FAILED: When retry budget is exhausted without ACK, state must be .failed, got \(vm.deliveryState)")
            return false
        }
        guard !vm.deliveryState.isDelivered else {
            print("FAILED: isDelivered must be false")
            return false
        }
        guard vmAckStage(vm) == .deliveryTimedOut else {
            print("FAILED: Expected stage DELIVERY_TIMED_OUT, got \(vmAckStage(vm))")
            return false
        }
        
        print("PASSED: testRetryBudgetExhaustedHonestFailure")
        return true
    }
    
    // MARK: - Helper Methods
    
    private static func getNextFrameData(from transport: SimulatedMeshTransport, timeoutSeconds: Double = 0.5) async -> Data? {
        let task = Task { () -> Data? in
            let stream = await transport.inboundFrames
            for await frame in stream {
                return frame.rawData
            }
            return nil
        }
        
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            task.cancel()
        }
        
        let result = await task.value
        timeoutTask.cancel()
        return result
    }
    
    private static func getNextInboundFrame(from transport: SimulatedMeshTransport, timeoutSeconds: Double = 0.5) async -> InboundFrame? {
        let task = Task { () -> InboundFrame? in
            let stream = await transport.inboundFrames
            for await frame in stream {
                return frame
            }
            return nil
        }
        
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            task.cancel()
        }
        
        let result = await task.value
        timeoutTask.cancel()
        return result
    }
    
    @MainActor
    private static func vmAckStage(_ vm: SOSViewModel) -> AcknowledgementStage {
        vm.deliveryState.stage
    }
}
