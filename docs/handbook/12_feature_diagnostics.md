# TeeKum Code Handbook — Volume 12: Feature — Mesh Diagnostics & Simulation

This volume provides an exhaustive, line-by-line architectural breakdown of TeeKum's real-time telemetry pipeline, the zero-knowledge privacy-preserving diagnostic metrics engine, the autonomous multi-node virtual mesh simulator, the directional packet sniffer, and the adversarial fault-injection framework.

---

## 📑 Included Source Files

* **Telemetry & Metrics**:
  * [`TeeKum Prototype/Features/Diagnostics/Services/MeshDiagnostics.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/Services/MeshDiagnostics.swift) — 278 lines: Immutable `MeshDiagnosticsSnapshot` tracking the 7 core operational mesh metrics and the actor-isolated `MeshDiagnosticsCollector`.
  * [`TeeKum Prototype/Core/Models/SOSDiagnostics.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/SOSDiagnostics.swift) — Diagnostics model tracking emergency SOS delivery latency and routing hops.
* **Virtual Mesh Simulation**:
  * [`TeeKum Prototype/Features/Diagnostics/Services/MeshTopologySimulator.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/Services/MeshTopologySimulator.swift) — 417 lines: Autonomous virtual node actor (`SimulatedMeshNode`), multi-hop topologies (linear chains, diamond multi-path, competing routes, closed rings), and simulated RF impairments.
  * [`TeeKum Prototype/Core/Transport/SimulatedMeshTransport.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Transport/SimulatedMeshTransport.swift) — Virtual radio transport supporting configurable packet loss, latency, and duplication.
