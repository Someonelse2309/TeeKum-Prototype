//
//  ChatMessagingEngineTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import Foundation
import CryptoKit

/// Authoritative Unit & Integration Test Suite for Agent 2 (Chat Messaging & Mesh Integration Engineer).
///
/// Master Specification Test Matrix:
/// 1. Message validation and UTF-8 byte boundary enforcement (1..20 bytes, rejecting empty & >20 bytes).
/// 2. 56-byte wire encoding and ChaCha20-Poly1305 AEAD authenticated encryption roundtrip.
/// 3. Direct peer message delivery and mutual delivery ACK exchange.
/// 4. Multi-hop mesh delivery over linear relay chain (Alice -> Relay R -> Bob).
/// 5. Privacy invariant: Relays forward opaque encrypted packets without decrypting or displaying.
/// 6. Deduplication: Duplicate packet reception suppresses repeated display, sirens, and mesh circulation.
/// 7. Outbox FIFO queueing: Chat operates in dedicated Tier 3 FIFO lane, preempting stranger relays and routine pings.
/// 8. Bounded retries: Maximum 2 retries (3 attempts total) with backoff using deterministic test clock.
/// 9. Client-side cooldown: 3.0-second cooldown enforced between messages using test clock.
/// 10. Multi-recipient tracking: Delivery state tracked separately for each intended recipient.
/// 11. Honest UX invariant: Never treats an intermediary relay ACK as final recipient delivery.
/// 12. Delivery timeout: Unconfirmed recipients transition to deliveryTimedOut after 15-second window.
/// 13. Ephemeral history: In-memory only (max 50 messages ring buffer), zero disk writes, purged on session teardown.
/// 14. Battery guard: Chat disabled at <20% battery or Low Power Mode, while Emergency SOS remains 100% active.
/// 15. Priority invariant: Emergency SOS strictly preempts chat messages, preserving rate limit budgets.
public enum ChatMessagingEngineTests {
    
    // MARK: - Test Mock Transport
    
    actor TestChatMockTransport: MeshTransport, PeerTransport {
        var broadcastedFrames: [Data] = []
        var sentFrames: [(data: Data, peerId: String)] = []
        var forwardedFrames: [(data: Data, nextHop: String)] = []
        var neighbors: [NeighborInfo] = []
        var relayPermitted: Bool = true
        
        let inboundFrames: AsyncStream<InboundFrame>
        let sendOutcomes: AsyncStream<SendOutcome>
        let neighborEvents: AsyncStream<NeighborEvent>
        let transportErrors: AsyncStream<TransportError>
        
        // PeerTransport requirements
        let inboundPackets: AsyncStream<InboundPacket>
        let peerUpdates: AsyncStream<[PeerInfo]>
        let stateUpdates: AsyncStream<TransportState>
        
        init(neighbors: [NeighborInfo] = []) {
            self.neighbors = neighbors
            self.inboundFrames = AsyncStream { _ in }
            self.sendOutcomes = AsyncStream { _ in }
            self.neighborEvents = AsyncStream { _ in }
            self.transportErrors = AsyncStream { _ in }
            self.inboundPackets = AsyncStream { _ in }
            self.peerUpdates = AsyncStream { _ in }
            self.stateUpdates = AsyncStream { _ in }
        }
        
        func start(serviceType: String, session: GroupSession) async throws {}
        func stop() async {}
        
        func sendFrame(_ data: Data, to peerId: String) async throws -> SendOutcome {
            sentFrames.append((data, peerId))
            return SendOutcome(destinationPeerId: peerId, packetType: .chatMessage, isSuccess: true)
        }
        
        func broadcastFrame(_ data: Data) async throws {
            broadcastedFrames.append(data)
        }
        
        func broadcastPacket(_ data: Data) async throws {
            broadcastedFrames.append(data)
        }
        
        func sendPacket(_ data: Data, to peerId: String) async throws {
            sentFrames.append((data, peerId))
        }
        
        func activeDirectPeerCount() async -> Int {
            neighbors.count
        }
        
        func getDiagnostics() async -> TransportDiagnostics {
            TransportDiagnostics(
                localPeerId: "test",
                serviceType: "_teekum._tcp",
                sessionName: "Test",
                sessionId: 0x1234,
                state: .connected(peerCount: neighbors.count),
                activeDirectPeers: [],
                packetsSent: sentFrames.count,
                packetsReceived: 0,
                obsoletePingsCoalesced: 0,
                sendErrors: 0,
                lastError: nil,
                recentEvents: []
            )
        }
        
        func forwardFrame(_ data: Data, to nextHopPeerId: String) async throws -> SendOutcome {
            forwardedFrames.append((data, nextHopPeerId))
            return SendOutcome(destinationPeerId: nextHopPeerId, packetType: .chatMessage, isSuccess: true)
        }
        
        func activeNeighbors() async -> [NeighborInfo] {
            neighbors
        }
        
        func setNeighbors(_ list: [NeighborInfo]) {
            self.neighbors = list
        }
        
        func queueDepth() async -> QueueDepth {
            QueueDepth()
        }
        
        func setRelayParticipation(enabled: Bool) async {
            self.relayPermitted = enabled
        }
        
        func isRelayPermitted() async -> Bool {
            relayPermitted
        }
        
        func lastBroadcastData(ofType type: PacketType? = nil) -> Data? {
            guard let type = type else { return broadcastedFrames.last }
            return broadcastedFrames.reversed().first { frame in
                guard frame.count >= 1 else { return false }
                let t = PacketType(rawValue: frame[frame.startIndex] & 0x0F)
                return t == type
            }
        }
        
        func lastSentData() -> Data? {
            sentFrames.last?.data
        }
        
        func broadcastCount() -> Int {
            broadcastedFrames.count
        }
        
        func clearHistory() {
            broadcastedFrames.removeAll()
            sentFrames.removeAll()
            forwardedFrames.removeAll()
        }
    }
    
    public static func runAllTests() async -> Bool {
        print("\n================================================================")
        print(">>> STARTING PHASE 3 CHAT MESSAGING & MESH INTEGRATION TESTS <<<")
        print("================================================================")
        fflush(stdout)
        
        var passed = CarryMessageStoreTests.runAllTests()
        passed = await testCarryAcrossDisconnectedEncounters() && passed
        
        passed = await testMessageValidationAndByteBoundaryEnforcement() && passed
        fflush(stdout)
        passed = await testEncryptionAndWireEncoding56Bytes() && passed
        fflush(stdout)
        passed = await testDirectPeerDeliveryAndACKExchange() && passed
        fflush(stdout)
        passed = await testMultiHopMeshDeliveryLinearChain() && passed
        fflush(stdout)
        passed = await testRelaysDoNotDecryptOrDisplayMessages() && passed
        fflush(stdout)
        passed = await testDuplicateMessageSuppression() && passed
        passed = await testCrossGroupEdgeLinkRecovery() && passed
        passed = await testConfiguredRelayBudgetAndTelemetryReservation() && passed
        fflush(stdout)
        passed = await testFIFOOutboxLanePrecedenceAndBounds() && passed
        fflush(stdout)
        passed = await testMaximumTwoRetriesAndRetryBackoff() && passed
        fflush(stdout)
        passed = await testThreeSecondCooldownWithTestClock() && passed
        fflush(stdout)
        passed = await testPerRecipientACKAndDeliveryTracking() && passed
        fflush(stdout)
        passed = await testRelayACKNeverTreatedAsFinalDelivery() && passed
        fflush(stdout)
        passed = await testDeliveryTimeoutWindow() && passed
        fflush(stdout)
        passed = await testEphemeralInMemoryHistoryAndTeardownPurge() && passed
        fflush(stdout)
        passed = await testBatteryCutoffDisablesChatWithoutDisablingSOS() && passed
        fflush(stdout)
        passed = await testPreserveSOSPriorityAndRateLimits() && passed
        fflush(stdout)
        passed = await testDirectOneOnOneInitialsCollisionNotDropped() && passed
        fflush(stdout)
        
        if passed {
            print("================================================================")
            print(">>> ALL CHAT MESSAGING & MESH INTEGRATION TESTS PASSED <<<")
            print("================================================================\n")
        } else {
            print("❌ SOME CHAT MESSAGING & MESH INTEGRATION TESTS FAILED!\n")
        }
        fflush(stdout)
        
        return passed
    }
    
