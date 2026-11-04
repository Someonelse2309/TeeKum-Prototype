//
//  MeshTopologySimulator.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation
import CoreLocation
import CryptoKit

/// Fully autonomous simulated mesh node with complete protocol stack:
/// radio transport, neighbor management, routing table, duplicate cache,
/// blind packet forwarder, and AODV route discovery engine.
public actor SimulatedMeshNode {
    public let id: String
    public let initials: String
    public private(set) var session: GroupSession?
    public let clock: TestMeshClock
    public let cryptoService: CryptoService
    public let routingTable: RoutingTable
    public let neighborTable: NeighborTable
    public let rateLimiter: ForwardingRateLimiter
    public let seenPacketCache: SeenPacketCache
    public let transport: SimulatedMeshTransport
    public let forwarder: PacketForwarder
    public let routeDiscovery: RouteDiscoveryService
    
    private var processingTask: Task<Void, Never>?
    public private(set) var deliveredPackets: [RawWirePacket] = []
    public private(set) var answeredRReqCount: Int = 0
    public private(set) var completedRRespCount: Int = 0
    private var sequenceCounter: UInt32 = 1
    
    public init(
        id: String,
        initials: String,
        session: GroupSession?,
        clock: TestMeshClock
    ) {
        self.id = id
        self.initials = initials
        self.session = session
        self.clock = clock
        self.cryptoService = CryptoService()
        self.routingTable = RoutingTable(clock: clock)
        self.neighborTable = NeighborTable(clock: clock)
        self.rateLimiter = ForwardingRateLimiter(clock: clock)
        self.seenPacketCache = SeenPacketCache(clock: clock)
        
        let trans = SimulatedMeshTransport(
            peerId: id,
            clock: clock,
            neighborTable: neighborTable,
            rateLimiter: rateLimiter
        )
        self.transport = trans
        
        let fwd = PacketForwarder(
            routingTable: routingTable,
            rateLimiter: rateLimiter,
            neighborTable: neighborTable,
            seenPacketCache: seenPacketCache,
            clock: clock,
            cryptoService: cryptoService,
            sessionProvider: { session },
            policyProvider: { RelayPolicyState(mode: .communalRelayActive) },
            transport: trans
        )
        self.forwarder = fwd
        
        let disc = RouteDiscoveryService(
            routingTable: routingTable,
            neighborTable: neighborTable,
            transport: trans,
            cryptoService: cryptoService,
            clock: clock
        )
        self.routeDiscovery = disc
    }
    
    public func start() async {
        let activeSession = session ?? GroupSession(
            sessionId: 0x0000,
            sessionName: "CommunalRelay",
            symmetricKeyData: Data(repeating: 0, count: 32),
            localInitials: initials
        )
        try? await transport.start(serviceType: "_teekum._tcp", session: activeSession)
        
        processingTask = Task { [weak self] in
            guard let self = self else { return }
            let inboundStream = await self.transport.inboundFrames
            for await frame in inboundStream {
                await self.handleInboundFrame(frame)
            }
        }
    }
    
    public func stop() async {
        processingTask?.cancel()
        processingTask = nil
        await routeDiscovery.teardown(sessionId: session.map { UInt32($0.sessionId) })
        await transport.stop()
    }
    
    public func setSession(_ session: GroupSession?) async {
        self.session = session
    }
    
    // MARK: - Frame Ingestion & Dispatch
    
    private func handleInboundFrame(_ frame: InboundFrame) async {
        guard let rawPacket = frame.rawPacket else { return }
        let packetType = rawPacket.envelope.type
        
        // 1. Check if packet is for our group session
        if let activeSession = session, rawPacket.envelope.sessionId == activeSession.sessionId {
            if packetType == .routeReq {
                if let result = try? await routeDiscovery.handleInboundRouteReq(
                    wireData: frame.rawData,
                    fromPeerId: frame.sourcePeerId,
                    session: activeSession
                ) {
                    if case .answeredWithRResp = result {
                        answeredRReqCount += 1
                    }
                }
                return
            } else if packetType == .routeResp {
                if let result = try? await routeDiscovery.handleInboundRouteResp(
                    wireData: frame.rawData,
                    fromPeerId: frame.sourcePeerId,
                    session: activeSession
                ) {
                    if case .completedDiscovery = result {
                        completedRRespCount += 1
                    }
                }
                return
            }
        }
        
        // 2. Route/forward via PacketForwarder
        let decision = await forwarder.evaluateInboundPacket(wireData: frame.rawData, fromPeerId: frame.sourcePeerId)
        switch decision {
        case .deliverLocally:
            deliveredPackets.append(rawPacket)
        case let .forward(mutatedWireData, nextHops):
            try? await forwarder.executeForward(wireData: mutatedWireData, toPeerIds: nextHops)
        case .dropDuplicate:
            await transport.recordDuplicateSuppression()
        case .dropHopLimitExceeded:
            await transport.recordPacketDrop(reason: .hopLimitExceeded)
        case .dropRateLimitExceeded:
            await transport.recordPacketDrop(reason: .rateLimitExceeded)
        case .dropPolicyDisabled:
            await transport.recordPacketDrop(reason: .policyDisabled)
        case .dropMalformed:
            await transport.recordPacketDrop(reason: .malformed)
        case .dropSecurityVerificationFailed:
            await transport.recordPacketDrop(reason: .securityVerificationFailed)
        }
    }
    
    // MARK: - Testing Helpers
    
    public func injectWireFrame(data: Data, fromPeerId: String) async {
        let rawPacket = try? RawWirePacket.fromWireData(data)
        let frame = InboundFrame(
            rawData: data,
            rawPacket: rawPacket,
            sourcePeerId: fromPeerId,
            receivedRssi: -60,
            receivedAt: clock.now()
        )
        await handleInboundFrame(frame)
    }
    
    public func sendLocationPing(
        coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    ) async throws {
        guard let activeSession = session else { throw TransportError.notStarted }
        sequenceCounter += 1
        
        let payload = LocationPingPayload(
            coordinate: coordinate,
            timestamp: clock.now(),
            accuracy: 5,
            senderInitials: initials,
            batteryLevel: 90,
            heading: 0
        )
        let serialized = payload.serialize()
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .locationPing,
            hopLimit: PacketConstants.defaultHopLimit,
            hopCount: 0,
            sessionId: activeSession.sessionId,
            sequenceNumber: sequenceCounter
        )
        let key = SymmetricKey(data: activeSession.symmetricKeyData)
        let (ciphertext, tag) = try await cryptoService.seal(payload: serialized, envelope: envelope, using: key)
        let wirePacket = RawWirePacket(envelope: envelope, ciphertext: ciphertext, authTag: tag)
        let wireData = try wirePacket.toWireData()
        try await transport.broadcastFrame(wireData)
    }
    
    public func sendEmergencySOS(emergencyType: SOSType = .general) async throws {
        guard let activeSession = session else { throw TransportError.notStarted }
        sequenceCounter += 1
        
        let payload = SOSPayload(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            timestamp: clock.now(),
            accuracy: 5,
            sosEventId: UInt32.random(in: 1...UInt32.max),
            senderInitials: initials,
            emergencyType: emergencyType,
            batteryLevel: 90
        )
        let serialized = payload.serialize()
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .sos,
            hopLimit: PacketConstants.sosHopLimit,
            hopCount: 0,
            sessionId: activeSession.sessionId,
            sequenceNumber: sequenceCounter
        )
        let key = SymmetricKey(data: activeSession.symmetricKeyData)
        let (ciphertext, tag) = try await cryptoService.seal(payload: serialized, envelope: envelope, using: key)
        let wirePacket = RawWirePacket(envelope: envelope, ciphertext: ciphertext, authTag: tag)
        let wireData = try wirePacket.toWireData()
        try await transport.broadcastFrame(wireData)
    }
    
    public func diagnostics() async -> MeshDiagnosticsSnapshot {
        var snap = await transport.meshDiagnosticsSnapshot()
        let rDiag = await routeDiscovery.diagnosticsSnapshot()
        snap.routeDiscoveriesInitiated = rDiag.totalDiscoveriesInitiated
        snap.routeDiscoveriesSucceeded = rDiag.totalDiscoveriesSucceeded
        snap.routeDiscoveriesFailed = rDiag.totalDiscoveriesFailed
        snap.routeFailuresOrInvalidations = rDiag.totalRoutesInvalidated
        return snap
    }
}

