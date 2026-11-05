//
//  MeshProtocols.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation
import CryptoKit

// MARK: - Testable Clock Abstraction

/// Testable clock protocol allowing deterministic advancement of time in unit and integration tests.
public protocol MeshClock: Sendable {
    nonisolated func now() -> Date
}

/// Standard system clock returning the current hardware date.
public struct SystemMeshClock: MeshClock {
    nonisolated public init() {}
    nonisolated public func now() -> Date { Date() }
}

/// Injected mock clock supporting instant, deterministic time advancement.
public final class TestMeshClock: MeshClock, @unchecked Sendable {
    private var currentDate: Date
    private let lock = NSLock()
    
    public init(initialDate: Date = Date()) {
        self.currentDate = initialDate
    }
    
    nonisolated public func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return currentDate
    }
    
    nonisolated public func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        currentDate = currentDate.addingTimeInterval(seconds)
    }
}

// MARK: - Canonical Packet Key

/// Canonical compact 7-byte packet identity used for duplicate suppression and routing cache keys.
///
/// Computed from:
/// - `sessionId` (24-bit / 3 bytes, 16.7M combinations)
/// - `sequenceNumber` (32-bit / 4 bytes, memberSlot + counter)
///
/// Note: `hopCount` is explicitly excluded so packet identity remains identical across all hops.
/// With 16,777,215 session IDs, cross-group collision is virtually impossible while keeping RAM minimal.
public struct PacketKey: Hashable, Sendable, CustomStringConvertible {
    public let sessionId: UInt32        // 24-bit value (0x000000...0xFFFFFF)
    public let sequenceNumber: UInt32   // 32-bit sequence counter
    public let type: PacketType?        // Optional packet type discriminator
    
    public init(sessionId: UInt32, sequenceNumber: UInt32, type: PacketType? = nil) {
        self.sessionId = sessionId & 0x00FFFFFF
        self.sequenceNumber = sequenceNumber
        self.type = type
    }
    
    public init(wirePacket: RawWirePacket) {
        self.sessionId = UInt32(wirePacket.envelope.sessionId)
        self.sequenceNumber = wirePacket.envelope.sequenceNumber
        self.type = wirePacket.envelope.type
    }
    
    public init?(wireData: Data) {
        guard wireData.count >= 10 else { return nil }
        let typeRaw = wireData[wireData.startIndex] & 0x0F
        let pType = PacketType(rawValue: typeRaw)
        let b3 = UInt32(wireData[wireData.startIndex + 3])
        let b4 = UInt32(wireData[wireData.startIndex + 4])
        let b5 = UInt32(wireData[wireData.startIndex + 5])
        let sid = (b3 << 16) | (b4 << 8) | b5
        let seq = wireData.subdata(in: (wireData.startIndex + 6)..<(wireData.startIndex + 10)).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        self.sessionId = sid
        self.sequenceNumber = seq
        self.type = pType
    }
    
    public var description: String {
        let typeStr = type.map { "\($0)" } ?? "any"
        return "PacketKey(sid: 0x\(String(format: "%06X", sessionId)), seq: \(sequenceNumber), type: \(typeStr))"
    }
}

// MARK: - Subsystem 1: Neighbor Management & Transport Capabilities

/// Supported physical and radio transport capabilities advertised or discovered per neighbor.
public struct TransportCapabilities: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    
    public static let awdlDirect  = TransportCapabilities(rawValue: 1 << 0)
    public static let bleDirect   = TransportCapabilities(rawValue: 1 << 1)
    public static let relayOpaque = TransportCapabilities(rawValue: 1 << 2)
    public static let urgentSOS   = TransportCapabilities(rawValue: 1 << 3)
    
    public static let standardMesh: TransportCapabilities = [.awdlDirect, .relayOpaque, .urgentSOS]
}

public enum NeighborState: Sendable, Equatable {
    case connecting
    case connected
    case degraded(packetLossRatio: Double)
    case stale
}

