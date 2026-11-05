# TeeKum Code Handbook — Volume 03: Transport & Cryptography Engines

This volume examines the physical radio transport, stream message framing, deterministic peer connection negotiation, and cryptographic integrity engines powering TeeKum.

---

## 📑 Included Files

1. [`TeeKum Prototype/Core/Transport/PeerTransportService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Transport/PeerTransportService.swift) — Apple `Network.framework` transport actor managing AWDL, Wi-Fi Direct, and Bonjour discovery.
2. [`TeeKum Prototype/Core/Transport/StreamMessageFramer.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Transport/StreamMessageFramer.swift) — Self-synchronizing stream delimitation and packet recovery buffer.
3. [`TeeKum Prototype/Core/Transport/PeerTransport.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Transport/PeerTransport.swift) — Transport protocol interfaces, `PeerInfo`, and `InboundPacket`.
4. [`TeeKum Prototype/Core/Transport/SimulatedMeshTransport.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Transport/SimulatedMeshTransport.swift) — In-memory multi-node simulator with packet loss and jitter simulation.
5. [`TeeKum Prototype/Core/Security/CryptoService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Security/CryptoService.swift) — AEAD cipher actor (`ChaCha20-Poly1305` / `AES-GCM`) and `ReplayProtectionFilter`.
6. [`TeeKum Prototype/Core/Security/CryptoServiceProtocol.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Security/CryptoServiceProtocol.swift) — Cryptographic provider contracts and error domains.

---

# 1. Physical Radio Layer & AWDL Realities

TeeKum operates without cellular towers or Wi-Fi routers by utilizing **Apple Wireless Direct Link (AWDL)**. AWDL is a proprietary Apple protocol operating across the Wi-Fi and Bluetooth chipsets:
* It synchronizes 802.11 Wi-Fi channel hops between devices using microsecond Bluetooth Low Energy (BLE) beacons.
* It sets up ad-hoc peer-to-peer data channels (`_teekum._tcp`) directly between iOS devices.
* Because TCP provides a continuous stream of bytes rather than discrete packets, packets can be fragmented, delayed, or coalesced over the air.

```
+-------------------------------------------------------+
|  Incoming TCP Byte Stream from NWConnection.receive   |
+--------------------+---------------------+------------+
| Partial Packet (20B)| Coalesced Packet(56B)| Rest (14B) |
+--------------------+---------------------+------------+
                         │
                         ▼
        ┌──────────────────────────────────┐
        │       StreamMessageFramer        │
        │  • Buffers partial bytes         │
        │  • Extracts exact 56B frames     │
        │  • Discards corrupt headers      │
        └──────────────────────────────────┘
                         │
                         ▼
        ┌──────────────────────────────────┐
        │  RawWirePacket.fromWireData()    │
        │  (10B Env + 30B Cipher + 16B Tag)│
        └──────────────────────────────────┘
```

---

# 2. `StreamMessageFramer.swift`

```swift
public final class StreamMessageFramer: @unchecked Sendable {
    private var buffer = Data()
    public let maxBufferSize: Int
    
    public init(maxBufferSize: Int = 65536) {
        self.maxBufferSize = maxBufferSize
    }
    
    public func processIncomingChunk(_ chunk: Data) throws -> [Data] {
        guard !chunk.isEmpty else { return [] }
        buffer.append(chunk)
        
        guard buffer.count <= maxBufferSize else {
            buffer.removeAll()
            throw TransportError.listenerFailed("Stream buffer overflow: exceeded max buffer size.")
        }
        
        var frames: [Data] = []
        
        while buffer.count >= PacketConstants.wirePacketSize {
            let startIndex = buffer.startIndex
            let byte0 = buffer[startIndex]
            let version = (byte0 >> 4) & 0x0F
            let typeRaw = byte0 & 0x0F
            
            // Check if Byte 0 contains valid protocol version (0x03) and recognized PacketType
            if version == PacketConstants.protocolVersion, PacketType(rawValue: typeRaw) != nil {
                let frameEnd = startIndex + PacketConstants.wirePacketSize
                let frameData = buffer.subdata(in: startIndex..<frameEnd)
                frames.append(frameData)
                buffer.removeSubrange(startIndex..<frameEnd)
            } else {
                // Stream misalignment detected: discard the leading byte to seek the next valid packet header
                buffer.removeFirst(1)
            }
        }
        
        return frames
    }
}
```

