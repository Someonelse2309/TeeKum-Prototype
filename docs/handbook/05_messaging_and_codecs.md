# TeeKum Code Handbook — Volume 05: Messaging Pipeline & Codecs (Definitive Deep-Dive)

This volume provides an exhaustive, method-by-method architectural deep-dive into the central packet demultiplexer, priority-queued radio transmission outbox, radix-27 initials compression, and binary payload codec engines in TeeKum.

---

## 📑 Included Source Files

1. [`TeeKum Prototype/Core/Messaging/PacketRouter.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/PacketRouter.swift) (324 lines) — Authoritative `@MainActor` coordinator demuxing decrypted wire datagrams into domain ViewModels.
2. [`TeeKum Prototype/Core/Messaging/PriorityOutboxQueue.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/PriorityOutboxQueue.swift) (299 lines) — 4-lane priority scheduler with GPS ping coalescing and stranger ring buffers.
3. [`TeeKum Prototype/Core/Messaging/InitialsCodec.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/InitialsCodec.swift) (118 lines) — Base-27 compression engine packing 3-letter initials into 2 bytes.
4. [`TeeKum Prototype/Core/Messaging/PacketCodec.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/PacketCodec.swift) (150 lines) — Central codec registry and serialization error definitions.

---

# 1. Authoritative Demultiplexer: `PacketRouter.swift`

Running strictly on the `@MainActor`, `PacketRouter` coordinates inbound wire datagrams arriving from physical AWDL radio links:

```swift
@MainActor
public final class PacketRouter {
    private let cryptoService: CryptoServiceProvider
    private let peerTransport: PeerTransportService
    private let relayPolicyManager: RelayPolicyManager
    private let routeDiscoveryService: RouteDiscoveryService
    private let chatMessageEngine: ChatMessageEngine
    private let seenPacketCache: SeenPacketCache
    
    private weak var sessionViewModel: GroupSessionViewModel?
    private weak var sosViewModel: SOSViewModel?
    private weak var meetingPointViewModel: MeetingPointViewModel?
    private weak var chatViewModel: ChatViewModel?
```

---

## 1.1 Inbound Routing & Demux Pipeline

```swift
    public func routeInboundPacket(_ inbound: InboundPacket, for session: GroupSession) async {
        let raw = inbound.rawPacket
        let envelope = raw.envelope
        
        // Step 1: Stranger Packet Check (Communal Mesh Relay)
        guard envelope.sessionId == session.sessionId else {
            await handleStrangerRelayPacket(inbound)
            return
        }
        
        // Step 2: Immediate ACK Processing
        if envelope.type == .ack {
            await sosViewModel?.processInboundPacket(inbound)
            _ = await chatMessageEngine.processDeliveryACK(rawPacket: raw, fromPeerId: inbound.sourcePeerId)
            await relayMeshPacketIfNeeded(inbound, for: session)
            return
        }
        
        // Step 3: Trigger High-Priority SOS Siren HUD
        if envelope.type == .sos {
            await sosViewModel?.processInboundPacket(inbound)
        }
        
        // Step 4: Authenticated ChaCha20-Poly1305 Decryption
        let key = SymmetricKey(data: session.symmetricKeyData)
        guard let decrypted = try? await cryptoService.open(
            ciphertext: raw.ciphertext,
            envelope: envelope,
            authTag: raw.authTag,
            using: key
        ) else {
            // Decryption failure fallback: If packet is an emergency SOS, STILL RELAY IT
            if envelope.type == .sos {
                await relayMeshPacketIfNeeded(inbound, for: session)
            }
            return
        }
```

### The SOS Decryption Fallback Guarantee
* Lines 98–101 embody a non-negotiable life-safety rule:
  * If an incoming packet is an emergency SOS alert (`envelope.type == .sos`) but local decryption fails (for example, if an attendee from a different camping group triggers distress), **our phone STILL broadcasts the packet forward across the mesh**.
  * Even if our device cannot decrypt the payload, re-broadcasting ensures the emergency reaches attendees who *do* possess that group's symmetric key.

---

## 1.2 Multi-Hop Group Relay: `relayMeshPacketIfNeeded`

```swift
    public func relayMeshPacketIfNeeded(_ inbound: InboundPacket, for session: GroupSession) async {
        let envelope = inbound.rawPacket.envelope
        guard envelope.hopCount < envelope.hopLimit else { return }
        
        // Prevent forwarding packets originating locally on this device
        if envelope.memberSlot == session.memberSlot {
            return
        }
        
        // Prevent routing loops: deduplicate via 1,024-entry LRU cache
        let packetKey = PacketKey(wirePacket: inbound.rawPacket)
        let isDuplicate = await seenPacketCache.isDuplicateAndRecord(packetKey)
        if isDuplicate {
            return
        }
        
        var relayedEnvelope = envelope
        relayedEnvelope.hopCount &+= 1
        
        let relayedWirePacket = RawWirePacket(
            envelope: relayedEnvelope,
            ciphertext: inbound.rawPacket.ciphertext,
            authTag: inbound.rawPacket.authTag
        )
        
        do {
            let wireData = try relayedWirePacket.toWireData()
            try await peerTransport.broadcastPacket(wireData)
        } catch {
            print("[PacketRouter] Failed to relay mesh packet: \(error)")
        }
    }
```

### Routing Loop Defense
* **Loop Filter 1**: Checks `envelope.memberSlot == session.memberSlot`. If the packet originated from our own device and bounced back over the mesh, it is immediately discarded.
* **Loop Filter 2**: Records the 7-byte canonical `PacketKey` in `SeenPacketCache`. If the packet was already processed within the 5-minute sliding window, it is suppressed.
* **Safe Wire Mutation**: Only `hopCount` is incremented. The 30-byte ciphertext and 16-byte Poly1305 MAC tag remain bit-for-bit identical.

