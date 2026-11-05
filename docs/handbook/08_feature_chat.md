# TeeKum Code Handbook — Volume 08: Feature — Offline P2P Chat (Definitive Deep-Dive)

This volume provides an exhaustive, method-by-method architectural deep-dive into the offline peer-to-peer chat engine, UTF-8 byte metering, multi-hop mesh forwarding, per-recipient delivery confirmation receipts, and ephemeral in-memory privacy controls in TeeKum.

---

## 📑 Included Source Files

1. [`TeeKum Prototype/Features/Chat/Services/ChatMessageEngine.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Services/ChatMessageEngine.swift) (776 lines) — Actor-isolated message engine managing outbox queueing, retries, ACK state machines, and stranger relaying.
2. [`TeeKum Prototype/Features/Chat/Services/ChatMessagingService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Services/ChatMessagingService.swift) (70 lines) — Interface protocol defining chat contracts for unit testing.
3. [`TeeKum Prototype/Features/Chat/ViewModels/ChatViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/ViewModels/ChatViewModel.swift) (350 lines) — Presentation ViewModel managing real-time byte calculation, cooldown timers, and message bubbles.
4. [`TeeKum Prototype/Features/Chat/Views/ByteMeterView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Views/ByteMeterView.swift) (57 lines) — Circular progress gauge dynamically color-coding UTF-8 byte consumption.
5. [`TeeKum Prototype/Features/Chat/Views/ChatMessageBubbleView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Views/ChatMessageBubbleView.swift) (220 lines) — Message bubble rendering with delivery status icons and tap-to-inspect breakdowns.
6. [`TeeKum Prototype/Features/Chat/Views/ChatSheetView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Views/ChatSheetView.swift) (250 lines) — Modal chat presentation bottom sheet.
7. [`TeeKum Prototype/Features/Chat/Views/PresetChipsView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Views/PresetChipsView.swift) (84 lines) — 1-tap quick text presets for festival communication.

---

# 1. Ephemeral Privacy & Wire Constraints

Festival group chat in TeeKum operates under strict resource and privacy bounds:
* **The 20-Byte Wire Allocation**: Standard chat applications transmit kilobytes of JSON metadata. In TeeKum, the text is packed into **strictly 20 UTF-8 bytes** within the 30-byte payload budget.
* **Strict Zero-Disk Persistence**: Plaintext messages and chat histories are stored **strictly in RAM memory buffers** (capped at 50 messages). No messages are ever written to iOS disk storage, CoreData, or Keychain. Quitting the app or leaving the session purges 100% of chat history.
* **Preserving SOS Priority**: Local chat traffic operates in Tier 3 FIFO, strictly behind Tier 1 Emergency SOS.

```
+-------------------------------------------------------------------------------+
|             30-BYTE ENCRYPTED CHAT MESSAGE PAYLOAD (Type: 0x07)               |
+-------------------+------------------+---------------+----------------+-------+
| SenderInitials(2B)| Timestamp(4B BE) | TextLength(1B)| TextBuffer(20B)|Pad(3B)|
+-------------------+------------------+---------------+----------------+-------+
```

---

# 2. `ChatMessageEngine.swift`: The 776-Line Chat Actor

```swift
public actor ChatMessageEngine {
    private let transport: MeshTransport
    private let cryptoService: CryptoServiceProvider
    private let routingTable: RoutingTableManaging?
    private let neighborTable: NeighborManaging?
    private let rateLimiter: ForwardingBudgetManaging?
    private let seenPacketCache: SeenPacketCache
    private let clock: MeshClock
    
    public let maxHistoryCount: Int = 50
    private var inMemoryMessages: [ChatMessage] = []
    private var inFlightMessages: [UInt32: InFlightMessage] = [:]
    private var monotonicCounter: UInt32 = 1
```

---

## 2.1 The 5-State Honest Delivery State Machine

TeeKum distinguishes between a stranger relay forwarding a message and the destination friend actually receiving it:

```
[locallyAccepted]
       │
       ▼ (Sealed and submitted to radio outbox)
[forwardedToNextHop]
       │
       ▼ (Intermediary relay confirms forwarding; NOT friend)
[relayedByMesh]
       │
       ▼ (Destination friend device decrypted and issued ACK)
[deliveredToRecipient]
       │
       ▼ (Timeout after 4.5s without ACK response)
[deliveryTimedOut]
```

```swift
    public func processDeliveryACK(rawPacket: RawWirePacket, fromPeerId: String) async -> Bool {
        guard let ack = try? ACKPayload.deserialize(from: decrypted) else { return false }
        
        if ack.ackStatus == .delivered {
            // 0x01: End-to-End Final Recipient Delivery Confirmation
            m.recipientStates[ack.ackSenderInitials] = .delivered(at: clock.now())
        } else if ack.ackStatus == .relayed {
            // 0x02: Intermediary Stranger Relay Acknowledgement
            // NOTE: Never mark as .delivered; mark as .relayed
            m.recipientStates[ack.ackSenderInitials] = .relayed(at: clock.now())
        }
    }
```

### The Honest UI Guarantee
* If Bob's phone receives a message, it emits an `ACKPayload` with `ackStatus = 0x01` (`.delivered`).
* If an intermediary stranger relays the message, it emits an `ACKPayload` with `ackStatus = 0x02` (`.relayed`).
* TeeKum **never presents an intermediary relay ACK as final friend delivery**. The sender's UI displays a cyan relay icon, only changing to double green checkmarks when the intended friend's device confirms receipt.

---

## 2.2 Transmitting a Message: `sendMessage`

```swift
    public func sendMessage(_ text: String) async throws -> ChatMessage {
        guard currentBatteryLevel >= 0.20 && !isLowPowerMode && !isSurvivalMode else {
            throw ChatEngineError.survivalModeRestricted
        }
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChatEngineError.emptyMessage }
        guard trimmed.utf8.count <= ChatMessagePayload.maxTextBytes else {
            throw ChatEngineError.messageTooLong(trimmed.utf8.count)
        }
        
        // Cooldown enforcement: 3.0 seconds between messages
        let now = clock.now()
        guard now.timeIntervalSince(lastSentTimestamp) >= timingConfig.chatCooldownInterval else {
            throw ChatEngineError.cooldownActive
        }
```

### Safety & Resource Guards
1. **Battery Guard**: If the device battery is $<20\%$ or Low Power Mode is enabled, chat transmission throws `ChatEngineError.survivalModeRestricted`, preserving battery for SOS.
2. **Byte Limit**: Enforces `trimmed.utf8.count <= 20`.
3. **Spam Cooldown**: Enforces a 3.0-second delay between outgoing messages to prevent radio congestion in large groups.

---

## 2.3 Stranger Relay Pipeline

```swift
        // 2. Stranger Packet Relaying (Zero-Knowledge Blind Relaying)
        if let session = activeSession, envelope.sessionId != session.sessionId {
            guard currentBatteryLevel >= 0.20 && !isLowPowerMode && !isSurvivalMode else {
                return .droppedPolicyDisabled
            }
            
            // Rate limiter check (ordinary relay budget: 2 pkts/sec)
            if let limiter = rateLimiter {
                let permitted = await limiter.consumeOrdinaryToken()
                guard permitted else { return .droppedPolicyDisabled }
            }
            
            // Deduplication suppression
            let packetKey = PacketKey(wirePacket: rawPacket)
            let isDuplicate = await seenPacketCache.isDuplicateAndRecord(packetKey, now: clock.now())
            if isDuplicate {
                return .droppedDuplicate(sequenceNumber: envelope.sequenceNumber)
            }
            
            // Mutate hopCount (+1)
            var mutatedData = wireData
            mutatedData[mutatedData.startIndex + 2] = envelope.hopCount + 1
            
            // Blind forward across mesh (never decrypt or display)
            try await transport.broadcastFrame(mutatedData)
            return .relayedBlindly
        }
```

* Stranger packets are forwarded blindly without decrypting, logging, or exposing content to the UI.

---

# 3. Real-Time Byte Meter: `ByteMeterView.swift`

Because UTF-8 characters have variable length (ASCII = 1 byte, Chinese/Japanese = 3 bytes, Emojis = 4 bytes), checking character count (`text.count`) can cause packet truncation. `ChatViewModel` computes exact UTF-8 byte usage:

```swift
    public var currentByteCount: Int {
        inputText.utf8.count
    }
    
    public var byteUsageRatio: Double {
        min(1.0, Double(currentByteCount) / Double(Self.maxBytes)) // Max 20 bytes
    }
    
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

```swift
    // Animated circular progress gauge
    Circle()
        .trim(from: 0.0, to: CGFloat(viewModel.byteUsageRatio))
        .stroke(viewModel.byteMeterColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .frame(width: 16, height: 16)
        .animation(.easeOut(duration: 0.15), value: viewModel.byteUsageRatio)
```

* Turns Neon Cyan during normal typing, switches to Neon Amber at 16 bytes, and flashes Neon Red at 20 bytes, preventing failed transmissions.

---

# 4. Quick Presets: `PresetChipsView.swift`

In loud, crowded music festivals, typing on a small keyboard is slow. TeeKum provides 1-tap preset chips pre-measured to fit within wire byte budgets:

```swift
    public static let presetBeerLine = "Beer line"       // 9 bytes
    public static let presetAtMainStage = "At Main Stage" // 13 bytes
    public static let presetRestroom = "Restroom"         // 8 bytes
    public static let presetWhereAreYou = "Where are you?"// 14 bytes
    public static let presetOnMyWay = "On my way"         // 9 bytes
    public static let presetLost = "Lost"                 // 4 bytes
```

* Tapping a chip populates the input field and allows 1-tap broadcast.

---

Proceed to **[Volume 09: Feature — Main Map & Spatial Awareness](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/09_feature_map.md)**.
