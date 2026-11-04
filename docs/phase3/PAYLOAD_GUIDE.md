# TeeKum Phase 3 — 56-Byte Wire Protocol & Payload Developer Guide

> **Audience:** iOS Developers, Protocol Engineers, and Security Specialists working on TeeKum.  
> **Scope:** Phase 3 byte-level wire framing, Option B pure location telemetry re-packing, Festival Group Mesh Chat (`0x07`), independent status transmission via quick-tap preset chips, AEAD cryptographic boundaries, and validation rules under Protocol v3.  
> **Current Version:** Phase 3 Wire Standard (Protocol v3).  
> **Source Code Reference:** [`Packet.swift`](../../TeeKum%20Prototype/Models/Packet.swift), [`CryptoService.swift`](../../TeeKum%20Prototype/Services/CryptoService.swift), [`PacketCodecTests.swift`](../../TeeKum%20Prototype/Tests/PacketCodecTests.swift), [`CHAT_ARCHITECTURE.md`](CHAT_ARCHITECTURE.md).

---

## 1. Executive Summary & Core Phase 3 Wire Invariants

TeeKum is engineered to operate in dense festival environments (e.g. EDC, Coachella, Glastonbury) where 50,000 to 100,000 attendees congest RF channels and cellular infrastructure is non-existent.

To maintain single-digit millisecond radio airtime, prevent radio collisions on Apple Wireless Direct Link (AWDL) and Wi-Fi Direct, and allow zero-knowledge blind relaying for strangers without leaking private attendee data, every datagram across the mesh is constrained to **exactly 56 bytes**.

```text
+-----------------------+-----------------------------+-------------------------+
|  Outer Envelope (10B) |   Encrypted Payload (30B)   |   Auth Tag (16B)        |
|  (Cleartext Routing)  |   (Zero-Knowledge Cipher)   |   (Poly1305 / RFC 8439) |
+-----------------------+-----------------------------+-------------------------+
0                       10                            40                        56 Bytes
```

### Key Phase 3 Architectural Invariants:
1. **Option B Location Telemetry Re-Packing:** `statusCode` (formerly Byte 13) and `targetRefId` (formerly Bytes 14..17) are completely removed from `LocationPingPayload` (Type `0x01`). Telemetry is packed contiguously into Bytes 0..17, leaving a consolidated **12-byte contiguous reserved block (Bytes 18..29)** at the tail ready to absorb vertical floor & barometric altimetry (`floorLevel` + `barometricPressure`).
2. **Status Decoupling & Independent Transmission:** The legacy 1-byte canned status hash system is retired from location pings. Status updates and attendee intentions are transmitted independently via the new **Festival Group Mesh Chat** (`0x07`) using quick-tap preset chips (*"Beer line"*, *"At Main Stage"*, *"Restroom"*, *"Where are you?"*, *"On my way"*, *"Lost"*).
3. **Festival Group Mesh Chat Packet Type `0x07`:** Introduces direct serverless group text messaging across the multi-hop mesh. The outer envelope sets `versionAndType = 0x37` (`(0x03 << 4) | 0x07`), with default `hopLimit = 8`.
4. **Dedicated 20-Byte UTF-8 Encrypted Payload:** Text is encoded as direct UTF-8 bytes ($0 \dots 20$ bytes) with an explicit 1-byte length field and 3 reserved zero-padding bytes.
5. **Exact 56-Byte Wire Invariant:** 10-byte cleartext envelope + 30-byte ChaCha20 ciphertext + 16-byte Poly1305 MAC tag = exactly 56 bytes.
6. **Zero-Knowledge Blind Stranger Relaying:** Relay nodes inspect only the 10-byte cleartext outer envelope. Inner payloads remain sealed under ChaCha20-Poly1305.

---

## 2. Packet Types Summary (Protocol v3)

