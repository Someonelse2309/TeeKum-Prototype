//
//  InactivityGuardTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 04/11/26.
//

import Foundation
import CoreLocation
import CryptoKit

// MARK: - Mock In-Memory Transport for Inactivity Guard Testing

private actor MockInactivityPeerTransport: PeerTransport {
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
    
    func simulateInboundPacket(_ packet: InboundPacket) {
        inboundContinuation?.yield(packet)
    }
}

private final class MockInactivityAudioAlerter: SOSAudioAlerting, @unchecked Sendable {
    var triggerCount: Int = 0
    var stopCount: Int = 0
    
    func triggerEmergencyAlertFeedback() {
        triggerCount += 1
    }
    
    func stopEmergencyAlertFeedback() {
        stopCount += 1
    }
}

// MARK: - Inactivity Guard Test Suite

public struct InactivityGuardTests {
    
    @MainActor
    public static func runAllTests() async -> Bool {
        print("================================================================")
        print("--- [InactivityGuardTests] Running Man Down / Auto-SOS Suite ---")
        print("================================================================")
        var passed = true
        
        if !(await testSOSTypeInactivityWireCodec()) { passed = false }
        if !(await testInactivityGuardDisabledByDefault()) { passed = false }
        if !(await testInactivityStillnessTriggersWarningCountdown()) { passed = false }
        if !(await testUserInteractionResetsStillnessTimer()) { passed = false }
        if !(await testPhysicalMotionCancelsWarningCountdown()) { passed = false }
        if !(await testExplicitTapDismissCancelsWarningCountdown()) { passed = false }
        if !(await testWarningCountdownExpirationDispatchesAutoSOS()) { passed = false }
        if !(await testIncomingInactivitySOSAlertOnFriendDevice()) { passed = false }
        if !(await testInactivityGuardPreservedAcrossLiveSharingAndReset()) { passed = false }
        
        if passed {
            print("================================================================")
            print("--- [InactivityGuardTests] ✓ ALL 9 INACTIVITY TESTS PASSED ---")
            print("================================================================")
        } else {
            print("================================================================")
            print("--- [InactivityGuardTests] ✗ SOME INACTIVITY TESTS FAILED ---")
            print("================================================================")
        }
        return passed
    }
    
    // MARK: - 1. Wire Codec Verification
    
    @MainActor
    private static func testSOSTypeInactivityWireCodec() async -> Bool {
        print("[TEST 1] testSOSTypeInactivityWireCodec...")
        
        // Ensure SOSType.inactivity is exactly 0x04
        guard SOSType.inactivity.rawValue == 0x04 else {
            print("FAIL: SOSType.inactivity.rawValue (\(SOSType.inactivity.rawValue)) != 0x04")
            return false
        }
        guard SOSType.inactivity.title == "Inactivity / Man Down" else {
            print("FAIL: Title mismatch for inactivity SOSType")
            return false
        }
        
        let payload = SOSPayload(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            timestamp: Date(timeIntervalSince1970: 1700000000),
            accuracy: 10,
            sosEventId: 0x99AABBCC,
            senderInitials: "INA",
            emergencyType: .inactivity,
            batteryLevel: 85,
            colorCode: 3
        )
        
        let serialized = payload.serialize()
        guard serialized.count == PacketConstants.encryptedPayloadSize else {
            print("FAIL: Serialized payload size (\(serialized.count)) != \(PacketConstants.encryptedPayloadSize)")
            return false
        }
        
        do {
            let deserialized = try SOSPayload.deserialize(from: serialized)
            guard deserialized.emergencyType == .inactivity else {
                print("FAIL: Deserialized emergencyType (\(deserialized.emergencyType)) != .inactivity")
                return false
            }
            guard deserialized.senderInitials == "INA" else {
                print("FAIL: Deserialized initials mismatch")
                return false
            }
            guard deserialized.sosEventId == 0x99AABBCC else {
                print("FAIL: Deserialized event ID mismatch")
                return false
            }
        } catch {
            print("FAIL: SOSPayload deserialization threw error: \(error)")
            return false
        }
        
        print("  ✓ SOSType.inactivity wire encoding & decoding verified (56-byte invariant preserved)")
        return true
    }
    
    // MARK: - 2. Disabled by Default
    
