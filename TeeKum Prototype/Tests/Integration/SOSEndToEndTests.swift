//
//  SOSEndToEndTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation
import CryptoKit

// MARK: - Mock SOS Audio Alerter for Integration Testing

/// Deterministic mock audio alerter for unit and integration testing.
/// Tracks exact trigger and stop invocations to verify duplicate suppression.
final class MockSOSAudioAlerter: SOSAudioAlerting, @unchecked Sendable {
    private let lock = NSLock()
    private var _triggerCount: Int = 0
    private var _stopCount: Int = 0
    
    var triggerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _triggerCount
    }
    
    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _stopCount
    }
    
    init() {}
    
    func triggerEmergencyAlertFeedback() {
        lock.lock()
        defer { lock.unlock() }
        _triggerCount += 1
    }
    
    func stopEmergencyAlertFeedback() {
        lock.lock()
        defer { lock.unlock() }
        _stopCount += 1
    }
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _triggerCount = 0
        _stopCount = 0
    }
}

// MARK: - Mock In-Memory Transport for SOS Integration Testing

private actor MockSOSPeerTransport: PeerTransport {
    var activePeers: Int
    var broadcastPackets: [Data] = []
    var directPackets: [(data: Data, peerId: String)] = []
    
    private var inboundContinuation: AsyncStream<InboundPacket>.Continuation?
    public let inboundPackets: AsyncStream<InboundPacket>
    
    private var peerUpdatesContinuation: AsyncStream<[PeerInfo]>.Continuation?
    public let peerUpdates: AsyncStream<[PeerInfo]>
    
    private var stateUpdatesContinuation: AsyncStream<TransportState>.Continuation?
    public let stateUpdates: AsyncStream<TransportState>
    
    private var transportErrorsContinuation: AsyncStream<TransportError>.Continuation?
    public let transportErrors: AsyncStream<TransportError>
    
    init(activePeers: Int = 1) {
        self.activePeers = activePeers
        
        var localInbound: AsyncStream<InboundPacket>.Continuation?
        self.inboundPackets = AsyncStream { localInbound = $0 }
        self.inboundContinuation = localInbound
        
        var localPeer: AsyncStream<[PeerInfo]>.Continuation?
        self.peerUpdates = AsyncStream { localPeer = $0 }
        self.peerUpdatesContinuation = localPeer
        
        var localState: AsyncStream<TransportState>.Continuation?
        self.stateUpdates = AsyncStream { localState = $0 }
        self.stateUpdatesContinuation = localState
        
        var localErrors: AsyncStream<TransportError>.Continuation?
        self.transportErrors = AsyncStream { localErrors = $0 }
        self.transportErrorsContinuation = localErrors
    }
    
    func setActivePeers(_ count: Int) {
        self.activePeers = count
    }
    
    func start(serviceType: String, session: GroupSession) async throws {}
    func stop() async {}
    
    func broadcastPacket(_ data: Data) async throws {
        broadcastPackets.append(data)
    }
    
    func sendPacket(_ data: Data, to peerId: String) async throws {
        directPackets.append((data: data, peerId: peerId))
    }
    
    func activeDirectPeerCount() async -> Int {
        activePeers
    }
    
    func getDiagnostics() async -> TransportDiagnostics {
        TransportDiagnostics(
            localPeerId: "TEST",
            serviceType: "_teekum._udp",
            sessionName: "Test",
            sessionId: 1,
            state: .connected(peerCount: activePeers),
            activeDirectPeers: [],
            packetsSent: broadcastPackets.count,
            packetsReceived: 0,
            obsoletePingsCoalesced: 0,
            sendErrors: 0,
            lastError: nil,
            recentEvents: []
        )
    }
    
    func deliverInbound(_ packet: InboundPacket) {
        inboundContinuation?.yield(packet)
    }
}

// MARK: - Mock Location Service Provider for SOS Testing

@MainActor
private final class MockSOSLocationService: LocationServiceProvider {
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
    #if os(iOS)
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    #else
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    #endif
    var isGPSAvailable: Bool = true
    var isLocationStale: Bool = false
    var locationAge: TimeInterval? = 2.0
    var currentCadenceInterval: TimeInterval = 4.0
    var cadenceConfig: CadenceConfiguration = CadenceConfiguration()
    
    let publishedPings: AsyncStream<LocationPin>
    private let publishedPingsContinuation: AsyncStream<LocationPin>.Continuation
    
    init(initialLocation: LocationPin? = nil) {
        self.currentLocation = initialLocation
        var continuation: AsyncStream<LocationPin>.Continuation!
        self.publishedPings = AsyncStream { continuation = $0 }
        self.publishedPingsContinuation = continuation
    }
    
    func requestPermissions() async -> Bool { true }
    func startTracking() throws {}
    func stopTracking() {}
    
    func getLatestLocationForSOS() -> LocationPin? {
        currentLocation
    }
}

// MARK: - Comprehensive SOS Verification Suite

/// Comprehensive verification suite for the Emergency SOS flow, hold gesture,
/// urgent priority scheduling, bounded retries, duplicate suppression,
/// authentication, and honest delivery state semantics.
public struct SOSEndToEndTests {
    