    /// Exercises real encryption/ingestion and late ACK handling across disconnected encounters.
    public static func testCarryAcrossDisconnectedEncounters() async -> Bool {
        let clock = TestMeshClock()
        let key = Data(repeating: 0x45, count: 32)
        let a = GroupSession(sessionId: 123, sessionName: "Carry", symmetricKeyData: key, localInitials: "ALI")
        let b = GroupSession(sessionId: 123, sessionName: "Carry", symmetricKeyData: key, localInitials: "BOB")
        let c = GroupSession(sessionId: 123, sessionName: "Carry", symmetricKeyData: key, localInitials: "CAR")
        let ta = TestChatMockTransport(), tb = TestChatMockTransport(), tc = TestChatMockTransport()
        let ea = ChatMessageEngine(transport: ta, cryptoService: CryptoService(), clock: clock, sessionProvider: { a })
        let eb = ChatMessageEngine(transport: tb, cryptoService: CryptoService(), clock: clock, sessionProvider: { b })
        let ec = ChatMessageEngine(transport: tc, cryptoService: CryptoService(), clock: clock, sessionProvider: { c })
        do {
            let sent = try await ea.sendMessage(text: "Meet at gate", targetRecipients: ["CAR"])
            guard let wire = await ta.lastBroadcastData(ofType: .chatMessage) else { return false }
            _ = try await eb.handleInboundWirePacket(wire, fromPeerId: "ALI")
            guard let forwarded = await tb.lastBroadcastData(ofType: .chatMessage) else { return false }
            var custody = CarryMessageStore()
            custody.remember(forwarded, isForeign: false, now: clock.now())
            clock.advance(by: 180)
            await ea.evaluateTimeoutsAndRetries()
            guard let later = custody.nextTransmission(to: ["CAR"], now: clock.now()) else { return false }
            // The last permitted hop must still deliver locally. Tampering must not poison dedup.
            var finalHop = later.data
            finalHop[2] = finalHop[1]
            var tampered = finalHop
            tampered[12] ^= 1
            _ = try await ec.handleInboundWirePacket(tampered, fromPeerId: "BOB")
            let received = try await ec.handleInboundWirePacket(finalHop, fromPeerId: "BOB")
            guard received.deliveredMessage?.text == "Meet at gate" else { return false }
            _ = try await ec.handleInboundWirePacket(finalHop, fromPeerId: "BOB")
            guard await ec.activeMessages().count == 1,
                  let ack = await tc.lastBroadcastData(ofType: .ack) else { return false }
            var reverseCustody = CarryMessageStore()
            reverseCustody.remember(ack, isForeign: false, now: clock.now())
            clock.advance(by: 120)
            guard let returnTrip = reverseCustody.nextTransmission(to: ["ALI"], now: clock.now()) else { return false }
            let processed = await ea.processDeliveryACK(rawPacket: try RawWirePacket.fromWireData(returnTrip.data), fromPeerId: "BOB")
            guard processed, await ea.message(withSequenceNumber: sent.sequenceNumber)?.confirmedResponders.contains("CAR") == true else { return false }
            print("Carry integration passed: A → B, delayed B → C, final hop, tamper rejection, duplicate suppression, late ACK")
            return true
        } catch {
            print("Carry integration failed: \(error)")
            return false
        }
    }

    // MARK: - Test 1: Message Validation & UTF-8 Byte Boundaries
    
    public static func testMessageValidationAndByteBoundaryEnforcement() async -> Bool {
        print("[Test 1] Message validation and 1..20 UTF-8 byte boundary enforcement...")
        let clock = TestMeshClock()
        let transport = TestChatMockTransport()
        let crypto = CryptoService()
        let dummyKey = Data(repeating: 0x42, count: 32)
        let session = GroupSession(sessionId: 0x1111, sessionName: "Crew", symmetricKeyData: dummyKey, localInitials: "ALI")
        
        let engine = ChatMessageEngine(
            transport: transport,
            cryptoService: crypto,
            clock: clock,
            sessionProvider: { session }
        )
        
        // 1. Empty text must be rejected
        do {
            _ = try await engine.sendMessage(text: "")
            print("  FAIL: Empty text was not rejected.")
            return false
        } catch let ChatEngineError.invalidTextLength(len) {
            guard len == 0 else {
                print("  FAIL: Expected 0 bytes length error.")
                return false
            }
        } catch {
            print("  FAIL: Unexpected error for empty text: \(error)")
            return false
        }
        
        // 2. Oversized text (>20 bytes) must be rejected
        do {
            _ = try await engine.sendMessage(text: "This string is way too long for twenty bytes")
            print("  FAIL: Oversized text was not rejected.")
            return false
        } catch let ChatEngineError.invalidTextLength(len) {
            guard len > 20 else {
                print("  FAIL: Expected >20 bytes length error.")
                return false
            }
        } catch {
            print("  FAIL: Unexpected error for oversized text: \(error)")
            return false
        }
        
        // 3. Valid ASCII text (exactly 20 bytes) must succeed
        clock.advance(by: 3.5)
        do {
            let msg = try await engine.sendMessage(text: "12345678901234567890")
            guard msg.text == "12345678901234567890" else {
                print("  FAIL: Text mismatch for 20-byte ASCII.")
                return false
            }
        } catch {
            print("  FAIL: Valid 20-byte text threw error: \(error)")
            return false
        }
        
        // 4. Standard festival preset chips must all succeed
        for preset in ChatMessagePayload.standardPresets {
            clock.advance(by: 3.5)
            do {
                let msg = try await engine.sendMessage(text: preset)
                guard msg.text == preset else {
                    print("  FAIL: Preset text mismatch for '\(preset)'.")
                    return false
                }
            } catch {
                print("  FAIL: Preset '\(preset)' threw error: \(error)")
                return false
            }
        }
        
        print("  PASS: Message validation and UTF-8 byte boundary enforcement verified.")
        return true
    }
    
    // MARK: - Test 2: Encryption & 56-Byte Wire Datagram
    
    public static func testEncryptionAndWireEncoding56Bytes() async -> Bool {
        print("[Test 2] 56-byte wire datagram and ChaCha20-Poly1305 sealing...")
        let clock = TestMeshClock()
        let transport = TestChatMockTransport()
        let crypto = CryptoService()
        let dummyKey = Data(repeating: 0x77, count: 32)
        let session = GroupSession(sessionId: 0x2222, sessionName: "Rave", symmetricKeyData: dummyKey, localInitials: "ALI")
        
        let engine = ChatMessageEngine(
            transport: transport,
            cryptoService: crypto,
            clock: clock,
            sessionProvider: { session }
        )
        
        do {
            _ = try await engine.sendMessage(text: "Beer line")
            guard let wireData = await transport.lastBroadcastData() else {
                print("  FAIL: No frame found in transport broadcast buffer.")
                return false
            }
            
            // Wire datagram size invariant: exactly 56 bytes
            guard wireData.count == PacketConstants.wirePacketSize else {
                print("  FAIL: Packet size is \(wireData.count), expected 56 bytes.")
                return false
            }
            
            // Envelope Byte 0: version 3 (0x3) | type 7 (0x07) = 0x37
            guard wireData[0] == 0x37 else {
                print("  FAIL: Byte 0 is 0x\(String(format: "%02X", wireData[0])), expected 0x37.")
                return false
            }
            
            // Envelope Byte 1: hopLimit = chatHopLimit (default: 8)
            guard wireData[1] == PacketConstants.chatHopLimit else {
                print("  FAIL: HopLimit is \(wireData[1]), expected \(PacketConstants.chatHopLimit).")
                return false
            }
            
            // Envelope Byte 2: hopCount = 0
            guard wireData[2] == 0 else {
                print("  FAIL: HopCount is \(wireData[2]), expected 0.")
                return false
            }
            
            // Verify recipient can authenticate and decrypt with session symmetric key
            let rawPacket = try RawWirePacket.fromWireData(wireData)
            let decrypted = try await crypto.open(
                ciphertext: rawPacket.ciphertext,
                envelope: rawPacket.envelope,
                authTag: rawPacket.authTag,
                using: SymmetricKey(data: dummyKey)
            )
            
            let payload = try ChatMessagePayload.deserialize(from: decrypted)
            guard payload.senderInitials == "ALI", payload.text == "Beer line" else {
                print("  FAIL: Decrypted payload content mismatch.")
                return false
            }
        } catch {
            print("  FAIL: Sealing or wire encoding failed: \(error)")
            return false
        }
        
        print("  PASS: 56-byte wire datagram and ChaCha20-Poly1305 encryption verified.")
        return true
    }
    