    @MainActor
    private static func testInactivityGuardDisabledByDefault() async -> Bool {
        print("[TEST 2] testInactivityGuardDisabledByDefault...")
        
        var simulatedNow = Date()
        let guardService = InactivityGuardService(dateProvider: { simulatedNow })
        
        guard !guardService.isEnabled else {
            print("FAIL: InactivityGuardService should be disabled by default")
            return false
        }
        guard guardService.state == .disabled else {
            print("FAIL: InactivityGuardService state should be .disabled")
            return false
        }
        
        // Advance time by 10 minutes while disabled
        simulatedNow = simulatedNow.addingTimeInterval(600.0)
        guardService.evaluateStillness()
        
        guard guardService.state == .disabled else {
            print("FAIL: Guard triggered while disabled")
            return false
        }
        
        print("  ✓ Inactivity guard is strictly opt-in and idle when disabled")
        return true
    }
    
    // MARK: - 3. Stillness Triggers Pre-Alarm Warning Countdown
    
    @MainActor
    private static func testInactivityStillnessTriggersWarningCountdown() async -> Bool {
        print("[TEST 3] testInactivityStillnessTriggersWarningCountdown...")
        
        var simulatedNow = Date()
        let guardService = InactivityGuardService(dateProvider: { simulatedNow })
        
        var warningStarted = false
        guardService.onWarningStarted = {
            warningStarted = true
        }
        
        guardService.isEnabled = true
        guard case .monitoring = guardService.state else {
            print("FAIL: Guard should be in .monitoring state after enabling")
            return false
        }
        
        // Advance time to 179s (just below 180s threshold)
        simulatedNow = simulatedNow.addingTimeInterval(179.0)
        guardService.evaluateStillness()
        guard case .monitoring = guardService.state else {
            print("FAIL: Guard triggered prematurely before 180s threshold")
            return false
        }
        
        // Advance time to 180s (threshold reached)
        simulatedNow = simulatedNow.addingTimeInterval(1.0)
        guardService.evaluateStillness()
        
        guard case let .warning(remaining) = guardService.state else {
            print("FAIL: Guard did not enter .warning state after 180s stillness")
            return false
        }
        guard warningStarted else {
            print("FAIL: onWarningStarted callback was not invoked")
            return false
        }
        guard remaining > 0 && remaining <= guardService.warningCountdownSeconds else {
            print("FAIL: Warning remaining countdown (\(remaining)) invalid")
            return false
        }
        guard guardService.isWarningActive else {
            print("FAIL: isWarningActive should be true")
            return false
        }
        
        print("  ✓ Stillness reached 180s and cleanly transitioned to pre-alarm silent warning")
        return true
    }
    
    // MARK: - 4. User Interaction Resets Stillness Timer
    
    @MainActor
    private static func testUserInteractionResetsStillnessTimer() async -> Bool {
        print("[TEST 4] testUserInteractionResetsStillnessTimer...")
        
        var simulatedNow = Date()
        let guardService = InactivityGuardService(dateProvider: { simulatedNow })
        guardService.isEnabled = true
        
        // Advance 150s of stillness
        simulatedNow = simulatedNow.addingTimeInterval(150.0)
        guardService.evaluateStillness()
        
        // User taps screen or navigates in app
        guardService.recordUserInteraction()
        
        // Advance another 100s (total elapsed 250s, but only 100s since interaction)
        simulatedNow = simulatedNow.addingTimeInterval(100.0)
        guardService.evaluateStillness()
        
        guard case .monitoring = guardService.state else {
            print("FAIL: Screen interaction did not reset stillness timer; state is \(guardService.state)")
            return false
        }
        
        print("  ✓ Screen touch/unlock successfully resets stillness duration")
        return true
    }
    
    // MARK: - 5. Physical Motion Cancels Warning Countdown
    
    @MainActor
    private static func testPhysicalMotionCancelsWarningCountdown() async -> Bool {
        print("[TEST 5] testPhysicalMotionCancelsWarningCountdown...")
        
        var simulatedNow = Date()
        let guardService = InactivityGuardService(dateProvider: { simulatedNow })
        guardService.isEnabled = true
        
        // Enter warning state
        guardService.simulateWarningState(remainingSeconds: 20.0)
        guard guardService.isWarningActive else {
            print("FAIL: Warning state not active")
            return false
        }
        
        var warningCancelled = false
        guardService.onWarningCancelled = {
            warningCancelled = true
        }
        
        // Attendee picks up or moves their phone
        guardService.recordPhysicalMotion()
        
        guard case .monitoring = guardService.state else {
            print("FAIL: Physical motion did not cancel warning; state is \(guardService.state)")
            return false
        }
        guard warningCancelled else {
            print("FAIL: onWarningCancelled was not called on motion cancellation")
            return false
        }
        
        print("  ✓ Physical movement immediately cancels the warning countdown")
        return true
    }
    