---

# 2. 4-Lane Priority Outbox: `PriorityOutboxQueue.swift`

Low-bandwidth peer-to-peer radio transports suffer from severe head-of-line blocking if managed with standard FIFO queues. `PriorityOutboxQueue` organizes transmissions into four strict priority tiers:

```
[Tier 1: Urgent Lane] (FIFO, Capacity: 16)
  └─ Emergency SOS Alerts, Delivery ACKs, Meeting Updates
        │ (High Priority: Always drained first)
        ▼
[Tier 2: Local Chat Lane] (FIFO, Capacity: 16)
  └─ Outgoing P2P Text Messages
        │ (Medium Priority: Drained second)
        ▼
[Tier 3: Normal Coalesced Lane] (Keyed Map: DestPeerID -> OutboxItem)
  └─ Periodic Location Pings (NEW FIX OVERWRITES OLD FIX)
        │ (Low Priority: Drained third)
        ▼
[Tier 4: Stranger Relay Lane] (Ring Buffer FIFO, Capacity: 32)
  └─ Opaque Stranger Packets (DROP-HEAD ON OVERFLOW)
```

---

## 2.1 GPS Coalescing: Eliminating Obsolete Packets

```swift
        if packetType == .locationPing {
            let destKey = destinationPeerId ?? ""
            if normalCoalescedLane[destKey] != nil {
                obsoletePingsCoalesced += 1 // Discard older GPS fix
            }
            normalCoalescedLane[destKey] = item
            return item
        }
```

### Field Performance Rationale
* Suppose an iPhone is moving through a dense crowd and the radio is busy.
* At $t = 0\text{s}$, a GPS fix at $(x_1, y_1)$ is queued.
* At $t = 4\text{s}$, the radio is still waiting, and a fresh GPS fix at $(x_2, y_2)$ arrives.
* Instead of buffering both packets, `PriorityOutboxQueue` **overwrites** $(x_1, y_1)$ with $(x_2, y_2)$.
* Saves 50% radio airtime and guarantees that when transmission succeeds, friends receive the freshest spatial position.

---

## 2.2 Priority Dequeueing Logic

```swift
    public func dequeueNextItem() -> OutboxItem? {
        // Priority 1: Urgent SOS & ACKs
        if !urgentLane.isEmpty {
            return urgentLane.removeFirst()
        }
        // Priority 2: Local Group Chat
        if !localChatLane.isEmpty {
            return localChatLane.removeFirst()
        }
        // Priority 3: Fresh Location Pings
        if let key = normalCoalescedLane.keys.first, let item = normalCoalescedLane.removeValue(forKey: key) {
            return item
        }
        // Priority 4: Stranger Blind Relaying
        if !strangerRelayLane.isEmpty {
            return strangerRelayLane.removeFirst()
        }
        return nil
    }
```

* An emergency SOS packet is guaranteed to be dequeued and transmitted before any chat message or location ping, regardless of how many pings are queued.

---

# 3. Base-27 Radix Initials Compression: `InitialsCodec.swift`

Standard UTF-8 strings require 1 byte per ASCII character (3 bytes for initials like `"DNA"`). In a tightly constrained 30-byte payload budget, saving even 1 byte expands text capacity by 5%.

```swift
nonisolated public enum InitialsCodec {
    public static func encode(_ initials: String) -> [UInt8]? {
        let letters = Array(initials.uppercased().utf8)
        guard letters.count >= 1 && letters.count <= 3,
              letters.allSatisfy({ $0 >= 65 && $0 <= 90 }) else {
            return nil
        }
        
        let a = Int(letters[0]) - 64
        let b = letters.count >= 2 ? (Int(letters[1]) - 64) : 0
        let c = letters.count >= 3 ? (Int(letters[2]) - 64) : 0
        
        // Base-27 positional formula: (a * 729) + (b * 27) + c
        let number = (a * 729) + (b * 27) + c
        
        let highByte = UInt8(number / 256)
        let lowByte = UInt8(number % 256)
        return [highByte, lowByte]
    }
```

### Mathematical Derivation
* Consider a radix system of base $R = 27$:
  * $0 = \text{Empty position}$
  * $1 = \text{'A'}, 2 = \text{'B'}, \dots, 26 = \text{'Z'}$
* For 1 to 3 letters:
  $$\text{Value} = a \times 27^2 + b \times 27^1 + c \times 27^0 = a \times 729 + b \times 27 + c$$
* Maximum possible value for `"ZZZ"`:
  $$\text{Value} = 26 \times 729 + 26 \times 27 + 26 = 18,954 + 702 + 26 = 19,682$$
* Because $19,682 < 65,536$ ($2^{16}$), **any combination of 1 to 3 uppercase letters fits into exactly 2 bytes (`UInt16`)**.

```swift
    public static func decode(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 2 else { return nil }
        let number = (Int(bytes[0]) * 256) + Int(bytes[1])
        guard number >= 729 && number <= 19682 else { return nil }
        
        let a = number / 729
        let b = (number % 729) / 27
        let c = number % 27
        
        guard a >= 1 && a <= 26, b <= 26, c <= 26 else { return nil }
        guard !(b == 0 && c > 0) else { return nil } // No trailing letter without middle letter
        
        var letterBytes: [UInt8] = [UInt8(a + 64)]
        if b > 0 { letterBytes.append(UInt8(b + 64)) }
        if c > 0 { letterBytes.append(UInt8(c + 64)) }
        return String(bytes: letterBytes, encoding: .utf8)
    }
```

* Decoding reverses the positional division, extracting the original ASCII letters without precision loss.

---

Proceed to **[Volume 06: Location & Background Services](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/06_location_and_live_activity.md)**.
