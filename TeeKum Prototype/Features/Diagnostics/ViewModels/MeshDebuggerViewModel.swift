//
//  MeshDebuggerViewModel.swift
//  TeeKum Prototype
//
//  Created by Nicho on 02/11/26.
//

import SwiftUI
import CoreLocation
import CryptoKit

// MARK: - Debugger Display Modes & Tabs

public enum DebuggerMode: String, CaseIterable, Sendable {
    case liveRadio = "Live Radio"
    case virtualSimulation = "Virtual Simulator"
}

public enum DebuggerTab: String, CaseIterable, Sendable {
    case topology = "Topology"
    case packets = "Packets"
    case injector = "Injector"
    case virtualSandbox = "Virtual Sandbox"
}

public enum PacketLogFilter: String, CaseIterable, Sendable {
    case all = "All"
    case sos = "SOS"
    case ping = "Ping"
    case ack = "ACK"
    case routing = "Route"
    case dropped = "Dropped"
}

public enum PacketDirection: String, Sendable {
    case inbound = "Inbound"
    case outbound = "Outbound"
    case relayed = "Relayed"
    case dropped = "Dropped"
    
    public var icon: String {
        switch self {
        case .inbound: return "arrow.down.circle.fill"
        case .outbound: return "arrow.up.circle.fill"
        case .relayed: return "arrow.triangle.swap"
        case .dropped: return "xmark.circle.fill"
        }
    }
    
    public var color: Color {
        switch self {
        case .inbound: return .green
        case .outbound: return .blue
        case .relayed: return .cyan
        case .dropped: return .red
        }
    }
}

// MARK: - Packet Log Entry Model

public struct MeshPacketLogItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let direction: PacketDirection
    public let type: PacketType
    public let sourcePeer: String
    public let destinationPeer: String?
    public let hopCount: UInt8
    public let hopLimit: UInt8
    public let sessionId: UInt32
    public let sequenceNumber: UInt32
    public let rawLength: Int
    public let rawBytes: Data
    public let envelopeSummary: String
    public let payloadSummary: String
    public let authTagHex: String
    public let dropReason: String?
    public let isDecrypted: Bool
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        direction: PacketDirection,
        type: PacketType,
        sourcePeer: String,
        destinationPeer: String? = nil,
        hopCount: UInt8,
        hopLimit: UInt8,
        sessionId: UInt32,
        sequenceNumber: UInt32,
        rawLength: Int = 56,
        rawBytes: Data = Data(),
        envelopeSummary: String,
        payloadSummary: String,
        authTagHex: String,
        dropReason: String? = nil,
        isDecrypted: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.type = type
        self.sourcePeer = sourcePeer
        self.destinationPeer = destinationPeer
        self.hopCount = hopCount
        self.hopLimit = hopLimit
        self.sessionId = sessionId
        self.sequenceNumber = sequenceNumber
        self.rawLength = rawLength
        self.rawBytes = rawBytes
        self.envelopeSummary = envelopeSummary
        self.payloadSummary = payloadSummary
        self.authTagHex = authTagHex
        self.dropReason = dropReason
        self.isDecrypted = isDecrypted
    }
}

// MARK: - Automated Health Triage Result

public struct MeshTriageItem: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let category: String
    public let title: String
    public let detail: String
    public let status: TriageStatus
    public let remediation: String?
    
    public enum TriageStatus: Sendable {
        case pass
        case warning
        case fail
        
        public var icon: String {
            switch self {
            case .pass: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .fail: return "xmark.octagon.fill"
            }
        }
        
        public var color: Color {
            switch self {
            case .pass: return .green
            case .warning: return .yellow
            case .fail: return .red
            }
        }
    }
}

// MARK: - Virtual Topology Presets

public enum VirtualTopologyPreset: String, CaseIterable, Sendable {
    case linearChain = "3-Hop Linear Chain"
    case diamondMultiPath = "Diamond Multi-Path"
    case competingRoutes = "Competing Routes (2 vs 3)"
    case closedRing = "4-Node Closed Ring"
    
    public var description: String {
        switch self {
        case .linearChain:
            return "Alice -> Relay 1 -> Relay 2 -> Bob. Tests linear multi-hop traversal and hop increment."
        case .diamondMultiPath:
            return "Alice -> [Relay 1, Relay 2] -> Bob. Tests multi-path duplicate suppression."
        case .competingRoutes:
            return "Path A (2 hops) vs Path B (3 hops). Tests shorter-hop preference and sequence monotonicity."
        case .closedRing:
            return "Node 1 <-> 2 <-> 3 <-> 4 <-> 1. Tests routing loop mitigation and hop-limit boundaries."
        }
    }
}

// MARK: - View Model