    @MainActor
    public static func runAllTests() async -> Bool {
        print("================================================================")
        print("--- [SOSEndToEndTests] Running Emergency SOS Verification Suite ---")
        print("================================================================")
        var passed = true
        
        if !(await testHoldGestureStateMachine()) { passed = false }
        if !(await testDispatchIndependentOfPingIntervalAndTrueTimestamp()) { passed = false }
        if !(await testUrgentQueuePriorityAndCoalescingProtection()) { passed = false }
        if !(await testHonestDeliveryStateTransitionsAndEvidence()) { passed = false }
        if !(await testBoundedRetriesAndUnreachableRecipientHandling()) { passed = false }
        if !(await testUnauthorizedSenderAndTamperRejection()) { passed = false }
        if !(await testDuplicateSuppressionAndRepeatedSirenPrevention()) { passed = false }
        if !(await testSimulatedTwoDeviceSOSRoundtrip()) { passed = false }
        if !(await testRelayAckProgressionToFriendAck()) { passed = false }
        if !(await testEmptyPeerListNeverPresentsSuccessfulDelivery()) { passed = false }
        if !(await testMultiHopRelaySOSForwarding()) { passed = false }
        
        if passed {
            print("================================================================")
            print("--- [SOSEndToEndTests] ✓ ALL 11 SOS VERIFICATION SUITES PASSED ---")
            print("================================================================")
        } else {
            print("================================================================")
            print("--- [SOSEndToEndTests] ✗ SOME SOS VERIFICATION TESTS FAILED ---")
            print("================================================================")
        }
        return passed
    }
    
    // MARK: - 1. Hold Gesture State Machine
    
    @MainActor
    private static func testHoldGestureStateMachine() async -> Bool {
        print("[TEST 1] testHoldGestureStateMachine...")
        let vm = SOSViewModel()
        
        guard vm.deliveryState == .idle, vm.holdProgress == 0.0 else {
            print("FAILED: initial state must be .idle with 0.0 progress")
            return false
        }
        
        // Touch down
        vm.handlePressBegan()
        guard case let .countdown(remaining) = vm.deliveryState, remaining == 3.0 else {
            print("FAILED: deliveryState must be .countdown(3.0) on press began")
            return false
        }
        
        // 1.5 seconds elapsed (50% progress)
        vm.updateProgress(elapsedSeconds: 1.5)
        guard abs(vm.holdProgress - 0.5) < 0.001 else {
            print("FAILED: holdProgress must be 0.5 at 1.5s")
            return false
        }
        guard case let .countdown(remaining) = vm.deliveryState, abs(remaining - 1.5) < 0.001 else {
            print("FAILED: remaining must be 1.5s at 1.5s elapsed")
            return false
        }
        
        // Early release at 2.5s (< 3.0s threshold) -> Must cancel and reset to idle!
        vm.handlePressCancelled()
        guard vm.deliveryState == .idle, vm.holdProgress == 0.0 else {
            print("FAILED: early release must cancel hold and reset to .idle")
            return false
        }
        
        // Press again and complete full 3.0 seconds
        vm.handlePressBegan()
        vm.updateProgress(elapsedSeconds: 2.0)
        vm.updateProgress(elapsedSeconds: 3.0)
        
        guard vm.holdProgress == 1.0, vm.deliveryState == .localSending else {
            print("FAILED: completed 3s hold must trigger SOS and enter .localSending")
            return false
        }
        
        // Reset returns to idle
        vm.reset()
        guard vm.deliveryState == .idle, vm.holdProgress == 0.0 else {
            print("FAILED: reset must return to .idle")
            return false
        }
        
        print("PASSED: testHoldGestureStateMachine")
        return true
    }
    
    // MARK: - 2. Independent Dispatch & Coordinate Freshness
    
    @MainActor
    private static func testDispatchIndependentOfPingIntervalAndTrueTimestamp() async -> Bool {
        print("[TEST 2] testDispatchIndependentOfPingIntervalAndTrueTimestamp...")
        
        // GPS measured 14.5 seconds ago (honest measurement age)
        let measurementTime = Date(timeIntervalSince1970: 1761550000)
        let pin = LocationPin(
            coordinate: CLLocationCoordinate2D(latitude: 33.681234, longitude: -116.234567),
            horizontalAccuracy: 6.5,
            timestamp: measurementTime
        )
        
        let mockLocation = MockSOSLocationService(initialLocation: pin)
        mockLocation.isLiveSharingEnabled = false // Live Sharing is paused!
        
        let mockTransport = MockSOSPeerTransport(activePeers: 1)
        let cryptoService = CryptoService()
        let session = GroupSession(
            sessionId: 0x1234,
            sessionName: "Test Group",
            symmetricKeyData: Data(repeating: 0x42, count: 32),
            localInitials: "TST",
            memberSlot: 1,
            isHost: true
        )
        
        let vm = SOSViewModel(
            locationService: mockLocation,
            sessionProvider: { session },
            cryptoService: cryptoService,
            transport: mockTransport
        )
        
        // Trigger SOS immediately
        vm.triggerSOS(emergencyType: .medical)
        
        // Allow async dispatch to execute
        try? await Task.sleep(nanoseconds: 150_000_000)
        
        // Verify broadcast occurred independently of Live Sharing OFF
        let packets = await mockTransport.broadcastPackets
        guard packets.count == 1 else {
            print("FAILED: SOS must broadcast packet immediately regardless of Live Sharing state (got \(packets.count))")
            return false
        }
        
        // Verify wire packet structure
        let wireData = packets[0]
        guard wireData.count == PacketConstants.wirePacketSize else {
            print("FAILED: packet must be exactly \(PacketConstants.wirePacketSize) bytes")
            return false
        }
        
        let rawWire = try! RawWirePacket.fromWireData(wireData)
        guard rawWire.envelope.type == .sos else {
            print("FAILED: packet type must be .sos (0x02)")
            return false
        }
        guard rawWire.envelope.hopLimit == PacketConstants.sosHopLimit else {
            print("FAILED: SOS envelope hopLimit must be \(PacketConstants.sosHopLimit), got \(rawWire.envelope.hopLimit)")
            return false
        }
        
        // Decrypt payload to verify coordinate freshness honesty
        let key = SymmetricKey(data: session.symmetricKeyData)
        let decrypted = try! await cryptoService.open(
            ciphertext: rawWire.ciphertext,
            envelope: rawWire.envelope,
            authTag: rawWire.authTag,
            using: key
        )
        
        let payload = try! SOSPayload.deserialize(from: decrypted)
        guard payload.emergencyType == .medical else {
            print("FAILED: emergencyType mismatch")
            return false
        }
        
        // HONESTY CHECK: Measurement timestamp must equal original GPS hardware timestamp!
        guard abs(payload.timestamp.timeIntervalSince1970 - measurementTime.timeIntervalSince1970) < 0.001 else {
            print("FAILED: SOS payload must retain original GPS measurement timestamp without false freshness")
            return false
        }
        
        guard abs(payload.coordinate.latitude - 33.681234) < 0.0001,
              abs(payload.coordinate.longitude - (-116.234567)) < 0.0001 else {
            print("FAILED: coordinates mismatch")
            return false
        }
        
        print("PASSED: testDispatchIndependentOfPingIntervalAndTrueTimestamp")
        return true
    }
    