    // MARK: - Test 3: Direct Peer Delivery & Mutual ACK Exchange
    
    public static func testDirectPeerDeliveryAndACKExchange() async -> Bool {
        print("[Test 3] Direct peer delivery and mutual delivery ACK exchange...")
        let clock = TestMeshClock()
        let dummyKey = Data(repeating: 0x99, count: 32)
        let sessionAlice = GroupSession(sessionId: 0x3333, sessionName: "Duo", symmetricKeyData: dummyKey, localInitials: "ALI")
        let sessionBob = GroupSession(sessionId: 0x3333, sessionName: "Duo", symmetricKeyData: dummyKey, localInitials: "BOB")
        
        let tAlice = TestChatMockTransport()
        let tBob = TestChatMockTransport()
        
        let cryptoAlice = CryptoService()
        let cryptoBob = CryptoService()
        
        let engineAlice = ChatMessageEngine(
            transport: tAlice,
            cryptoService: cryptoAlice,
            clock: clock,
            sessionProvider: { sessionAlice },
            recipientsProvider: { ["BOB"] }
        )
        
        let engineBob = ChatMessageEngine(
            transport: tBob,
            cryptoService: cryptoBob,
            clock: clock,
            sessionProvider: { sessionBob },
            recipientsProvider: { ["ALI"] }
        )
        
        do {
            // Alice sends message targeted to Bob
            let aliceMsg = try await engineAlice.sendMessage(text: "Where are you?")
            
            // Deliver Alice's transmitted frame to Bob
            guard let wireData = await tAlice.lastBroadcastData() else {
                print("  FAIL: Alice did not produce a wire packet.")
                return false
            }
            
            // Bob ingests wire data
            let bobOutcome = try await engineBob.handleInboundWirePacket(wireData, fromPeerId: "Alice", receivedRssi: -65)
            guard let bobReceivedMsg = bobOutcome.deliveredMessage else {
                print("  FAIL: Bob did not deliver message locally: \(bobOutcome).")
                return false
            }
            guard bobReceivedMsg.text == "Where are you?", bobReceivedMsg.senderInitials == "ALI" else {
                print("  FAIL: Bob's received message content mismatch.")
                return false
            }
            
            // Bob generated and transmitted a delivery ACK back to Alice
            guard let ackWireData = await tBob.lastBroadcastData(ofType: .ack) else {
                print("  FAIL: Bob did not broadcast an ACK packet.")
                return false
            }
            
            // Alice ingests Bob's ACK
            let aliceRawAck = try RawWirePacket.fromWireData(ackWireData)
            let ackProcessed = await engineAlice.processDeliveryACK(rawPacket: aliceRawAck, fromPeerId: "Bob")
            guard ackProcessed else {
                print("  FAIL: Alice failed to process Bob's delivery ACK.")
                return false
            }
            
            // Verify Alice's message state transitioned to delivered
            guard let updatedAliceMsg = await engineAlice.message(withSequenceNumber: aliceMsg.sequenceNumber) else {
                print("  FAIL: Alice could not find message in history.")
                return false
            }
            
            guard updatedAliceMsg.deliveryState == .delivered(confirmedCount: 1, totalRecipients: 1) else {
                print("  FAIL: Alice message deliveryState is \(updatedAliceMsg.deliveryState), expected delivered(1, 1).")
                return false
            }
            guard updatedAliceMsg.recipientStates["BOB"]?.isDelivered == true else {
                print("  FAIL: Bob's recipient delivery status is not delivered.")
                return false
            }
        } catch {
            print("  FAIL: Direct delivery test threw error: \(error)")
            return false
        }
        
        print("  PASS: Direct peer delivery and mutual ACK exchange verified.")
        return true
    }
    
    // MARK: - Test 4: Multi-Hop Mesh Delivery Linear Chain
    
    public static func testMultiHopMeshDeliveryLinearChain() async -> Bool {
        print("[Test 4] Multi-hop mesh delivery over linear chain (Alice -> Relay R -> Bob)...")
        let clock = TestMeshClock()
        let groupKey = Data(repeating: 0x33, count: 32)
        let strangerKey = Data(repeating: 0xAA, count: 32)
        
        let sessionAlice = GroupSession(sessionId: 0x4444, sessionName: "Festival", symmetricKeyData: groupKey, localInitials: "ALI")
        let sessionRelay = GroupSession(sessionId: 0x9999, sessionName: "StrangerGroup", symmetricKeyData: strangerKey, localInitials: "REL")
        let sessionBob = GroupSession(sessionId: 0x4444, sessionName: "Festival", symmetricKeyData: groupKey, localInitials: "BOB")
        
        let tAlice = TestChatMockTransport()
        let tRelay = TestChatMockTransport()
        let tBob = TestChatMockTransport()
        
        let cryptoAlice = CryptoService()
        let cryptoRelay = CryptoService()
        let cryptoBob = CryptoService()
        
        let engineAlice = ChatMessageEngine(transport: tAlice, cryptoService: cryptoAlice, clock: clock, sessionProvider: { sessionAlice }, recipientsProvider: { ["BOB"] })
        let engineRelay = ChatMessageEngine(transport: tRelay, cryptoService: cryptoRelay, clock: clock, sessionProvider: { sessionRelay })
        let engineBob = ChatMessageEngine(transport: tBob, cryptoService: cryptoBob, clock: clock, sessionProvider: { sessionBob }, recipientsProvider: { ["ALI"] })
        
        do {
            // 1. Alice sends message
            let msgAlice = try await engineAlice.sendMessage(text: "At Main Stage")
            guard let aliceWire = await tAlice.lastBroadcastData() else {
                print("  FAIL: Alice outbox empty.")
                return false
            }
            
            // 2. Relay ingests Alice's packet (Session mismatch: Stranger relay!)
            let relayOutcome = try await engineRelay.handleInboundWirePacket(aliceWire, fromPeerId: "Alice")
            guard case .relayedStranger(let sid, let hopCount) = relayOutcome else {
                print("  FAIL: Relay did not blind-forward stranger packet: \(relayOutcome).")
                return false
            }
            guard sid == 0x4444, hopCount == 1 else {
                print("  FAIL: Relay mutated metadata incorrect (sid: \(sid), hop: \(hopCount)).")
                return false
            }
            
            // 3. Relay transmits mutated packet to Bob
            guard let relayWire = await tRelay.lastBroadcastData() else {
                print("  FAIL: Relay broadcast buffer empty.")
                return false
            }
            guard relayWire[2] == 1 else {
                print("  FAIL: Mutated hopCount on wire is \(relayWire[2]), expected 1.")
                return false
            }
            
            // 4. Bob ingests relayed packet (Hop 1)
            let bobOutcome = try await engineBob.handleInboundWirePacket(relayWire, fromPeerId: "Relay", receivedRssi: -72)
            guard let bobMsg = bobOutcome.deliveredMessage else {
                print("  FAIL: Bob did not deliver multi-hop message locally: \(bobOutcome).")
                return false
            }
            guard bobMsg.text == "At Main Stage", bobMsg.senderInitials == "ALI" else {
                print("  FAIL: Bob message content mismatch on multi-hop delivery.")
                return false
            }
            
            // 5. Bob dispatches ACK back through Relay
            guard let bobAckWire = await tBob.lastBroadcastData(ofType: .ack) else {
                print("  FAIL: Bob ACK wire missing.")
                return false
            }
            
            // Relay blinds forwards ACK back to Alice
            let relayAckOutcome = try await engineRelay.handleInboundWirePacket(bobAckWire, fromPeerId: "Bob")
            guard case .relayedStranger = relayAckOutcome else {
                print("  FAIL: Relay did not blind-forward stranger ACK: \(relayAckOutcome).")
                return false
            }
            
            guard let relayForwardedAck = await tRelay.lastBroadcastData(ofType: .ack) else {
                print("  FAIL: Relay did not forward ACK.")
                return false
            }
            
            // Alice ingests forwarded ACK
            let aliceRawAck = try RawWirePacket.fromWireData(relayForwardedAck)
            let ackHandled = await engineAlice.processDeliveryACK(rawPacket: aliceRawAck, fromPeerId: "Relay")
            guard ackHandled else {
                print("  FAIL: Alice could not process multi-hop ACK.")
                return false
            }
            
            let finalMsg = await engineAlice.message(withSequenceNumber: msgAlice.sequenceNumber)
            guard finalMsg?.deliveryState == .delivered(confirmedCount: 1, totalRecipients: 1) else {
                print("  FAIL: Alice multi-hop deliveryState is \(String(describing: finalMsg?.deliveryState)).")
                return false
            }
        } catch {
            print("  FAIL: Multi-hop delivery test threw error: \(error)")
            return false
        }
        
        print("  PASS: Multi-hop mesh delivery over linear chain verified.")
        return true
    }
    
