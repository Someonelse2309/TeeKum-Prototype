# TeeKum — Product Decisions & Architectural Decision Records (ADR)

> **Document Type:** Authoritative Product & Architectural Decisions Register  
> **Target Audience:** Product Owners, Technical Architects, iOS Engineers, and AI Coding Agents  
> **Status:** APPROVED BASELINE & PENDING REFINEMENT REGISTER  
> **Current Date:** 2026-11-04  
> **Companion Documents:**
> - [Feature Requirements Document (FEATURE_REQUIREMENTS.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/product/FEATURE_REQUIREMENTS.md)
> - [User Stories Specification (USER_STORIES.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/product/USER_STORIES.md)
> - [Product Backlog (PRODUCT_BACKLOG.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/product/PRODUCT_BACKLOG.md)
> - [Master Agent Instructions (agent.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/agent.md)
> - [Knowledge Transfer Master Decisions (docs/knowledge_transfer/ARCHITECTURAL_DECISIONS.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/knowledge_transfer/ARCHITECTURAL_DECISIONS.md)

---

## 1. Decision Governance & Lifecycle

Every product and architectural decision governing TeeKum is classified under one of the following lifecycle states:
- **`APPROVED`**: Formally reviewed, consensus reached, implemented in the codebase, and verified via automated regression tests.
- **`PROPOSED`**: Formally documented and scheduled for future phases (Phase 4), awaiting human engineering sign-off or physical device trials.
- **`UNRESOLVED / REQUIRING APPROVAL`**: Open architectural questions or trade-offs that have technical implications and require explicit human stakeholder decision before implementation.
- **`SUPERSEDED / RETIRED`**: Historical decisions that have been replaced or retired during architectural iterations.

---

## 2. Approved Product Decisions (D01 – D22)

### Decision D01: 100% Serverless Group Pairing (QR & URL Fragments)
- **Status:** `APPROVED` (`Implemented`)
- **Context:** Attendees need to pair devices off-grid at remote venues with 0 cellular reception, without accounts, emails, or phone numbers.
- **Decision:** Generate a 256-bit symmetric encryption key via `SecRandomCopyBytes` entirely on-device. Share keys offline via on-screen CoreImage QR barcode, or pre-event via universal deep link (`teekum://join#key=Base64Key&sid=HexSID&name=GroupName`). Embed all key material strictly inside the URL fragment (`#`) per RFC 3986 so keys are never transmitted over network request lines.
- **Consequences:** Zero recurring server costs, complete user anonymity, instant on-site pairing. Sessions expire ephemerally; tearing down the session permanently deletes keys from the iOS Keychain.
- **Related Requirements & Stories:** `FR-GRP-01`, `FR-GRP-02`, `FR-GRP-03`, `US-GRP-01`, `US-GRP-02`.

---

### Decision D02: User-Controlled Live Sharing Master Toggle & SOS Override
- **Status:** `APPROVED` (`Implemented`)
- **Context:** Continuous GPS broadcasting drains attendee phone batteries and creates unwanted tracking while standing at music stages.
- **Decision:** Introduce a prominent "Live Sharing" toggle on the main map. When OFF, periodic location broadcasting and GPS satellite polling are completely halted. When ON, updates broadcast every 3–5s while moving or 15–30s while stationary. Emergency SOS alerts bypass the toggle and broadcast unconditionally.
- **Consequences:** Eliminates unnecessary GPS polling; respects attendee privacy while resting.
- **Related Requirements & Stories:** `FR-LOC-02`, `US-LOC-01`.

---

### Decision D03: Single Active Meeting Point & Setter Lock Rule
- **Status:** `APPROVED` (`Implemented`)
- **Context:** In chaotic festival crowds, having multiple simultaneous meeting points or allowing any member to move/cancel meeting points creates confusion and conflicting group instructions.
- **Decision:**
  1. Only **ONE active meeting point** exists for the group at any given time.
  2. **Setter Lock Rule:** The original proposer becomes the authoritative **Setter**. Only the Setter can update coordinates, change meetup time, or unset (cancel) the rendezvous.
  3. Non-setters are locked out from setting new meeting points while one is active, restricted strictly to 1-tap RSVP confirmations (*"I'll be there"*, *"Can't make it"*).
  4. Auto-expires 3,600s (1 hour) post-meetup time, releasing the lock.
- **Consequences:** Eliminates meeting point edit wars and conflicting rendezvous spots.
- **Related Requirements & Stories:** `FR-MTG-01`, `FR-MTG-02`, `FR-MTG-03`, `US-MTG-01`, `US-MTG-02`.

---

### Decision D04: Continuous Directional Finding & Tactical Polar Radar
- **Status:** `APPROVED` (`Implemented`)
- **Context:** Traditional 2D north-up street maps are disorienting in dense crowds with 30,000 dark silhouettes and no street landmarks.
- **Decision:** Implement a 60m forward-up tactical polar radar (`RadarView`). The radar disk rotates with the device magnetometer heading so that "Up" on the screen is always the direction the user is facing in the crowd. Members beyond 60m are clamped to the outer rim with outward chevrons and distance tags. Approaching within ~5–8m smoothly transitions into Apple Nearby Interaction (UWB) precision finding.
- **Consequences:** Instant, intuitive crowd navigation; zero mental map-rotation required.
- **Related Requirements & Stories:** `FR-NAV-01`, `FR-NAV-02`, `US-NAV-01`, `US-NAV-02`.

---

### Decision D05: Communal Relay Policy, Live Activity & Background Execution
- **Status:** `APPROVED` (`Implemented`)
- **Context:** iOS suspends background sockets when an iPhone is locked in a pocket, killing multi-hop mesh forwarding.
- **Decision:**
  1. Engage Apple's official background location status indicator (`showsBackgroundLocationIndicator = true`) and `allowsBackgroundLocationUpdates = true` on `CLLocationManager`. The system location status pill keeps `NWListener` and `NWConnection` sockets alive in pockets.
  2. `CoreMotion` safely sleeps the power-hungry GPS receiver when stationary.
  3. Group joining is gated behind the Communal Mesh Compact (`MeshAgreementView`). Three selectable relay modes: Always Active, Timed 30 Min, and Disabled.
  4. Stranger relaying automatically suspends at 20% battery (Festival Survival Mode).
- **Consequences:** Background mesh survival without running continuous GPS drain.
- **Related Requirements & Stories:** `FR-GRP-04`, `FR-MSH-07`, `FR-MSH-09`, `US-GRP-04`, `US-MSH-07`.

---

### Decision D06: Festival Survival Mode (Hard 20% Battery Cutoff)
- **Status:** `APPROVED` (`Implemented`)
- **Context:** An attendee whose phone battery completely dies at 2:00 AM at a festival is in danger of being stranded without navigation or safety alerts.
- **Decision:** When battery level drops below 20% (or iOS Low Power Mode is engaged), automatically:
  1. Halt all stranger packet forwarding and close stranger radio sockets.
  2. Terminate background socket listening.
  3. Throttle GPS sampling to 60–120s or strictly on-demand.
  4. Suspend outgoing chat.
  5. Reserve remaining power strictly for emergency SOS and viewing offline meeting maps.
- **Consequences:** Guaranteed power preservation for safety-critical operations.
- **Related Requirements & Stories:** `FR-BAT-03`, `FR-MSH-06`, `US-MSH-06`.

---

### Decision D07: Fixed 56-Byte Wire Datagram Standard & Int32 Coordinate Quantization
- **Status:** `APPROVED` (`Implemented`)
- **Context:** Over-the-air packets must fit within a single MTU frame to avoid fragmentation, transmit in $<1\text{ ms}$, and minimize radio baseband power draw.
- **Decision:** Enforce a fixed 56-byte binary datagram: 10-byte cleartext envelope + 30-byte encrypted payload + 16-byte Poly1305 MAC tag. Double-precision coordinates are quantized into signed 32-bit big-endian integers (`Int32`) via $1{,}000{,}000.0$ multiplier (~11cm resolution).
- **Consequences:** Maximum radio efficiency, sub-millisecond transmission, invariant packet framing.
- **Related Requirements & Stories:** `FR-MSH-01`, `FR-LOC-01`.

---

### Decision D08: 2-Byte Base-27 Initials Compression & Self-Describing Frames
- **Status:** `APPROVED` (`Implemented`)
- **Context:** Transmitting full string usernames wastes precious byte budget in a 30-byte payload.
- **Decision:** Compress 1 to 3 uppercase alphabetic letters ($A \dots Z$) into exactly 2 bytes (`UInt16`) using Base-27 radix encoding ($26^3 = 17,576 \le 65,535$). Every packet is self-describing, rendering member avatars instantly on maps without runtime handshake exchanges.
- **Consequences:** Compact identity representation leaving 28 bytes for coordinates and sensor telemetry.
- **Related Requirements & Stories:** `FR-GRP-01`, `FR-LOC-01`.

---

### Decision D09: Hybrid Routing Strategy (Immediate Flooding + On-Demand AODV)
- **Status:** `APPROVED` (`Implemented`)
- **Context:** Pure flooding causes broadcast storms in dense meshes; pure proactive routing tables collapse under rapid pedestrian mobility.
- **Decision:** Use a hybrid model:
  1. Emergency SOS and routine location pings use immediate bounded flooding (max 8 hops for pings, 15 hops for SOS) with 1,024-entry LRU deduplication (`SeenPacketCache`). SOS never waits for route discovery.
  2. ACKs follow reverse routes unicast if known, or flood if unknown.
  3. On-demand AODV (`ROUTE_REQ` / `ROUTE_RESP`) is used for directed queries and stale peer recovery.
- **Consequences:** Rapid emergency delivery without table lookups, combined with efficient directed routing.
- **Related Requirements & Stories:** `FR-MSH-03`, `FR-MSH-05`, `US-MSH-01`, `US-MSH-05`.

---

### Decision D10: Tethered Apple Watch Companion Architecture (Phase 4)
- **Status:** `PROPOSED / APPROVED IN ARCHITECTURE` (`Planned Phase 4`)
- **Context:** Standalone mesh node execution on Apple Watch is prohibited by watchOS ad-hoc networking restrictions and would deplete watch battery in $<1\text{ hour}$.
- **Decision:** Standardize Apple Watch strictly as a tethered companion extension (`WatchConnectivity` / `WCSession`) to the host iPhone. Primary roles: (1) high-intensity Taptic Engine wrist haptics for emergency SOS alerts in 100+ dB noise, (2) discrete 3-second wrist SOS triggers, (3) heads-up compass navigation, (4) 1-tap meeting point RSVP, and (5) watchOS Smart Stack mirroring.
- **Consequences:** Preserves watch battery while delivering high-value wrist haptics in loud concerts.
- **Related Requirements & Stories:** `FR-WAT-01` to `FR-WAT-06`, `US-WAT-01` to `US-WAT-05`.

---

### Decision D11: Close-Range Direction & Apple Nearby Interaction (UWB Scoping)
- **Status:** `APPROVED` (`Implemented`)
- **Context:** GPS horizontal accuracy is typically ±5–10m in outdoor crowds, leaving attendees unable to distinguish which person in a crowd is their friend.
- **Decision:** Scope Apple Nearby Interaction (Ultra-Wideband U1/U2) strictly as a close-range finder (<8 meters) inside `FinderBeaconView`. Exchange discovery tokens out-of-band over 1-hop mesh packets (`Type 0x08`, `uwbHopLimit = 1`). Provide seamless fallback to GPS/compass simulation on non-UWB devices.
- **Consequences:** Centimeter-level finding in the "last 10 meters" without requiring external hardware.
- **Related Requirements & Stories:** `FR-NAV-04`, `FR-NAV-05`, `US-NAV-03`, `US-NAV-04`.

---

### Decision D12: Multi-Floor & Differential Barometric Elevation (Phase 4)
- **Status:** `PROPOSED / APPROVED IN ARCHITECTURE` (`Planned Phase 4`)
- **Context:** In multi-story arenas, stadiums, and bleachers, 2D coordinates cause "0-meter arrival" confusion when friends are on different levels.
- **Decision:** Allocate 3 bytes from inner payload reserved padding (`floorLevel: Int8` at Byte 18 + `barometricPressure: UInt16` at Bytes 19..20). Resolve vertical elevation using peer-to-peer differential barometry ($\Delta h \approx 8.43 \times \Delta P$ meters) via `CMAltimeter`. Differential comparison cancels regional weather shifts without internet or indoor map dependencies.
- **Consequences:** Sub-meter vertical elevation awareness in multi-tiered venues while preserving 56-byte wire format.
- **Related Requirements & Stories:** `FR-ALT-01` to `FR-ALT-06`, `US-ALT-01` to `US-ALT-04`.

---

### Decision D13: Tactical Radar Polar Projection & Perimeter Clamping
- **Status:** `APPROVED` (`Implemented`)
- **Context:** Friends wandering $>60\text{m}$ away would vanish from a 60m radar disk if not clamped, causing sudden loss of situational awareness.
- **Decision:** Implement polar coordinate mapping ($r, \theta$) centered on the user. Dynamically clamp friends $>60\text{m}$ to the outer rim with outward chevrons and distance badges. Synchronize disk rotation with compass heading.
- **Consequences:** Guarantees that no group member ever vanishes from the tactical screen.
- **Related Requirements & Stories:** `FR-NAV-01`, `FR-NAV-02`, `US-NAV-01`, `US-NAV-02`.

---

### Decision D14: Dynamic Adaptive CoreLocation GNSS Accuracy Scaling
- **Status:** `APPROVED` (`Implemented`)
- **Context:** Running dual-frequency L1+L5 GPS continuously drains iPhone batteries in $<3\text{ hours}$.
- **Decision:** Scale GNSS power dynamically via `applyDynamicAccuracy()`:
  - Tactical Radar active: `kCLLocationAccuracyBestForNavigation` (dual-frequency L1/L5, 0m/0° filter).
  - Map overview moving: `kCLLocationAccuracyBest` (1.0° filter).
  - Stationary at stage / Survival Mode: `kCLLocationAccuracyHundredMeters` (15m/25m filter), cutting power by ~70%.
- **Consequences:** Delivers sub-meter navigation when looking at radar while extending battery to 8+ hours.
- **Related Requirements & Stories:** `FR-LOC-04`, `US-LOC-06`.

---

### Decision D15: Stale Peer Accelerated Cadence, Staggered AODV & Response Burst
- **Status:** `APPROVED` (`Implemented`)
- **Context:** In crowded venues, radio contact is easily interrupted by stage structures or crowds; passive recovery is too slow.
- **Decision:** When any peer is unseen $>30\text{s}$, accelerate local cadence to 2.0s; at 45s, dispatch an AODV `ROUTE_REQ` probe; the recovering peer replies with `ROUTE_RESP` and an immediate 3-ping burst at 2.0s intervals. Fall back to 20s if still missing after 90s.
- **Consequences:** Automated fast reconnect when friends come back into radio range.
- **Related Requirements & Stories:** `FR-LOC-08`, `US-LOC-05`.

---

### Decision D16: Integrated On-Device Mesh Debugger & Virtual Simulation Lab
- **Status:** `APPROVED` (`Implemented`)
- **Context:** Debugging wireless multi-hop meshes in the field without laptops or network sniffers is difficult and error-prone.
- **Decision:** Build an integrated diagnostic suite inside the app (`MeshDebuggerView`): 1-tap triage health audit, live 56-byte packet stream logger with bitfield inspector, synthetic packet/fault injector, and in-memory virtual multi-node topology sandbox (`MeshTopologySimulator`).
- **Consequences:** Enables on-site diagnostic triage, regression verification, and protocol inspection directly on iPhones.
- **Related Requirements & Stories:** `FR-DBG-01` to `FR-DBG-06`, `US-DBG-01` to `US-DBG-05`.

---

### Decision D17: Festival Group Mesh Chat & 20-Byte Text Engine (Status Retirement)
- **Status:** `APPROVED` (`Implemented`)
- **Context:** The legacy 1-byte canned status enum (`StatusCode`) piggybacked on location pings had critical flaws: GPS pings continually overwrote user status, status updates failed when Live Sharing was OFF, and canned codes were too rigid for festival needs.
- **Decision:** Fully retire the canned status system (`StatusCode`, `UserStatus`, `StatusPickerView`). Introduce **Festival Group Mesh Chat** (`ChatMessagePayload`, Type `0x07`, 56 bytes) transmitting up to 20 UTF-8 bytes over the multi-hop mesh. Provide 6 quick-tap preset chips (*"Beer line"*, *"At Main Stage"*, etc.) for one-handed messaging. Re-pack location pings into pure telemetry (Option B) with 12 bytes reserved.
- **Consequences:** Flexible text messaging, zero overwrite bugs, decoupled location telemetry, and vastly superior festival UX.
- **Related Requirements & Stories:** `FR-CHT-01` to `FR-CHT-07`, `US-CHT-01` to `US-CHT-05`.

---

### Decision D18: Peer Facing Direction & Vision Cones on Map View
- **Status:** `APPROVED` (`Implemented`)
- **Context:** Knowing a friend's position without knowing which way they are looking makes spotting them in a crowd difficult.
- **Decision:** Encode magnetometer heading into Byte 16 of `LocationPingPayload` ($0 \dots 255$). Reconstruct heading degrees ($0.0^\circ \dots 359.9^\circ$) on receiving devices and render a 50° translucent vision cone radiating from friend map pins.
- **Consequences:** Clear visual understanding of which direction friends are facing and walking.
- **Related Requirements & Stories:** `FR-LOC-05`, `US-LOC-03`.

---

### Decision D19: Native Apple Ultra-Wideband (U1/U2) Token Fragmentation
- **Status:** `APPROVED` (`Implemented`)
- **Context:** Apple `NIDiscoveryToken` data structures (~297 bytes) exceed the 56-byte wire datagram limit.
- **Decision:** Fragment discovery tokens across up to 12 frames (25 bytes per fragment) inside Type `0x08` datagrams (`UWBTokenExchangePayload`), strictly limited to direct 1-hop delivery (`uwbHopLimit = 1`). Reassemble byte-perfect tokens on receiver before initializing `NISession`.
- **Consequences:** Successful native Apple UWB ranging while preserving the 56-byte packet invariant.
- **Related Requirements & Stories:** `FR-NAV-04`, `US-NAV-03`.

---

### Decision D20: Autonomous "Man Down" Inactivity Guard Watchdog
- **Status:** `APPROVED` (`Implemented`)
- **Context:** If an attendee collapses, overdoses, or is knocked unconscious, they cannot press the manual SOS button.
- **Decision:** Implement an autonomous background motion watchdog (`InactivityGuardService`). Disabled by default (opt-in). If phone experiences variance $<0.15g$ and zero touches for 180s (3m), trigger a 30-second silent vibration warning modal (*"Are you okay? Auto-SOS in 30s"*). Any movement dismisses the alarm. Countdown expiry broadcasts an authenticated auto-SOS (`emergencyType = 0x04` inactivity) across 15 hops.
- **Consequences:** Autonomous life-safety rescue for unconscious members with zero-effort false-positive cancellation.
- **Related Requirements & Stories:** `FR-EMG-05`, `FR-EMG-06`, `US-EMG-04`, `US-EMG-05`.

---

### Decision D21: Centralized Master Configuration Architecture (`TeeKumConfiguration.swift`)
- **Status:** `APPROVED` (`Implemented`)
- **Context:** Scattered magic numbers and tuning parameters across dozens of services made benchmarking, testing, and field adjustment error-prone.
- **Decision:** Centralize all tuneable variables across 7 domains (Network, Timing, Chat, SOS, Rendezvous, Battery, Navigation) in a single source file: `TeeKumConfiguration.swift`.
- **Consequences:** One-stop configuration tuning for developers, field testers, and AI coding agents.
- **Related Requirements & Stories:** `FR-BAT-06`.

---

### Decision D22: Abandonment of Persistent SQLite Storage in Favor of In-Memory Actor State
- **Status:** `APPROVED` (`Implemented`)
- **Context:** An early POC concept explored using `libsqlite3` (`SessionStorageProtocol`) for persistent crash recovery.
- **Decision:** Formally abandon `libsqlite3` and purge `SessionStorageProtocol` from the codebase. All ephemeral runtime state (neighbor tables, packet deduplication caches, routing tables, and chat messages) is maintained in thread-safe Swift `actor`s in volatile RAM. Session keys are stored in the iOS Keychain.
- **Consequences:** Simplified architecture, zero database disk I/O, zero risk of persistent location data leakage.
- **Related Requirements & Stories:** `FR-GRP-07`, `NFR-PRIV-01`.

---

## 3. Outstanding Product Decisions Requiring Human Approval (PD-01 – PD-06)

The following decisions represent open architectural trade-offs, bug remediation strategies, or planned roadmap enhancements. Each decision specifies context, options considered, recommended direction, and exact impact. **None of these decisions may be unilaterally implemented by AI agents without explicit human approval.**

---

### Decision PD-01: Group Size Scalability Beyond 8 Members
- **Status:** `UNRESOLVED / REQUIRING APPROVAL`
- **Context:** The current system caps group sessions at **8 concurrent active members** (`memberSlot: 0...7`). In festival scenarios, groups of 10 to 16 friends frequently travel together.
- **Options Considered:**
  - **Option A (Preserve 8-Member Cap):** Maintain strict 8-member limit. Groups $>8$ split into two sub-groups. Protects AWDL radio airtime from TDMA slot exhaustion and keeps packet header sizes minimal.
  - **Option B (Expand to 16 Members via 4-Bit Slot Partitioning):** Expand `memberSlot` from 3 bits ($0 \dots 7$) to 4 bits ($0 \dots 15$) inside the 32-bit sequence number (`UInt32`), leaving 28 bits for the monotonic counter (268M sequence numbers).
  - **Option C (Dynamic Soft Peering with Priority Sub-Clustering):** Allow up to 16 group members, but each node actively peers with only the 8 closest members, relying on internal mesh hops for distant members.
- **Recommendation:** **Option B (Expand to 16 Members)** for Phase 4. Sequence number bit-partitioning ($4\text{ bits slot} + 28\text{ bits counter}$) fits cleanly within the existing 4-byte `sequenceNumber` wire field without altering the 56-byte packet size.
- **Questions for Human Stakeholders:**
  1. Is an 8-member group ceiling acceptable for the initial App Store release?
  2. Does physical AWDL radio contention support 16 concurrent peers in crowded RF conditions without packet loss?

---

### Decision PD-02: Cryptographic Member Slot Allocation & Nonce Partitioning (Remediation of `BUG-01`)
- **Status:** `UNRESOLVED / REQUIRING APPROVAL`
- **Context:** Confirmed defect `BUG-01` in `GroupSession.swift` (line 53): `memberSlot` is currently computed as `bytes[0] ^ bytes[1]` of the Base-27 initials. In a group where two friends have initials that XOR to the same value (e.g. "AB" vs "BA", or any initials with identical XOR byte hashes), their `memberSlot` values collide. This causes identical 96-bit ChaCha20 nonces (a catastrophic cryptographic vulnerability leading to keystream reuse) and causes `TeeKumApp.swift` to drop self-relayed packets.
- **Options Considered:**
  - **Option A (Host-Assigned Sequential Slot in QR / Invite Link):** Host is always Slot 0. When joiners scan the QR code or tap the link, they negotiate a unique sequential slot index ($1, 2, 3 \dots$) via direct Bonjour handshake.
  - **Option B (Randomized 8-Bit Nonce Salt with Collision Detection):** Replace `memberSlot` with a cryptographically random 8-bit CSPRNG salt generated on session start, and broadcast a slot-claim packet during peering to detect and re-roll collisions.
  - **Option C (Full 12-Byte CSPRNG Nonce in Packet Header):** Replace partitioned sequence numbers with a truly random 12-byte initialization vector per packet. *(Rejected: Wire envelope would expand by 8 bytes, breaking 56-byte standard)*.
- **Recommendation:** **Option A (Host-Assigned Sequential Slot)**. Host is Slot 0; joiners receive an assigned slot during pairing, eliminating XOR hash collision mathematically.
- **Questions for Human Stakeholders:**
  1. Do you approve transitioning from Initials-XOR slot generation to Host-Assigned sequential slot assignment?

---

### Decision PD-03: Session ID Bit-Width Alignment (Resolving `BUG-02`)
- **Status:** `UNRESOLVED / REQUIRING APPROVAL`
- **Context:** Confirmed issue `BUG-02`: In `agent.md` and `Packet.swift`, the wire protocol envelope allocates **3 bytes (24 bits)** for `sessionId` (`Bytes 3..5`). However, several Swift data models (`GroupSession.swift`, `PacketKey`) declare `sessionId` as a 16-bit `UInt16`, permanently writing `0x00` into Byte 3 and truncating entropy to 65,536 sessions.
- **Options Considered:**
  - **Option A (Promote Swift Models to Full 24-Bit `UInt32` Clamped):** Update `GroupSession.sessionId` and internal models to use `UInt32` masked to `0x00FFFFFF`, generating full 24-bit session IDs ($16.7\text{ million}$ combinations) and utilizing all 3 bytes on the wire.
  - **Option B (Formally Shrink Wire Protocol to 16-Bit `UInt16`):** Redefine Byte 3 as an additional protocol flag or reserved byte, and formally standardise `sessionId` as 2 bytes (`UInt16`).
- **Recommendation:** **Option A (Promote Swift Models to Full 24-Bit)**. Preserves the approved 3-byte wire format and expands session entropy by $256\times$, minimizing session hash collisions across different festival groups.
- **Questions for Human Stakeholders:**
  1. Do you approve updating Swift session models to 24-bit `UInt32`?

---

### Decision PD-04: Apple Watch Dedicated Target vs Shared Framework
- **Status:** `UNRESOLVED / REQUIRING APPROVAL`
- **Context:** `TeeKumWatch` companion extension is approved in Phase 4 roadmap (Decision D10). We must decide how code is shared between host iOS app and watchOS target.
- **Options Considered:**
  - **Option A (Shared Target Membership):** Add existing Swift model files (`Member.swift`, `Formatters.swift`, `SessionActivityAttributes.swift`) directly to the watchOS target membership in Xcode. Zero new targets needed.
  - **Option B (Create Shared Swift Package / Framework `TeeKumCore`):** Extract protocol models, codecs, and formatters into a shared local Swift framework target embedded in both iOS and watchOS targets.
- **Recommendation:** **Option A (Shared Target Membership)** for simplicity, adhering to the "Radical Simplicity" product principle without adding framework build overhead.
- **Questions for Human Stakeholders:**
  1. Do you prefer direct target file sharing (Option A) or a dedicated shared framework target (Option B)?

---

### Decision PD-05: Offline Vector GeoJSON Venue Overlays vs Pre-Cached MapKit
- **Status:** `UNRESOLVED / REQUIRING APPROVAL`
- **Context:** In remote desert festivals (e.g. Burning Man, Coachella campgrounds), Apple MapKit vector tiles may render blank grey grids if not pre-cached by the user before arriving.
- **Decision Trade-Off:**
  - **Option A (Pre-Cached MapKit Tiles Only):** Prompt user to download offline MapKit map regions in iOS Settings prior to arrival. Zero app bundle bloat.
  - **Option B (Bundled GeoJSON Vector Festival Overlays):** Support importing a lightweight GeoJSON vector package containing stage boundaries, medical tents, restrooms, and landmarks rendered as `MKOverlay` polygons directly over the map.
- **Recommendation:** **Option B** as a Phase 4 feature. Bundling offline festival vector polygons (~50 KB GeoJSON) guarantees crisp venue maps even when MapKit background satellite tiles are missing.
- **Questions for Human Stakeholders:**
  1. Should offline festival stage polygons be supported via GeoJSON overlays in Phase 4?

---

### Decision PD-06: Multi-Rendezvous Sub-Group Support vs Strict Single Active Invariant
- **Status:** `UNRESOLVED / REQUIRING APPROVAL`
- **Context:** In groups of 6–8 members, members occasionally split into two separate factions (e.g. 3 people going to Bass Stage, 4 people going to House Stage). Currently, `FR-MTG-01` strictly permits only ONE active meeting point for the entire group.
- **Options Considered:**
  - **Option A (Preserve Strict Single Active Meeting Point):** Maintain the single rendezvous invariant. Promotes group unity and eliminates confusion.
  - **Option B (Allow Multiple Labeled Meeting Points):** Support up to 3 simultaneous meeting points with distinct labels (*"Stage A Meetup"*, *"Camp Rendezvous"*).
- **Recommendation:** **Option A (Preserve Single Active)** for Phase 1–3. In loud, chaotic festivals, a single unambiguous meeting point is the safest and clearest experience. Sub-groups can communicate different intentions via Group Mesh Chat.
- **Questions for Human Stakeholders:**
  1. Should the single active meeting point rule remain strictly invariant, or should multi-rendezvous support be evaluated for Phase 4?

---

> **End of Product Decisions Register**  
> *Author:* Senior Product Owner & Requirements Engineer  
> *Next Document:* [Product Backlog (PRODUCT_BACKLOG.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/product/PRODUCT_BACKLOG.md)