@Observable
public final class MeshDebuggerViewModel: @unchecked Sendable {
    
    // Mode & Tabs
    public var mode: DebuggerMode = .liveRadio
    public var selectedTab: DebuggerTab = .topology
    public var packetFilter: PacketLogFilter = .all
    public var searchQuery: String = ""
    public var selectedPacket: MeshPacketLogItem? = nil
    
    // Live Telemetry
    public var transportState: TransportState = .stopped
    public var liveNeighbors: [NeighborInfo] = []
    public var livePeerCount: Int = 0
    public var activeSession: GroupSession?
    public var relayPolicyState: RelayPolicyState?
    
    // Automated Health Triage
    public var triageItems: [MeshTriageItem] = []
    public var isTriageRunning: Bool = false
    public var overallTriageStatus: MeshTriageItem.TriageStatus = .pass
    public var triageSummaryMessage: String = "All systems operational"
    
    // Live Packet Logs (Bounded ring buffer)
    public var packetLogs: [MeshPacketLogItem] = []
    private let maxPacketLogs: Int = 100
    
    // Packet Injection Feedback
    public var injectionFeedback: String? = nil
    public var isInjecting: Bool = false
    
    // Virtual Mesh Simulator
    public var virtualPreset: VirtualTopologyPreset = .linearChain
    public var virtualNodes: [String] = [] // IDs of virtual nodes
    public var virtualActiveLinks: [String: Bool] = [:] // "nodeA-nodeB" -> isConnected
    public var virtualPacketLossRatio: Double = 0.0
    public var virtualLatencyMs: Double = 0.0
    public var virtualLogs: [String] = []
    public var isVirtualRunning: Bool = false
    
    // Export Status
    public var copiedReportNotification: Bool = false
    
    // Dependencies
    private weak var peerTransport: PeerTransportService?
    private weak var groupSessionViewModel: GroupSessionViewModel?
    private weak var locationService: (any LocationServiceProvider)?
    private weak var relayPolicyManager: RelayPolicyManager?
    private var streamTask: Task<Void, Never>?
    private var simulator: MeshTopologySimulator?
    
    public init(
        peerTransport: PeerTransportService? = nil,
        groupSessionViewModel: GroupSessionViewModel? = nil,
        locationService: (any LocationServiceProvider)? = nil,
        relayPolicyManager: RelayPolicyManager? = nil
    ) {
        self.peerTransport = peerTransport
        self.groupSessionViewModel = groupSessionViewModel
        self.locationService = locationService
        self.relayPolicyManager = relayPolicyManager
        self.activeSession = groupSessionViewModel?.activeSession
    }
    
    deinit {
        streamTask?.cancel()
    }
    
    // MARK: - Lifecycle & Initialization
    
    @MainActor
    public func startObserving() async {
        self.activeSession = groupSessionViewModel?.activeSession
        await runAutomatedTriage()
        await refreshLiveNeighbors()
        startStreamSubscriptions()
        await initializeVirtualSandbox()
    }
    
    @MainActor
    public func stopObserving() {
        streamTask?.cancel()
        streamTask = nil
    }
    
    // MARK: - Automated Health Triage Assistant
    
