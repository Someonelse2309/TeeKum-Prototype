# TeeKum Code Handbook — Volume 04: Mesh Routing Engine (Definitive Deep-Dive)

This volume provides an exhaustive, method-by-method architectural deep-dive into Ad-hoc On-Demand Distance Vector (AODV) routing, multi-hop blind packet forwarding, zero-knowledge stranger relaying, token bucket traffic shaping, and duplicate packet suppression in TeeKum.

---

## 📑 Included Source Files

1. [`TeeKum Prototype/Core/Mesh/PacketForwarder.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/PacketForwarder.swift) (354 lines) — Authoritative multi-hop packet forwarder, blind relay gate, and wire mutation engine.
2. [`TeeKum Prototype/Core/Mesh/RouteDiscoveryService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/RouteDiscoveryService.swift) (675 lines) — Reactive AODV route discovery supervisor (`ROUTE_REQ` / `ROUTE_RESP`), in-flight coalescer, and loop detector.
3. [`TeeKum Prototype/Core/Mesh/RoutingTable.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/RoutingTable.swift) (312 lines) — Forward routing table (64 entries, 30–60s TTL) and reverse return paths (128 entries, 15s TTL).
4. [`TeeKum Prototype/Core/Mesh/SeenPacketCache.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/SeenPacketCache.swift) (174 lines) — Bounded 1,024-entry LRU duplicate packet suppression cache with 300s sliding window.
5. [`TeeKum Prototype/Core/Mesh/ForwardingRateLimiter.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/ForwardingRateLimiter.swift) (120 lines) — Dual-lane token bucket traffic shaper (2 pkts/s ordinary, 4 pkts/s SOS).
6. [`TeeKum Prototype/Core/Mesh/NeighborTable.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/NeighborTable.swift) (386 lines) — 1-hop physical neighbor registry, link health metrics, and packet loss ratio calculation.
7. [`TeeKum Prototype/Core/Mesh/RelayPolicyManager.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/RelayPolicyManager.swift) (313 lines) — Communal mesh participation modes, 20% battery cutoff, and zero-knowledge telemetry counters.
8. [`TeeKum Prototype/Core/Mesh/MeshTimingConfiguration.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/MeshTimingConfiguration.swift) (130 lines) — Timing constants, intervals, and hop bounds.
9. [`TeeKum Prototype/Core/Mesh/MeshProtocols.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/MeshProtocols.swift) (110 lines) — Dependency injection protocol interfaces.

---

# 1. Hybrid Mesh Architecture: Controlled Flooding vs Reactive AODV

TeeKum utilizes a **hybrid routing architecture** tailored for high-density, dynamic festival crowds:

```
+-----------------------------------+-----------------------------------+
| Packet Type                       | Routing Strategy                  |
+-----------------------------------+-----------------------------------+
| Emergency SOS (Type 0x02)         | Controlled Bounded Flooding (15H) |
| Meeting Point Updates (Type 0x03) | Controlled Bounded Flooding (15H) |
| Location Pings (Type 0x01)        | Bounded Flooding (8 Hops)         |
| Chat Messages (Type 0x07)         | Unicast AODV Next-Hop Route (8H)  |
| Delivery ACKs (Type 0x06)         | Unicast AODV Reverse Path (8 Hops)|
+-----------------------------------+-----------------------------------+
```

* **Controlled Flooding**: Packets are broadcast to all direct 1-hop neighbors (except the node that sent it). Every node records the packet's canonical key in its `SeenPacketCache`. Duplicate echoes arriving over different paths are instantly dropped.
* **Reactive AODV (Ad-hoc On-Demand Distance Vector)**: For high-frequency unicast traffic (chat messages), flooding the entire festival is too bandwidth-intensive. TeeKum initiates an on-demand route query (`ROUTE_REQ`), discovers the shortest next-hop path, and caches it in `RoutingTable`.

---

# 2. Main Forwarding Pipeline: `PacketForwarder.swift`

```swift
public actor PacketForwarder: PacketForwarding {
    private let routingTable: RoutingTableManaging
    private let rateLimiter: ForwardingBudgetManaging
    private let neighborTable: NeighborManaging
    private let seenPacketCache: SeenPacketCache
    private let clock: MeshClock
    private let cryptoService: CryptoServiceProvider?
    private let sessionProvider: (@Sendable () -> GroupSession?)?
    private let policyManager: RelayPolicyManaging?
```

---

## 2.1 The 7-Stage Forwarding Evaluation Pipeline

```swift
    public func evaluateInboundPacket(
        wireData: Data,
        fromPeerId: String
    ) async -> ForwardingDecision {
        totalEvaluatedCount += 1
        
        // Stage 1: Strict Size & Wire Integrity Verification
        guard wireData.count == PacketConstants.wirePacketSize else {
            totalDroppedMalformedCount += 1
            return .dropMalformed
        }
        
        let byte0 = wireData[wireData.startIndex]
        let version = (byte0 >> 4) & 0x0F
        guard version == PacketConstants.protocolVersion else {
            totalDroppedMalformedCount += 1
            return .dropMalformed
        }
        guard let packetType = PacketType(rawValue: byte0 & 0x0F) else {
            totalDroppedMalformedCount += 1
            return .dropMalformed
        }
```

### Stage 1: Fast Wire Verification
* Slices Byte 0. If `version != 0x03` or `packetType` is unrecognized, drops immediately without allocating memory or running cryptographic operations.

```swift
        // Stage 2: Type-Specific Hop Limit Enforcement
        let hopLimit = wireData[wireData.startIndex + 1]
        let hopCount = wireData[wireData.startIndex + 2]
        
        let effectiveLimit: UInt8
        switch packetType {
        case .sos:              effectiveLimit = PacketConstants.sosHopLimit          // 15
        case .meetingUpdate:    effectiveLimit = PacketConstants.meetingPointHopLimit // 15
        case .chatMessage, .ack:effectiveLimit = PacketConstants.chatHopLimit         // 8
        case .uwbTokenExchange: effectiveLimit = PacketConstants.uwbHopLimit          // 1
        default:                effectiveLimit = PacketConstants.defaultHopLimit      // 8
        }
        
        guard hopCount < effectiveLimit else {
            totalDroppedHopLimitCount += 1
            return .dropHopLimitExceeded
        }
```

### Stage 2: Clamping & Hop Limit Defense
* Clamps hop limit to the strict architectural maximum for that packet type (`effectiveLimit`).
* Prevents malicious or buggy nodes from injecting packets with `hopLimit = 255` to induce perpetual routing loops.

```swift
        // Stage 3: Duplicate Suppression Cache
        let rawPacket = try RawWirePacket.fromWireData(wireData)
        let packetKey = PacketKey(wirePacket: rawPacket)
        let isDuplicate = await seenPacketCache.isDuplicateAndRecord(packetKey, now: clock.now())
        if isDuplicate {
            totalDroppedDuplicatesCount += 1
            return .dropDuplicate
        }
```

### Stage 3: Canonical Key Deduplication
* Extracts the 7-byte canonical `PacketKey`:
  $$\mathtt{PacketKey} = (\mathtt{sessionId}, \mathtt{sequenceNumber}, \mathtt{type})$$
* **Notice**: `hopCount` is intentionally excluded from `PacketKey`! If node A broadcasts a packet at hop 0, and node B relays it at hop 1, both packets share the same `PacketKey`. When node A hears its own packet echoed back from node B, node A recognizes it as a duplicate and drops it.

```swift
        // Stage 4: Local Group Session Matching
        let localSession = sessionProvider?()
        if let session = localSession, rawPacket.envelope.sessionId == session.sessionId {
            // Addressed to our group! Decrypt and authenticate Poly1305 MAC tag
            guard let crypto = cryptoService else { return .dropSecurityVerificationFailed }
            let key = SymmetricKey(data: session.symmetricKeyData)
            do {
                let decrypted = try await crypto.open(
                    ciphertext: rawPacket.ciphertext,
                    envelope: rawPacket.envelope,
                    authTag: rawPacket.authTag,
                    using: key
                )
                totalLocallyDeliveredCount += 1
                return .deliverLocally
            } catch {
                return .dropSecurityVerificationFailed
            }
        }
```

### Stage 4: Local Group Acceptance
* If `sessionId == session.sessionId`, the packet belongs to our festival friends.
* Verifies the 16-byte Poly1305 MAC tag. If authentication succeeds, returns `.deliverLocally` to pass the plaintext to `PacketRouter`.

```swift
        // Stage 5: Stranger Packet Relaying (Opt-In & Battery Cutoff)
        let policyState = await policyManager?.currentState() ?? RelayPolicyState(mode: .communalRelayActive)
        guard policyState.isPermitted(at: clock.now()) else {
            totalDroppedPolicyCount += 1
            return .dropPolicyDisabled
        }
        
        // Stage 6: Token Bucket Rate Limiting
        if packetType == .sos {
            guard await rateLimiter.consumeSOSToken() else { return .dropRateLimitExceeded }
        } else {
            guard await rateLimiter.consumeOrdinaryToken() else { return .dropRateLimitExceeded }
        }
        
        // Stage 7: Mutate hopCount (+1) & Split-Horizon Next-Hop Forwarding
        var mutatedData = wireData
        mutatedData[mutatedData.startIndex + 2] = hopCount + 1
        
        let activeNeighbors = await neighborTable.activeNeighbors()
        let eligibleNeighbors = activeNeighbors.filter { $0.id != fromPeerId } // Split-Horizon
```

### Stages 5–7: Zero-Knowledge Blind Relaying
* **Stranger Relaying**: If `sessionId != localSession.sessionId`, the phone does NOT possess the group key and CANNOT decrypt the 30-byte payload. It blindly acts as a transparent relay.
* **Battery Cutoff**: If battery is $<20\%$ or Low Power Mode is active, stranger relaying drops immediately.
* **Token Bucket**: Consumes 1 forwarding token (ordinary: 2 pkts/sec; urgent SOS: 4 pkts/sec).
* **Wire Mutation**: Increments Byte 2 (`hopCount &+= 1`). Because `CleartextEnvelope` masks Byte 2 during AAD calculation, the sender's Poly1305 MAC tag remains completely valid!
* **Split-Horizon Rule**: `filter { $0.id != fromPeerId }` prevents echoing the packet back to the node that delivered it, eliminating 2-node ping-pong routing loops.

---

# 3. Reactive AODV Route Discovery: `RouteDiscoveryService.swift`

`RouteDiscoveryService` (675 lines) implements on-demand route discovery across multi-hop paths:

```
[Alice]                                [Relay Node]                                [Bob]
   │                                         │                                       │
   │─── ROUTE_REQ (seq: 101, hop: 0) ───────►│                                       │
   │    (Stores in-flight continuation)      │─── ROUTE_REQ (seq: 101, hop: 1) ─────►│
   │                                         │    (Records reverse route:            │ (Records forward route to Alice)
   │                                         │     seq 101 -> Alice, TTL: 15s)       │
   │                                         │                                       │
   │                                         │◄── ROUTE_RESP (seq: 101, cost: 0) ────│
   │◄── ROUTE_RESP (seq: 101, cost: 1) ──────│    (Pops reverse route matching 101)  │
   │    (Records forward route to Bob;       │                                       │
   │     resumes continuation with RouteEntry)
```

---

## 3.1 In-Flight Request Coalescing

```swift
        let targetKey = "\(session.sessionId):\(sanitizedTarget)"
        
        // 1. Coalesce with existing in-flight discovery to avoid duplicate floods
        if let existingNonce = inFlightByTarget[targetKey],
           var existing = inFlightDiscoveries[existingNonce] {
            return try await withCheckedThrowingContinuation { cont in
                existing.continuations.append(cont)
                inFlightDiscoveries[existingNonce] = existing
            }
        }
```

### Anti-Flooding Guarantee
* If three different viewmodels or UI sheets request a route to `"BOB"` simultaneously, TeeKum emits strictly **ONE** broadcast `ROUTE_REQ` datagram over the radio.
* All three callers await on the same in-flight record. When `ROUTE_RESP` returns, all continuations are resumed at the exact same millisecond.

---

## 3.2 Handling Inbound Route Requests: `handleInboundRouteReq`

```swift
        // Check if local node is the target destination
        if payload.targetInitials == session.localInitials {
            // Target member reached!
            let forwardHopCount = envelope.hopCount + 1
            await routingTable.recordForwardRoute(
                destinationId: payload.originatorInitials,
                nextHop: fromPeerId,
                hopCount: forwardHopCount,
                cost: payload.routeCost + 1,
                sequenceNumber: envelope.sequenceNumber,
                ttl: 60.0
            )
            
            // Craft authenticated Route Response
            let respPayload = RouteRespPayload(
                originatorInitials: payload.originatorInitials,
                targetInitials: session.localInitials,
                discoveryNonce: payload.discoveryNonce,
                routeCost: 0
            )
            let respEnvelope = CleartextEnvelope(
                type: .routeResp,
                hopLimit: maxHops,
                hopCount: 0,
                sessionId: envelope.sessionId,
                sequenceNumber: envelope.sequenceNumber // Echo sequenceNumber for reverse route matching
            )
            let respWire = try await cryptoService.sealToWireBytes(
                payload: respPayload.serialize(),
                envelope: respEnvelope,
                using: SymmetricKey(data: session.symmetricKeyData)
            )
            _ = try await transport.sendFrame(respWire, to: fromPeerId)
            onTargetReached?(payload.originatorInitials)
            return .answeredWithRResp(targetInitials: payload.targetInitials, nextHop: fromPeerId)
        }
```

### Protocol Mechanics
1. Target matches `localInitials`.
2. Target learns the forward route back to the originator (`nextHop: fromPeerId`).
3. Target crafts a `RouteRespPayload`, copying the exact `sequenceNumber` from the request.
4. Target seals the datagram using the shared group key and unicasts `ROUTE_RESP` back to `fromPeerId`.
5. Intermediary relays inspect `sequenceNumber`, query their ephemeral reverse routing table (`reverseRoutes[sequenceNumber]`), and unicast `ROUTE_RESP` back towards the originator without flooding the mesh.

---

# 4. Routing Table & Next-Hop Caching: `RoutingTable.swift`

```swift
public actor RoutingTable: RoutingTableManaging {
    private var forwardRoutes: [String: RouteEntry] = [:]       // Bounded: 64 entries, 30s-60s TTL
    private var reverseRoutes: [UInt32: ReverseRouteEntry] = [:] // Bounded: 128 entries, 15s TTL
```

### Monotonic Sequence Invariant
* A new route to `"BOB"` is ONLY accepted if:
  1. `newRoute.sequenceNumber > existingRoute.sequenceNumber` (fresher route state), OR
  2. `newRoute.sequenceNumber == existingRoute.sequenceNumber` AND `newRoute.hopCount < existingRoute.hopCount` (shorter path for identical route freshness).
* Defends against stale, looping, or degraded routing paths.

---

# 5. `SeenPacketCache.swift`: Bounded LRU Cache

```swift
public actor SeenPacketCache {
    private let capacity: Int = 1024
    private let ttl: TimeInterval = 300.0 // 5 minutes
    private var entries: [PacketKey: CacheEntry] = [:]
    private var lruOrder: [PacketKey] = []
```

### Memory Footprint & Deterministic Eviction
* Each `PacketKey` occupies 7 bytes:
  $$\text{RAM Footprint} \approx 1024 \times (7\text{B} + 16\text{B Date} + 8\text{B Pointer}) \approx 31.7 \text{ KB}$$
* When `count > 1024`, the least recently accessed key is evicted (`lruOrder.removeFirst()`).
* Ensures deterministic bounded memory usage even during multi-day festival operation.

---

# 6. `ForwardingRateLimiter.swift`: Token Bucket Traffic Shaper

```swift
public actor ForwardingRateLimiter: ForwardingBudgetManaging {
    // Ordinary relay traffic: 2.0 pkts/s, burst capacity 4.0
    private let ordinaryCapacity: Double = 4.0
    private let ordinaryRefillRate: Double = 2.0
    private var ordinaryTokens: Double = 4.0
    
    // Urgent SOS traffic: 4.0 pkts/s, burst capacity 8.0
    private let sosCapacity: Double = 8.0
    private let sosRefillRate: Double = 4.0
    private var sosTokens: Double = 8.0
```

### Continuous Refill Formula
$$\text{tokens}_{\text{current}} = \min\left(\text{capacity}, \text{tokens}_{\text{last}} + \Delta t \times \text{refillRate}\right)$$
* Prevents battery depletion caused by high-rate packet storms while allowing instant transmission bursts for emergency alerts.

---

Proceed to **[Volume 05: Messaging Pipeline & Codecs](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/05_messaging_and_codecs.md)**.