/// Deterministic multi-node topology test harness for Phase 2 mesh validation.
public actor MeshTopologySimulator {
    public let clock: TestMeshClock
    private var nodes: [String: SimulatedMeshNode] = [:]
    
    public init(clock: TestMeshClock = TestMeshClock()) {
        self.clock = clock
    }
    
    @discardableResult
    public func createNode(
        id: String,
        initials: String,
        session: GroupSession?
    ) async -> SimulatedMeshNode {
        let node = SimulatedMeshNode(id: id, initials: initials, session: session, clock: clock)
        nodes[id] = node
        await node.start()
        return node
    }
    
    @discardableResult
    public func createStrangerRelay(id: String) async -> SimulatedMeshNode {
        await createNode(id: id, initials: "REL", session: nil)
    }
    
    public func node(named id: String) -> SimulatedMeshNode? {
        nodes[id]
    }
    
    public func allNodes() -> [SimulatedMeshNode] {
        Array(nodes.values)
    }
    
    public var nodeCount: Int {
        nodes.count
    }
    
    public func link(
        _ idA: String,
        _ idB: String,
        rssi: Int8 = -60,
        packetLossRatio: Double = 0.0,
        latency: TimeInterval = 0.0,
        duplicationRatio: Double = 0.0
    ) async {
        guard let nodeA = nodes[idA], let nodeB = nodes[idB] else { return }
        let sessionA = await nodeA.session
        let sessionB = await nodeB.session
        let isGroup = sessionA != nil && sessionB != nil && sessionA?.sessionId == sessionB?.sessionId
        await nodeA.transport.link(
            to: nodeB.transport,
            rssi: rssi,
            packetLossRatio: packetLossRatio,
            latency: latency,
            duplicationRatio: duplicationRatio,
            isGroupMember: isGroup,
            bidirectional: true
        )
    }
    
    public func setLinkLatency(_ idA: String, _ idB: String, latency: TimeInterval) async {
        guard let nodeA = nodes[idA], let nodeB = nodes[idB] else { return }
        await nodeA.transport.setSimulatedLatency(peerId: idB, latency: latency)
        await nodeB.transport.setSimulatedLatency(peerId: idA, latency: latency)
    }
    
    public func setLinkDuplication(_ idA: String, _ idB: String, ratio: Double) async {
        guard let nodeA = nodes[idA], let nodeB = nodes[idB] else { return }
        await nodeA.transport.setSimulatedDuplication(peerId: idB, ratio: ratio)
        await nodeB.transport.setSimulatedDuplication(peerId: idA, ratio: ratio)
    }
    
    public func setLinkPacketLoss(_ idA: String, _ idB: String, ratio: Double) async {
        guard let nodeA = nodes[idA], let nodeB = nodes[idB] else { return }
        await nodeA.transport.setSimulatedPacketLoss(peerId: idB, ratio: ratio)
        await nodeB.transport.setSimulatedPacketLoss(peerId: idA, ratio: ratio)
    }
    
    public func disconnect(
        _ idA: String,
        _ idB: String
    ) async {
        guard let nodeA = nodes[idA], let nodeB = nodes[idB] else { return }
        await nodeA.transport.disconnect(from: idB, bidirectional: true)
        await nodeA.routeDiscovery.handleNeighborDisconnected(peerId: idB)
        await nodeB.routeDiscovery.handleNeighborDisconnected(peerId: idA)
    }
    
    public func reconnect(
        _ idA: String,
        _ idB: String
    ) async {
        guard let nodeA = nodes[idA] else { return }
        await nodeA.transport.reconnect(to: idB, bidirectional: true)
    }
    
    /// Connects a list of nodes in a linear chain: chain[0] <-> chain[1] <-> ... <-> chain[N-1]
    public func setupLinearChain(ids: [String], rssi: Int8 = -60) async {
        guard ids.count >= 2 else { return }
        for i in 0..<(ids.count - 1) {
            await link(ids[i], ids[i + 1], rssi: rssi)
        }
    }
    
    /// Sets up a diamond topology: sender links to relay1 and relay2, both link to destination.
    public func setupDiamondTopology(
        sender: String,
        relay1: String,
        relay2: String,
        destination: String,
        rssi: Int8 = -60
    ) async {
        await link(sender, relay1, rssi: rssi)
        await link(sender, relay2, rssi: rssi)
        await link(relay1, destination, rssi: rssi)
        await link(relay2, destination, rssi: rssi)
    }
    
    /// Sets up competing routes: sender -> shortRelay -> destination (2 hops) vs
    /// sender -> longRelay1 -> longRelay2 -> destination (3 hops).
    public func setupCompetingRoutesTopology(
        sender: String,
        shortRelay: String,
        longRelay1: String,
        longRelay2: String,
        destination: String
    ) async {
        // Path A (2 hops)
        await link(sender, shortRelay, rssi: -60)
        await link(shortRelay, destination, rssi: -60)
        
        // Path B (3 hops)
        await link(sender, longRelay1, rssi: -60)
        await link(longRelay1, longRelay2, rssi: -60)
        await link(longRelay2, destination, rssi: -60)
    }
    
    /// Sets up a closed ring topology: 0 <-> 1 <-> 2 <-> ... <-> N-1 <-> 0
    public func setupRingTopology(ids: [String], rssi: Int8 = -60) async {
        guard ids.count >= 3 else { return }
        for i in 0..<(ids.count - 1) {
            await link(ids[i], ids[i + 1], rssi: rssi)
        }
        await link(ids[ids.count - 1], ids[0], rssi: rssi)
    }
    
    public func aggregateDiagnostics() async -> MeshDiagnosticsSnapshot {
        var total = MeshDiagnosticsSnapshot()
        for node in nodes.values {
            let snap = await node.diagnostics()
            total = total + snap
        }
        return total
    }
    
    public func advanceClock(by seconds: TimeInterval) {
        clock.advance(by: seconds)
    }
    
    public func stopAll() async {
        let allNodes = Array(nodes.values)
        for node in allNodes {
            await node.stop()
        }
    }
}

