# TeeKum Code Handbook — Volume 02: Wire Protocol & Domain Models

This volume breaks down the low-level binary data structures, fixed 56-byte wire packets, sequence number bit partitions, 30-byte payload schemas, cryptographic inputs, and high-level domain entities of TeeKum.

---

## 📑 Included Files

* **Wire & Packaging**:
  * [`TeeKum Prototype/Core/Messaging/Models/RawWirePacket.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Models/RawWirePacket.swift)
  * [`TeeKum Prototype/Core/Messaging/Models/CleartextEnvelope.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Models/CleartextEnvelope.swift)
  * [`TeeKum Prototype/Core/Messaging/Models/PacketConstants.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Models/PacketConstants.swift)
* **Encrypted 30-Byte Payloads**:
  * [`TeeKum Prototype/Core/Messaging/Payloads/LocationPingPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/LocationPingPayload.swift)
  * [`TeeKum Prototype/Core/Messaging/Payloads/ChatMessagePayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/ChatMessagePayload.swift)
  * [`TeeKum Prototype/Core/Messaging/Payloads/SOSPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/SOSPayload.swift)
  * [`TeeKum Prototype/Core/Messaging/Payloads/ACKPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/ACKPayload.swift)
  * [`TeeKum Prototype/Core/Messaging/Payloads/RouteReqPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/RouteReqPayload.swift)
  * [`TeeKum Prototype/Core/Messaging/Payloads/RouteRespPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/RouteRespPayload.swift)
  * [`TeeKum Prototype/Core/Messaging/Payloads/MeetingUpdatePayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/MeetingUpdatePayload.swift)
* **Domain Models & Enums**:
  * [`TeeKum Prototype/Core/Models/GroupSession.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/GroupSession.swift)
  * [`TeeKum Prototype/Core/Models/Member.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Member.swift)
  * [`TeeKum Prototype/Core/Models/ChatMessage.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/ChatMessage.swift)
  * [`TeeKum Prototype/Core/Models/MeetingPoint.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/MeetingPoint.swift)
  * [`TeeKum Prototype/Core/Models/TeeKumConfiguration.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/TeeKumConfiguration.swift)
  * [`TeeKum Prototype/Core/Models/Enums/MemberColor.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/MemberColor.swift)
  * [`TeeKum Prototype/Core/Models/Enums/RouteChoice.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/RouteChoice.swift)

---

# 1. Wire Datagram Architecture

Every transmission in TeeKum is strictly **56 bytes**:

```
+-------------------------------------------------------------------------+
|                  56-BYTE FIXED TEEKUM WIRE DATAGRAM                     |
+--------------------------+------------------------------+---------------+
| Cleartext Envelope (10B) | Encrypted Payload (30B)      | Auth Tag (16B)|
| Readable by all relays   | Sealed with AES-GCM-256      | Poly1305 / GCM|
+--------------------------+------------------------------+---------------+
 0                        9 10                          39 40           55
```

---

# 2. `RawWirePacket.swift`

```swift
nonisolated public struct RawWirePacket: Equatable, Sendable {
    public var envelope: CleartextEnvelope
    public var ciphertext: Data
    public var authTag: Data
    
    public init(envelope: CleartextEnvelope, ciphertext: Data, authTag: Data) {
        self.envelope = envelope
        self.ciphertext = ciphertext
        self.authTag = authTag
    }
    
    /// Combines envelope (10B), ciphertext (30B), and auth tag (16B) into exactly 56 bytes.
    public func toWireData() throws -> Data {
        let envData = envelope.serialize()
        guard envData.count == PacketConstants.cleartextEnvelopeSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.cleartextEnvelopeSize, actual: envData.count)
        }
        guard ciphertext.count == PacketConstants.encryptedPayloadSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.encryptedPayloadSize, actual: ciphertext.count)
        }
        guard authTag.count == PacketConstants.authTagSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.authTagSize, actual: authTag.count)
        }
        
        var packet = Data(capacity: PacketConstants.wirePacketSize)
        packet.append(envData)
        packet.append(ciphertext)
        packet.append(authTag)
        return packet
    }
    
    /// Parses a 56-byte binary datagram from the network.
    public static func fromWireData(_ data: Data) throws -> RawWirePacket {
        guard data.count == PacketConstants.wirePacketSize else {
            throw PacketCodecError.invalidPacketSize(expected: PacketConstants.wirePacketSize, actual: data.count)
        }
        
        let envData = data.subdata(in: 0..<10)
        let envelope = try CleartextEnvelope.deserialize(from: envData)
        let ciphertext = data.subdata(in: 10..<40)
        let authTag = data.subdata(in: 40..<56)
        
        return RawWirePacket(envelope: envelope, ciphertext: ciphertext, authTag: authTag)
    }
}
```

### Line-by-Line Breakdown
* `nonisolated public struct RawWirePacket: Equatable, Sendable`: Explicitly marked `nonisolated` so it can be passed across any actor boundary without triggering isolation warnings. It is a value type (`struct`) with value semantics.
* `toWireData()`: Serializes the 3 components. Pre-allocates buffer capacity (`Data(capacity: 56)`) to eliminate dynamic heap reallocations.
* `fromWireData(_ data: Data)`: Slices the received byte buffer using non-copying subdata ranges (`0..<10`, `10..<40`, `40..<56`).
* `guard data.count == PacketConstants.wirePacketSize`: Rejects any malformed, truncated, or fragmented packet at the earliest possible stage before doing any cryptographic parsing.

---

# 3. `CleartextEnvelope.swift`

## 3.1 Structure & Bitfield Layout

```swift
public struct CleartextEnvelope: Equatable, Sendable {
    public var version: UInt8
    public var type: PacketType
    public var hopLimit: UInt8
    public var hopCount: UInt8
    public var sessionId: UInt16
    public var sequenceNumber: UInt32
    