    // MARK: - Test 5: Relays Do Not Decrypt Or Display Messages
    
    public static func testRelaysDoNotDecryptOrDisplayMessages() async -> Bool {
        print("[Test 5] Privacy invariant: Relays forward opaque packets without decrypting or displaying...")
        let clock = TestMeshClock()
        let groupKey = Data(repeating: 0x12, count: 32)
        let strangerKey = Data(repeating: 0x89, count: 32)
        
        let sessionAlice = GroupSession(sessionId: 0x5555, sessionName: "GroupA", symmetricKeyData: groupKey, localInitials: "ALI")
        let sessionRelay = GroupSession(sessionId: 0x6666, sessionName: "GroupB", symmetricKeyData: strangerKey, localInitials: "STR")
        
        let tAlice = TestChatMockTransport()
        let tRelay = TestChatMockTransport()
        
        let cryptoAlice = CryptoService()
        let cryptoRelay = CryptoService()
        
        let engineAlice = ChatMessageEngine(transport: tAlice, cryptoService: cryptoAlice, clock: clock, sessionProvider: { sessionAlice })
        let engineRelay = ChatMessageEngine(transport: tRelay, cryptoService: cryptoRelay, clock: clock, sessionProvider: { sessionRelay })
        
        do {
            _ = try await engineAlice.sendMessage(text: "Secret location")
            guard let aliceWire = await tAlice.lastBroadcastData() else {
                print("  FAIL: Alice outbox empty.")
                return false
            }
            
            // Relay ingests Alice's packet
            _ = try await engineRelay.handleInboundWirePacket(aliceWire, fromPeerId: "Alice")
            
            // Invariant: Relay's in-memory messages must remain completely empty!
            let relayMessages = await engineRelay.activeMessages()
            guard relayMessages.isEmpty else {
                print("  FAIL: Relay leaked message into its in-memory message history! Count: \(relayMessages.count).")
                return false
            }
        } catch {
            print("  FAIL: Privacy invariant test threw error: \(error)")
            return false
        }
        
        print("  PASS: Relay privacy invariant (zero-knowledge forwarding) verified.")
        return true
    }
    
    // MARK: - Test 6: Duplicate Message Suppression
    
    public static func testDuplicateMessageSuppression() async -> Bool {
        print("[Test 6] Duplicate suppression: Repeated message reception suppressed...")
        let clock = TestMeshClock()
        let key = Data(repeating: 0x50, count: 32)
        let sessionA = GroupSession(sessionId: 0x7777, sessionName: "Duo", symmetricKeyData: key, localInitials: "ALI")
        let sessionB = GroupSession(sessionId: 0x7777, sessionName: "Duo", symmetricKeyData: key, localInitials: "BOB")
        
        let tA = TestChatMockTransport()
        let tB = TestChatMockTransport()
        
        let cryptoA = CryptoService()
        let cryptoB = CryptoService()
        
        let engineA = ChatMessageEngine(transport: tA, cryptoService: cryptoA, clock: clock, sessionProvider: { sessionA }, recipientsProvider: { ["BOB"] })
        let engineB = ChatMessageEngine(transport: tB, cryptoService: cryptoB, clock: clock, sessionProvider: { sessionB }, recipientsProvider: { ["ALI"] })
        
        do {
            let msg = try await engineA.sendMessage(text: "Lost")
            guard let wireData = await tA.lastBroadcastData() else {
                print("  FAIL: Alice wire packet missing.")
                return false
            }
            
            // First arrival at Bob -> delivered locally
            let firstOutcome = try await engineB.handleInboundWirePacket(wireData, fromPeerId: "Alice")
            guard firstOutcome.isDeliveredLocally else {
                print("  FAIL: First packet should deliver locally: \(firstOutcome).")
                return false
            }
            
            // Drop Bob's first ACK. Sender retries must obtain a fresh ACK without redisplay.
            let firstACKs = await tB.broadcastedFrames.filter { (try? RawWirePacket.fromWireData($0))?.envelope.type == .ack }

            // Second arrival of same wire packet (duplicate arrival over alternative mesh path)
            let secondOutcome = try await engineB.handleInboundWirePacket(wireData, fromPeerId: "RelayPath2")
            guard case .droppedDuplicate(let seq) = secondOutcome, seq == msg.sequenceNumber else {
                print("  FAIL: Duplicate packet was not suppressed: \(secondOutcome).")
                return false
            }
            
            let retryACKs = await tB.broadcastedFrames.filter { (try? RawWirePacket.fromWireData($0))?.envelope.type == .ack }
            guard retryACKs.count == firstACKs.count + 1, let retryACK = retryACKs.last else {
                print("  FAIL: Lost delivery ACK cannot recover: duplicate chat did not produce a fresh ACK.")
                return false
            }
            _ = try await engineA.handleInboundWirePacket(retryACK, fromPeerId: "ForeignRelay")
            guard let delivered = await engineA.message(withSequenceNumber: msg.sequenceNumber), delivered.deliveryState.isDelivered else {
                print("  FAIL: Sender did not confirm delivery after ACK recovery.")
                return false
            }

            // Bob's in-memory messages must contain exactly 1 entry
            let bobMsgs = await engineB.activeMessages()
            guard bobMsgs.count == 1 else {
                print("  FAIL: Bob in-memory messages contains \(bobMsgs.count) items, expected exactly 1.")
                return false
            }
        } catch {
            print("  FAIL: Duplicate suppression test threw error: \(error)")
            return false
        }
        
        print("  PASS: Duplicate message suppression verified.")
        return true
    }
    
    // MARK: - Test 7: FIFO Outbox Lane Precedence & Bounds
    