### Line-by-Line Breakdown
* `private var buffer = Data()`: Internal byte accumulator holding partial packets across multiple async socket read callbacks.
* `guard buffer.count <= maxBufferSize else`: Memory exhaustion defense. If a malicious or corrupted peer floods data without a valid delimiter, the buffer drops its contents after 64 KB rather than crashing the device with an Out-Of-Memory (OOM) panic.
* `while buffer.count >= PacketConstants.wirePacketSize`: Loops as long as at least 56 bytes are available.
* `let version = (byte0 >> 4) & 0x0F`: Reads the upper 4 bits of the header byte.
* `buffer.removeFirst(1)`: **Self-synchronizing slide**. If line noise or dropped radio frames introduce offset bytes, the framer slides forward one byte at a time until the next valid packet magic header is detected.

---

# 3. `PeerTransportService.swift`

## 3.1 Architecture & State Isolation

```swift
public actor PeerTransportService: PeerTransport, MeshTransport {
    private var listener: NWListener?
    private var browser: NWBrowser?
    private let dispatchQueue = DispatchQueue(label: "com.teekum.peertransport", qos: .userInitiated)
    private var connections: [String: PeerConnection] = [:]
    private let outbox = PriorityOutboxQueue()
    public let neighborTable: NeighborTable
    public let rateLimiter: ForwardingBudgetManaging
    public private(set) var isRelayEnabled: Bool = true
```

### Actor Guarantees
* Isolated within the `PeerTransportService` actor. Mutating connections, updating neighbor tables, and modifying socket endpoints cannot suffer from thread race conditions.
* Bridges Network.framework's block-based GCD callbacks into modern Swift `AsyncStream` continuations (`inboundPackets`, `peerUpdates`, `sendOutcomes`).

---

## 3.2 Deterministic Tie-Breaking & Connection Duplication Defense

When two devices (Device A and Device B) discover each other simultaneously over Bonjour, both phones attempt to dial an outbound `NWConnection`. If unhandled, this results in two conflicting sockets between the same devices, wasting radio bandwidth and battery.

```swift
    private func shouldAcceptInbound(remotePeerId: String) -> Bool {
        // Deterministic lexicographical tie-break
        if let existing = connections[remotePeerId] {
            if existing.isReady {
                return false // Already stably connected
            }
            // Tie-break: node with higher alphabetical peer ID keeps outbound
            return localPeerId < remotePeerId
        }
        return true
    }
```

### Mathematical Invariant
* If `Peer A ("ALX")` and `Peer B ("DNA")` dial each other simultaneously:
  * Since `"ALX" < "DNA"`, Device A yields to Device B's incoming connection and aborts its own outbound attempt.
  * Device B maintains its outbound socket to Device A.
  * Result: Exactly **one** bidirectional TCP connection is formed deterministically.

---

# 4. Cryptographic Service: `CryptoService.swift`

## 4.1 Authenticated Encryption with Associated Data (AEAD)

```swift
public actor CryptoService: CryptoServiceProvider {
    private var inMemoryKeys: [UInt16: SymmetricKey] = [:]
    public let replayFilter: ReplayProtectionFilter
    
    public func seal(
        payload: Data,
        envelope: CleartextEnvelope,
        using key: SymmetricKey
    ) throws -> (ciphertext: Data, authTag: Data) {
        guard payload.count == PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.invalidPacketSize(...)
        }
        
        let nonceData = envelope.constructNonce()
        guard let nonce = try? ChaChaPoly.Nonce(data: nonceData) else {
            throw CryptoServiceError.encryptionFailed("Nonce construction failed")
        }
        
        let aad = envelope.authenticatedAssociatedData()
        
        do {
            let sealedBox = try ChaChaPoly.seal(payload, using: key, nonce: nonce, authenticating: aad)
            return (ciphertext: Data(sealedBox.ciphertext), authTag: Data(sealedBox.tag))
        } catch {
            throw CryptoServiceError.encryptionFailed(error.localizedDescription)
        }
    }
```