    public var memberSlot: UInt8 {
        CleartextEnvelope.memberSlot(from: sequenceNumber)
    }
    
    public var counter: UInt32 {
        CleartextEnvelope.counter(from: sequenceNumber)
    }
```

### Envelope Byte Map (10 Bytes)
```
 Byte 0: [ Version (4 bits) | Packet Type (4 bits) ]
 Byte 1: [ Hop Limit (UInt8: 1..15)                ]
 Byte 2: [ Hop Count (UInt8: 0..hopLimit)          ]
 Byte 3..5: [ Session ID (24-bit Big-Endian UInt)  ]
 Byte 6..9: [ Sequence Number (32-bit Big-Endian)  ]
            └─ Byte 6: Member Slot (UInt8: 0..255)
            └─ Bytes 7..9: Monotonic Counter (24-bit: 0..16,777,215)
```

---

## 3.2 Sequence Number Partitioning & Nonce Collision Defense

```swift
    public static func makeSequenceNumber(memberSlot: UInt8, counter: UInt32) -> UInt32 {
        (UInt32(memberSlot) << 24) | (counter & 0x00FFFFFF)
    }
    
    public static func memberSlot(from sequenceNumber: UInt32) -> UInt8 {
        UInt8((sequenceNumber >> 24) & 0xFF)
    }
    