    public static func testFIFOOutboxLanePrecedenceAndBounds() async -> Bool {
        print("[Test 7] Outbox FIFO lane precedence (SOS > Chat > Relay > Ping)...")
        let outbox = PriorityOutboxQueue(maxUrgentCapacity: 16, maxRelayCapacity: 32, maxChatCapacity: 16)
        
        // Helper to construct 56-byte wire packets
        func makePacket(type: PacketType, seq: UInt32) -> Data {
            var data = Data(capacity: 56)
            data.append((PacketConstants.protocolVersion << 4) | type.rawValue)
            data.append(8) // hopLimit
            data.append(0) // hopCount
            data.append(contentsOf: [0x00, 0x12, 0x34]) // sessionId
            var s = seq.bigEndian
            data.append(Data(bytes: &s, count: 4))
            data.append(Data(repeating: 0, count: 46)) // payload + authTag padding
            return data
        }
        
        do {
            // 1. Enqueue 3 chat messages: M1, M2, M3
            let chat1 = makePacket(type: .chatMessage, seq: 101)
            let chat2 = makePacket(type: .chatMessage, seq: 102)
            let chat3 = makePacket(type: .chatMessage, seq: 103)
            
            try outbox.enqueue(data: chat1)
            try outbox.enqueue(data: chat2)
            try outbox.enqueue(data: chat3)
            
            guard outbox.chatCount == 3 else {
                print("  FAIL: Expected chatCount 3, got \(outbox.chatCount).")
                return false
            }
            
            // 2. Enqueue routine location ping
            let ping = makePacket(type: .locationPing, seq: 201)
            try outbox.enqueue(data: ping)
            
            // 3. Enqueue stranger relay packet
            let relay = makePacket(type: .chatMessage, seq: 301)
            try outbox.enqueue(data: relay, isRelay: true)
            
            // 4. Enqueue urgent SOS packet
            let sos = makePacket(type: .sos, seq: 401)
            try outbox.enqueue(data: sos)
            
            // Verify Dequeue Precedence:
            // Tier 1: Urgent SOS must dequeue first
            let d1 = outbox.dequeue()
            guard d1?.packetType == .sos else {
                print("  FAIL: Item 1 was not SOS: \(String(describing: d1?.packetType)).")
                return false
            }
            
            // Tier 2: Chat FIFO: chat1 must dequeue next
            let d2 = outbox.dequeue()
            guard d2?.packetType == .chatMessage, !d2!.isRelay else {
                print("  FAIL: Item 2 was not local chat.")
                return false
            }
            let seq2 = d2!.packetData.subdata(in: 6..<10).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard seq2 == 101 else {
                print("  FAIL: FIFO violation: Expected seq 101, got \(seq2).")
                return false
            }
            
            // Chat FIFO: chat2 must dequeue next
            let d3 = outbox.dequeue()
            let seq3 = d3!.packetData.subdata(in: 6..<10).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard seq3 == 102 else {
                print("  FAIL: FIFO violation: Expected seq 102, got \(seq3).")
                return false
            }
            
            // Chat FIFO: chat3 must dequeue next
            let d4 = outbox.dequeue()
            let seq4 = d4!.packetData.subdata(in: 6..<10).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard seq4 == 103 else {
                print("  FAIL: FIFO violation: Expected seq 103, got \(seq4).")
                return false
            }
            
            // Tier 3: Stranger relay must dequeue next
            let d5 = outbox.dequeue()
            guard d5?.isRelay == true else {
                print("  FAIL: Item 5 was not stranger relay.")
                return false
            }
            
            // Tier 4: Routine location ping must dequeue last
            let d6 = outbox.dequeue()
            guard d6?.packetType == .locationPing else {
                print("  FAIL: Item 6 was not routine location ping.")
                return false
            }
            
            guard outbox.isEmpty else {
                print("  FAIL: Outbox should be empty.")
                return false
            }
        } catch {
            print("  FAIL: Outbox precedence test threw error: \(error)")
            return false
        }
        
        print("  PASS: Outbox FIFO lane precedence (SOS > Chat > Relay > Ping) verified.")
        return true
    }
    
    // MARK: - Test 8: Maximum Two Retries And Retry Backoff
    
    public static func testMaximumTwoRetriesAndRetryBackoff() async -> Bool {
        print("[Test 8] Maximum two retries (3 total attempts) and backoff timing...")
        let clock = TestMeshClock()
        let dummyKey = Data(repeating: 0x88, count: 32)
        let session = GroupSession(sessionId: 0x8888, sessionName: "Crew", symmetricKeyData: dummyKey, localInitials: "ALI")
        let transport = TestChatMockTransport()
        let crypto = CryptoService()
        
        let engine = ChatMessageEngine(
            transport: transport,
            cryptoService: crypto,
            clock: clock,
            sessionProvider: { session },
            recipientsProvider: { ["BOB"] }
        )
        
        do {
            // Attempt 1: Initial transmission
            _ = try await engine.sendMessage(text: "Restroom")
            var sentCount = await transport.broadcastCount()
            guard sentCount == 1 else {
                print("  FAIL: Expected 1 packet sent initially, got \(sentCount).")
                return false
            }
            
            // Advance clock by 0.2s (< 0.5s backoff) -> Should NOT retransmit yet
            clock.advance(by: 0.2)
            await engine.evaluateTimeoutsAndRetries()
            sentCount = await transport.broadcastCount()
            guard sentCount == 1 else {
                print("  FAIL: Premature retry before 0.5s backoff delay.")
                return false
            }
            
            // Attempt 2 (Retry 1): Advance clock past 0.5s backoff
            clock.advance(by: 0.4) // total 0.6s
            await engine.evaluateTimeoutsAndRetries()
            sentCount = await transport.broadcastCount()
            guard sentCount == 2 else {
                print("  FAIL: Expected 2 packets sent after retry 1, got \(sentCount).")
                return false
            }
            
            // Attempt 3 (Retry 2): Advance clock past another 0.5s backoff
            clock.advance(by: 0.6)
            await engine.evaluateTimeoutsAndRetries()
            sentCount = await transport.broadcastCount()
            guard sentCount == 3 else {
                print("  FAIL: Expected 3 packets sent after retry 2, got \(sentCount).")
                return false
            }
            
            // Attempt 4 (Exceeded Max Retries): Advance clock further -> MUST NOT RETRY AGAIN
            clock.advance(by: 1.0)
            await engine.evaluateTimeoutsAndRetries()
            sentCount = await transport.broadcastCount()
            guard sentCount == 3 else {
                print("  FAIL: Exceeded max 2 retries! Packets sent: \(sentCount).")
                return false
            }
        } catch {
            print("  FAIL: Retry test threw error: \(error)")
            return false
        }
        
        print("  PASS: Maximum two retries (3 total attempts) and backoff verified.")
        return true
    }
    
    // MARK: - Test 9: Three-Second Cooldown With Test Clock
    
    public static func testThreeSecondCooldownWithTestClock() async -> Bool {
        print("[Test 9] Client-side 3.0-second cooldown enforcement with clock advancement...")
        let clock = TestMeshClock()
        let dummyKey = Data(repeating: 0x44, count: 32)
        let session = GroupSession(sessionId: 0x9999, sessionName: "Crew", symmetricKeyData: dummyKey, localInitials: "ALI")
        let transport = TestChatMockTransport()
        let crypto = CryptoService()
        
        let engine = ChatMessageEngine(
            transport: transport,
            cryptoService: crypto,
            clock: clock,
            sessionProvider: { session }
        )
        
        do {
            // First message at t = 0.0s
            _ = try await engine.sendMessage(text: "First message")
            
            // Rapid attempt at t = 1.0s (cooldown active: 2.0s remaining)
            clock.advance(by: 1.0)
            do {
                _ = try await engine.sendMessage(text: "Second message")
                print("  FAIL: Second message was permitted during 3.0s cooldown.")
                return false
            } catch let ChatEngineError.cooldownActive(remaining) {
                guard remaining > 1.8 && remaining <= 2.0 else {
                    print("  FAIL: Expected ~2.0s remaining cooldown, got \(remaining).")
                    return false
                }
            }
            
            // Advance clock past 3.0s cooldown (t = 3.5s total) -> Must succeed now
            clock.advance(by: 2.5)
            let secondMsg = try await engine.sendMessage(text: "Second message")
            guard secondMsg.text == "Second message" else {
                print("  FAIL: Second message content mismatch.")
                return false
            }
        } catch {
            print("  FAIL: Cooldown test threw error: \(error)")
            return false
        }
        
        print("  PASS: Client-side 3.0-second cooldown enforcement verified.")
        return true
    }
    
    // MARK: - Test 10: Per-Recipient ACK And Delivery Tracking
    
