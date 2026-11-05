//
//  RouteDiscoveryService.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation
import CryptoKit

/// Thread-safe Ad-hoc On-Demand Distance Vector (AODV) Route Discovery Engine.
///
/// Implements Subsystem 2 Route Discovery for Phase 2 Multi-Hop Mesh Architecture:
/// - On-demand discovery of multi-hop paths between group members (`ROUTE_REQ` / `ROUTE_RESP`).
/// - Deduplicates route requests using `(originatorInitials, discoveryNonce)` and sequence identifiers.
/// - Rejects stale route responses, detects routing loops, and caps maximum hop count at 8.
/// - Bounded flooding with token bucket rate limiter (2 pkts/sec) and per-target cooldown to prevent broadcast storms.
/// - Re-discovers routes when intermediate next hops disconnect.
/// - Multi-group isolation: destinations and reverse routes are scoped to group sessions.
/// - Emergency SOS bypasses route discovery delay while respecting authentication and hop limits.
/// - 100% testable with injected `MeshClock` and actors.
public actor RouteDiscoveryService: RouteDiscoveryManaging {
    
    // MARK: - Internal Types
    
    private struct InFlightDiscovery {
        let targetInitials: String
        let sessionId: UInt32
        let discoveryNonce: UInt32
        let sequenceNumber: UInt32
        let startedAt: Date
        let timeoutDeadline: Date
        var continuations: [CheckedContinuation<RouteEntry, Error>]
    }
    
    private struct SeenRREQEntry {
        let hopCount: UInt8
        let recordedAt: Date
    }
    
    // MARK: - Dependencies & Configuration
    
    private let routingTable: RoutingTableManaging
    private let neighborTable: NeighborManaging
    private let transport: MeshTransport
    private let cryptoService: CryptoServiceProvider
    private let clock: MeshClock
    private let maxHops: UInt8
    private let maxInFlightCapacity: Int
    
    // MARK: - Token Bucket Rate Limiter
    
    private let tokenCapacity: Double = 4.0
    private let refillRatePerSec: Double = 2.0
    private var tokens: Double = 4.0
    private var lastRefillTime: Date
    
    // MARK: - Discovery State
    
    /// Map of discoveryNonce -> in-flight discovery
    private var inFlightDiscoveries: [UInt32: InFlightDiscovery] = [:]
    
    /// Index of "sessionId:targetInitials" -> discoveryNonce for coalescing
    private var inFlightByTarget: [String: UInt32] = [:]
    
    /// Last RREQ sent timestamp per "sessionId:targetInitials" for cooldown
    private var targetCooldowns: [String: Date] = [:]
    
    /// Bounded LRU cache of seen (originatorInitials, discoveryNonce) -> SeenRREQEntry
    private var seenRREQs: [String: SeenRREQEntry] = [:]
    private let maxSeenRREQCapacity: Int = 128
    private let seenRREQTtl: TimeInterval = 30.0
    
    /// Monotonic sequence counter per session
    private var sequenceCounters: [UInt32: UInt32] = [:]
    
    // MARK: - Telemetry & Diagnostics Counters
    
    private var totalDiscoveriesInitiatedCount: Int = 0
    private var totalDiscoveriesSucceededCount: Int = 0
    private var totalDiscoveriesFailedCount: Int = 0
    private var totalRReqSentCount: Int = 0
    private var totalRReqReceivedCount: Int = 0
    private var totalRRespSentCount: Int = 0
    private var totalRRespReceivedCount: Int = 0
    private var totalRoutesInvalidatedCount: Int = 0
    
    /// Callback invoked when an inbound route request reaches the local device as destination.
    /// Used to trigger an immediate location response burst in one-to-many topologies.
    public var onTargetReached: (@Sendable (String) -> Void)?
    
    // MARK: - Initialization
    
    public init(
        routingTable: RoutingTableManaging,
        neighborTable: NeighborManaging,
        transport: MeshTransport,
        cryptoService: CryptoServiceProvider,
        clock: MeshClock = SystemMeshClock(),
        maxHops: UInt8 = PacketConstants.defaultHopLimit,
        maxInFlightCapacity: Int = 16,
        onTargetReached: (@Sendable (String) -> Void)? = nil
    ) {
        self.routingTable = routingTable
        self.neighborTable = neighborTable
        self.transport = transport
        self.cryptoService = cryptoService
        self.clock = clock
        self.maxHops = min(maxHops, PacketConstants.defaultHopLimit)
        self.maxInFlightCapacity = max(1, maxInFlightCapacity)
        self.lastRefillTime = clock.now()
        self.onTargetReached = onTargetReached
    }
    
    public func setOnTargetReached(_ handler: (@Sendable (String) -> Void)?) {
        self.onTargetReached = handler
    }
    
    // MARK: - Route Resolution & Discovery Initiation
    
    /// Resolves an on-demand route towards target initials in the given session.
    /// Returns immediately if an unexpired, active route already exists.
    public func resolveRoute(
        to targetInitials: String,
        session: GroupSession,
        timeout: TimeInterval = 3.0
    ) async throws -> RouteEntry {
        let sanitizedTarget = InitialsCodec.sanitize(targetInitials)
        
        // 1. Check existing unexpired route in routing table
        if let routingTable = routingTable as? RoutingTable {
            if let cached = await routingTable.findRoute(to: sanitizedTarget, inSession: UInt32(session.sessionId)), cached.isFresh {
                return cached
            }
        } else if let cached = await routingTable.findRoute(to: sanitizedTarget), cached.isFresh {
            return cached
        }
        
        // 2. Fall back to on-demand AODV discovery
        return try await initiateDiscovery(to: sanitizedTarget, session: session, timeout: timeout)
    }
    
    /// Forces initiation of route discovery regardless of existing cached routes.
    public func initiateDiscovery(
        to targetInitials: String,
        session: GroupSession,
        timeout: TimeInterval = 3.0
    ) async throws -> RouteEntry {
        let sanitizedTarget = InitialsCodec.sanitize(targetInitials)
        
        // Loop prevention: cannot discover route to self
        guard sanitizedTarget != session.localInitials else {
            throw RouteDiscoveryFailure.loopDetected
        }
        
        let targetKey = "\(session.sessionId):\(sanitizedTarget)"
        
        // 1. Coalesce with existing in-flight discovery to avoid duplicate floods
        if let existingNonce = inFlightByTarget[targetKey],
           var existing = inFlightDiscoveries[existingNonce] {
            return try await withCheckedThrowingContinuation { cont in
                existing.continuations.append(cont)
                inFlightDiscoveries[existingNonce] = existing
            }
        }
        
        // 2. Check per-target cooldown (500ms minimum between new discoveries for same target)
        let now = clock.now()
        if let lastSent = targetCooldowns[targetKey], now.timeIntervalSince(lastSent) < 0.5 {
            throw RouteDiscoveryFailure.floodingBudgetExhausted
        }
        
        // 3. Enforce token bucket rate limiting (2 pkts/sec)
        guard consumeToken() else {
            throw RouteDiscoveryFailure.floodingBudgetExhausted
        }
        targetCooldowns[targetKey] = now
        
        // 4. Enforce in-flight queue bounds
        guard inFlightDiscoveries.count < maxInFlightCapacity else {
            throw RouteDiscoveryFailure.alreadyInProgress
        }
        
        // 5. Construct authenticated Route Request datagram
        let nonce = UInt32.random(in: 1...UInt32.max)
        let seq = nextSequenceNumber(for: session)
        
        let reqPayload = RouteReqPayload(
            originatorInitials: session.localInitials,
            targetInitials: sanitizedTarget,
            discoveryNonce: nonce,
            routeCost: 0
        )
        let envelope = CleartextEnvelope(
            type: .routeReq,
            hopLimit: maxHops,
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: seq
        )
        let wireData = try await cryptoService.sealToWireBytes(
            payload: reqPayload.serialize(),
            envelope: envelope,
            using: SymmetricKey(data: session.symmetricKeyData)
        )
        
        totalDiscoveriesInitiatedCount += 1
        totalRReqSentCount += 1
        
        // 6. Broadcast across all active connected radio links
        try await transport.broadcastFrame(wireData)
        
        // 7. Track in-flight state and set timeout deadline
        let deadline = now.addingTimeInterval(max(0.5, timeout))
        
        // Schedule background timeout task
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await self?.handleDiscoveryTimeout(nonce: nonce)
        }
        
        return try await withCheckedThrowingContinuation { cont in
            let inFlight = InFlightDiscovery(
                targetInitials: sanitizedTarget,
                sessionId: UInt32(session.sessionId),
                discoveryNonce: nonce,
                sequenceNumber: seq,
                startedAt: now,
                timeoutDeadline: deadline,
                continuations: [cont]
            )
            inFlightDiscoveries[nonce] = inFlight
            inFlightByTarget[targetKey] = nonce
        }
    }
    
    // MARK: - Inbound Packet Ingestion Pipeline
    
    /// Ingests and processes an inbound Route Request packet.
    public func handleInboundRouteReq(
        wireData: Data,
        fromPeerId: String,
        session: GroupSession
    ) async throws -> RouteReqHandlingResult {
        totalRReqReceivedCount += 1
        
        // 1. Packet structure verification
        guard wireData.count == PacketConstants.wirePacketSize else {
            return .droppedSecurityFailed
        }
        guard let rawPacket = try? RawWirePacket.fromWireData(wireData) else {
            return .droppedSecurityFailed
        }
        
        let envelope = rawPacket.envelope
        guard envelope.type == .routeReq else {
            return .droppedSecurityFailed
        }
        guard envelope.sessionId == session.sessionId else {
            // Addressed to different session (stranger traffic)
            return .droppedSecurityFailed
        }
        
        // 2. Hop limit bounds enforcement (capped at 8 hops)
        guard envelope.hopCount < envelope.hopLimit && envelope.hopCount < maxHops else {
            return .droppedHopLimitExceeded
        }
        
        // 3. Cryptographic authentication: Poly1305 MAC verification
        let decrypted: Data
        do {
            let key = SymmetricKey(data: session.symmetricKeyData)
            decrypted = try await cryptoService.open(
                ciphertext: rawPacket.ciphertext,
                envelope: rawPacket.envelope,
                authTag: rawPacket.authTag,
                using: key
            )
        } catch {
            return .droppedSecurityFailed
        }
        
        guard let payload = try? RouteReqPayload.deserialize(from: decrypted) else {
            return .droppedSecurityFailed
        }
        
        // 4. Routing loop detection: check if originator is self
        if payload.originatorInitials == session.localInitials {
            return .droppedLoopDetected
        }
        
        // 5. Deduplication using originator initials + discoveryNonce
        let rreqKey = "\(payload.originatorInitials):\(payload.discoveryNonce)"
        let now = clock.now()
        pruneExpiredSeenRREQs(now: now)
        
        if let existing = seenRREQs[rreqKey] {
            if envelope.hopCount >= existing.hopCount {
                // Duplicate request arrived via equal or longer path: drop
                return .droppedDuplicate
            }
            // Better / shorter path discovered: update reverse route
            await routingTable.recordReverseRoute(
                discoveryKey: envelope.sequenceNumber,
                incomingPeerId: fromPeerId,
                hopCount: envelope.hopCount + 1,
                ttl: 15.0
            )
            seenRREQs[rreqKey] = SeenRREQEntry(hopCount: envelope.hopCount, recordedAt: now)
        } else {
            // First time seeing this RREQ: record in seen cache and reverse table
            if seenRREQs.count >= maxSeenRREQCapacity {
                if let oldest = seenRREQs.min(by: { $0.value.recordedAt < $1.value.recordedAt })?.key {
                    seenRREQs.removeValue(forKey: oldest)
                }
            }
            seenRREQs[rreqKey] = SeenRREQEntry(hopCount: envelope.hopCount, recordedAt: now)
            await routingTable.recordReverseRoute(
                discoveryKey: envelope.sequenceNumber,
                incomingPeerId: fromPeerId,
                hopCount: envelope.hopCount + 1,
                ttl: 15.0
            )
        }
        
        // 6. Check if local node is the target destination
        if payload.targetInitials == session.localInitials {
            // Target member reached!
            // Record forward route back to the originator
            let forwardHopCount = envelope.hopCount + 1
            if let rt = routingTable as? RoutingTable {
                await rt.recordForwardRoute(
                    destinationId: payload.originatorInitials,
                    nextHop: fromPeerId,
                    hopCount: forwardHopCount,
                    cost: payload.routeCost + 1,
                    sequenceNumber: envelope.sequenceNumber,
                    ttl: 60.0,
                    sessionId: UInt32(envelope.sessionId)
                )
            } else {
                await routingTable.recordForwardRoute(
                    destinationId: payload.originatorInitials,
                    nextHop: fromPeerId,
                    hopCount: forwardHopCount,
                    cost: payload.routeCost + 1,
                    sequenceNumber: envelope.sequenceNumber,
                    ttl: 60.0
                )
            }
            
            // Craft authenticated Route Response
            let respPayload = RouteRespPayload(
                originatorInitials: payload.originatorInitials,
                targetInitials: session.localInitials,
                discoveryNonce: payload.discoveryNonce,
                routeCost: 0
            )
            let respEnvelope = CleartextEnvelope(
                type: .routeResp,
                hopLimit: maxHops,
                hopCount: 0,
                sessionId: envelope.sessionId,
                sequenceNumber: envelope.sequenceNumber // Echo sequenceNumber so relays match reverse route
            )
            let respWire = try await cryptoService.sealToWireBytes(
                payload: respPayload.serialize(),
                envelope: respEnvelope,
                using: SymmetricKey(data: session.symmetricKeyData)
            )
            
            totalRRespSentCount += 1
            _ = try await transport.sendFrame(respWire, to: fromPeerId)
            onTargetReached?(payload.originatorInitials)
            return .answeredWithRResp(targetInitials: payload.targetInitials, nextHop: fromPeerId)
        }
        
        // 7. Intermediate Group Member: Relay RREQ forward
        let nextHopCount = envelope.hopCount + 1
        guard nextHopCount < maxHops else {
            return .droppedHopLimitExceeded
        }
        
        // Rate limit RREQ propagation
        guard consumeToken() else {
            return .droppedFloodingThrottled
        }
        
        // Mutate only hopCount (Byte 2) to preserve Poly1305 MAC under AAD hop masking
        var mutatedWire = wireData
        mutatedWire[mutatedWire.startIndex + 2] = nextHopCount
        
        let neighbors = await neighborTable.activeNeighbors()
        let targetPeers = neighbors.map(\.id).filter { $0 != fromPeerId }
        
        for peerId in targetPeers {
            _ = try? await transport.sendFrame(mutatedWire, to: peerId)
        }
        
        return .forwarded(nextHops: targetPeers, hopCount: nextHopCount)
    }
    
    /// Ingests and processes an inbound Route Response packet.
    public func handleInboundRouteResp(
        wireData: Data,
        fromPeerId: String,
        session: GroupSession
    ) async throws -> RouteRespHandlingResult {
        totalRRespReceivedCount += 1
        
        // 1. Packet structure verification
        guard wireData.count == PacketConstants.wirePacketSize else {
            return .droppedSecurityFailed
        }
        guard let rawPacket = try? RawWirePacket.fromWireData(wireData) else {
            return .droppedSecurityFailed
        }
        
        let envelope = rawPacket.envelope
        guard envelope.type == .routeResp else {
            return .droppedSecurityFailed
        }
        guard envelope.sessionId == session.sessionId else {
            return .droppedSecurityFailed
        }
        
        // 2. Hop limit bounds check
        guard envelope.hopCount < maxHops else {
            return .droppedHopLimitExceeded
        }
        
        // 3. Cryptographic authentication: Poly1305 MAC verification
        let decrypted: Data
        do {
            let key = SymmetricKey(data: session.symmetricKeyData)
            decrypted = try await cryptoService.open(
                ciphertext: rawPacket.ciphertext,
                envelope: rawPacket.envelope,
                authTag: rawPacket.authTag,
                using: key
            )
        } catch {
            return .droppedSecurityFailed
        }
        
        guard let payload = try? RouteRespPayload.deserialize(from: decrypted) else {
            return .droppedSecurityFailed
        }
        
        // 4. Originator Check: Are we the original requester?
        if payload.originatorInitials == session.localInitials {
            // Originator member reached!
            guard let inFlight = inFlightDiscoveries.removeValue(forKey: payload.discoveryNonce),
                  inFlight.targetInitials == payload.targetInitials else {
                // Stale, timed-out, or unsolicited RREP
                return .droppedStaleOrUnsolicited
            }
            
            let targetKey = "\(session.sessionId):\(payload.targetInitials)"
            inFlightByTarget.removeValue(forKey: targetKey)
            
            // Loop check
            if fromPeerId == session.localInitials {
                return .droppedLoopDetected
            }
            
            let routeHopCount = envelope.hopCount + 1
            guard routeHopCount <= maxHops else {
                return .droppedHopLimitExceeded
            }
            
            let entry = RouteEntry(
                destinationId: payload.targetInitials,
                nextHopPeerId: fromPeerId,
                hopCount: routeHopCount,
                routeCost: payload.routeCost + 1,
                sequenceNumber: envelope.sequenceNumber,
                expiresAt: clock.now().addingTimeInterval(60.0),
                sessionId: UInt32(envelope.sessionId)
            )
            
            if let rt = routingTable as? RoutingTable {
                await rt.recordForwardRoute(
                    destinationId: payload.targetInitials,
                    nextHop: fromPeerId,
                    hopCount: routeHopCount,
                    cost: payload.routeCost + 1,
                    sequenceNumber: envelope.sequenceNumber,
                    ttl: 60.0,
                    sessionId: UInt32(envelope.sessionId)
                )
            } else {
                await routingTable.recordForwardRoute(
                    destinationId: payload.targetInitials,
                    nextHop: fromPeerId,
                    hopCount: routeHopCount,
                    cost: payload.routeCost + 1,
                    sequenceNumber: envelope.sequenceNumber,
                    ttl: 60.0
                )
            }
            
            totalDiscoveriesSucceededCount += 1
            for cont in inFlight.continuations {
                cont.resume(returning: entry)
            }
            
            return .completedDiscovery(destination: payload.targetInitials, nextHop: fromPeerId, hopCount: routeHopCount)
        }
        
        // 5. Intermediate Group Member: Relay RREP along reverse path
        let intermediateHopCount = envelope.hopCount + 1
        guard intermediateHopCount <= maxHops else {
            return .droppedHopLimitExceeded
        }
        
        // Record forward route towards the responder
        if let rt = routingTable as? RoutingTable {
            await rt.recordForwardRoute(
                destinationId: payload.targetInitials,
                nextHop: fromPeerId,
                hopCount: intermediateHopCount,
                cost: payload.routeCost + 1,
                sequenceNumber: envelope.sequenceNumber,
                ttl: 60.0,
                sessionId: UInt32(envelope.sessionId)
            )
        } else {
            await routingTable.recordForwardRoute(
                destinationId: payload.targetInitials,
                nextHop: fromPeerId,
                hopCount: intermediateHopCount,
                cost: payload.routeCost + 1,
                sequenceNumber: envelope.sequenceNumber,
                ttl: 60.0
            )
        }
        
        // Pop reverse route for envelope.sequenceNumber
        guard let reverseRoute = await routingTable.popReverseRoute(for: envelope.sequenceNumber) else {
            return .droppedStaleOrUnsolicited
        }
        
        var mutatedWire = wireData
        mutatedWire[mutatedWire.startIndex + 2] = intermediateHopCount
        
        _ = try await transport.sendFrame(mutatedWire, to: reverseRoute.incomingPeerId)
        return .forwardedToReverseHop(nextHop: reverseRoute.incomingPeerId, hopCount: intermediateHopCount)
    }
    
    // MARK: - Link Invalidation & Topology Maintenance
    
    /// Handles neighbor disconnection: invalidates all routes using this neighbor as next-hop.
    public func handleNeighborDisconnected(peerId: String) async {
        if let rt = routingTable as? RoutingTable {
            await rt.invalidateRoutesUsingNextHop(peerId)
        } else {
            await routingTable.invalidateRoute(towards: peerId)
        }
        totalRoutesInvalidatedCount += 1
    }
    
    /// Invalidates a route towards a specific destination.
    public func invalidateRoute(towards targetInitials: String, session: GroupSession?) async {
        let sid = session.map { UInt32($0.sessionId) }
        if let rt = routingTable as? RoutingTable {
            await rt.invalidateRoute(towards: targetInitials, inSession: sid)
        } else {
            await routingTable.invalidateRoute(towards: targetInitials)
        }
        totalRoutesInvalidatedCount += 1
    }
    
    /// Teardown: cancels in-flight discoveries and purges session routes.
    public func teardown(sessionId: UInt32? = nil) async {
        let noncesToCancel: [UInt32]
        if let sid = sessionId {
            noncesToCancel = inFlightDiscoveries.values.filter { $0.sessionId == sid }.map(\.discoveryNonce)
            if let rt = routingTable as? RoutingTable {
                await rt.invalidateRoutes(forSessionId: sid)
            }
        } else {
            noncesToCancel = Array(inFlightDiscoveries.keys)
            await routingTable.removeAll()
        }
        
        for nonce in noncesToCancel {
            if let inFlight = inFlightDiscoveries.removeValue(forKey: nonce) {
                let targetKey = "\(inFlight.sessionId):\(inFlight.targetInitials)"
                inFlightByTarget.removeValue(forKey: targetKey)
                totalDiscoveriesFailedCount += 1
                for cont in inFlight.continuations {
                    cont.resume(throwing: RouteDiscoveryFailure.sessionTerminated)
                }
            }
        }
    }
    
    /// Manually or deterministically checks and expires timed-out in-flight discoveries.
    public func checkTimeouts(now: Date? = nil) {
        let currentTime = now ?? clock.now()
        var expiredNonces: [UInt32] = []
        for (nonce, inFlight) in inFlightDiscoveries {
            if currentTime >= inFlight.timeoutDeadline {
                expiredNonces.append(nonce)
            }
        }
        for nonce in expiredNonces {
            handleDiscoveryTimeout(nonce: nonce)
        }
    }
    
    public func handleDiscoveryTimeout(nonce: UInt32) {
        guard let inFlight = inFlightDiscoveries.removeValue(forKey: nonce) else { return }
        let targetKey = "\(inFlight.sessionId):\(inFlight.targetInitials)"
        inFlightByTarget.removeValue(forKey: targetKey)
        totalDiscoveriesFailedCount += 1
        for cont in inFlight.continuations {
            cont.resume(throwing: RouteDiscoveryFailure.timeout)
        }
    }
    
    // MARK: - Diagnostics & Telemetry
    
    public func diagnosticsSnapshot() async -> RouteDiscoveryDiagnostics {
        var activeRoutes = 0
        if let rt = routingTable as? RoutingTable {
            activeRoutes = await rt.activeForwardRoutesCount
        }
        return RouteDiscoveryDiagnostics(
            activeInFlightDiscoveries: inFlightDiscoveries.count,
            totalDiscoveriesInitiated: totalDiscoveriesInitiatedCount,
            totalDiscoveriesSucceeded: totalDiscoveriesSucceededCount,
            totalDiscoveriesFailed: totalDiscoveriesFailedCount,
            totalRReqSent: totalRReqSentCount,
            totalRReqReceived: totalRReqReceivedCount,
            totalRRespSent: totalRRespSentCount,
            totalRRespReceived: totalRRespReceivedCount,
            totalRoutesInvalidated: totalRoutesInvalidatedCount,
            activeRoutesCount: activeRoutes
        )
    }
    
    // MARK: - Private Helpers
    
    /// Public helper for testing token bucket rate limiter deterministically.
    @discardableResult
    public func consumeFloodingToken() -> Bool {
        consumeToken()
    }
    
    private func nextSequenceNumber(for session: GroupSession) -> UInt32 {
        let sid = UInt32(session.sessionId)
        let counter = (sequenceCounters[sid] ?? 0) &+ 1
        sequenceCounters[sid] = counter
        return CleartextEnvelope.makeSequenceNumber(memberSlot: 1, counter: counter)
    }
    
    private func consumeToken() -> Bool {
        let now = clock.now()
        let elapsed = max(0.0, now.timeIntervalSince(lastRefillTime))
        tokens = min(tokenCapacity, tokens + (elapsed * refillRatePerSec))
        lastRefillTime = now
        
        if tokens >= 1.0 {
            tokens -= 1.0
            return true
        }
        return false
    }
    
    private func pruneExpiredSeenRREQs(now: Date) {
        seenRREQs = seenRREQs.filter { now.timeIntervalSince($0.value.recordedAt) < seenRREQTtl }
    }
}