    public static func counter(from sequenceNumber: UInt32) -> UInt32 {
        sequenceNumber & 0x00FFFFFF
    }
```

### Cryptographic Significance
* In AES-GCM, encrypting two different messages with the same key and same nonce causes **catastrophic key recovery** (the polynomial authenticator collapses).
* Since all festival friends share the same symmetric group key, two devices must NEVER emit the same nonce.
* By bit-shifting `memberSlot` into the high 8 bits `(memberSlot << 24)`, Member A (`slot 1`) emits nonces starting with `0x01......`, while Member B (`slot 2`) emits nonces starting with `0x02......`. Nonce spaces can never collide.

---

## 3.3 Authenticated Associated Data (AAD) & Hop Masking

```swift
    public func authenticatedAssociatedData() -> Data {
        var aad = Data(capacity: PacketConstants.cleartextEnvelopeSize)
        
        // Byte 0: versionAndType
        let byte0 = ((version & 0x0F) << 4) | (type.rawValue & 0x0F)
        aad.append(byte0)
        
        // Byte 1: hopLimit
        aad.append(hopLimit)
        
        // Byte 2: hopCount masked to 0x00
        aad.append(0x00)
        
        // Bytes 3..5: sessionId (3 bytes)
        let sid3Bytes: [UInt8] = [
            UInt8((sessionId >> 16) & 0xFF),
            UInt8((sessionId >> 8) & 0xFF),
            UInt8(sessionId & 0xFF)
        ]
        aad.append(contentsOf: sid3Bytes)
        
        // Bytes 6..9: sequenceNumber (4 bytes)
        var seqBE = sequenceNumber.bigEndian
        aad.append(Data(bytes: &seqBE, count: 4))
        
        return aad
    }
```

### Why Mask `hopCount` to `0x00` in AAD?
* When intermediate stranger devices relay a packet across the festival, they increment `hopCount` by 1.
* If `hopCount` were included directly in the AEAD authentication calculation, the recipient's Poly1305 authentication tag check would fail on the very first relay hop!
* **Solution**: Byte 2 is masked to `0x00` during AAD calculation on both sender and receiver. The remaining fields (`version`, `type`, `hopLimit`, `sessionId`, `sequenceNumber`) remain cryptographically bound and tamper-proof.

---

## 3.4 Nonce Construction (96-bit / 12 Bytes)

```swift
    public func constructNonce() -> Data {
        var nonceData = Data(capacity: PacketConstants.nonceSize)
        
        let sid3Bytes: [UInt8] = [
            UInt8((sessionId >> 16) & 0xFF),
            UInt8((sessionId >> 8) & 0xFF),
            UInt8(sessionId & 0xFF)
        ]
        nonceData.append(contentsOf: sid3Bytes)
        
        var seqBE = sequenceNumber.bigEndian
        nonceData.append(Data(bytes: &seqBE, count: 4))
        
        let byte0 = ((version & 0x0F) << 4) | (type.rawValue & 0x0F)
        nonceData.append(byte0)
        
        nonceData.append(contentsOf: PacketConstants.protocolDomainTag)
        return nonceData
    }
```

### Nonce Memory Layout
```
 Bytes 0..2:  [ Session ID (3 bytes)                               ]
 Bytes 3..6:  [ Sequence Number: MemberSlot (1B) + Counter (3B)    ]
 Byte 7:      [ Version & Type (1 byte)                            ]
 Bytes 8..11: [ Protocol Domain Tag: 'T', 'K', 'M', '3' (4 bytes)  ]
```

---

# 4. Encrypted 30-Byte Payloads

## 4.1 `LocationPingPayload.swift` (Type `0x01`)

```swift
public struct LocationPingPayload: Equatable, Sendable {
    public var coordinate: CLLocationCoordinate2D
    public var timestamp: Date
    public var accuracy: UInt8
    public var senderInitials: String // 1..3 uppercase characters A-Z
    public var batteryLevel: UInt8    // 0...100
    public var heading: UInt8         // 0...255 representing 0..<360 degrees
    public var colorCode: UInt8       // 0x00...0x08 MemberColor code
```

### Binary Packing Table
| Byte Offset | Field | Type | Scale / Format | Resolution |
| :---: | :--- | :--- | :--- | :--- |
| **0..3** | `latitudeRaw` | `Int32` (BE) | `lat * 10,000,000` | ~11 mm worldwide |
| **4..7** | `longitudeRaw` | `Int32` (BE) | `lon * 10,000,000` | ~11 mm worldwide |
| **8..11** | `timestamp` | `UInt32` (BE) | Epoch seconds | 1 second |
| **12** | `accuracy` | `UInt8` | Raw meters | 0 to 255 meters |
| **13..14** | `senderInitials`| 2 × `UInt8` | Base-27 compressed | 3 letters in 16 bits |
| **15** | `batteryLevel` | `UInt8` | Percentage | 0 to 100% |
| **16** | `heading` | `UInt8` | `deg * 255 / 360` | ~1.41 degrees |
| **17** | `colorCode` | `UInt8` | `MemberColor.rawValue` | Palette index 0..8 |
| **18..29** | `reserved` | 12 × `UInt8` | Zero padding | Reserved for elevation |

---

## 4.2 `ChatMessagePayload.swift` (Type `0x07`)

```swift
public struct ChatMessagePayload: Equatable, Sendable {
    public var messageId: UInt16
    public var senderInitials: String
    public var recipientInitials: String // "ALL" for broadcast, or specific initials
    public var text: String              // Max 25 UTF-8 bytes
```

### Binary Packing Table
| Byte Offset | Field | Type | Purpose |
| :---: | :--- | :--- | :--- |
| **0..1** | `messageId` | `UInt16` (BE) | Unique ID for end-to-end delivery ACK correlation |
| **2..3** | `senderInitials` | 2 × `UInt8` | Base-27 compressed sender initials |
| **4..5** | `recipientInitials`| 2 × `UInt8` | Base-27 compressed destination (or `ALL`) |
| **6..30** | `textData` | 25 × `UInt8` | UTF-8 encoded text characters |

---

## 4.3 `SOSPayload.swift` (Type `0x02`)

```swift
public struct SOSPayload: Equatable, Sendable {
    public var flags: UInt8             // Bit 0: Active, Bit 1: Medical, Bit 2: Panic
    public var coordinate: CLLocationCoordinate2D
    public var timestamp: Date
    public var senderInitials: String
    public var batteryLevel: UInt8
    public var ackBitmask: UInt32       // Confirmed peer acknowledgements
```

### Binary Packing Mechanics
* `ackBitmask`: Allows the SOS victim's phone to broadcast which peers have confirmed receipt, providing visual peace-of-mind feedback directly on everyone's HUD.

---

## 4.4 `ACKPayload.swift` (Type `0x06`)

```swift
public struct ACKPayload: Equatable, Sendable {
    public var targetSequenceNumber: UInt32 // Original sequence being confirmed
    public var ackSenderInitials: String     // Who confirmed it
    public var deliveryStatus: UInt8         // 0 = Received, 1 = Displayed
```

* Direct return receipt sent back along the reverse mesh path to guarantee message delivery without a cellular network.

---

# 5. Domain Entities

## 5.1 `GroupSession.swift` & Serverless Invite Security

```swift
public struct GroupSession: Identifiable, Equatable, Sendable, Codable {
    public let sessionId: UInt16
    public let sessionName: String
    public let symmetricKeyData: Data
    public var localInitials: String
    public var localColorCode: UInt8
    public let isHost: Bool
    public let createdAt: Date
```

### The URL Fragment Security Guarantee
```swift
    public func inviteURL() -> URL {
        var components = URLComponents()
        components.scheme = "teekum"
        components.host = "join"
        components.queryItems = [
            URLQueryItem(name: "id", value: String(format: "%04X", sessionId)),
            URLQueryItem(name: "name", value: sessionName)
        ]
        // 256-bit symmetric key is stored in the fragment (#)
        components.fragment = symmetricKeyData.base64EncodedString()
        return components.url!
    }
```

* **Why Fragment (`#`)?** RFC 3986 specifies that the fragment component of a URI is **client-side only**. Web browsers and proxies NEVER transmit the fragment to the web server in HTTP requests. If a user texts their join link, no intermediary web server can intercept the AES-256 group decryption key.

---

## 5.2 `MemberColor.swift` & The DJB2 Neon Hash

```swift
public enum MemberColor: UInt8, CaseIterable, Identifiable, Sendable {
    case unset          = 0x00
    case neonPink       = 0x01
    case electricPurple = 0x02
    case skyBlue        = 0x03
    case limeMint       = 0x04
    case brightTeal     = 0x05
    case neonAmber      = 0x06
    case coralPeach     = 0x07
    case lavender       = 0x08
    
    public static func deterministicColor(for initials: String) -> MemberColor {
        let clean = initials.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return .skyBlue }
        
        let hash = clean.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) }
        let index = abs(hash) % 8 // 0...7
        let raw = UInt8(index + 1) // 1...8
        return MemberColor(rawValue: raw) ?? .skyBlue
    }
}
```

### Algorithm Highlights
* **The Red Exclusion Rule**: Pure Red is strictly banned from user selection. Red is reserved exclusively for the SOS siren system to eliminate false alarms.
* **DJB2 Hash**: Uses Daniel J. Bernstein's prime constant `5381` and bitwise multiplier `($0 << 5) &+ $0` (equivalent to `hash * 33 + char`) with Swift's wrapping addition operator `&+` to deterministically assign the same neon color to a friend across every phone.

---

Proceed to **[Volume 03: Transport & Cryptography Engines](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/03_transport_and_security.md)**.