    public static func testPerRecipientACKAndDeliveryTracking() async -> Bool {
        print("[Test 10] Per-recipient delivery state tracking (Bob & Charlie in roster)...")
        let clock = TestMeshClock()
        let groupKey = Data(repeating: 0x66, count: 32)
        let sessionAlice = GroupSession(sessionId: 0xAAAA, sessionName: "Trio", symmetricKeyData: groupKey, localInitials: "ALI")
        
        let tAlice = TestChatMockTransport()
        let cryptoAlice = CryptoService()
        let cryptoBob = CryptoService()
        let cryptoCharlie = CryptoService()
        
        let engineAlice = ChatMessageEngine(
            transport: tAlice,
            cryptoService: cryptoAlice,
            clock: clock,
            sessionProvider: { sessionAlice },
            recipientsProvider: { ["BOB", "CHA"] }
        )
        
        do {
            let msg = try await engineAlice.sendMessage(text: "Meet at gate")
            
            // Both Bob and Charlie should be initialized to forwardedToNextHop
            guard msg.recipientStates["BOB"] == .forwardedToNextHop,
                  msg.recipientStates["CHA"] == .forwardedToNextHop else {
                print("  FAIL: Initial recipient states mismatch: \(msg.recipientStates).")
                return false
            }
            
            // Bob sends delivery ACK
            let bobAckPayload = ACKPayload(
                ackedSeqNumber: msg.sequenceNumber,
                ackedSenderInitials: "ALI",
                ackTimestamp: clock.now(),
                ackStatus: .deliveredToFriend,
                receivedRssi: -60,
                originalEventId: msg.sequenceNumber,
                responderInitials: "BOB"
            )
            let bobEnvelope = CleartextEnvelope(version: 3, type: .ack, hopLimit: 8, hopCount: 0, sessionId: 0xAAAA, sequenceNumber: 991)
            let (cBob, tBob) = try await cryptoBob.seal(payload: bobAckPayload.serialize(), envelope: bobEnvelope, using: SymmetricKey(data: groupKey))
            let rawBobAck = RawWirePacket(envelope: bobEnvelope, ciphertext: cBob, authTag: tBob)
            
            _ = await engineAlice.processDeliveryACK(rawPacket: rawBobAck, fromPeerId: "Bob")
            
            // Verify partial delivery: Bob is deliveredToRecipient, Charlie is still forwardedToNextHop
            let partialMsg = await engineAlice.message(withSequenceNumber: msg.sequenceNumber)!
            guard partialMsg.recipientStates["BOB"]?.isDelivered == true else {
                print("  FAIL: Bob should be marked delivered.")
                return false
            }
            guard partialMsg.recipientStates["CHA"]?.isDelivered == false else {
                print("  FAIL: Charlie should NOT be marked delivered yet.")
                return false
            }
            guard partialMsg.confirmedRecipientCount == 1, partialMsg.totalRecipientCount == 2 else {
                print("  FAIL: Expected 1/2 delivered tally, got \(partialMsg.confirmedRecipientCount)/\(partialMsg.totalRecipientCount).")
                return false
            }
            
            // Charlie sends delivery ACK
            let charlieAckPayload = ACKPayload(
                ackedSeqNumber: msg.sequenceNumber,
                ackedSenderInitials: "ALI",
                ackTimestamp: clock.now(),
                ackStatus: .deliveredToFriend,
                receivedRssi: -68,
                originalEventId: msg.sequenceNumber,
                responderInitials: "CHA"
            )
            let charlieEnvelope = CleartextEnvelope(version: 3, type: .ack, hopLimit: 8, hopCount: 0, sessionId: 0xAAAA, sequenceNumber: 992)
            let (cCha, tCha) = try await cryptoCharlie.seal(payload: charlieAckPayload.serialize(), envelope: charlieEnvelope, using: SymmetricKey(data: groupKey))
            let rawChaAck = RawWirePacket(envelope: charlieEnvelope, ciphertext: cCha, authTag: tCha)
            
            _ = await engineAlice.processDeliveryACK(rawPacket: rawChaAck, fromPeerId: "Charlie")
            
            // Verify full delivery: both delivered
            let fullMsg = await engineAlice.message(withSequenceNumber: msg.sequenceNumber)!
            guard fullMsg.confirmedRecipientCount == 2, fullMsg.totalRecipientCount == 2 else {
                print("  FAIL: Expected 2/2 confirmed tally.")
                return false
            }
            guard fullMsg.deliveryState == .delivered(confirmedCount: 2, totalRecipients: 2) else {
                print("  FAIL: Delivery state mismatch: \(fullMsg.deliveryState).")
                return false
            }
        } catch {
            print("  FAIL: Per-recipient ACK test threw error: \(error)")
            return false
        }
        
        print("  PASS: Per-recipient ACK and delivery state tracking verified.")
        return true
    }
    
    // MARK: - Test 11: Relay ACK Never Treated As Final Delivery
    
    public static func testRelayACKNeverTreatedAsFinalDelivery() async -> Bool {
        print("[Test 11] Honest UX invariant: Intermediary relay ACK is never treated as recipient delivery...")
        let clock = TestMeshClock()
        let groupKey = Data(repeating: 0x73, count: 32)
        let sessionAlice = GroupSession(sessionId: 0xBBBB, sessionName: "Crew", symmetricKeyData: groupKey, localInitials: "ALI")
        
        let tAlice = TestChatMockTransport()
        let cryptoAlice = CryptoService()
        let cryptoRelay = CryptoService()
        
        let engineAlice = ChatMessageEngine(
            transport: tAlice,
            cryptoService: cryptoAlice,
            clock: clock,
            sessionProvider: { sessionAlice },
            recipientsProvider: { ["BOB"] }
        )
        
        do {
            let msg = try await engineAlice.sendMessage(text: "On my way")
            
            // Relay node generates a RELAY ACK (ackStatus: .relayedByMeshHop = 0x02)
            let relayAckPayload = ACKPayload(
                ackedSeqNumber: msg.sequenceNumber,
                ackedSenderInitials: "ALI",
                ackTimestamp: clock.now(),
                ackStatus: .relayedByMeshHop, // Intermediary hop!
                receivedRssi: -75,
                originalEventId: msg.sequenceNumber,
                responderInitials: "REL"
            )
            let env = CleartextEnvelope(version: 3, type: .ack, hopLimit: 8, hopCount: 1, sessionId: 0xBBBB, sequenceNumber: 888)
            let (c, t) = try await cryptoRelay.seal(payload: relayAckPayload.serialize(), envelope: env, using: SymmetricKey(data: groupKey))
            let rawRelayAck = RawWirePacket(envelope: env, ciphertext: c, authTag: t)
            
            _ = await engineAlice.processDeliveryACK(rawPacket: rawRelayAck, fromPeerId: "Relay")
            
            let updatedMsg = await engineAlice.message(withSequenceNumber: msg.sequenceNumber)!
            
            // Must transition to relayedByMesh, NOT delivered!
            guard updatedMsg.deliveryState == .relayedByMesh(hopCount: 1) else {
                print("  FAIL: Message deliveryState is \(updatedMsg.deliveryState), expected relayedByMesh(1).")
                return false
            }
            
            // Recipient must NOT be marked delivered
            guard updatedMsg.recipientStates["BOB"]?.isDelivered == false else {
                print("  FAIL: Bob was falsely marked delivered from a relay ACK!")
                return false
            }
            guard updatedMsg.confirmedRecipientCount == 0 else {
                print("  FAIL: Confirmed recipient count should be 0 from a relay ACK.")
                return false
            }
        } catch {
            print("  FAIL: Relay ACK test threw error: \(error)")
            return false
        }
        
        print("  PASS: Honest UX invariant (relay ACK != recipient delivery) verified.")
        return true
    }
    
    // MARK: - Test 12: Delivery Timeout Window
    
    public static func testDeliveryTimeoutWindow() async -> Bool {
        print("[Test 12] Delivery timeout window (15.0s) transitions unconfirmed recipients to deliveryTimedOut...")
        let clock = TestMeshClock()
        let dummyKey = Data(repeating: 0x11, count: 32)
        let session = GroupSession(sessionId: 0xCCCC, sessionName: "Crew", symmetricKeyData: dummyKey, localInitials: "ALI")
        let transport = TestChatMockTransport()
        let crypto = CryptoService()
        
        let engine = ChatMessageEngine(
            transport: transport,
            cryptoService: crypto,
            clock: clock,
            sessionProvider: { session },
            recipientsProvider: { ["BOB"] }
        )
        
        do {
            let msg = try await engine.sendMessage(text: "Where u at?")
            
            // Advance clock by 10s (< 15.0s timeout)
            clock.advance(by: 10.0)
            await engine.evaluateTimeoutsAndRetries()
            var currentMsg = await engine.message(withSequenceNumber: msg.sequenceNumber)!
            guard currentMsg.deliveryState != .deliveryTimedOut else {
                print("  FAIL: Premature timeout at 10.0s.")
                return false
            }
            
            // Advance clock past 15.0s window (total 16.0s)
            clock.advance(by: 6.0)
            await engine.evaluateTimeoutsAndRetries()
            currentMsg = await engine.message(withSequenceNumber: msg.sequenceNumber)!
            
            guard currentMsg.deliveryState == .deliveryTimedOut else {
                print("  FAIL: Message deliveryState is \(currentMsg.deliveryState), expected deliveryTimedOut.")
                return false
            }
            guard currentMsg.recipientStates["BOB"] == .deliveryTimedOut else {
                print("  FAIL: Bob's recipientState is \(String(describing: currentMsg.recipientStates["BOB"])), expected deliveryTimedOut.")
                return false
            }
        } catch {
            print("  FAIL: Timeout test threw error: \(error)")
            return false
        }
        
        print("  PASS: Delivery timeout window (15.0s) verified.")
        return true
    }
    
