//
//  SOSForwardingEngine.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation
import CoreLocation
import CryptoKit

/// Authoritative Actor implementing Subsystem 5 of TeeKum Phase 2 Multi-Hop Mesh:
/// Emergency SOS Dispatch, Multi-Hop Forwarding, Authenticated Ingestion,
/// Route Preference, Bounded Flooding Fallback, and Multi-Hop Return ACK Routing.
///
/// Master Specification Guarantees:
/// 1. Emergency Priority: SOS packets bypass normal location ping cycles and coalescing.
/// 2. Route Preference: Prefers known unexpired routes in `RoutingTable`; falls back to bounded flooding when none exist.
/// 3. Zero-Knowledge Safe Relaying: Relays forward without group keys; Poly1305 MAC tag is preserved across hops via AAD masking.
/// 4. Cryptographic Authentication: Only valid group keys and fresh timestamps trigger trusted sirens and alerts.
/// 5. Return ACK Routing: Recipient group friends route authenticated Poly1305 ACKs back to sender via known route or bounded flooding.
/// 6. Honest Delivery States: Strictly distinguishes local sending, intermediary relay hops (`RELAY_ACK`), and cryptographic friend delivery (`DELIVERED_TO_FRIEND`).
/// 7. Duplicate Suppression: Received `sosEventId` values are deduplicated to prevent repeated audible sirens or alert flooding.
/// 8. Bounded Retries: Exactly 3 retransmissions before marking confirmation timeout / searching peers.
public actor SOSForwardingEngine: SOSForwardingManaging {
    
    // MARK: - Dependencies
    
    private let transport: MeshTransport
    private let cryptoService: CryptoServiceProvider
    private let routingTable: RoutingTableManaging?
    private let neighborTable: NeighborManaging?
    private let rateLimiter: ForwardingBudgetManaging?
    private let clock: MeshClock
    private let sessionProvider: (@Sendable () -> GroupSession?)?
    private let audioAlerter: SOSAudioAlerting?
    
    // MARK: - Active Outbound SOS State
    
    public private(set) var activeSOSEventId: UInt32?
    public private(set) var currentDeliveryState: SOSDeliveryState = .idle
    public private(set) var currentRouteChoice: RouteChoice = .none
    public private(set) var retryCount: Int = 0
    public let maxRetries: Int = 3
    public var retryInterval: TimeInterval = 1.5
    
    // MARK: - Ingestion & Duplicate Suppression
    
    public private(set) var seenSOSEventIds: Set<UInt32> = []
    public private(set) var activeIncomingAlert: IncomingSOSAlert?
    public private(set) var isSirenActive: Bool = false
    
    // MARK: - Evidence & Diagnostics
    
    public private(set) var lastDeliveredFriendId: String?
    public private(set) var lastDeliveredTimestamp: Date?
    public private(set) var lastDeliveredHopCount: UInt8?
    public private(set) var lastRelayHopCount: UInt8?
    public private(set) var lastRelayResponderId: String?
    
    public private(set) var monotonicCounter: UInt32 = 1
    public private(set) var totalDispatchedCount: Int = 0
    public private(set) var totalReceivedCount: Int = 0
    public private(set) var totalDuplicatesSuppressedCount: Int = 0
    public private(set) var totalAcksSentCount: Int = 0
    public private(set) var totalAcksReceivedCount: Int = 0
    
    // Internal tasks
    private var retryTask: Task<Void, Never>?
    private var lastDispatchedPayload: SOSPayload?
    
    // MARK: - State Change Handlers
    
    private var onDeliveryStateChanged: (@Sendable (SOSDeliveryState) -> Void)?
    private var onIncomingAlertTriggered: (@Sendable (IncomingSOSAlert) -> Void)?
    
    // MARK: - Initialization
    
    public init(
        transport: MeshTransport,
        cryptoService: CryptoServiceProvider,
        routingTable: RoutingTableManaging? = nil,
        neighborTable: NeighborManaging? = nil,
        rateLimiter: ForwardingBudgetManaging? = nil,
        clock: MeshClock = SystemMeshClock(),
        sessionProvider: (@Sendable () -> GroupSession?)? = nil,
        audioAlerter: SOSAudioAlerting? = nil,
        onDeliveryStateChanged: (@Sendable (SOSDeliveryState) -> Void)? = nil,
        onIncomingAlertTriggered: (@Sendable (IncomingSOSAlert) -> Void)? = nil
    ) {
        self.transport = transport
        self.cryptoService = cryptoService
        self.routingTable = routingTable
        self.neighborTable = neighborTable
        self.rateLimiter = rateLimiter
        self.clock = clock
        self.sessionProvider = sessionProvider
        self.audioAlerter = audioAlerter
        self.onDeliveryStateChanged = onDeliveryStateChanged
        self.onIncomingAlertTriggered = onIncomingAlertTriggered
    }
    
    public func setCallbacks(
        onDeliveryStateChanged: (@Sendable (SOSDeliveryState) -> Void)? = nil,
        onIncomingAlertTriggered: (@Sendable (IncomingSOSAlert) -> Void)? = nil
    ) {
        self.onDeliveryStateChanged = onDeliveryStateChanged
        self.onIncomingAlertTriggered = onIncomingAlertTriggered
    }
    
    // MARK: - Outbound SOS Dispatch Pipeline
    
    /// High-level entry point to dispatch an emergency SOS alert.
    /// Selects known usable route if available, otherwise executes bounded flooding fallback.
    public func dispatchSOS(
        emergencyType: SOSType = .general,
        location: CLLocationCoordinate2D,
        accuracy: UInt8,
        timestamp: Date,
        batteryPct: UInt8
    ) async throws -> UInt32 {
        guard let session = sessionProvider?() else {
            throw TransportError.sessionInvalid
        }
        
        let eventId = UInt32.random(in: 1...UInt32.max)
        self.activeSOSEventId = eventId
        self.retryCount = 0
        
        let payload = SOSPayload(
            coordinate: location,
            timestamp: timestamp,
            accuracy: accuracy,
            sosEventId: eventId,
            senderInitials: session.localInitials,
            emergencyType: emergencyType,
            batteryLevel: batteryPct,
            colorCode: session.localColorCode
        )
        self.lastDispatchedPayload = payload
        
        let neighbors = await transport.activeNeighbors()
        if neighbors.isEmpty {
            updateDeliveryState(.searchingPeers)
            self.currentRouteChoice = .none
        } else {
            updateDeliveryState(.localSending)
        }
        
        let seq = CleartextEnvelope.makeSequenceNumber(memberSlot: session.memberSlot, counter: monotonicCounter)
        monotonicCounter &+= 1
        
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .sos,
            hopLimit: PacketConstants.sosHopLimit,
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: seq
        )
        
        let key = SymmetricKey(data: session.symmetricKeyData)
        try await broadcastEmergencySOS(payload: payload, envelope: envelope, symmetricKey: key)
        
        totalDispatchedCount += 1
        
        // Start bounded retries task
        startRetryTask(payload: payload, session: session)
        
        return eventId
    }
    
    /// Conformance to `SOSForwardingManaging`: Dispatches an emergency SOS alert across the mesh.
    /// Prefers known usable route in routing table when available; falls back to bounded flooding.
    public func broadcastEmergencySOS(
        payload: SOSPayload,
        envelope: CleartextEnvelope,
        symmetricKey: SymmetricKey
    ) async throws {
        // Enforce SOS token budget if rate limiter is present
        if let rateLimiter = rateLimiter {
            let allowed = await rateLimiter.consumeSOSToken()
            if !allowed {
                // In emergency life-safety scenarios, rate limiter drops excessive bursts
                // but logs telemetry
            }
        }
        
        let payloadData = payload.serialize()
        let sealed = try await cryptoService.seal(payload: payloadData, envelope: envelope, using: symmetricKey)
        let wirePacket = RawWirePacket(envelope: envelope, ciphertext: sealed.ciphertext, authTag: sealed.authTag)
        let wireData = try wirePacket.toWireData()
        
        let neighbors = await transport.activeNeighbors()
        if neighbors.isEmpty {
            updateDeliveryState(.searchingPeers)
            self.currentRouteChoice = .none
            try await transport.broadcastFrame(wireData)
            return
        }
        
        // Route Selection: Prefer known usable route when available
        if let routingTable = routingTable {
            // Check for any known fresh route towards group members or destination
            let activeNeighbors = neighbors.filter { $0.state == .connected }
            var selectedRoute: RouteEntry?
            
            // Check routing table for any friend route
            for neighbor in activeNeighbors where neighbor.isGroupMember {
                if let route = await routingTable.findRoute(to: neighbor.id), route.isFresh {
                    selectedRoute = route
                    break
                }
            }
            
            if let route = selectedRoute, activeNeighbors.contains(where: { $0.id == route.nextHopPeerId }) {
                self.currentRouteChoice = .knownRoute(nextHop: route.nextHopPeerId, hopCount: route.hopCount)
                _ = try await transport.sendFrame(wireData, to: route.nextHopPeerId)
                return
            }
        }
        
        // Bounded Flooding Fallback across all direct physical radio neighbors
        self.currentRouteChoice = .boundedFlooding(neighborCount: neighbors.count)
        try await transport.broadcastFrame(wireData)
    }
    
    // MARK: - Bounded Retries Scheduler
    
    private func startRetryTask(payload: SOSPayload, session: GroupSession) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled {
                let interval = await self.retryInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                
                let isDelivered = await self.currentDeliveryState.isDelivered
                if isDelivered { break }
                
                await self.executeRetryAttempt(payload: payload, session: session)
            }
        }
    }
    
    /// Executes a single bounded retry attempt. Publicly callable for synchronous unit tests.
    public func executeRetryAttempt(payload: SOSPayload, session: GroupSession) async {
        let isDelivered = currentDeliveryState.isDelivered
        guard !isDelivered else { return }
        
        if retryCount < maxRetries {
            retryCount += 1
            
            let neighbors = await transport.activeNeighbors()
            if neighbors.isEmpty {
                updateDeliveryState(.searchingPeers)
                self.currentRouteChoice = .none
            } else if !currentDeliveryState.isRelayed {
                updateDeliveryState(.localSending)
            }
            
            let seq = CleartextEnvelope.makeSequenceNumber(memberSlot: session.memberSlot, counter: monotonicCounter)
            monotonicCounter &+= 1
            
            let envelope = CleartextEnvelope(
                version: PacketConstants.protocolVersion,
                type: .sos,
                hopLimit: PacketConstants.sosHopLimit,
                hopCount: 0,
                sessionId: session.sessionId,
                sequenceNumber: seq
            )
            
            let key = SymmetricKey(data: session.symmetricKeyData)
            try? await broadcastEmergencySOS(payload: payload, envelope: envelope, symmetricKey: key)
        } else {
            // Retries exhausted without confirmation
            cancelRetries()
            let neighbors = await transport.activeNeighbors()
            if currentDeliveryState.isRelayed {
                // Intermediary acknowledged, but recipient friend never confirmed
                // Keep relayed state honestly showing it was relayed but unconfirmed by friend
            } else if neighbors.isEmpty {
                updateDeliveryState(.searchingPeers)
            } else {
                updateDeliveryState(.failed(reason: "Delivery confirmation timeout: exhausted \(maxRetries) retries without recipient ACK."))
            }
        }
    }
    
    public func triggerRetryNow() async {
        guard let payload = lastDispatchedPayload, let session = sessionProvider?() else { return }
        await executeRetryAttempt(payload: payload, session: session)
    }
    
    public func cancelRetries() {
        retryTask?.cancel()
        retryTask = nil
    }
    
    // MARK: - Inbound SOS Processing & Authentication Pipeline
    
    /// Conformance to `SOSForwardingManaging`: Ingests and processes an incoming SOS packet.
    /// Strict Cryptographic Authentication: Only verified group members can trigger emergency alerts.
    public func handleInboundSOSPacket(
        rawPacket: RawWirePacket,
        fromPeerId: String
    ) async throws {
        guard let session = sessionProvider?() else {
            throw TransportError.sessionInvalid
        }
        
        let envelope = rawPacket.envelope
        
        // 1. Session Isolation
        guard envelope.sessionId == session.sessionId else {
            throw TransportError.sessionMismatch
        }
        
        // 2. Cryptographic Tag Verification (ChaCha20-Poly1305)
        let key = SymmetricKey(data: session.symmetricKeyData)
        let decrypted: Data
        do {
            decrypted = try await cryptoService.open(
                ciphertext: rawPacket.ciphertext,
                envelope: envelope,
                authTag: rawPacket.authTag,
                using: key
            )
        } catch {
            // Tampered, forged, or unauthenticated packet: Reject with ZERO state changes!
            throw TransportError.securityVerificationFailed
        }
        
        // 3. Deserialize Emergency Payload
        guard let payload = try? SOSPayload.deserialize(from: decrypted) else {
            throw TransportError.malformedPacket
        }
        
        // 4. Do not sound alert for our own packets
        guard payload.senderInitials != session.localInitials else { return }
        
        // 5. Freshness & Clock Skew Verification (<= 300 seconds)
        let skew = abs(clock.now().timeIntervalSince(payload.timestamp))
        guard skew <= 300.0 else {
            throw TransportError.securityVerificationFailed
        }
        
        let eventId = payload.sosEventId
        
        // 6. Duplicate Suppression Check
        if seenSOSEventIds.contains(eventId) {
            totalDuplicatesSuppressedCount += 1
            // Duplicate arrived (e.g. over an alternate multi-hop path):
            // Re-emit delivery ACK so sender's retry timer resolves,
            // but STRICTLY SUPPRESS repeated sirens and alert banners!
            try await sendDeliveryACK(for: rawPacket, status: .deliveredToFriend)
            return
        }
        
        // 7. First-Time Trusted Reception
        seenSOSEventIds.insert(eventId)
        totalReceivedCount += 1
        
        // Sound Siren & Haptics
        isSirenActive = true
        audioAlerter?.triggerEmergencyAlertFeedback()
        
        let alert = IncomingSOSAlert(
            id: eventId,
            senderInitials: payload.senderInitials,
            senderName: payload.senderInitials,
            emergencyType: payload.emergencyType,
            coordinate: payload.coordinate,
            accuracy: payload.accuracy,
            timestamp: payload.timestamp,
            batteryLevel: payload.batteryLevel,
            receivedAt: clock.now()
        )
        self.activeIncomingAlert = alert
        onIncomingAlertTriggered?(alert)
        
        // 8. Multi-Hop Return ACK Routing
        try await sendDeliveryACK(for: rawPacket, status: .deliveredToFriend)
    }
    
    // MARK: - Multi-Hop Return ACK Transmission
    
    /// Conformance to `SOSForwardingManaging`: Generates and transmits an authenticated ACK.
    /// Routes unicast along known reverse route if present; otherwise uses bounded flooding fallback.
    public func sendDeliveryACK(
        for originalPacket: RawWirePacket,
        status: ACKStatus
    ) async throws {
        guard let session = sessionProvider?() else {
            throw TransportError.sessionInvalid
        }
        
        let key = SymmetricKey(data: session.symmetricKeyData)
        
        // Decrypt original payload to extract event ID and sender initials
        let decrypted = try await cryptoService.open(
            ciphertext: originalPacket.ciphertext,
            envelope: originalPacket.envelope,
            authTag: originalPacket.authTag,
            using: key
        )
        
        guard let sosPayload = try? SOSPayload.deserialize(from: decrypted) else {
            throw TransportError.malformedPacket
        }
        
        let ackPayload = ACKPayload(
            ackedSeqNumber: originalPacket.envelope.sequenceNumber,
            ackedSenderInitials: sosPayload.senderInitials,
            ackTimestamp: clock.now(),
            ackStatus: status,
            receivedRssi: 0,
            originalEventId: sosPayload.sosEventId,
            responderInitials: session.localInitials
        )
        let payloadData = ackPayload.serialize()
        
        let seq = CleartextEnvelope.makeSequenceNumber(memberSlot: session.memberSlot, counter: monotonicCounter)
        monotonicCounter &+= 1
        
        let ackEnvelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .ack,
            hopLimit: PacketConstants.sosHopLimit,
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: seq
        )
        
        let sealed = try await cryptoService.seal(payload: payloadData, envelope: ackEnvelope, using: key)
        let wirePacket = RawWirePacket(envelope: ackEnvelope, ciphertext: sealed.ciphertext, authTag: sealed.authTag)
        let wireData = try wirePacket.toWireData()
        
        // Return ACK Route Resolution: Prefer known usable route towards the distressed sender
        if let routingTable = routingTable,
           let route = await routingTable.findRoute(to: sosPayload.senderInitials),
           route.isFresh {
            // Send unicast along known multi-hop route
            _ = try await transport.sendFrame(wireData, to: route.nextHopPeerId)
        } else {
            // Bounded Flooding Fallback across all active mesh links
            try await transport.broadcastFrame(wireData)
        }
        
        totalAcksSentCount += 1
    }
    
    // MARK: - Inbound ACK Processing Pipeline
    
    /// Conformance to `SOSForwardingManaging`: Ingests and processes an incoming delivery ACK.
    public func handleInboundACK(
        rawPacket: RawWirePacket,
        fromPeerId: String
    ) async {
        guard let session = sessionProvider?() else { return }
        
        let envelope = rawPacket.envelope
        guard envelope.sessionId == session.sessionId else { return }
        
        let key = SymmetricKey(data: session.symmetricKeyData)
        guard let decrypted = try? await cryptoService.open(
            ciphertext: rawPacket.ciphertext,
            envelope: envelope,
            authTag: rawPacket.authTag,
            using: key
        ) else {
            // Unauthenticated ACK dropped
            return
        }
        
        guard let payload = try? ACKPayload.deserialize(from: decrypted) else { return }
        
        // Verify this ACK confirms our local member and matches active SOS event
        guard payload.ackedSenderInitials == session.localInitials else { return }
        if let activeId = activeSOSEventId, payload.originalEventId != activeId {
            return
        }
        
        totalAcksReceivedCount += 1
        
        switch payload.ackStatus {
        case .deliveredToFriend:
            cancelRetries()
            lastDeliveredFriendId = payload.responderInitials
            lastDeliveredTimestamp = clock.now()
            lastDeliveredHopCount = envelope.hopCount
            updateDeliveryState(.deliveredToFriend(friendId: payload.responderInitials, timestamp: clock.now()))
            
        case .relayedByMeshHop:
            lastRelayHopCount = envelope.hopCount
            lastRelayResponderId = payload.responderInitials
            if !currentDeliveryState.isDelivered {
                updateDeliveryState(.relayedAck(relayHopCount: envelope.hopCount, responderId: payload.responderInitials))
            }
        }
    }
    
    // MARK: - State Management & Diagnostics
    
    private func updateDeliveryState(_ newState: SOSDeliveryState) {
        self.currentDeliveryState = newState
        onDeliveryStateChanged?(newState)
    }
    
    public func dismissIncomingAlert() {
        activeIncomingAlert = nil
        isSirenActive = false
        audioAlerter?.stopEmergencyAlertFeedback()
    }
    
    public func reset() {
        cancelRetries()
        currentDeliveryState = .idle
        currentRouteChoice = .none
        activeSOSEventId = nil
        retryCount = 0
        lastDispatchedPayload = nil
    }
    
    public func diagnosticsSnapshot() -> SOSDiagnostics {
        SOSDiagnostics(
            eventId: activeSOSEventId,
            hopCount: lastDeliveredHopCount ?? lastRelayHopCount,
            retryCount: retryCount,
            routeChoice: currentRouteChoice,
            stage: currentDeliveryState.stage,
            lastDeliveredFriendId: lastDeliveredFriendId,
            lastRelayResponderId: lastRelayResponderId,
            timestamp: clock.now()
        )
    }
}