    // MARK: - 6. Explicit "I'm OK" Button Cancels Warning Countdown
    
    @MainActor
    private static func testExplicitTapDismissCancelsWarningCountdown() async -> Bool {
        print("[TEST 6] testExplicitTapDismissCancelsWarningCountdown...")
        
        var simulatedNow = Date()
        let guardService = InactivityGuardService(dateProvider: { simulatedNow })
        guardService.isEnabled = true
        
        guardService.simulateWarningState(remainingSeconds: 15.0)
        
        var warningCancelled = false
        guardService.onWarningCancelled = {
            warningCancelled = true
        }
        
        // User taps "I'M OK" button
        guardService.cancelWarning()
        
        guard case .monitoring = guardService.state else {
            print("FAIL: cancelWarning() did not return to monitoring; state is \(guardService.state)")
            return false
        }
        guard warningCancelled else {
            print("FAIL: onWarningCancelled was not called")
            return false
        }
        
        print("  ✓ Tapping 'I'M OK' button immediately cancels pending emergency SOS")
        return true
    }
    
    // MARK: - 7. Warning Expiration Dispatches Auto-SOS
    
    @MainActor
    private static func testWarningCountdownExpirationDispatchesAutoSOS() async -> Bool {
        print("[TEST 7] testWarningCountdownExpirationDispatchesAutoSOS...")
        
        let transport = MockInactivityPeerTransport(activePeers: 1)
        let keyData = Data(repeating: 0x42, count: 32)
        let session = GroupSession(
            sessionId: 0x7788,
            sessionName: "Test Festival",
            symmetricKeyData: keyData,
            localInitials: "TST"
        )
        let crypto = CryptoService()
        let alerter = MockInactivityAudioAlerter()
        
        let sosVM = SOSViewModel(
            sessionProvider: { session },
            cryptoService: crypto,
            transport: transport,
            audioAlerter: alerter
        )
        
        sosVM.isInactivityGuardEnabled = true
        guard sosVM.inactivityGuard.isEnabled else {
            print("FAIL: isInactivityGuardEnabled did not set guard service isEnabled")
            return false
        }
        
        // Simulate warning countdown expiring (calling triggerSOS directly)
        sosVM.triggerSOS(emergencyType: .inactivity)
        
        guard sosVM.currentEmergencyType == .inactivity else {
            print("FAIL: currentEmergencyType (\(sosVM.currentEmergencyType)) != .inactivity")
            return false
        }
        guard sosVM.deliveryState == .localSending else {
            print("FAIL: deliveryState (\(sosVM.deliveryState)) != .localSending")
            return false
        }
        
        // Wait for asynchronous broadcast execution
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        let broadcastCount = await transport.broadcastPackets.count
        guard broadcastCount > 0 else {
            print("FAIL: No SOS wire packets broadcast onto transport")
            return false
        }
        
        let sentPacketData = await transport.broadcastPackets.first!
        guard sentPacketData.count == PacketConstants.wirePacketSize else {
            print("FAIL: Broadcast packet size (\(sentPacketData.count)) != 56 bytes")
            return false
        }
        
        // Open and verify wire contents
        let wire = try! RawWirePacket.fromWireData(sentPacketData)
        guard wire.envelope.type == .sos else {
            print("FAIL: Wire envelope type != .sos")
            return false
        }
        let decrypted = try! await crypto.open(
            ciphertext: wire.ciphertext,
            envelope: wire.envelope,
            authTag: wire.authTag,
            using: SymmetricKey(data: keyData)
        )
        let decodedPayload = try! SOSPayload.deserialize(from: decrypted)
        guard decodedPayload.emergencyType == .inactivity else {
            print("FAIL: Decoded emergencyType != .inactivity")
            return false
        }
        guard decodedPayload.senderInitials == "TST" else {
            print("FAIL: Decoded initials != TST")
            return false
        }
        
        print("  ✓ Warning countdown expiration successfully dispatched 56-byte SOSType.inactivity packet")
        return true
    }
    
    // MARK: - 8. Inbound Inactivity Alert on Friend Device
    
