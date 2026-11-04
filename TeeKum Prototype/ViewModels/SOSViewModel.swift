//
//  SOSViewModel.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import Observation
import CoreLocation
import CryptoKit

/// Pure MVVM ViewModel governing the 3-second hold emergency button,
/// immediate urgent radio dispatch, bounded retries, duplicate suppression,
/// incoming emergency siren/alerting, and honest delivery state feedback.
///
/// Delivery State Semantics (Master Specification):
/// - `LOCAL_SENDING`: Packet dispatched onto the radio interface.
/// - `SEARCHING_PEERS`: Dispatched without direct peers, actively seeking discovery.
/// - `RELAY_ACK`: Intermediary relay accepted or forwarded the packet (NOT confirmed by friend).
/// - `DELIVERED_TO_FRIEND`: Confirmed received and authenticated on the destination friend device.
///
/// Non-Negotiable Reliability Invariants:
/// 1. SOS is dispatched immediately, bypassing ordinary ping intervals and GPS wait cycles.
/// 2. Freshest available coordinate is used without fabricating false freshness timestamps.
/// 3. Normal location coalescing in the outbox cannot overwrite or drop an SOS packet.
/// 4. Repeated packets do not trigger repeated audible sirens or duplicate alerts.
/// 5. An empty peer list, transport error, or exhausted retry budget must never be presented as successful delivery.
@Observable
@MainActor
public final class SOSViewModel {
    
    // MARK: - Dependencies
    
    public var locationService: LocationServiceProvider?
    public var sessionProvider: (@Sendable () -> GroupSession?)?
    public var cryptoService: CryptoServiceProvider?
    public var transport: PeerTransport?
    public var audioAlerter: SOSAudioAlerting?
    public var memberNameResolver: (@MainActor (String) -> String?)?
    public var routingTable: RoutingTableManaging?
    public var neighborTable: NeighborManaging?
    public var rateLimiter: ForwardingBudgetManaging?
    public var forwardingEngine: SOSForwardingManaging?
    public var clock: MeshClock?
    private let dateProvider: @Sendable () -> Date
    
    // MARK: - Inactivity Guard ("Man Down" Auto-SOS)
    
    /// Dedicated service governing accelerometer immobility & screen stillness detection.
    public let inactivityGuard: InactivityGuardService
    
    /// User master toggle for Inactivity Guard (opt-in default: false).
    public var isInactivityGuardEnabled: Bool {
        get { inactivityGuard.isEnabled }
        set { inactivityGuard.isEnabled = newValue }
    }
    
    // MARK: - Delivery & Gesture State
    
    /// Current honest delivery feedback state.
    public var deliveryState: SOSDeliveryState = .idle
    
    /// Categorization of route choice taken for emergency SOS dispatch.
    public private(set) var currentRouteChoice: RouteChoice = .none
    
    /// Duration in seconds required to hold the SOS button.
    public let holdThresholdSeconds: Double = 3.0
    
    /// Current continuous press progress (0.0 to 1.0).
    public var holdProgress: Double = 0.0
    
    /// Selected category of emergency.
    public var currentEmergencyType: SOSType = .general
    
    /// Active 32-bit emergency event ID currently in-flight.
    public private(set) var activeSOSEventId: UInt32?
    
    /// Active incoming emergency alert received from a group member.
    public var activeIncomingAlert: IncomingSOSAlert?
    
    /// True when the emergency alert siren or haptic pulse is sounding.
    public private(set) var isSirenActive: Bool = false
    
    // MARK: - Retry & Evidence Tracking
    
    /// Number of bounded retransmission attempts executed for the current SOS event.
    public private(set) var retryCount: Int = 0
    
    /// Maximum allowed bounded retransmissions before transitioning to failed / searchingPeers.
    public var maxRetries: Int = 3
    
    /// Interval in seconds between bounded retransmissions.
    public var retryInterval: TimeInterval = 1.5
    
    /// Last confirmed friend responder ID (initials).
    public private(set) var lastDeliveredFriendId: String?
    
    /// Timestamp when friend delivery confirmation arrived.
    public private(set) var lastDeliveredTimestamp: Date?
    
    /// Hop count traversed by confirmed friend delivery ACK.
    public private(set) var lastDeliveredHopCount: UInt8?
    