public enum NeighborEvent: Sendable, Equatable {
    case discovered(NeighborInfo)
    case connected(NeighborInfo)
    case disconnected(peerId: String)
    case stateChanged(peerId: String, oldState: NeighborState, newState: NeighborState)
    case evicted(peerId: String)
}

public struct NeighborInfo: Sendable, Equatable, Identifiable {
    public let id: String                    // Remote peer identifier (e.g. initials or UUID)
    public let displayName: String?          // Optional display name from Bonjour TXT
    public let state: NeighborState          // Current link status
    public let rssi: Int8?                   // Signal strength in dBm (-30 dBm to -95 dBm)
    public let lastSeen: Date                // Last packet reception timestamp
    public let roundTripTimeMs: Double?      // Estimated latency over link
    public let isGroupMember: Bool           // True if matches local session ID
    public let capabilities: TransportCapabilities
    
    public init(
        id: String,
        displayName: String? = nil,
        state: NeighborState = .connected,
        rssi: Int8? = nil,
        lastSeen: Date = Date(),
        roundTripTimeMs: Double? = nil,
        isGroupMember: Bool = false,
        capabilities: TransportCapabilities = .standardMesh
    ) {
        self.id = id
        self.displayName = displayName
        self.state = state
        self.rssi = rssi
        self.lastSeen = lastSeen
        self.roundTripTimeMs = roundTripTimeMs
        self.isGroupMember = isGroupMember
        self.capabilities = capabilities
    }
}

public protocol NeighborManaging: Actor {
    /// Returns all currently discovered and connected 1-hop physical neighbors.
    func activeNeighbors() async -> [NeighborInfo]
    
    /// Updates neighbor telemetry upon packet arrival or keep-alive tick.
    func recordNeighborActivity(peerId: String, rssi: Int8?, isGroupMember: Bool) async
    
    /// Updates neighbor connection state.
    func setNeighborState(peerId: String, state: NeighborState) async
    
    /// Removes a neighbor upon socket disconnection or keep-alive expiry.
    func removeNeighbor(peerId: String) async
    
    /// Selects the healthiest neighbor link for a given candidate set.
    func selectBestNextHop(excluding: Set<String>) async -> String?
    
    /// Evicts neighbors whose keep-alive has lapsed beyond the timeout threshold.
    func evictStaleNeighbors(thresholdSeconds: TimeInterval) async
}

// MARK: - Mesh Transport Foundation & Frame Interfaces

/// Complete received protocol frame carrying raw wire bytes and optional decoded packet.
nonisolated public struct InboundFrame: Sendable {
    public let rawData: Data
    public let rawPacket: RawWirePacket?
    public let sourcePeerId: String
    public let receivedRssi: Int8?
    public let receivedAt: Date
    
    public nonisolated init(
        rawData: Data,
        rawPacket: RawWirePacket? = nil,
        sourcePeerId: String,
        receivedRssi: Int8? = nil,
        receivedAt: Date = Date()
    ) {
        self.rawData = rawData
        self.rawPacket = rawPacket
        self.sourcePeerId = sourcePeerId
        self.receivedRssi = receivedRssi
        self.receivedAt = receivedAt
    }
}

/// Outcome of a local frame submission or next-hop forwarding attempt.
nonisolated public struct SendOutcome: Sendable, Equatable {
    public let id: UUID
    public let destinationPeerId: String
    public let packetType: PacketType
    public let isSuccess: Bool
    public let error: TransportError?
    public let timestamp: Date
    
    public nonisolated init(
        id: UUID = UUID(),
        destinationPeerId: String,
        packetType: PacketType,
        isSuccess: Bool,
        error: TransportError? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.destinationPeerId = destinationPeerId
        self.packetType = packetType
        self.isSuccess = isSuccess
        self.error = error
        self.timestamp = timestamp
    }
}

