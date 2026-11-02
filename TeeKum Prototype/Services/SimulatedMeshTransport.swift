//
//  SimulatedMeshTransport.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation

/// In-memory simulated radio transport conforming to `MeshTransport` and `PeerTransport`.
///
/// Designed for deterministic automated unit and integration testing of multi-node mesh topologies
/// (e.g. 2-node, 3-node linear chain Alice -> Relay B -> Bob, ring topologies, or star networks).
///
/// Capabilities:
/// - Connects multiple simulated nodes without physical Wi-Fi or Bluetooth radios.
/// - Simulates radio link parameters: RSSI signal strength, artificial packet loss ratios, and sudden disconnects.
/// - Validates opaque blind forwarding, hop limit enforcement, rate limiting, and neighbor telemetry.
/// - Thread-safe actor isolation with injected `MeshClock`.
public actor SimulatedMeshTransport: MeshTransport, PeerTransport {
    
    // MARK: - Node Configuration
    
    public let localPeerId: String
    public let clock: MeshClock
    public let neighborTable: NeighborTable
    public let rateLimiter: ForwardingBudgetManaging
    public private(set) var isRelayEnabled: Bool = true
    
    // MARK: - Virtual Mesh Links
    
    private struct VirtualLink {
        weak var transport: SimulatedMeshTransport?
        var rssi: Int8
        var packetLossRatio: Double
        var latency: TimeInterval
        var duplicationRatio: Double
        var isConnected: Bool
        var isGroupMember: Bool
    }
    
    private var links: [String: VirtualLink] = [:]
    
    // Internal prioritized outbox for queue depth testing
    private let outbox: PriorityOutboxQueue
    
    // Operational state
    public private(set) var currentState: TransportState = .stopped
    private var activeSession: GroupSession?
    
    // Telemetry counts
    public private(set) var packetsSentCount: Int = 0
    public private(set) var packetsReceivedCount: Int = 0
    public private(set) var packetsForwardedCount: Int = 0
    public private(set) var sendErrorsCount: Int = 0
    public private(set) var forwardingAttemptsCount: Int = 0
    public private(set) var packetsDuplicatedCount: Int = 0
    public private(set) var duplicatesSuppressedCount: Int = 0
    public private(set) var packetsDroppedRateLimitCount: Int = 0
    public private(set) var packetsDroppedHopLimitCount: Int = 0
    public private(set) var packetsDroppedPolicyCount: Int = 0
    public private(set) var packetsDroppedBatteryCount: Int = 0
    public private(set) var packetsDroppedMalformedCount: Int = 0
    public private(set) var packetsDroppedSecurityCount: Int = 0
    public private(set) var packetsDroppedSimulatedLossCount: Int = 0
    public private(set) var maxHopCountObserved: UInt8 = 0
    public private(set) var hopCountHistogram: [UInt8: Int] = [:]
    public private(set) var totalHopsSum: Int = 0
    public private(set) var totalHopsSamples: Int = 0
    
    // MARK: - Streams & Continuations
    
    private var inboundFrameContinuation: AsyncStream<InboundFrame>.Continuation?
    public private(set) var inboundFrames: AsyncStream<InboundFrame>
    
    private var inboundPacketContinuation: AsyncStream<InboundPacket>.Continuation?
    public private(set) var inboundPackets: AsyncStream<InboundPacket>
    
    private var sendOutcomeContinuation: AsyncStream<SendOutcome>.Continuation?
    public private(set) var sendOutcomes: AsyncStream<SendOutcome>
    
    private var neighborEventContinuation: AsyncStream<NeighborEvent>.Continuation?
    public private(set) var neighborEvents: AsyncStream<NeighborEvent>
    
    private var peerUpdatesContinuation: AsyncStream<[PeerInfo]>.Continuation?
    public private(set) var peerUpdates: AsyncStream<[PeerInfo]>
    
    private var stateUpdatesContinuation: AsyncStream<TransportState>.Continuation?
    public private(set) var stateUpdates: AsyncStream<TransportState>
    
    private var transportErrorsContinuation: AsyncStream<TransportError>.Continuation?
    public private(set) var transportErrors: AsyncStream<TransportError>
    
    // MARK: - Initialization
    
    public init(
        peerId: String,
        clock: MeshClock = SystemMeshClock(),
        neighborTable: NeighborTable? = nil,
        rateLimiter: ForwardingBudgetManaging? = nil,
        maxUrgentCapacity: Int = 16,
        maxRelayCapacity: Int = 32
    ) {
        self.localPeerId = peerId
        self.clock = clock
        let nTable = neighborTable ?? NeighborTable(clock: clock)
        self.neighborTable = nTable
        self.rateLimiter = rateLimiter ?? ForwardingRateLimiter(clock: clock)
        self.outbox = PriorityOutboxQueue(maxUrgentCapacity: maxUrgentCapacity, maxRelayCapacity: maxRelayCapacity)
        
        var inFrameCont: AsyncStream<InboundFrame>.Continuation?
        self.inboundFrames = AsyncStream { inFrameCont = $0 }
        self.inboundFrameContinuation = inFrameCont
        
        var inPktCont: AsyncStream<InboundPacket>.Continuation?
        self.inboundPackets = AsyncStream { inPktCont = $0 }
        self.inboundPacketContinuation = inPktCont
        
        var outcomeCont: AsyncStream<SendOutcome>.Continuation?
        self.sendOutcomes = AsyncStream { outcomeCont = $0 }
        self.sendOutcomeContinuation = outcomeCont
        
        var nEventCont: AsyncStream<NeighborEvent>.Continuation?
        self.neighborEvents = AsyncStream { nEventCont = $0 }
        self.neighborEventContinuation = nEventCont
        
        var peerCont: AsyncStream<[PeerInfo]>.Continuation?
        self.peerUpdates = AsyncStream { peerCont = $0 }
        self.peerUpdatesContinuation = peerCont
        
        var stateCont: AsyncStream<TransportState>.Continuation?
        self.stateUpdates = AsyncStream { stateCont = $0 }
        self.stateUpdatesContinuation = stateCont
        
        var errCont: AsyncStream<TransportError>.Continuation?
        self.transportErrors = AsyncStream { errCont = $0 }
        self.transportErrorsContinuation = errCont
    }
    
    // MARK: - Virtual Radio Topology Management
    
    /// Establishes a virtual bidirectional or unidirectional radio link to another simulated peer.
    public func link(
        to other: SimulatedMeshTransport,
        rssi: Int8 = -60,
        packetLossRatio: Double = 0.0,
        latency: TimeInterval = 0.0,
        duplicationRatio: Double = 0.0,
        isGroupMember: Bool = true,
        bidirectional: Bool = true
    ) async {
        let otherPeerId = await other.localPeerId
        links[otherPeerId] = VirtualLink(
            transport: other,
            rssi: rssi,
            packetLossRatio: packetLossRatio,
            latency: latency,
            duplicationRatio: duplicationRatio,
            isConnected: true,
            isGroupMember: isGroupMember
        )
        
        await neighborTable.registerOrUpdateNeighbor(
            id: otherPeerId,
            displayName: "Sim-\(otherPeerId)",
            state: .connected,
            rssi: rssi,
            isGroupMember: isGroupMember
        )
        
        let info = NeighborInfo(
            id: otherPeerId,
            displayName: "Sim-\(otherPeerId)",
            state: .connected,
            rssi: rssi,
            lastSeen: clock.now(),
            isGroupMember: isGroupMember
        )
        neighborEventContinuation?.yield(.connected(info))
        emitPeerUpdates()
        
        if bidirectional {
            await other.link(
                to: self,
                rssi: rssi,
                packetLossRatio: packetLossRatio,
                latency: latency,
                duplicationRatio: duplicationRatio,
                isGroupMember: isGroupMember,
                bidirectional: false
            )
        }
    }
    
    /// Breaks the virtual link to a peer, simulating out-of-range or radio failure.
    public func disconnect(from peerId: String, bidirectional: Bool = true) async {
        if var link = links[peerId] {
            link.isConnected = false
            links[peerId] = link
            
            await neighborTable.removeNeighbor(peerId: peerId)
            neighborEventContinuation?.yield(.disconnected(peerId: peerId))
            emitPeerUpdates()
            
            if bidirectional, let remote = link.transport {
                await remote.disconnect(from: localPeerId, bidirectional: false)
            }
        }
    }
    
    /// Reconnects a previously disconnected link.
    public func reconnect(to peerId: String, bidirectional: Bool = true) async {
        if var link = links[peerId] {
            link.isConnected = true
            links[peerId] = link
            
            await neighborTable.registerOrUpdateNeighbor(
                id: peerId,
                displayName: "Sim-\(peerId)",
                state: .connected,
                rssi: link.rssi,
                isGroupMember: link.isGroupMember
            )
            
            let info = NeighborInfo(
                id: peerId,
                displayName: "Sim-\(peerId)",
                state: .connected,
                rssi: link.rssi,
                lastSeen: clock.now(),
                isGroupMember: link.isGroupMember
            )
            neighborEventContinuation?.yield(.connected(info))
            emitPeerUpdates()
            
            if bidirectional, let remote = link.transport {
                await remote.reconnect(to: localPeerId, bidirectional: false)
            }
        }
    }
    
    /// Updates simulated RSSI signal strength for link health tests.
    public func setSimulatedRSSI(peerId: String, rssi: Int8) async {
        if var link = links[peerId] {
            link.rssi = rssi
            links[peerId] = link
            await neighborTable.recordNeighborActivity(peerId: peerId, rssi: rssi, isGroupMember: link.isGroupMember)
        }
    }
    
    /// Updates artificial packet loss ratio on a link.
    public func setSimulatedPacketLoss(peerId: String, ratio: Double) {
        if var link = links[peerId] {
            link.packetLossRatio = ratio
            links[peerId] = link
        }
    }
    
    /// Updates artificial transmission latency / delay on a link.
    public func setSimulatedLatency(peerId: String, latency: TimeInterval) {
        if var link = links[peerId] {
            link.latency = latency
            links[peerId] = link
        }
    }
    
    /// Updates artificial link-level packet duplication probability.
    public func setSimulatedDuplication(peerId: String, ratio: Double) {
        if var link = links[peerId] {
            link.duplicationRatio = ratio
            links[peerId] = link
        }
    }
    
    // MARK: - MeshTransport Protocol Implementation
    
    public func start(serviceType: String, session: GroupSession) async throws {
        self.activeSession = session
        self.currentState = .discovering
        stateUpdatesContinuation?.yield(.discovering)
        
        let count = links.values.filter { $0.isConnected }.count
        if count > 0 {
            self.currentState = .connected(peerCount: count)
            stateUpdatesContinuation?.yield(.connected(peerCount: count))
        }
    }
    
    public func stop() async {
        self.currentState = .stopped
        self.activeSession = nil
        outbox.clear()
        stateUpdatesContinuation?.yield(.stopped)
        emitPeerUpdates()
    }
    
    /// Submits a complete 56-byte protocol frame to a specific connected peer.
    public func sendFrame(_ data: Data, to peerId: String) async throws -> SendOutcome {
        guard currentState != .stopped else { throw TransportError.notStarted }
        guard data.count == PacketConstants.wirePacketSize else {
            packetsDroppedMalformedCount += 1
            throw TransportError.invalidPacketSize
        }
        
        let byte0 = data[data.startIndex]
        let packetType = PacketType(rawValue: byte0 & 0x0F) ?? .locationPing
        
        // Enqueue into outbox to maintain queue bounds observability
        _ = try outbox.enqueue(data: data, destinationPeerId: peerId, isRelay: false)
        _ = outbox.dequeue()
        
        guard let link = links[peerId], link.isConnected, let remote = link.transport else {
            let error = TransportError.peerNotFound(peerId)
            await neighborTable.recordTransmissionOutcome(peerId: peerId, success: false)
            let failedOutcome = SendOutcome(destinationPeerId: peerId, packetType: packetType, isSuccess: false, error: error)
            sendOutcomeContinuation?.yield(failedOutcome)
            transportErrorsContinuation?.yield(error)
            sendErrorsCount += 1
            throw error
        }
        
        // Check artificial packet loss
        if link.packetLossRatio > 0.0 && Double.random(in: 0.0...1.0) < link.packetLossRatio {
            packetsDroppedSimulatedLossCount += 1
            let error = TransportError.sendFailed("Simulated transmission loss")
            await neighborTable.recordTransmissionOutcome(peerId: peerId, success: false)
            let failedOutcome = SendOutcome(destinationPeerId: peerId, packetType: packetType, isSuccess: false, error: error)
            sendOutcomeContinuation?.yield(failedOutcome)
            sendErrorsCount += 1
            throw error
        }
        
        // Successful transmission
        packetsSentCount += 1
        await neighborTable.recordTransmissionOutcome(peerId: peerId, success: true)
        
        // Deliver to destination node (respecting simulated latency)
        if link.latency > 0 {
            let lat = link.latency
            let senderId = localPeerId
            let rssiVal = link.rssi
            Task {
                try? await Task.sleep(nanoseconds: UInt64(lat * 1_000_000_000))
                await remote.deliverSimulatedFrame(data, fromPeerId: senderId, rssi: rssiVal)
            }
        } else {
            await remote.deliverSimulatedFrame(data, fromPeerId: localPeerId, rssi: link.rssi)
        }
        
        // Check link-level packet duplication
        if link.duplicationRatio > 0.0 && (link.duplicationRatio >= 1.0 || Double.random(in: 0.0...1.0) < link.duplicationRatio) {
            packetsDuplicatedCount += 1
            let senderId = localPeerId
            let rssiVal = link.rssi
            let dupLatency = max(0.005, link.latency)
            Task {
                try? await Task.sleep(nanoseconds: UInt64(dupLatency * 1_000_000_000))
                await remote.deliverSimulatedFrame(data, fromPeerId: senderId, rssi: rssiVal)
            }
        }
        
        let outcome = SendOutcome(destinationPeerId: peerId, packetType: packetType, isSuccess: true)
        sendOutcomeContinuation?.yield(outcome)
        return outcome
    }
    
    /// Submits a complete 56-byte protocol frame for broadcast to all connected direct peers.
    public func broadcastFrame(_ data: Data) async throws {
        guard currentState != .stopped else { throw TransportError.notStarted }
        guard data.count == PacketConstants.wirePacketSize else { throw TransportError.invalidPacketSize }
        
        let readyPeers = links.filter { $0.value.isConnected }
        for (peerId, _) in readyPeers {
            _ = try? await sendFrame(data, to: peerId)
        }
    }
    
    /// Blindly forwards an opaque 56-byte protocol frame to a designated next hop.
    /// Does not decrypt the payload. Mutates only hopCount (+1) and enforces hopLimit.
    public func forwardFrame(_ data: Data, to nextHopPeerId: String) async throws -> SendOutcome {
        forwardingAttemptsCount += 1
        guard currentState != .stopped else { throw TransportError.notStarted }
        guard isRelayEnabled else {
            packetsDroppedPolicyCount += 1
            throw TransportError.relayDisabled
        }
        guard data.count == PacketConstants.wirePacketSize else {
            packetsDroppedMalformedCount += 1
            throw TransportError.invalidPacketSize
        }
        
        let byte0 = data[data.startIndex]
        guard (byte0 >> 4) == PacketConstants.protocolVersion else {
            packetsDroppedMalformedCount += 1
            throw PacketCodecError.unsupportedVersion(byte0 >> 4)
        }
        
        let hopLimit = data[data.startIndex + 1]
        let hopCount = data[data.startIndex + 2]
        
        guard hopLimit >= 1 && hopLimit <= PacketConstants.sosHopLimit else {
            packetsDroppedMalformedCount += 1
            throw PacketCodecError.invalidHopLimit(hopLimit)
        }
        guard hopCount < hopLimit else {
            packetsDroppedHopLimitCount += 1
            throw PacketCodecError.hopCountExceededLimit(count: hopCount, limit: hopLimit)
        }
        
        let packetType = PacketType(rawValue: byte0 & 0x0F) ?? .locationPing
        
        // Rate limiting check
        if packetType == .sos {
            let allowed = await rateLimiter.consumeSOSToken()
            guard allowed else {
                packetsDroppedRateLimitCount += 1
                throw TransportError.rateLimitExceeded("Urgent SOS forwarding budget exceeded")
            }
        } else {
            let allowed = await rateLimiter.consumeOrdinaryToken()
            guard allowed else {
                packetsDroppedRateLimitCount += 1
                throw TransportError.rateLimitExceeded("Ordinary relay budget exceeded (2 pkts/sec)")
            }
        }
        
        // Mutate only hopCount (Byte 2)
        var mutatedData = data
        mutatedData[mutatedData.startIndex + 2] = hopCount + 1
        
        // Check destination link
        guard let link = links[nextHopPeerId], link.isConnected, let remote = link.transport else {
            let error = TransportError.peerNotFound(nextHopPeerId)
            await neighborTable.recordTransmissionOutcome(peerId: nextHopPeerId, success: false)
            let failedOutcome = SendOutcome(destinationPeerId: nextHopPeerId, packetType: packetType, isSuccess: false, error: error)
            sendOutcomeContinuation?.yield(failedOutcome)
            transportErrorsContinuation?.yield(error)
            sendErrorsCount += 1
            throw error
        }
        
        // Enqueue to relay lane to track ring buffer capacity
        _ = try outbox.enqueue(data: mutatedData, destinationPeerId: nextHopPeerId, isRelay: true)
        _ = outbox.dequeue()
        
        packetsSentCount += 1
        packetsForwardedCount += 1
        await neighborTable.recordTransmissionOutcome(peerId: nextHopPeerId, success: true)
        
        // Deliver respecting latency
        if link.latency > 0 {
            let lat = link.latency
            let senderId = localPeerId
            let rssiVal = link.rssi
            Task {
                try? await Task.sleep(nanoseconds: UInt64(lat * 1_000_000_000))
                await remote.deliverSimulatedFrame(mutatedData, fromPeerId: senderId, rssi: rssiVal)
            }
        } else {
            await remote.deliverSimulatedFrame(mutatedData, fromPeerId: localPeerId, rssi: link.rssi)
        }
        
        // Check link-level packet duplication
        if link.duplicationRatio > 0.0 && (link.duplicationRatio >= 1.0 || Double.random(in: 0.0...1.0) < link.duplicationRatio) {
            packetsDuplicatedCount += 1
            let senderId = localPeerId
            let rssiVal = link.rssi
            let dupLatency = max(0.005, link.latency)
            Task {
                try? await Task.sleep(nanoseconds: UInt64(dupLatency * 1_000_000_000))
                await remote.deliverSimulatedFrame(mutatedData, fromPeerId: senderId, rssi: rssiVal)
            }
        }
        
        let outcome = SendOutcome(destinationPeerId: nextHopPeerId, packetType: packetType, isSuccess: true)
        sendOutcomeContinuation?.yield(outcome)
        return outcome
    }
    
    /// Current view of directly reachable neighbors.
    public func activeNeighbors() async -> [NeighborInfo] {
        await neighborTable.activeNeighbors()
    }
    
    /// Current queue depth across priority lanes.
    public func queueDepth() async -> QueueDepth {
        outbox.queueDepth
    }
    
    /// Updates relay participation status.
    public func setRelayParticipation(enabled: Bool) async {
        guard isRelayEnabled != enabled else { return }
        isRelayEnabled = enabled
        if !enabled {
            outbox.clearRelayQueue()
        }
    }
    
    /// Checks if relaying is currently permitted.
    public func isRelayPermitted() async -> Bool {
        isRelayEnabled
    }
    
    // MARK: - Frame Delivery Mechanism (Called by Remote Linked Nodes)
    
    /// Ingests a frame transmitted over a simulated virtual link.
    public func deliverSimulatedFrame(_ data: Data, fromPeerId: String, rssi: Int8?) async {
        packetsReceivedCount += 1
        if data.count >= 3 {
            let hopCount = data[data.startIndex + 2]
            if hopCount > maxHopCountObserved {
                maxHopCountObserved = hopCount
            }
            hopCountHistogram[hopCount, default: 0] += 1
            totalHopsSum += Int(hopCount)
            totalHopsSamples += 1
        }
        
        let isGroup = links[fromPeerId]?.isGroupMember ?? false
        await neighborTable.recordNeighborActivity(peerId: fromPeerId, rssi: rssi, isGroupMember: isGroup)
        
        let wirePacket = try? RawWirePacket.fromWireData(data)
        let now = clock.now()
        
        let inboundFrame = InboundFrame(
            rawData: data,
            rawPacket: wirePacket,
            sourcePeerId: fromPeerId,
            receivedRssi: rssi,
            receivedAt: now
        )
        inboundFrameContinuation?.yield(inboundFrame)
        
        if let wirePacket = wirePacket {
            let inboundPacket = InboundPacket(
                rawPacket: wirePacket,
                sourcePeerId: fromPeerId,
                receivedRssi: rssi,
                receivedAt: now
            )
            inboundPacketContinuation?.yield(inboundPacket)
        }
    }
    
    // MARK: - Operational Diagnostics & Metrics
    
    public func recordDuplicateSuppression() {
        duplicatesSuppressedCount += 1
    }
    
    public func recordPacketDrop(reason: DropReason) {
        switch reason {
        case .rateLimitExceeded:
            packetsDroppedRateLimitCount += 1
        case .hopLimitExceeded:
            packetsDroppedHopLimitCount += 1
        case .duplicate:
            duplicatesSuppressedCount += 1
        case .batteryThrottled:
            packetsDroppedBatteryCount += 1
            packetsDroppedPolicyCount += 1
        case .policyDisabled:
            packetsDroppedPolicyCount += 1
        case .queueSaturation:
            break
        case .malformed:
            packetsDroppedMalformedCount += 1
        case .securityVerificationFailed:
            packetsDroppedSecurityCount += 1
        case .simulatedLoss:
            packetsDroppedSimulatedLossCount += 1
        }
    }
    
    public func meshDiagnosticsSnapshot() -> MeshDiagnosticsSnapshot {
        MeshDiagnosticsSnapshot(
            forwardingAttempts: forwardingAttemptsCount,
            forwardingSuccesses: packetsForwardedCount,
            forwardingFailures: sendErrorsCount,
            droppedRateLimit: packetsDroppedRateLimitCount,
            droppedHopLimit: packetsDroppedHopLimitCount,
            droppedQueueSaturation: outbox.totalQueueSaturationDrops,
            droppedPolicyDisabled: packetsDroppedPolicyCount,
            droppedBatterySurvival: packetsDroppedBatteryCount,
            droppedMalformed: packetsDroppedMalformedCount,
            droppedSecurityFailed: packetsDroppedSecurityCount,
            droppedSimulatedLoss: packetsDroppedSimulatedLossCount,
            duplicatesSuppressed: duplicatesSuppressedCount,
            routeDiscoveriesInitiated: 0,
            routeDiscoveriesSucceeded: 0,
            routeDiscoveriesFailed: 0,
            routeFailuresOrInvalidations: 0,
            maxHopCountObserved: maxHopCountObserved,
            hopCountHistogram: hopCountHistogram,
            totalHopsSum: totalHopsSum,
            totalHopsSamples: totalHopsSamples,
            queueSaturationDrops: outbox.totalQueueSaturationDrops,
            urgentQueueDepth: outbox.urgentCount,
            relayQueueDepth: outbox.relayCount,
            normalQueueDepth: max(0, outbox.totalQueuedCount - outbox.urgentCount - outbox.relayCount)
        )
    }
    
    // MARK: - Legacy PeerTransport Protocol Conformance
    
    public func broadcastPacket(_ data: Data) async throws {
        try await broadcastFrame(data)
    }
    
    public func sendPacket(_ data: Data, to peerId: String) async throws {
        _ = try await sendFrame(data, to: peerId)
    }
    
    public func activeDirectPeerCount() async -> Int {
        links.values.filter { $0.isConnected }.count
    }
    
    public func getDiagnostics() async -> TransportDiagnostics {
        let activePeers = links.map { (id, link) in
            PeerInfo(
                id: id,
                displayName: "Sim-\(id)",
                rssi: link.rssi,
                isDirectLink: link.isConnected,
                isGroupMember: link.isGroupMember,
                lastSeen: clock.now()
            )
        }
        
        return TransportDiagnostics(
            localPeerId: localPeerId,
            serviceType: "_teekum._tcp",
            sessionName: activeSession?.sessionName ?? "Simulated",
            sessionId: activeSession?.sessionId ?? 0,
            state: currentState,
            activeDirectPeers: activePeers,
            packetsSent: packetsSentCount,
            packetsReceived: packetsReceivedCount,
            obsoletePingsCoalesced: outbox.obsoletePingsCoalesced,
            sendErrors: sendErrorsCount,
            lastError: nil,
            recentEvents: []
        )
    }
    
    private func emitPeerUpdates() {
        let peerList = links.map { (id, link) in
            PeerInfo(
                id: id,
                displayName: "Sim-\(id)",
                rssi: link.rssi,
                isDirectLink: link.isConnected,
                isGroupMember: link.isGroupMember,
                lastSeen: clock.now()
            )
        }
        peerUpdatesContinuation?.yield(peerList)
    }
}
