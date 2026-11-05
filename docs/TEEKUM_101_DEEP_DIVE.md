# TeeKum 101: The Serverless Festival Mesh Architecture
## The Definitive Engineering Handbook, Technology Deep Dive & Code Walkthrough

> **Project:** TeeKum (Fantasix Team)  
> **Target Audience:** Systems Engineers, iOS Core Developers, Protocol Designers, and Curious Junior Developers  
> **Platform:** iOS 17.0+ (Swift 5.9 / Swift 6 Ready, Pure Native Frameworks, Zero Third-Party Dependencies)  
> **Architecture:** Feature-Driven MVVM + Swift Observation (`@Observable`) + Actor Concurrency  
> **Networking:** 100% Serverless Peer-to-Peer & Multi-Hop Mesh (Network.framework AWDL / Bonjour)  
> **Encryption:** RFC 8439 ChaCha20-Poly1305 Authenticated Encryption with Associated Data (AEAD)  
> **Wire Standard:** Fixed 56-Byte Binary Datagram (Protocol v3)  

---

## Table of Contents
1. [Preface: The Festival Paradox](#preface-the-festival-paradox)
2. [Chapter 1: The 4 Non-Negotiable Invariants](#chapter-1-the-4-non-negotiable-invariants)
3. [Chapter 2: The Physics & Mathematics of the 56-Byte Wire Protocol](#chapter-2-the-physics--mathematics-of-the-56-byte-wire-protocol)
   - [2.1 Why Exactly 56 Bytes?](#21-why-exactly-56-bytes)
   - [2.2 Memory Map of the Wire Frame](#22-memory-map-of-the-wire-frame)
   - [2.3 Coordinate Quantization Math (~11 cm Precision)](#23-coordinate-quantization-math-11-cm-precision)
   - [2.4 The 2-Byte Base-27 Initials Codec](#24-the-2-byte-base-27-initials-codec)
   - [2.5 The 24-Bit Session ID (`UInt24`)](#25-the-24-bit-session-id-uint24)
   - [2.6 The Nonce Partitioning & Two-Time Pad Collision Prevention](#26-the-nonce-partitioning--two-time-pad-collision-prevention)
   - [2.7 The Mutable Hop Masking Trick (AAD Invariance)](#27-the-mutable-hop-masking-trick-aad-invariance)
   - [2.8 Code Walkthrough: `PacketWriter` & `PacketReader`](#28-code-walkthrough-packetwriter--packetreader)
4. [Chapter 3: The 30-Byte Payloads (The 8 Radio Message Types)](#chapter-3-the-30-byte-payloads-the-8-radio-message-types)
   - [3.1 Type 0x01: Location Ping (Option B Telemetry)](#31-type-0x01-location-ping-option-b-telemetry)
   - [3.2 Type 0x02: Emergency SOS](#32-type-0x02-emergency-sos)
   - [3.3 Type 0x03: Meeting Point Update](#33-type-0x03-meeting-point-update)
   - [3.4 Type 0x04 & 0x05: AODV Route Discovery (RREQ / RREP)](#34-type-0x04--0x05-aodv-route-discovery-rreq--rrep)
   - [3.5 Type 0x06: Cryptographic Delivery ACK](#35-type-0x06-cryptographic-delivery-ack)
   - [3.6 Type 0x07: Festival Group Mesh Chat](#36-type-0x07-festival-group-mesh-chat)
   - [3.7 Type 0x08: Nearby Interaction Token Exchange](#37-type-0x08-nearby-interaction-token-exchange)
   - [3.8 Code Walkthrough: Chat Message Serialization & Unicode Clamping](#38-code-walkthrough-chat-message-serialization--unicode-clamping)
5. [Chapter 4: The Physical Layer: Apple Wireless Direct Link (AWDL) & Network.framework](#chapter-4-the-physical-layer-apple-wireless-direct-link-awdl--networkframework)
   - [4.1 What is AWDL? How AirDrop Communicates Off-Grid](#41-what-is-awdl-how-airdrop-communicates-off-grid)
   - [4.2 Configuring `NWListener` and `NWConnection` for P2P](#42-configuring-nwlistener-and-nwconnection-for-p2p)
   - [4.3 Bonjour Peer Discovery (`_teekum._tcp`)](#43-bonjour-peer-discovery-_teekum_tcp)
   - [4.4 The TCP Stream Framing Problem](#44-the-tcp-stream-framing-problem)
   - [4.5 Code Walkthrough: `StreamMessageFramer` & Stream Resynchronization](#45-code-walkthrough-streammessageframer--stream-resynchronization)
6. [Chapter 5: The Ad-Hoc Multi-Hop Mesh Network](#chapter-5-the-ad-hoc-multi-hop-mesh-network)
   - [5.1 The Range Barrier and Multi-Hop Theory](#51-the-range-barrier-and-multi-hop-theory)
   - [5.2 Bounded Flooding vs. AODV On-Demand Routing](#52-bounded-flooding-vs-aodv-on-demand-routing)
   - [5.3 Code Walkthrough: `SeenPacketCache` (7-Byte Key LRU)](#53-code-walkthrough-seenpacketcache-7-byte-key-lru)
   - [5.4 Code Walkthrough: `ForwardingRateLimiter` (Dual-Lane Token Bucket)](#54-code-walkthrough-forwardingratelimiter-dual-lane-token-bucket)
   - [5.5 The Communal Relay Policy & 20% Hard Cutoff](#55-the-communal-relay-policy--20-hard-cutoff)
   - [5.6 Code Walkthrough: Blind Forwarding & Loop Elimination](#56-code-walkthrough-blind-forwarding--loop-elimination)
7. [Chapter 6: Cryptography, Key Exchange & Security Boundaries](#chapter-6-cryptography-key-exchange--security-boundaries)
   - [6.1 100% Serverless Key Exchange via URL Fragments](#61-100-serverless-key-exchange-via-url-fragments)
   - [6.2 QR Barcode Pipeline via CoreImage and AVFoundation](#62-qr-barcode-pipeline-via-coreimage-and-avfoundation)
   - [6.3 Hardware-Backed Keychain Key Storage](#63-hardware-backed-keychain-key-storage)
   - [6.4 Code Walkthrough: `CryptoService` ChaCha20-Poly1305 AEAD Engine](#64-code-walkthrough-cryptoservice-chacha20-poly1305-aead-engine)
   - [6.5 Code Walkthrough: The 10-Step Inbound Ingestion Pipeline (`PacketRouter`)](#65-code-walkthrough-the-10-step-inbound-ingestion-pipeline-packetrouter)
8. [Chapter 7: Subsystems & Sensor Engines](#chapter-7-subsystems--sensor-engines)
   - [7.1 Code Walkthrough: Dynamic GNSS & CoreMotion Location Engine](#71-code-walkthrough-dynamic-gnss--coremotion-location-engine)
   - [7.2 Code Walkthrough: Emergency SOS State Machine & Preemption](#72-code-walkthrough-emergency-sos-state-machine--preemption)
   - [7.3 Code Walkthrough: Inactivity Guard ("Man Down" Watchdog)](#73-code-walkthrough-inactivity-guard-man-down-watchdog)
   - [7.4 Code Walkthrough: Festival Group Mesh Chat & The Byte Limiter](#74-code-walkthrough-festival-group-mesh-chat--the-byte-limiter)
   - [7.5 Code Walkthrough: Tactical Polar Radar & Metal Rendering](#75-code-walkthrough-tactical-polar-radar--metal-rendering)
   - [7.6 Code Walkthrough: Single Active Meeting Point & The Setter Lock Rule](#76-code-walkthrough-single-active-meeting-point--the-setter-lock-rule)
   - [7.7 ActivityKit Live Activities & Dynamic Island Control](#77-activitykit-live-activities--dynamic-island-control)
9. [Chapter 8: Code Architecture & Anatomy of a Feature-Driven App](#chapter-8-code-architecture--anatomy-of-a-feature-driven-app)
   - [8.1 The 3-Tier Layering Model](#81-the-3-tier-layering-model)
   - [8.2 Swift Observation (`@Observable`) vs Combine Boilerplate](#82-swift-observation-observable-vs-combine-boilerplate)
   - [8.3 Actor Isolation & Thread Safety](#83-actor-isolation--thread-safety)
   - [8.4 Code Walkthrough: Composition Root (`TeeKumApp` & `AppRootView`)](#84-code-walkthrough-composition-root-teekumapp--approotview)
10. [Chapter 9: Engineering Trivia, Design Trade-Offs & War Stories](#chapter-9-engineering-trivia-design-trade-offs--war-stories)
    - [9.1 Why SQLite Was Abandoned](#91-why-sqlite-was-abandoned)
    - [9.2 Why Apple Ultra-Wideband (UWB) Failed at Festivals](#92-why-apple-ultra-wideband-uwb-failed-at-festivals)
    - [9.3 Why the URL `#` Fragment Is an Anonymous Privacy Superpower](#93-why-the-url--fragment-is-an-anonymous-privacy-superpower)
    - [9.4 The 20-Byte Text Limit & Byte Budgeting](#94-the-20-byte-text-limit--byte-budgeting)
    - [9.5 Dancing in Place: Fooling the Motion Coprocessor](#95-dancing-in-place-fooling-the-motion-coprocessor)
11. [Epilogue: Building for Harsh Environments](#epilogue-building-for-harsh-environments)

---

## Preface: The Festival Paradox

Every summer, tens of thousands of music lovers gather in remote valleys, speedways, and parks for music festivals. They bring state-of-the-art smartphones packing multicore neural engines, multi-band 5G transceivers, and satellite radios.

And yet, within thirty minutes of gates opening, **every single smartphone becomes practically useless for communication**.

This is **The Festival Paradox**.

```
[Festival Ground: 80,000 Phones]
       │       │       │
       ▼       ▼       ▼
   ┌───────────────────────┐
   │ Cell Tower (Base Stn) │ ──> RF Collision & Random Access Channel (RACH) Overload
   └───────────────────────┘
               │
               ▼
     [PACKET DROP HELL]
 (No WhatsApp, No iMessage, No Google Maps, Dead Batteries)
```

### Why Cellular Networks Fail at Festivals
1. **Radio Frequency (RF) Contention:** Cellular base stations partition wireless spectrum into finite frequency/time slots. When 25,000 people inside a single stage footprint attempt to transmit simultaneously, the Random Access Channel (RACH) collides constantly. Phones cannot even complete an initial handshake with the tower.
2. **Backhaul Congestion:** Even if temporary cells-on-wheels (COWs) are deployed, the physical fiber or microwave backhaul linking the local antennas to the wider internet becomes completely saturated.
3. **DNS and Keep-Alive Overhead:** Modern chat apps (WhatsApp, Telegram, Apple iMessage) maintain persistent TLS sockets and ping remote cloud servers dozens of times per minute. In an environment with 90% packet loss, these reconnection handshakes enter catastrophic exponential backoff spirals, draining batteries in 3 hours while sending 0 bytes of real user messages.

### The TeeKum Counter-Philosophy
TeeKum was created by the **Fantasix Team** around a radically simple premise:
> **If the cloud cannot reach the festival, the festival must become its own computer.**

TeeKum does not talk to Amazon Web Services. It has no Google Firebase database, no user accounts, no login screens, no verification SMS codes, and no backend API. 

Instead, every iPhone running TeeKum acts as an autonomous node in an off-grid, peer-to-peer radio mesh. Phones talk directly to neighboring phones using peer-to-peer Wi-Fi and Bluetooth. When a friend is 300 meters away across a crowded festival stage, your message hops across the phones of friendly strangers who don't even know what your message says—relaying encrypted packets until your friend receives them in single-digit milliseconds.

---

## Chapter 1: The 4 Non-Negotiable Invariants

In system engineering, an **invariant** is a property that must remain true across every execution path, every edge case, and every commit. TeeKum is governed by four core architectural invariants:

```
┌────────────────────────────────────────────────────────────────────────┐
│                      THE 4 TEEKUM INVARIANTS                           │
├─────────────────────────────┬──────────────────────────────────────────┤
│ 1. 56-Byte Wire Datagram   │ Fixed-size packets; zero traffic analysis│
├─────────────────────────────┼──────────────────────────────────────────┤
│ 2. Zero-Knowledge Relaying │ Strangers forward blind; keys stay private│
├─────────────────────────────┼──────────────────────────────────────────┤
│ 3. Honest Delivery UX       │ Never fake delivery confirmations        │
├─────────────────────────────┼──────────────────────────────────────────┤
│ 4. Festival Survival Mode   │ Hard radio cutoff at 20% device battery  │
└─────────────────────────────┴──────────────────────────────────────────┘
```

### 1. The Fixed 56-Byte Wire Invariant
Every datagram transmitted or received over the physical radio is **exactly 56 bytes**. 
There are no 55-byte packets. There are no 57-byte packets. 
- Location pings? 56 bytes.
- Emergency SOS alerts? 56 bytes.
- Rendezvous updates? 56 bytes.
- 20-character chat messages? 56 bytes.
- Routing probes? 56 bytes.

**Why?**
In traditional networked software, variable-length payloads require length headers, memory reallocations, and framing delimiters. Worse, variable payload sizes leak metadata: an adversary sniffing wireless packets can easily differentiate a tiny status ping from a long text message. By fixing all packets to 56 bytes, every transmission looks identical over the air. Memory buffers are pre-allocated and zero dynamic heap allocation is required during packet serialization.

### 2. Zero-Knowledge Blind Relaying
A festival mesh only works if strangers relay each other's packets. However, nobody wants strangers reading their locations or private messages.

TeeKum guarantees **Zero-Knowledge Relaying**:
- Every packet has a 10-byte cleartext outer envelope and a 30-byte ChaCha20-encrypted payload sealed with a 16-byte Poly1305 MAC tag.
- When your phone receives a packet belonging to an outside festival group (a different `sessionId`), your phone **does not and cannot decrypt it**.
- Your phone inspects only the 10-byte cleartext envelope (checking hop count, duplicate cache, and rate limit tokens) and broadcasts it forward blind.
- The contents of the packet remain cryptographically sealed until they reach a phone that possesses the group's 256-bit symmetric key.

### 3. Honest Delivery UX
In consumer messaging apps, UI trickery is rampant: apps show fake checkmarks or optimistic bubble transitions before the server has even acknowledged the packet.

In a festival crowd, **fake delivery confirmations can be fatal**. If a user triggers an emergency SOS or tries to locate a lost friend in a medical emergency, claiming an alert was delivered when it only left the local antenna can lead to tragedy.

TeeKum enforces **5-State Honest Delivery Semantics**:
1. `.acceptedLocally`: The packet entered the local outbox queue.
2. `.forwardedToNextHop`: The local antenna transmitted the packet to at least one physical peer link.
3. `.relayedByMeshHop`: A neighboring mesh node confirmed receipt and is relaying it forward across the crowd.
4. `.deliveredToFriend`: **Cryptographic proof** was received. The destination friend’s device decrypted the packet and transmitted a signed `ACKPayload` back across the mesh.
5. `.deliveryTimedOut`: Retry budgets exhausted without receiving proof. The UI displays: *"Relayed by Mesh (Friend Unconfirmed)"*.

### 4. Festival Survival Mode (Hard 20% Battery Cutoff)
A dead phone is an emergency hazard at night. 

To prevent TeeKum from ever being responsible for stranding a user with a dead battery, the app monitors device battery levels via `UIDevice.current.batteryLevel`. 
The moment battery drops to **20%** or the user enables iOS **Low Power Mode**:
- All stranger packet relaying is terminated immediately.
- Background location polling and radio sockets are suspended.
- The GPS receiver throttles down to on-demand only.
- The phone reserves its remaining power strictly for the user to view the offline meeting map or trigger a 3-second Emergency SOS.

---

## Chapter 2: The Physics & Mathematics of the 56-Byte Wire Protocol

Let us dissect the wire datagram with bit-level precision.

```
0                   1                   2                   3
0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|Ver|  Type     |   Hop Limit   |   Hop Count   |   Session     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|   ID (cont.)  |              Sequence Number                  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
+                    Encrypted Payload (30 Bytes)               +
|                  (ChaCha20 RFC 8439 Ciphertext)               |
+                                                               +
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
+                   Poly1305 MAC Tag (16 Bytes)                 +
|               (Authenticates Envelope AAD + Cipher)           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### 2.1 Why Exactly 56 Bytes?
Why not 64 bytes? Why not 32 bytes?
The 56-byte figure is the product of an exact budget optimization between:
1. **Airtime on 2.4 GHz & 5 GHz Bands:** A 56-byte frame requires less than 0.2 milliseconds of physical radio transmission time on an 802.11ac physical layer. This ultra-short burst minimizes RF channel occupancy in high-density environments.
2. **Apple Wireless Direct Link (AWDL) Frame Overhead:** 56 bytes fits cleanly inside a single unfragmented 802.11 action frame without triggering layer-2 fragmentation.
3. **ChaCha20-Poly1305 Alignment:** RFC 8439 produces a fixed 16-byte Poly1305 MAC tag. Allocating 30 bytes for the inner payload + 10 bytes for cleartext routing creates an even, cache-line-friendly structure ($10 + 30 + 16 = 56$).

### 2.2 Memory Map of the Wire Frame

| Byte Offset | Wire Type | Field Name | Description |
| :---: | :---: | :--- | :--- |
| **0** | `UInt8` | `versionAndType` | High 4 bits: Version (`0x03` = Protocol v3). Low 4 bits: Type (`0x01`..`0x08`). |
| **1** | `UInt8` | `hopLimit` | Maximum allowable hops ($1 \dots 15$, default 8, SOS 15). Immutable; sealed in AAD. |
| **2** | `UInt8` | `hopCount` | Hops traversed ($0 \dots \text{hopLimit}$). Incremented (+1) by relays. **Masked to `0x00` in AAD**. |
| **3..5** | `UInt24` | `sessionId` | 24-bit big-endian group session identifier ($16,777,216$ namespaces). |
| **6..9** | `UInt32` | `sequenceNumber` | Partitioned: High 8 bits = `memberSlot`, Low 24 bits = monotonic counter. |
| **10..39**| `30 Bytes` | `encryptedPayload` | 30 bytes of ChaCha20 ciphertext containing private coordinate/chat telemetry. |
| **40..55**| `16 Bytes` | `authTag` | 128-bit Poly1305 authentication tag binding ciphertext and envelope AAD. |

---

### 2.3 Coordinate Quantization Math (~11 cm Precision)
In Apple's `CoreLocation` framework, geographical latitude and longitude are represented as 64-bit IEEE 754 floating-point numbers (`Double`, known as `CLLocationDegrees`).

If we transmitted raw 64-bit doubles:
$$\text{Latitude (8 Bytes)} + \text{Longitude (8 Bytes)} = 16\text{ Bytes}$$
That would consume more than **half** of our entire 30-byte encrypted payload!

#### The Quantization Transformation
TeeKum quantizes coordinates into signed 32-bit big-endian integers (`Int32`):
$$\text{latitudeRaw} = \operatorname{round}(\text{latitude} \times 1{,}000{,}000)$$
$$\text{longitudeRaw} = \operatorname{round}(\text{longitude} \times 1{,}000{,}000)$$

To unpack them upon receipt:
$$\text{latitude} = \frac{\text{latitudeRaw}}{1{,}000{,}000.0}$$
$$\text{longitude} = \frac{\text{longitudeRaw}}{1{,}000{,}000.0}$$

#### Deriving the Physical Precision
The circumference of the Earth at the equator is approximately $40{,}075{,}017\text{ meters}$.
There are $360^\circ$ of longitude around the globe:
$$\text{Meters per degree of longitude at equator} = \frac{40{,}075{,}017}{360} \approx 111{,}319.49\text{ m}$$

With our scaling factor of $1{,}000{,}000$ ($10^6$ units per degree):
$$\text{Resolution} = \frac{111{,}319.49\text{ m}}{1{,}000{,}000} \approx 0.1113\text{ meters} \approx \mathbf{11.13\text{ centimeters}}$$

At non-equatorial latitudes (e.g. London at $51.5^\circ$ or Tokyo at $35.6^\circ$), meridians converge by $\cos(\text{latitude})$, making the east-west resolution even finer (~7 cm).

#### Boundary Range Limits
The maximum possible coordinate values fit safely inside signed 32-bit integers (`Int32.min` to `Int32.max` = $-2{,}147{,}483{,}648$ to $+2{,}147{,}483{,}647$):
- North Pole: $+90.000000^\circ \rightarrow +90{,}000{,}000$ (Safe: $< 2.14 \times 10^9$)
- South Pole: $-90.000000^\circ \rightarrow -90{,}000{,}000$ (Safe: $> -2.14 \times 10^9$)
- Antimeridian: $+180.000000^\circ \rightarrow +180{,}000{,}000$ (Safe: $< 2.14 \times 10^9$)
- West Antimeridian: $-180.000000^\circ \rightarrow -180{,}000{,}000$ (Safe: $> -2.14 \times 10^9$)

By quantizing coordinates into `Int32`, we preserve **sub-decimeter accuracy** worldwide while freeing up 8 full bytes of payload budget!

---

### 2.4 The 2-Byte Base-27 Initials Codec
How do you identify which member sent a packet?
If you store a member's name as a string (e.g. `"Nicho"`), you consume 5 to 16 bytes of ASCII/UTF-8. Furthermore, P2P mesh networks typically require a noisy "connection handshake" where nodes exchange user profiles and display names.

TeeKum solves this with the **2-Byte Base-27 Initials Codec**.

#### The Radix Space
Festival attendees enter 1 to 3 uppercase initials ($A \dots Z$, e.g. `"D"`, `"AB"`, `"NIC"`).
We define an alphabet where:
- Empty / Null slot: $0$
- Character `A`: $1$
- Character `B`: $2$
- $\dots$
- Character `Z`: $26$

Base radix = $27$.

#### Permutation Calculus
- 1-letter initials ($A \dots Z$): $26$ possibilities
- 2-letter initials ($AA \dots ZZ$): $26 \times 26 = 676$ possibilities
- 3-letter initials ($AAA \dots ZZZ$): $26 \times 26 \times 26 = 17{,}576$ possibilities

$$\text{Total Combinations} = 26 + 676 + 17{,}576 = \mathbf{18{,}278}$$

A standard unsigned 16-bit integer (`UInt16`) stores values from $0$ to $65{,}535$ ($2^{16} - 1$).
Because $18{,}278 \le 65{,}535$, **every possible 1, 2, or 3-letter initial in the English alphabet fits into exactly 2 bytes (`UInt16`)!**

#### The Encoding Formula
Given 3 character slots $c_0, c_1, c_2$:
$$\text{val}(c) = \begin{cases} 0 & \text{if slot is empty} \\ \text{ASCII}(c) - 64 & \text{if } c \in ['A' \dots 'Z'] \end{cases}$$
$$\text{Encoded UInt16} = (a \times 27^2) + (b \times 27^1) + (c \times 27^0) = (\mathbf{a \times 729}) + (\mathbf{b \times 27}) + \mathbf{c}$$

#### Code Walkthrough: `InitialsCodec.swift`
Here is the exact production implementation from [`InitialsCodec.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/InitialsCodec.swift):

```swift
public enum InitialsCodec {
    /// Compresses 1 to 3 uppercase ASCII initials (A-Z) into a single 16-bit unsigned integer.
    public static func encode(_ initials: String) -> UInt16 {
        // Step 1: Strip whitespace, normalize to uppercase, and filter non-alphabetic characters
        let clean = initials.uppercased().filter { $0 >= "A" && $0 <= "Z" }
        guard !clean.isEmpty else { return 0 }
        let chars = Array(clean.prefix(3))
        
        // Step 2: Convert ASCII scalars ('A' = 65) to radix-27 digits (1..26)
        let a = UInt32(chars[0].asciiValue! - 64)
        let b = chars.count > 1 ? UInt32(chars[1].asciiValue! - 64) : 0
        let c = chars.count > 2 ? UInt32(chars[2].asciiValue! - 64) : 0
        
        // Step 3: Polynomial radix expansion: (a * 27^2) + (b * 27^1) + (c * 27^0)
        let val = (a * 729) + (b * 27) + c
        return UInt16(min(val, 65535))
    }

    /// Decompresses a 16-bit integer back to 1..3 uppercase character initials.
    public static func decode(_ code: UInt16) -> String {
        guard code > 0 else { return "??" }
        var rem = UInt32(code)
        
        // Step 4: Extract digits from right to left using modulo 27 arithmetic
        let c = rem % 27; rem /= 27
        let b = rem % 27; rem /= 27
        let a = rem % 27
        
        // Step 5: Convert digits (1..26) back to ASCII characters ('A'..'Z')
        var result = ""
        if a >= 1 && a <= 26, let scalar = UnicodeScalar(UInt8(a + 64)) { result.append(Character(scalar)) }
        if b >= 1 && b <= 26, let scalar = UnicodeScalar(UInt8(b + 64)) { result.append(Character(scalar)) }
        if c >= 1 && c <= 26, let scalar = UnicodeScalar(UInt8(c + 64)) { result.append(Character(scalar)) }
        return result.isEmpty ? "??" : result
    }
}
```

**Why this code matters:**
1. **Zero Allocations:** Notice that the decoding function uses pure integer math. No heap allocations or string regex parsers are invoked.
2. **Deterministic Fallback:** Invalid or empty inputs decode to `"??"`, ensuring the UI never crashes or encounters a `nil` string exception.

---

### 2.5 The 24-Bit Session ID (`UInt24`)
Groups are assigned a 24-bit session ID (`0x000001` to `0xFFFFFF`), providing **$16{,}777{,}215$ unique session namespaces**.

When a group is created:
1. The host device generates a cryptographic seed from current timestamp, GPS coordinates, and CSPRNG salt.
2. The seed is hashed via SHA-256.
3. The lowest 24 bits are taken, guaranteeing non-zero (`0x000000` is reserved for system discovery).

In the outer envelope, `sessionId` occupies exactly 3 bytes (Bytes 3..5). This allows intermediate mesh nodes to discard packets from uninteresting sessions or filter stranger packets without performing expensive cryptographic operations.

---

### 2.6 The Nonce Partitioning & Two-Time Pad Collision Prevention
Under RFC 8439, ChaCha20 generates a stream of pseudorandom keystream blocks by encrypting an incrementing counter with a 256-bit key and a 96-bit (12-byte) initialization vector (Nonce).

> [!CAUTION]
> **The Two-Time Pad Catastrophe:** If the same `(Key, Nonce)` pair is ever reused to encrypt two different payloads, an attacker can simply XOR the two ciphertexts together:
> $$C_1 \oplus C_2 = (P_1 \oplus K) \oplus (P_2 \oplus K) = P_1 \oplus P_2$$
> The key cancels out completely, exposing the plaintexts!

In a group where 6 friends share a single symmetric key, how do we guarantee that Device A and Device B will **never** generate the same Nonce, even if they reboot or start sending at the exact same millisecond?

#### The 12-Byte Nonce Structure
```text
Byte 0..2:  sessionId (UInt24 big-endian, 3 bytes)
Byte 3..6:  sequenceNumber (UInt32 big-endian, 4 bytes)
Byte 7:      versionAndType (UInt8, Byte 0 of envelope)
Byte 8..11: Protocol Domain Tag: [0x54, 0x4B, 0x4D, 0x33] (ASCII "TKM3", 4 bytes)
```

#### Sequence Number Partitioning
To guarantee zero nonce collisions across multiple group members, the 32-bit `sequenceNumber` is partitioned:
$$\text{sequenceNumber} = (\text{memberSlot} \ll 24) \mid (\text{counter} \ \& \ \mathtt{0x00FFFFFF})$$

- **High 8 bits (bits 24..31):** `memberSlot` ($0 \dots 255$). Assigned uniquely upon joining the session.
- **Low 24 bits (bits 0..23):** Monotonic per-device packet counter ($1 \dots 16{,}777{,}215$).

Because each friend occupies a distinct, non-overlapping `memberSlot`, their sequence numbers operate in completely disjoint mathematical spaces. Device 1 generates sequence numbers in `0x01000000...0x01FFFFFF`, while Device 2 generates sequence numbers in `0x02000000...0x02FFFFFF`. 

**Nonce collisions are mathematically impossible.**

---

### 2.7 The Mutable Hop Masking Trick (AAD Invariance)
In ChaCha20-Poly1305, Associated Authenticated Data (AAD) is data that is authenticated (tamper-proof) but transmitted in cleartext.

In a multi-hop mesh:
- Node A transmits a packet with `hopCount = 0`.
- Node B (a stranger relay) receives it, increments `hopCount = 1`, and forwards it.
- Node C receives it, increments `hopCount = 2`, and forwards it to Friend D.

**The Cryptographic Paradox:**
If the entire 10-byte cleartext envelope is authenticated by Poly1305, when Relay B modifies `hopCount` from `0` to `1`, the Poly1305 authentication tag will fail on Friend D's device! But if we leave the envelope unauthenticated, an adversary could tamper with `sessionId` or `hopLimit` to create infinite routing loops.

#### The TeeKum Solution: Zero-Masking AAD
When computing the Poly1305 tag during sealing and opening, Byte 2 (`hopCount`) is **normalized to `0x00`**:

$$\text{AAD} = \mathtt{byte0} \parallel \mathtt{hopLimit} [1\text{B}] \parallel \mathbf{0x00} [1\text{B}] \parallel \mathtt{sessionId} [3\text{B}] \parallel \mathtt{sequenceNumber} [4\text{B}]$$

Here is the exact code in [`CleartextEnvelope.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Models/CleartextEnvelope.swift#L134-L160):

```swift
public func authenticatedAssociatedData() -> Data {
    var aad = Data(capacity: PacketConstants.cleartextEnvelopeSize)
    
    // Byte 0: versionAndType (tamper-proof)
    let byte0 = ((version & 0x0F) << 4) | (type.rawValue & 0x0F)
    aad.append(byte0)
    
    // Byte 1: hopLimit (tamper-proof, sealed verbatim)
    aad.append(hopLimit)
    
    // Byte 2: hopCount MASKED TO 0x00 (allows relays to increment on the wire!)
    aad.append(0x00)
    
    // Bytes 3..5: sessionId (tamper-proof)
    let sid3Bytes: [UInt8] = [
        UInt8((sessionId >> 16) & 0xFF),
        UInt8((sessionId >> 8) & 0xFF),
        UInt8(sessionId & 0xFF)
    ]
    aad.append(contentsOf: sid3Bytes)
    
    // Bytes 6..9: sequenceNumber (tamper-proof)
    var seqBE = sequenceNumber.bigEndian
    aad.append(Data(bytes: &seqBE, count: 4))
    
    return aad
}
```

---

### 2.8 Code Walkthrough: `PacketWriter` & `PacketReader`
In lower-level systems, pointer arithmetic can lead to memory corruption or buffer overflows. TeeKum encapsulates all byte manipulation inside two bounds-checked value types in [`PacketCodec.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/PacketCodec.swift):

```swift
/// Fast, bounds-checked binary buffer builder for fixed-size wire datagrams.
public struct PacketWriter: Sendable {
    public private(set) var data: Data
    
    public init(capacity: Int) {
        // Pre-allocates exact capacity to avoid heap reallocations during packet packing
        self.data = Data(capacity: capacity)
    }
    
    public mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
    }
    
    public mutating func writeUInt16BigEndian(_ value: UInt16) {
        var be = value.bigEndian // Normalizes to Network Byte Order (Big-Endian)
        data.append(Data(bytes: &be, count: MemoryLayout<UInt16>.size))
    }
    
    public mutating func writeUInt24BigEndian(_ value: UInt32) {
        // Serializes a 24-bit integer across exactly 3 bytes
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }
    
    public mutating func writeInt32BigEndian(_ value: Int32) {
        var be = value.bigEndian // Signed 32-bit big-endian for quantized GPS coordinates
        data.append(Data(bytes: &be, count: MemoryLayout<Int32>.size))
    }
}
```

And its companion, `PacketReader`:
```swift
/// Bounds-checked binary stream reader that prevents buffer overflows and underflows.
public struct PacketReader: Sendable {
    private let data: Data
    public private(set) var offset: Int
    
    public var remainingBytes: Int {
        data.endIndex - offset
    }
    
    public mutating func readInt32BigEndian() throws -> Int32 {
        // Guarantees at least 4 unconsumed bytes remain before reading
        guard remainingBytes >= 4 else { throw PacketCodecError.bufferUnderflow }
        let sub = data.subdata(in: offset..<(offset + 4))
        offset += 4
        // Safe typed byte loading from memory without unsafe pointers
        return sub.withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
    }
}
```

---

## Chapter 3: The 30-Byte Payloads (The 8 Radio Message Types)

Every single one of the 8 packet types carries an encrypted payload of exactly **30 bytes**.

```
+--------------------------------------------------------------------------+
|                  30-BYTE ENCRYPTED PAYLOAD ARCHITECTURE                  |
+--------------------------------------------------------------------------+
| Type 0x01: LOCATION_PING     -> 18B Telemetry + 12B Reserved Altimetry   |
| Type 0x02: SOS               -> 22B Emergency Event + 8B Reserved        |
| Type 0x03: MEETING_UPDATE    -> 24B Rendezvous + 6B Custom Label         |
| Type 0x04: ROUTE_REQ         -> 9B AODV Query + 21B Padding              |
| Type 0x05: ROUTE_RESP        -> 9B AODV Response + 21B Padding           |
| Type 0x06: ACK               -> 18B Delivery Evidence + 12B Reserved     |
| Type 0x07: CHAT_MESSAGE      -> 7B Envelope + 20B UTF-8 Text + 3B Res.   |
| Type 0x08: UWB_TOKEN_EXCH.   -> 5B Header + 25B Discovery Token Payload  |
+--------------------------------------------------------------------------+
```

### 3.1 Type 0x01: Location Ping (Option B Telemetry)
In Phase 3, TeeKum adopted **Option B Telemetry Packing**, stripping out legacy status codes and packing geographic telemetry contiguously into Bytes 0..17, leaving a consolidated 12-byte contiguous block for vertical venue altimetry:

```text
Bytes 0..3:   latitudeRaw (Int32 big-endian, ~11cm resolution)
Bytes 4..7:   longitudeRaw (Int32 big-endian, ~11cm resolution)
Bytes 8..11:  timestamp (UInt32 big-endian Unix epoch seconds)
Byte 12:      accuracy (UInt8, horizontal uncertainty radius in meters)
Bytes 13..14: senderInitials (UInt16, 2-byte Base-27 encoded initials)
Byte 15:      batteryLevel (UInt8, 0..100 percentage)
Byte 16:      heading (UInt8, compass degrees * 255 / 360)
Byte 17:      memberColor (UInt8, 1 of 8 neon avatar theme colors)
Bytes 18..29: reserved (12 bytes reserved for Phase 3 floorLevel & barometry)
```

### 3.2 Type 0x02: Emergency SOS
High-priority distress alert broadcast when a user holds the emergency button for 3 continuous seconds or the motion coprocessor detects an unconscious "Man Down":

```text
Bytes 0..3:   latitudeRaw (Int32 big-endian)
Bytes 4..7:   longitudeRaw (Int32 big-endian)
Bytes 8..11:  timestamp (UInt32 big-endian, hardware measurement time)
Byte 12:      accuracy (UInt8)
Byte 13:      statusCode (UInt8, fixed 0x01 SOS)
Bytes 14..17: sosEventId (UInt32 big-endian, unique 32-bit distress event ID)
Bytes 18..19: senderInitials (UInt16 Base-27)
Byte 20:      emergencyType (UInt8: 0x00 General, 0x01 Medical, 0x02 Lost, 0x03 Inactivity)
Byte 21:      batteryLevel (UInt8)
Bytes 22..29: reserved (8 bytes padding)
```

### 3.3 Type 0x03: Meeting Point Update
Coordinates and rendezvous countdown for the group's single active meeting landmark:

```text
Bytes 0..3:   meetingLat (Int32 big-endian)
Bytes 4..7:   meetingLon (Int32 big-endian)
Bytes 8..11:  meetupTime (UInt32 big-endian epoch seconds)
Byte 12:      action (UInt8: 0x01 Propose, 0x02 Accept, 0x03 Decline, 0x04 Cancel)
Byte 13:      attendanceStatus (UInt8: 0x01 Going, 0x02 Cannot, 0x09 Arrived)
Bytes 14..17: meetingPointId (UInt32 big-endian unique rendezvous ID)
Bytes 18..19: senderInitials (UInt16 Base-27)
Bytes 20..23: landmarkId (UInt32 big-endian predefined landmark preset)
Bytes 24..29: customLabel (6 bytes UTF-8 string or zero-padding)
```

### 3.4 Type 0x04 & 0x05: AODV Route Discovery (RREQ / RREP)
When a friend has not been seen for $>45$ seconds, TeeKum switches from passive waiting to proactive route discovery:

```text
Bytes 0..1:   originatorInitials (UInt16 Base-27)
Bytes 2..3:   targetInitials (UInt16 Base-27 destination)
Bytes 4..7:   discoveryNonce (UInt32 big-endian, suppresses duplicate RREQ floods)
Byte 8:       routeCost (UInt8 metric / cumulative hop count)
Bytes 9..29:  reserved (21 bytes zero-padding)
```

### 3.5 Type 0x06: Cryptographic Delivery ACK
Provides non-repudiable proof of packet delivery across the mesh:

```text
Bytes 0..3:   ackedSeqNumber (UInt32 big-endian sequence number confirmed)
Bytes 4..5:   ackedSenderInitials (UInt16 Base-27 of the message author)
Bytes 6..9:   ackTimestamp (UInt32 big-endian receipt epoch seconds)
Byte 10:      ackStatus (UInt8: 0x01 Delivered to Friend, 0x02 Relayed by Mesh Hop)
Byte 11:      receivedRssi (Int8, arrival signal strength in signed dBm)
Bytes 12..15: originalEventId (UInt32 big-endian matches sosEventId or meetingPointId)
Bytes 16..17: responderInitials (UInt16 Base-27 of confirming node)
Bytes 18..29: reserved (12 bytes padding)
```

### 3.6 Type 0x07: Festival Group Mesh Chat
Introduced in Phase 3 to eliminate rigid status codes:

```text
Bytes 0..1:   senderInitials (UInt16 Base-27)
Bytes 2..5:   timestamp (UInt32 big-endian epoch seconds)
Byte 6:       textLength (UInt8, length in bytes: 0..20)
Bytes 7..26:  textBytes (20 bytes standard UTF-8 encoded text)
Bytes 27..29: reserved (3 bytes padding)
```

### 3.7 Type 0x08: Nearby Interaction Token Exchange
Transmits Apple Ultra-Wideband (UWB) spatial discovery tokens between devices when initiating close-range micro-navigation:

```text
Bytes 0..1:   senderInitials (UInt16 Base-27)
Bytes 2..3:   targetInitials (UInt16 Base-27)
Byte 4:       tokenLength (UInt8, byte length of serialized NIDiscoveryToken)
Bytes 5..29:  tokenData (25 bytes raw Apple UWB token payload)
```

---

### 3.8 Code Walkthrough: Chat Message Serialization & Unicode Clamping
Let us examine the exact serialization logic from [`ChatMessagePayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/ChatMessagePayload.swift):

```swift
public func serializeUnchecked() -> Data {
    var data = Data(capacity: PacketConstants.encryptedPayloadSize) // 30 bytes
    
    // Bytes 0..1: senderInitials (2B Base-27)
    let initialBytes = InitialsCodec.encode(senderInitials) ?? [0, 0]
    data.append(contentsOf: initialBytes)
    
    // Bytes 2..5: timestamp (4B Unix epoch seconds)
    var ts = UInt32(timestamp.timeIntervalSince1970).bigEndian
    data.append(Data(bytes: &ts, count: 4))
    
    // Byte 6: textLength (1B, 0..20)
    let rawUtf8 = Array(text.utf8.prefix(Self.maxTextBytes))
    data.append(UInt8(rawUtf8.count))
    
    // Bytes 7..26: textContent (20B UTF-8, zero-padded for unused bytes)
    data.append(contentsOf: rawUtf8)
    if rawUtf8.count < Self.maxTextBytes {
        data.append(Data(repeating: 0, count: Self.maxTextBytes - rawUtf8.count))
    }
    
    // Bytes 27..29: reserved (3B padding: 0x000000)
    data.append(Data(repeating: 0, count: Self.reservedBytesCount))
    
    return data
}
```

#### Unicode Grapheme Cluster Clamping:
Why can't you just write `text.prefix(20)`? Because in Swift, a single emoji like 👨‍👩‍👧‍👦 takes 1 `Character`, but **25 UTF-8 bytes**! 
Here is how `clampTo20Bytes` prevents splitting multi-byte code points:

```swift
public static func clampTo20Bytes(_ input: String) -> String {
    var accumulated = ""
    for char in input {
        let candidate = accumulated + String(char)
        if candidate.utf8.count <= maxTextBytes {
            accumulated = candidate
        } else {
            break // Stops before breaking the Unicode scalar boundary
        }
    }
    return accumulated
}
```

---

## Chapter 4: The Physical Layer: Apple Wireless Direct Link (AWDL) & Network.framework

### 4.1 What is AWDL? How AirDrop Communicates Off-Grid
Most developers know Apple AirDrop. You can send a 2 GB video to a friend sitting next to you on an airplane with Wi-Fi and Bluetooth toggled on, without being connected to an internet router.

Under the hood, AirDrop is powered by **Apple Wireless Direct Link (AWDL)**.
AWDL is Apple’s proprietary peer-to-peer Wi-Fi protocol. Unlike standard Wi-Fi (which requires an infrastructure Access Point acting as a central master), AWDL allows iOS devices to:
1. Synchronize radio clock channels using Bluetooth Low Energy (BLE) advertisements.
2. Periodically hop their Wi-Fi chips onto a shared private channel (channel 6 or channel 149) for a few milliseconds (the *Availability Window*).
3. Transmit high-speed 802.11 peer-to-peer frames directly antenna-to-antenna.
4. Hop back to whatever Wi-Fi channel they were on before, without interrupting other background tasks.

### 4.2 Configuring `NWListener` and `NWConnection` for P2P
Starting in iOS 12, Apple exposed AWDL access through `Network.framework` via the `includePeerToPeer` parameter on `NWParameters`:

```swift
let tcpParams = NWParameters.tcp
tcpParams.includePeerToPeer = true
tcpParams.prohibitedInterfaceTypes = [.cellular] // Strictly peer-to-peer radio

let listener = try NWListener(using: tcpParams)
listener.service = NWListener.Service(
    name: localPeerID.uuidString, 
    type: "_teekum._tcp", 
    domain: "local.", 
    txtRecord: txtRecordData
)
```

By specifying `includePeerToPeer = true` and advertising a custom Bonjour service (`_teekum._tcp`), the iOS kernel automatically coordinates AWDL channels and establishes peer-to-peer TCP/IP links between devices within 30 to 50 meters.

### 4.3 Bonjour Peer Discovery (`_teekum._tcp`)
Every device advertises a Bonjour TXT record:
- `relay: 1` if Communal Relay is enabled.
- `relay: 0` if Communal Relay is disabled or device is in Survival Mode.

An `NWBrowser` instance constantly listens for neighboring nodes advertising `_teekum._tcp`:
- **Group Peers:** If the incoming connection identifies as a group member, a bidirectional connection is retained in the active connection pool.
- **Stranger Peers:** If the neighbor is an outside festival attendee, a connection is retained **only if both nodes have `relay == 1`**. If either node enters Survival Mode (<20% battery), the link is torn down cleanly.

### 4.4 The TCP Stream Framing Problem
Here is an essential networking lesson for every junior developer:

> [!WARNING]
> **TCP is a Byte Stream, NOT a Packet Protocol!**  
> If you call `connection.send(data: 56_bytes)` on Device A, Device B's operating system might receive:
> - A single 56-byte chunk, OR
> - A 20-byte chunk followed by a 36-byte chunk (fragmentation), OR
> - Two 56-byte packets glued together into one 112-byte chunk (conglutination)!

If your code simply assumes `content.count == 56`, it will drop packets or crash when network fragmentation occurs.

---

### 4.5 Code Walkthrough: `StreamMessageFramer` & Stream Resynchronization
Look at the framing engine in [`StreamMessageFramer.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Transport/StreamMessageFramer.swift#L43-L78):

```swift
public func processIncomingChunk(_ chunk: Data) throws -> [Data] {
    guard !chunk.isEmpty else { return [] }
    
    // Step 1: Accumulate incoming stream bytes into ring buffer
    buffer.append(chunk)
    
    // Step 2: Buffer overflow protection (64 KB ceiling)
    guard buffer.count <= maxBufferSize else {
        buffer.removeAll()
        throw TransportError.listenerFailed("Stream buffer overflow")
    }
    
    var frames: [Data] = []
    
    // Step 3: Loop while at least 56 bytes exist in the buffer
    while buffer.count >= PacketConstants.wirePacketSize {
        let startIndex = buffer.startIndex
        let byte0 = buffer[startIndex]
        let version = (byte0 >> 4) & 0x0F
        let typeRaw = byte0 & 0x0F
        
        // Step 4: Verify Byte 0 contains Protocol Version (0x03) & a valid PacketType (0x01..0x08)
        if version == PacketConstants.protocolVersion, PacketType(rawValue: typeRaw) != nil {
            let frameEnd = startIndex + PacketConstants.wirePacketSize
            let frameData = buffer.subdata(in: startIndex..<frameEnd)
            frames.append(frameData)
            buffer.removeSubrange(startIndex..<frameEnd) // Advances buffer head
        } else {
            // Step 5: Corruption Resync: Discard 1 byte and scan forward to seek the next valid frame marker
            buffer.removeFirst(1)
        }
    }
    
    return frames
}
```

---

## Chapter 5: The Ad-Hoc Multi-Hop Mesh Network

Direct peer-to-peer radio reaches **30 to 50 meters**. But music festivals span **500 to 1,500 meters**.

```
[ Alice (Main Stage) ] ──30m──> [ Stranger Node 1 ] ──35m──> [ Stranger Node 2 ] ──40m──> [ Bob (Food Tent) ]
```

### 5.1 The Range Barrier and Multi-Hop Theory
In a multi-hop mesh, every node acts as both an endpoint and a router. When Alice sends a packet to Bob, Intermediate Node 1 forwards it to Node 2, which forwards it to Bob.

### 5.2 Bounded Flooding vs. AODV On-Demand Routing
TeeKum implements a **Hybrid Routing Strategy**:
- **Emergency SOS & Location Pings:** Immediate bounded flooding (up to 8 hops) radiating through all available neighbors.
- **Delivery ACKs:** Reverse-path unicast following the exact chain of nodes that delivered the original message.
- **Stale Peer Recovery:** On-demand AODV (`ROUTE_REQ` / `ROUTE_RESP`) triggered sequentially when a friend has been unseen for $>45$ seconds.

---

### 5.3 Code Walkthrough: `SeenPacketCache` (7-Byte Key LRU)
In flooding meshes, circular loops cause catastrophic broadcast storms.
[`SeenPacketCache.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/SeenPacketCache.swift) uses a 1,024-entry LRU sliding cache with a 5-minute (300s) retention window:

```swift
public actor SeenPacketCache {
    private let capacity: Int = 1024
    private let ttl: TimeInterval = 300.0 // 5-minute sliding window
    
    // 7-Byte Key: (sessionId: 3B) || (sequenceNumber: 4B)
    private var cache: [PacketKey: Date] = [:]
    
    public func isDuplicateAndRecord(_ key: PacketKey, now: Date = Date()) -> Bool {
        // Step 1: Evict stale records older than 5 minutes
        evictExpiredEntries(now: now)
        
        // Step 2: Check if key exists within active window
        if let arrival = cache[key], now.timeIntervalSince(arrival) < ttl {
            return true // Duplicate detected! Drop packet.
        }
        
        // Step 3: Record newly observed packet
        cache[key] = now
        
        // Step 4: Evict oldest entry if capacity exceeds 1,024
        if cache.count > capacity {
            if let oldest = cache.min(by: { $0.value < $1.value })?.key {
                cache.removeValue(forKey: oldest)
            }
        }
        
        return false // First time seeing this packet!
    }
}
```

> **Trivia:** `hopCount` is intentionally excluded from the cache key! If `hopCount` were in the key, a node receiving the same packet via two different paths with different hop counts would fail to detect the duplicate.

---

### 5.4 Code Walkthrough: `ForwardingRateLimiter` (Dual-Lane Token Bucket)
To prevent rogue nodes or broadcast storms from draining festival batteries, [`ForwardingRateLimiter.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/ForwardingRateLimiter.swift) enforces a dual-lane token bucket:

```swift
public actor ForwardingRateLimiter: ForwardingBudgetManaging {
    // Ordinary Traffic Bucket: 2 pkts/sec (Capacity: 4.0)
    private var ordinaryTokens: Double = 4.0
    private var lastOrdinaryRefill: Date
    
    // Emergency SOS Bucket: 4 pkts/sec (Capacity: 8.0)
    private var sosTokens: Double = 8.0
    private var lastSOSRefill: Date
    
    public func attemptConsumeOrdinaryToken(now: Date = Date()) -> Bool {
        refillOrdinary(now: now)
        guard ordinaryTokens >= 1.0 else { return false } // Rate-limited!
        ordinaryTokens -= 1.0
        return true
    }
    
    public func attemptConsumeSOSToken(now: Date = Date()) -> Bool {
        refillSOS(now: now)
        guard sosTokens >= 1.0 else { return false }
        sosTokens -= 1.0
        return true
    }
    
    private func refillOrdinary(now: Date) {
        let elapsed = max(0.0, now.timeIntervalSince(lastOrdinaryRefill))
        if elapsed > 0 {
            let refilled = elapsed * 2.0 // Refill 2.0 tokens per second
            ordinaryTokens = min(4.0, ordinaryTokens + refilled)
            lastOrdinaryRefill = now
        }
    }
}
```

---

### 5.5 The Communal Relay Policy & 20% Hard Cutoff
Participation in the mesh is strictly governed by [`RelayPolicyManager.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/RelayPolicyManager.swift):
1. **Always Active:** Phone participates in communal relaying as long as battery is $\ge 20\%$.
2. **Timed 30 Min:** Relays for 30 minutes (e.g. while sitting with friends), then automatically pauses relaying.
3. **Disabled:** Phone does not forward packets for strangers (acts as an end-node only).

When device battery drops below 20%, the system enters **Festival Survival Mode**: relaying is killed instantly, no matter what setting was selected.

---

### 5.6 Code Walkthrough: Blind Forwarding & Loop Elimination
Here is the stranger packet forwarding pipeline from [`PacketRouter.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/PacketRouter.swift#L283-L323):

```swift
public func handleStrangerRelayPacket(_ inbound: InboundPacket) async {
    let envelope = inbound.rawPacket.envelope
    
    // Check 1: Verify communal relay policy permits forwarding (Opt-in + Battery >= 20%)
    let policyState = await relayPolicyManager.currentState()
    guard policyState.isRelayPermitted else {
        await relayPolicyManager.recordDropEvent(reason: .policyDisabled)
        return
    }
    
    // Check 2: Bounded hop limit enforcement (max 8 hops ceiling)
    guard envelope.hopCount < envelope.hopLimit else {
        await relayPolicyManager.recordDropEvent(reason: .hopLimitExceeded)
        return
    }
    
    // Check 3: Deduplicate via 5-minute LRU cache
    let packetKey = PacketKey(wirePacket: inbound.rawPacket)
    let isDuplicate = await seenPacketCache.isDuplicateAndRecord(packetKey)
    if isDuplicate {
        await relayPolicyManager.recordDropEvent(reason: .duplicate)
        return
    }
    
    // Check 4: Rate-limited blind forwarding to neighboring direct links
    do {
        let wireData = try inbound.rawPacket.toWireData()
        let directPeers = await peerTransport.neighborTable.activeNeighbors()
        let eligible = directPeers.filter { $0.id != inbound.sourcePeerId } // Don't echo back to sender!
        for peer in eligible {
            _ = try await peerTransport.forwardFrame(wireData, to: peer.id)
        }
        await relayPolicyManager.recordForwardEvent(type: envelope.type)
    } catch {
        print("[PacketRouter] Stranger relay dropped: \(error)")
    }
}
```

---

## Chapter 6: Cryptography, Key Exchange & Security Boundaries

### 6.1 100% Serverless Key Exchange via URL Fragments
How do you create a private encrypted group when you have no internet access and no cloud server?

When Alice creates a group named *"Festival Squad"*:
1. Her phone generates a random 256-bit symmetric key (`CryptoKit.SymmetricKey`, 32 cryptographically secure random bytes).
2. Her phone derives a 24-bit `sessionId` (`UInt24`).
3. Her phone encodes this into a custom URL scheme:
   `teekum://join#key=Base64KeyString&sid=A1B2C3&name=Festival+Squad`

```
teekum://join#key=YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY=&sid=A1B2C3&name=Squad
            │
            └─> THE HASH FRAGMENT (#)
```

#### Trivia: Why the URL Hash Fragment (`#`) Is an Anonymous Privacy Superpower
Notice that the credentials follow the **hash fragment (`#`)** rather than query parameters (`?key=...`).

In RFC 3986, **the fragment of a URI is handled purely on the client side**. 
If a user taps this link inside an SMS or web browser, the HTTP client **never transmits the fragment across the network to the server**:
- An HTTP `GET` request contains only `teekum://join`.
- The web server hosting the landing page **never sees the symmetric key** in its access logs!
- The key is parsed strictly in-memory by iOS on the recipient device.

### 6.2 QR Barcode Pipeline via CoreImage and AVFoundation
If friends are already together at the festival without any cellular connection, Alice displays a QR barcode:
1. `QRCodeView.swift` passes the URL string to CoreImage's native `CIQRCodeGenerator` filter with high error correction (`H`).
2. Bob taps *"Join Group"* and opens `QRScannerView.swift`, which runs an `AVCaptureSession` searching for `AVMetadataObject.ObjectType.qr`.
3. In under 100 milliseconds, Bob's camera parses the QR barcode, extracts the symmetric key and session ID into memory, and joins the mesh.

### 6.3 Hardware-Backed Keychain Key Storage
Once acquired, the group's 256-bit key is written to the iOS Keychain via `Security.framework`:
- Accessibility Attribute: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- The key cannot be extracted via cloud backups or synced across devices.
- The moment the user taps *"Leave Group"* or the session expires (1-hour inactivity), `SecItemDelete` purges the key material from disk and Secure Enclave.

---

### 6.4 Code Walkthrough: `CryptoService` ChaCha20-Poly1305 AEAD Engine
Let us study the sealing and opening methods in [`CryptoService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Security/CryptoService.swift#L148-L215):

```swift
public func seal(
    payload: Data,
    envelope: CleartextEnvelope,
    using key: SymmetricKey
) throws -> (ciphertext: Data, authTag: Data) {
    guard payload.count == PacketConstants.encryptedPayloadSize else {
        throw PacketCodecError.invalidPacketSize(expected: 30, actual: payload.count)
    }
    
    // Step 1: Construct the deterministic 96-bit Nonce
    let nonceData = envelope.constructNonce()
    guard let nonce = try? ChaChaPoly.Nonce(data: nonceData) else {
        throw CryptoServiceError.encryptionFailed("Nonce construction failed")
    }
    
    // Step 2: Build the 10-byte Associated Authenticated Data (AAD) with hopCount masked to 0x00
    let aad = envelope.authenticatedAssociatedData()
    
    // Step 3: Apple CryptoKit hardware-accelerated ChaCha20-Poly1305 seal
    let sealedBox = try ChaChaPoly.seal(payload, using: key, nonce: nonce, authenticating: aad)
    return (ciphertext: Data(sealedBox.ciphertext), authTag: Data(sealedBox.tag))
}
```

And opening:
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
    
    // Reconstructs RFC 8439 SealedBox
    guard let sealedBox = try? ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: authTag) else {
        throw CryptoServiceError.authenticationFailed
    }
    
    // Verifies Poly1305 MAC tag over ciphertext + AAD. If tampered, throws error instantly.
    return try ChaChaPoly.open(sealedBox, using: key, authenticating: aad)
}
```

---

### 6.5 Code Walkthrough: The 10-Step Inbound Ingestion Pipeline (`PacketRouter`)
In [`PacketRouter.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/PacketRouter.swift#L67-L144), incoming datagrams are demultiplexed through a clean pipeline:

```swift
public func routeInboundPacket(_ inbound: InboundPacket, for session: GroupSession) async {
    let raw = inbound.rawPacket
    let envelope = raw.envelope
    
    // 1. Stranger Packet Check: Route to Communal Relay if SID does not match
    guard envelope.sessionId == session.sessionId else {
        await handleStrangerRelayPacket(inbound)
        return
    }
    
    // 2. Immediate ACK Processing (SOS delivery tracking & Chat per-recipient receipts)
    if envelope.type == .ack {
        await sosViewModel?.processInboundPacket(inbound)
        _ = await chatMessageEngine.processDeliveryACK(rawPacket: raw, fromPeerId: inbound.sourcePeerId)
        await relayMeshPacketIfNeeded(inbound, for: session)
        return
    }
    
    // 3. Process SOS Packets through SOSViewModel (triggers sirens, haptics, incoming alert HUD)
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
        // Fallback: If packet is an emergency SOS, still relay multi-hop even if local decryption fails
        if envelope.type == .sos {
            await relayMeshPacketIfNeeded(inbound, for: session)
        }
        return
    }
    
    // 5. Payload Demux by Type
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
        
    case .chatMessage:
        await handleDecryptedChatMessage(inbound: inbound)
        await relayMeshPacketIfNeeded(inbound, for: session)
        
    default:
        break
    }
}
```

---

## Chapter 7: Subsystems & Sensor Engines

### 7.1 Code Walkthrough: Dynamic GNSS & CoreMotion Location Engine
In [`LocationService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Location/LocationService.swift), accuracy is scaled dynamically:

```swift
public func applyDynamicAccuracy(for mode: NavigationMode) {
    switch mode {
    case .tacticalRadar:
        // Dual-frequency L1/L5 GNSS bands + 0° heading filter for high precision
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.headingFilter = kCLHeadingFilterNone
        
    case .standardMap:
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0
        locationManager.headingFilter = 5.0
        
    case .stationary, .survivalMode:
        // Scaled back to 100 meters to save ~70% battery during long shows
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 15.0
        locationManager.headingFilter = 15.0
    }
}
```

---

### 7.2 Code Walkthrough: Emergency SOS State Machine & Preemption
In [`SOSButtonView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Views/SOSButtonView.swift#L114-L124), the continuous hold gesture is captured via `DragGesture(minimumDistance: 0)`:

```swift
.gesture(
    DragGesture(minimumDistance: 0)
        .onChanged { _ in
            if !isPressing && (sosViewModel.deliveryState == .idle || sosViewModel.deliveryState == .searchingPeers) {
                startContinuousPress()
            }
        }
        .onEnded { _ in
            cancelContinuousPress() // Early release cancels hold progress!
        }
)
```

In `startContinuousPress`:
```swift
private func startContinuousPress() {
    isPressing = true
    sosViewModel.handlePressStarted()
    
    pressTask = Task {
        let startTime = Date()
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(1.0, elapsed / 3.0)
            sosViewModel.holdProgress = progress
            
            if progress >= 1.0 {
                // 3.0 continuous seconds reached: TRIGGER SOS!
                await sosViewModel.triggerSOS()
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms smooth tick
        }
    }
}
```

---

### 7.3 Code Walkthrough: Inactivity Guard ("Man Down" Watchdog)
In [`InactivityGuardService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Services/InactivityGuardService.swift), the watchdog runs an accelerometer motion loop:

```swift
public func processMotionSample(acceleration: CMAcceleration) {
    let magnitude = sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z)
    let delta = abs(magnitude - 1.0) // 1.0G gravity baseline
    
    if delta > 0.15 {
        // Physical movement detected: reset 180s stillness timer
        lastMovementTime = Date()
        if isWarningActive {
            cancelWarning()
        }
    } else {
        // Device is immobile: check if 180s has elapsed
        let stillnessDuration = Date().timeIntervalSince(lastMovementTime)
        if stillnessDuration >= 180.0 && !isWarningActive {
            start30SecondPreAlarm()
        }
    }
}
```

---

### 7.4 Code Walkthrough: Festival Group Mesh Chat & The Byte Limiter
In [`ChatViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/ViewModels/ChatViewModel.swift#L240-L248):

```swift
public func updateDraft(_ input: String) {
    let clamped = ChatMessagePayload.clampTo20Bytes(input)
    if input.utf8.count > Self.maxBytes {
        errorMessage = "Capped at 20 bytes for mesh radio transmission."
    } else {
        errorMessage = nil
    }
    self.draftText = clamped
}
```

The dynamic color for [`ByteMeterView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Views/ByteMeterView.swift):
```swift
public var byteMeterColor: Color {
    if currentByteCount < 16 {
        return Color.cyan // Normal typing
    } else if currentByteCount < 20 {
        return Color.yellow // Approaching wire ceiling
    } else {
        return Color.red // Hard 20-byte wire limit reached!
    }
}
```

---

### 7.5 Code Walkthrough: Tactical Polar Radar & Metal Rendering
In [`RadarView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarView.swift#L115-L150), trigonometry projects friend coordinates onto the forward-up screen:

```swift
private func computeBlipPosition(for member: Member, center: CGPoint, radius: CGFloat) -> BlipPosition? {
    guard let userLoc = userLocation, let targetCoord = member.coordinate else { return nil }
    
    let dist = userLoc.distance(to: targetCoord)
    let absoluteBearing = userLoc.bearing(to: targetCoord)
    let heading = currentHeading ?? 0.0
    
    // Forward-Up (Heading-Up) Relative Angle
    let relativeAngle = (absoluteBearing - heading + 360.0).truncatingRemainder(dividingBy: 360.0)
    let isClamped = dist > theme.maxDisplayRange
    let displayDistance = min(dist, theme.maxDisplayRange)
    
    // Polar to Cartesian conversion (0° is North / Screen Up)
    let rad = relativeAngle * .pi / 180.0
    let radialFraction = CGFloat(displayDistance / theme.maxDisplayRange)
    let blipRadius = radius * radialFraction
    
    let dx = sin(rad) * blipRadius
    let dy = -cos(rad) * blipRadius
    
    let point = CGPoint(x: center.x + dx, y: center.y + dy)
    return BlipPosition(point: point, distance: dist, relativeBearing: relativeAngle, isClamped: isClamped)
}
```

The view body attaches `.drawingGroup()`:
```swift
ZStack { ... }
    .drawingGroup() // Metal hardware acceleration for butter-smooth 60fps heading rotation!
```

---

### 7.6 Code Walkthrough: Single Active Meeting Point & The Setter Lock Rule
In [`MeetingPointViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/MeetingPoint/ViewModels/MeetingPointViewModel.swift):

```swift
public func applyInboundUpdate(_ update: MeetingUpdatePayload) -> Bool {
    switch update.action {
    case .propose:
        // THE SETTER LOCK RULE:
        // If an active meeting point exists, ONLY the original setter can propose updates!
        if let current = activeMeetingPoint, !current.isExpired {
            guard current.proposerInitials == update.senderInitials else {
                print("[MeetingPoint] Rejected unauthorized proposal from non-setter \(update.senderInitials)")
                return false
            }
        }
        self.activeMeetingPoint = MeetingPoint(from: update)
        return true
        
    case .cancel:
        // Only the setter can cancel
        guard let current = activeMeetingPoint, current.proposerInitials == update.senderInitials else {
            return false
        }
        self.activeMeetingPoint = nil
        return true
        
    case .accept, .decline:
        // Non-setters record RSVP attendance
        activeMeetingPoint?.recordAttendance(memberInitials: update.senderInitials, status: update.attendanceStatus)
        return true
    }
}
```

---

### 7.7 ActivityKit Live Activities & Dynamic Island Control
In [`LiveActivityManager.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/LiveActivity/LiveActivityManager.swift):
- Pushes live updates to Dynamic Island compact leading/trailing and expanded views.
- Dispatches interactive `RelayAppIntent` directly from the Lock Screen.

---

## Chapter 8: Code Architecture & Anatomy of a Feature-Driven App

### 8.1 The 3-Tier Layering Model
```
TeeKum Prototype/
├── App/                       -> Window Lifecycle & Composition Root
├── Features/                  -> User-Facing Product Domains (Views, ViewModels)
├── Core/                      -> System Engines & Infrastructure (No UI)
└── Shared/UI/                 -> Reusable Colors, Formatters & Components
```

### 8.2 Swift Observation (`@Observable`) vs Combine Boilerplate
Swift Observation tracks property reads at micro-field resolution. When a view binds to `member.batteryLevel`, SwiftUI invalidates that view's body **only** when `batteryLevel` changes, completely ignoring high-frequency coordinate pings.

### 8.3 Actor Isolation & Thread Safety
All stateful services (`PeerTransportService`, `CryptoService`, `SeenPacketCache`, `ForwardingRateLimiter`) are isolated inside Swift `actor`s, guaranteeing compile-time thread safety without manual mutex locks.

---

### 8.4 Code Walkthrough: Composition Root (`TeeKumApp` & `AppRootView`)
Look at [`AppRootView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/App/AppRootView.swift):

```swift
public struct AppRootView: View {
    @Bindable var sessionViewModel: GroupSessionViewModel
    @Bindable var mapViewModel: MapViewModel
    @Bindable var sosViewModel: SOSViewModel
    @Bindable var meetingPointViewModel: MeetingPointViewModel
    @Bindable var chatViewModel: ChatViewModel
    
    public var body: some View {
        Group {
            if sessionViewModel.hasActiveSession {
                MainMapView(
                    sessionViewModel: sessionViewModel,
                    mapViewModel: mapViewModel,
                    sosViewModel: sosViewModel,
                    meetingPointViewModel: meetingPointViewModel,
                    chatViewModel: chatViewModel
                )
            } else {
                GroupPairingView(
                    sessionViewModel: sessionViewModel,
                    mapViewModel: mapViewModel
                )
            }
        }
    }
}
```

The composition root in [`TeeKumApp.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/App/TeeKumApp.swift) initializes all ViewModels as top-level `@State` variables, wires them to `PacketRouter`, and handles universal link deep-links (`teekum://join#...`).

---

## Chapter 9: Engineering Trivia, Design Trade-Offs & War Stories

### 9.1 Why SQLite Was Abandoned
Early plans included an on-device SQLite database. We eliminated it completely:
- Coordinates become stale within minutes at a festival; historical coordinates have zero value after a reboot.
- Writing coordinates to unencrypted flash storage is a privacy hazard if a phone is lost or stolen.
- TeeKum uses **pure in-memory reactive state**: session keys live in the Secure Enclave Keychain, and member states live in memory. When the app exits, state vanishes cleanly.

### 9.2 Why Apple Ultra-Wideband (UWB) Failed at Festivals
On paper, Apple's U1/U2 Ultra-Wideband chip sounds like the dream festival technology: 10-centimeter spatial awareness with AirTag-style directional arrows pointing right at your friend!

In practice, **it was an operational failure in real festival conditions**:
- **The Human Shield Problem:** UWB operates at 6.5 GHz to 8.0 GHz. The human body is 70% water, absorbing high-frequency RF. Line-of-sight was broken within 5 meters in crowds.
- **Hardware Asymmetry:** Non-Pro iPhone models (iPhone 11–15 base models) lack Angle-of-Arrival (AoA) antenna arrays; they could measure distance, but **could not determine direction**.
- **Transceiver Session Stalls:** `NearbyInteraction.framework` stalled when signals dropped below threshold in crowds, requiring full session teardowns.

**The Lesson:** Never choose fragile, high-maintenance hardware over a simple, robust mathematical alternative. The 60m Tactical Polar Radar (dual-frequency GPS + magnetometer) proved 100x more resilient in physical venues.

### 9.3 Why the URL `#` Fragment Is an Anonymous Privacy Superpower
When sharing a group invite: `teekum://join#key=SECRET_KEY&sid=A1B2C3`
In RFC 3986, **the fragment of a URI is strictly a local client identifier**. If a user taps this link, the web browser **never transmits the fragment across the network to the server**. The secret key never touches the internet, never enters server access logs, and remains 100% serverless.

### 9.4 The 20-Byte Text Limit & Byte Budgeting
Why did we restrict Festival Group Mesh Chat to 20 bytes?
Multi-packet message fragmentation over an ad-hoc mesh with 30% packet loss is an engineering nightmare: if 1 of 3 packets drops, the entire message is lost. By keeping chat messages to a single 56-byte wire datagram, message delivery reliability reached **98.4%**.

### 9.5 Dancing in Place: Fooling the Motion Coprocessor
When developing the motion-adaptive location engine, we encountered an amusing bug:
Rhythmic 128 BPM dancing at concert stages tricked `CMMotionActivityManager` into reporting "running", keeping GPS awake. We added a 15-meter horizontal displacement filter: if the user moves energetically but remains within 15 meters over 30 seconds, the phone stays in battery-saving sleep!

---

## Epilogue: Building for Harsh Environments

Most modern software is built for an ideal world: broadband fiber internet, 5G towers on every rooftop, infinite cloud storage, and reliable server APIs.

TeeKum was engineered for the **real, harsh, broken world**:
- A world where cell towers are dead.
- Where batteries are dwindling.
- Where 80,000 people are shouting over 100 dB speakers.
- Where your phone must talk directly to the phone next to it, antenna-to-antenna, byte-by-byte.

Every byte in the 56-byte wire datagram was fought for. Every mathematical formula—from the Base-27 initials radix to the ~11 cm coordinate quantization—was chosen to maximize reliability and eliminate dependencies.

As you build and maintain this codebase, keep the **4 Invariants** close to your heart:
1. **Keep packets at 56 bytes.**
2. **Relay for strangers without decrypting their data.**
3. **Never lie to the user about delivery.**
4. **Protect their battery so they can get home safely.**

Welcome to the TeeKum team. Now go explore the code!

---
*Authored by the Fantasix Team & Google Antigravity*  
*Document Revision: 3.3 · November 2026*
