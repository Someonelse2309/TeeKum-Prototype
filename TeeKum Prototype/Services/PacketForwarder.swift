//
//  PacketForwarder.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation
import CryptoKit

/// Thread-safe Ad-hoc Multi-Hop Mesh Packet Forwarder & Blind Relay Engine.
///
/// Implements Subsystem 3 of Phase 2 Multi-Hop Mesh Architecture:
/// - Enforces zero-knowledge blind relaying: intermediate phones forward opaque ciphertexts without group keys.
/// - Validates packet structure, version, and hop bounds before enqueuing.
/// - Suppresses duplicate packets across hops via bounded 1,024-entry 5-minute LRU `SeenPacketCache`.
/// - Authenticates packets addressed to local group sessions with Poly1305 MAC tag and freshness filters.
/// - Enforces communal participation policies: opt-in requirement and hard 20% battery cutoff.
/// - Enforces rate limiting: 2 pkts/sec ordinary token bucket, 4 pkts/sec urgent SOS token bucket.
/// - Mutates only `hopCount` (Byte 1 low 4b), preserving the sender's Poly1305 tag via AAD hop masking.
/// - Supports injected `MeshClock` and actors for 100% deterministic test execution.
public actor PacketForwarder: PacketForwarding {
    
    private let routingTable: RoutingTableManaging
    private let rateLimiter: ForwardingBudgetManaging
    private let neighborTable: NeighborManaging
    private let seenPacketCache: SeenPacketCache
    private let clock: MeshClock
    private let cryptoService: CryptoServiceProvider?
    private let sessionProvider: (@Sendable () -> GroupSession?)?
    private let policyProvider: (@Sendable () -> RelayPolicyState)?
    private let policyManager: RelayPolicyManaging?
    private weak var transport: MeshTransport?
    
    // Telemetry counters
    private var totalEvaluatedCount: Int = 0
    private var totalLocallyDeliveredCount: Int = 0
    private var totalForwardedCount: Int = 0
    private var totalDroppedDuplicatesCount: Int = 0
    private var totalDroppedHopLimitCount: Int = 0
    private var totalDroppedRateLimitCount: Int = 0
    private var totalDroppedPolicyCount: Int = 0
    private var totalDroppedBatteryCount: Int = 0
    private var totalDroppedMalformedCount: Int = 0
    private var totalDroppedSecurityCount: Int = 0
    
    public init(
        routingTable: RoutingTableManaging,
        rateLimiter: ForwardingBudgetManaging,
        neighborTable: NeighborManaging,
        seenPacketCache: SeenPacketCache,
        clock: MeshClock = SystemMeshClock(),
        cryptoService: CryptoServiceProvider? = nil,
        sessionProvider: (@Sendable () -> GroupSession?)? = nil,
        policyProvider: (@Sendable () -> RelayPolicyState)? = nil,
        policyManager: RelayPolicyManaging? = nil,
        transport: MeshTransport? = nil
    ) {
        self.routingTable = routingTable
        self.rateLimiter = rateLimiter
        self.neighborTable = neighborTable
        self.seenPacketCache = seenPacketCache
        self.clock = clock
        self.cryptoService = cryptoService
        self.sessionProvider = sessionProvider
        self.policyProvider = policyProvider
        self.policyManager = policyManager
        self.transport = transport
    }
    
    // MARK: - Inbound Packet Evaluation Pipeline
    
    /// Evaluates an inbound wire packet to determine whether it should be delivered locally,
    /// forwarded to other mesh peers, or dropped.
    public func evaluateInboundPacket(
        wireData: Data,
        fromPeerId: String
    ) async -> ForwardingDecision {
        totalEvaluatedCount += 1
        
        // 1. Strict Size & Wire Integrity Verification
        guard wireData.count == PacketConstants.wirePacketSize else {
            totalDroppedMalformedCount += 1
            return .dropMalformed
        }
        
        let byte0 = wireData[wireData.startIndex]
        let version = (byte0 >> 4) & 0x0F
        guard version == PacketConstants.protocolVersion else {
            totalDroppedMalformedCount += 1
            return .dropMalformed
        }
        
        guard let packetType = PacketType(rawValue: byte0 & 0x0F) else {
            totalDroppedMalformedCount += 1
            return .dropMalformed
        }
        
        let hopLimit = wireData[wireData.startIndex + 1]
        let hopCount = wireData[wireData.startIndex + 2]
        
        guard hopLimit >= 1 && hopLimit <= PacketConstants.sosHopLimit else {
            totalDroppedMalformedCount += 1
            return .dropMalformed
        }
        
        // Hop Bound Enforcement (Max 8 hops for standard mesh)
        guard hopCount < hopLimit else {
            totalDroppedHopLimitCount += 1
            if let diag = policyManager as? RelayDiagnosticsProviding {
                await diag.recordDropEvent(reason: .hopLimitExceeded)
            }
            return .dropHopLimitExceeded
        }
        
        let effectiveLimit: UInt8
        switch packetType {
        case .sos:
            effectiveLimit = PacketConstants.sosHopLimit
        case .meetingUpdate:
            effectiveLimit = PacketConstants.meetingPointHopLimit
        case .chatMessage, .ack:
            effectiveLimit = PacketConstants.chatHopLimit
        case .uwbTokenExchange:
            effectiveLimit = PacketConstants.uwbHopLimit
        default:
            effectiveLimit = PacketConstants.defaultHopLimit
        }
        
        guard hopCount < effectiveLimit else {
            totalDroppedHopLimitCount += 1
            if let diag = policyManager as? RelayDiagnosticsProviding {
                await diag.recordDropEvent(reason: .hopLimitExceeded)
            }
            return .dropHopLimitExceeded
        }
        
        guard let rawPacket = try? RawWirePacket.fromWireData(wireData) else {
            totalDroppedMalformedCount += 1
            return .dropMalformed
        }
        
        // 2. Canonical Packet Deduplication Key & Suppression
        let packetKey = PacketKey(wirePacket: rawPacket)
        let isDuplicate = await seenPacketCache.isDuplicateAndRecord(packetKey, now: clock.now())
        if isDuplicate {
            totalDroppedDuplicatesCount += 1
            if let diag = policyManager as? RelayDiagnosticsProviding {
                await diag.recordDropEvent(reason: .duplicate)
            }
            return .dropDuplicate
        }
        
        // 3. Local Group Session Matching & Cryptographic Authentication
        let localSession = sessionProvider?()
        if let session = localSession, rawPacket.envelope.sessionId == session.sessionId {
            // Addressed to our group! Must verify Poly1305 MAC tag and payload integrity
            guard let crypto = cryptoService else {
                totalDroppedSecurityCount += 1
                return .dropSecurityVerificationFailed
            }
            
            let key = SymmetricKey(data: session.symmetricKeyData)
            do {
                let decrypted = try await crypto.open(
                    ciphertext: rawPacket.ciphertext,
                    envelope: rawPacket.envelope,
                    authTag: rawPacket.authTag,
                    using: key
                )
                
                // Freshness & Clock Skew Verification for location and SOS
                if packetType == .locationPing, let ping = try? LocationPingPayload.deserialize(from: decrypted) {
                    let replayFilter = await crypto.replayFilter
                    guard await replayFilter.isTimestampValid(ping.timestamp, now: clock.now()) else {
                        totalDroppedSecurityCount += 1
                        return .dropSecurityVerificationFailed
                    }
                } else if packetType == .sos, let sos = try? SOSPayload.deserialize(from: decrypted) {
                    let replayFilter = await crypto.replayFilter
                    guard await replayFilter.isTimestampValid(sos.timestamp, now: clock.now()) else {
                        totalDroppedSecurityCount += 1
                        return .dropSecurityVerificationFailed
                    }
                } else if packetType == .chatMessage, let chat = try? ChatMessagePayload.deserialize(from: decrypted) {
                    let replayFilter = await crypto.replayFilter
                    guard await replayFilter.isTimestampValid(chat.timestamp, now: clock.now()) else {
                        totalDroppedSecurityCount += 1
                        return .dropSecurityVerificationFailed
                    }
                }
                
                totalLocallyDeliveredCount += 1
                return .deliverLocally
            } catch {
                // Cryptographic verification failed! Tag mismatch, forged payload, or key mismatch
                totalDroppedSecurityCount += 1
                return .dropSecurityVerificationFailed
            }
        }
        
        // 4. Stranger Packet Relaying: Opt-In & Battery Policy Gate
        let policyState: RelayPolicyState
        if let pm = policyManager {
            policyState = await pm.currentState()
        } else if let provider = policyProvider {
            policyState = provider()
        } else {
            policyState = RelayPolicyState(mode: .communalRelayActive)
        }
        
        let now = clock.now()
        guard policyState.isPermitted(at: now) else {
            totalDroppedPolicyCount += 1
            if policyState.batteryLevel < 0.20 || policyState.isLowPowerModeActive {
                totalDroppedBatteryCount += 1
                if let diag = policyManager as? RelayDiagnosticsProviding {
                    await diag.recordDropEvent(reason: .batteryThrottled)
                }
            } else {
                if let diag = policyManager as? RelayDiagnosticsProviding {
                    await diag.recordDropEvent(reason: .policyDisabled)
                }
            }
            return .dropPolicyDisabled
        }
        
        // 5. Rate Limiting Budget Verification
        if packetType == .sos {
            let allowed = await rateLimiter.consumeSOSToken()
            guard allowed else {
                totalDroppedRateLimitCount += 1
                if let diag = policyManager as? RelayDiagnosticsProviding {
                    await diag.recordDropEvent(reason: .rateLimitExceeded)
                }
                return .dropRateLimitExceeded
            }
        } else {
            let allowed = await rateLimiter.consumeOrdinaryToken()
            guard allowed else {
                totalDroppedRateLimitCount += 1
                if let diag = policyManager as? RelayDiagnosticsProviding {
                    await diag.recordDropEvent(reason: .rateLimitExceeded)
                }
                return .dropRateLimitExceeded
            }
        }
        
        // 6. Mutable Metadata Mutation (Byte 2: hopCount &+= 1)
        var mutatedData = wireData
        mutatedData[mutatedData.startIndex + 2] = hopCount + 1
        
        // 7. Route Selection & Next-Hop Resolution
        let activeNeighbors = await neighborTable.activeNeighbors()
        let eligibleNeighbors = activeNeighbors.filter { $0.id != fromPeerId }
        
        if packetType == .sos {
            // Emergency SOS uses immediate bounded flooding
            let targetPeerIds = eligibleNeighbors.map(\.id)
            totalForwardedCount += 1
            if let diag = policyManager as? RelayDiagnosticsProviding {
                await diag.recordForwardEvent(type: .sos)
            }
            return .forward(mutatedWireData: mutatedData, nextHops: targetPeerIds)
        }
        
        if packetType == .routeReq {
            // Stranger relay records reverse route for returning RREP
            await routingTable.recordReverseRoute(
                discoveryKey: rawPacket.envelope.sequenceNumber,
                incomingPeerId: fromPeerId,
                hopCount: hopCount + 1,
                ttl: 15.0
            )
            let targetPeerIds = eligibleNeighbors.map(\.id)
            totalForwardedCount += 1
            if let diag = policyManager as? RelayDiagnosticsProviding {
                await diag.recordForwardEvent(type: .routeReq)
            }
            return .forward(mutatedWireData: mutatedData, nextHops: targetPeerIds)
        }
        
        if packetType == .routeResp {
            // Route response: check for matching reverse route
            if let reverseRoute = await routingTable.popReverseRoute(for: rawPacket.envelope.sequenceNumber) {
                totalForwardedCount += 1
                if let diag = policyManager as? RelayDiagnosticsProviding {
                    await diag.recordForwardEvent(type: .routeResp)
                }
                return .forward(mutatedWireData: mutatedData, nextHops: [reverseRoute.incomingPeerId])
            }
        }
        
        // For directed packets: query routing table
        let destinationId = String(format: "%04X", rawPacket.envelope.sessionId)
        if let route = await routingTable.findRoute(to: destinationId),
           eligibleNeighbors.contains(where: { $0.id == route.nextHopPeerId }) {
            totalForwardedCount += 1
            if let diag = policyManager as? RelayDiagnosticsProviding {
                await diag.recordForwardEvent(type: packetType)
            }
            return .forward(mutatedWireData: mutatedData, nextHops: [route.nextHopPeerId])
        }
        
        // Bounded flooding fallback across remaining connected neighbors
        let targetPeerIds = eligibleNeighbors.map(\.id)
        totalForwardedCount += 1
        if let diag = policyManager as? RelayDiagnosticsProviding {
            await diag.recordForwardEvent(type: packetType)
        }
        return .forward(mutatedWireData: mutatedData, nextHops: targetPeerIds)
    }
    
    // MARK: - Forwarding Execution
    
    /// Executes blind forwarding of the mutated wire packet to the specified next-hop peers.
    public func executeForward(
        wireData: Data,
        toPeerIds: [String]
    ) async throws {
        guard let transport = transport else { return }
        for peerId in toPeerIds {
            _ = try await transport.sendFrame(wireData, to: peerId)
        }
    }
    
    /// Floods an opaque wire packet across all active neighbors except the specified peer.
    public func floodPacket(
        wireData: Data,
        exceptPeerId: String?
    ) async throws {
        let neighbors = await neighborTable.activeNeighbors()
        let targets = neighbors.map(\.id).filter { $0 != exceptPeerId }
        try await executeForward(wireData: wireData, toPeerIds: targets)
    }
    
    // MARK: - Telemetry & Diagnostic Snapshot
    
    public func telemetry() -> RelayTelemetry {
        RelayTelemetry(
            totalPacketsForwarded: totalForwardedCount,
            totalSOSForwarded: 0,
            packetsDroppedRateLimit: totalDroppedRateLimitCount,
            packetsDroppedHopLimit: totalDroppedHopLimitCount,
            duplicatePacketsSuppressed: totalDroppedDuplicatesCount,
            packetsDroppedPolicy: totalDroppedPolicyCount,
            packetsDroppedBattery: totalDroppedBatteryCount,
            activeRoutesCount: 0,
            activeNeighborsCount: 0,
            currentForwardingRatePerSec: 0.0,
            isFestivalSurvivalActive: false
        )
    }
}