/// Instantaneous queue depth across priority lanes.
nonisolated public struct QueueDepth: Sendable, Equatable {
    public let urgentCount: Int
    public let normalCount: Int
    public let relayCount: Int
    public let chatCount: Int
    
    public var total: Int { urgentCount + normalCount + relayCount + chatCount }
    
    public nonisolated init(
        urgentCount: Int = 0,
        normalCount: Int = 0,
        relayCount: Int = 0,
        chatCount: Int = 0
    ) {
        self.urgentCount = urgentCount
        self.normalCount = normalCount
        self.relayCount = relayCount
        self.chatCount = chatCount
    }
}

/// Authoritative transport-independent abstraction for Phase 2 multi-hop mesh networking.
public protocol MeshTransport: Actor {
    /// Inbound stream of complete received wire frames.
    var inboundFrames: AsyncStream<InboundFrame> { get }
    
    /// Stream of transmission outcomes for each submitted or forwarded packet.
    var sendOutcomes: AsyncStream<SendOutcome> { get }
    
    /// Stream of neighbor connection and state change events.
    var neighborEvents: AsyncStream<NeighborEvent> { get }
    
    /// Stream of transport errors.
    var transportErrors: AsyncStream<TransportError> { get }
    
    /// Starts the transport for an active session.
    func start(serviceType: String, session: GroupSession) async throws
    
    /// Stops the transport and cleans up all radio/socket resources.
    func stop() async
    
    /// Submits a complete 56-byte protocol frame to a specific connected peer.
    func sendFrame(_ data: Data, to peerId: String) async throws -> SendOutcome
    
    /// Submits a complete 56-byte protocol frame for broadcast to all connected direct peers.
    func broadcastFrame(_ data: Data) async throws
    
    /// Blindly forwards an opaque 56-byte protocol frame to a designated next hop.
    /// Does not decrypt the payload. Mutates only hopCount (+1) and enforces hopLimit.
    func forwardFrame(_ data: Data, to nextHopPeerId: String) async throws -> SendOutcome
    
    /// Current view of directly reachable neighbors.
    func activeNeighbors() async -> [NeighborInfo]
    
    /// Current queue depth across urgent, normal, and relay queues.
    func queueDepth() async -> QueueDepth
    
    /// Updates relay participation status.
    func setRelayParticipation(enabled: Bool) async
    
    /// Checks if relaying is currently permitted.
    func isRelayPermitted() async -> Bool
}

// MARK: - Subsystem 2: Routing Table & Route Discovery

nonisolated public struct RouteEntry: Sendable, Equatable {
    public let destinationId: String          // Destination member initials or session target
    public let nextHopPeerId: String         // Immediate 1-hop neighbor to transmit to
    public let hopCount: UInt8               // Path metric (1..8)
    public let routeCost: UInt8              // Cumulative cost (hops + link quality penalty)
    public let sequenceNumber: UInt32        // Destination sequence counter
    public let expiresAt: Date               // Eviction deadline
    public let sessionId: UInt32?            // Group session identifier for cross-group isolation
    
    public var isFresh: Bool { Date() < expiresAt }
    
    public nonisolated init(
        destinationId: String,
        nextHopPeerId: String,
        hopCount: UInt8,
        routeCost: UInt8,
        sequenceNumber: UInt32,
        expiresAt: Date,
        sessionId: UInt32? = nil
    ) {
        self.destinationId = destinationId
        self.nextHopPeerId = nextHopPeerId
        self.hopCount = hopCount
        self.routeCost = routeCost
        self.sequenceNumber = sequenceNumber
        self.expiresAt = expiresAt
        self.sessionId = sessionId
    }
}

nonisolated public struct ReverseRouteEntry: Sendable, Equatable {
    public let discoveryKey: UInt32          // Discovery nonce or sequenceNumber
    public let incomingPeerId: String        // Node that forwarded the RREQ
    public let hopCount: UInt8               // Traversal hops observed
    public let expiresAt: Date               // Ephemeral TTL (typically 15s)
    
    public nonisolated init(
        discoveryKey: UInt32,
        incomingPeerId: String,
        hopCount: UInt8,
        expiresAt: Date
    ) {
        self.discoveryKey = discoveryKey
        self.incomingPeerId = incomingPeerId
        self.hopCount = hopCount
        self.expiresAt = expiresAt
    }
}

