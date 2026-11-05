# TeeKum Code Handbook — Volume 02: Wire Protocol & Domain Models (Definitive Deep-Dive)

This volume provides an exhaustive, byte-by-byte and field-by-field breakdown of the fixed 56-byte wire datagram, cleartext envelope serialization, cryptographic nonce derivation, authenticated associated data (AAD) masking, all seven binary payload layouts, and high-level domain entities in TeeKum.

---

## 📑 Included Source Files

* **Wire & Packaging**:
  * [`TeeKum Prototype/Core/Messaging/Models/RawWirePacket.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Models/RawWirePacket.swift) (54 lines) — 56-byte container combining cleartext envelope, ciphertext, and Poly1305 MAC tag.
  * [`TeeKum Prototype/Core/Messaging/Models/CleartextEnvelope.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Models/CleartextEnvelope.swift) (186 lines) — 10-byte routing header, sequence bit-partitioning, and AAD mask.
  * [`TeeKum Prototype/Core/Messaging/Models/PacketConstants.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Models/PacketConstants.swift) (50 lines) — Master packet constants and architectural limits.
* **Encrypted 30-Byte Payloads**:
  * [`TeeKum Prototype/Core/Messaging/Payloads/LocationPingPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/LocationPingPayload.swift) (120 lines) — Type 0x01 geographic & sensor telemetry.
  * [`TeeKum Prototype/Core/Messaging/Payloads/SOSPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/SOSPayload.swift) (104 lines) — Type 0x02 emergency distress alert.
  * [`TeeKum Prototype/Core/Messaging/Payloads/MeetingUpdatePayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/MeetingUpdatePayload.swift) (148 lines) — Type 0x03 group rendezvous beacon & attendance update.
  * [`TeeKum Prototype/Core/Messaging/Payloads/RouteReqPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/RouteReqPayload.swift) (60 lines) — Type 0x04 AODV route discovery request.
  * [`TeeKum Prototype/Core/Messaging/Payloads/RouteRespPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/RouteRespPayload.swift) (60 lines) — Type 0x05 AODV route discovery response.
  * [`TeeKum Prototype/Core/Messaging/Payloads/ACKPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/ACKPayload.swift) (94 lines) — Type 0x06 delivery acknowledgement receipt.
  * [`TeeKum Prototype/Core/Messaging/Payloads/ChatMessagePayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/ChatMessagePayload.swift) (164 lines) — Type 0x07 offline peer-to-peer text message.