    // MARK: - 3. Urgent Queue Priority & Coalescing Protection
    
    @MainActor
    private static func testUrgentQueuePriorityAndCoalescingProtection() async -> Bool {
        print("[TEST 3] testUrgentQueuePriorityAndCoalescingProtection...")
        let queue = PriorityOutboxQueue(maxUrgentCapacity: 10)
        
        let locPingHeader = (PacketConstants.protocolVersion << 4) | PacketType.locationPing.rawValue
        let sosHeader = (PacketConstants.protocolVersion << 4) | PacketType.sos.rawValue
        let ackHeader = (PacketConstants.protocolVersion << 4) | PacketType.ack.rawValue
        
        // 1. Enqueue older normal location ping (Type 0x01)
        var ping1 = Data(repeating: 0x11, count: PacketConstants.wirePacketSize)
        ping1[0] = locPingHeader
        try! queue.enqueue(data: ping1, destinationPeerId: "peer-B")
        
        guard queue.totalQueuedCount == 1, queue.urgentCount == 0 else {
            print("FAILED: normal ping should be in normal lane")
            return false
        }
        
        // 2. Enqueue newer normal location ping for same destination -> Coalesce!
        var ping2 = Data(repeating: 0x22, count: PacketConstants.wirePacketSize)
        ping2[0] = locPingHeader
        try! queue.enqueue(data: ping2, destinationPeerId: "peer-B")
        
        guard queue.totalQueuedCount == 1, queue.obsoletePingsCoalesced == 1 else {
            print("FAILED: normal location pings must coalesce and discard obsolete fixes")
            return false
        }
        
        // 3. Enqueue Emergency SOS Packet (Type 0x02)
        var sosPacket = Data(repeating: 0xEE, count: PacketConstants.wirePacketSize)
        sosPacket[0] = sosHeader
        try! queue.enqueue(data: sosPacket)
        
        guard queue.urgentCount == 1, queue.totalQueuedCount == 2 else {
            print("FAILED: SOS must be placed in urgent lane")
            return false
        }
        
        // 4. Enqueue Delivery ACK Packet (Type 0x06)
        var ackPacket = Data(repeating: 0xAA, count: PacketConstants.wirePacketSize)
        ackPacket[0] = ackHeader
        try! queue.enqueue(data: ackPacket)
        
        guard queue.urgentCount == 2, queue.totalQueuedCount == 3 else {
            print("FAILED: ACK must be placed in urgent lane")
            return false
        }
        
        // 5. Enqueue third location ping -> must coalesce without touching urgent lane!
        var ping3 = Data(repeating: 0x33, count: PacketConstants.wirePacketSize)
        ping3[0] = locPingHeader
        try! queue.enqueue(data: ping3, destinationPeerId: "peer-B")
        
        guard queue.urgentCount == 2, queue.obsoletePingsCoalesced == 2 else {
            print("FAILED: coalescing must never overwrite urgent packets")
            return false
        }
        
        // 6. Verify Dequeue Order: Urgent lane (SOS, then ACK) strictly preempts normal ping!
        guard let popped1 = queue.dequeue(), popped1.packetType == .sos else {
            print("FAILED: dequeue #1 must be urgent SOS packet")
            return false
        }
        
        guard let popped2 = queue.dequeue(), popped2.packetType == .ack else {
            print("FAILED: dequeue #2 must be urgent ACK packet")
            return false
        }
        
        guard let popped3 = queue.dequeue(), popped3.packetType == .locationPing else {
            print("FAILED: dequeue #3 must be coalesced location ping")
            return false
        }
        
        guard popped3.packetData == ping3 else {
            print("FAILED: coalesced ping must be the newest fix (ping3)")
            return false
        }
        
        guard queue.isEmpty else {
            print("FAILED: queue should now be empty")
            return false
        }
        
        // 7. Verify Retry Preemption: Re-queuing urgent item puts it at index 0
        let retried = queue.requeueForRetry(popped1)
        guard retried, queue.urgentCount == 1 else {
            print("FAILED: requeueForRetry must accept urgent item")
            return false
        }
        
        let poppedRetry = queue.dequeue()
        guard poppedRetry?.packetType == .sos, poppedRetry?.attemptCount == 1 else {
            print("FAILED: retried SOS must preempt back to front of urgent lane")
            return false
        }
        
        print("PASSED: testUrgentQueuePriorityAndCoalescingProtection")
        return true
    }
    
