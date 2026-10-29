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
    func now() -> Date
}

/// Standard system clock returning the current hardware date.
public struct SystemMeshClock: MeshClock {
    public init() {}
    public func now() -> Date { Date() }
}

/// Injected mock clock supporting instant, deterministic time advancement.
public final class TestMeshClock: MeshClock, @unchecked Sendable {
    private var currentDate: Date
    private let lock = NSLock()
    
    public init(initialDate: Date = Date()) {
        self.currentDate = initialDate
    }
    
    public func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return currentDate
    }
    
    public func advance(by seconds: TimeInterval) {
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
    
    public init(sessionId: UInt32, sequenceNumber: UInt32) {
        self.sessionId = sessionId & 0x00FFFFFF
        self.sequenceNumber = sequenceNumber
    }
    
    public init(wirePacket: RawWirePacket) {
        self.sessionId = UInt32(wirePacket.envelope.sessionId)
        self.sequenceNumber = wirePacket.envelope.sequenceNumber
    }
    
    public var description: String {
        "PacketKey(sid: 0x\(String(format: "%06X", sessionId)), seq: \(sequenceNumber))"
    }
}

// MARK: - Subsystem 1: Neighbor Management

public enum NeighborState: Sendable, Equatable {
    case connecting
    case connected
    case degraded(packetLossRatio: Double)
    case stale
}

public struct NeighborInfo: Sendable, Equatable, Identifiable {
    public let id: String                    // Remote peer identifier (e.g. initials or UUID)
    public let displayName: String?          // Optional display name from Bonjour TXT
    public let state: NeighborState          // Current link status
    public let rssi: Int8?                   // Signal strength in dBm (-30 dBm to -95 dBm)
    public let lastSeen: Date                // Last packet reception timestamp
    public let roundTripTimeMs: Double?      // Estimated latency over link
    public let isGroupMember: Bool           // True if matches local session ID
    
    public init(
        id: String,
        displayName: String? = nil,
        state: NeighborState = .connected,
        rssi: Int8? = nil,
        lastSeen: Date = Date(),
        roundTripTimeMs: Double? = nil,
        isGroupMember: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.state = state
        self.rssi = rssi
        self.lastSeen = lastSeen
        self.roundTripTimeMs = roundTripTimeMs
        self.isGroupMember = isGroupMember
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

// MARK: - Subsystem 2: Routing Table & Route Discovery

public struct RouteEntry: Sendable, Equatable {
    public let destinationId: String          // Destination member initials or session target
    public let nextHopPeerId: String         // Immediate 1-hop neighbor to transmit to
    public let hopCount: UInt8               // Path metric (1..8)
    public let routeCost: UInt8              // Cumulative cost (hops + link quality penalty)
    public let sequenceNumber: UInt32        // Destination sequence counter
    public let expiresAt: Date               // Eviction deadline
    
    public var isFresh: Bool { Date() < expiresAt }
    
    public init(
        destinationId: String,
        nextHopPeerId: String,
        hopCount: UInt8,
        routeCost: UInt8,
        sequenceNumber: UInt32,
        expiresAt: Date
    ) {
        self.destinationId = destinationId
        self.nextHopPeerId = nextHopPeerId
        self.hopCount = hopCount
        self.routeCost = routeCost
        self.sequenceNumber = sequenceNumber
        self.expiresAt = expiresAt
    }
}

public struct ReverseRouteEntry: Sendable, Equatable {
    public let discoveryKey: UInt32          // Discovery nonce or sequenceNumber
    public let incomingPeerId: String        // Node that forwarded the RREQ
    public let hopCount: UInt8               // Traversal hops observed
    public let expiresAt: Date               // Ephemeral TTL (typically 15s)
    
    public init(
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
}

// MARK: - Subsystem 3: Packet Forwarding & Forwarding Budgets

public enum ForwardingDecision: Sendable, Equatable {
    case deliverLocally                              // Packet is addressed to our session and authenticated
    case forward(mutatedWireData: Data, nextHops: [String]) // Relay blindly
    case dropDuplicate                              // Already seen in 5m LRU cache
    case dropHopLimitExceeded                       // hopCount >= hopLimit (max 8)
    case dropRateLimitExceeded                      // Exceeded 2 pkts/sec budget
    case dropPolicyDisabled                         // Relay participation is OFF or battery < 20%
    case dropMalformed                              // Size != 54B or invalid version
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

public struct RelayPolicyState: Sendable, Equatable {
    public let mode: RelayParticipationMode
    public let batteryLevel: Float           // 0.0 to 1.0
    public let isLowPowerModeActive: Bool
    public let timedExpiryDate: Date?
    
    public init(
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
    
    public var isRelayPermitted: Bool {
        guard mode != .disabled else { return false }
        guard batteryLevel >= 0.20 && !isLowPowerModeActive else { return false }
        if let expiry = timedExpiryDate {
            return Date() < expiry
        }
        return true
    }
}

public protocol RelayPolicyManaging: Actor {
    /// Current effective policy state.
    func currentState() async -> RelayPolicyState
    
    /// Updates user-selected participation mode (from UI or Lock Screen).
    func setParticipationMode(_ mode: RelayParticipationMode) async
    
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
    case malformed
}

public struct RelayTelemetry: Sendable, Equatable {
    public let totalPacketsForwarded: Int
    public let totalSOSForwarded: Int
    public let packetsDroppedRateLimit: Int
    public let packetsDroppedHopLimit: Int
    public let duplicatePacketsSuppressed: Int
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
