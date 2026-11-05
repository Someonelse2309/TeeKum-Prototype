# TeeKum Code Handbook — Volume 12: Feature — Mesh Diagnostics & Simulation

This volume breaks down the operational telemetry pipeline, privacy-preserving diagnostics snapshots, the autonomous multi-node virtual mesh simulator, and the real-time visual mesh debugger in TeeKum.

---

## 📑 Included Files

1. [`TeeKum Prototype/Features/Diagnostics/Services/MeshDiagnostics.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/Services/MeshDiagnostics.swift) — Immutable diagnostic snapshot tracking the 7 core mesh operational metrics.
2. [`TeeKum Prototype/Features/Diagnostics/Services/MeshTopologySimulator.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/Services/MeshTopologySimulator.swift) — Autonomous multi-node virtual mesh engine for deterministic simulation.
3. [`TeeKum Prototype/Features/Diagnostics/ViewModels/MeshDebuggerViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/ViewModels/MeshDebuggerViewModel.swift) — Presentation ViewModel managing live packet sniffers, filters, and fault injection.
4. [`TeeKum Prototype/Features/Diagnostics/Views/DiagnosticsView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/Views/DiagnosticsView.swift) — High-level telemetry HUD card presenting hop histograms and forwarding counters.
5. [`TeeKum Prototype/Features/Diagnostics/Views/MeshDebuggerView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/Views/MeshDebuggerView.swift) — Developer tool interface displaying visual node graphs, packet inspection logs, and manual packet injectors.

---

# 1. Operational Telemetry: `MeshDiagnosticsSnapshot`

```swift
public struct MeshDiagnosticsSnapshot: Sendable, Equatable {
    // 1. Forwarding attempts (total, successes, failures)
    public var forwardingAttempts: Int
    public var forwardingSuccesses: Int
    public var forwardingFailures: Int
    
    // 2. Packets dropped (categorized by exact failure reason)
    public var droppedRateLimit: Int
    public var droppedHopLimit: Int
    public var droppedQueueSaturation: Int
    public var droppedPolicyDisabled: Int
    public var droppedBatterySurvival: Int
    public var droppedMalformed: Int
    public var droppedSecurityFailed: Int
    public var droppedSimulatedLoss: Int
    
    // 3. Duplicates suppressed
    public var duplicatesSuppressed: Int
    
    // 4. Route discoveries (initiated, succeeded, failed)
    public var routeDiscoveriesInitiated: Int
    public var routeDiscoveriesSucceeded: Int
    public var routeDiscoveriesFailed: Int
    
    // 5. Route failures / invalidations
    public var routeFailuresOrInvalidations: Int
    
    // 6. Hop count metrics
    public var maxHopCountObserved: UInt8
    public var hopCountHistogram: [UInt8: Int] // [HopCount: Count]
    public var averageHopCount: Double
    
    // 7. Queue saturation & memory footprint
    public var queueSaturationDrops: Int
    public var urgentQueueDepth: Int
    public var relayQueueDepth: Int
    public var normalQueueDepth: Int
```

---

## 1.1 The Zero-Knowledge Privacy Guarantee

```swift
    public var containsLocationData: Bool { false }
    public var containsCryptographicKeys: Bool { false }
    public var isPrivacyCompliant: Bool { true }
```

### Engineering Invariant
* Under **NO circumstances** does the diagnostic system retain, log, or export user GPS coordinates, friend locations, or 256-bit symmetric keys.
* Only aggregated packet counts, queue depths, and anonymized hop histograms are collected.

---

# 2. Virtual Multi-Node Simulator: `MeshTopologySimulator.swift`

Testing an ad-hoc 5-hop mesh network in an office or automated CI pipeline without physical iPhones is challenging. `MeshTopologySimulator` implements full autonomous virtual nodes:

```swift
public actor SimulatedMeshNode {
    public let id: String
    public let initials: String
    public let clock: TestMeshClock
    public let cryptoService: CryptoService
    public let routingTable: RoutingTable
    public let neighborTable: NeighborTable
    public let rateLimiter: ForwardingRateLimiter
    public let seenPacketCache: SeenPacketCache
    public let transport: SimulatedMeshTransport
    public let forwarder: PacketForwarder
    public let routeDiscovery: RouteDiscoveryService
```

### Supported Topologies
* **Linear Daisy Chain**: $A \longleftrightarrow B \longleftrightarrow C \longleftrightarrow D \longleftrightarrow E$ (verifies 4-hop multi-hop relaying and TTL decrements).
* **Star Cluster**: Multiple leaf nodes connected through a single central relay.
* **Partition & Recovery**: Simulates walking behind a concrete stadium wall by dynamically dropping peer connections and verifying that AODV discovers an alternate route.

---

# 3. Real-Time Packet Sniffer: `MeshDebuggerViewModel.swift`

`MeshDebuggerView` gives developers a live window into what the iPhone radio is doing in real time:

```swift
public enum PacketDirection: String, Sendable {
    case inbound  = "Inbound"  // Received from direct peer
    case outbound = "Outbound" // Originated by this phone
    case relayed  = "Relayed"  // Blindly forwarded for a stranger
    case dropped  = "Dropped"  // Suppressed (duplicate, TTL, rate limit)
}
```

### Capabilities
1. **Live Wire Sniffer**: Inspects raw 56-byte datagrams, showing cleartext envelope headers and hex dumps.
2. **Directional Filtering**: Filters by `.inbound`, `.outbound`, `.relayed`, or `.dropped`.
3. **Manual Packet Injector**: Allows manual crafting and broadcasting of raw test packets to test edge-case recovery in the field.

---

Proceed to **[Volume 13: Automated Testing & Verification](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/13_automated_testing_and_verification.md)**.
