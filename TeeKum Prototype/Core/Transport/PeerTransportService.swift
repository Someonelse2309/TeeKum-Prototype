//
//  PeerTransportService.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import Network

/// Low-level Apple Peer-to-Peer Transport Service implementing the `PeerTransport` interface.
///
/// Uses native Apple `Network.framework` (`NWListener`, `NWBrowser`, `NWConnection`) over
/// Apple Wireless Direct Link (AWDL) and Wi-Fi Direct with Bonjour discovery.
///
/// Features:
/// - Zero external dependencies.
/// - Full peer discovery and automatic connection negotiation.
/// - Deterministic tie-breaking to eliminate duplicate connections.
/// - Stream framing handling partial reads and coalesced packets (`StreamMessageFramer`).
/// - Priority coalescing outbox preventing radio saturation and stale location queueing (`PriorityOutboxQueue`).
/// - Bounded retries and exponential backoff on connection failure.
/// - Real-time diagnostics for two-device physical verification.
public actor PeerTransportService: PeerTransport, MeshTransport {
    
    // MARK: - Internal Peer State
    
    private final class PeerConnection: @unchecked Sendable {
        var peerId: String
        var displayName: String
        var endpoint: NWEndpoint
        var connection: NWConnection
        var isReady: Bool = false
        var isOutbound: Bool
        var isGroupMember: Bool
        var capabilities: TransportCapabilities
        let framer = StreamMessageFramer()
        var retryCount: Int = 0
        var lastSeen: Date = Date()
        
        init(
            peerId: String,
            displayName: String,
            endpoint: NWEndpoint,
            connection: NWConnection,
            isOutbound: Bool,
            isGroupMember: Bool = false,
            capabilities: TransportCapabilities = .standardMesh
        ) {
            self.peerId = peerId
            self.displayName = displayName
            self.endpoint = endpoint
            self.connection = connection
            self.isOutbound = isOutbound
            self.isGroupMember = isGroupMember
            self.capabilities = capabilities
        }
    }
    
    // MARK: - Active Session & Radio Configuration
    
    private var activeSession: GroupSession?
    private var serviceType: String = "_teekum._tcp"
    private var isUDP: Bool = false
    private var localPeerId: String = ""
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    private let dispatchQueue = DispatchQueue(label: "com.teekum.peertransport", qos: .userInitiated)
    
    /// Map of connected or connecting peers keyed by peer ID.
    private var connections: [String: PeerConnection] = [:]
    
    private var latestBrowseResults: Set<NWBrowser.Result> = []

    /// Endpoints currently visible in NWBrowser results keyed by peer ID.
    private var discoveredEndpoints: [String: (endpoint: NWEndpoint, displayName: String?, isGroup: Bool)] = [:]
    
    /// Dual-lane prioritized outbox with stranger relay ring buffer.
    private let outbox = PriorityOutboxQueue()
    private var isFlushingOutbox: Bool = false
    private var carryStore = CarryMessageStore()
    private var carryTask: Task<Void, Never>?
    private var carryPowerPermitted = true
    private var bleLink: BLEPeerLink?
    private var blePeers: [String] = []
    private var radioGeneration = UUID()
    
    /// Neighbor management registry.
    public let neighborTable: NeighborTable
    
    /// Forwarding rate limiter enforcing Decision 7 token bucket budgets.
    public let rateLimiter: ForwardingBudgetManaging
    
    /// User-controlled communal mesh relay toggle.
    public private(set) var isRelayEnabled: Bool = true
    
    // MARK: - Streams & Continuations
    
    private var inboundContinuation: AsyncStream<InboundPacket>.Continuation?
    public private(set) var inboundPackets: AsyncStream<InboundPacket>
    
    private var inboundFrameContinuation: AsyncStream<InboundFrame>.Continuation?
    public private(set) var inboundFrames: AsyncStream<InboundFrame>
    
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
    
    // MARK: - Diagnostics Telemetry
    
    public private(set) var currentState: TransportState = .stopped
    private var packetsSentCount: Int = 0
    private var packetsReceivedCount: Int = 0
    private var sendErrorsCount: Int = 0
    private var lastErrorMessage: String?
    private var diagnosticEvents: [DiagnosticEvent] = []
    private let maxDiagnosticEvents: Int = 50
    
    // MARK: - Initialization
    
    public init(
        neighborTable: NeighborTable? = nil,
        rateLimiter: ForwardingBudgetManaging? = nil,
        clock: MeshClock = SystemMeshClock()
    ) {
        let nTable = neighborTable ?? NeighborTable(clock: clock)
        self.neighborTable = nTable
        self.rateLimiter = rateLimiter ?? ForwardingRateLimiter(clock: clock)
        
        var localInbound: AsyncStream<InboundPacket>.Continuation?
        let inStream = AsyncStream<InboundPacket> { continuation in
            localInbound = continuation
        }
        self.inboundPackets = inStream
        self.inboundContinuation = localInbound
        
        var localInboundFrame: AsyncStream<InboundFrame>.Continuation?
        let inFrameStream = AsyncStream<InboundFrame> { continuation in
            localInboundFrame = continuation
        }
        self.inboundFrames = inFrameStream
        self.inboundFrameContinuation = localInboundFrame
        
        var localOutcomes: AsyncStream<SendOutcome>.Continuation?
        let outcomeStream = AsyncStream<SendOutcome> { continuation in
            localOutcomes = continuation
        }
        self.sendOutcomes = outcomeStream
        self.sendOutcomeContinuation = localOutcomes
        
        var localNeighborEvents: AsyncStream<NeighborEvent>.Continuation?
        let nEventStream = AsyncStream<NeighborEvent> { continuation in
            localNeighborEvents = continuation
        }
        self.neighborEvents = nEventStream
        self.neighborEventContinuation = localNeighborEvents
        
        var localPeerUpdates: AsyncStream<[PeerInfo]>.Continuation?
        let peerStream = AsyncStream<[PeerInfo]> { continuation in
            localPeerUpdates = continuation
        }
        self.peerUpdates = peerStream
        self.peerUpdatesContinuation = localPeerUpdates
        
        var localStateUpdates: AsyncStream<TransportState>.Continuation?
        let stateStream = AsyncStream<TransportState> { continuation in
            localStateUpdates = continuation
        }
        self.stateUpdates = stateStream
        self.stateUpdatesContinuation = localStateUpdates
        
        var localErrors: AsyncStream<TransportError>.Continuation?
        let errStream = AsyncStream<TransportError> { continuation in
            localErrors = continuation
        }
        self.transportErrors = errStream
        self.transportErrorsContinuation = localErrors
    }
    
    /// Recreates streams and continuations ensuring fresh, un-terminated streams for each session.
    private func resetStreams() {
        var localInbound: AsyncStream<InboundPacket>.Continuation?
        self.inboundPackets = AsyncStream { continuation in
            localInbound = continuation
        }
        self.inboundContinuation = localInbound
        
        var localInboundFrame: AsyncStream<InboundFrame>.Continuation?
        self.inboundFrames = AsyncStream { continuation in
            localInboundFrame = continuation
        }
        self.inboundFrameContinuation = localInboundFrame
        
        var localOutcomes: AsyncStream<SendOutcome>.Continuation?
        self.sendOutcomes = AsyncStream { continuation in
            localOutcomes = continuation
        }
        self.sendOutcomeContinuation = localOutcomes
        
        var localNeighborEvents: AsyncStream<NeighborEvent>.Continuation?
        self.neighborEvents = AsyncStream { continuation in
            localNeighborEvents = continuation
        }
        self.neighborEventContinuation = localNeighborEvents
        
        var localPeerUpdates: AsyncStream<[PeerInfo]>.Continuation?
        self.peerUpdates = AsyncStream { continuation in
            localPeerUpdates = continuation
        }
        self.peerUpdatesContinuation = localPeerUpdates
        
        var localStateUpdates: AsyncStream<TransportState>.Continuation?
        self.stateUpdates = AsyncStream { continuation in
            localStateUpdates = continuation
        }
        self.stateUpdatesContinuation = localStateUpdates
        
        var localErrors: AsyncStream<TransportError>.Continuation?
        self.transportErrors = AsyncStream { continuation in
            localErrors = continuation
        }
        self.transportErrorsContinuation = localErrors
    }
    
    // MARK: - PeerTransport Protocol Implementation
    
    /// Starts Bonjour advertising (NWListener) and discovery (NWBrowser) for the active session.
    public func start(serviceType: String, session: GroupSession) async throws {
        await stop()
        resetStreams()
        
        self.activeSession = session
        self.serviceType = serviceType
        self.isUDP = serviceType.contains("udp")
        self.localPeerId = session.localInitials
        let generation = radioGeneration
        let link = await BLEPeerLink(
            receive: { [weak self] data, peer in Task { await self?.receiveBLE(data, from: peer, generation: generation) } },
            peersChanged: { [weak self] peers in Task { await self?.updateBLEPeers(peers, generation: generation) } },
            report: { [weak self] message in Task { await self?.logEvent(message, level: .info) } }
        )
        bleLink = link
        await link.start()
        carryTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                await self?.replayCarriedMessage()
            }
        }
        
        logEvent("Starting radio transport (Initials: \(localPeerId), Service: \(serviceType), Mode: \(isUDP ? "UDP" : "TCP")).", level: .info)
        updateState(.starting)
        
        do {
            try startListener()
            try startBrowser()
            updateState(.discovering)
            logEvent("Bonjour listener and browser active. Advertising local peer.", level: .info)
        } catch {
            let transportError = TransportError.listenerFailed(error.localizedDescription)
            updateState(.failed(transportError))
            transportErrorsContinuation?.yield(transportError)
            logEvent("Failed to start radio transport: \(error.localizedDescription)", level: .error)
            throw transportError
        }
    }
    
    /// Stops all radio advertising, browsing, and active socket connections.
    public func stop() async {
        logEvent("Stopping radio transport and releasing sockets.", level: .info)
        
        radioGeneration = UUID()
        let oldBLE = bleLink
        bleLink = nil
        blePeers.removeAll()
        await oldBLE?.stop()
        carryTask?.cancel()
        carryTask = nil
        carryStore.removeAll()
        browser?.cancel()
        browser = nil
        
        listener?.cancel()
        listener = nil
        
        for peer in connections.values {
            peer.connection.cancel()
        }
        connections.removeAll()
        discoveredEndpoints.removeAll()
        latestBrowseResults.removeAll()
        outbox.clear()
        
        for neighbor in await neighborTable.activeNeighbors() {
            await neighborTable.removeNeighbor(peerId: neighbor.id)
        }
        
        activeSession = nil
        updateState(.stopped)
        emitPeerUpdates()
    }
    
    // MARK: - MeshTransport Protocol Implementation
    
    /// Submits a complete 56-byte protocol frame to a specific connected peer.
    public func sendFrame(_ data: Data, to peerId: String) async throws -> SendOutcome {
        guard currentState != .stopped, activeSession != nil else {
            throw TransportError.notStarted
        }
        guard data.count == PacketConstants.wirePacketSize else {
            throw TransportError.invalidPacketSize
        }
        if blePeers.contains(peerId) {
            rememberForCarry(data)
            try outbox.enqueue(data: data, destinationPeerId: peerId, isRelay: false)
            triggerOutboxFlush()
            let packet = try RawWirePacket.fromWireData(data)
            return SendOutcome(destinationPeerId: peerId, packetType: packet.envelope.type, isSuccess: true)
        }
        guard let peer = connections[peerId], peer.isReady else {
            let err = TransportError.peerNotFound(peerId)
            let byte0 = data[data.startIndex]
            let pType = PacketType(rawValue: byte0 & 0x0F) ?? .locationPing
            let failedOutcome = SendOutcome(destinationPeerId: peerId, packetType: pType, isSuccess: false, error: err)
            sendOutcomeContinuation?.yield(failedOutcome)
            throw err
        }
        
        rememberForCarry(data)
        let item = try outbox.enqueue(data: data, destinationPeerId: peerId, isRelay: false)
        triggerOutboxFlush()
        
        let outcome = SendOutcome(id: item.id, destinationPeerId: peerId, packetType: item.packetType, isSuccess: true)
        return outcome
    }
    
    /// Submits a complete 56-byte protocol frame for broadcast to all connected direct peers.
    public func broadcastFrame(_ data: Data) async throws {
        try await broadcastPacket(data)
    }
    
    /// Blindly forwards an opaque 56-byte protocol frame to a designated next hop.
    /// Does not decrypt the payload. Mutates only hopCount (+1) and enforces hopLimit.
    public func forwardFrame(_ data: Data, to nextHopPeerId: String) async throws -> SendOutcome {
        guard currentState != .stopped, activeSession != nil else {
            throw TransportError.notStarted
        }
        guard isRelayEnabled else {
            throw TransportError.relayDisabled
        }
        guard data.count == PacketConstants.wirePacketSize else {
            throw TransportError.invalidPacketSize
        }
        
        let byte0 = data[data.startIndex]
        guard (byte0 >> 4) == PacketConstants.protocolVersion else {
            throw PacketCodecError.unsupportedVersion(byte0 >> 4)
        }
        
        let hopLimit = data[data.startIndex + 1]
        let hopCount = data[data.startIndex + 2]
        
        guard hopLimit >= 1 && hopLimit <= PacketConstants.sosHopLimit else {
            throw PacketCodecError.invalidHopLimit(hopLimit)
        }
        guard hopCount < hopLimit else {
            throw PacketCodecError.hopCountExceededLimit(count: hopCount, limit: hopLimit)
        }
        
        guard blePeers.contains(nextHopPeerId) || connections[nextHopPeerId]?.isReady == true else {
            let err = TransportError.peerNotFound(nextHopPeerId)
            let pType = PacketType(rawValue: byte0 & 0x0F) ?? .locationPing
            let failedOutcome = SendOutcome(destinationPeerId: nextHopPeerId, packetType: pType, isSuccess: false, error: err)
            sendOutcomeContinuation?.yield(failedOutcome)
            throw err
        }
        
        // Rate limiting budget check
        let packetType = PacketType(rawValue: byte0 & 0x0F) ?? .locationPing
        if packetType == .sos {
            let allowed = await rateLimiter.consumeSOSToken()
            guard allowed else {
                throw TransportError.rateLimitExceeded("Urgent SOS forwarding budget exceeded")
            }
        } else {
            let allowed = packetType == .chatMessage || packetType == .ack
                ? await rateLimiter.consumeOrdinaryToken() : await rateLimiter.consumeTelemetryToken()
            guard allowed else {
                throw TransportError.rateLimitExceeded("Ordinary relay budget exhausted")
            }
        }
        
        // Mutate only hopCount: Byte 2 incremented by 1
        var mutatedData = data
        mutatedData[mutatedData.startIndex + 2] = hopCount + 1
        
        rememberForCarry(mutatedData)
        let item = try outbox.enqueue(data: mutatedData, destinationPeerId: nextHopPeerId, isRelay: true)
        triggerOutboxFlush()
        
        let outcome = SendOutcome(id: item.id, destinationPeerId: nextHopPeerId, packetType: packetType, isSuccess: true)
        return outcome
    }
    
    /// Current view of directly reachable Wi-Fi and Bluetooth links.
    public func activeNeighbors() async -> [NeighborInfo] {
        // Forward using live links, not the asynchronously updated telemetry registry.
        // BLE and newly ready Wi-Fi links must be available to the router immediately.
        let wifi = connections.values.filter { $0.isReady }.map {
            NeighborInfo(id: $0.peerId, displayName: $0.displayName, state: .connected,
                rssi: nil, lastSeen: $0.lastSeen, roundTripTimeMs: nil,
                isGroupMember: $0.isGroupMember, capabilities: $0.capabilities)
        }
        return wifi + blePeers.map {
            NeighborInfo(id: $0, displayName: "Bluetooth peer", state: .connected,
                rssi: nil, lastSeen: Date(), roundTripTimeMs: nil,
                isGroupMember: false, capabilities: .standardMesh)
        }
    }
    
    /// Current queue depth across urgent, normal, and relay queues.
    public func queueDepth() async -> QueueDepth {
        outbox.queueDepth
    }
    
    /// Updates relay participation status.
    public func setRelayParticipation(enabled: Bool) async {
        guard isRelayEnabled != enabled else { return }
        isRelayEnabled = enabled
        if !enabled {
            outbox.clearRelayQueue()
            carryStore.removeForeign()
            logEvent("Mesh relay participation disabled. Purged relay outbox.", level: .info)
        } else {
            logEvent("Mesh relay participation enabled.", level: .info)
        }
        
        // Results may have arrived while relay was disabled. NWBrowser need not emit
        // another change when only our local preference changes.
        if enabled, activeSession != nil {
            handleBrowseResults(latestBrowseResults, changes: [])
        }

        // Update Bonjour TXT record dynamically with relay flag
        if let session = activeSession, let currentListener = listener {
            var txtDict: [String: Data] = [:]
            txtDict["sid"] = String(format: "%08X", session.sessionId).data(using: .utf8)
            txtDict["name"] = session.localMemberName.data(using: .utf8)
            txtDict["relay"] = (enabled ? "1" : "0").data(using: .utf8)
            let txtData = NetService.data(fromTXTRecord: txtDict)
            currentListener.service = NWListener.Service(
                name: localPeerId,
                type: serviceType,
                domain: nil,
                txtRecord: txtData
            )
        }
    }
    
    /// Checks if relaying is currently permitted.
    public func isRelayPermitted() async -> Bool {
        isRelayEnabled
    }
    
    // MARK: - Legacy PeerTransport Protocol Implementation
    
    /// Broadcasts a 56-byte wire datagram to all currently connected direct peers.
    public func broadcastPacket(_ data: Data) async throws {
        guard currentState != .stopped, activeSession != nil else {
            throw TransportError.notStarted
        }
        guard data.count == PacketConstants.wirePacketSize else {
            throw TransportError.invalidPacketSize
        }
        
        rememberForCarry(data)
        try outbox.enqueue(data: data, destinationPeerId: nil, isRelay: false)
        triggerOutboxFlush()
    }
    
    /// Transmits a 56-byte wire datagram to a specific connected peer, or broadcasts to direct peers if peerId is not an active transport connection key.
    public func sendPacket(_ data: Data, to peerId: String) async throws {
        if let peer = connections[peerId], peer.isReady {
            _ = try await sendFrame(data, to: peerId)
        } else {
            // Direct connection key not mapped (e.g. member initials target); broadcast over 1-hop direct link
            try await broadcastPacket(data)
        }
    }
    
    /// Returns the number of direct peer connections currently established and operational.
    public func activeDirectPeerCount() async -> Int {
        connections.values.filter { $0.isReady }.count + blePeers.count
    }
    
    /// Captures a live diagnostic snapshot of radio telemetry.
    public func getDiagnostics() async -> TransportDiagnostics {
        let activePeers = connections.values.map { peer in
            PeerInfo(
                id: peer.peerId,
                displayName: peer.displayName,
                rssi: nil,
                isDirectLink: peer.isReady,
                isGroupMember: peer.isGroupMember,
                lastSeen: peer.lastSeen
            )
        }
        
        return TransportDiagnostics(
            localPeerId: localPeerId,
            serviceType: serviceType,
            sessionName: activeSession?.sessionName ?? "None",
            sessionId: activeSession?.sessionId ?? 0,
            state: currentState,
            activeDirectPeers: activePeers + blePeers.map { PeerInfo(id: $0, displayName: "Bluetooth peer", isGroupMember: false) },
            packetsSent: packetsSentCount,
            packetsReceived: packetsReceivedCount,
            obsoletePingsCoalesced: outbox.obsoletePingsCoalesced,
            sendErrors: sendErrorsCount,
            lastError: lastErrorMessage,
            recentEvents: diagnosticEvents
        )
    }
    
    // MARK: - Listener & Browser Setup
    
    private func createParameters() -> NWParameters {
        let params: NWParameters
        if isUDP {
            params = NWParameters.udp
        } else {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 5
            tcpOptions.keepaliveInterval = 2
            tcpOptions.keepaliveCount = 3
            params = NWParameters(tls: nil, tcp: tcpOptions)
        }
        params.includePeerToPeer = true
        return params
    }
    
    private func startListener() throws {
        guard let session = activeSession else { return }
        
        let params = createParameters()
        let newListener = try NWListener(using: params)
        
        // Encode metadata in Bonjour TXT record
        var txtDict: [String: Data] = [:]
        txtDict["sid"] = String(format: "%08X", session.sessionId).data(using: .utf8)
        txtDict["name"] = session.localMemberName.data(using: .utf8)
        txtDict["relay"] = (isRelayEnabled ? "1" : "0").data(using: .utf8)
        let txtData = NetService.data(fromTXTRecord: txtDict)
        
        newListener.service = NWListener.Service(
            name: localPeerId,
            type: serviceType,
            domain: nil,
            txtRecord: txtData
        )
        
        newListener.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleListenerState(state) }
        }
        
        newListener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleIncomingConnection(connection) }
        }
        
        newListener.start(queue: dispatchQueue)
        self.listener = newListener
    }
    
    private func startBrowser() throws {
        let params = createParameters()
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: nil)
        let newBrowser = NWBrowser(for: descriptor, using: params)
        
        newBrowser.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleBrowserState(state) }
        }
        
        newBrowser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { await self?.handleBrowseResults(results, changes: changes) }
        }
        
        newBrowser.start(queue: dispatchQueue)
        self.browser = newBrowser
    }
    
    // MARK: - State Handlers
    
    private func restartListener() {
        guard activeSession != nil, currentState != .stopped else { return }
        listener?.cancel()
        listener = nil
        do {
            try startListener()
            logEvent("NWListener successfully restarted.", level: .info)
        } catch {
            logEvent("NWListener restart failed: \(error.localizedDescription)", level: .error)
        }
    }
    
    private func restartBrowser() {
        guard activeSession != nil, currentState != .stopped else { return }
        browser?.cancel()
        browser = nil
        do {
            try startBrowser()
            logEvent("NWBrowser successfully restarted.", level: .info)
        } catch {
            logEvent("NWBrowser restart failed: \(error.localizedDescription)", level: .error)
        }
    }
    
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            logEvent("NWListener ready on AWDL interface.", level: .info)
        case let .failed(error):
            let err = TransportError.listenerFailed(error.localizedDescription)
            logEvent("NWListener failed: \(error)", level: .error)
            if activeSession != nil, currentState != .stopped {
                logEvent("NWListener failed during active session, scheduling recovery restart...", level: .warning)
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await self?.restartListener()
                }
            } else {
                updateState(.failed(err))
                transportErrorsContinuation?.yield(err)
            }
        case .cancelled:
            logEvent("NWListener cancelled.", level: .info)
        default:
            break
        }
    }
    
    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            logEvent("NWBrowser scanning for Bonjour service '\(serviceType)'.", level: .info)
        case let .failed(error):
            let err = TransportError.browserFailed(error.localizedDescription)
            logEvent("NWBrowser failed: \(error)", level: .error)
            if activeSession != nil, currentState != .stopped {
                logEvent("NWBrowser failed during active session, scheduling recovery restart...", level: .warning)
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await self?.restartBrowser()
                }
            } else {
                updateState(.failed(err))
                transportErrorsContinuation?.yield(err)
            }
        case .cancelled:
            logEvent("NWBrowser cancelled.", level: .info)
        default:
            break
        }
    }
    
    // MARK: - Discovery & Tie-Breaking
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        guard let session = activeSession else { return }
        latestBrowseResults = results
        
        var currentDiscovered: [String: (endpoint: NWEndpoint, displayName: String?, isGroup: Bool)] = [:]
        
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            let remotePeerId = name
            
            // 1. Prevent connecting to self or loopback ghosts from previous session
            guard remotePeerId != localPeerId, !remotePeerId.starts(with: localPeerId) else { continue }
            
            // 2. Check session ID from TXT record if present
            var remoteName: String?
            var isGroup = false
            var isRemoteRelayEnabled = true // default true for backwards compatibility
            if case let .bonjour(txtRecord) = result.metadata {
                if let sidStr = txtRecord.dictionary["sid"] {
                    let expectedSid = String(format: "%08X", session.sessionId)
                    isGroup = (sidStr.uppercased() == expectedSid.uppercased())
                }
                if let name = txtRecord.dictionary["name"] {
                    remoteName = name
                }
                if let relayStr = txtRecord.dictionary["relay"] {
                    isRemoteRelayEnabled = (relayStr == "1")
                }
            }
            
            // If communal relaying is disabled locally, or remote stranger has relay disabled, do not peer
            if !isGroup {
                guard isRelayEnabled && isRemoteRelayEnabled else {
                    continue
                }
            }
            
            currentDiscovered[remotePeerId] = (result.endpoint, remoteName, isGroup)
        }
        
        self.discoveredEndpoints = currentDiscovered
        
        // Evaluate connection initiation for discovered peers
        for (remotePeerId, info) in currentDiscovered {
            // Check if connection already exists
            if let existing = connections[remotePeerId] {
                if existing.isReady {
                    continue // Connection is already established and healthy
                }
            }
            
            // Reconcile pre-discovery inbound link if it arrived before NWBrowser completed
            if localPeerId > remotePeerId {
                if let inboundEntry = connections.first(where: { $0.key.starts(with: "inbound-") }) {
                    let inboundConn = inboundEntry.value
                    connections.removeValue(forKey: inboundEntry.key)
                    inboundConn.peerId = remotePeerId
                    inboundConn.displayName = info.displayName ?? "Peer-\(remotePeerId.prefix(3))"
                    inboundConn.isGroupMember = info.isGroup
                    connections[remotePeerId] = inboundConn
                    logEvent("Matched pre-discovery inbound link to peer \(remotePeerId) (group: \(info.isGroup)).", level: .info)
                    
                    Task {
                        await neighborTable.registerOrUpdateNeighbor(
                            id: remotePeerId,
                            displayName: inboundConn.displayName,
                            state: inboundConn.isReady ? .connected : .connecting,
                            rssi: nil,
                            isGroupMember: info.isGroup,
                            capabilities: inboundConn.capabilities
                        )
                    }
                    emitPeerUpdates()
                    continue
                }
            }
            
            // Deterministic Tie-Breaking:
            // The peer with the smaller peerId initiates the outbound connection.
            // The peer with the larger peerId waits for the incoming connection.
            if localPeerId < remotePeerId {
                logEvent("Discovered peer \(remotePeerId) (Initiator role: local < remote, group: \(info.isGroup)). Connecting...", level: .info)
                initiateOutboundConnection(to: info.endpoint, peerId: remotePeerId, displayName: info.displayName, isGroupMember: info.isGroup)
            } else {
                logEvent("Discovered peer \(remotePeerId) (Listener role: local > remote, group: \(info.isGroup)). Awaiting incoming link.", level: .info)
                // Schedule fallback connection in case remote is delayed
                scheduleFallbackConnection(to: info.endpoint, peerId: remotePeerId, displayName: info.displayName, isGroupMember: info.isGroup)
            }
        }
    }
    
    private func scheduleFallbackConnection(to endpoint: NWEndpoint, peerId: String, displayName: String?, isGroupMember: Bool) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000) // 3.5 seconds
            guard let self = self else { return }
            await self.checkAndFallbackConnect(to: endpoint, peerId: peerId, displayName: displayName, isGroupMember: isGroupMember)
        }
    }
    
    private func checkAndFallbackConnect(to endpoint: NWEndpoint, peerId: String, displayName: String?, isGroupMember: Bool) {
        guard activeSession != nil, currentState != .stopped else { return }
        guard discoveredEndpoints[peerId] != nil else { return }
        
        if let conn = connections[peerId], conn.isReady {
            return // Successfully connected in the meantime
        }
        
        logEvent("Fallback connection trigger for peer \(peerId). Initiating outbound link.", level: .info)
        initiateOutboundConnection(to: endpoint, peerId: peerId, displayName: displayName, isGroupMember: isGroupMember)
    }
    
    // MARK: - Connection Lifecycle
    
    private func initiateOutboundConnection(to endpoint: NWEndpoint, peerId: String, displayName: String?, isGroupMember: Bool) {
        // Prevent duplicate connection attempts
        if let existing = connections[peerId], existing.isReady {
            return
        }
        
        let params = createParameters()
        let nwConn = NWConnection(to: endpoint, using: params)
        
        let peer = PeerConnection(
            peerId: peerId,
            displayName: displayName ?? "Peer-\(peerId.prefix(4))",
            endpoint: endpoint,
            connection: nwConn,
            isOutbound: true,
            isGroupMember: isGroupMember
        )
        connections[peerId] = peer
        
        setupConnectionHandlers(peer)
        nwConn.start(queue: dispatchQueue)
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        // Inbound connection from NWListener
        var resolvedPeerId = "inbound-\(UUID().uuidString.prefix(6))"
        var resolvedDisplayName = "Connecting..."
        var isGroup = false
        
        // Find awaiting discovered peer that should be connecting to us (remoteId < localPeerId)
        if let awaitingPeer = discoveredEndpoints.keys.first(where: { remoteId in
            remoteId < localPeerId && connections[remoteId] == nil
        }) {
            resolvedPeerId = awaitingPeer
            if let info = discoveredEndpoints[awaitingPeer] {
                resolvedDisplayName = info.displayName ?? "Peer-\(awaitingPeer.prefix(3))"
                isGroup = info.isGroup
            }
        }
        
        let peer = PeerConnection(
            peerId: resolvedPeerId,
            displayName: resolvedDisplayName,
            endpoint: connection.endpoint,
            connection: connection,
            isOutbound: false,
            isGroupMember: isGroup
        )
        connections[resolvedPeerId] = peer
        
        logEvent("Incoming link established with peer \(resolvedPeerId) from endpoint \(connection.endpoint).", level: .info)
        setupConnectionHandlers(peer)
        connection.start(queue: dispatchQueue)
    }
    
    private func setupConnectionHandlers(_ peer: PeerConnection) {
        let conn = peer.connection
        
        conn.stateUpdateHandler = { [weak self, weak peer] state in
            guard let self = self, let peer = peer else { return }
            Task { await self.handleConnectionStateChange(peer: peer, state: state) }
        }
    }
    
    private func handleConnectionStateChange(peer: PeerConnection, state: NWConnection.State) {
        switch state {
        case .ready:
            peer.isReady = true
            peer.retryCount = 0
            peer.lastSeen = Date()
            logEvent("Connection to \(peer.peerId) reached READY state (isGroup: \(peer.isGroupMember)).", level: .info)
            
            Task {
                await neighborTable.registerOrUpdateNeighbor(
                    id: peer.peerId,
                    displayName: peer.displayName,
                    state: .connected,
                    rssi: nil,
                    isGroupMember: peer.isGroupMember,
                    capabilities: peer.capabilities
                )
            }
            
            // Start reading frames directly without handshake
            receiveNextBytes(from: peer)
            
            refreshConnectionState()
            emitPeerUpdates()
            triggerOutboxFlush()
            
        case let .failed(error):
            logEvent("Connection to \(peer.peerId) FAILED: \(error.localizedDescription)", level: .warning)
            handleDisconnection(peer: peer, error: error)
            
        case .cancelled:
            logEvent("Connection to \(peer.peerId) CANCELLED.", level: .info)
            handleDisconnection(peer: peer, error: nil)
            
        case let .waiting(error):
            logEvent("Connection to \(peer.peerId) WAITING: \(error.localizedDescription)", level: .warning)
            
        default:
            break
        }
    }
    
    private func handleDisconnection(peer: PeerConnection, error: Error?) {
        let peerId = peer.peerId
        peer.isReady = false
        carryStore.disconnected(peerId)
        peer.connection.cancel()
        connections.removeValue(forKey: peerId)
        
        Task {
            await neighborTable.removeNeighbor(peerId: peerId)
        }
        
        refreshConnectionState()
        emitPeerUpdates()
        
        if let error = error {
            let err = TransportError.connectionFailed(error.localizedDescription)
            transportErrorsContinuation?.yield(err)
            
            // Bounded Reconnect Attempt
            scheduleReconnection(for: peerId, lastEndpoint: peer.endpoint, currentRetry: peer.retryCount)
        }
    }
    
    private func scheduleReconnection(for peerId: String, lastEndpoint: NWEndpoint, currentRetry: Int) {
        guard activeSession != nil, currentState != .stopped else { return }
        
        let maxRetries = 3
        guard currentRetry < maxRetries else {
            logEvent("Peer \(peerId) exceeded max reconnect retries (\(maxRetries)). Marking unreachable.", level: .warning)
            transportErrorsContinuation?.yield(.peerNotFound(peerId))
            return
        }
        
        let nextRetry = currentRetry + 1
        // Exponential backoff: 1.0s, 2.0s, 4.0s + jitter
        let delaySeconds = min(5.0, Double(1 << (nextRetry - 1))) + Double.random(in: 0.1...0.3)
        logEvent("Scheduling reconnection attempt \(nextRetry)/\(maxRetries) to \(peerId) in \(String(format: "%.1f", delaySeconds))s.", level: .info)
        
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let self = self else { return }
            await self.attemptReconnection(peerId: peerId, endpoint: lastEndpoint, retryCount: nextRetry)
        }
    }
    
    private func attemptReconnection(peerId: String, endpoint: NWEndpoint, retryCount: Int) {
        guard activeSession != nil, currentState != .stopped else { return }
        // Ensure no active connection exists before reconnecting
        if let existing = connections[peerId], existing.isReady {
            return
        }
        
        logEvent("Executing reconnection attempt \(retryCount) to peer \(peerId)...", level: .info)
        let params = createParameters()
        let nwConn = NWConnection(to: endpoint, using: params)
        
        let peer = PeerConnection(
            peerId: peerId,
            displayName: "Peer-\(peerId.prefix(4))",
            endpoint: endpoint,
            connection: nwConn,
            isOutbound: true
        )
        peer.retryCount = retryCount
        connections[peerId] = peer
        
        setupConnectionHandlers(peer)
        nwConn.start(queue: dispatchQueue)
    }
    
    // MARK: - Message Framing & Reception
    
    private func receiveNextBytes(from peer: PeerConnection) {
        let conn = peer.connection
        
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak peer] content, _, isComplete, error in
            guard let self = self, let peer = peer else { return }
            
            Task {
                await self.processReceivedData(peer: peer, content: content, isComplete: isComplete, error: error)
            }
        }
    }
    
    private func processReceivedData(peer: PeerConnection, content: Data?, isComplete: Bool, error: NWError?) {
        if let error = error {
            logEvent("Read error on \(peer.peerId): \(error.localizedDescription)", level: .warning)
            handleDisconnection(peer: peer, error: error)
            return
        }
        
        if let data = content, !data.isEmpty {
            peer.lastSeen = Date()
            
            do {
                // Ingest chunk into the message framer to handle partial reads / coalescing
                let frames = try peer.framer.processIncomingChunk(data)
                
                for frame in frames {
                    packetsReceivedCount += 1
                    
                    Task {
                        await neighborTable.recordNeighborActivity(
                            peerId: peer.peerId,
                            rssi: nil,
                            isGroupMember: peer.isGroupMember
                        )
                    }
                    
                    let wirePacket = try? RawWirePacket.fromWireData(frame)
                    
                    let inboundFrame = InboundFrame(
                        rawData: frame,
                        rawPacket: wirePacket,
                        sourcePeerId: peer.peerId,
                        receivedRssi: nil,
                        receivedAt: Date()
                    )
                    inboundFrameContinuation?.yield(inboundFrame)
                    
                    if let wirePacket = wirePacket {
                        let inbound = InboundPacket(
                            rawPacket: wirePacket,
                            sourcePeerId: peer.peerId,
                            receivedRssi: nil,
                            receivedAt: Date()
                        )
                        inboundContinuation?.yield(inbound)
                    }
                }
            } catch {
                logEvent("Framer processing failure: \(error.localizedDescription)", level: .error)
            }
        }
        
        if isComplete {
            logEvent("Peer \(peer.peerId) stream closed (EOF received).", level: .info)
            handleDisconnection(peer: peer, error: nil)
            return
        }
        
        // Loop receive
        receiveNextBytes(from: peer)
    }
    
    private func updateBLEPeers(_ peers: [String], generation: UUID) async {
        guard generation == radioGeneration, activeSession != nil else { return }
        for peer in blePeers where !peers.contains(peer) {
            carryStore.disconnected(peer)
            await neighborTable.removeNeighbor(peerId: peer)
        }
        blePeers = peers
        for peer in peers {
            await neighborTable.registerOrUpdateNeighbor(id: peer, displayName: "Bluetooth peer", state: .connected,
                rssi: nil, isGroupMember: false, capabilities: .standardMesh)
        }
        refreshConnectionState()
        emitPeerUpdates()
    }

    private func receiveBLE(_ data: Data, from peer: String, generation: UUID) {
        guard generation == radioGeneration, activeSession != nil,
              let packet = try? RawWirePacket.fromWireData(data) else { return }
        packetsReceivedCount += 1
        inboundContinuation?.yield(InboundPacket(rawPacket: packet, sourcePeerId: peer))
        inboundFrameContinuation?.yield(InboundFrame(rawData: data, rawPacket: packet, sourcePeerId: peer))
    }

    /// Input is already authenticated by PacketRouter for group traffic, or policy-approved for strangers.
    public func retainReceivedForCarry(_ packet: RawWirePacket, excludingPeerId: String? = nil) {
        guard activeSession != nil,
              packet.envelope.hopCount < packet.envelope.hopLimit else { return }
        var forwarded = packet
        forwarded.envelope.hopCount += 1
        if let data = try? forwarded.toWireData() { rememberForCarry(data, excludingPeerId: excludingPeerId) }
    }

    private func rememberForCarry(_ data: Data, excludingPeerId: String? = nil) {
        guard let session = activeSession, let packet = try? RawWirePacket.fromWireData(data) else { return }
        let foreign = packet.envelope.sessionId != session.sessionId
        guard !foreign || isRelayEnabled else { return }
        carryStore.remember(data, isForeign: foreign, excludingPeerId: excludingPeerId)
    }

    public func updateCarryPowerMetrics(_ batteryLevel: Float, isLowPowerMode: Bool) {
        carryPowerPermitted = batteryLevel >= 0.20 && !isLowPowerMode
    }

    private func replayCarriedMessage() async {
        guard carryPowerPermitted, activeSession != nil, currentState != .stopped else { return }
        let peers = (connections.values.filter { $0.isReady }.map(\.peerId) + blePeers).sorted()
        let generation = radioGeneration
        guard carryStore.nextTransmission(to: peers) != nil,
              await rateLimiter.consumeOrdinaryToken(), activeSession != nil,
              generation == radioGeneration, carryPowerPermitted else { return }
        guard let next = carryStore.nextTransmission(to: peers),
              !next.isForeign || isRelayEnabled else { return }
        do {
            // Already incremented when custody was taken: retries never spend another hop.
            try outbox.enqueue(data: next.data, destinationPeerId: next.peer, isRelay: next.isForeign)
            triggerOutboxFlush()
        } catch {
            logEvent("Carry enqueue deferred: \(error)", level: .warning)
        }
    }

    // MARK: - Transmission & Priority Outbox Flush
    
    private func triggerOutboxFlush() {
        guard !isFlushingOutbox else { return }
        isFlushingOutbox = true
        
        Task { [weak self] in
            await self?.drainOutbox()
        }
    }
    
    private func drainOutbox() async {
        let generation = radioGeneration
        while generation == radioGeneration, let item = outbox.dequeue() {
            guard !item.isRelay || isRelayEnabled else { continue }
            let readyPeers = connections.values.filter { $0.isReady }
            
            if let targetId = item.destinationPeerId {
                // Send to specific target peer
                if blePeers.contains(targetId) {
                    await bleLink?.send(item.packetData, to: targetId)
                    guard generation == radioGeneration else { break }
                    carryStore.markAttempt(item.packetData, to: targetId)
                } else if let peer = connections[targetId], peer.isReady {
                    sendData(item.packetData, on: peer, outboxItem: item)
                } else {
                    logEvent("Target peer \(targetId) unavailable for packet \(item.packetType).", level: .warning)
                    sendErrorsCount += 1
                    let err = TransportError.peerNotFound(targetId)
                    transportErrorsContinuation?.yield(err)
                    
                    Task {
                        await neighborTable.recordTransmissionOutcome(peerId: targetId, success: false)
                    }
                    let failedOutcome = SendOutcome(
                        id: item.id,
                        destinationPeerId: targetId,
                        packetType: item.packetType,
                        isSuccess: false,
                        error: err
                    )
                    sendOutcomeContinuation?.yield(failedOutcome)
                }
            } else {
                // Broadcast to all active direct peers
                await bleLink?.send(item.packetData, to: nil)
                guard generation == radioGeneration else { break }
                for peer in blePeers { carryStore.markAttempt(item.packetData, to: peer) }
                if readyPeers.isEmpty && blePeers.isEmpty {
                    logEvent("No direct peers available to broadcast \(item.packetType).", level: .warning)
                } else {
                    for peer in readyPeers {
                        sendData(item.packetData, on: peer, outboxItem: item)
                    }
                }
            }
        }
        
        isFlushingOutbox = false
    }
    
    private func sendData(_ data: Data, on peer: PeerConnection, outboxItem: OutboxItem) {
        carryStore.markAttempt(data, to: peer.peerId)
        peer.connection.send(content: data, completion: .contentProcessed { [weak self, weak peer] error in
            guard let self = self else { return }
            Task {
                if let error = error {
                    if let p = peer {
                        await self.neighborTable.recordTransmissionOutcome(peerId: p.peerId, success: false)
                    }
                    await self.handleSendError(error, on: peer, outboxItem: outboxItem)
                    
                    let outcome = SendOutcome(
                        id: outboxItem.id,
                        destinationPeerId: peer?.peerId ?? (outboxItem.destinationPeerId ?? "broadcast"),
                        packetType: outboxItem.packetType,
                        isSuccess: false,
                        error: .sendFailed(error.localizedDescription)
                    )
                    await self.recordSendOutcome(outcome)
                } else {
                    if let p = peer {
                        await self.neighborTable.recordTransmissionOutcome(peerId: p.peerId, success: true)
                    }
                    await self.recordSendSuccess(packetType: outboxItem.packetType)
                    
                    let outcome = SendOutcome(
                        id: outboxItem.id,
                        destinationPeerId: peer?.peerId ?? (outboxItem.destinationPeerId ?? "broadcast"),
                        packetType: outboxItem.packetType,
                        isSuccess: true
                    )
                    await self.recordSendOutcome(outcome)
                }
            }
        })
    }
    
    private func recordSendOutcome(_ outcome: SendOutcome) {
        sendOutcomeContinuation?.yield(outcome)
    }
    
    private func recordSendSuccess(packetType: PacketType) {
        packetsSentCount += 1
    }
    
    private func handleSendError(_ error: NWError, on peer: PeerConnection?, outboxItem: OutboxItem) {
        sendErrorsCount += 1
        lastErrorMessage = error.localizedDescription
        logEvent("Transmission error for \(outboxItem.packetType): \(error.localizedDescription)", level: .warning)
        
        // Do not resurrect a foreign retry after the user/power policy stopped relaying.
        guard !outboxItem.isRelay || isRelayEnabled else { return }
        // If retries remain (urgent SOS/ACK or distant relay), requeue with configurable backoff
        if outbox.requeueForRetry(outboxItem) {
            let attempt = outboxItem.attemptCount + 1
            logEvent("Re-queuing \(outboxItem.isRelay ? "stranger relay" : "urgent") packet \(outboxItem.packetType) (attempt \(attempt)/\(outboxItem.maxRetries + 1)).", level: .info)
            let delay = MeshTimingConfiguration.default.distantLinkRetryDelay
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await self?.triggerOutboxFlush()
            }
        } else {
            transportErrorsContinuation?.yield(.sendFailed(error.localizedDescription))
        }
    }
    
    // MARK: - State Management & Helpers
    
    private func updateState(_ newState: TransportState) {
        guard currentState != newState else { return }
        currentState = newState
        stateUpdatesContinuation?.yield(newState)
    }
    
    private func refreshConnectionState() {
        let count = connections.values.filter { $0.isReady }.count + blePeers.count
        if count > 0 {
            updateState(.connected(peerCount: count))
        } else if currentState != .stopped && activeSession != nil {
            updateState(.discovering)
        }
    }
    
    private func emitPeerUpdates() {
        let peerList = connections.values.map { peer in
            PeerInfo(
                id: peer.peerId,
                displayName: peer.displayName,
                rssi: nil,
                isDirectLink: peer.isReady,
                isGroupMember: peer.isGroupMember,
                lastSeen: peer.lastSeen
            )
        }
        peerUpdatesContinuation?.yield(peerList + blePeers.map { PeerInfo(id: $0, displayName: "Bluetooth peer", isGroupMember: false) })
    }
    
    private func logEvent(_ message: String, level: DiagnosticEvent.EventLevel) {
        let event = DiagnosticEvent(message: message, level: level)
        diagnosticEvents.append(event)
        if diagnosticEvents.count > maxDiagnosticEvents {
            diagnosticEvents.removeFirst(diagnosticEvents.count - maxDiagnosticEvents)
        }
    }
    
    // MARK: - Diagnostic Testing Mechanism
    
    /// Interactive diagnostic probe for physical two-device testing.
    /// Sends a diagnostic test message to verify bidirectional link latency and ACK reception.
    ///
    /// - Parameter peerId: Target peer ID, or nil to ping all direct peers.
    /// - Returns: Count of peers to which the test probe was dispatched.
    @discardableResult
    public func sendDiagnosticPing(to peerId: String? = nil) async throws -> Int {
        guard let session = activeSession else {
            throw TransportError.notStarted
        }
        
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .ack,
            hopLimit: 1,
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: UInt32.random(in: 1...UInt32.max)
        )
        
        // 30 bytes dummy payload for ping
        let dummyPayload = Data(repeating: 0xEE, count: PacketConstants.encryptedPayloadSize)
        // 16 bytes auth tag
        let dummyTag = Data(repeating: 0xFF, count: PacketConstants.authTagSize)
        
        let wirePacket = RawWirePacket(envelope: envelope, ciphertext: dummyPayload, authTag: dummyTag)
        let wireData = try wirePacket.toWireData()
        
        if let peerId = peerId {
            try await sendPacket(wireData, to: peerId)
            return 1
        } else {
            let count = await activeDirectPeerCount()
            try await broadcastPacket(wireData)
            return count
        }
    }
}