    // MARK: - Test 13: Ephemeral In-Memory History & Teardown Purge
    
    public static func testEphemeralInMemoryHistoryAndTeardownPurge() async -> Bool {
        print("[Test 13] In-memory history bounds (max 50) and session teardown purge...")
        let clock = TestMeshClock()
        let dummyKey = Data(repeating: 0x22, count: 32)
        let session = GroupSession(sessionId: 0xDDDD, sessionName: "Crew", symmetricKeyData: dummyKey, localInitials: "ALI")
        let transport = TestChatMockTransport()
        let crypto = CryptoService()
        
        let engine = ChatMessageEngine(
            transport: transport,
            cryptoService: crypto,
            clock: clock,
            sessionProvider: { session }
        )
        
        do {
            // Send 55 messages advancing clock past cooldown
            for i in 1...55 {
                clock.advance(by: 3.5)
                _ = try await engine.sendMessage(text: "Msg \(i)")
            }
            
            // Ring buffer capacity enforcement: exactly 50 messages retained
            let active = await engine.activeMessages()
            guard active.count == 50 else {
                print("  FAIL: Expected 50 messages retained, got \(active.count).")
                return false
            }
            
            // First 5 messages should have been evicted; earliest retained is Msg 6
            guard active.first?.text == "Msg 6", active.last?.text == "Msg 55" else {
                print("  FAIL: Ring buffer drop-head order mismatch: first=\(active.first?.text ?? ""), last=\(active.last?.text ?? "").")
                return false
            }
            
            // Teardown / Session exit purge
            await engine.clearHistory()
            let purged = await engine.activeMessages()
            guard purged.isEmpty else {
                print("  FAIL: History not empty after clearHistory(). Count: \(purged.count).")
                return false
            }
        } catch {
            print("  FAIL: Ephemeral history test threw error: \(error)")
            return false
        }
        
        print("  PASS: In-memory history bounds and session teardown purge verified.")
        return true
    }
    
    // MARK: - Test 14: Battery Cutoff Disables Chat Without Disabling SOS
    
    public static func testBatteryCutoffDisablesChatWithoutDisablingSOS() async -> Bool {
        print("[Test 14] Battery cutoff (<20% battery) disables chat while Emergency SOS remains active...")
        let clock = TestMeshClock()
        let dummyKey = Data(repeating: 0x33, count: 32)
        let session = GroupSession(sessionId: 0xEEEE, sessionName: "Crew", symmetricKeyData: dummyKey, localInitials: "ALI")
        let transport = TestChatMockTransport()
        let crypto = CryptoService()
        
        let engine = ChatMessageEngine(
            transport: transport,
            cryptoService: crypto,
            clock: clock,
            sessionProvider: { session }
        )
        
        // 1. Normal battery (85%) -> Chat sends successfully
        await engine.setBatteryLevel(0.85, isLowPowerMode: false)
        do {
            _ = try await engine.sendMessage(text: "Hello")
        } catch {
            print("  FAIL: Normal battery chat failed: \(error)")
            return false
        }
        
        // 2. Drop battery below 20% (15%) -> Chat must be rejected
        clock.advance(by: 3.5)
        await engine.setBatteryLevel(0.15, isLowPowerMode: false)
        do {
            _ = try await engine.sendMessage(text: "Low battery msg")
            print("  FAIL: Chat was permitted at 15% battery!")
            return false
        } catch let ChatEngineError.batteryThrottled(level) {
            guard abs(level - 0.15) < 0.01 else {
                print("  FAIL: Battery level reported mismatch: \(level).")
                return false
            }
        } catch {
            print("  FAIL: Unexpected error on low battery: \(error)")
            return false
        }
        
        #if canImport(UIKit)
        // 3. Verify Emergency SOS is NOT disabled by this cutoff
        let sosViewModel = SOSViewModel(
            sessionProvider: { session },
            cryptoService: crypto,
            transport: transport,
            dateProvider: { clock.now() }
        )
        
        // SOS should still dispatch successfully even at 15% battery
        sosViewModel.triggerSOS(emergencyType: .medical)
        guard sosViewModel.deliveryState == .localSending else {
            print("  FAIL: SOS dispatch failed at 15% battery: \(sosViewModel.deliveryState).")
            return false
        }
        
        print("  PASS: Battery cutoff (<20%) disables chat without disabling Emergency SOS.")
        #else
        print("  PASS: Chat battery cutoff. SOS ViewModel assertion requires iOS and was skipped.")
        #endif
        return true
    }
    
    // MARK: - Test 15: Preserve SOS Priority And Rate Limits
    
    public static func testPreserveSOSPriorityAndRateLimits() async -> Bool {
        print("[Test 15] Preserve SOS priority and existing forwarding rate limits...")
        let clock = TestMeshClock()
        let rateLimiter = ForwardingRateLimiter(clock: clock, ordinaryCapacity: 2.0, ordinaryRefillRate: 2.0, sosCapacity: 4.0, sosRefillRate: 4.0)
        
        // Consume all ordinary tokens (e.g. by routine chat relays)
        let o1 = await rateLimiter.consumeOrdinaryToken()
        let o2 = await rateLimiter.consumeOrdinaryToken()
        let o3 = await rateLimiter.consumeOrdinaryToken()
        guard o1 && o2 && !o3 else {
            print("  FAIL: Ordinary token bucket did not exhaust properly.")
            return false
        }
        
        // Even when ordinary relay capacity is 100% exhausted, SOS tokens MUST remain available
        let s1 = await rateLimiter.consumeSOSToken()
        let s2 = await rateLimiter.consumeSOSToken()
        guard s1 && s2 else {
            print("  FAIL: SOS lane was starved by ordinary rate limit exhaustion!")
            return false
        }
        
        print("  PASS: SOS priority lane and rate limit independence verified.")
        return true
    }
    
    // MARK: - Test 16: Direct 1-on-1 Topology With XOR Initials Collision Not Dropped
    
