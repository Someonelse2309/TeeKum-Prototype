//
//  ChatMessageEngine.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import Foundation
import CryptoKit

/// Authoritative Actor implementing the TeeKum Phase 3 Festival Group Mesh Chat Engine.
///
/// Implements Master Specification Guarantees:
/// 1. Validation & Encoding: Accepts, validates (1..20 UTF-8 bytes), encodes, encrypts with ChaCha20-Poly1305,
///    and dispatches 56-byte wire packets (`PacketType.chatMessage = 0x07`).
/// 2. Direct & Multi-Hop: Supports direct radio links and bounded multi-hop mesh forwarding (up to 8 hops).
/// 3. Zero-Knowledge Blind Relays: Relays forward opaque ciphertexts without group keys; never decrypt or display.
/// 4. Duplicate Suppression: Deduplicates by canonical `(sessionId, sequenceNumber)` via `SeenPacketCache`.
/// 5. Timing Semantics: Strict FIFO transmission, max 2 retries (3 total attempts), 3.0s client-side cooldown.
/// 6. Per-Recipient ACK Tracking: Tracks delivery state separately for every intended group recipient.
/// 7. Honest UX: Never treats intermediary relay ACKs (`0x02`) as final friend recipient delivery (`0x01`).
/// 8. Explicit 5-State Progression: `locallyAccepted` -> `forwardedToNextHop` -> `relayedByMesh` -> `deliveredToRecipient` -> `deliveryTimedOut`.
/// 9. Ephemeral Security: Retains at most 50 messages strictly in memory. Never persists plaintext or logs content.
///    All chat history is purged upon session termination.
/// 10. Battery Guard: Automatically disables chat below 20% battery (Festival Survival Mode) without disabling SOS.
/// 11. Preserves SOS Priority: Local chat operates in Tier 3 FIFO, strictly behind Tier 1 Emergency SOS.
public actor ChatMessageEngine {
    
    // MARK: - Dependencies
    
    private let transport: MeshTransport
    private let cryptoService: CryptoServiceProvider
    private let routingTable: RoutingTableManaging?
    private let neighborTable: NeighborManaging?
    private let rateLimiter: ForwardingBudgetManaging?
    private let seenPacketCache: SeenPacketCache
    private let clock: MeshClock
    private var sessionProvider: (@Sendable () -> GroupSession?)?
    private var recipientsProvider: (@MainActor @Sendable () -> [String])?
    
    // MARK: - Configuration & Tunables
    
    public var timingConfig: MeshTimingConfiguration
    public let maxHistoryCount: Int = 50
    
    // MARK: - Ephemeral In-Memory State
    
    private var inMemoryMessages: [ChatMessage] = []
    private var lastSentTimestamp: Date = .distantPast
    private var monotonicCounter: UInt32 = 1
    
    // Hardware battery & survival tracking
    public private(set) var currentBatteryLevel: Float = 1.0
    public private(set) var isLowPowerMode: Bool = false
    public private(set) var isSurvivalMode: Bool = false
    
    // In-flight message tracking for retries and ACK confirmation timeouts
    private struct InFlightMessage {
        var message: ChatMessage
        var rawWirePacket: RawWirePacket
        var wireData: Data
        var attemptCount: Int
        var maxRetries: Int
        var lastSentAt: Date
        var retryTask: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?
    }
    private var inFlightMessages: [UInt32: InFlightMessage] = [:]
    
    // Deduplication tracking for received chat sequence numbers
    private var seenChatSequences: Set<UInt32> = []
    
    // Stream of message updates for UI observers
    private var messageUpdateContinuation: AsyncStream<ChatMessage>.Continuation?
    public nonisolated let messageUpdates: AsyncStream<ChatMessage>
    
    // Direct callback for state updates
    private var onMessageUpdated: (@Sendable (ChatMessage) -> Void)?
    private var retrySupervisorTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init(
        transport: MeshTransport,
        cryptoService: CryptoServiceProvider,
        routingTable: RoutingTableManaging? = nil,
        neighborTable: NeighborManaging? = nil,
        rateLimiter: ForwardingBudgetManaging? = nil,
        seenPacketCache: SeenPacketCache? = nil,
        clock: MeshClock = SystemMeshClock(),
        timingConfig: MeshTimingConfiguration = MeshTimingConfiguration(),
        sessionProvider: (@Sendable () -> GroupSession?)? = nil,
        recipientsProvider: (@MainActor @Sendable () -> [String])? = nil,
        onMessageUpdated: (@Sendable (ChatMessage) -> Void)? = nil
    ) {
        self.transport = transport
        self.cryptoService = cryptoService
        self.routingTable = routingTable
        self.neighborTable = neighborTable
        self.rateLimiter = rateLimiter
        self.seenPacketCache = seenPacketCache ?? SeenPacketCache(clock: clock)
        self.clock = clock
        self.timingConfig = timingConfig
        self.sessionProvider = sessionProvider
        self.recipientsProvider = recipientsProvider
        self.onMessageUpdated = onMessageUpdated
        
        let (stream, continuation) = AsyncStream.makeStream(of: ChatMessage.self)
        self.messageUpdates = stream
        self.messageUpdateContinuation = continuation
    }
    
    public func setOnMessageUpdated(_ handler: (@Sendable (ChatMessage) -> Void)?) {
        self.onMessageUpdated = handler
    }
    
    /// Reconfigures session and recipient providers for an active session lifecycle.
    public func configure(
        sessionProvider: (@Sendable () -> GroupSession?)?,
        recipientsProvider: (@MainActor @Sendable () -> [String])? = nil
    ) {
        self.sessionProvider = sessionProvider
        self.recipientsProvider = recipientsProvider
        
        retrySupervisorTask?.cancel()
        if sessionProvider != nil {
            retrySupervisorTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { break }
                    await self?.evaluateTimeoutsAndRetries()
                }
            }
        } else {
            retrySupervisorTask = nil
        }
    }
    
    // MARK: - Battery & Power Policy
    
    /// Updates hardware power state. Automatically disables outgoing chat at <20% battery or Low Power Mode.
    /// Does NOT disable Emergency SOS.
    public func setBatteryLevel(_ level: Float, isLowPowerMode: Bool = false) {
        self.currentBatteryLevel = level
        self.isLowPowerMode = isLowPowerMode
        self.isSurvivalMode = (level < 0.20) || isLowPowerMode
    }
    
    // MARK: - Outbound Chat Dispatch Pipeline
    
    /// Accepts, validates, encodes, encrypts, and transmits a chat message across the mesh.
    ///
    /// - Parameters:
    ///   - text: User text content (must be between 1 and 20 UTF-8 bytes).
    ///   - targetRecipients: Optional explicit recipient initials list. If nil, defaults to active group roster.
    /// - Returns: Created `ChatMessage` in `.forwardedToNextHop` state.
    /// - Throws: `ChatEngineError` on validation, battery cutoff, cooldown, or cryptographic failure.
    @discardableResult
    public func sendMessage(
        text: String,
        targetRecipients: [String]? = nil
    ) async throws -> ChatMessage {
        // 1. Session verification
        guard let session = sessionProvider?() else {
            throw ChatEngineError.noActiveSession
        }
        
        // 2. Battery & Survival Mode verification (Requirement 10)
        guard currentBatteryLevel >= 0.20 && !isLowPowerMode && !isSurvivalMode else {
            throw ChatEngineError.batteryThrottled(batteryLevel: currentBatteryLevel)
        }
        
        // 3. 3-Second Cooldown verification (Requirement 5)
        let now = clock.now()
        let elapsedSinceLast = now.timeIntervalSince(lastSentTimestamp)
        if elapsedSinceLast < timingConfig.chatUserCooldown {
            let remaining = timingConfig.chatUserCooldown - elapsedSinceLast
            throw ChatEngineError.cooldownActive(remainingSeconds: remaining)
        }
        
        // 4. Text validation (1..20 UTF-8 bytes)
        let rawUtf8 = Array(text.utf8)
        guard !rawUtf8.isEmpty && rawUtf8.count <= ChatMessagePayload.maxTextBytes else {
            throw ChatEngineError.invalidTextLength(rawUtf8.count)
        }
        
        // 5. Intended Recipients Resolution (Requirement 6)
        let resolvedRecipients: [String]
        if let explicit = targetRecipients {
            resolvedRecipients = explicit.map { InitialsCodec.sanitize($0) }.filter { $0 != session.localInitials }
        } else if let provider = recipientsProvider {
            let recipients = await provider()
            resolvedRecipients = recipients.map { InitialsCodec.sanitize($0) }.filter { $0 != session.localInitials }
        } else {
            resolvedRecipients = []
        }
        
        // 6. Sequence Number Generation
        let seq = (UInt32(session.memberSlot) << 24) | (monotonicCounter & 0x00FFFFFF)
        monotonicCounter &+= 1
        
        // 7. Payload Serialization
        let payload = ChatMessagePayload(
            senderInitials: session.localInitials,
            timestamp: now,
            text: text
        )
        guard let payloadData = try? payload.serialize() else {
            throw ChatEngineError.serializationFailed
        }
        
        // 8. Envelope Construction & Cryptographic Sealing (Requirement 1)
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .chatMessage,
            hopLimit: PacketConstants.chatHopLimit,
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: seq
        )
        
        let symmetricKey = SymmetricKey(data: session.symmetricKeyData)
        let (ciphertext, authTag): (Data, Data)
        do {
            (ciphertext, authTag) = try await cryptoService.seal(
                payload: payloadData,
                envelope: envelope,
                using: symmetricKey
            )
        } catch {
            throw ChatEngineError.encryptionFailed(error.localizedDescription)
        }
        
        let rawWirePacket = RawWirePacket(
            envelope: envelope,
            ciphertext: ciphertext,
            authTag: authTag
        )
        
        let wireData: Data
        do {
            wireData = try rawWirePacket.toWireData()
        } catch {
            throw ChatEngineError.serializationFailed
        }
        
        // 9. Initial In-Memory Message Model (Requirement 8 & 9)
        var initialRecipientStates: [String: RecipientDeliveryState] = [:]
        for recipient in resolvedRecipients {
            initialRecipientStates[recipient] = .locallyAccepted
        }
        
        var message = ChatMessage(
            id: UUID(),
            sequenceNumber: seq,
            senderInitials: session.localInitials,
            text: text,
            timestamp: now,
            confirmedResponders: [],
            recipientStates: initialRecipientStates,
            deliveryState: .locallyAccepted,
            isLocalSender: true
        )
        
        // Record in in-memory message history (strictly in-memory, no persistence)
        appendMessage(message)
        lastSentTimestamp = now
        
        // 10. Radio Transmission & Transition to Forwarded
        message.deliveryState = .forwardedToNextHop
        for recipient in resolvedRecipients {
            initialRecipientStates[recipient] = .forwardedToNextHop
        }
        message.recipientStates = initialRecipientStates
        updateMessage(message)
        
        // Submit to transport outbox (FIFO Tier 3, ahead of stranger relays)
        try await transport.broadcastFrame(wireData)
        
        // 11. Register in-flight message for ACK tracking & retries (Requirement 5 & 6)
        let inFlight = InFlightMessage(
            message: message,
            rawWirePacket: rawWirePacket,
            wireData: wireData,
            attemptCount: 1,
            maxRetries: timingConfig.chatMaxRetries,
            lastSentAt: now
        )
        inFlightMessages[seq] = inFlight
        
        return message
    }
    
    // MARK: - Inbound Packet Ingestion Pipeline
    
    /// Ingests, validates, and processes an inbound wire packet.
    /// Supports direct peer reception and blind stranger relay forwarding.
    public func handleInboundWirePacket(
        _ wireData: Data,
        fromPeerId: String,
        receivedRssi: Int8? = nil
    ) async throws -> InboundChatOutcome {
        // 1. Strict size check
        guard wireData.count == PacketConstants.wirePacketSize else {
            return .droppedMalformed
        }
        
        let rawPacket: RawWirePacket
        do {
            rawPacket = try RawWirePacket.fromWireData(wireData)
        } catch {
            return .droppedMalformed
        }
        
        return try await handleInboundPacket(
            rawPacket: rawPacket,
            wireData: wireData,
            fromPeerId: fromPeerId,
            receivedRssi: receivedRssi
        )
    }
    
    /// Ingests an inbound `InboundPacket` struct.
    public func handleInboundPacket(_ inbound: InboundPacket) async throws -> InboundChatOutcome {
        let wireData = try inbound.rawPacket.toWireData()
        return try await handleInboundPacket(
            rawPacket: inbound.rawPacket,
            wireData: wireData,
            fromPeerId: inbound.sourcePeerId,
            receivedRssi: inbound.receivedRssi
        )
    }
    
    private func handleInboundPacket(
        rawPacket: RawWirePacket,
        wireData: Data,
        fromPeerId: String,
        receivedRssi: Int8? = nil
    ) async throws -> InboundChatOutcome {
        let envelope = rawPacket.envelope
        
        // Verify protocol version
        guard envelope.version == PacketConstants.protocolVersion else {
            return .droppedMalformed
        }
        
        // Hop count enforcement (Requirement 2: Max 8 hops)
        guard envelope.hopCount <= envelope.hopLimit else {
            return .droppedHopLimitExceeded
        }
        
        let activeSession = sessionProvider?()
        
        // 2. Stranger Packet Relaying (Requirement 3: Zero-Knowledge Blind Relaying)
        if let session = activeSession, envelope.sessionId != session.sessionId {
            guard envelope.hopCount < envelope.hopLimit else { return .droppedHopLimitExceeded }
            // Stranger packet! Verify relay policy and battery cutoff (<20%)
            guard currentBatteryLevel >= 0.20 && !isLowPowerMode && !isSurvivalMode else {
                return .droppedPolicyDisabled
            }
            
            // Rate limiter check for ordinary relay traffic
            if let limiter = rateLimiter {
                let permitted = await limiter.consumeOrdinaryToken()
                guard permitted else {
                    return .droppedPolicyDisabled
                }
            }
            
            // Deduplication suppression (Requirement 4)
            let packetKey = PacketKey(wirePacket: rawPacket)
            let isDuplicate = await seenPacketCache.isDuplicateAndRecord(packetKey, now: clock.now())
            if isDuplicate {
                return .droppedDuplicate(sequenceNumber: envelope.sequenceNumber)
            }
            
            // Mutate hopCount (+1) preserving Poly1305 MAC tag via AAD masking
            var mutatedData = wireData
            mutatedData[mutatedData.startIndex + 2] = envelope.hopCount + 1
            
            // Blind forward across mesh (never decrypt or display)
            try await forwardOpaquePacket(mutatedData, exceptPeerId: fromPeerId)
            return .relayedStranger(sessionId: envelope.sessionId, hopCount: envelope.hopCount + 1)
        }
        
        // 3. Local Group Session Ingestion
        guard let session = activeSession, envelope.sessionId == session.sessionId else {
            return .droppedSecurityFailed
        }
        
        if envelope.type == .ack {
            // Process delivery acknowledgement
            let processed = await processDeliveryACK(rawPacket: rawPacket, fromPeerId: fromPeerId)
            if processed {
                let decrypted = try? await decryptPayload(rawPacket: rawPacket)
                let ackPayload = decrypted.flatMap { try? ACKPayload.deserialize(from: $0) }
                let responder = ackPayload?.responderInitials ?? fromPeerId
                return .ackProcessed(sequenceNumber: envelope.sequenceNumber, responderInitials: responder, isDelivered: true)
            }
            if envelope.hopCount < envelope.hopLimit {
                var mutatedData = wireData
                mutatedData[mutatedData.startIndex + 2] = envelope.hopCount + 1
                try await forwardOpaquePacket(mutatedData, exceptPeerId: fromPeerId)
            }
            return .droppedMalformed
        }
        
        guard envelope.type == .chatMessage else {
            return .droppedMalformed
        }
        
        // 4. Cryptographic Authentication & Decryption (Requirement 1)
        let symmetricKey = SymmetricKey(data: session.symmetricKeyData)
        let decrypted: Data
        do {
            decrypted = try await cryptoService.open(
                ciphertext: rawPacket.ciphertext,
                envelope: envelope,
                authTag: rawPacket.authTag,
                using: symmetricKey
            )
        } catch {
            return .droppedSecurityFailed
        }
        
        // Deserialization & validation
        guard let payload = try? ChatMessagePayload.deserialize(from: decrypted) else {
            return .droppedMalformed
        }
        
        guard payload.senderInitials != session.localInitials else {
            return .droppedSelfEcho
        }
        
        guard abs(clock.now().timeIntervalSince(payload.timestamp)) <= CarryMessageStore.retention else {
            return .droppedMalformed
        }

        // Duplicate suppression (Requirement 4)
        let packetKey = PacketKey(wirePacket: rawPacket)
        let isDuplicate = await seenPacketCache.isDuplicateAndRecord(packetKey, now: clock.now())
        if isDuplicate || seenChatSequences.contains(envelope.sequenceNumber) {
            // The first ACK may have been lost. Confirm authenticated receipt again,
            // without adding another message or forwarding the chat again.
            try await sendDeliveryACK(for: rawPacket, senderInitials: payload.senderInitials,
                receivedRssi: receivedRssi ?? -70)
            return .droppedDuplicate(sequenceNumber: envelope.sequenceNumber)
        }
        seenChatSequences.insert(envelope.sequenceNumber)
        if seenChatSequences.count > 1000 {
            seenChatSequences.removeAll()
        }

        // 5. In-Memory Message Display (Requirement 9: In-Memory Only, Zero Persistence)
        let message = ChatMessage(
            sequenceNumber: envelope.sequenceNumber,
            senderInitials: payload.senderInitials,
            text: payload.text,
            timestamp: payload.timestamp,
            confirmedResponders: [session.localInitials],
            recipientStates: [:],
            deliveryState: .delivered(confirmedCount: 1, totalRecipients: 1),
            isLocalSender: false
        )
        appendMessage(message)
        
        // 6. Return Delivery ACK Dispatch (Requirement 6 & 7)
        try await sendDeliveryACK(
            for: rawPacket,
            senderInitials: payload.senderInitials,
            receivedRssi: receivedRssi ?? -70
        )
        
        // 7. Multi-Hop Forwarding if hops remain (Requirement 2)
        if envelope.hopCount < envelope.hopLimit {
            var mutatedData = wireData
            mutatedData[mutatedData.startIndex + 2] = envelope.hopCount + 1
            try await forwardOpaquePacket(mutatedData, exceptPeerId: fromPeerId)
            return .deliveredLocallyAndRelayed(message: message, nextHopCount: envelope.hopCount + 1)
        }
        
        return .deliveredLocally(message: message)
    }
    
    // MARK: - Delivery ACK Dispatching & Ingestion
    
    /// Generates and transmits an authenticated ACK back to the message sender across the mesh.
    public func sendDeliveryACK(
        for originalPacket: RawWirePacket,
        senderInitials: String,
        receivedRssi: Int8
    ) async throws {
        guard let session = sessionProvider?() else { return }
        let now = clock.now()
        
        let ackPayload = ACKPayload(
            ackedSeqNumber: originalPacket.envelope.sequenceNumber,
            ackedSenderInitials: senderInitials,
            ackTimestamp: now,
            ackStatus: .deliveredToFriend,
            receivedRssi: receivedRssi,
            originalEventId: originalPacket.envelope.sequenceNumber,
            responderInitials: session.localInitials
        )
        let payloadData = ackPayload.serialize()
        
        let ackSeq = (UInt32(session.memberSlot) << 24) | (monotonicCounter & 0x00FFFFFF)
        monotonicCounter &+= 1
        
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .ack,
            hopLimit: PacketConstants.chatHopLimit,
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: ackSeq
        )
        
        let key = SymmetricKey(data: session.symmetricKeyData)
        let (ciphertext, authTag) = try await cryptoService.seal(
            payload: payloadData,
            envelope: envelope,
            using: key
        )
        let rawAck = RawWirePacket(
            envelope: envelope,
            ciphertext: ciphertext,
            authTag: authTag
        )
        let wireData = try rawAck.toWireData()
        
        // Broadcast ACK across direct neighbors to find route back to originator
        try await transport.broadcastFrame(wireData)
    }
    
    /// Generates an intermediary relay ACK when forwarding for a multi-hop friend.
    public func sendRelayACK(
        for originalPacket: RawWirePacket,
        senderInitials: String,
        receivedRssi: Int8
    ) async throws {
        guard let session = sessionProvider?() else { return }
        let now = clock.now()
        
        let ackPayload = ACKPayload(
            ackedSeqNumber: originalPacket.envelope.sequenceNumber,
            ackedSenderInitials: senderInitials,
            ackTimestamp: now,
            ackStatus: .relayedByMeshHop,
            receivedRssi: receivedRssi,
            originalEventId: originalPacket.envelope.sequenceNumber,
            responderInitials: session.localInitials
        )
        let payloadData = ackPayload.serialize()
        
        let ackSeq = (UInt32(session.memberSlot) << 24) | (monotonicCounter & 0x00FFFFFF)
        monotonicCounter &+= 1
        
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .ack,
            hopLimit: PacketConstants.chatHopLimit,
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: ackSeq
        )
        
        let key = SymmetricKey(data: session.symmetricKeyData)
        let (ciphertext, authTag) = try await cryptoService.seal(
            payload: payloadData,
            envelope: envelope,
            using: key
        )
        let rawAck = RawWirePacket(
            envelope: envelope,
            ciphertext: ciphertext,
            authTag: authTag
        )
        let wireData = try rawAck.toWireData()
        try await transport.broadcastFrame(wireData)
    }
    
    /// Processes an incoming delivery ACK.
    ///
    /// Implements Requirement 6 & 7:
    /// - Tracks ACK and delivery state separately for each intended recipient.
    /// - Never treats a relay ACK (`0x02`) as final recipient delivery (`0x01`).
    public func processDeliveryACK(rawPacket: RawWirePacket, fromPeerId: String) async -> Bool {
        guard rawPacket.envelope.type == .ack else { return false }
        guard let session = sessionProvider?(), rawPacket.envelope.sessionId == session.sessionId else {
            return false
        }
        
        let decrypted: Data
        do {
            decrypted = try await decryptPayload(rawPacket: rawPacket)
        } catch {
            return false
        }
        
        guard let ack = try? ACKPayload.deserialize(from: decrypted) else {
            return false
        }
        
        // Verify this ACK was intended for our local device
        guard ack.ackedSenderInitials == session.localInitials else {
            return false
        }
        
        let seq = ack.ackedSeqNumber
        guard let idx = inMemoryMessages.firstIndex(where: { $0.sequenceNumber == seq && $0.isLocalSender }) else {
            return false
        }
        
        var message = inMemoryMessages[idx]
        let responder = ack.responderInitials
        
        if ack.ackStatus == .relayedByMeshHop {
            // Intermediate Mesh Relay Hop Confirmed!
            // Requirement 7: Never treat a relay ACK as final recipient delivery!
            if message.deliveryState == .locallyAccepted || message.deliveryState == .forwardedToNextHop {
                message.deliveryState = .relayedByMesh(hopCount: rawPacket.envelope.hopCount)
            }
            
            // Mark individual recipient state as relayed by mesh without marking delivered
            if let current = message.recipientStates[responder], !current.isDelivered {
                message.recipientStates[responder] = .relayedByMesh(hops: rawPacket.envelope.hopCount, relayPeerId: fromPeerId)
            } else if message.recipientStates[responder] == nil {
                for (rec, state) in message.recipientStates where !state.isDelivered {
                    message.recipientStates[rec] = .relayedByMesh(hops: rawPacket.envelope.hopCount, relayPeerId: fromPeerId)
                }
            }
            
            inMemoryMessages[idx] = message
            if var inFlight = inFlightMessages[seq] {
                inFlight.message = message
                inFlightMessages[seq] = inFlight
            }
            notifyMessageUpdated(message)
            return true
            
        } else if ack.ackStatus == .deliveredToFriend {
            // Final Intended Recipient Confirmed Delivery!
            message.confirmedResponders.insert(responder)
            message.recipientStates[responder] = .deliveredToRecipient(
                timestamp: ack.ackTimestamp,
                rssi: ack.receivedRssi
            )
            
            let total = message.totalRecipientCount
            let confirmed = message.confirmedRecipientCount
            message.deliveryState = .delivered(confirmedCount: confirmed, totalRecipients: total)
            
            inMemoryMessages[idx] = message
            if confirmed >= total {
                // All recipients have confirmed delivery
                inFlightMessages.removeValue(forKey: seq)
            } else if var inFlight = inFlightMessages[seq] {
                inFlight.message = message
                inFlightMessages[seq] = inFlight
            }
            notifyMessageUpdated(message)
            return true
        }
        
        return false
    }
    
    // MARK: - Retries & Timeout Evaluation (Deterministic Test Support)
    
    /// Evaluates in-flight messages against retry delays and ACK timeouts.
    /// Supports deterministic testing when invoked after advancing a `MeshClock`.
    public func evaluateTimeoutsAndRetries() async {
        let now = clock.now()
        
        for (seq, var inFlight) in inFlightMessages {
            // 1. Check if all intended recipients have already confirmed
            let unconfirmedRecipients = inFlight.message.recipientStates.filter { !$0.value.isDelivered }
            if inFlight.message.recipientStates.isEmpty && inFlight.message.deliveryState.isDelivered {
                inFlightMessages.removeValue(forKey: seq)
                continue
            }
            
            // 2. Check 15-Second Delivery Timeout Window (Requirement 8)
            if now.timeIntervalSince(inFlight.message.timestamp) >= timingConfig.chatAckTimeout {
                var message = inFlight.message
                for (rec, state) in message.recipientStates where !state.isDelivered {
                    message.recipientStates[rec] = .deliveryTimedOut
                }
                
                if message.confirmedRecipientCount == 0 {
                    message.deliveryState = .deliveryTimedOut
                } else if message.confirmedRecipientCount < message.totalRecipientCount {
                    message.deliveryState = .deliveryTimedOut
                }
                
                updateMessage(message)
                inFlightMessages.removeValue(forKey: seq)
                continue
            }
            
            // 3. Check Transmission Retries (Max 2 retries, 3 total attempts, 0.5s backoff)
            if unconfirmedRecipients.count > 0 || inFlight.message.recipientStates.isEmpty {
                if inFlight.attemptCount < inFlight.maxRetries + 1 {
                    if now.timeIntervalSince(inFlight.lastSentAt) >= timingConfig.chatRetryBackoff {
                        inFlight.attemptCount += 1
                        inFlight.lastSentAt = now
                        inFlightMessages[seq] = inFlight
                        
                        // Retransmit frame across radio
                        try? await transport.broadcastFrame(inFlight.wireData)
                    }
                }
            }
        }
    }
    
    // MARK: - Ephemeral History & Querying (Requirement 9)
    
    /// Returns the active in-memory message history (up to 50 latest messages).
    public func activeMessages() -> [ChatMessage] {
        inMemoryMessages
    }
    
    /// Finds a message by sequence counter.
    public func message(withSequenceNumber seq: UInt32) -> ChatMessage? {
        inMemoryMessages.first(where: { $0.sequenceNumber == seq })
    }
    
    /// Clears all in-memory chat history and in-flight tracking on group session teardown.
    public func clearHistory() {
        retrySupervisorTask?.cancel()
        retrySupervisorTask = nil
        inMemoryMessages.removeAll()
        inFlightMessages.removeAll()
        seenChatSequences.removeAll()
    }
    
    // MARK: - Private Helpers
    
    private func appendMessage(_ message: ChatMessage) {
        inMemoryMessages.append(message)
        if inMemoryMessages.count > maxHistoryCount {
            inMemoryMessages.removeFirst(inMemoryMessages.count - maxHistoryCount)
        }
        notifyMessageUpdated(message)
    }
    
    private func updateMessage(_ message: ChatMessage) {
        if let idx = inMemoryMessages.firstIndex(where: { $0.sequenceNumber == message.sequenceNumber }) {
            inMemoryMessages[idx] = message
        }
        notifyMessageUpdated(message)
    }
    
    private func notifyMessageUpdated(_ message: ChatMessage) {
        messageUpdateContinuation?.yield(message)
        onMessageUpdated?(message)
    }
    
    private func decryptPayload(rawPacket: RawWirePacket) async throws -> Data {
        guard let session = sessionProvider?() else {
            throw ChatEngineError.noActiveSession
        }
        let symmetricKey = SymmetricKey(data: session.symmetricKeyData)
        return try await cryptoService.open(
            ciphertext: rawPacket.ciphertext,
            envelope: rawPacket.envelope,
            authTag: rawPacket.authTag,
            using: symmetricKey
        )
    }
    
    private func forwardOpaquePacket(_ wireData: Data, exceptPeerId: String?) async throws {
        if let neighbors = neighborTable {
            let active = await neighbors.activeNeighbors()
            let targets = active.filter { $0.id != exceptPeerId }
            for peer in targets {
                _ = try? await transport.sendFrame(wireData, to: peer.id)
            }
        } else {
            try? await transport.broadcastFrame(wireData)
        }
    }
}