public protocol RoutingTableManaging: Actor {
    /// Looks up an active, unexpired route towards the given destination.
    func findRoute(to destinationId: String) async -> RouteEntry?
    
    /// Inserts or updates a forward route entry.
    func recordForwardRoute(
        destinationId: String,
        nextHop: String,
        hopCount: UInt8,
        cost: UInt8,
        sequenceNumber: UInt32,
        ttl: TimeInterval
    ) async
    
    /// Records a reverse route entry during RREQ forwarding.
    func recordReverseRoute(
        discoveryKey: UInt32,
        incomingPeerId: String,
        hopCount: UInt8,
        ttl: TimeInterval
    ) async
    
    /// Retrieves and consumes a reverse route for RREP forwarding.
    func popReverseRoute(for discoveryKey: UInt32) async -> ReverseRouteEntry?
    
    /// Invalidates a route when a neighbor link breaks.
    func invalidateRoute(towards destinationId: String) async
    
    /// Evicts expired route records from memory.
    func purgeExpiredRoutes() async
    
    /// Clears all routes for session reset or teardown.
    func removeAll() async
}

// MARK: - Route Discovery Enums & Protocol

public enum RouteDiscoveryFailure: Error, Sendable, Equatable, LocalizedError {
    case timeout
    case destinationUnreachable
    case hopLimitExceeded
    case floodingBudgetExhausted
    case alreadyInProgress
    case sessionTerminated
    case loopDetected
    case transportNotReady
    
    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Route discovery timed out without response."
        case .destinationUnreachable:
            return "Target destination is unreachable across the mesh."
        case .hopLimitExceeded:
            return "Route exceeds the maximum allowed 8 hops."
        case .floodingBudgetExhausted:
            return "Route discovery flooding budget exhausted (rate limited)."
        case .alreadyInProgress:
            return "A route discovery for this destination is already in progress."
        case .sessionTerminated:
            return "Active session was terminated during route discovery."
        case .loopDetected:
            return "Routing loop detected; route advertisement rejected."
        case .transportNotReady:
            return "Mesh transport is stopped or has no active radio connections."
        }
    }
}

public enum RouteReqHandlingResult: Sendable, Equatable {
    case answeredWithRResp(targetInitials: String, nextHop: String)
    case forwarded(nextHops: [String], hopCount: UInt8)
    case droppedLoopDetected
    case droppedDuplicate
    case droppedHopLimitExceeded
    case droppedSecurityFailed
    case droppedFloodingThrottled
}

public enum RouteRespHandlingResult: Sendable, Equatable {
    case completedDiscovery(destination: String, nextHop: String, hopCount: UInt8)
    case forwardedToReverseHop(nextHop: String, hopCount: UInt8)
    case droppedStaleOrUnsolicited
    case droppedLoopDetected
    case droppedHopLimitExceeded
    case droppedSecurityFailed
}