    public static func testDirectOneOnOneInitialsCollisionNotDropped() async -> Bool {
        print("[Test 16] Direct 1-on-1 topology with XOR hash collision not dropped...")
        let clock = TestMeshClock()
        let dummyKey = Data(repeating: 0x77, count: 32)
        
        let sessionAlice = GroupSession(sessionId: 0x5555, sessionName: "Duo", symmetricKeyData: dummyKey, localInitials: "ALI")
        let sessionBob = GroupSession(sessionId: 0x5555, sessionName: "Duo", symmetricKeyData: dummyKey, localInitials: "BOB")
        
        let tAlice = TestChatMockTransport()
        let tBob = TestChatMockTransport()
        let cryptoAlice = CryptoService()
        let cryptoBob = CryptoService()
        
        let engineBob = ChatMessageEngine(
            transport: tBob,
            cryptoService: cryptoBob,
            clock: clock,
            sessionProvider: { sessionBob },
            recipientsProvider: { ["ALI"] }
        )
        
        do {
            // Craft packet where envelope.memberSlot matches Bob's local memberSlot
            let bobSlot = sessionBob.memberSlot
            let collidingSeq = CleartextEnvelope.makeSequenceNumber(memberSlot: bobSlot, counter: 42)
            let collidingEnvelope = CleartextEnvelope(
                type: .chatMessage,
                hopLimit: 8,
                hopCount: 0,
                sessionId: sessionAlice.sessionId,
                sequenceNumber: collidingSeq
            )
            
            let alicePayload = ChatMessagePayload(senderInitials: "ALI", text: "Direct hello!")
            let sealedAlice = try await cryptoAlice.seal(
                payload: alicePayload.serialize(),
                envelope: collidingEnvelope,
                using: SymmetricKey(data: dummyKey)
            )
            let collidingPacket = RawWirePacket(envelope: collidingEnvelope, ciphertext: sealedAlice.ciphertext, authTag: sealedAlice.authTag)
            let inboundAlice = InboundPacket(rawPacket: collidingPacket, sourcePeerId: "Alice", receivedRssi: -60)
            let bobOutcome = try await engineBob.handleInboundPacket(inboundAlice)
            
            guard let bobMsg = bobOutcome.deliveredMessage else {
                print("  FAIL: Bob dropped Alice's message because memberSlot matched local memberSlot: \(bobOutcome)")
                return false
            }
            
            guard bobMsg.senderInitials == "ALI", bobMsg.text == "Direct hello!" else {
                print("  FAIL: Bob delivered wrong message contents: \(bobMsg)")
                return false
            }
            
            // Also verify that genuine self-echo (authenticated payload.senderInitials == sessionBob.localInitials) IS dropped
            let selfSeq = CleartextEnvelope.makeSequenceNumber(memberSlot: bobSlot, counter: 43)
            let selfEnvelope = CleartextEnvelope(
                type: .chatMessage,
                hopLimit: 8,
                hopCount: 0,
                sessionId: sessionAlice.sessionId,
                sequenceNumber: selfSeq
            )
            let selfEchoPayload = ChatMessagePayload(senderInitials: sessionBob.localInitials, text: "Echo test")
            let sealedSelf = try await cryptoBob.seal(
                payload: selfEchoPayload.serialize(),
                envelope: selfEnvelope,
                using: SymmetricKey(data: dummyKey)
            )
            let selfRaw = RawWirePacket(envelope: selfEnvelope, ciphertext: sealedSelf.ciphertext, authTag: sealedSelf.authTag)
            let inboundSelf = InboundPacket(rawPacket: selfRaw, sourcePeerId: "BobSelf", receivedRssi: -50)
            let selfOutcome = try await engineBob.handleInboundPacket(inboundSelf)
            
            guard case .droppedSelfEcho = selfOutcome else {
                print("  FAIL: Genuine self-echo packet was not dropped: \(selfOutcome)")
                return false
            }
        } catch {
            print("  FAIL: Exception in initials collision test: \(error)")
            return false
        }
        
        print("  PASS: Direct 1-on-1 chat packets not dropped on memberSlot collision, self-echo properly filtered.")
        return true
    }
    /// Uses the same ciphertext store, budget and outbox as the radio transport.
    /// Both a B->C data submission and a B->A ACK submission are deliberately lost.
    public static func testCrossGroupEdgeLinkRecovery() async -> Bool {
        print("[Regression] Cross-group edge link: lost data and lost reverse ACK at 0.8/2/8 packets/sec...")
        for rate in [0.8, 2.0, 8.0] {
            let clock = TestMeshClock(initialDate: Date(timeIntervalSince1970: 1_800_000_000))
            let key = Data(repeating: 0x55, count: 32)
            let a = GroupSession(sessionId: 0x1111, symmetricKeyData: key, localInitials: "AAA")
            let c = GroupSession(sessionId: a.sessionId, symmetricKeyData: key, localInitials: "CCC")
            let ta = TestChatMockTransport()
            let tc = TestChatMockTransport()
            let engineA = ChatMessageEngine(transport: ta, cryptoService: CryptoService(), clock: clock, sessionProvider: { a })
            let engineC = ChatMessageEngine(transport: tc, cryptoService: CryptoService(), clock: clock, sessionProvider: { c })
            let budget = ForwardingRateLimiter(clock: clock, ordinaryCapacity: 1, ordinaryRefillRate: rate)
            var custody = CarryMessageStore()
            let outbox = PriorityOutboxQueue()
            do {
                let message = try await engineA.sendMessage(text: "Meet at gate", targetRecipients: ["CCC"])
                guard let original = await ta.lastBroadcastData() else { return false }
                var relayed = original
                relayed[2] += 1
                custody.remember(relayed, isForeign: true, excludingPeerId: "A", now: clock.now())
                // Exhaust ordinary airtime before the reliable packet arrives.
                _ = await budget.consumeOrdinaryToken()
                guard !(await budget.consumeOrdinaryToken()) else { return false }
                for attempt in 0..<2 {
                    clock.advance(by: 2)
                    guard let next = custody.nextTransmission(to: ["A", "C"], now: clock.now()), next.peer == "C",
                          await budget.consumeOrdinaryToken() else { return false }
                    try outbox.enqueue(data: next.data, destinationPeerId: next.peer, isRelay: next.isForeign)
                    guard let item = outbox.dequeue(), item.packetType == .chatMessage else { return false }
                    custody.markAttempt(item.packetData, to: "C", now: clock.now())
                    guard item.packetData[2] == 1, item.packetData.suffix(46) == original.suffix(46) else { return false }
                    if attempt == 1 { _ = try await engineC.handleInboundWirePacket(item.packetData, fromPeerId: "B") }
                    // First attempt is accepted by the link but never reaches C.
                }
                let responses = await tc.broadcastedFrames
                guard var ack = responses.first(where: { (try? RawWirePacket.fromWireData($0))?.envelope.type == .ack }) else { return false }
                ack[2] += 1
                custody.remember(ack, isForeign: true, excludingPeerId: "C", now: clock.now())
                for attempt in 0..<2 {
                    clock.advance(by: 2)
                    guard let next = custody.nextTransmission(to: ["A", "C"], now: clock.now()), next.peer == "A",
                          await budget.consumeOrdinaryToken() else { return false }
                    try outbox.enqueue(data: next.data, destinationPeerId: next.peer, isRelay: next.isForeign)
                    guard let item = outbox.dequeue(), item.packetType == .ack, item.isUrgent, item.isRelay else { return false }
                    custody.markAttempt(item.packetData, to: "A", now: clock.now())
                    if attempt == 1 { _ = try await engineA.handleInboundWirePacket(item.packetData, fromPeerId: "B") }
                    // First ACK attempt never reaches A; the relay must resend it.
                }
                let received = await engineC.activeMessages()
                guard let result = await engineA.message(withSequenceNumber: message.sequenceNumber),
                      result.deliveryState.isDelivered, received.count == 1,
                      clock.now().timeIntervalSince(message.timestamp) < 15 else { return false }
            } catch {
                print("  FAIL: Loss recovery at rate \(rate): \(error)")
                return false
            }
        }
        print("  PASS: Data and reverse ACK recover within 8 seconds, one displayed message, unchanged ciphertext/hop budget.")
        return true
    }

    public static func testConfiguredRelayBudgetAndTelemetryReservation() async -> Bool {
        print("[Regression] Relay limiter reads configuration; telemetry cannot spend the chat/ACK reserve...")
        let clock = TestMeshClock()
        let configured = ForwardingRateLimiter(clock: clock)
        for _ in 0..<Int(TeeKumConfiguration.Timing.ordinaryRelayBurstCapacity) {
            _ = await configured.consumeOrdinaryToken()
        }
        clock.advance(by: 1)
        let available = await configured.availableTokens()
        let expected = min(TeeKumConfiguration.Timing.ordinaryRelayBurstCapacity, TeeKumConfiguration.Timing.ordinaryRelayRateLimit)
        guard abs(available - expected) < 0.0001 else {
            print("  FAIL: Configured rate \(expected) differs from actual tokens \(available).")
            return false
        }
        let budget = ForwardingRateLimiter(clock: clock, ordinaryCapacity: 4, ordinaryRefillRate: 0.8)
        for _ in 0..<3 { guard await budget.consumeTelemetryToken() else { return false } }
        guard !(await budget.consumeTelemetryToken()), await budget.consumeOrdinaryToken(),
              !(await budget.consumeOrdinaryToken()), await budget.consumeSOSToken() else { return false }
        print("  PASS: Configured refill is effective; reliable traffic uses a reserve within the same bounded budget; SOS remains independent.")
        return true
    }

}
