# TeeKum Code Handbook — Volume 05: Messaging Pipeline & Codecs

This volume examines the packet routing engine, priority outbox queues, radix-based initials compression, payload demultiplexers, and delivery acknowledgement mechanics in TeeKum.

---

## 📑 Included Files

1. [`TeeKum Prototype/Core/Messaging/PacketRouter.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/PacketRouter.swift) — Authoritative demux coordinator dispatching decrypted wire packets to domain ViewModels and engines.
2. [`TeeKum Prototype/Core/Messaging/PriorityOutboxQueue.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/PriorityOutboxQueue.swift) — Prioritized 4-lane transmission queue with GPS coalescing and stranger ring buffers.
3. [`TeeKum Prototype/Core/Messaging/InitialsCodec.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/InitialsCodec.swift) — Base-27 compression packing 3-character initials into 2 bytes.
4. [`TeeKum Prototype/Core/Messaging/PacketCodec.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/PacketCodec.swift) — Binary payload serialization and deserialization orchestrator.
5. Enums & Models:
   * [`TeeKum Prototype/Core/Messaging/Enums/PacketType.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Enums/PacketType.swift)
   * [`TeeKum Prototype/Core/Messaging/Enums/ACKStatus.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Enums/ACKStatus.swift)
   * [`TeeKum Prototype/Core/Messaging/Enums/SOSType.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Enums/SOSType.swift)

---

# 1. Authoritative Demultiplexer: `PacketRouter.swift`

`PacketRouter` runs on the `@MainActor` to directly update SwiftUI ViewModels as soon as authenticated packets are decrypted:

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
        
        // 1. Stranger Packet Check: Route to Communal Relay if SID does not match
        guard envelope.sessionId == session.sessionId else {
            await handleStrangerRelayPacket(inbound)
            return
        }
        
        // 2. Immediate ACK Processing
        if envelope.type == .ack {
            await sosViewModel?.processInboundPacket(inbound)
            _ = await chatMessageEngine.processDeliveryACK(rawPacket: raw, fromPeerId: inbound.sourcePeerId)
            await relayMeshPacketIfNeeded(inbound, for: session)
            return
        }
        
        // 3. Process SOS Packets through SOSViewModel
        if envelope.type == .sos {
            await sosViewModel?.processInboundPacket(inbound)
        }
        
        // 4. Authenticated AEAD Decryption with Session Symmetric Key
        let key = SymmetricKey(data: session.symmetricKeyData)
        guard let decrypted = try? await cryptoService.open(
            ciphertext: raw.ciphertext,
            envelope: envelope,
            authTag: raw.authTag,
            using: key
        ) else {
            // Decryption failure fallback: If packet is an emergency SOS, still relay multi-hop
            if envelope.type == .sos {
                await relayMeshPacketIfNeeded(inbound, for: session)
            }
            return
        }
```

### Critical Life-Safety Feature: The SOS Decryption Fallback
* Lines 98–101 represent an essential safety guarantee:
  * If an emergency SOS datagram arrives but fails local decryption (for instance, if an attendee from a different festival group triggered an emergency alarm), **the phone STILL forwards the packet across the mesh**.
  * Even if our phone cannot decrypt it, forwarding ensures the SOS reaches peers who *do* possess that group's symmetric key.

---

## 1.2 Type-Specific Dispatchers

```swift
        switch envelope.type {
        case .sos:
            await handleDecryptedSOS(decrypted, inbound: inbound, session: session)
            await relayMeshPacketIfNeeded(inbound, for: session)
            
        case .locationPing:
            handleDecryptedLocationPing(decrypted, inbound: inbound, session: session)
            await relayMeshPacketIfNeeded(inbound, for: session)
            
        case .meetingUpdate:
            handleDecryptedMeetingUpdate(decrypted, session: session)
            await relayMeshPacketIfNeeded(inbound, for: session)
            
        case .routeReq:
            if let wireData = try? inbound.rawPacket.toWireData() {
                _ = try? await routeDiscoveryService.handleInboundRouteReq(
                    wireData: wireData,
                    fromPeerId: inbound.sourcePeerId,
                    session: session
                )
            }
            
        case .chatMessage:
            await handleDecryptedChatMessage(inbound: inbound)
            await relayMeshPacketIfNeeded(inbound, for: session)
            
        default:
            break
        }
```

---

# 2. Base-27 Radix Initials Compression: `InitialsCodec.swift`

Standard UTF-8 strings require 1 byte per ASCII character (3 bytes for initials like `"DNA"`). In a tightly constrained 30-byte payload budget, spending 10% of total payload capacity on sender initials is inefficient.

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
}
```

### Mathematical Proof
* Let alphabet size $R = 27$ ($0 = \text{none}, 1 = \text{'A'}, \dots, 26 = \text{'Z'}$).
* For up to 3 letters:
  $$\text{Value} = a \times 27^2 + b \times 27^1 + c \times 27^0 = a \times 729 + b \times 27 + c$$
* Maximum value for `"ZZZ"`:
  $$26 \times 729 + 26 \times 27 + 26 = 18,954 + 702 + 26 = 19,682$$
* Since $19,682 < 65,536$ ($2^{16}$), **any 1 to 3 letter initials fit into exactly 2 bytes (`UInt16`)**, saving 1 byte on every single radio packet sent across the festival.

---

# 3. 4-Lane Priority Outbox: `PriorityOutboxQueue.swift`

When sending data over a low-bandwidth, contention-prone radio link (AWDL), simple FIFO queues cause **head-of-line blocking**: an urgent SOS alert could get stuck behind 10 periodic location pings.

`PriorityOutboxQueue` solves this using four dedicated lanes:

```
+-------------------------------------------------------------+
|               PRIORITY OUTBOX QUEUE LANES                  |
+-------------------------------------------------------------+
| Lane 1: Urgent Lane (FIFO, Capacity: 16)                    |
|   • Emergency SOS sirens, Delivery ACKs, Meeting Updates   |
+-------------------------------------------------------------+
| Lane 2: Local Chat Lane (FIFO, Capacity: 16)                |
|   • Outgoing P2P text messages                              |
+-------------------------------------------------------------+
| Lane 3: Normal Coalesced Lane (Keyed by destination peer ID)|
|   • Periodic location pings: NEW FIX OVERWRITES OLD FIX     |
+-------------------------------------------------------------+
| Lane 4: Stranger Relay Lane (Ring Buffer, Capacity: 32)     |
|   • Blind stranger relay packets: Drop-head on overflow     |
+-------------------------------------------------------------+
```

---

## 3.1 Location Ping Coalescing

```swift
    public func enqueue(_ item: OutboxItem) -> Bool {
        if item.isUrgent {
            urgentLane.append(item)
            return true
        }
        
        if item.packetType == .locationPing {
            let key = item.destinationPeerId ?? ""
            if normalCoalescedLane[key] != nil {
                obsoletePingsCoalesced += 1 // Discard older fix
            }
            normalCoalescedLane[key] = item
            return true
        }
```

### Performance Impact
* If Device A has queued a location ping with coordinates $(x_1, y_1)$ and the radio is busy, when a new GPS fix arrives $(x_2, y_2)$, the queue **overwrites** the older item.
* The obsolete coordinate is dropped, saving radio bandwidth and ensuring friends always receive the freshest geographic location upon transmission.

---

Proceed to **[Volume 06: Location & Background Services](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/06_location_and_live_activity.md)**.