nonisolated public struct RouteDiscoveryDiagnostics: Sendable, Equatable {
    public let activeInFlightDiscoveries: Int
    public let totalDiscoveriesInitiated: Int
    public let totalDiscoveriesSucceeded: Int
    public let totalDiscoveriesFailed: Int
    public let totalRReqSent: Int
    public let totalRReqReceived: Int
    public let totalRRespSent: Int
    public let totalRRespReceived: Int
    public let totalRoutesInvalidated: Int
    public let activeRoutesCount: Int
    
    public init(
        activeInFlightDiscoveries: Int = 0,
        totalDiscoveriesInitiated: Int = 0,
        totalDiscoveriesSucceeded: Int = 0,
        totalDiscoveriesFailed: Int = 0,
        totalRReqSent: Int = 0,
        totalRReqReceived: Int = 0,
        totalRRespSent: Int = 0,
        totalRRespReceived: Int = 0,
        totalRoutesInvalidated: Int = 0,
        activeRoutesCount: Int = 0
    ) {
        self.activeInFlightDiscoveries = activeInFlightDiscoveries
        self.totalDiscoveriesInitiated = totalDiscoveriesInitiated
        self.totalDiscoveriesSucceeded = totalDiscoveriesSucceeded
        self.totalDiscoveriesFailed = totalDiscoveriesFailed
        self.totalRReqSent = totalRReqSent
        self.totalRReqReceived = totalRReqReceived
        self.totalRRespSent = totalRRespSent
        self.totalRRespReceived = totalRRespReceived
        self.totalRoutesInvalidated = totalRoutesInvalidated
        self.activeRoutesCount = activeRoutesCount
    }
}

public protocol RouteDiscoveryManaging: Actor {
    /// Resolves an on-demand route towards target initials in the given session.
    /// If an active unexpired route exists in the routing table, returns it immediately.
    /// Otherwise, initiates an AODV route discovery with rate limiting and timeout.
    func resolveRoute(
        to targetInitials: String,
        session: GroupSession,
        timeout: TimeInterval
    ) async throws -> RouteEntry
    
    /// Forces initiation of route discovery regardless of existing cached routes.
    func initiateDiscovery(
        to targetInitials: String,
        session: GroupSession,
        timeout: TimeInterval
    ) async throws -> RouteEntry
    
    /// Ingests and processes an inbound Route Request packet.
    func handleInboundRouteReq(
        wireData: Data,
        fromPeerId: String,
        session: GroupSession
    ) async throws -> RouteReqHandlingResult
    
    /// Ingests and processes an inbound Route Response packet.
    func handleInboundRouteResp(
        wireData: Data,
        fromPeerId: String,
        session: GroupSession
    ) async throws -> RouteRespHandlingResult
    
    /// Handles neighbor disconnection: invalidates dependent routes.
    func handleNeighborDisconnected(peerId: String) async
    
    /// Invalidates a route towards a specific destination.
    func invalidateRoute(towards targetInitials: String, session: GroupSession?) async
    
    /// Teardown: cancels in-flight discoveries and purges session routes.
    func teardown(sessionId: UInt32?) async
    
    /// Live diagnostics snapshot for HUD or telemetry.
    func diagnosticsSnapshot() async -> RouteDiscoveryDiagnostics
}

// MARK: - Subsystem 3: Packet Forwarding & Forwarding Budgets

public enum ForwardingDecision: Sendable, Equatable {
    case deliverLocally                              // Packet is addressed to our session and authenticated
    case forward(mutatedWireData: Data, nextHops: [String]) // Relay blindly
    case dropDuplicate                              // Already seen in 5m LRU cache
    case dropHopLimitExceeded                       // hopCount >= hopLimit (max 8)
    case dropRateLimitExceeded                      // Exceeded 2 pkts/sec budget
    case dropPolicyDisabled                         // Relay participation is OFF or battery < 20%
    case dropMalformed                              // Size != 56B or invalid version
    case dropSecurityVerificationFailed             // Authenticated tag mismatch, replay rejected, or forged packet
}

public protocol ForwardingBudgetManaging: Actor {
    /// Attempts to consume tokens for forwarding ordinary traffic (2 pkts/sec).
    func consumeOrdinaryToken() async -> Bool
    
    /// Attempts to consume tokens for urgent SOS forwarding (max 4 pkts/sec).
    func consumeSOSToken() async -> Bool
    
    /// Current available ordinary token reserve.
    func availableTokens() async -> Double
}

public protocol PacketForwarding: Actor {
    /// Evaluates an inbound wire packet to determine whether it should be delivered locally,
    /// forwarded to other peers, or dropped.
    func evaluateInboundPacket(
        wireData: Data,
        fromPeerId: String
    ) async -> ForwardingDecision
    