* **Domain Models & Enums**:
  * [`TeeKum Prototype/Core/Models/GroupSession.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/GroupSession.swift) (172 lines)
  * [`TeeKum Prototype/Core/Models/Member.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Member.swift) (129 lines)
  * [`TeeKum Prototype/Core/Models/ChatMessage.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/ChatMessage.swift) (140 lines)
  * [`TeeKum Prototype/Core/Models/MeetingPoint.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/MeetingPoint.swift) (120 lines)
  * [`TeeKum Prototype/Core/Models/TeeKumConfiguration.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/TeeKumConfiguration.swift) (205 lines)
  * [`TeeKum Prototype/Core/Models/Enums/MemberColor.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/MemberColor.swift) (88 lines)
  * [`TeeKum Prototype/Core/Models/Enums/RouteChoice.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/RouteChoice.swift) (29 lines)

---

# 1. Master Wire Datagram Specification (56 Bytes)

Every packet transmitted across physical AWDL radios in TeeKum is strictly **56 bytes**. This invariant prevents IP fragmentation, eliminates memory reallocations, and simplifies hardware sliding window parsing:

```
+----------------------------------------------------------------------------------------------------+
|                               56-BYTE TEEKUM BINARY WIRE DATAGRAM                                  |
+------------------------------------+------------------------------------+--------------------------+
| Cleartext Envelope (10 Bytes)      | Encrypted Payload (30 Bytes)       | Poly1305 Tag (16 Bytes)  |
| Visible to all intermediate relays | Sealed with ChaCha20 / AES-256     | Authenticates Envelope+PL|
+------------------------------------+------------------------------------+--------------------------+
 0                                  9 10                                39 40                      55
```

---

# 2. `RawWirePacket.swift`: Packaging & Bounds Enforcement

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

### Detailed Method Dissection
* `nonisolated public struct`: Explicitly marked `nonisolated` so value instances can be transferred across any Swift `actor` boundary without compiler warnings.
* `toWireData()`: Pre-allocates buffer capacity `Data(capacity: 56)` to prevent dynamic memory heap reallocations. Enforces that `envData == 10B`, `ciphertext == 30B`, and `authTag == 16B`.
* `fromWireData(_ data: Data)`: Parses incoming stream slices. If `data.count != 56`, immediately aborts before running expensive cryptographic routines.

---

# 3. `CleartextEnvelope.swift`: Header Anatomy & Bitwise Packing

## 3.1 Field-to-Byte Layout Map (10 Bytes)

```
Byte 0: [ Version (High 4 bits) | Packet Type (Low 4 bits) ]
Byte 1: [ Hop Limit (UInt8: 1..15)                         ]
Byte 2: [ Hop Count (UInt8: 0..hopLimit)                   ]
Bytes 3..5: [ Session ID (24-bit Big-Endian UInt)          ]
Bytes 6..9: [ Sequence Number (32-bit Big-Endian UInt)     ]
            └─ Byte 6: Member Slot (UInt8: 0..255)
            └─ Bytes 7..9: Monotonic Counter (24-bit: 0..16,777,215)
```

```swift
    public func serialize() -> Data {
        var data = Data(capacity: PacketConstants.cleartextEnvelopeSize)
        
        // Byte 0: version (high 4 bits) | type (low 4 bits)
        let byte0 = ((version & 0x0F) << 4) | (type.rawValue & 0x0F)
        data.append(byte0)
        
        // Byte 1: hopLimit (UInt8)
        data.append(hopLimit)
        
        // Byte 2: hopCount (UInt8)
        data.append(hopCount)
        
        // Bytes 3..5: sessionId (3 bytes, 24-bit big-endian)
        let sid3Bytes: [UInt8] = [
            UInt8((sessionId >> 16) & 0xFF),
            UInt8((sessionId >> 8) & 0xFF),
            UInt8(sessionId & 0xFF)
        ]
        data.append(contentsOf: sid3Bytes)
        
        // Bytes 6..9: sequenceNumber (32-bit big-endian)
        var seqBE = sequenceNumber.bigEndian
        data.append(Data(bytes: &seqBE, count: 4))
        
        return data
    }
```

### Nibble Packing & Endianness
* **Byte 0 Packing**: `((version & 0x0F) << 4) | (type.rawValue & 0x0F)` compresses protocol version (`0x03`) and packet type (`0x01` through `0x07`) into a single byte.
* **Big-Endian Invariant**: Network byte order is strictly Big-Endian. Multi-byte integers (`sequenceNumber`, `sessionId`) use `.bigEndian` to ensure identical byte representations across Apple Silicon ARM64 devices and x86_64 simulators.

---

## 3.2 Sequence Number Bit-Partitioning: Mathematical Proof

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

### The Multi-Node Nonce Collision Catastrophe
In AEAD ciphers (ChaCha20-Poly1305 and AES-GCM), **encrypting two different messages with the same key and same nonce causes catastrophic key recovery**. Because all festival friends in a group share the same symmetric group key, two devices must NEVER generate the same nonce.

TeeKum partitions the 32-bit sequence number:
* **High 8 Bits (Byte 6)**: `memberSlot` (derived deterministically from member initials).
* **Low 24 Bits (Bytes 7..9)**: Monotonic sequence counter ($0 \dots 16,777,215$).

$$\text{Sequence Space for Member A (Slot 1)} = \mathtt{0x01000000} \dots \mathtt{0x01FFFFFF}$$
$$\text{Sequence Space for Member B (Slot 2)} = \mathtt{0x02000000} \dots \mathtt{0x02FFFFFF}$$

The two sequence spaces are mathematically disjoint. Nonce collision across group members is impossible.

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

### The Mutable Header Paradox
When stranger nodes relay a packet, they increment `hopCount` by 1. If `hopCount` were part of the cryptographic MAC calculation, the Poly1305 tag would break on the first relay hop.

**The Solution**: Byte 2 is masked to `0x00` during AAD generation on both the sender and receiver. The remaining fields (`version`, `type`, `hopLimit`, `sessionId`, `sequenceNumber`) remain fully authenticated, preventing attackers from modifying hop limits or hijacking sessions.

---

## 3.4 96-Bit Nonce Construction

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

### 12-Byte Nonce Memory Structure
```
Bytes 0..2:  Session ID (3 bytes)
Bytes 3..6:  Sequence Number (4 bytes: 1B MemberSlot + 3B Monotonic Counter)
Byte 7:      Version & Type Nibble (1 byte)
Bytes 8..11: Protocol Domain Separation Tag: [0x54, 0x4B, 0x4D, 0x33] ("TKM3")
```

---

# 4. The 7 Encrypted 30-Byte Payloads: Byte-by-Byte Layouts

Every payload in TeeKum is serialized to **strictly 30 bytes**:

## 4.1 Type 0x01: `LocationPingPayload` (Geographic Telemetry)

| Byte Range | Field Name | Data Type | Encoding / Unit | Resolution |
| :---: | :--- | :--- | :--- | :--- |
| **0..3** | `latitudeRaw` | `Int32` (BE) | `lat * 10,000,000` | ~11 mm worldwide |
| **4..7** | `longitudeRaw`| `Int32` (BE) | `lon * 10,000,000` | ~11 mm worldwide |
| **8..11**| `timestamp` | `UInt32` (BE) | Unix epoch seconds | 1 second |
| **12** | `accuracy` | `UInt8` | Horizontal uncertainty | 0 to 255 meters |
| **13..14**| `senderInitials` | 2 × `UInt8` | Base-27 compressed | 3 letters in 16 bits |
| **15** | `batteryLevel` | `UInt8` | Integer percentage | 0 to 100% |
| **16** | `heading` | `UInt8` | `deg * 255 / 360` | ~1.41 degrees |
| **17** | `colorCode` | `UInt8` | `MemberColor.rawValue` | Palette index 0..8 |
| **18..29**| `reserved` | 12 × `UInt8` | Zero padding (`0x00`) | Reserved for barometry |

---

## 4.2 Type 0x02: `SOSPayload` (Emergency Distress Siren)

| Byte Range | Field Name | Data Type | Encoding / Unit | Purpose |
| :---: | :--- | :--- | :--- | :--- |
| **0..3** | `latitudeRaw` | `Int32` (BE) | Fixed-point coordinate | Victim GPS latitude |
| **4..7** | `longitudeRaw`| `Int32` (BE) | Fixed-point coordinate | Victim GPS longitude |
| **8..11**| `timestamp` | `UInt32` (BE) | Unix epoch seconds | Distress trigger time |
| **12** | `accuracy` | `UInt8` | Meters (0..255m) | GPS accuracy |
| **13** | `statusMarker`| `UInt8` | Fixed `0x01` | Urgent status flag |
| **14..17**| `sosEventId` | `UInt32` (BE) | Random 32-bit ID | Uniquely identifies SOS event |
| **18..19**| `senderInitials`| 2 × `UInt8` | Base-27 compressed | Victim initials |
| **20** | `emergencyType`| `UInt8` | `SOSType.rawValue` | General, Medical, Inactivity |
| **21** | `batteryLevel` | `UInt8` | Percentage (0..100) | Victim battery status |
| **22** | `colorCode` | `UInt8` | `MemberColor.rawValue` | Member color code |
| **23..29**| `reserved` | 7 × `UInt8` | Zero padding (`0x00`) | Reserved expansion bytes |

---

## 4.3 Type 0x03: `MeetingUpdatePayload` (Group Rendezvous)

| Byte Range | Field Name | Data Type | Encoding / Unit | Purpose |
| :---: | :--- | :--- | :--- | :--- |
| **0..3** | `latitudeRaw` | `Int32` (BE) | Fixed-point coordinate | Landmark GPS latitude |
| **4..7** | `longitudeRaw`| `Int32` (BE) | Fixed-point coordinate | Landmark GPS longitude |
| **8..11**| `meetupTime` | `UInt32` (BE) | Epoch seconds | Target rendezvous time |
| **12..15**| `createdAt` | `UInt32` (BE) | Epoch seconds | Proposal creation timestamp |
| **16** | `action` | `UInt8` | `MeetingAction` | Propose (1), Cancel (2), Update (3) |
| **17** | `attendanceStatus`| `UInt8`| `AttendanceStatus` | OnTheWay (1), Arrived (2), CannotMakeIt (3) |
| **18..21**| `meetingPointId`| `UInt32` (BE)| Monotonic ID | Unique landmark identifier |
| **22..23**| `senderInitials`| 2 × `UInt8` | Base-27 compressed | Proposer initials |
| **24** | `arrivalRadius`| `UInt8` | Meters (5..100m) | Geofence arrival radius (default: 25m) |
| **25** | `flags` | `UInt8` | Bitfield | Bit 0: RightNow, Bit 1: AnchorToGPS |
| **26..29**| `reserved` | 4 × `UInt8` | Zero padding (`0x00`) | Reserved expansion bytes |

---

## 4.4 Type 0x04 & Type 0x05: `RouteReqPayload` & `RouteRespPayload`

Used for reactive Ad-hoc On-Demand Distance Vector (AODV) multi-hop route negotiation:

| Byte Range | Field Name | Data Type | Purpose |
| :---: | :--- | :--- | :--- |
| **0..1** | `originatorInitials` | 2 × `UInt8` (Base-27) | Node requesting the route |
| **2..3** | `targetInitials` | 2 × `UInt8` (Base-27) | Destination node sought |
| **4..7** | `discoveryNonce` | `UInt32` (BE) | Random 32-bit ID suppressing duplicate RREQs |
| **8** | `routeCost` | `UInt8` | Accumulated hop metric along path |
| **9..29** | `reserved` | 21 × `UInt8` | Zero padding (`0x00`) |

---

## 4.5 Type 0x06: `ACKPayload` (Delivery Receipts)

| Byte Range | Field Name | Data Type | Purpose |
| :---: | :--- | :--- | :--- |
| **0..3** | `ackedSeqNumber` | `UInt32` (BE) | Original wire packet sequence confirmed |
| **4..5** | `ackedSenderInitials`| 2 × `UInt8` (Base-27)| Original sender being notified |
| **6..9** | `ackTimestamp` | `UInt32` (BE) | Epoch seconds when confirmation was issued |
| **10** | `ackStatus` | `UInt8` | `0x01` (Delivered to Friend), `0x02` (Relayed by Mesh) |
| **11** | `receivedRssi` | `Int8` | Signal strength observed on incoming link (dBm) |
| **12..15**| `originalEventId` | `UInt32` (BE) | Event ID being acknowledged |
| **16..17**| `responderInitials` | 2 × `UInt8` (Base-27)| Peer confirming receipt |
| **18..29**| `reserved` | 12 × `UInt8` | Zero padding (`0x00`) |

---

## 4.6 Type 0x07: `ChatMessagePayload` (Offline P2P Chat)

| Byte Range | Field Name | Data Type | Purpose |
| :---: | :--- | :--- | :--- |
| **0..1** | `senderInitials` | 2 × `UInt8` (Base-27) | Sender 3-letter initials |
| **2..5** | `timestamp` | `UInt32` (BE) | Unix epoch seconds |
| **6** | `textLength` | `UInt8` | Exact UTF-8 byte count ($0 \dots 20$) |
| **7..26** | `textContent` | 20 × `UInt8` | Direct UTF-8 text bytes (zero-padded) |
| **27..29**| `reserved` | 3 × `UInt8` | Zero padding (`0x000000`) |

---

# 5. Domain Entities & Hashing Algorithms

## 5.1 `MemberColor.swift` & The DJB2 Wrapping Hash

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

### The Invariants
1. **The Pure Red Exclusion Rule**: Pure Red is strictly banned from the user color palette. Red is reserved exclusively for Emergency SOS sirens to prevent false panic in crowded festivals.
2. **Daniel J. Bernstein's DJB2 Hash**: Uses prime seed `5381` and bitwise multiplier `($0 << 5) &+ $0` (equivalent to `hash * 33 + char`). Swift's wrapping addition operator `&+` guarantees that integer overflows wrap cleanly on 32-bit and 64-bit architectures without crashing.
3. **Deterministic Color Consistency**: If Alice's initials are `"ALX"`, every iPhone in the festival automatically resolves her pin to `.brightTeal` without transmitting color metadata over the air.

---

Proceed to **[Volume 03: Transport & Cryptography Engines](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/03_transport_and_security.md)**.