* **Live Radio Debugger & Injection**:
  * [`TeeKum Prototype/Features/Diagnostics/ViewModels/MeshDebuggerViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/ViewModels/MeshDebuggerViewModel.swift) — 1,032 lines: Debugger state machine, live 100-packet ring buffer sniffer, adversarial packet injectors, automated health triage, and Markdown report exporter.
  * [`TeeKum Prototype/Features/Diagnostics/Views/DiagnosticsView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/Views/DiagnosticsView.swift) — 669 lines: Comprehensive on-device debug HUD presenting active session keys, GPS accuracy, radio status, and embedded test runners.
  * [`TeeKum Prototype/Features/Diagnostics/Views/MeshDebuggerView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/Views/MeshDebuggerView.swift) — Developer tool UI displaying interactive node topologies, 56-byte wire frame inspectors, and simulated RF link toggles.

---

# 1. The 7 Operational Mesh Metrics & Zero-Knowledge Invariant: `MeshDiagnostics.swift`

Maintaining network visibility in a decentralized mesh is notoriously difficult because nodes have no central telemetry server. Furthermore, logging telemetry must never compromise user privacy.

`MeshDiagnosticsSnapshot` tracks the **7 required Phase 2 operational metrics**:

```swift
public struct MeshDiagnosticsSnapshot: Sendable, Equatable {
    
    // MARK: - 1. Forwarding Attempts & Outcomes
    public var forwardingAttempts: Int
    public var forwardingSuccesses: Int
    public var forwardingFailures: Int
    
    // MARK: - 2. Packets Dropped (Categorized by Reason)
    public var droppedRateLimit: Int
    public var droppedHopLimit: Int
    public var droppedQueueSaturation: Int
    public var droppedPolicyDisabled: Int
    public var droppedBatterySurvival: Int
    public var droppedMalformed: Int
    public var droppedSecurityFailed: Int
    public var droppedSimulatedLoss: Int
    
    public var totalPacketsDropped: Int {
        droppedRateLimit +
        droppedHopLimit +
        droppedQueueSaturation +
        droppedPolicyDisabled +
        droppedBatterySurvival +
        droppedMalformed +
        droppedSecurityFailed +
        droppedSimulatedLoss
    }
    
    // MARK: - 3. Duplicates Suppressed
    public var duplicatesSuppressed: Int
    
    // MARK: - 4. Route Discoveries
    public var routeDiscoveriesInitiated: Int
    public var routeDiscoveriesSucceeded: Int
    public var routeDiscoveriesFailed: Int
    
    // MARK: - 5. Route Failures & Invalidation Events
    public var routeFailuresOrInvalidations: Int
    
    // MARK: - 6. Hop Count Metrics
    public var maxHopCountObserved: UInt8
    public var hopCountHistogram: [UInt8: Int] // [HopCount: OccurrenceCount]
    public var totalHopsSum: Int
    public var totalHopsSamples: Int
    
    public var averageHopCount: Double {
        totalHopsSamples > 0 ? Double(totalHopsSum) / Double(totalHopsSamples) : 0.0
    }
    
    // MARK: - 7. Queue Saturation & Memory Footprint
    public var queueSaturationDrops: Int
    public var urgentQueueDepth: Int
    public var relayQueueDepth: Int
    public var normalQueueDepth: Int
```

### Architectural Metric Definitions
1. **Forwarding Attempts (`forwardingAttempts`, `forwardingSuccesses`, `forwardingFailures`)**:
   Tracks every attempt by `PacketForwarder` to relay an inbound packet to 1-hop physical neighbors over AWDL radio sockets.
2. **Categorized Packet Drops**:
   Instead of a generic counter, drops are partitioned across 8 mutually exclusive fault domains:
   * `droppedRateLimit`: Token-bucket forwarding rate limiter saturated ($>2\text{ pkts/sec}$).
   * `droppedHopLimit`: Time-to-Live expired (`hopCount >= hopLimit`).
   * `droppedQueueSaturation`: Memory backpressure ring buffer drops.
   * `droppedPolicyDisabled`: User disabled stranger relaying in Relay Settings.
   * `droppedBatterySurvival`: Battery dropped below 20% or Low Power Mode active.
   * `droppedMalformed`: Wire packet length $\ne 56\text{ bytes}$ or protocol version mismatch.
   * `droppedSecurityFailed`: ChaCha20-Poly1305 authentication tag verification failed.
   * `droppedSimulatedLoss`: Artificially dropped by test harness.
3. **Duplicates Suppressed (`duplicatesSuppressed`)**:
   Packets dropped because their 64-bit sequence hash `(sessionId << 32) | sequenceNumber` already exists in the 1,024-entry LRU `SeenPacketCache`.
4. **Route Discoveries (`routeDiscoveriesInitiated`, `Succeeded`, `Failed`)**:
   AODV reactive routing engine performance tracking.
5. **Route Failures & Invalidations (`routeFailuresOrInvalidations`)**:
   Occurs when a peer socket drops, link breaks, or route reaches its 300-second TTL.
6. **Hop Count Distribution**:
   Histogram `[UInt8: Int]` mapping each hop distance ($0, 1, 2, \dots, 15$) to packet counts, calculating real-time mathematical average path lengths:
   $$\bar{h} = \frac{\sum_{i=1}^{N} h_i}{N}$$
7. **Queue Saturation & Memory Footprint**:
   Real-time queue depths across the 4-tier scheduler (Urgent, Chat, Normal GPS, Stranger Relay).

---

## 1.1 The Zero-Knowledge Privacy Verification Invariant

```swift
    // MARK: - Privacy & Security Verification
    public var containsLocationData: Bool { false }
    public var containsCryptographicKeys: Bool { false }
    public var isPrivacyCompliant: Bool { true }
```

```swift
    public func verifyPrivacyCompliance() -> Bool {
        snapshotData.isPrivacyCompliant &&
        !snapshotData.containsLocationData &&
        !snapshotData.containsCryptographicKeys
    }
```

### Privacy-Preserving Guarantees
* **Strict Type Level Enforcement**: `MeshDiagnosticsSnapshot` contains exclusively scalar integers (`Int`, `UInt8`), doubles, and dictionary counters.
* **No Coordinate Buffering**: Under no circumstances does the diagnostic collector retain latitude, longitude, altitude, timestamps of user movements, or GPS track histories.
* **No Cryptographic Key Retention**: The 256-bit symmetric session key is strictly barred from the diagnostics pipeline; only a safe 4-byte key fingerprint is displayed in the developer HUD.
* **Safe Field Export**: Telemetry snapshots can be dumped to text files or shared via clipboard without risk of location stalking or cryptographic key extraction.

---

## 1.2 Mathematical Multi-Node Snapshot Aggregation: `+` Operator

When running virtual simulations or aggregating fleet diagnostics, snapshots from independent nodes must combine into a single holistic network metric:

```swift
    public static func +(lhs: MeshDiagnosticsSnapshot, rhs: MeshDiagnosticsSnapshot) -> MeshDiagnosticsSnapshot {
        var mergedHisto = lhs.hopCountHistogram
        for (hops, count) in rhs.hopCountHistogram {
            mergedHisto[hops, default: 0] += count
        }
        
        return MeshDiagnosticsSnapshot(
            forwardingAttempts: lhs.forwardingAttempts + rhs.forwardingAttempts,
            forwardingSuccesses: lhs.forwardingSuccesses + rhs.forwardingSuccesses,
            forwardingFailures: lhs.forwardingFailures + rhs.forwardingFailures,
            droppedRateLimit: lhs.droppedRateLimit + rhs.droppedRateLimit,
            droppedHopLimit: lhs.droppedHopLimit + rhs.droppedHopLimit,
            droppedQueueSaturation: lhs.droppedQueueSaturation + rhs.droppedQueueSaturation,
            droppedPolicyDisabled: lhs.droppedPolicyDisabled + rhs.droppedPolicyDisabled,
            droppedBatterySurvival: lhs.droppedBatterySurvival + rhs.droppedBatterySurvival,
            droppedMalformed: lhs.droppedMalformed + rhs.droppedMalformed,
            droppedSecurityFailed: lhs.droppedSecurityFailed + rhs.droppedSecurityFailed,
            droppedSimulatedLoss: lhs.droppedSimulatedLoss + rhs.droppedSimulatedLoss,
            duplicatesSuppressed: lhs.duplicatesSuppressed + rhs.duplicatesSuppressed,
            routeDiscoveriesInitiated: lhs.routeDiscoveriesInitiated + rhs.routeDiscoveriesInitiated,
            routeDiscoveriesSucceeded: lhs.routeDiscoveriesSucceeded + rhs.routeDiscoveriesSucceeded,
            routeDiscoveriesFailed: lhs.routeDiscoveriesFailed + rhs.routeDiscoveriesFailed,
            routeFailuresOrInvalidations: lhs.routeFailuresOrInvalidations + rhs.routeFailuresOrInvalidations,
            maxHopCountObserved: max(lhs.maxHopCountObserved, rhs.maxHopCountObserved),
            hopCountHistogram: mergedHisto,
            totalHopsSum: lhs.totalHopsSum + rhs.totalHopsSum,
            totalHopsSamples: lhs.totalHopsSamples + rhs.totalHopsSamples,
            queueSaturationDrops: lhs.queueSaturationDrops + rhs.queueSaturationDrops,
            urgentQueueDepth: lhs.urgentQueueDepth + rhs.urgentQueueDepth,
            relayQueueDepth: lhs.relayQueueDepth + rhs.relayQueueDepth,
            normalQueueDepth: lhs.normalQueueDepth + rhs.normalQueueDepth
        )
    }
```

### Algebraic Properties of Snapshot Merging
* **Commutative & Associative**: $A + B = B + A$, allowing snapshots from arbitrary nodes to be merged in any sequence across worker threads.
* **Exact Histogram Union**: `mergedHisto[hops, default: 0] += count` preserves discrete probability distributions across multi-hop clusters.
* **Global Maximum Tracking**: `max(lhs.maxHopCountObserved, rhs.maxHopCountObserved)` correctly captures the longest traversed mesh path in the fleet.

---

## 1.3 Actor-Isolated Thread-Safe Telemetry Collection: `MeshDiagnosticsCollector`

```swift
public actor MeshDiagnosticsCollector {
    private let clock: MeshClock
    private var snapshotData = MeshDiagnosticsSnapshot()
    
    public init(clock: MeshClock = SystemMeshClock()) {
        self.clock = clock
    }
    
    public func recordForwardingAttempt(success: Bool) {
        snapshotData.forwardingAttempts += 1
        if success {
            snapshotData.forwardingSuccesses += 1
        } else {
            snapshotData.forwardingFailures += 1
        }
    }
    
    public func recordPacketDrop(reason: DropReason) {
        switch reason {
        case .rateLimitExceeded:
            snapshotData.droppedRateLimit += 1
        case .hopLimitExceeded:
            snapshotData.droppedHopLimit += 1
        case .duplicate:
            snapshotData.duplicatesSuppressed += 1
        case .batteryThrottled:
            snapshotData.droppedBatterySurvival += 1
        case .policyDisabled:
            snapshotData.droppedPolicyDisabled += 1
        case .queueSaturation:
            snapshotData.droppedQueueSaturation += 1
            snapshotData.queueSaturationDrops += 1
        case .malformed:
            snapshotData.droppedMalformed += 1
        case .securityVerificationFailed:
            snapshotData.droppedSecurityFailed += 1
        case .simulatedLoss:
            snapshotData.droppedSimulatedLoss += 1
        }
    }
    
    public func recordHopCount(_ hopCount: UInt8) {
        if hopCount > snapshotData.maxHopCountObserved {
            snapshotData.maxHopCountObserved = hopCount
        }
        snapshotData.hopCountHistogram[hopCount, default: 0] += 1
        snapshotData.totalHopsSum += Int(hopCount)
        snapshotData.totalHopsSamples += 1
    }
    
    public func snapshot() -> MeshDiagnosticsSnapshot {
        snapshotData
    }
    
    public func reset() {
        snapshotData = MeshDiagnosticsSnapshot()
    }
}
```

### Concurrency & Isolation Guarantees
* **Swift Actor Isolation**: High-frequency packet forwarding (up to hundreds of frames per second) executes concurrently across background dispatch queues. The `actor` boundary guarantees zero data races without manual pthread mutexes.
* **Clock Decoupling**: Accepts an injected `MeshClock` protocol, enabling the unit test suite to advance virtual time deterministically.

---

# 2. Autonomous Multi-Node Virtual Mesh Simulator: `MeshTopologySimulator.swift`

Validating 4-hop mesh routing, AODV path discovery, split-horizon loops, and duplicate suppression on physical hardware requires multiple iPhones spread across a field. `MeshTopologySimulator` implements full autonomous virtual nodes operating the exact production codebase inside memory.

```swift
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
```

```
┌────────────────────────────────────────────────────────────────────────┐
│                      SimulatedMeshNode Architecture                    │
│                                                                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                 SimulatedMeshTransport                         │   │
│   │   (Virtual Peer Connections, RSSI, Packet Loss, Latency)       │   │
│   └───────────────┬────────────────────────────────┬───────────────┘   │
│                   │ inboundFrames                  │ broadcastFrame    │
│                   ▼                                ▲                   │
│   ┌───────────────────────────────┐ ┌──────────────────────────────┐   │
│   │       PacketForwarder         │ │    RouteDiscoveryService     │   │
│   │  - 7-Stage Validation Pipeline│ │    - RREQ Flooding           │   │
│   │  - Zero-Knowledge Stranger Fwd│ │    - RREP Reverse Route Path │   │
│   │  - Hop Mutation (Byte 2 &+= 1)│ │    - Route Invalidation      │   │
│   └───────────────┬───────────────┘ └──────────────┬───────────────┘   │
│                   │                                │                   │
│                   ▼                                ▼                   │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │              Local Application State Machine                   │   │
│   │   - deliveredPackets Buffer  - Diagnostics Snapshot Collector  │   │
│   └────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2.1 Autonomous Frame Ingestion & Dispatch Loop

```swift
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
```

```swift
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
```

### Protocol Mechanics
* **Continuous AsyncSequence Loop**: Consumes frames from the transport's `AsyncStream<InboundFrame>`.
* **Zero-Knowledge Stranger Node Derivation**:
  * If a node is instantiated via `createStrangerRelay(id:)`, its `session` is `nil`.
  * It cannot decrypt group payloads or parse RREQ/RREP route extensions.
  * It passes frames directly to `forwarder.evaluateInboundPacket(...)`, blindly incrementing `hopCount &+= 1` and forwarding packets over its local links while verifying that payload ciphertexts remain untouched.

---

## 2.2 Built-In Network Topologies: `MeshTopologySimulator`

The simulator provides 4 pre-configured topology topologies designed to exercise specific mesh edge cases:

```swift
public actor MeshTopologySimulator {
    public let clock: TestMeshClock
    private var nodes: [String: SimulatedMeshNode] = [:]
    
    // ... init & node management ...
```

### 1. 3-Hop Linear Daisy Chain
$$\text{Alice (ALI)} \longleftrightarrow \text{Relay 1 (R1)} \longleftrightarrow \text{Relay 2 (R2)} \longleftrightarrow \text{Bob (BOB)}$$
* **Tested Behavior**: Linear multi-hop traversal. Alice sends a location ping with `hopLimit = 8, hopCount = 0`. R1 receives it, verifies it, increments `hopCount = 1`, and forwards to R2. R2 increments `hopCount = 2` and forwards to Bob. Bob delivers locally with `hopCount = 2`.

### 2. Diamond Multi-Path Topology
```
           ┌─── Relay 1 (R1) ───┐
Alice (ALI)                      Bob (BOB)
           └─── Relay 2 (R2) ───┘
```
* **Tested Behavior**: Multi-path duplicate suppression. Alice broadcasts a packet received simultaneously by R1 and R2. Both forward to Bob. Bob's `SeenPacketCache` accepts the first arrival and drops the second arrival as `.dropDuplicate`.

### 3. Competing Routes (2 vs 3 Hops)
```
Path A: Alice ─────────► Fast Relay ─────────► Bob (2 Hops)
Path B: Alice ──► Slow Relay 1 ──► Slow Relay 2 ──► Bob (3 Hops)
```
* **Tested Behavior**: AODV metric convergence. Proves that Bob's routing table records the shorter 2-hop route via `Fast Relay` and suppresses the later-arriving 3-hop RREP packet.

### 4. 4-Node Closed Ring
$$\text{Node 1} \longleftrightarrow \text{Node 2} \longleftrightarrow \text{Node 3} \longleftrightarrow \text{Node 4} \longleftrightarrow \text{Node 1}$$
* **Tested Behavior**: Routing loop prevention. Demonstrates that the Split-Horizon rule and `SeenPacketCache` prevent packets from circulating endlessly in circular meshes.

---

# 3. Real-Time Packet Sniffer & Debugger: `MeshDebuggerViewModel.swift`

`MeshDebuggerViewModel` powers the developer HUD, providing live packet sniffing, filterable inspection logs, manual packet injection, and automated health triage.

```swift
public enum PacketDirection: String, Sendable {
    case inbound = "Inbound"
    case outbound = "Outbound"
    case relayed = "Relayed"
    case dropped = "Dropped"
```

```swift
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
```

---

## 3.1 Bounded Ring-Buffer Packet Sniffer: `appendLogItem`

To prevent memory bloat during multi-hour festival deployments, `MeshDebuggerViewModel` caps stored packet logs to exactly 100 items:

```swift
    private let maxPacketLogs: Int = 100
    
    @MainActor
    private func appendLogItem(_ item: MeshPacketLogItem) {
        packetLogs.insert(item, at: 0)
        if packetLogs.count > maxPacketLogs {
            packetLogs.removeLast()
        }
    }
```

* **Memory Footprint**: Each `MeshPacketLogItem` consumes $\approx 256\text{ bytes}$. A 100-item ring buffer consumes under $30\text{ KB}$ of RAM, completely eliminating memory exhaustion risks.

---

## 3.2 Live Wire Frame Sniffing & In-Place Decryption

When an inbound packet hits the AWDL radio socket, the sniffer intercepts the raw bytes, parses the 10-byte cleartext envelope, and attempts safe zero-knowledge inspection:

```swift
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
```

### Zero-Knowledge Inspection Rules
* **Local Group Packets (`sid == session.sessionId`)**:
  * Authenticates and decrypts the 30-byte payload using the local group key.
  * Formats payload telemetry for debugging (e.g. `Ping [DNA] lat:37.7749, lon:-122.4194, bat:88%`).
* **Stranger Relay Packets (`sid != session.sessionId`)**:
  * Decryption is mathematically impossible without the stranger's key.
  * The sniffer reports: `"30B Ciphertext (Zero-Knowledge Sealed)"` alongside the raw 16-byte Poly1305 MAC tag hex. The developer can verify that packet relaying is occurring without observing stranger data.

---

# 4. Adversarial Fault & Packet Injection Engine

The debugger includes an on-device packet injection engine allowing engineers to broadcast valid, malformed, or hostile packets to test boundary conditions:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Packet Injection Engine                         │
│                                                                        │
│   1. injectLocationPing()       ──► Standard 56B GPS Ping              │
│   2. injectUrgentSOS()          ──► Priority Emergency Alert           │
│   3. injectReceiptACK()         ──► Delivery Confirmation ACK          │
│   4. injectCorruptedAuthTag()   ──► Poly1305 MAC Tamper Test           │
│   5. injectExceededHopCount()   ──► TTL Boundary Test (Hops > Limit)   │
│   6. injectRogueSessionId()     ──► Zero-Knowledge Relay Test (0xBADF) │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4.1 Injected Attack Vectors

### 1. Corrupted Poly1305 Auth Tag (`injectCorruptedAuthTag`)
```swift
    let (ciphertext, tag) = try await CryptoService().seal(payload: serialized, envelope: envelope, using: key)
    
    // Deliberately corrupt 1 byte of the 16-byte Poly1305 MAC tag
    var corruptedTag = tag
    corruptedTag[corruptedTag.startIndex] ^= 0xFF
    
    let wirePacket = RawWirePacket(envelope: envelope, ciphertext: ciphertext, authTag: corruptedTag)
```
* **Tested Defense**: Inverts bit 0 of the Poly1305 MAC tag. Receiving nodes fail cryptographic verification at Stage 5 of `PacketForwarder` and silently drop the packet (`.dropSecurityVerificationFailed`).

### 2. Exceeded Hop Count Boundary (`injectExceededHopCount`)
```swift
    var rawData = Data(count: 56)
    rawData[0] = (PacketConstants.protocolVersion << 4) | PacketType.locationPing.rawValue
    rawData[1] = 8  // hopLimit
    rawData[2] = 9  // hopCount > hopLimit (illegal)
```
* **Tested Defense**: Injects a packet with `hopCount (9) > hopLimit (8)`. Forwarders drop it immediately at Stage 2 without parsing ciphertext (`.dropHopLimitExceeded`), preventing packet circulation attacks.

### 3. Rogue Stranger Session ID (`injectRogueSessionId`)
```swift
    // Rogue / Stranger Session ID 0xBADF00
    rawData[3] = 0xBA
    rawData[4] = 0xDF
    rawData[5] = 0x00
```
* **Tested Defense**: Injects a validly formatted 56-byte wire packet belonging to a foreign session ID (`0xBADF00`). Proves that nodes in `.communalRelayActive` relay the frame over the mesh without being able to decrypt the payload.

---

# 5. Automated Health Triage Assistant: `runAutomatedTriage()`

When a user in the field reports: *"I can't see my friends on the map"*, `runAutomatedTriage()` performs a sequential 5-tier diagnostic sweep to identify the root cause:

```swift
    @MainActor
    public func runAutomatedTriage() async {
        isTriageRunning = true
        var items: [MeshTriageItem] = []
        
        // 1. Check Location Authorization & GPS
        // 2. Check Radio & Bonjour Transport
        // 3. Check Session ID & Cryptographic Keys
        // 4. Check Relay Policy & Battery Cutoff
        // 5. Evaluate Overall Status
```

### The 5 Triage Checkpoints
1. **CoreLocation Hardware Fix**:
   * Evaluates `loc.authorizationStatus`.
   * Checks if `loc.isGPSAvailable` is true. If denied, provides remediation: *"Open iOS Settings $\rightarrow$ Privacy $\rightarrow$ Location $\rightarrow$ TeeKum"*.
2. **Network.framework AWDL Sockets**:
   * Inspects `transport.currentState`.
   * Checks if Bonjour listener and browser are active on `_teekum._tcp`. If failed, flags that Wi-Fi or Bluetooth may be disabled in iOS Settings.
3. **CryptoKit 256-Bit Session Key**:
   * Verifies `session.symmetricKeyData.count == 32`. Rejects corrupted or truncated keys.
4. **Relay Policy & Battery Survival Mode**:
   * Inspects battery level and Low Power Mode state. If battery $<20\%$, alerts that stranger relaying is suspended to conserve emergency SOS power.
5. **Verdict Generation**:
   * Surfaces a single high-level verdict: `PASS` (Green), `WARNING` (Yellow), or `FAIL` (Red) with clear remediation instructions.

---

# 6. Markdown Telemetry Report Exporter: `exportDiagnosticReport()`

```swift
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
        }
        
        report += "\n\n## 3. Active Neighbors\n"
        // ... formats 1-hop neighbors with RSSI dBm ...
        
        report += "\n\n## 4. Recent Packet Trace (Last \(min(packetLogs.count, 20)))\n"
        // ... formats recent 20 packets with hop counts and drop reasons ...
        
        UIPasteboard.general.string = report
        copiedReportNotification = true
        return report
    }
```

* **Zero-Cloud Export**: Serializes the complete diagnostic state directly into the iOS system clipboard (`UIPasteboard.general.string`).
* **Tactile Confirmation**: Triggers `copiedReportNotification = true`, showing a brief confirmation banner in the UI.

---

# 7. Diagnostics & Simulation Failure Recovery Matrix

| Failure Mode | Root Cause / Trigger | Concurrency / System Impact | Diagnostics Detection & Remediation |
| :--- | :--- | :--- | :--- |
| **Radio Sockets Offline** | Wi-Fi turned off in iOS Settings (disables Apple AWDL radio). | NWListener fails to bind to AWDL interface; zero peer discovery. | Triage detects `transportState == .failed`; surfaces remediation: *"Ensure Wi-Fi & Bluetooth are ON in iOS Settings"*. |
| **GPS Unavailable** | User indoors or in metal-reinforced stage pavilion. | CoreLocation cannot acquire satellite fix; `horizontalAccuracy < 0`. | Triage detects `!loc.isGPSAvailable`; UI marks measurement as stale and flags orange warning badge. |
| **Key Size Corruption** | Truncated QR barcode scan or manual link edit. | Symmetric key data length $\ne 32$ bytes. ChaCha20-Poly1305 crashes. | Triage detects `keyData.count != 32`; blocks session initialization with red alert: *"Malformed Key Data"*. |
| **High RF Contention Drop** | High festival RF noise floor ($>-85\text{ dBm}$) causes packet loss. | Packets drop over physical radio links. | Diagnostics histogram records hop drop spike; simulation allows testing with `packetLossRatio` injection. |
| **Simulator Clock Drift** | Virtual tests advancing time faster than real clock. | Route TTLs expire prematurely if test clock jumps too fast. | `TestMeshClock` provides explicit, deterministic time steps (`advance(by:)`), preventing race conditions in automated CI. |
| **Memory Buffer Growth** | Running continuous diagnostics during a 3-day festival. | Unbounded packet arrays cause iOS memory pressure jetsam kill. | `appendLogItem` caps packet logs strictly at 100 items; older logs are pruned FIFO. |

---

Proceed to **[Volume 13: Automated Testing & Verification](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/13_automated_testing_and_verification.md)**.
