# TeeKum Code Handbook — Volume 08: Feature — Offline P2P Chat

This volume details the offline peer-to-peer festival chat engine, byte-metered text input, multi-hop mesh forwarding, per-recipient delivery confirmation receipts, and ephemeral in-memory privacy controls in TeeKum.

---

## 📑 Included Files

1. [`TeeKum Prototype/Features/Chat/Services/ChatMessageEngine.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Services/ChatMessageEngine.swift) — Actor-isolated message engine managing outbox queueing, retries, and ACK tracking.
2. [`TeeKum Prototype/Features/Chat/Services/ChatMessagingService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Services/ChatMessagingService.swift) — Interface defining chat service contracts for testing.
3. [`TeeKum Prototype/Features/Chat/ViewModels/ChatViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/ViewModels/ChatViewModel.swift) — Presentation ViewModel managing text input, byte limits, cooldowns, and bubble lists.
4. [`TeeKum Prototype/Features/Chat/Views/ByteMeterView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Views/ByteMeterView.swift) — Circular progress meter dynamically color-coding UTF-8 byte usage.
5. [`TeeKum Prototype/Features/Chat/Views/ChatMessageBubbleView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Views/ChatMessageBubbleView.swift) — Left/right message bubbles displaying honest delivery status checks.
6. [`TeeKum Prototype/Features/Chat/Views/ChatSheetView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Views/ChatSheetView.swift) — Main chat presentation modal bottom sheet.
7. [`TeeKum Prototype/Features/Chat/Views/PresetChipsView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Views/PresetChipsView.swift) — 1-tap quick chips for common festival messages.

---

# 1. Festival Mesh Chat Architecture

Standard messaging applications rely on cloud servers and large payload sizes. In TeeKum:
* **Payload Constraint**: The entire chat message must fit in **25 bytes** inside the 30-byte payload budget (2 bytes message ID, 2 bytes sender initials, 2 bytes recipient initials, and up to 20 UTF-8 text bytes).
* **Strict Ephemeral Privacy**: Messages are stored **strictly in memory** (max 50 messages). No plaintext or messages are ever written to iOS disk storage or Keychain. Upon leaving the session or quitting the app, the history is completely wiped.
* **Preserving SOS Priority**: Local chat traffic is queued in Tier 3 FIFO behind Tier 1 Emergency SOS, ensuring text messages never delay emergency sirens.

```
+-------------------------------------------------------+
|  30-BYTE ENCRYPTED CHAT PAYLOAD SCHEMA (Type: 0x07)   |
+-----------+---------------+------------------+--------+
| Msg ID(2B)| Sender Init(2B)| Recipient Init(2B)| Text(20B)
+-----------+---------------+------------------+--------+
```

---

# 2. `ChatMessageEngine.swift`: The Core Chat Actor

```swift
public actor ChatMessageEngine {
    private let transport: MeshTransport
    private let cryptoService: CryptoServiceProvider
    private let routingTable: RoutingTableManaging?
    private let neighborTable: NeighborManaging?
    private let rateLimiter: ForwardingBudgetManaging?
    private let seenPacketCache: SeenPacketCache
    
    public let maxHistoryCount: Int = 50
    private var inMemoryMessages: [ChatMessage] = []
    private var lastSentTimestamp: Date = .distantPast
    private var inFlightMessages: [UInt32: InFlightMessage] = [:]
```

---

## 2.1 The 5-State Honest Delivery Progression

TeeKum distinguishes between a stranger relay forwarding a message and the destination friend actually receiving it:

```
[Locally Accepted]
        │
        ▼
[Forwarded to Next Hop] ──► (Dispatched across AWDL radio link)
        │
        ▼
[Relayed by Mesh]       ──► (Intermediary relay confirms forwarding; NOT friend)
        │
        ▼
[Delivered to Friend]   ──► (End recipient decrypted and sent authenticated ACK)
        │
        ▼ (Timeout after 4.5s without response)
[Delivery Timed Out]
```

### Code Implementation
```swift
    public func processDeliveryACK(rawPacket: RawWirePacket, fromPeerId: String) async -> Bool {
        guard let ack = try? ACKPayload.deserialize(from: decrypted) else { return false }
        
        if ack.deliveryStatus == 0x01 {
            // 0x01 = End-to-End Final Recipient Delivery Confirmation
            m.recipientStates[ack.ackSenderInitials] = .delivered(at: clock.now())
        } else if ack.deliveryStatus == 0x02 {
            // 0x02 = Intermediary Stranger Relay Acknowledgement
            // NOTE: Never mark as .delivered; mark as .relayed
            m.recipientStates[ack.ackSenderInitials] = .relayed(at: clock.now())
        }
    }
```

---

## 2.2 Battery Guard & Survival Throttling

```swift
    public func setBatteryLevel(_ level: Float, isLowPowerMode: Bool) {
        self.currentBatteryLevel = level
        self.isLowPowerMode = isLowPowerMode
        self.isSurvivalMode = level < 0.20 || isLowPowerMode
    }
```

* If battery drops below 20%, `isSurvivalMode` becomes true. Outgoing chat is disabled to preserve battery for SOS and emergency location pings.

---

# 3. Dynamic Byte-Meter: `ByteMeterView.swift`

Because UTF-8 characters have variable length (ASCII = 1 byte, emojis = 4 bytes), counting string characters (`text.count`) can cause packet truncation. `ChatViewModel` computes exact UTF-8 byte length:

```swift
    public var currentByteCount: Int {
        inputText.utf8.count
    }
    
    public var byteUsageRatio: Double {
        min(1.0, Double(currentByteCount) / Double(Self.maxBytes)) // Max 20 bytes
    }
```

```swift
    public var byteMeterColor: Color {
        let count = currentByteCount
        if count < 16 {
            return Color(red: 0.0, green: 0.85, blue: 1.0) // Neon Cyan
        } else if count < 20 {
            return Color(red: 1.0, green: 0.84, blue: 0.04) // Neon Amber
        } else {
            return Color(red: 1.0, green: 0.18, blue: 0.45) // Neon Red (Limit)
        }
    }
```

* Provides instant visual feedback in the UI: turns Amber at 16 bytes and Red at 20 bytes, preventing message rejection.

---

# 4. Quick Presets: `PresetChipsView.swift`

In noisy, crowded concert crowds, typing on a virtual keyboard is slow and difficult. TeeKum provides 1-tap preset chips pre-measured to fit within wire byte budgets:

* `"Beer line"` (9 bytes)
* `"At Main Stage"` (13 bytes)
* `"Restroom"` (8 bytes)
* `"Where are you?"` (14 bytes)
* `"On my way"` (9 bytes)
* `"Lost"` (4 bytes)

Tapping a chip immediately populates the input field and allows 1-tap transmission.

---

Proceed to **[Volume 09: Feature — Main Map & Spatial Awareness](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/09_feature_map.md)**.