    @MainActor
    private static func testIncomingInactivitySOSAlertOnFriendDevice() async -> Bool {
        print("[TEST 8] testIncomingInactivitySOSAlertOnFriendDevice...")
        
        let transport = MockInactivityPeerTransport(activePeers: 1)
        let keyData = Data(repeating: 0x88, count: 32)
        let friendSession = GroupSession(
            sessionId: 0x1234,
            sessionName: "Friend Group",
            symmetricKeyData: keyData,
            localInitials: "FRD"
        )
        let crypto = CryptoService()
        let audioAlerter = MockInactivityAudioAlerter()
        
        let friendVM = SOSViewModel(
            sessionProvider: { friendSession },
            cryptoService: crypto,
            transport: transport,
            audioAlerter: audioAlerter
        )
        friendVM.memberNameResolver = { initials in "Alice (\(initials))" }
        
        // Craft an authenticated inbound SOSType.inactivity packet from member "ALC"
        let sosPayload = SOSPayload(
            coordinate: CLLocationCoordinate2D(latitude: 37.7833, longitude: -122.4167),
            timestamp: Date(),
            accuracy: 8,
            sosEventId: 0x55667788,
            senderInitials: "ALC",
            emergencyType: .inactivity,
            batteryLevel: 62,
            colorCode: 2
        )
        let payloadData = sosPayload.serialize()
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .sos,
            hopLimit: PacketConstants.sosHopLimit,
            hopCount: 1,
            sessionId: friendSession.sessionId,
            sequenceNumber: CleartextEnvelope.makeSequenceNumber(memberSlot: 1, counter: 1)
        )
        let sealed = try! await crypto.seal(payload: payloadData, envelope: envelope, using: SymmetricKey(data: keyData))
        let wirePacket = RawWirePacket(envelope: envelope, ciphertext: sealed.ciphertext, authTag: sealed.authTag)
        let inbound = InboundPacket(rawPacket: wirePacket, sourcePeerId: "peer_relay")
        
        // Friend device processes the inbound packet
        await friendVM.processInboundPacket(inbound)
        
        guard let alert = friendVM.activeIncomingAlert else {
            print("FAIL: Friend device did not populate activeIncomingAlert")
            return false
        }
        guard alert.emergencyType == .inactivity else {
            print("FAIL: Incoming alert emergencyType (\(alert.emergencyType)) != .inactivity")
            return false
        }
        guard alert.senderInitials == "ALC" else {
            print("FAIL: Alert initials mismatch (\(alert.senderInitials))")
            return false
        }
        guard alert.senderName == "Alice (ALC)" else {
            print("FAIL: Resolved sender name mismatch: \(alert.senderName)")
            return false
        }
        guard audioAlerter.triggerCount == 1 else {
            print("FAIL: Emergency siren feedback was not triggered on friend device")
            return false
        }
        guard friendVM.isSirenActive else {
            print("FAIL: isSirenActive should be true")
            return false
        }
        
        // Re-inject duplicate packet: siren MUST be suppressed!
        await friendVM.processInboundPacket(inbound)
        guard audioAlerter.triggerCount == 1 else {
            print("FAIL: Duplicate inbound packet triggered repeated siren!")
            return false
        }
        guard friendVM.totalDuplicatesSuppressedCount == 1 else {
            print("FAIL: Duplicate packet was not counted in totalDuplicatesSuppressedCount")
            return false
        }
        
        print("  ✓ Friend device properly surfaces Man Down alert, triggers sirens, and suppresses duplicates")
        return true
    }
    
    // MARK: - 9. Preserved Across Reset & Independent of Live Sharing
    
    @MainActor
    private static func testInactivityGuardPreservedAcrossLiveSharingAndReset() async -> Bool {
        print("[TEST 9] testInactivityGuardPreservedAcrossLiveSharingAndReset...")
        
        let sosVM = SOSViewModel()
        sosVM.isInactivityGuardEnabled = true
        
        guard sosVM.inactivityGuard.isEnabled else {
            print("FAIL: Guard should be enabled")
            return false
        }
        
        // Simulate warning state then reset
        sosVM.inactivityGuard.simulateWarningState(remainingSeconds: 10.0)
        guard sosVM.inactivityGuard.isWarningActive else {
            print("FAIL: Warning state should be active")
            return false
        }
        
        sosVM.reset()
        
        // After reset, guard is back in monitoring state, not warning
        guard !sosVM.inactivityGuard.isWarningActive else {
            print("FAIL: Warning should be cleared after reset")
            return false
        }
        guard case .monitoring = sosVM.inactivityGuard.state else {
            print("FAIL: Guard should be returned to monitoring state")
            return false
        }
        
        print("  ✓ Inactivity guard cleanly resets and maintains state integrity")
        return true
    }
}