    // MARK: - 4. Delivery State Transitions & Evidence Tracking
    
    @MainActor
    private static func testHonestDeliveryStateTransitionsAndEvidence() async -> Bool {
        print("[TEST 4] testHonestDeliveryStateTransitionsAndEvidence...")
        let vm = SOSViewModel()
        
        // Dispatch
        vm.triggerSOS()
        guard vm.deliveryState == .localSending else {
            print("FAILED: state should be .localSending")
            return false
        }
        
        // Relay ACK arrival
        vm.handleAckReceived(status: .relayedByMeshHop, responderId: "REL", hopCount: 3)
        guard case let .relayedAck(hops, responder) = vm.deliveryState, hops == 3, responder == "REL" else {
            print("FAILED: relay ack must set .relayedAck with hop count and responder evidence")
            return false
        }
        
        // HONESTY INVARIANT: Must NOT claim delivery to friend!
        guard !vm.deliveryState.isDelivered, !vm.deliveryState.title.contains("Delivered to Friend") else {
            print("FAILED: relay ack must NEVER claim friend delivery")
            return false
        }
        
        // Destination Friend ACK arrival
        vm.handleAckReceived(status: .deliveredToFriend, responderId: "FRN", hopCount: 1)
        guard case let .deliveredToFriend(friendId, _) = vm.deliveryState, friendId == "FRN" else {
            print("FAILED: friend delivery ack must set .deliveredToFriend with friendId evidence")
            return false
        }
        
        guard vm.deliveryState.isDelivered, vm.lastDeliveredFriendId == "FRN" else {
            print("FAILED: isDelivered and lastDeliveredFriendId mismatch")
            return false
        }
        
        print("PASSED: testHonestDeliveryStateTransitionsAndEvidence")
        return true
    }
    
    // MARK: - 5. Bounded Retries & Unreachable Recipient Handling
    
    @MainActor
    private static func testBoundedRetriesAndUnreachableRecipientHandling() async -> Bool {
        print("[TEST 5] testBoundedRetriesAndUnreachableRecipientHandling...")
        
        let mockTransport = MockSOSPeerTransport(activePeers: 1)
        let cryptoService = CryptoService()
        let session = GroupSession(
            sessionId: 0x9999,
            sessionName: "Test Group",
            symmetricKeyData: Data(repeating: 0x55, count: 32),
            localInitials: "TST",
            memberSlot: 1,
            isHost: true
        )
        
        let vm = SOSViewModel(
            sessionProvider: { session },
            cryptoService: cryptoService,
            transport: mockTransport
        )
        vm.retryInterval = 0.05 // Rapid 50ms interval for fast deterministic test
        vm.maxRetries = 2       // Total 3 transmissions: initial + 2 retries
        
        vm.triggerSOS()
        
        // Wait for retry loop to execute all attempts (initial + 2 retries = ~150ms)
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Verify broadcast packet count equals 3 (initial + 2 retries)
        let packets = await mockTransport.broadcastPackets
        guard packets.count == 3 else {
            print("FAILED: expected exactly 3 broadcast packets (initial + 2 retries), got \(packets.count)")
            return false
        }
        
        // Verify all 3 packets reuse the exact same sosEventId
        var eventIds = Set<UInt32>()
        let key = SymmetricKey(data: session.symmetricKeyData)
        for pkt in packets {
            let raw = try! RawWirePacket.fromWireData(pkt)
            let dec = try! await cryptoService.open(ciphertext: raw.ciphertext, envelope: raw.envelope, authTag: raw.authTag, using: key)
            let p = try! SOSPayload.deserialize(from: dec)
            eventIds.insert(p.sosEventId)
        }
        
        guard eventIds.count == 1 else {
            print("FAILED: retries must reuse the exact same sosEventId for deduplication")
            return false
        }
        
        // Verify failure state: retries exhausted without ACK
        guard case .failed = vm.deliveryState else {
            print("FAILED: deliveryState must be .failed when retries exhausted without ACK")
            return false
        }
        
        // NON-NEGOTIABLE CRITERION: Exhausted retry budget must NEVER be presented as successful!
        guard !vm.deliveryState.isDelivered else {
            print("FAILED: exhausted retry budget must not be presented as delivered")
            return false
        }
        
        print("PASSED: testBoundedRetriesAndUnreachableRecipientHandling")
        return true
    }
    
    // MARK: - 6. Inbound Authentication & Unauthorized Sender Rejection
    
    @MainActor
    private static func testUnauthorizedSenderAndTamperRejection() async -> Bool {
        print("[TEST 6] testUnauthorizedSenderAndTamperRejection...")
        
        let cryptoService = CryptoService()
        let session = GroupSession(
            sessionId: 0x1111,
            sessionName: "Legit Group",
            symmetricKeyData: Data(repeating: 0xAA, count: 32),
            localInitials: "VIC",
            memberSlot: 1,
            isHost: false
        )
        
        let mockAlerter = MockSOSAudioAlerter()
        let vm = SOSViewModel(
            sessionProvider: { session },
            cryptoService: cryptoService,
            audioAlerter: mockAlerter
        )
        
        // 1. Rogue sender encrypted with wrong stranger key
        let strangerKey = SymmetricKey(data: Data(repeating: 0xFF, count: 32))
        let payload = SOSPayload(
            coordinate: CLLocationCoordinate2D(latitude: 33.68, longitude: -116.23),
            accuracy: 5,
            sosEventId: 0xBAD00001,
            senderInitials: "STR",
            emergencyType: .security,
            batteryLevel: 90
        )
        let env = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .sos,
            sessionId: session.sessionId,
            sequenceNumber: 0x02000001
        )
        