    @MainActor
    public func runAutomatedTriage() async {
        isTriageRunning = true
        var items: [MeshTriageItem] = []
        
        // 1. Check Location Authorization & GPS
        if let loc = locationService {
            let auth = loc.authorizationStatus
            switch auth {
            case .authorizedAlways, .authorizedWhenInUse:
                items.append(MeshTriageItem(
                    category: "CoreLocation",
                    title: "Location Permission Granted",
                    detail: "Authorized with \(loc.isGPSAvailable ? "active hardware GPS fix" : "sensor/network fix").",
                    status: .pass,
                    remediation: nil
                ))
            case .denied, .restricted:
                items.append(MeshTriageItem(
                    category: "CoreLocation",
                    title: "Location Access Denied",
                    detail: "App is blocked from reading GPS coordinates. Location pings will fail or send zero coordinates.",
                    status: .fail,
                    remediation: "Open iOS Settings -> Privacy & Security -> Location Services -> TeeKum -> Allow While Using."
                ))
            case .notDetermined:
                items.append(MeshTriageItem(
                    category: "CoreLocation",
                    title: "Location Permission Not Determined",
                    detail: "User has not yet granted location access.",
                    status: .warning,
                    remediation: "Return to Main Map to trigger the permission prompt."
                ))
            @unknown default:
                break
            }
        } else {
            items.append(MeshTriageItem(
                category: "CoreLocation",
                title: "Location Service Detached",
                detail: "Location service reference not attached to debugger.",
                status: .warning,
                remediation: nil
            ))
        }
        
        // 2. Check Radio & Bonjour Transport
        if let transport = peerTransport {
            let state = await transport.currentState
            self.transportState = state
            
            switch state {
            case .discovering, .connected:
                items.append(MeshTriageItem(
                    category: "Network.framework",
                    title: "Bonjour AWDL Radio Active",
                    detail: "NWListener & NWBrowser active on '_teekum._tcp'. Direct peer sockets ready.",
                    status: .pass,
                    remediation: nil
                ))
            case .starting:
                items.append(MeshTriageItem(
                    category: "Network.framework",
                    title: "Radio Starting",
                    detail: "NWListener is binding sockets to AWDL interface...",
                    status: .warning,
                    remediation: "Wait 2-3 seconds for Bonjour registration to complete."
                ))
            case .failed(let err):
                items.append(MeshTriageItem(
                    category: "Network.framework",
                    title: "Radio Sockets Failed",
                    detail: "Transport error: \(err.localizedDescription)",
                    status: .fail,
                    remediation: "Ensure Wi-Fi & Bluetooth are turned ON in iOS Settings (AWDL requires Wi-Fi enabled)."
                ))
            case .stopped:
                items.append(MeshTriageItem(
                    category: "Network.framework",
                    title: "Radio Transport Stopped",
                    detail: "Peer transport is not actively broadcasting or listening.",
                    status: .warning,
                    remediation: "Create or join a group session to start the AWDL radio transport."
                ))
            }
        } else {
            items.append(MeshTriageItem(
                category: "Network.framework",
                title: "Transport Service Missing",
                detail: "No active PeerTransportService attached.",
                status: .fail,
                remediation: "Ensure the app initialized PeerTransportService."
            ))
        }
        
        // 3. Check Session ID & Cryptographic Keys
        if let session = activeSession ?? groupSessionViewModel?.activeSession {
            if session.symmetricKeyData.count == 32 {
                items.append(MeshTriageItem(
                    category: "CryptoKit",
                    title: "256-Bit Group Key Verified",
                    detail: "Session ID 0x\(String(format: "%04X", session.sessionId)) with initials '\(session.localInitials)'.",
                    status: .pass,
                    remediation: nil
                ))
            } else {
                items.append(MeshTriageItem(
                    category: "CryptoKit",
                    title: "Malformed Key Data",
                    detail: "Key size is \(session.symmetricKeyData.count) bytes (expected 32 bytes).",
                    status: .fail,
                    remediation: "Re-generate group QR barcode or rejoin session."
                ))
            }
        } else {
            items.append(MeshTriageItem(
                category: "CryptoKit",
                title: "No Active Session",
                detail: "Device has not joined any group session yet.",
                status: .warning,
                remediation: "Scan a friend's QR code or tap 'Create Group' to form a private mesh session."
            ))
        }
        
        // 4. Check Relay Policy & Battery Cutoff
        if let relayManager = relayPolicyManager {
            let policy = await relayManager.currentState()
            self.relayPolicyState = policy
            
            if policy.batteryLevel < 0.20 || policy.isLowPowerModeActive {
                items.append(MeshTriageItem(
                    category: "Battery Policy",
                    title: "Festival Survival Mode Active (<20%)",
                    detail: "Stranger packet relaying is automatically suspended to preserve power for SOS.",
                    status: .warning,
                    remediation: "Charge device above 20% or disable Low Power Mode to re-enable communal relaying."
                ))
            } else if !policy.isRelayPermitted {
                items.append(MeshTriageItem(
                    category: "Relay Policy",
                    title: "Communal Relaying Disabled",
                    detail: "User mode set to '\(policy.mode.rawValue)'. Relaying packets for strangers is OFF.",
                    status: .pass,
                    remediation: "Open Relay Settings to enable Always Active or Timed 30m relaying."
                ))
            } else {
                items.append(MeshTriageItem(
                    category: "Relay Policy",
                    title: "Communal Relaying Active",
                    detail: "Relaying for strangers enabled (Rate limit: 2 pkts/sec).",
                    status: .pass,
                    remediation: nil
                ))
            }
        }
        
        // 5. Evaluate Overall Status
        if items.contains(where: { $0.status == .fail }) {
            self.overallTriageStatus = .fail
            self.triageSummaryMessage = "Mesh Blocked — Action Required"
        } else if items.contains(where: { $0.status == .warning }) {
            self.overallTriageStatus = .warning
            self.triageSummaryMessage = "Mesh Active with Warnings"
        } else {
            self.overallTriageStatus = .pass
            self.triageSummaryMessage = "All Systems Operational"
        }
        
        self.triageItems = items
        self.isTriageRunning = false
    }
    
    // MARK: - Neighbor & Telemetry Updates
    
