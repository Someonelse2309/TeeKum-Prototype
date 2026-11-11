//
//  PeerTransport.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

/// Information regarding an active peer discovered over the radio link.
public struct PeerInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let rssi: Int8?
    public let isDirectLink: Bool
    public let isGroupMember: Bool
    public let lastSeen: Date
    
    public init(
        id: String,
        displayName: String,
        rssi: Int8? = nil,
        isDirectLink: Bool = true,
        isGroupMember: Bool = true,
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.rssi = rssi
        self.isDirectLink = isDirectLink
        self.isGroupMember = isGroupMember
        self.lastSeen = lastSeen
    }
}

/// An incoming 56-byte packet received from the peer-to-peer radio transport.
public struct InboundPacket: Sendable {
    public let rawPacket: RawWirePacket
    public let sourcePeerId: String
    public let receivedRssi: Int8?
    public let receivedAt: Date
    
    public init(
        rawPacket: RawWirePacket,
        sourcePeerId: String,
        receivedRssi: Int8? = nil,
        receivedAt: Date = Date()
    ) {
        self.rawPacket = rawPacket
        self.sourcePeerId = sourcePeerId
        self.receivedRssi = receivedRssi
        self.receivedAt = receivedAt
    }
}

/// Transport-specific errors.
public enum TransportError: Error, LocalizedError, Equatable {
    case notStarted
    case listenerFailed(String)
    case browserFailed(String)
    case connectionFailed(String)
    case sendFailed(String)
    case invalidPacketSize
    case peerNotFound(String)
    case queueFull(String)
    case handshakeFailed(String)
    case relayDisabled
    case hopLimitExceeded(count: UInt8, limit: UInt8)
    case rateLimitExceeded(String)
    case loopDetected(String)
    case sessionInvalid
    case sessionMismatch
    case securityVerificationFailed
    case malformedPacket
    
    public var errorDescription: String? {
        switch self {
        case .notStarted:
            return "Peer transport service is not started."
        case let .listenerFailed(reason):
            return "NWListener failed: \(reason)"
        case let .browserFailed(reason):
            return "NWBrowser failed: \(reason)"
        case let .connectionFailed(reason):
            return "NWConnection failed: \(reason)"
        case let .sendFailed(reason):
            return "Packet transmission failed: \(reason)"
        case .invalidPacketSize:
            return "Wire packet size must be exactly \(PacketConstants.wirePacketSize) bytes."
        case let .peerNotFound(id):
            return "Target peer '\(id)' is not currently reachable."
        case let .queueFull(reason):
            return "Outbox queue capacity exceeded: \(reason)"
        case let .handshakeFailed(reason):
            return "Peer handshake negotiation failed: \(reason)"
        case .relayDisabled:
            return "Mesh relaying is disabled by user policy or battery constraints."
        case let .hopLimitExceeded(count, limit):
            return "Packet hop count (\(count)) reached or exceeded limit (\(limit))."
        case let .rateLimitExceeded(reason):
            return "Forwarding rate limit exceeded: \(reason)"
        case let .loopDetected(reason):
            return "Forwarding loop prevented: \(reason)"
        case .sessionInvalid:
            return "Active cryptographic session is invalid or missing."
        case .sessionMismatch:
            return "Packet session ID does not match the active group session."
        case .securityVerificationFailed:
            return "Cryptographic authentication failed: invalid Poly1305 MAC tag or expired replay timestamp."
        case .malformedPacket:
            return "Packet payload is malformed or corrupted."
        }
    }
}

/// Connection lifecycle and operational states of the peer-to-peer transport.
public enum TransportState: Equatable, Sendable {
    case stopped
    case starting
    case discovering
    case connected(peerCount: Int)
    case failed(TransportError)
    
    public var description: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting Radio..."
        case .discovering:
            return "Searching for Nearby Peers..."
        case let .connected(count):
            return "Connected (\(count) active peer\(count == 1 ? "" : "s"))"
        case let .failed(error):
            return "Transport Failed: \(error.localizedDescription)"
        }
    }
}

/// A timestamped diagnostic event recording transport-level operations.
public struct DiagnosticEvent: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let message: String
    public let level: EventLevel
    
    public enum EventLevel: String, Sendable {
        case info
        case warning
        case error
    }
    
    public init(id: UUID = UUID(), timestamp: Date = Date(), message: String, level: EventLevel = .info) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
        self.level = level
    }
}

/// Live diagnostic snapshot of peer-to-peer radio telemetry for on-device HUD testing.
nonisolated public struct TransportDiagnostics: Sendable {
    public let localPeerId: String
    public let serviceType: String
    public let sessionName: String
    public let sessionId: UInt16
    public let state: TransportState
    public let activeDirectPeers: [PeerInfo]
    public let packetsSent: Int
    public let packetsReceived: Int
    public let obsoletePingsCoalesced: Int
    public let sendErrors: Int
    public let lastError: String?
    public let recentEvents: [DiagnosticEvent]
    
    public init(
        localPeerId: String,
        serviceType: String,
        sessionName: String,
        sessionId: UInt16,
        state: TransportState,
        activeDirectPeers: [PeerInfo],
        packetsSent: Int,
        packetsReceived: Int,
        obsoletePingsCoalesced: Int,
        sendErrors: Int,
        lastError: String?,
        recentEvents: [DiagnosticEvent]
    ) {
        self.localPeerId = localPeerId
        self.serviceType = serviceType
        self.sessionName = sessionName
        self.sessionId = sessionId
        self.state = state
        self.activeDirectPeers = activeDirectPeers
        self.packetsSent = packetsSent
        self.packetsReceived = packetsReceived
        self.obsoletePingsCoalesced = obsoletePingsCoalesced
        self.sendErrors = sendErrors
        self.lastError = lastError
        self.recentEvents = recentEvents
    }
}

/// Authoritative contract for the low-level Apple Peer-to-Peer transport service (`Network.framework`).
/// Must be implemented as a Swift `actor` to guarantee thread-safe radio access.
public protocol PeerTransport: Actor {
    /// Live asynchronous stream of inbound 56-byte binary datagrams.
    var inboundPackets: AsyncStream<InboundPacket> { get }
    
    /// Live asynchronous stream of active peer updates.
    var peerUpdates: AsyncStream<[PeerInfo]> { get }
    
    /// Live asynchronous stream of transport operational state changes.
    var stateUpdates: AsyncStream<TransportState> { get }
    
    /// Live asynchronous stream of transport errors.
    var transportErrors: AsyncStream<TransportError> { get }
    
    /// Starts local Bonjour listener and browser for the active session.
    func start(serviceType: String, session: GroupSession) async throws
    
    /// Stops all listeners, connections, and advertising, releasing radio resources.
    func stop() async
    
    /// Broadcasts a 56-byte datagram to all currently connected direct peers.
    func broadcastPacket(_ data: Data) async throws
    
    /// Transmits a 56-byte datagram to a specific connected peer.
    func sendPacket(_ data: Data, to peerId: String) async throws
    
    /// Retains authenticated group or policy-approved opaque frames for later delivery.
    func retainReceivedForCarry(_ packet: RawWirePacket, excludingPeerId: String?) async

    /// Returns the number of direct peer connections currently established.
    func activeDirectPeerCount() async -> Int
    
    /// Captures a live diagnostic snapshot of transport state and peer telemetry.
    func getDiagnostics() async -> TransportDiagnostics
}

public extension PeerTransport {
    func retainReceivedForCarry(_ packet: RawWirePacket, excludingPeerId: String?) async {}
}