| Type Identifier | Packet Type | Wire Nibble | Cleartext Envelope `byte0` | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x01` | `.locationPing` | `0x1` | `0x31` | Pure geographic & sensor telemetry (Option B, status removed). |
| `0x02` | `.sos` | `0x2` | `0x32` | Emergency distress alert (15 hops, priority preemption). |
| `0x03` | `.meetingUpdate` | `0x3` | `0x33` | Single active rendezvous point proposal / acceptance. |
| `0x04` | `.routeReq` | `0x4` | `0x34` | On-demand AODV route discovery request. |
| `0x05` | `.routeResp` | `0x5` | `0x35` | On-demand AODV route discovery response. |
| `0x06` | `.ack` | `0x6` | `0x36` | Delivery acknowledgement confirmation. |
| `0x07` | `.chatMessage` | `0x7` | `0x37` | **(Phase 3 NEW)** Group mesh chat & independent status presets. |
| `0x08` | `.uwbTokenExchange` | `0x8` | `0x38` | **(Phase 3 NEW)** Apple Ultra-Wideband (U1/U2) discovery token fragment exchange. Strictly direct link (`hopLimit = 1`). |

---

## 3. Cleartext Outer Routing Envelope (Bytes 0..9)

The 10-byte envelope is transmitted in cleartext so intermediate mesh relay nodes can route frames, reject expired budgets, and deduplicate broadcasts without decrypting attendee coordinates or messages.

| Byte Offset | Wire Type | Field Name | Description & Invariant |
| :---: | :---: | :--- | :--- |
| **0** | `UInt8` | `versionAndType` | **High 4 bits:** Protocol Version (`0x3` for Protocol v3).<br>**Low 4 bits:** Packet Type (`0x1`..`0x7`). |
| **1** | `UInt8` | `hopLimit` | Forwarding budget ($1 \dots 15$, default `8` for ping/chat, `15` for SOS & meeting). Authenticated verbatim in AAD. |
| **2** | `UInt8` | `hopCount` | Hops traversed ($0 \dots \text{hopLimit}$, starts at `0`). Mutated (+1) per relay hop. **Masked to `0x00` in AAD**. |
| **3..5** | `UInt24` | `sessionId` | Big-endian 24-bit group identifier (`0x000001`..`0xFFFFFF`, $16,777,216$ namespaces). `0x000000` is reserved sentinel. |
| **6..9** | `UInt32` | `sequenceNumber` | Big-endian partitioned counter: **High 8 bits** = `memberSlot` ($0 \dots 255$); **Low 24 bits** = Monotonic counter ($1 \dots 16{,}777{,}215$). Provides replay protection and unique nonces. |

---

## 4. Cryptographic Proof of Mutable Relay Forwarding

### 4.1 AAD Hop-Masking Invariant
When calculating the Poly1305 MAC tag, the 10-byte envelope is injected as **Associated Authenticated Data (AAD)** into ChaCha20-Poly1305. Because intermediate relays increment `hopCount` (Byte 2), both sender and receiver normalize Byte 2 by **masking `hopCount` to `0x00`**:

$$\text{AAD} = \mathtt{byte0} \parallel \mathtt{hopLimit} [1\text{B}] \parallel \mathtt{0x00} [1\text{B}] \parallel \mathtt{sessionId} [3\text{B}] \parallel \mathtt{sequenceNumber} [4\text{B}]$$

```text
AAD Buffer (10 Bytes):
[ Byte 0: versionAndType (0x31..0x37) ]
[ Byte 1: hopLimit (authenticated verbatim) ]
[ Byte 2: 0x00 ]                     <-- hopCount normalized to 0x00
[ Bytes 3..5: sessionId (3 bytes) ]
[ Bytes 6..9: sequenceNumber (4 bytes) ]
```

### 4.2 RFC 8439 12-Byte Nonce Construction
$$\text{Nonce} = \mathtt{sessionId} [3\text{B}] \parallel \mathtt{sequenceNumber} [4\text{B}] \parallel \mathtt{versionAndType} [1\text{B}] \parallel \mathtt{"TKM3"} [4\text{B}]$$

- `Bytes 0..2`: `sessionId` (3 bytes, `UInt24` big-endian)
- `Bytes 3..6`: `sequenceNumber` (4 bytes, `UInt32` big-endian)
- `Byte 7`: `versionAndType` (1 byte, envelope Byte 0: e.g. `0x37` for chat)
- `Bytes 8..11`: 4-byte protocol domain tag `"TKM3"` (`[0x54, 0x4B, 0x4D, 0x33]`)

---

## 5. Phase 3 Payload Specifications (30 Bytes Each)

---

### Type 1: `0x01` — `LOCATION_PING` (Option B: Pure Telemetry)
*Broadcast periodically (3–5s moving, 15–30s stationary). Status code and target reference are stripped; telemetry is packed contiguously into Bytes 0..17, leaving 12 bytes reserved for Phase 3 vertical floor and barometry.*

```text
+---------------------------------------------------------------------------------------+
| Outer Cleartext Envelope (Bytes 0..9)                                                 |
| Byte 0: 0x31 | Byte 1: hopLimit (8) | Byte 2: hopCount | Bytes 3..5: sid | Bytes 6..9: seq|
+---------------------------------------------------------------------------------------+
| Encrypted Payload (Bytes 10..39 — 30 Bytes):                                          |
| Bytes 10..13: latitudeRaw (Int32 big-endian, lat * 1,000,000, ~11cm resolution)        |
| Bytes 14..17: longitudeRaw (Int32 big-endian, lon * 1,000,000, ~11cm resolution)      |
| Bytes 18..21: timestamp (UInt32 big-endian, Unix epoch seconds)                       |
| Byte 22: accuracy (UInt8, horizontal accuracy radius in meters 0..255)                |
| Bytes 23..24: senderInitials (UInt16 big-endian Base-27 compressed initials)          |
| Byte 25: batteryLevel (UInt8, percentage 0..100)                                      |
| Byte 26: heading (UInt8, compass degrees * 255 / 360)                                 |
| Byte 27: colorCode (UInt8, MemberColor code 0x00..0x08, 0x00=unset/initials hash)    |
| Bytes 28..39: reserved (12 bytes zero padding, 0x00...00, reserved for floor/barometry)|
+---------------------------------------------------------------------------------------+
| Bytes 40..55: authTag (16 bytes Poly1305 MAC)                                         |
+---------------------------------------------------------------------------------------+
```

| Payload Byte | Wire Type | Field Name | Description |
| :---: | :--- | :--- | :--- |
| **0..3** | `Int32` | `latitudeRaw` | Signed 32-bit big-endian: `Int32((latitude * 1_000_000).rounded())`. |
| **4..7** | `Int32` | `longitudeRaw` | Signed 32-bit big-endian: `Int32((longitude * 1_000_000).rounded())`. |
| **8..11** | `UInt32` | `timestamp` | Big-endian Unix epoch seconds (`UInt32(date.timeIntervalSince1970)`). |
| **12** | `UInt8` | `accuracy` | Horizontal uncertainty radius in meters ($0 \dots 255$m). |
| **13..14** | `UInt16` | `senderInitials` | Big-endian Base-27 compressed 1..3 uppercase letters via `InitialsCodec`. |
| **15** | `UInt8` | `batteryLevel` | Sender battery percentage ($0 \dots 100$%). |
| **16** | `UInt8` | `heading` | Compass heading ($0 \dots 255$ representing $0 \dots 360^\circ$, `degrees * 255 / 360`). Reconstructed into degrees via `headingDegrees` ($0.0^\circ \dots 359.9^\circ$), driving the live map `DirectionalHeadingIndicator` pointer and $50^\circ$ vision beam cone. |
| **17** | `UInt8` | `colorCode` | 1-byte personal neon member color code ($0\text{x}00$ unset, $0\text{x}01 \dots 0\text{x}08$). |
| **18..29** | `12 Bytes` | `reserved` | Consolidated reserved zero padding (`0x00...00`). |

---

### Type 7: `0x07` — `CHAT_MESSAGE` (Group Mesh Chat & Independent Status)
*Broadcast across the multi-hop mesh to transmit direct 20-byte UTF-8 text messages and quick-tap status presets.*

```text
+---------------------------------------------------------------------------------------+
| Outer Cleartext Envelope (Bytes 0..9)                                                 |
| Byte 0: 0x37 | Byte 1: hopLimit (8) | Byte 2: hopCount | Bytes 3..5: sid | Bytes 6..9: seq|
+---------------------------------------------------------------------------------------+
| Encrypted Payload (Bytes 10..39 — 30 Bytes):                                          |
| Bytes 10..11: senderInitials (UInt16 big-endian Base-27 compressed initials)          |
| Bytes 12..15: timestamp (UInt32 big-endian, Unix epoch seconds)                       |
| Byte 16: textLength (UInt8, exact UTF-8 byte count: 0..20)                            |
| Bytes 17..36: textContent (20 bytes UTF-8 text, zero-padded for unused bytes)          |
| Bytes 37..39: reserved (3 bytes zero padding, 0x000000)                                |
+---------------------------------------------------------------------------------------+
| Bytes 40..55: authTag (16 bytes Poly1305 MAC)                                         |
+---------------------------------------------------------------------------------------+
```

| Payload Byte | Wire Type | Field Name | Description |
| :---: | :--- | :--- | :--- |
| **0..1** | `UInt16` | `senderInitials` | Big-endian Base-27 compressed 1..3 uppercase letters via `InitialsCodec`. |
| **2..5** | `UInt32` | `timestamp` | Big-endian Unix epoch seconds (`UInt32(date.timeIntervalSince1970)`). |
| **6** | `UInt8` | `textLength` | Exact UTF-8 byte count of message text ($0 \dots 20$). |
| **7..26** | `20 Bytes` | `textContent` | Direct UTF-8 text bytes, zero-padded (`0x00`) for unused positions. |
| **27..29** | `3 Bytes` | `reserved` | Reserved zero padding (`0x000000`). |

#### Standard Festival Preset Quick Reply Chips (Independent Status)
Preset chips are pre-validated to never exceed the 20-byte wire limit:
- `"Beer line"` (9 bytes UTF-8)
- `"At Main Stage"` (13 bytes UTF-8)
- `"Restroom"` (8 bytes UTF-8)
- `"Where are you?"` (14 bytes UTF-8)
- `"On my way"` (9 bytes UTF-8)
- `"Lost"` (4 bytes UTF-8)

---

### Type 8: `0x08` — `UWB_TOKEN_EXCHANGE` (Ultra-Wideband Discovery Token Fragments)
*Strictly direct peer-to-peer transmission (`hopLimit = 1`). Exchanges serialized Apple `NIDiscoveryToken` fragments (25 bytes per fragment) out-of-band to establish bidirectional Ultra-Wideband (U1/U2) precision ranging sessions.*

```text
+---------------------------------------------------------------------------------------+
| Outer Cleartext Envelope (Bytes 0..9)                                                 |
| Byte 0: 0x38 | Byte 1: hopLimit (1) | Byte 2: hopCount (0) | Bytes 3..5: sid | Seq    |
+---------------------------------------------------------------------------------------+
| Encrypted Payload (Bytes 10..39 — 30 Bytes):                                          |
| Byte 10: action (UInt8: 0x01=tokenRequest, 0x02=tokenResponse, 0x03=stopRanging)     |
| Byte 11: sequenceId (UInt8: unique multi-fragment transaction correlation identifier)|
| Byte 12: fragmentIndex (UInt8: 0-indexed fragment number, 0..totalFragments-1)       |
| Byte 13: totalFragments (UInt8: total chunk count, e.g. 12 for 297B discovery token)  |
| Byte 14: dataLength (UInt8: number of valid fragment bytes in this frame, 1..25)      |
| Bytes 15..39: fragmentData (25 bytes chunk data, zero-padded for unused bytes)        |
+---------------------------------------------------------------------------------------+
| Bytes 40..55: authTag (16 bytes Poly1305 MAC)                                         |
+---------------------------------------------------------------------------------------+
```

| Payload Byte | Wire Type | Field Name | Description |
| :---: | :--- | :--- | :--- |
| **0** | `UInt8` | `action` | `0x01` = `tokenRequest`, `0x02` = `tokenResponse`, `0x03` = `stopRanging`. |
| **1** | `UInt8` | `sequenceId` | Transaction correlation identifier ($1 \dots 255$). |
| **2** | `UInt8` | `fragmentIndex` | Zero-based index of this fragment ($0 \dots \text{totalFragments}-1$). |
| **3** | `UInt8` | `totalFragments` | Total fragments comprising the complete archived `NIDiscoveryToken` ($1 \dots 15$). |
| **4** | `UInt8` | `dataLength` | Exact byte count of `fragmentData` in this packet ($1 \dots 25$). |
| **5..29** | `25 Bytes` | `fragmentData` | Raw slice of `NSKeyedArchiver` discovery token data, zero-padded for trailing slice. |


---

### Type 2: `0x02` — `SOS` (Urgent Emergency Distress Alert)
*Dispatched immediately upon 3-second continuous hold. Preempts all queues with 15-hop limit.*

```text
+---------------------------------------------------------------------------------------+
| Bytes 10..13: latitudeRaw (Int32 big-endian, freshest available GPS lat)              |
| Bytes 14..17: longitudeRaw (Int32 big-endian, freshest available GPS lon)            |
| Bytes 18..21: timestamp (UInt32 big-endian, epoch seconds of original GPS fix)        |
| Byte 22: accuracy (UInt8, horizontal accuracy radius in meters)                       |
| Byte 23: fixedStatusCode (UInt8, 0x01 SOS)                                            |
| Bytes 24..27: sosEventId (UInt32 big-endian, unique emergency alert nonce)            |
| Bytes 28..29: senderInitials (UInt16 big-endian Base-27 compressed initials)          |
| Byte 30: emergencyType (UInt8, 0x00 General, 0x01 Medical, 0x02 Separated, 0x03 Sec) |
| Byte 31: batteryLevel (UInt8, percentage 0..100)                                      |
| Byte 32: colorCode (UInt8, MemberColor code 0x00..0x08)                               |
| Bytes 33..39: reserved (7 bytes zero padding, 0x00000000000000)                       |
+---------------------------------------------------------------------------------------+
```

---

### Type 3: `0x03` — `MEETING_UPDATE` (Single Active Rendezvous — Redesigned)
*Proposes, accepts, or updates the single active group rendezvous point with explicit meetup time, auto-arrival geofencing, and automatic 1-hour post-meetup expiration. Location naming has been completely redesigned to be dynamic (proposer initials + target time & countdown).*

```text
+---------------------------------------------------------------------------------------+
| Bytes 10..13: latitudeRaw (Int32 big-endian, rendezvous latitude * 1,000,000)        |
| Bytes 14..17: longitudeRaw (Int32 big-endian, rendezvous longitude * 1,000,000)      |
| Bytes 18..21: meetupTime (UInt32 big-endian, scheduled arrival epoch seconds)         |
| Bytes 22..25: createdAt (UInt32 big-endian, proposal creation epoch seconds)          |
| Byte 26: action (UInt8, 0x01 Propose, 0x02 Accept, 0x03 Decline, 0x04 Cancel)        |
| Byte 27: attendanceStatus (UInt8, 0x01 Attending, 0x02 Can't Make It, 0x09 Arrived)   |
| Bytes 28..31: meetingPointId (UInt32 big-endian, unique proposal UUID nonce)          |
| Bytes 32..33: senderInitials (UInt16 big-endian Base-27 compressed initials)          |
| Byte 34: arrivalRadiusMeters (UInt8, geofence radius for auto-arrival, default 25m)   |
| Byte 35: flags (UInt8, Bit 0: isRightNow, Bit 1: anchorToProposerGPS)                 |
| Bytes 36..39: reserved (4 bytes zero padding, 0x00000000)                             |
+---------------------------------------------------------------------------------------+
```

---

### Type 4: `0x04` & `0x05` — `ROUTE_REQ` / `ROUTE_RESP` (AODV Mesh Discovery)
*Used for on-demand AODV route discovery to establish multi-hop paths to stale peers.*

```text
+---------------------------------------------------------------------------------------+
| Bytes 10..11: originatorInitials (UInt16 big-endian, Base-27 requester initials)     |
| Bytes 12..13: targetInitials (UInt16 big-endian, Base-27 target friend initials)      |
| Bytes 14..17: discoveryNonce (UInt32 big-endian, unique discovery session nonce)      |
| Byte 18: routeCost (UInt8, cumulative hop count & link quality metric)                |
| Bytes 19..39: reserved (21 bytes zero padding)                                        |
+---------------------------------------------------------------------------------------+
```

---

### Type 6: `0x06` — `ACK` (Delivery Acknowledgement)
*Confirms delivery of SOS alerts, chat messages, or meeting point updates.*

```text
+---------------------------------------------------------------------------------------+
| Bytes 10..13: ackedSeqNumber (UInt32 big-endian, sequence number being confirmed)     |
| Bytes 14..15: ackedSenderInitials (UInt16 big-endian, initials of original sender)     |
| Bytes 16..19: ackTimestamp (UInt32 big-endian, reception timestamp in epoch seconds)  |
| Byte 20: ackStatus (UInt8, 0x01 Delivered to Friend, 0x02 Relayed by Mesh Hop)        |
| Byte 21: receivedRssi (Int8, raw radio signal strength in dBm: e.g. -65)              |
| Bytes 22..25: originalEventId (UInt32 big-endian, echoed alert ID or 0)               |
| Bytes 26..27: responderInitials (UInt16 big-endian, Base-27 initials of confirmer)    |
| Bytes 28..39: reserved (12 bytes zero padding)                                        |
+---------------------------------------------------------------------------------------+
```

---

## 6. Validation, Bounds Checking & Malformed Packet Rules

1. **Exact Length Validation:**
   - Wire packets must be exactly 56 bytes (`PacketCodecError.invalidPacketSize(expected: 56, actual: n)`).
   - Inner payloads must be exactly 30 bytes (`PacketCodecError.bufferUnderflow` if $<30$).
2. **Text Length Constraints (Chat):**
   - Wire payload allocates strictly 20 bytes for `textContent`.
   - Byte 6 (`textLength`) must satisfy $0 \le \text{textLength} \le 20$. Values $>20$ trigger `PacketCodecError.invalidTextLength(Int)`.
   - `ChatMessagePayload.serialize()` throws `invalidTextLength` if input string exceeds 20 UTF-8 bytes.
   - `ChatMessagePayload.serializeUnchecked()` clamps to 20 bytes safely.
3. **UTF-8 Text Encoding Validity:**
   - Deserialization verifies that the byte slice `7..<(7 + textLength)` represents valid UTF-8. Corrupted byte sequences trigger `PacketCodecError.invalidTextEncoding`.
4. **Reserved Field Integrity:**
   - Bytes 27..29 of `ChatMessagePayload` are strictly reserved (`0x000000`).
   - Unused text padding bytes from `(7 + textLength)` to `26` must be `0x00`.
   - `ChatMessagePayload.deserializeStrict(from:)` verifies reserved zero padding, rejecting tampered padding with `PacketCodecError.payloadDeserializationFailed`.
5. **Code-Point Clamping (`clampTo20Bytes`):**
   - Prevents multi-byte UTF-8 corruption when pasting long text:
   ```swift
   public static func clampTo20Bytes(_ input: String) -> String {
       var accumulated = ""
       for char in input {
           let candidate = accumulated + String(char)
           if candidate.utf8.count <= maxTextBytes {
               accumulated = candidate
           } else {
               break
           }
       }
       return accumulated
   }
   ```

---

## 7. Concrete Worked Hex Scenarios

### Scenario 1: Alice Broadcasts Option B Location Ping
- **Sender:** Alice (`"ALI"`, MemberSlot: `1`)
- **Session ID:** `0x014321`
- **Coordinates:** Lat `36.114704`, Lon `-115.172813`
- **Accuracy:** `6` meters, **Battery:** `84%`, **Heading:** `180°` ($\mathtt{0x7F}$), **Color:** `NeonPink` (`0x01`)
- **Timestamp:** `1730198400` (`0x6720D300`)

```text
Offset  00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  Decoded Interpretation
-------------------------------------------------------------------------------------------------
0000    31 08 00 01 43 21 01 00 00 2A                    [Envelope] Ver:3, Type:Ping, Hops:8/0, SID:014321, Seq:1#42
000A    02 27 11 10 F9 22 9A 33 67 20 D3 00 06 04 26 54  [Payload] Lat:36.114704, Lon:-115.172813, Time, Acc:6m, ALI, Bat:84%
001A    7F 01 00 00 00 00 00 00 00 00 00 00 00 00        [Payload] Hdg:180°, NeonPink, 12 Reserved Zero Bytes
0028    A4 21 CD 88 12 90 BE 44 91 02 73 FA 55 19 CE 01  [AuthTag] 128-bit Poly1305 MAC Signature
```

### Scenario 2: Bob Broadcasts Group Chat Preset ("Beer line")
- **Sender:** Bob (`"BOB"`, MemberSlot: `2`)
- **Session ID:** `0x014321`
- **Text:** `"Beer line"` (9 bytes UTF-8)
- **Timestamp:** `1730198415` (`0x6720D30F`)
- **Initials Base-27:** `"BOB"` $\to (2 \times 729) + (15 \times 27) + 2 = 1{,}865$ $\to$ `0x0749`

```text
Offset  00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  Decoded Interpretation
-------------------------------------------------------------------------------------------------
0000    37 08 00 01 43 21 02 00 00 05                    [Envelope] Ver:3, Type:Chat(0x07), Hops:8/0, SID:014321, Seq:2#5
000A    07 49 67 20 D3 0F 09 42 65 65 72 20 6C 69 6E 65  [Payload] BOB, Time, Len:9B, "Beer line"
001A    00 00 00 00 00 00 00 00 00 00 00 00 00 00        [Payload] 11B Unused Padding + 3B Reserved Padding
0028    C8 44 19 B2 FE 80 11 9A 40 76 22 DA 08 31 7E FA  [AuthTag] 128-bit Poly1305 MAC Signature
```