        let sealedStranger = try! await cryptoService.seal(payload: payload.serialize(), envelope: env, using: strangerKey)
        let strangerWire = RawWirePacket(envelope: env, ciphertext: sealedStranger.ciphertext, authTag: sealedStranger.authTag)
        let inboundStranger = InboundPacket(rawPacket: strangerWire, sourcePeerId: "stranger-node")
        
        // Ingest rogue stranger packet
        await vm.processInboundPacket(inboundStranger)
        
        // SECURITY VERIFICATION: Zero state mutation, no siren, no alert!
        guard vm.activeIncomingAlert == nil, !vm.isSirenActive, mockAlerter.triggerCount == 0 else {
            print("FAILED: unauthenticated stranger packet must be rejected without triggering siren")
            return false
        }
        guard vm.totalReceivedSOSCount == 0 else {
            print("FAILED: totalReceivedSOSCount must not increment for rogue packets")
            return false
        }
        
        // 2. Tampered Envelope AAD: Attacker tampers with sequenceNumber on valid packet
        let legitKey = SymmetricKey(data: session.symmetricKeyData)
        let sealedLegit = try! await cryptoService.seal(payload: payload.serialize(), envelope: env, using: legitKey)
        
        var tamperedEnv = env
        tamperedEnv.sequenceNumber = 0x99999999 // Tampered sequence number!
        let tamperedWire = RawWirePacket(envelope: tamperedEnv, ciphertext: sealedLegit.ciphertext, authTag: sealedLegit.authTag)
        let inboundTampered = InboundPacket(rawPacket: tamperedWire, sourcePeerId: "tampered-node")
        
        await vm.processInboundPacket(inboundTampered)
        guard vm.activeIncomingAlert == nil, mockAlerter.triggerCount == 0 else {
            print("FAILED: tampered AAD must cause Poly1305 verification failure and drop packet")
            return false
        }
        
        // 3. Self-reflection packet (senderInitials matches localInitials)
        let selfPayload = SOSPayload(
            coordinate: CLLocationCoordinate2D(latitude: 33.68, longitude: -116.23),
            accuracy: 5,
            sosEventId: 0x00001234,
            senderInitials: session.localInitials, // Reflection
            emergencyType: .general,
            batteryLevel: 80
        )
        let sealedSelf = try! await cryptoService.seal(payload: selfPayload.serialize(), envelope: env, using: legitKey)
        let selfWire = RawWirePacket(envelope: env, ciphertext: sealedSelf.ciphertext, authTag: sealedSelf.authTag)
        let inboundSelf = InboundPacket(rawPacket: selfWire, sourcePeerId: "self")
        
        await vm.processInboundPacket(inboundSelf)
        guard vm.activeIncomingAlert == nil, mockAlerter.triggerCount == 0 else {
            print("FAILED: self reflection packets must be ignored")
            return false
        }
        