### Cryptographic Security Proof
1. **Confidentiality**: ChaCha20 / AES-256 encrypts the 30-byte payload. Outside observers (and intermediate stranger relays) cannot view friend coordinates, battery levels, or text messages.
2. **Integrity & Authenticity**: Poly1305 / GHASH produces a 16-byte authentication tag over the ciphertext AND the Associated Data (AAD).
3. **Tamper Proofing**: If an attacker tampers with the `hopLimit`, `sessionId`, or `type` in the cleartext header, the tag verification fails during `open()` and the packet is immediately dropped.

---

## 4.2 Decryption & Authentication Verification

```swift
    public func open(
        ciphertext: Data,
        envelope: CleartextEnvelope,
        authTag: Data,
        using key: SymmetricKey
    ) throws -> Data {
        let nonceData = envelope.constructNonce()
        guard let nonce = try? ChaChaPoly.Nonce(data: nonceData) else {
            throw CryptoServiceError.authenticationFailed
        }
        
        let aad = envelope.authenticatedAssociatedData()
        
        do {
            let sealedBox = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: authTag)
            let plaintext = try ChaChaPoly.open(sealedBox, using: key, authenticating: aad)
            return plaintext
        } catch {
            throw CryptoServiceError.authenticationFailed
        }
    }
```

### Safety Guarantee
* If decryption or authentication throws an error, the raw ciphertext is destroyed. Plaintext memory buffers are never instantiated or leaked to view-models.

---

# 5. `ReplayProtectionFilter`: Defending Against Mesh Replays

```swift
public actor ReplayProtectionFilter {
    private struct PacketKey: Hashable {
        let sessionId: UInt16
        let sequenceNumber: UInt32
    }
    
    private let deduplicationWindow: TimeInterval
    private let maxClockSkew: TimeInterval
    private var seenPackets: [PacketKey: Date] = [:]
    private var highestSequencePerSender: [String: UInt32] = [:]
    private var latestTimestampPerSender: [String: Date] = [:]
```

### Multi-Tiered Verification Rules
1. **Sliding Window Deduplication**: Tracks every seen `(sessionId, sequenceNumber)` pair for 300 seconds (5 minutes). Re-broadcasted duplicate mesh echoes are instantly rejected without decrypting.
2. **Clock Skew Guard**: Validates that the payload timestamp is not more than 5 minutes into the future, preventing malicious nodes from poisoning timelines.
3. **Monotonic Sequence Enforcement**: Ensures that sequence numbers from a specific sender strictly advance.
4. **Out-of-Order Coordinate Rejection**: If an old location ping arrives delayed via a slow multi-hop detour after a fresh direct ping was already received, the old coordinate is discarded to prevent friend pins from jumping backwards on the map.

---

# 6. `SimulatedMeshTransport.swift`: Testing Without Radios

```swift
public actor SimulatedMeshTransport: PeerTransport, MeshTransport {
    private var simulatedPeers: [String: PeerInfo] = [:]
    public var packetDropRate: Double = 0.0
    public var artificialLatency: TimeInterval = 0.05
    
    public func injectPacket(_ packet: RawWirePacket, from senderId: String) {
        guard Double.random(in: 0...1) >= packetDropRate else { return }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(artificialLatency * 1_000_000_000))
            inboundContinuation?.yield(InboundPacket(rawPacket: packet, sourcePeerId: senderId))
        }
    }
}
```

* Enables 100% deterministic, offline automated unit tests. Allows test suites to simulate 30% packet loss, 200ms radio latency, and multi-hop routing without requiring physical iOS hardware.

---

Proceed to **[Volume 04: Mesh Routing Engine](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/04_mesh_routing_engine.md)**.