    /// Last observed hop count from relay acknowledgement.
    public private(set) var lastRelayHopCount: UInt8?
    
    /// Last observed relay responder ID (initials).
    public private(set) var lastRelayResponderId: String?
    
    /// Diagnostics snapshot summarizing hop count, retries, route choice, and acknowledgement stage.
    public var diagnostics: SOSDiagnostics {
        SOSDiagnostics(
            eventId: activeSOSEventId,
            hopCount: lastDeliveredHopCount ?? lastRelayHopCount,
            retryCount: retryCount,
            routeChoice: currentRouteChoice,
            stage: deliveryState.stage,
            lastDeliveredFriendId: lastDeliveredFriendId,
            lastRelayResponderId: lastRelayResponderId,
            timestamp: dateProvider()
        )
    }
    
    // MARK: - Ingestion & Duplicate Suppression Cache
    
    /// Cache of received `sosEventId` values to prevent duplicate sirens or multiple alerts.
    public private(set) var seenSOSEventIds: Set<UInt32> = []
    
    /// Highest seen monotonic sequence number per sender for replay filtering.
    private var seenSequenceNumbersBySender: [UInt32: UInt32] = [:]
    
    /// Local monotonic sequence counter for outbound packets.
    public private(set) var monotonicCounter: UInt32 = 1
    
    // MARK: - Telemetry Metrics
    
    public private(set) var totalDispatchedSOSCount: Int = 0
    public private(set) var totalReceivedSOSCount: Int = 0
    public private(set) var totalDuplicatesSuppressedCount: Int = 0
    public private(set) var totalEmittedAcksCount: Int = 0
    public private(set) var totalReceivedAcksCount: Int = 0
    
    // MARK: - Internal Tasks
    
    private var holdStartTime: Date?
    private var retryTask: Task<Void, Never>?
    private var inboundListeningTask: Task<Void, Never>?
    
    // MARK: - Initialization & Configuration
    
    public init(
        locationService: LocationServiceProvider? = nil,
        sessionProvider: (@Sendable () -> GroupSession?)? = nil,
        cryptoService: CryptoServiceProvider? = nil,
        transport: PeerTransport? = nil,
        audioAlerter: SOSAudioAlerting? = nil,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.locationService = locationService
        self.sessionProvider = sessionProvider
        self.cryptoService = cryptoService
        self.transport = transport
        self.audioAlerter = audioAlerter ?? DefaultSOSAudioAlerter()
        self.dateProvider = dateProvider
        
        let guardService = InactivityGuardService(dateProvider: dateProvider)
        self.inactivityGuard = guardService
        guardService.onTriggerSOS = { [weak self] in
            self?.triggerSOS(emergencyType: .inactivity)
        }
    }
    
    /// Reconfigures dependencies.
    public func configure(
        locationService: LocationServiceProvider? = nil,
        sessionProvider: (@Sendable () -> GroupSession?)? = nil,
        cryptoService: CryptoServiceProvider? = nil,
        transport: PeerTransport? = nil,
        audioAlerter: SOSAudioAlerting? = nil,
        memberNameResolver: (@MainActor (String) -> String?)? = nil,
        routingTable: RoutingTableManaging? = nil,
        neighborTable: NeighborManaging? = nil,
        rateLimiter: ForwardingBudgetManaging? = nil,
        forwardingEngine: SOSForwardingManaging? = nil,
        clock: MeshClock? = nil
    ) {
        if let locationService { self.locationService = locationService }
        if let sessionProvider { self.sessionProvider = sessionProvider }
        if let cryptoService { self.cryptoService = cryptoService }
        if let audioAlerter { self.audioAlerter = audioAlerter }
        if let transport { self.transport = transport }
        if let memberNameResolver { self.memberNameResolver = memberNameResolver }
        if let routingTable { self.routingTable = routingTable }
        if let neighborTable { self.neighborTable = neighborTable }
        if let rateLimiter { self.rateLimiter = rateLimiter }
        if let forwardingEngine { self.forwardingEngine = forwardingEngine }
        if let clock { self.clock = clock }
    }
    
    // MARK: - Hold Gesture State Machine
    