    /// Executes the blind forwarding of a packet across designated next hops.
    func executeForward(
        wireData: Data,
        toPeerIds: [String]
    ) async throws
    
    /// Bounded flooding fallback: transmits packet to all connected peers except originator.
    func floodPacket(
        wireData: Data,
        exceptPeerId: String?
    ) async throws
}

// MARK: - Subsystem 4: Relay Participation Policy

public enum RelayParticipationMode: String, Sendable, Codable, CaseIterable {
    case disabled            // Relay OFF: never forwards stranger packets
    case communalRelayActive // Always relay while battery >= 20%
    case timed30Minutes      // Relay for 30 minutes, then automatically pause
}

public enum RelayStatus: Sendable, Equatable {
    case activeAlways
    case activeTimed(remainingSeconds: Int)
    case pausedSurvivalBattery
    case pausedLowPowerMode
    case stoppedDisabled
    case timedExpired
    
    public var isForwardingPermitted: Bool {
        switch self {
        case .activeAlways, .activeTimed:
            return true
        case .pausedSurvivalBattery, .pausedLowPowerMode, .stoppedDisabled, .timedExpired:
            return false
        }
    }
    
    public var displayTitle: String {
        switch self {
        case .activeAlways:
            return "Active (Always)"
        case .activeTimed(let remainingSeconds):
            let mins = max(1, remainingSeconds / 60)
            return "Active (Timed: \(mins)m left)"
        case .pausedSurvivalBattery:
            return "Paused (<20% Battery)"
        case .pausedLowPowerMode:
            return "Paused (Low Power Mode)"
        case .stoppedDisabled:
            return "Stopped (Disabled)"
        case .timedExpired:
            return "Paused (30m Expired)"
        }
    }
}

nonisolated public struct RelayPolicyState: Sendable, Equatable {
    public let mode: RelayParticipationMode
    public let batteryLevel: Float           // 0.0 to 1.0
    public let isLowPowerModeActive: Bool
    public let timedExpiryDate: Date?
    
    public nonisolated init(
        mode: RelayParticipationMode = .communalRelayActive,
        batteryLevel: Float = 1.0,
        isLowPowerModeActive: Bool = false,
        timedExpiryDate: Date? = nil
    ) {
        self.mode = mode
        self.batteryLevel = batteryLevel
        self.isLowPowerModeActive = isLowPowerModeActive
        self.timedExpiryDate = timedExpiryDate
    }
    
    public func isPermitted(at now: Date = Date()) -> Bool {
        guard mode != .disabled else { return false }
        guard batteryLevel >= 0.20 && !isLowPowerModeActive else { return false }
        if let expiry = timedExpiryDate {
            return now < expiry
        }
        return true
    }
    
    public var isRelayPermitted: Bool {
        isPermitted(at: Date())
    }
    
    public func status(at now: Date = Date()) -> RelayStatus {
        guard mode != .disabled else { return .stoppedDisabled }
        if batteryLevel < 0.20 { return .pausedSurvivalBattery }
        if isLowPowerModeActive { return .pausedLowPowerMode }
        if let expiry = timedExpiryDate {
            if now >= expiry {
                return .timedExpired
            } else {
                let remaining = max(0, Int(expiry.timeIntervalSince(now)))
                return .activeTimed(remainingSeconds: remaining)
            }
        }
        return .activeAlways
    }
    
    public func statusDescription(at now: Date = Date()) -> String {
        status(at: now).displayTitle
    }
}

public protocol RelayPolicyManaging: Actor {
    /// Current effective policy state.
    func currentState() async -> RelayPolicyState
    
    /// Updates user-selected participation mode (from UI or Lock Screen).
    func setParticipationMode(_ mode: RelayParticipationMode) async
    
    /// Sets timed participation mode for the specified duration (default 30 minutes / 1800s).
    func setTimedParticipation(durationSeconds: TimeInterval) async
    
    /// Promptly halts relaying and drains/cancels queued work.
    func stopRelaying() async
    
