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
public actor PeerTransportService: PeerTransport {
    
    // MARK: - Handshake Constants
    
    /// 4-byte magic signature for peer introduction handshakes: 'T', 'K', 'P', '1'
    private static let handshakeMagic: [UInt8] = [0x54, 0x4B, 0x50, 0x31]
    
    // MARK: - Internal Peer State
    
    private final class PeerConnection: @unchecked Sendable {
        var peerId: String
        var displayName: String
        var endpoint: NWEndpoint
        var connection: NWConnection
        var isReady: Bool = false
        var isOutbound: Bool
        let framer = StreamMessageFramer()
        var retryCount: Int = 0
        var lastSeen: Date = Date()
        var handshakeCompleted: Bool = false
        
        init(
            peerId: String,
            displayName: String,
            endpoint: NWEndpoint,
            connection: NWConnection,
            isOutbound: Bool
        ) {
            self.peerId = peerId
            self.displayName = displayName
            self.endpoint = endpoint
            self.connection = connection
            self.isOutbound = isOutbound
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
    
    /// Endpoints currently visible in NWBrowser results keyed by peer ID.
    private var discoveredEndpoints: [String: (endpoint: NWEndpoint, displayName: String?)] = [:]
    
    /// Dual-lane prioritized outbox.
    private let outbox = PriorityOutboxQueue()
    private var isFlushingOutbox: Bool = false
    
    // MARK: - Streams & Continuations
    
    private var inboundContinuation: AsyncStream<InboundPacket>.Continuation?
    public private(set) var inboundPackets: AsyncStream<InboundPacket>
    
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
    
    public init() {
        var localInbound: AsyncStream<InboundPacket>.Continuation?
        let inStream = AsyncStream<InboundPacket> { continuation in
            localInbound = continuation
        }
        self.inboundPackets = inStream
        self.inboundContinuation = localInbound
        
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
        self.localPeerId = String(format: "%08X", session.localMemberId)
        
        logEvent("Starting radio transport (ID: \(localPeerId), Service: \(serviceType), Mode: \(isUDP ? "UDP" : "TCP")).", level: .info)
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
        
        browser?.cancel()
        browser = nil
        
        listener?.cancel()
        listener = nil
        
        for peer in connections.values {
            peer.connection.cancel()
        }
        connections.removeAll()
        discoveredEndpoints.removeAll()
        outbox.clear()
        
        activeSession = nil
        updateState(.stopped)
        emitPeerUpdates()
    }
    
    /// Broadcasts a 56-byte wire datagram to all currently connected direct peers.
    public func broadcastPacket(_ data: Data) async throws {
        guard currentState != .stopped, activeSession != nil else {
            throw TransportError.notStarted
        }
        guard data.count == PacketConstants.wirePacketSize else {
            throw TransportError.invalidPacketSize
        }
        
        try outbox.enqueue(data: data, destinationPeerId: nil)
        triggerOutboxFlush()
    }
    
    /// Transmits a 56-byte wire datagram to a specific connected peer.
    public func sendPacket(_ data: Data, to peerId: String) async throws {
        guard currentState != .stopped, activeSession != nil else {
            throw TransportError.notStarted
        }
        guard data.count == PacketConstants.wirePacketSize else {
            throw TransportError.invalidPacketSize
        }
        guard let peer = connections[peerId], peer.isReady else {
            throw TransportError.peerNotFound(peerId)
        }
        
        try outbox.enqueue(data: data, destinationPeerId: peerId)
        triggerOutboxFlush()
    }
    
    /// Returns the number of direct peer connections currently established and operational.
    public func activeDirectPeerCount() async -> Int {
        connections.values.filter { $0.isReady }.count
    }
    
    /// Captures a live diagnostic snapshot of radio telemetry.
    public func getDiagnostics() async -> TransportDiagnostics {
        let activePeers = connections.values.map { peer in
            PeerInfo(
                id: peer.peerId,
                displayName: peer.displayName,
                rssi: nil,
                isDirectLink: peer.isReady,
                lastSeen: peer.lastSeen
            )
        }
        
        return TransportDiagnostics(
            localPeerId: localPeerId,
            serviceType: serviceType,
            sessionName: activeSession?.sessionName ?? "None",
            sessionId: activeSession?.sessionId ?? 0,
            state: currentState,
            activeDirectPeers: activePeers,
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
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
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
    
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            logEvent("NWListener ready on AWDL interface.", level: .info)
        case let .failed(error):
            let err = TransportError.listenerFailed(error.localizedDescription)
            updateState(.failed(err))
            transportErrorsContinuation?.yield(err)
            logEvent("NWListener failed: \(error)", level: .error)
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
            updateState(.failed(err))
            transportErrorsContinuation?.yield(err)
            logEvent("NWBrowser failed: \(error)", level: .error)
        case .cancelled:
            logEvent("NWBrowser cancelled.", level: .info)
        default:
            break
        }
    }
    
    // MARK: - Discovery & Tie-Breaking
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        guard let session = activeSession else { return }
        
        var currentDiscovered: [String: (endpoint: NWEndpoint, displayName: String?)] = [:]
        
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            let remotePeerId = name
            
            // 1. Prevent connecting to self
            guard remotePeerId != localPeerId else { continue }
            
            // 2. Validate session ID from TXT record if present
            var remoteName: String?
            if case let .bonjour(txtRecord) = result.metadata {
                if let sidStr = txtRecord.dictionary["sid"] {
                    let expectedSid = String(format: "%08X", session.sessionId)
                    guard sidStr.uppercased() == expectedSid.uppercased() else {
                        // Discovered peer belongs to a different session; skip
                        continue
                    }
                }
                if let name = txtRecord.dictionary["name"] {
                    remoteName = name
                }
            }
            
            currentDiscovered[remotePeerId] = (result.endpoint, remoteName)
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
            
            // Deterministic Tie-Breaking:
            // The peer with the smaller peerId initiates the outbound connection.
            // The peer with the larger peerId waits for the incoming connection.
            if localPeerId < remotePeerId {
                logEvent("Discovered peer \(remotePeerId) (Initiator role: local < remote). Connecting...", level: .info)
                initiateOutboundConnection(to: info.endpoint, peerId: remotePeerId, displayName: info.displayName)
            } else {
                logEvent("Discovered peer \(remotePeerId) (Listener role: local > remote). Awaiting incoming link.", level: .info)
                // Schedule fallback connection in case remote is delayed
                scheduleFallbackConnection(to: info.endpoint, peerId: remotePeerId, displayName: info.displayName)
            }
        }
    }
    
    private func scheduleFallbackConnection(to endpoint: NWEndpoint, peerId: String, displayName: String?) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000) // 3.5 seconds
            guard let self = self else { return }
            await self.checkAndFallbackConnect(to: endpoint, peerId: peerId, displayName: displayName)
        }
    }
    
    private func checkAndFallbackConnect(to endpoint: NWEndpoint, peerId: String, displayName: String?) {
        guard activeSession != nil, currentState != .stopped else { return }
        guard discoveredEndpoints[peerId] != nil else { return }
        
        if let conn = connections[peerId], conn.isReady {
            return // Successfully connected in the meantime
        }
        
        logEvent("Fallback connection trigger for peer \(peerId). Initiating outbound link.", level: .info)
        initiateOutboundConnection(to: endpoint, peerId: peerId, displayName: displayName)
    }
    
    // MARK: - Connection Lifecycle
    
    private func initiateOutboundConnection(to endpoint: NWEndpoint, peerId: String, displayName: String?) {
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
            isOutbound: true
        )
        connections[peerId] = peer
        
        setupConnectionHandlers(peer)
        nwConn.start(queue: dispatchQueue)
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        // Inbound connection from NWListener
        // Temporary ID until handshake completes
        let tempId = "inbound-\(UUID().uuidString.prefix(6))"
        let peer = PeerConnection(
            peerId: tempId,
            displayName: "Connecting...",
            endpoint: connection.endpoint,
            connection: connection,
            isOutbound: false
        )
        connections[tempId] = peer
        
        logEvent("Incoming link received from endpoint \(connection.endpoint). Starting handshake...", level: .info)
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
            logEvent("Connection to \(peer.peerId) reached READY state.", level: .info)
            
            // Send initial Handshake frame
            sendHandshake(on: peer)
            
            // Start reading frames
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
        peer.connection.cancel()
        connections.removeValue(forKey: peerId)
        
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
    
    // MARK: - Handshake Protocol
    
    private func sendHandshake(on peer: PeerConnection) {
        guard let session = activeSession else { return }
        
        var handshakeData = Data(Self.handshakeMagic)
        var sidBE = session.sessionId.bigEndian
        handshakeData.append(Data(bytes: &sidBE, count: 4))
        var memBE = session.localMemberId.bigEndian
        handshakeData.append(Data(bytes: &memBE, count: 4))
        
        let nameBytes = Array(session.localMemberName.utf8.prefix(20))
        let nameLen = UInt8(nameBytes.count)
        handshakeData.append(nameLen)
        handshakeData.append(contentsOf: nameBytes)
        
        peer.connection.send(content: handshakeData, completion: .contentProcessed { [weak self, weak peer] error in
            if let error = error {
                Task { [weak self] in
                    await self?.logEvent("Failed to send handshake: \(error.localizedDescription)", level: .warning)
                }
            } else {
                peer?.handshakeCompleted = true
            }
        })
    }
    
    private func parseHandshake(_ data: Data, on peer: PeerConnection) -> Bool {
        guard data.count >= 13 else { return false }
        let magic = Array(data.prefix(4))
        guard magic == Self.handshakeMagic else { return false }
        
        let remoteSid = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard let session = activeSession, remoteSid == session.sessionId else {
            logEvent("Handshake rejected: remote session ID 0x\(String(format: "%08X", remoteSid)) does not match active session.", level: .warning)
            return false
        }
        let remoteMemberId = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let nameLen = Int(data[12])
        
        var name = "Member-\(String(format: "%04X", remoteMemberId & 0xFFFF))"
        if data.count >= 13 + nameLen {
            let nameData = data.subdata(in: 13..<(13 + nameLen))
            if let str = String(data: nameData, encoding: .utf8) {
                name = str
            }
        }
        
        let resolvedPeerId = String(format: "%08X", remoteMemberId)
        
        // If this connection was keyed under a temporary ID, re-key it
        if peer.peerId != resolvedPeerId {
            connections.removeValue(forKey: peer.peerId)
            
            // Check for duplicate connection race condition
            if let existing = connections[resolvedPeerId], existing !== peer, existing.isReady {
                // Duplicate connection detected! Tie-break:
                // Keep the outbound connection if local < remote, else keep inbound.
                if localPeerId < resolvedPeerId {
                    if !peer.isOutbound {
                        logEvent("Duplicate connection detected with \(resolvedPeerId). Closing redundant inbound link.", level: .info)
                        peer.connection.cancel()
                        return true
                    } else {
                        existing.connection.cancel()
                    }
                } else {
                    if peer.isOutbound {
                        logEvent("Duplicate connection detected with \(resolvedPeerId). Closing redundant outbound link.", level: .info)
                        peer.connection.cancel()
                        return true
                    } else {
                        existing.connection.cancel()
                    }
                }
            }
            
            // Update the existing peer object in place so active closures remain valid
            peer.peerId = resolvedPeerId
            peer.displayName = name
            peer.isReady = true
            peer.handshakeCompleted = true
            connections[resolvedPeerId] = peer
            
            logEvent("Handshake verified with \(name) (ID: \(resolvedPeerId)). Peer confirmed.", level: .info)
            emitPeerUpdates()
            refreshConnectionState()
            triggerOutboxFlush()
            return true
        }
        
        peer.displayName = name
        peer.handshakeCompleted = true
        emitPeerUpdates()
        refreshConnectionState()
        triggerOutboxFlush()
        return true
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
        
        if var data = content, !data.isEmpty {
            peer.lastSeen = Date()
            
            // Check if this chunk begins with a handshake packet
            if data.count >= 4 && Array(data.prefix(4)) == Self.handshakeMagic {
                if data.count >= 13 {
                    let nameLen = Int(data[12])
                    let handshakeLen = 13 + nameLen
                    let handshakeSlice = data.prefix(min(data.count, handshakeLen))
                    _ = parseHandshake(Data(handshakeSlice), on: peer)
                    
                    if data.count > handshakeLen {
                        data = data.subdata(in: handshakeLen..<data.count)
                    } else {
                        data = Data()
                    }
                } else {
                    _ = parseHandshake(data, on: peer)
                    data = Data()
                }
            }
            
            if !data.isEmpty {
                do {
                    // Ingest chunk into the message framer to handle partial reads / coalescing
                    let frames = try peer.framer.processIncomingChunk(data)
                    
                    for frame in frames {
                        do {
                            let wirePacket = try RawWirePacket.fromWireData(frame)
                            packetsReceivedCount += 1
                            
                            let inbound = InboundPacket(
                                rawPacket: wirePacket,
                                sourcePeerId: peer.peerId,
                                receivedRssi: nil,
                                receivedAt: Date()
                            )
                            inboundContinuation?.yield(inbound)
                        } catch {
                            logEvent("Packet codec error: \(error.localizedDescription)", level: .warning)
                        }
                    }
                } catch {
                    logEvent("Framer processing failure: \(error.localizedDescription)", level: .error)
                }
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
    
    // MARK: - Transmission & Priority Outbox Flush
    
    private func triggerOutboxFlush() {
        guard !isFlushingOutbox else { return }
        isFlushingOutbox = true
        
        Task { [weak self] in
            await self?.drainOutbox()
        }
    }
    
    private func drainOutbox() {
        while let item = outbox.dequeue() {
            let readyPeers = connections.values.filter { $0.isReady }
            
            if let targetId = item.destinationPeerId {
                // Send to specific target peer
                if let peer = connections[targetId], peer.isReady {
                    sendData(item.packetData, on: peer, outboxItem: item)
                } else {
                    logEvent("Target peer \(targetId) unavailable for packet \(item.packetType).", level: .warning)
                    sendErrorsCount += 1
                    transportErrorsContinuation?.yield(.peerNotFound(targetId))
                }
            } else {
                // Broadcast to all active direct peers
                if readyPeers.isEmpty {
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
        peer.connection.send(content: data, completion: .contentProcessed { [weak self, weak peer] error in
            guard let self = self else { return }
            Task {
                if let error = error {
                    await self.handleSendError(error, on: peer, outboxItem: outboxItem)
                } else {
                    await self.recordSendSuccess(packetType: outboxItem.packetType)
                }
            }
        })
    }
    
    private func recordSendSuccess(packetType: PacketType) {
        packetsSentCount += 1
    }
    
    private func handleSendError(_ error: NWError, on peer: PeerConnection?, outboxItem: OutboxItem) {
        sendErrorsCount += 1
        lastErrorMessage = error.localizedDescription
        logEvent("Transmission error for \(outboxItem.packetType): \(error.localizedDescription)", level: .warning)
        
        // If urgent, requeue if retries remain
        if outbox.requeueForRetry(outboxItem) {
            logEvent("Re-queuing urgent packet \(outboxItem.packetType) (attempt \(outboxItem.attemptCount + 1)).", level: .info)
            triggerOutboxFlush()
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
        let count = connections.values.filter { $0.isReady }.count
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
                lastSeen: peer.lastSeen
            )
        }
        peerUpdatesContinuation?.yield(peerList)
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