        print("PASSED: testUnauthorizedSenderAndTamperRejection")
        return true
    }
    
    // MARK: - 7. Duplicate Suppression & Repeated Siren Prevention
    
    @MainActor
    private static func testDuplicateSuppressionAndRepeatedSirenPrevention() async -> Bool {
        print("[TEST 7] testDuplicateSuppressionAndRepeatedSirenPrevention...")
        
        let cryptoService = CryptoService()
        let mockTransport = MockSOSPeerTransport(activePeers: 1)
        let session = GroupSession(
            sessionId: 0x3333,
            sessionName: "Test Group",
            symmetricKeyData: Data(repeating: 0x77, count: 32),
            localInitials: "RCV",
            memberSlot: 1,
            isHost: false
        )
        
        let mockAlerter = MockSOSAudioAlerter()
        let vm = SOSViewModel(
            sessionProvider: { session },
            cryptoService: cryptoService,
            transport: mockTransport,
            audioAlerter: mockAlerter
        )
        
        let sosPayload = SOSPayload(
            coordinate: CLLocationCoordinate2D(latitude: 33.68, longitude: -116.23),
            accuracy: 5,
            sosEventId: 0xDEADBEEF, // Constant event ID
            senderInitials: "FRN",   // Friend in distress
            emergencyType: .separated,
            batteryLevel: 65
        )
        
        let env1 = CleartextEnvelope(version: PacketConstants.protocolVersion, type: .sos, sessionId: session.sessionId, sequenceNumber: 0x02000001)
        let legitKey = SymmetricKey(data: session.symmetricKeyData)
        let sealed1 = try! await cryptoService.seal(payload: sosPayload.serialize(), envelope: env1, using: legitKey)
        let wire1 = RawWirePacket(envelope: env1, ciphertext: sealed1.ciphertext, authTag: sealed1.authTag)
        
        // --- Packet 1: Initial Arrival ---
        await vm.processInboundPacket(InboundPacket(rawPacket: wire1, sourcePeerId: "friend-device"))
        
        guard vm.activeIncomingAlert?.id == 0xDEADBEEF else {
            print("FAILED: activeIncomingAlert should be set for packet 1")
            return false
        }
        guard mockAlerter.triggerCount == 1 else {
            print("FAILED: siren should trigger exactly once on initial arrival")
            return false
        }
        guard vm.totalReceivedSOSCount == 1, vm.totalDuplicatesSuppressedCount == 0 else {
            print("FAILED: telemetry mismatch on initial arrival")
            return false
        }
        
        // Check that initial delivery ACK was emitted
        let initialAcks = await mockTransport.broadcastPackets
        guard initialAcks.count == 1 else {
            print("FAILED: receiver must emit delivery ACK immediately")
            return false
        }
        
        // --- Packet 2: Rapid Duplicate Retransmission (Same sosEventId) ---
        let env2 = CleartextEnvelope(version: PacketConstants.protocolVersion, type: .sos, sessionId: session.sessionId, sequenceNumber: 0x02000002)
        let sealed2 = try! await cryptoService.seal(payload: sosPayload.serialize(), envelope: env2, using: legitKey)
        let wire2 = RawWirePacket(envelope: env2, ciphertext: sealed2.ciphertext, authTag: sealed2.authTag)
        
        await vm.processInboundPacket(InboundPacket(rawPacket: wire2, sourcePeerId: "friend-device"))
        
        // DUPLICATE INVARIANT: Siren must NOT re-trigger! Alert must NOT duplicate!
        guard mockAlerter.triggerCount == 1 else {
            print("FAILED: duplicate packet must NOT re-trigger audible siren (triggerCount: \(mockAlerter.triggerCount))")
            return false
        }
        guard vm.totalDuplicatesSuppressedCount == 1 else {
            print("FAILED: totalDuplicatesSuppressedCount must increment to 1")
            return false
        }
        
        // RE-EMIT ACK: Must re-emit delivery ACK so sender's retry loop resolves
        let totalAcksAfterDup = await mockTransport.broadcastPackets
        guard totalAcksAfterDup.count == 2 else {
            print("FAILED: receiver must re-emit delivery ACK for duplicate packet to satisfy sender's retries")
            return false
        }
        
        // --- Packet 3: Third Duplicate Retransmission ---
        let env3 = CleartextEnvelope(version: PacketConstants.protocolVersion, type: .sos, sessionId: session.sessionId, sequenceNumber: 0x02000003)
        let sealed3 = try! await cryptoService.seal(payload: sosPayload.serialize(), envelope: env3, using: legitKey)
        let wire3 = RawWirePacket(envelope: env3, ciphertext: sealed3.ciphertext, authTag: sealed3.authTag)
        
        await vm.processInboundPacket(InboundPacket(rawPacket: wire3, sourcePeerId: "friend-device"))
        
        guard mockAlerter.triggerCount == 1 else {
            print("FAILED: third duplicate packet must NOT re-trigger siren")
            return false
        }
        guard vm.totalDuplicatesSuppressedCount == 2 else {
            print("FAILED: totalDuplicatesSuppressedCount must increment to 2")
            return false
        }
        
        print("PASSED: testDuplicateSuppressionAndRepeatedSirenPrevention")
        return true
    }
    
    // MARK: - 8. Simulated Two-Device SOS Roundtrip
    
    @MainActor
    private static func testSimulatedTwoDeviceSOSRoundtrip() async -> Bool {
        print("[TEST 8] testSimulatedTwoDeviceSOSRoundtrip...")
        
        let cryptoService = CryptoService()
        let sharedKeyData = Data(repeating: 0x88, count: 32)
        let sessionId: UInt16 = 0x5555
        
        // Device A (Distressed Sender)
        let transportA = MockSOSPeerTransport(activePeers: 1)
        let sessionA = GroupSession(
            sessionId: sessionId,
            sessionName: "Festival Group",
            symmetricKeyData: sharedKeyData,
            localInitials: "ALX",
            memberSlot: 1,
            isHost: true
        )
        let vmA = SOSViewModel(
            sessionProvider: { sessionA },
            cryptoService: cryptoService,
            transport: transportA
        )
        vmA.retryInterval = 0.5
        
        // Device B (Observing Friend)
        let transportB = MockSOSPeerTransport(activePeers: 1)
        let sessionB = GroupSession(
            sessionId: sessionId,
            sessionName: "Festival Group",
            symmetricKeyData: sharedKeyData,
            localInitials: "BOB",
            memberSlot: 2,
            isHost: false
        )
        let mockAlerterB = MockSOSAudioAlerter()
        let vmB = SOSViewModel(
            sessionProvider: { sessionB },
            cryptoService: cryptoService,
            transport: transportB,
            audioAlerter: mockAlerterB
        )
        
        // 1. Device A triggers SOS
        vmA.triggerSOS(emergencyType: .security)
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        guard vmA.deliveryState == .localSending else {
            print("FAILED: Device A should be in .localSending")
            return false
        }
        
        // 2. Radio transmission: Alice -> Bob
        let aPackets = await transportA.broadcastPackets
        guard let alicePacket = aPackets.first else {
            print("FAILED: Alice should have broadcast packet")
            return false
        }
        
        let rawAlice = try! RawWirePacket.fromWireData(alicePacket)
        await vmB.processInboundPacket(InboundPacket(rawPacket: rawAlice, sourcePeerId: "Alice"))
        
        // 3. Verify Bob received and processed Alice's emergency
        guard vmB.activeIncomingAlert?.emergencyType == .security else {
            print("FAILED: Bob should have activeIncomingAlert with .security")
            return false
        }
        guard mockAlerterB.triggerCount == 1 else {
            print("FAILED: Bob's siren should sound")
            return false
        }
        
        // 4. Radio transmission: Bob's ACK -> Alice
        let bPackets = await transportB.broadcastPackets
        guard let bobAckPacket = bPackets.first else {
            print("FAILED: Bob should have emitted ACK")
            return false
        }
        
        let rawBobAck = try! RawWirePacket.fromWireData(bobAckPacket)
        await vmA.processInboundPacket(InboundPacket(rawPacket: rawBobAck, sourcePeerId: "Bob"))
        
        // 5. Verify Alice confirms DELIVERED_TO_FRIEND
        guard case let .deliveredToFriend(friendId, _) = vmA.deliveryState, friendId == "BOB" else {
            print("FAILED: Alice's state must transition to .deliveredToFriend with Bob's ID")
            return false
        }
        guard vmA.deliveryState.isDelivered else {
            print("FAILED: isDelivered must be true")
            return false
        }
        
        print("PASSED: testSimulatedTwoDeviceSOSRoundtrip")
        return true
    }
    
    // MARK: - 9. Relay ACK Progression to Friend ACK
    
    @MainActor
    private static func testRelayAckProgressionToFriendAck() async -> Bool {
        print("[TEST 9] testRelayAckProgressionToFriendAck...")
        let vm = SOSViewModel()
        vm.triggerSOS()
        
        guard vm.deliveryState == .localSending else {
            print("FAILED: state should be .localSending")
            return false
        }
        
        // 1. Relay Node responds first with relayedByMeshHop
        vm.handleAckReceived(status: .relayedByMeshHop, responderId: "REL", hopCount: 2)
        guard case let .relayedAck(hops, responder) = vm.deliveryState, hops == 2, responder == "REL" else {
            print("FAILED: state should be .relayedAck")
            return false
        }
        guard !vm.deliveryState.isDelivered else {
            print("FAILED: relayedAck must not be considered delivered to friend")
            return false
        }
        
        // 2. Later, destination friend device confirms delivery
        vm.handleAckReceived(status: .deliveredToFriend, responderId: "BOB", hopCount: 1)
        guard case let .deliveredToFriend(friendId, _) = vm.deliveryState, friendId == "BOB" else {
            print("FAILED: state must progress to .deliveredToFriend upon friend confirmation")
            return false
        }
        guard vm.deliveryState.isDelivered else {
            print("FAILED: isDelivered must be true after friend confirmation")
            return false
        }
        
        print("PASSED: testRelayAckProgressionToFriendAck")
        return true
    }
    
    // MARK: - 10. Empty Peer List Handling
    
    @MainActor
    private static func testEmptyPeerListNeverPresentsSuccessfulDelivery() async -> Bool {
        print("[TEST 10] testEmptyPeerListNeverPresentsSuccessfulDelivery...")
        
        // Mock transport with 0 connected peers
        let mockTransport = MockSOSPeerTransport(activePeers: 0)
        let cryptoService = CryptoService()
        let session = GroupSession(
            sessionId: 0x7777,
            sessionName: "Lonely Group",
            symmetricKeyData: Data(repeating: 0x33, count: 32),
            localInitials: "SOL",
            memberSlot: 1,
            isHost: true
        )
        
        let vm = SOSViewModel(
            sessionProvider: { session },
            cryptoService: cryptoService,
            transport: mockTransport
        )
        
        vm.triggerSOS()
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        // NON-NEGOTIABLE CRITERION: An empty peer list must NOT be presented as successful delivery!
        guard vm.deliveryState == .searchingPeers else {
            print("FAILED: deliveryState must be .searchingPeers when direct peer count is 0 (got \(vm.deliveryState))")
            return false
        }
        guard !vm.deliveryState.isDelivered else {
            print("FAILED: isDelivered must be false for empty peer list")
            return false
        }
        
        print("PASSED: testEmptyPeerListNeverPresentsSuccessfulDelivery")
        return true
    }
    
    // MARK: - 11. Multi-Hop Mesh Relay Forwarding
    
    @MainActor
    private static func testMultiHopRelaySOSForwarding() async -> Bool {
        print("[TEST 11] testMultiHopRelaySOSForwarding...")
        
        let cryptoService = CryptoService()
        let sharedKeyData = Data(repeating: 0x99, count: 32)
        let sessionId: UInt16 = 0x7788
        
        // Node A: Alice (Sender in distress)
        let transportA = MockSOSPeerTransport(activePeers: 1)
        let sessionA = GroupSession(
            sessionId: sessionId,
            sessionName: "Festival Mesh",
            symmetricKeyData: sharedKeyData,
            localInitials: "ALX",
            memberSlot: 1,
            isHost: true
        )
        let vmA = SOSViewModel(
            sessionProvider: { sessionA },
            cryptoService: cryptoService,
            transport: transportA
        )
        
        // Node B: Bob (Intermediary Local Relay)
        let transportB = MockSOSPeerTransport(activePeers: 2)
        let sessionB = GroupSession(
            sessionId: sessionId,
            sessionName: "Festival Mesh",
            symmetricKeyData: sharedKeyData,
            localInitials: "BOB",
            memberSlot: 2,
            isHost: false
        )
        let mockAlerterB = MockSOSAudioAlerter()
        let vmB = SOSViewModel(
            sessionProvider: { sessionB },
            cryptoService: cryptoService,
            transport: transportB,
            audioAlerter: mockAlerterB
        )
        vmB.memberNameResolver = { id in id == "ALX" ? "Alice" : nil }
        
        // Node C: Charlie (Downstream Friend reachable only through Bob)
        let transportC = MockSOSPeerTransport(activePeers: 1)
        let sessionC = GroupSession(
            sessionId: sessionId,
            sessionName: "Festival Mesh",
            symmetricKeyData: sharedKeyData,
            localInitials: "CHL",
            memberSlot: 3,
            isHost: false
        )
        let mockAlerterC = MockSOSAudioAlerter()
        let vmC = SOSViewModel(
            sessionProvider: { sessionC },
            cryptoService: cryptoService,
            transport: transportC,
            audioAlerter: mockAlerterC
        )
        vmC.memberNameResolver = { id in id == "ALX" ? "Alice" : nil }
        
        // Step 1: Alice triggers SOS
        vmA.triggerSOS(emergencyType: .medical)
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        let packetsFromA = await transportA.broadcastPackets
        guard let alicePacket = packetsFromA.first else {
            print("FAILED: Alice should broadcast initial SOS packet")
            return false
        }
        
        // Step 2: Bob (Local Relay) receives Alice's packet (hopCount = 0)
        let rawAtBob = try! RawWirePacket.fromWireData(alicePacket)
        guard rawAtBob.envelope.hopCount == 0 else {
            print("FAILED: Alice's initial packet must have hopCount = 0")
            return false
        }
        guard rawAtBob.envelope.hopLimit == PacketConstants.sosHopLimit else {
            print("FAILED: Alice's initial SOS packet must carry hopLimit \(PacketConstants.sosHopLimit), got \(rawAtBob.envelope.hopLimit)")
            return false
        }
        
        await vmB.processInboundPacket(InboundPacket(rawPacket: rawAtBob, sourcePeerId: "Alice"))
        
        // Verify Bob (Relay) displayed the SOS signal locally
        guard vmB.activeIncomingAlert?.emergencyType == .medical else {
            print("FAILED: Bob (Local Relay) must display activeIncomingAlert with .medical")
            return false
        }
        guard vmB.activeIncomingAlert?.senderName == "Alice" else {
            print("FAILED: Bob's alert should resolve sender name to Alice (got: \(String(describing: vmB.activeIncomingAlert?.senderName)))")
            return false
        }
        guard mockAlerterB.triggerCount == 1 else {
            print("FAILED: Bob's siren should trigger on emergency arrival")
            return false
        }
        
        // Step 3: Bob forwards packet as mesh relay (hopCount incremented to 1)
        guard rawAtBob.envelope.hopCount < rawAtBob.envelope.hopLimit else {
            print("FAILED: hopCount must be less than hopLimit for relaying")
            return false
        }
        
        var relayedEnv = rawAtBob.envelope
        relayedEnv.hopCount &+= 1
        let relayedWire = RawWirePacket(
            envelope: relayedEnv,
            ciphertext: rawAtBob.ciphertext,
            authTag: rawAtBob.authTag
        )
        let relayedData = try! relayedWire.toWireData()
        
        // Step 4: Charlie (Downstream Friend) receives relayed packet (hopCount = 1)
        let rawAtCharlie = try! RawWirePacket.fromWireData(relayedData)
        guard rawAtCharlie.envelope.hopCount == 1 else {
            print("FAILED: Relayed packet at Charlie must have hopCount = 1")
            return false
        }
        
        await vmC.processInboundPacket(InboundPacket(rawPacket: rawAtCharlie, sourcePeerId: "Bob"))
        
        // Verify Charlie received, authenticated, and displayed Alice's emergency
        guard vmC.activeIncomingAlert?.emergencyType == .medical else {
            print("FAILED: Charlie must display activeIncomingAlert with .medical via relay")
            return false
        }
        guard vmC.activeIncomingAlert?.senderName == "Alice" else {
            print("FAILED: Charlie must resolve sender name to Alice")
            return false
        }
        guard mockAlerterC.triggerCount == 1 else {
            print("FAILED: Charlie's siren must trigger when receiving relayed SOS")
            return false
        }
        
        // Step 5: Verify Charlie emitted delivery ACK with hopCount = 1
        let charliePackets = await transportC.broadcastPackets
        guard let charlieAckData = charliePackets.first else {
            print("FAILED: Charlie should emit delivery ACK")
            return false
        }
        
        let charlieRawAck = try! RawWirePacket.fromWireData(charlieAckData)
        guard charlieRawAck.envelope.type == .ack else {
            print("FAILED: Charlie's emitted packet must be an ACK")
            return false
        }
        guard charlieRawAck.envelope.hopLimit == PacketConstants.sosHopLimit else {
            print("FAILED: Charlie's emitted ACK must carry hopLimit \(PacketConstants.sosHopLimit), got \(charlieRawAck.envelope.hopLimit)")
            return false
        }
        
        // Step 6: Relay ACK back to Alice through Bob
        await vmA.processInboundPacket(InboundPacket(rawPacket: charlieRawAck, sourcePeerId: "Bob"))
        
        guard case let .deliveredToFriend(friendId, _) = vmA.deliveryState, friendId == "CHL" else {
            print("FAILED: Alice must receive confirmed delivery from Charlie")
            return false
        }
        
        // Step 7: Duplicate suppression on Bob (Relay)
        await vmB.processInboundPacket(InboundPacket(rawPacket: rawAtBob, sourcePeerId: "Alice"))
        guard mockAlerterB.triggerCount == 1 else {
            print("FAILED: Bob must not re-trigger siren on duplicate SOS arrival")
            return false
        }
        guard vmB.totalDuplicatesSuppressedCount == 1 else {
            print("FAILED: Bob must increment duplicates suppressed count")
            return false
        }
        
        print("PASSED: testMultiHopRelaySOSForwarding")
        return true
    }
}