    /// Updates hardware power metrics from UIDevice / ProcessInfo.
    func updatePowerMetrics(batteryLevel: Float, isLowPowerMode: Bool) async
    
    /// Evaluates whether forwarding a packet of the given type is currently permitted.
    func canRelay(packetType: PacketType) async -> Bool
}

// MARK: - Subsystem 5: SOS Forwarding & Multi-Hop Acknowledgement

public protocol SOSForwardingManaging: Actor {
    /// Dispatches an immediate emergency SOS alert across all mesh links via bounded flooding.
    func broadcastEmergencySOS(
        payload: SOSPayload,
        envelope: CleartextEnvelope,
        symmetricKey: SymmetricKey
    ) async throws
    
    /// Processes an inbound SOS packet: authenticates, sounds siren if new, and routes ACK.
    func handleInboundSOSPacket(
        rawPacket: RawWirePacket,
        fromPeerId: String
    ) async throws
    
    /// Generates and transmits an authenticated ACK back to the distressed member.
    func sendDeliveryACK(
        for originalPacket: RawWirePacket,
        status: ACKStatus
    ) async throws
    
    /// Processes an incoming delivery ACK and updates delivery state.
    func handleInboundACK(
        rawPacket: RawWirePacket,
        fromPeerId: String
    ) async
}

// MARK: - Subsystem 6: Relay Diagnostics & Observability

public enum DropReason: Sendable, Equatable {
    case duplicate
    case hopLimitExceeded
    case rateLimitExceeded
    case batteryThrottled
    case policyDisabled
    case queueSaturation
    case malformed
    case securityVerificationFailed
    case simulatedLoss
}

public struct RelayTelemetry: Sendable, Equatable {
    public let totalPacketsForwarded: Int
    public let totalSOSForwarded: Int
    public let packetsDroppedRateLimit: Int
    public let packetsDroppedHopLimit: Int
    public let duplicatePacketsSuppressed: Int
    public let packetsDroppedPolicy: Int
    public let packetsDroppedBattery: Int
    public let activeRoutesCount: Int
    public let activeNeighborsCount: Int
    public let currentForwardingRatePerSec: Double
    public let isFestivalSurvivalActive: Bool
    
    public init(
        totalPacketsForwarded: Int = 0,
        totalSOSForwarded: Int = 0,
        packetsDroppedRateLimit: Int = 0,
        packetsDroppedHopLimit: Int = 0,
        duplicatePacketsSuppressed: Int = 0,
        packetsDroppedPolicy: Int = 0,
        packetsDroppedBattery: Int = 0,
        activeRoutesCount: Int = 0,
        activeNeighborsCount: Int = 0,
        currentForwardingRatePerSec: Double = 0.0,
        isFestivalSurvivalActive: Bool = false
    ) {
        self.totalPacketsForwarded = totalPacketsForwarded
        self.totalSOSForwarded = totalSOSForwarded
        self.packetsDroppedRateLimit = packetsDroppedRateLimit
        self.packetsDroppedHopLimit = packetsDroppedHopLimit
        self.duplicatePacketsSuppressed = duplicatePacketsSuppressed
        self.packetsDroppedPolicy = packetsDroppedPolicy
        self.packetsDroppedBattery = packetsDroppedBattery
        self.activeRoutesCount = activeRoutesCount
        self.activeNeighborsCount = activeNeighborsCount
        self.currentForwardingRatePerSec = currentForwardingRatePerSec
        self.isFestivalSurvivalActive = isFestivalSurvivalActive
    }
}

public protocol RelayDiagnosticsProviding: Actor {
    /// Returns an instantaneous snapshot of mesh performance and relay telemetry.
    func snapshot() async -> RelayTelemetry
    
    /// Records a packet forwarding event.
    func recordForwardEvent(type: PacketType) async
    
    /// Records a packet drop event with specific reason.
    func recordDropEvent(reason: DropReason) async
}