    @MainActor
    public func refreshLiveNeighbors() async {
        guard let transport = peerTransport else { return }
        self.liveNeighbors = await transport.activeNeighbors()
        self.livePeerCount = await transport.activeDirectPeerCount()
    }
    
    private func startStreamSubscriptions() {
        guard let transport = peerTransport else { return }
        
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self = self else { return }
            
            let frameStream = await transport.inboundFrames
            let outcomeStream = await transport.sendOutcomes
            let peerUpdates = await transport.peerUpdates
            
            await withTaskGroup(of: Void.self) { group in
                // Inbound Frames
                group.addTask {
                    for await frame in frameStream {
                        guard !Task.isCancelled else { break }
                        await self.handleInboundFrameLogged(frame)
                    }
                }
                
                // Outbound Outcomes
                group.addTask {
                    for await outcome in outcomeStream {
                        guard !Task.isCancelled else { break }
                        await self.handleSendOutcomeLogged(outcome)
                    }
                }
                
                // Peer Updates
                group.addTask {
                    for await peers in peerUpdates {
                        guard !Task.isCancelled else { break }
                        await self.handlePeersUpdated(peers)
                    }
                }
            }
        }
    }
    
    @MainActor
    private func handleInboundFrameLogged(_ frame: InboundFrame) async {
        let raw = frame.rawData
        guard raw.count >= PacketConstants.cleartextEnvelopeSize else { return }
        
        let byte0 = raw[raw.startIndex]
        let version = byte0 >> 4
        let pType = PacketType(rawValue: byte0 & 0x0F) ?? .locationPing
        let hopLimit = raw[raw.startIndex + 1]
        let hopCount = raw[raw.startIndex + 2]
        
        let b3 = UInt32(raw[raw.startIndex + 3])
        let b4 = UInt32(raw[raw.startIndex + 4])
        let b5 = UInt32(raw[raw.startIndex + 5])
        let sid = (b3 << 16) | (b4 << 8) | b5
        
        let seq = raw.subdata(in: (raw.startIndex + 6)..<(raw.startIndex + 10)).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        
        let authTagData = raw.count == 56 ? raw.suffix(16) : Data()
        let authTagHex = authTagData.map { String(format: "%02X", $0) }.joined()
        
        var payloadSummary = "30B Ciphertext (Zero-Knowledge Sealed)"
        var isDecrypted = false
        
        if let session = activeSession, session.sessionId == sid, raw.count == 56 {
            // Attempt decryption for inspector
            let ciphertext = raw.subdata(in: (raw.startIndex + 10)..<(raw.startIndex + 40))
            let key = SymmetricKey(data: session.symmetricKeyData)
            let env = CleartextEnvelope(
                version: version,
                type: pType,
                hopLimit: hopLimit,
                hopCount: hopCount,
                sessionId: UInt16(sid & 0xFFFF),
                sequenceNumber: seq
            )
            
            if let decrypted = try? await CryptoService().open(
                ciphertext: ciphertext,
                envelope: env,
                authTag: authTagData,
                using: key
            ) {
                isDecrypted = true
                if pType == .locationPing, let ping = try? LocationPingPayload.deserialize(from: decrypted) {
                    payloadSummary = "Ping [\(ping.senderInitials)] lat:\(String(format: "%.4f", ping.coordinate.latitude)), lon:\(String(format: "%.4f", ping.coordinate.longitude)), bat:\(ping.batteryLevel)%"
                } else if pType == .sos, let sos = try? SOSPayload.deserialize(from: decrypted) {
                    payloadSummary = "SOS [\(sos.senderInitials)] Type:\(sos.emergencyType.title) EventID:0x\(String(format: "%06X", sos.sosEventId))"
                } else if pType == .ack, let ack = try? ACKPayload.deserialize(from: decrypted) {
                    payloadSummary = "ACK [\(ack.responderInitials)] for seq:\(ack.ackedSeqNumber) status:\(ack.ackStatus)"
                } else if pType == .chatMessage, let chat = try? ChatMessagePayload.deserialize(from: decrypted) {
                    payloadSummary = "Chat [\(chat.senderInitials)] \"\(chat.text)\""
                }
            }
        }
        
        let item = MeshPacketLogItem(
            direction: .inbound,
            type: pType,
            sourcePeer: frame.sourcePeerId,
            destinationPeer: "Local",
            hopCount: hopCount,
            hopLimit: hopLimit,
            sessionId: sid,
            sequenceNumber: seq,
            rawLength: raw.count,
            rawBytes: raw,
            envelopeSummary: "v\(version) | Hops: \(hopCount)/\(hopLimit) | SID: 0x\(String(format: "%06X", sid)) | Seq: \(seq)",
            payloadSummary: payloadSummary,
            authTagHex: authTagHex,
            isDecrypted: isDecrypted
        )
        
        appendLogItem(item)
    }
    
    @MainActor
    private func handleSendOutcomeLogged(_ outcome: SendOutcome) {
        let dest = outcome.destinationPeerId.isEmpty ? "Broadcast" : outcome.destinationPeerId
        let item = MeshPacketLogItem(
            direction: outcome.isSuccess ? .outbound : .dropped,
            type: outcome.packetType,
            sourcePeer: activeSession?.localInitials ?? "Local",
            destinationPeer: dest,
            hopCount: 0,
            hopLimit: PacketConstants.defaultHopLimit,
            sessionId: UInt32(activeSession?.sessionId ?? 0),
            sequenceNumber: 0,
            rawLength: 56,
            rawBytes: Data(),
            envelopeSummary: "Outbound to \(dest)",
            payloadSummary: outcome.isSuccess ? "Dispatched over socket" : "Send failed: \(outcome.error?.localizedDescription ?? "Unknown")",
            authTagHex: "",
            dropReason: outcome.isSuccess ? nil : outcome.error?.localizedDescription
        )
        appendLogItem(item)
    }
    
    @MainActor
    private func handlePeersUpdated(_ peers: [PeerInfo]) async {
        await refreshLiveNeighbors()
    }
    
    @MainActor
    private func appendLogItem(_ item: MeshPacketLogItem) {
        packetLogs.insert(item, at: 0)
        if packetLogs.count > maxPacketLogs {
            packetLogs.removeLast()
        }
    }
    
    @MainActor
    public func clearPacketLogs() {
        packetLogs.removeAll()
        selectedPacket = nil
    }
    
    // MARK: - Packet Injection Engine
    
    @MainActor
    public func injectLocationPing() async {
        guard let transport = peerTransport, let session = activeSession ?? groupSessionViewModel?.activeSession else {
            injectionFeedback = "Error: Group session and radio transport required"
            return
        }
        
        isInjecting = true
        defer { isInjecting = false }
        
        do {
            let lat = 37.7749 + Double.random(in: -0.001...0.001)
            let lon = -122.4194 + Double.random(in: -0.001...0.001)
            let payload = LocationPingPayload(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                timestamp: Date(),
                accuracy: 5,
                senderInitials: session.localInitials,
                batteryLevel: 88,
                heading: 180
            )
            let serialized = payload.serialize()
            let envelope = CleartextEnvelope(
                version: PacketConstants.protocolVersion,
                type: .locationPing,
                hopLimit: PacketConstants.defaultHopLimit,
                hopCount: 0,
                sessionId: session.sessionId,
                sequenceNumber: UInt32.random(in: 1000...99999)
            )
            let key = SymmetricKey(data: session.symmetricKeyData)
            let (ciphertext, tag) = try await CryptoService().seal(payload: serialized, envelope: envelope, using: key)
            let wirePacket = RawWirePacket(envelope: envelope, ciphertext: ciphertext, authTag: tag)
            let wireData = try wirePacket.toWireData()
            
            try await transport.broadcastFrame(wireData)
            injectionFeedback = "PASS: Broadcasted Location Ping (56 bytes, Seq \(envelope.sequenceNumber))"
        } catch {
            injectionFeedback = "FAIL: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    public func injectUrgentSOS() async {
        guard let transport = peerTransport, let session = activeSession ?? groupSessionViewModel?.activeSession else {
            injectionFeedback = "Error: Group session and radio transport required"
            return
        }
        
        isInjecting = true
        defer { isInjecting = false }
        
        do {
            let payload = SOSPayload(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                timestamp: Date(),
                accuracy: 4,
                sosEventId: UInt32.random(in: 0x100000...0xFFFFFF),
                senderInitials: session.localInitials,
                emergencyType: .medical,
                batteryLevel: 75
            )
            let serialized = payload.serialize()
            let envelope = CleartextEnvelope(
                version: PacketConstants.protocolVersion,
                type: .sos,
                hopLimit: PacketConstants.sosHopLimit,
                hopCount: 0,
                sessionId: session.sessionId,
                sequenceNumber: UInt32.random(in: 1000...99999)
            )
            let key = SymmetricKey(data: session.symmetricKeyData)
            let (ciphertext, tag) = try await CryptoService().seal(payload: serialized, envelope: envelope, using: key)
            let wirePacket = RawWirePacket(envelope: envelope, ciphertext: ciphertext, authTag: tag)
            let wireData = try wirePacket.toWireData()
            
            try await transport.broadcastFrame(wireData)
            injectionFeedback = "PASS: Broadcasted Urgent SOS (Priority Lane, EventID 0x\(String(format: "%06X", payload.sosEventId)))"
        } catch {
            injectionFeedback = "FAIL: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    public func injectReceiptACK() async {
        guard let transport = peerTransport, let session = activeSession ?? groupSessionViewModel?.activeSession else {
            injectionFeedback = "Error: Group session and radio transport required"
            return
        }
        
        isInjecting = true
        defer { isInjecting = false }
        
        do {
            let payload = ACKPayload(
                ackedSeqNumber: 1042,
                ackedSenderInitials: "BOB",
                ackTimestamp: Date(),
                ackStatus: .deliveredToFriend,
                receivedRssi: -65,
                originalEventId: 0x55AA11,
                responderInitials: session.localInitials
            )
            let serialized = payload.serialize()
            let envelope = CleartextEnvelope(
                version: PacketConstants.protocolVersion,
                type: .ack,
                hopLimit: PacketConstants.defaultHopLimit,
                hopCount: 0,
                sessionId: session.sessionId,
                sequenceNumber: UInt32.random(in: 1000...99999)
            )
            let key = SymmetricKey(data: session.symmetricKeyData)
            let (ciphertext, tag) = try await CryptoService().seal(payload: serialized, envelope: envelope, using: key)
            let wirePacket = RawWirePacket(envelope: envelope, ciphertext: ciphertext, authTag: tag)
            let wireData = try wirePacket.toWireData()
            
            try await transport.broadcastFrame(wireData)
            injectionFeedback = "PASS: Broadcasted Delivery ACK (for BOB, seq 1042)"
        } catch {
            injectionFeedback = "FAIL: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    public func injectCorruptedAuthTag() async {
        guard let transport = peerTransport, let session = activeSession ?? groupSessionViewModel?.activeSession else {
            injectionFeedback = "Error: Group session and radio transport required"
            return
        }
        
        isInjecting = true
        defer { isInjecting = false }
        
        do {
            let payload = LocationPingPayload(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                timestamp: Date(),
                accuracy: 5,
                senderInitials: session.localInitials,
                batteryLevel: 90,
                heading: 0
            )
            let serialized = payload.serialize()
            let envelope = CleartextEnvelope(
                version: PacketConstants.protocolVersion,
                type: .locationPing,
                hopLimit: 8,
                hopCount: 0,
                sessionId: session.sessionId,
                sequenceNumber: 9999
            )
            let key = SymmetricKey(data: session.symmetricKeyData)
            let (ciphertext, tag) = try await CryptoService().seal(payload: serialized, envelope: envelope, using: key)
            
            // Deliberately corrupt 1 byte of the 16-byte Poly1305 MAC tag
            var corruptedTag = tag
            corruptedTag[corruptedTag.startIndex] ^= 0xFF
            
            let wirePacket = RawWirePacket(envelope: envelope, ciphertext: ciphertext, authTag: corruptedTag)
            let wireData = try wirePacket.toWireData()
            
            try await transport.broadcastFrame(wireData)
            injectionFeedback = "PASS: Injected Corrupted Auth Tag packet (Tamper Test). Receivers will drop it cryptographically."
        } catch {
            injectionFeedback = "FAIL: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    public func injectExceededHopCount() async {
        guard let transport = peerTransport, let session = activeSession ?? groupSessionViewModel?.activeSession else {
            injectionFeedback = "Error: Group session and radio transport required"
            return
        }
        
        isInjecting = true
        defer { isInjecting = false }
        
        do {
            var rawData = Data(count: 56)
            // version 3, type 1 (location ping)
            rawData[0] = (PacketConstants.protocolVersion << 4) | PacketType.locationPing.rawValue
            rawData[1] = 8  // hopLimit
            rawData[2] = 9  // hopCount > hopLimit (illegal)
            
            // sessionId
            let sid = session.sessionId
            rawData[3] = UInt8((sid >> 16) & 0xFF)
            rawData[4] = UInt8((sid >> 8) & 0xFF)
            rawData[5] = UInt8(sid & 0xFF)
            
            try await transport.broadcastFrame(rawData)
            injectionFeedback = "PASS: Injected packet with hopCount (9) > hopLimit (8). Relays will drop on ingestion."
        } catch {
            injectionFeedback = "FAIL: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    public func injectRogueSessionId() async {
        guard let transport = peerTransport else {
            injectionFeedback = "Error: Radio transport required"
            return
        }
        
        isInjecting = true
        defer { isInjecting = false }
        
        do {
            var rawData = Data(count: 56)
            rawData[0] = (PacketConstants.protocolVersion << 4) | PacketType.locationPing.rawValue
            rawData[1] = 8 // hopLimit
            rawData[2] = 0 // hopCount
            
            // Rogue / Stranger Session ID 0xBADF00
            rawData[3] = 0xBA
            rawData[4] = 0xDF
            rawData[5] = 0x00
            
            try await transport.broadcastFrame(rawData)
            injectionFeedback = "PASS: Injected Rogue Session ID (0xBADF00). Tested zero-knowledge stranger relay pipeline."
        } catch {
            injectionFeedback = "FAIL: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Virtual Mesh Simulator
    
    @MainActor
    public func initializeVirtualSandbox() async {
        let sim = MeshTopologySimulator()
        self.simulator = sim
        await applyVirtualPreset(virtualPreset)
    }
    
    @MainActor
    public func applyVirtualPreset(_ preset: VirtualTopologyPreset) async {
        self.virtualPreset = preset
        let sim = MeshTopologySimulator()
        self.simulator = sim
        self.virtualLogs.removeAll()
        self.virtualActiveLinks.removeAll()
        
        let dummyKey = Data(repeating: 0x42, count: 32)
        let groupSession = GroupSession(sessionId: 0x7E3A, sessionName: "Virtual Fest", symmetricKeyData: dummyKey, localInitials: "ALI")
        
        switch preset {
        case .linearChain:
            // Alice (ALI) <-> Relay 1 (R1) <-> Relay 2 (R2) <-> Bob (BOB)
            _ = await sim.createNode(id: "ALI", initials: "ALI", session: groupSession)
            _ = await sim.createStrangerRelay(id: "R1")
            _ = await sim.createStrangerRelay(id: "R2")
            _ = await sim.createNode(id: "BOB", initials: "BOB", session: groupSession)
            
            await sim.setupLinearChain(ids: ["ALI", "R1", "R2", "BOB"])
            self.virtualNodes = ["ALI", "R1", "R2", "BOB"]
            self.virtualActiveLinks["ALI-R1"] = true
            self.virtualActiveLinks["R1-R2"] = true
            self.virtualActiveLinks["R2-BOB"] = true
            virtualLogs.append("Initialized 3-Hop Linear Chain: ALI <-> R1 <-> R2 <-> BOB.")
            
        case .diamondMultiPath:
            // Alice -> [R1, R2] -> Bob
            _ = await sim.createNode(id: "ALI", initials: "ALI", session: groupSession)
            _ = await sim.createStrangerRelay(id: "R1")
            _ = await sim.createStrangerRelay(id: "R2")
            _ = await sim.createNode(id: "BOB", initials: "BOB", session: groupSession)
            
            await sim.setupDiamondTopology(sender: "ALI", relay1: "R1", relay2: "R2", destination: "BOB")
            self.virtualNodes = ["ALI", "R1", "R2", "BOB"]
            self.virtualActiveLinks["ALI-R1"] = true
            self.virtualActiveLinks["ALI-R2"] = true
            self.virtualActiveLinks["R1-BOB"] = true
            self.virtualActiveLinks["R2-BOB"] = true
            virtualLogs.append("Initialized Diamond Multi-Path Topology: ALI -> [R1, R2] -> BOB.")
            
        case .competingRoutes:
            _ = await sim.createNode(id: "ALI", initials: "ALI", session: groupSession)
            _ = await sim.createStrangerRelay(id: "FAST_R")
            _ = await sim.createStrangerRelay(id: "SLOW_R1")
            _ = await sim.createStrangerRelay(id: "SLOW_R2")
            _ = await sim.createNode(id: "BOB", initials: "BOB", session: groupSession)
            
            await sim.setupCompetingRoutesTopology(sender: "ALI", shortRelay: "FAST_R", longRelay1: "SLOW_R1", longRelay2: "SLOW_R2", destination: "BOB")
            self.virtualNodes = ["ALI", "FAST_R", "SLOW_R1", "SLOW_R2", "BOB"]
            self.virtualActiveLinks["ALI-FAST_R"] = true
            self.virtualActiveLinks["FAST_R-BOB"] = true
            self.virtualActiveLinks["ALI-SLOW_R1"] = true
            self.virtualActiveLinks["SLOW_R1-SLOW_R2"] = true
            self.virtualActiveLinks["SLOW_R2-BOB"] = true
            virtualLogs.append("Initialized Competing Routes: 2-Hop Path vs 3-Hop Path.")
            
        case .closedRing:
            _ = await sim.createNode(id: "N1", initials: "N1", session: groupSession)
            _ = await sim.createStrangerRelay(id: "N2")
            _ = await sim.createStrangerRelay(id: "N3")
            _ = await sim.createNode(id: "N4", initials: "N4", session: groupSession)
            
            await sim.setupRingTopology(ids: ["N1", "N2", "N3", "N4"])
            self.virtualNodes = ["N1", "N2", "N3", "N4"]
            self.virtualActiveLinks["N1-N2"] = true
            self.virtualActiveLinks["N2-N3"] = true
            self.virtualActiveLinks["N3-N4"] = true
            self.virtualActiveLinks["N4-N1"] = true
            virtualLogs.append("Initialized 4-Node Closed Ring: N1 <-> N2 <-> N3 <-> N4 <-> N1.")
        }
    }
    
    @MainActor
    public func toggleVirtualLink(nodeA: String, nodeB: String) async {
        guard let sim = simulator else { return }
        let key = "\(nodeA)-\(nodeB)"
        let altKey = "\(nodeB)-\(nodeA)"
        let isConnected = virtualActiveLinks[key] ?? virtualActiveLinks[altKey] ?? false
        
        if isConnected {
            await sim.disconnect(nodeA, nodeB)
            virtualActiveLinks[key] = false
            virtualActiveLinks[altKey] = false
            virtualLogs.append("LINK BROKEN: \(nodeA) -x- \(nodeB)")
        } else {
            await sim.reconnect(nodeA, nodeB)
            virtualActiveLinks[key] = true
            virtualActiveLinks[altKey] = true
            virtualLogs.append("LINK RESTORED: \(nodeA) <-> \(nodeB)")
        }
    }
    
    @MainActor
    public func sendVirtualPing() async {
        guard let sim = simulator, let ali = await sim.node(named: "ALI") else { return }
        isVirtualRunning = true
        defer { isVirtualRunning = false }
        
        do {
            try await ali.sendLocationPing()
            virtualLogs.append("ALI dispatched Location Ping. Propagating across virtual hops...")
            
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            if let bob = await sim.node(named: "BOB") {
                let count = await bob.deliveredPackets.count
                virtualLogs.append("BOB received count: \(count) valid packet(s).")
            }
        } catch {
            virtualLogs.append("Ping error: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    public func sendVirtualSOS() async {
        guard let sim = simulator, let ali = await sim.node(named: "ALI") else { return }
        isVirtualRunning = true
        defer { isVirtualRunning = false }
        
        do {
            try await ali.sendEmergencySOS(emergencyType: .medical)
            virtualLogs.append("ALI dispatched URGENT SOS. Flooding across virtual mesh...")
            
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            if let bob = await sim.node(named: "BOB") {
                let count = await bob.deliveredPackets.filter { $0.envelope.type == .sos }.count
                virtualLogs.append("BOB delivered SOS count: \(count). Emergency alert verified.")
            }
        } catch {
            virtualLogs.append("SOS error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Export Diagnostic Report
    
    @MainActor
    public func exportDiagnosticReport() -> String {
        var report = """
        # TeeKum Mesh Diagnostic & Health Report
        *Generated at:* \(Date().formatted())
        
        ## 1. System & Cryptographic Status
        - Local Member Initials: \(activeSession?.localInitials ?? "Unset")
        - Session Name: \(activeSession?.sessionName ?? "None")
        - Session ID: 0x\(String(format: "%04X", activeSession?.sessionId ?? 0))
        - Radio State: \(transportState)
        - Active Direct Peers: \(livePeerCount)
        - Communal Relay Permitted: \(relayPolicyState?.isRelayPermitted ?? false)
        - Battery Level: \((locationService?.currentBatteryLevel ?? 1.0).formattedBatteryPercentage)
        - Survival Mode Active: \(locationService?.isSurvivalModeActive ?? false)
        
        ## 2. Automated Health Triage
        - Overall Verdict: \(triageSummaryMessage)
        """
        
        for item in triageItems {
            report += "\n- [\(item.status)] \(item.category): \(item.title) — \(item.detail)"
            if let rem = item.remediation {
                report += " (Remediation: \(rem))"
            }
        }
        
        report += "\n\n## 3. Active Neighbors\n"
        if liveNeighbors.isEmpty {
            report += "*No 1-hop physical neighbors currently connected.*"
        } else {
            for n in liveNeighbors {
                report += "\n- Peer '\(n.id)': RSSI \(n.rssi?.description ?? "N/A") dBm | State: \(n.state) | Group: \(n.isGroupMember)"
            }
        }
        
        report += "\n\n## 4. Recent Packet Trace (Last \(min(packetLogs.count, 20)))\n"
        for p in packetLogs.prefix(20) {
            report += "\n- [\(p.timestamp.formatted(date: .omitted, time: .standard))] \(p.direction.rawValue) \(p.type) from \(p.sourcePeer) -> \(p.destinationPeer ?? "All") | Hops: \(p.hopCount)/\(p.hopLimit) | \(p.payloadSummary)"
            if let drop = p.dropReason {
                report += " (Dropped: \(drop))"
            }
        }
        
        UIPasteboard.general.string = report
        copiedReportNotification = true
        
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self.copiedReportNotification = false
        }
        
        return report
    }
}