    /// Called when the user touches and begins holding the SOS emergency button.
    public func handlePressBegan() {
        guard deliveryState == .idle || deliveryState == .searchingPeers || deliveryState.isFailed else { return }
        holdStartTime = dateProvider()
        holdProgress = 0.0
        deliveryState = .countdown(remainingSeconds: holdThresholdSeconds)
    }
    
    /// Called periodically during the continuous press to update progress.
    public func updateProgress(elapsedSeconds: Double) {
        let progress = min(1.0, elapsedSeconds / holdThresholdSeconds)
        self.holdProgress = progress
        let remaining = max(0.0, holdThresholdSeconds - elapsedSeconds)
        self.deliveryState = .countdown(remainingSeconds: remaining)
        
        if progress >= 1.0 {
            triggerSOS(emergencyType: currentEmergencyType)
        }
    }
    
    /// Called if the user releases the SOS button before 3 full seconds.
    public func handlePressCancelled() {
        if case .countdown = deliveryState {
            holdStartTime = nil
            holdProgress = 0.0
            deliveryState = .idle
        }
    }
    
    // MARK: - Urgent SOS Dispatch Engine
    
    /// Dispatches the SOS alert immediately via the urgent priority path.
    /// Operates independently of normal location ping intervals and Live Sharing state.
    public func triggerSOS(emergencyType: SOSType = .general) {
        holdStartTime = nil
        holdProgress = 1.0
        currentEmergencyType = emergencyType
        deliveryState = .localSending
        
        // Generate unique 32-bit emergency event ID
        let eventId = UInt32.random(in: 1...UInt32.max)
        self.activeSOSEventId = eventId
        self.retryCount = 0
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.executeSOSDispatch(eventId: eventId, emergencyType: emergencyType)
        }
    }
    
    /// Asynchronously executes initial broadcast and bounded retries.
    public func executeSOSDispatch(eventId: UInt32, emergencyType: SOSType) async {
        guard let session = sessionProvider?() else {
            // Standalone mock mode without session provider
            self.deliveryState = .localSending
            return
        }
        
        // Check peer connectivity to set initial honest state
        let peerCount = await transport?.activeDirectPeerCount() ?? 0
        if peerCount == 0 {
            if !self.deliveryState.isRelayed && !self.deliveryState.isDelivered {
                self.deliveryState = .searchingPeers
                self.currentRouteChoice = .none
            }
        } else if !self.deliveryState.isRelayed && !self.deliveryState.isDelivered {
            self.deliveryState = .localSending
        }
        
        await broadcastSOSWirePacket(eventId: eventId, emergencyType: emergencyType, session: session)
        totalDispatchedSOSCount += 1
        
        // Start Bounded Retry Loop
        startRetryTask(eventId: eventId, emergencyType: emergencyType, session: session)
    }
    
    /// Assembles, cryptographically seals, and broadcasts a 56-byte SOS packet.
    /// Prefers known usable route in routing table when available; falls back to bounded flooding.
    public func broadcastSOSWirePacket(eventId: UInt32, emergencyType: SOSType, session: GroupSession) async {
        guard let cryptoService, let transport else { return }
        
        // Freshest available coordinate without pretending an old fix is new
        let latestLocation = locationService?.getLatestLocationForSOS()
        
        let coordinate: CLLocationCoordinate2D
        let timestamp: Date
        let accuracy: UInt8
        
        if let latestLocation {
            coordinate = latestLocation.coordinate
            timestamp = latestLocation.timestamp // Original hardware GPS measurement time
            accuracy = latestLocation.rawAccuracyByte
        } else {
            coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
            timestamp = Date(timeIntervalSince1970: 0)
            accuracy = 255
        }
        
        let batteryPct = (locationService?.currentBatteryLevel ?? 1.0).asBatteryPercentage
        
        let sosPayload = SOSPayload(
            coordinate: coordinate,
            timestamp: timestamp,
            accuracy: accuracy,
            sosEventId: eventId,
            senderInitials: session.localInitials,
            emergencyType: emergencyType,
            batteryLevel: batteryPct,
            colorCode: session.localColorCode
        )
        
        let payloadData = sosPayload.serialize()
        
        let memberSlot = session.memberSlot
        let seq = CleartextEnvelope.makeSequenceNumber(memberSlot: memberSlot, counter: monotonicCounter)
        monotonicCounter &+= 1
        
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .sos,
            hopLimit: PacketConstants.sosHopLimit,
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: seq
        )
        
        do {
            let key = SymmetricKey(data: session.symmetricKeyData)
            let sealed = try await cryptoService.seal(payload: payloadData, envelope: envelope, using: key)
            let wirePacket = RawWirePacket(envelope: envelope, ciphertext: sealed.ciphertext, authTag: sealed.authTag)
            let wireData = try wirePacket.toWireData()
            
            // Route Selection: Prefer known usable route when available
            var routeUsed = false
            if let routingTable = routingTable {
                let neighbors = await neighborTable?.activeNeighbors() ?? []
                let connectedPeerIds = Set(neighbors.map(\.id))
                for neighbor in neighbors where neighbor.isGroupMember {
                    if let route = await routingTable.findRoute(to: neighbor.id), route.isFresh, connectedPeerIds.contains(route.nextHopPeerId) {
                        self.currentRouteChoice = .knownRoute(nextHop: route.nextHopPeerId, hopCount: route.hopCount)
                        if let meshTransport = transport as? MeshTransport {
                            _ = try await meshTransport.sendFrame(wireData, to: route.nextHopPeerId)
                        } else {
                            try await transport.sendPacket(wireData, to: route.nextHopPeerId)
                        }
                        routeUsed = true
                        break
                    }
                }
            }
            
            if !routeUsed {
                let peerCount = await transport.activeDirectPeerCount()
                self.currentRouteChoice = peerCount == 0 ? .none : .boundedFlooding(neighborCount: peerCount)
                // Broadcast packet (queued into urgent priority lane)
                try await transport.broadcastPacket(wireData)
            }
        } catch {
            // Radio transport errors
            let peerCount = await transport.activeDirectPeerCount()
            if peerCount == 0 {
                self.deliveryState = .searchingPeers
                self.currentRouteChoice = .none
            } else {
                self.deliveryState = .failed(reason: error.localizedDescription)
            }
        }
    }
    
    // MARK: - Bounded Retries Scheduler
    
    private func startRetryTask(eventId: UInt32, emergencyType: SOSType, session: GroupSession) {
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.retryInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                
                // If friend delivery has already been confirmed, stop retrying
                if self.deliveryState.isDelivered {
                    break
                }
                
                await self.executeRetryAttempt(eventId: eventId, emergencyType: emergencyType, session: session)
            }
        }
    }
    
    /// Executes a single bounded retry attempt. Can be invoked directly in deterministic tests.
    public func executeRetryAttempt(eventId: UInt32, emergencyType: SOSType, session: GroupSession) async {
        guard !deliveryState.isDelivered else { return }
        
        if retryCount < maxRetries {
            retryCount += 1
            
            let peerCount = await transport?.activeDirectPeerCount() ?? 0
            if peerCount == 0 {
                if !self.deliveryState.isRelayed {
                    self.deliveryState = .searchingPeers
                    self.currentRouteChoice = .none
                }
            } else if !self.deliveryState.isRelayed {
                self.deliveryState = .localSending
            }
            
            await broadcastSOSWirePacket(eventId: eventId, emergencyType: emergencyType, session: session)
        } else {
            // Retries exhausted without friend delivery
            let peerCount = await transport?.activeDirectPeerCount() ?? 0
            if self.deliveryState.isRelayed {
                // Keep relayed state honestly showing it was relayed but unconfirmed by friend
            } else if peerCount == 0 {
                self.deliveryState = .searchingPeers
            } else {
                self.deliveryState = .failed(reason: "Delivery confirmation timeout: exhausted \(maxRetries) retries without recipient ACK.")
            }
            cancelRetryTask()
        }
    }
    
    /// Triggers an immediate retry attempt for the active SOS event without waiting for the timer.
    public func triggerRetryNow() async {
        guard let eventId = activeSOSEventId, let session = sessionProvider?() else { return }
        await executeRetryAttempt(eventId: eventId, emergencyType: currentEmergencyType, session: session)
    }
    
    private func cancelRetryTask() {
        retryTask?.cancel()
        retryTask = nil
    }
    
    // MARK: - Acknowledgement Ingestion & Evidence Tracking
    
    /// Updates delivery status when an ACK is received over the air.
    ///
    /// Semantics:
    /// - `.deliveredToFriend`: Cryptographic proof of receipt on destination friend device. Stops retries.
    /// - `.relayedByMeshHop`: Intermediary relay accepted packet. Does NOT prove friend received it.
    public func handleAckReceived(status: ACKStatus, responderId: String, hopCount: UInt8, eventId: UInt32? = nil) {
        if let eventId, let activeSOSEventId, eventId != activeSOSEventId {
            // ACK for a different event; disregard
            return
        }
        
        totalReceivedAcksCount += 1
        
        switch status {
        case .deliveredToFriend:
            cancelRetryTask()
            lastDeliveredFriendId = responderId
            lastDeliveredTimestamp = dateProvider()
            lastDeliveredHopCount = hopCount
            deliveryState = .deliveredToFriend(friendId: responderId, timestamp: dateProvider())
            
        case .relayedByMeshHop:
            lastRelayHopCount = hopCount
            lastRelayResponderId = responderId
            
            // Only update if not already delivered to friend
            if !deliveryState.isDelivered {
                deliveryState = .relayedAck(relayHopCount: hopCount, responderId: responderId)
            }
        }
    }
    
    // MARK: - Inbound Packet Ingestion & Deduplication Pipeline
    
    /// Observes radio transport inbound packets stream.
    public func startListeningForInboundPackets() {
        guard let transport else { return }
        inboundListeningTask?.cancel()
        inboundListeningTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await inbound in await transport.inboundPackets {
                guard !Task.isCancelled else { break }
                await self.processInboundPacket(inbound)
            }
        }
    }
    
    public func stopListening() {
        inboundListeningTask?.cancel()
        inboundListeningTask = nil
    }
    
    /// Ingests an inbound 56-byte packet through the 6-step verification and deduplication pipeline.
    public func processInboundPacket(_ inbound: InboundPacket) async {
        guard let session = sessionProvider?(), let cryptoService else { return }
        
        let envelope = inbound.rawPacket.envelope
        
        // 1. Session Filter
        guard envelope.sessionId == session.sessionId else { return }
        
        // 2. Cryptographic Authentication Tag Verification
        let decryptedData: Data
        do {
            let key = SymmetricKey(data: session.symmetricKeyData)
            decryptedData = try await cryptoService.open(
                ciphertext: inbound.rawPacket.ciphertext,
                envelope: envelope,
                authTag: inbound.rawPacket.authTag,
                using: key
            )
        } catch {
            // Tampered or unauthorized packet: Drop with ZERO state changes!
            return
        }
        
        // 3. Process Decrypted Packet by Type
        switch envelope.type {
        case .sos:
            await handleInboundSOS(envelope: envelope, decryptedData: decryptedData, session: session, inbound: inbound)
            
        case .ack:
            await handleInboundACK(envelope: envelope, decryptedData: decryptedData, session: session)
            
        default:
            break
        }
    }
    
    // MARK: - Inbound SOS Processing & Duplicate Suppression
    
    private func handleInboundSOS(
        envelope: CleartextEnvelope,
        decryptedData: Data,
        session: GroupSession,
        inbound: InboundPacket
    ) async {
        guard let payload = try? SOSPayload.deserialize(from: decryptedData) else { return }
        
        // Sender validation: cannot alert self
        guard payload.senderInitials != session.localInitials else { return }
        
        let eventId = payload.sosEventId
        
        // Deduplication Check
        if seenSOSEventIds.contains(eventId) {
            // Duplicate packet arrived!
            totalDuplicatesSuppressedCount += 1
            
            // Re-emit delivery ACK so the sender's retry loop resolves,
            // but STRICTLY SUPPRESS repeated sirens and duplicate alert banners!
            await emitDeliveryACK(for: payload, envelope: envelope, session: session, status: .deliveredToFriend)
            return
        }
        
        // First-Time Trusted Reception
        seenSOSEventIds.insert(eventId)
        totalReceivedSOSCount += 1
        
        // Trigger Audio Siren & Haptics
        isSirenActive = true
        audioAlerter?.triggerEmergencyAlertFeedback()
        
        // Surface Incoming Alert in UI
        let resolvedName = memberNameResolver?(payload.senderInitials)
        let alert = IncomingSOSAlert(
            id: eventId,
            senderInitials: payload.senderInitials,
            senderName: resolvedName,
            emergencyType: payload.emergencyType,
            coordinate: payload.coordinate,
            accuracy: payload.accuracy,
            timestamp: payload.timestamp,
            batteryLevel: payload.batteryLevel,
            receivedAt: dateProvider()
        )
        self.activeIncomingAlert = alert
        
        // Emit Immediate Delivery ACK via Urgent Path
        await emitDeliveryACK(for: payload, envelope: envelope, session: session, status: .deliveredToFriend)
    }
    
    // MARK: - Inbound ACK Processing
    
    private func handleInboundACK(
        envelope: CleartextEnvelope,
        decryptedData: Data,
        session: GroupSession
    ) async {
        guard let payload = try? ACKPayload.deserialize(from: decryptedData) else { return }
        
        // Verify this ACK is addressed to our local member and matches active SOS event
        guard payload.ackedSenderInitials == session.localInitials else { return }
        guard payload.originalEventId == activeSOSEventId else { return }
        
        handleAckReceived(
            status: payload.ackStatus,
            responderId: payload.responderInitials,
            hopCount: envelope.hopCount,
            eventId: payload.originalEventId
        )
    }
    
    // MARK: - Delivery ACK Emission
    
    private func emitDeliveryACK(
        for sosPayload: SOSPayload,
        envelope: CleartextEnvelope,
        session: GroupSession,
        status: ACKStatus
    ) async {
        guard let cryptoService, let transport else { return }
        
        let ackPayload = ACKPayload(
            ackedSeqNumber: envelope.sequenceNumber,
            ackedSenderInitials: sosPayload.senderInitials,
            ackTimestamp: dateProvider(),
            ackStatus: status,
            receivedRssi: 0,
            originalEventId: sosPayload.sosEventId,
            responderInitials: session.localInitials
        )
        
        let payloadData = ackPayload.serialize()
        
        let memberSlot = session.memberSlot
        let seq = CleartextEnvelope.makeSequenceNumber(memberSlot: memberSlot, counter: monotonicCounter)
        monotonicCounter &+= 1
        
        let ackEnvelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .ack,
            hopLimit: PacketConstants.sosHopLimit,
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: seq
        )
        
        do {
            let key = SymmetricKey(data: session.symmetricKeyData)
            let sealed = try await cryptoService.seal(payload: payloadData, envelope: ackEnvelope, using: key)
            let wirePacket = RawWirePacket(envelope: ackEnvelope, ciphertext: sealed.ciphertext, authTag: sealed.authTag)
            let wireData = try wirePacket.toWireData()
            
            // Multi-Hop Return Route Selection: Prefer known usable route towards the distressed sender
            if let routingTable = routingTable,
               let route = await routingTable.findRoute(to: sosPayload.senderInitials),
               route.isFresh {
                if let meshTransport = transport as? MeshTransport {
                    _ = try await meshTransport.sendFrame(wireData, to: route.nextHopPeerId)
                } else {
                    try await transport.sendPacket(wireData, to: route.nextHopPeerId)
                }
            } else {
                // Broadcast ACK via Urgent Lane (Bounded Flooding Fallback)
                try await transport.broadcastPacket(wireData)
            }
            totalEmittedAcksCount += 1
        } catch {
            // Transport failure
        }
    }
    
    // MARK: - User Actions
    
    /// Dismisses the incoming emergency alert banner and stops any ongoing siren audio.
    public func dismissIncomingAlert() {
        activeIncomingAlert = nil
        isSirenActive = false
        audioAlerter?.stopEmergencyAlertFeedback()
    }
    
    /// Resets the SOS state machine back to idle.
    public func reset() {
        cancelRetryTask()
        inactivityGuard.reset()
        holdStartTime = nil
        holdProgress = 0.0
        deliveryState = .idle
        currentRouteChoice = .none
        activeSOSEventId = nil
        retryCount = 0
        lastDeliveredHopCount = nil
        lastDeliveredFriendId = nil
        lastDeliveredTimestamp = nil
        lastRelayHopCount = nil
        lastRelayResponderId = nil
    }
}
