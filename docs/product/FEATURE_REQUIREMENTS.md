# TeeKum — Comprehensive Feature Requirements Document (FRD)

> **Document Type:** Authoritative Product & Functional Requirements Specification  
> **Target Audience:** Product Owners, System Architects, iOS Developers, and AI Coding Agents  
> **Status:** APPROVED BASELINE (Phase 3 Completed & Phase 4 Planned)  
> **Current Date:** 2026-11-04  
> **Companion Documents:**
> - [Master Agent Instructions (agent.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/agent.md)
> - [User Stories Specification (USER_STORIES.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/product/USER_STORIES.md)
> - [Product Backlog (PRODUCT_BACKLOG.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/product/PRODUCT_BACKLOG.md)
> - [Product Decisions & ADRs (PRODUCT_DECISIONS.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/product/PRODUCT_DECISIONS.md)
> - [Technical Requirements Document (docs/TechnicalRequirements.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/TechnicalRequirements.md)
> - [Knowledge Transfer Master Index (docs/knowledge_transfer/README.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/knowledge_transfer/README.md)

---

## 1. Product Vision & Principles

### 1.1 Executive Product Vision
**TeeKum** is an offline-first, peer-to-peer friend finder, tactical crowd navigation, and emergency coordination application built natively for iOS. It is engineered specifically for dense crowd environments — including music festivals, stadium concerts, sporting events, and remote wilderness gatherings — where commercial cellular infrastructure (LTE/5G) suffers catastrophic Random Access Channel (RACH) collapse and internet access is unavailable.

Rather than relying on cloud servers, cellular towers, or user accounts, TeeKum transforms participating iPhones into a decentralized, ad-hoc, multi-hop mesh network operating over **Apple Wireless Direct Link (AWDL)** and local Wi-Fi Direct interfaces via Apple’s native `Network.framework`. Every transmission — periodic location telemetry, tactical chat messages, rendezvous updates, and life-critical emergency SOS alerts — is contiguously serialized into a **compact, fixed-size 56-byte binary datagram** sealed with authenticated ChaCha20-Poly1305 encryption. Stranger devices participate in blind, zero-knowledge forwarding across multiple radio hops without possessing the cryptographic keys required to inspect coordinates, identities, or messages.

### 1.2 Core Product Principles (The 11 Invariants)
1. **Offline-First:** Core group coordination, navigation, mesh chat, and emergency alerts must never require an active internet connection, cellular tower, or central cloud backend during an active session.
2. **Pure Location Telemetry (Option B Contiguous Packing):** Routine periodic broadcast pings carry only the sender's latest geographic coordinates and sensor telemetry (battery %, compass heading, personal neon color code). Chat messages and status presets are transmitted independently via multi-hop mesh chat (`Type 0x07`).
3. **SOS is Exceptional:** Emergency SOS alerts (`Type 0x02`) bypass routine location-ping cadences, cut to the front of priority transmission queues, pre-empt all ordinary traffic, and undergo immediate bounded multi-hop mesh flooding with dedicated rate budgets.
4. **Battery-Aware Conservation:** Avoid continuous GPS polling, gratuitous peer handshakes, connection churn, duplicate relay transmissions, and runaway retries. The app targets an overall battery consumption of **<3% to 5% per hour** during typical festival usage.
5. **Privacy by Design:** Collect and retain zero historical location logs. Stranger relay nodes blindly forward encrypted envelopes without possessing the symmetric keys required to inspect attendee locations, names, or messages. All session state is strictly ephemeral and held only in memory.
6. **Honest UX & Delivery Transparency:** Always display location age (*"Last seen 4 mins ago"*), reported horizontal accuracy radius (± meters), and transparent delivery progression. Never present a cached stale coordinate as a live position, and never indicate that an alert reached a friend when only an intermediate stranger relay received it.
7. **iOS-Realistic Backgrounding:** Never assume unrestricted background execution or permanent Wi-Fi scanning. Screen-on is used for active radar navigation; locked pocket execution leverages Apple's official location status indicator (`showsBackgroundLocationIndicator = true`) and `CoreMotion` coprocessor sleep.
8. **Security Before Packet Minimization:** Never compromise cryptography to save bandwidth. All payloads are sealed with full 128-bit Poly1305 MAC tags (`ChaCha20-Poly1305` AEAD), 12-byte deterministic nonces, and complete envelope Associated Authenticated Data (AAD) tamper protection.
9. **User-Controlled Live Sharing:** Location broadcasting is governed by an explicit "Live Sharing" toggle on the main map: active while navigating or searching for friends, paused while standing still watching a stage performance. Emergency SOS broadcasting remains unconditional regardless of toggle state.
10. **Verified-Only Emergency Scope:** Group coordination and emergency siren alerts require authenticated group membership established via in-person QR barcode scanning or pre-shared serverless links. Rogue stranger packets failing Poly1305 verification are discarded cryptographically without disturbing the attendee.
11. **Radical Architectural Simplicity:** Pure MVVM with modern Swift Observation (`@Observable`), actor-isolated services, zero coordinators (no MVVM+C), zero external dependencies, and 100% native Apple SDK frameworks.

---

## 2. User Roles & Personas

| Role Name | Identifier | Description & Primary Objectives |
| :--- | :---: | :--- |
| **Group Host / Leader** | `ROLE-HOST` | Initiates the group session, establishes the cryptographic group key, and distributes invitations to friends via offline QR code or online universal link before or during an event. |
| **Festival Attendee (Member)** | `ROLE-MBR` | A member of a paired festival group who wants to know where friends are, coordinate rendezvous spots, chat across the mesh, and maintain battery life throughout an 8–12 hour event. |
| **Separated / Lost Attendee** | `ROLE-NAV` | A member physically separated in a massive crowd (>40,000 attendees) seeking to navigate directly toward a specific friend or meeting point using compass, radar, and visual cues. |
| **Distressed Member** | `ROLE-SOS` | An attendee experiencing a medical emergency, panic, crowd crush, or physical incapacitation needing immediate group rescue. |
| **Stranger Relay Node** | `ROLE-RLY` | A nearby festival attendee running TeeKum who has agreed to the Communal Mesh Compact to forward encrypted packets blindly for others, without compromising personal privacy. |
| **Watch Companion User** | `ROLE-WAT` | An attendee navigating with an Apple Watch on their wrist, relying on glanceable directional cues and discrete haptic alerts in deafening sound environments (Phase 4). |

---

## 3. Detailed Functional Requirements (FR)

### 3.1 Feature Area 1: Group Management & Serverless Pairing

- **`FR-GRP-01: Zero-Backend Group Formation`**
  - The application shall create private group sessions entirely on-device without contacting any cloud servers, external databases, or user registration services.
  - Upon tapping "Create Group", the app shall generate a cryptographically secure 256-bit symmetric encryption key using `SecRandomCopyBytes`.
  - The app shall compute a 24-bit session ID (`UInt24`, 3 bytes) derived from the cryptographic key and local CSPRNG salt.
  - The local user shall select 1 to 3 uppercase alphabetic initials ($A \dots Z$, e.g. "DNA") encoded into 2 bytes via Base-27 radix encoding (`InitialsCodec`).

- **`FR-GRP-02: Offline In-Person QR Pairing`**
  - The host device shall display a high-contrast CoreImage QR barcode encoding the universal pairing URI: `teekum://join#key=<Base64Key>&sid=<HexSID>&name=<GroupName>&color=<ColorCode>`.
  - The joiner device shall activate the rear camera via `AVCaptureSession` to scan the QR barcode directly at the venue without internet access.
  - The camera scanner shall feature an integrated screen torch toggle for scanning in dark venue environments.
  - On platforms where camera hardware is unavailable (e.g. macOS Simulator), the UI shall provide a fallback to paste the invite URI directly from the clipboard.

- **`FR-GRP-03: Serverless Universal Share Link`**
  - When internet or SMS/iMessage is available (e.g., pre-event at home or hotel), the host shall be able to share a universal link (`teekum://join#...`) via the standard iOS system share sheet.
  - All cryptographic key material shall strictly reside in the URL fragment (`#`), ensuring that symmetric keys are never transmitted over HTTP request lines or captured in web server logs (RFC 3986).

- **`FR-GRP-04: Communal Mesh Compact Consent Gate`**
  - Prior to finalizing group creation, scanning an invitation QR code, or joining via deep link, the user must be presented with the mandatory Communal Mesh Compact agreement modal (`MeshAgreementView`).
  - The agreement must clearly inform the user that joining the mesh authorizes background relaying for nearby festival attendees to preserve reciprocal crowd connectivity, and that relaying automatically suspends at 20% battery.
  - No cryptographic session key shall be written to the Keychain and no peer discovery shall commence until the user explicitly accepts the compact.

- **`FR-GRP-05: Hardware Keychain Key Storage`**
  - The active group symmetric key shall be committed immediately to the iOS Keychain under `kSecClassGenericPassword` with accessibility attribute `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
  - Symmetric keys must never be logged, printed to console, or written to unencrypted persistent storage.

- **`FR-GRP-06: Member Slot Assignment & Collision Safety`**
  - Each group member shall be assigned an 8-bit `memberSlot` ($0 \dots 7$) used for sequence number partitioning and nonces.
  - To prevent cryptographic nonce collisions (as identified in `BUG-01`), slot assignment must guarantee uniqueness among co-present active members.

- **`FR-GRP-07: Ephemeral Session Teardown & Purge`**
  - When an attendee taps "Leave Group" or the session ends, the app shall:
    1. Delete the 256-bit symmetric key from the iOS Keychain (`SecItemDelete`).
    2. Terminate all active `NWListener` and `NWConnection` sockets.
    3. Purge all in-memory neighbor tables, routing tables, and deduplication caches (`SeenPacketCache`).
    4. Wipe all ephemeral chat message history from RAM.
    5. Terminate the active Lock Screen / Dynamic Island Live Activity.
    6. Transition the root UI back to the initial `GroupPairingView`.

- **`FR-GRP-08: Maximum Group Capacity`**
  - A group session shall support up to **8 concurrent active members**. This constraint is enforced to protect AWDL radio bandwidth and eliminate TDMA slot contention.

---

### 3.2 Feature Area 2: Location Telemetry & Live Sharing

- **`FR-LOC-01: Pure Location Telemetry (Option B Contiguous Wire Format)`**
  - Routine periodic location pings shall carry pure geographic coordinates and sensor telemetry inside `LocationPingPayload` (Type `0x01`, 30 bytes encrypted).
  - The wire payload layout must strictly adhere to:
    - Bytes 0..3: `latitudeRaw` (Int32 big-endian, $\text{latitude} \times 1{,}000{,}000.0$, ~11cm resolution).
    - Bytes 4..7: `longitudeRaw` (Int32 big-endian, $\text{longitude} \times 1{,}000{,}000.0$, ~11cm resolution).
    - Bytes 8..11: `timestamp` (UInt32 big-endian, Unix epoch seconds).
    - Byte 12: `horizontalAccuracy` (UInt8, clamped $0 \dots 255$ meters).
    - Bytes 13..14: `senderInitials` (UInt16 big-endian, 2-byte Base-27 compressed initials).
    - Byte 15: `batteryLevel` (UInt8, normalized $0 \dots 100\%$).
    - Byte 16: `heading` (UInt8, quantized $0 \dots 255$ representing $0.0^\circ \dots 359.9^\circ$).
    - Byte 17: `memberColor` (UInt8, palette index $1 \dots 8$).
    - Bytes 18..29: Reserved padding (12 bytes, initialized to `0x00`), designated for Phase 4 differential barometry and floor levels.
  - Canned status codes must never be embedded inside location pings.

- **`FR-LOC-02: User-Controlled Live Sharing Master Toggle`**
  - The primary map interface shall feature a prominent "Live Sharing" toggle switch.
  - When **ON**: The app actively publishes periodic location pings according to the smart adaptive cadence.
  - When **OFF**: Location publishing is immediately halted; GPS receiver is powered down to baseline. The device continues to listen for and display inbound peer updates.
  - **Emergency SOS Override**: Triggering manual SOS or Inactivity Guard auto-SOS shall immediately broadcast emergency coordinates regardless of whether Live Sharing is ON or OFF.

- **`FR-LOC-03: Smart Adaptive Cadence (CoreMotion Optimization)`**
  - When Live Sharing is ON, the broadcasting interval shall dynamically adapt based on physical movement detected via `CMMotionActivityManager`:
    - **Moving / Navigating:** Broadcast ping every **4.0 seconds** (range 3–5s).
    - **Stationary / Resting:** Drop broadcast interval to **20.0 seconds** (range 15–30s), powering down the GPS satellite baseband to conserve battery.
    - **Distant / Degraded Link:** Accelerate broadcast interval to **2.0 seconds** when peer distance $>30\text{m}$ or direct link RSSI drops below $-75\text{ dBm}$.

- **`FR-LOC-04: Dynamic Adaptive GNSS Accuracy Profile`**
  - The location manager shall dynamically scale CoreLocation receiver accuracy via `applyDynamicAccuracy()`:
    - **Tactical Radar Active (`FinderBeaconView`):** Engage `kCLLocationAccuracyBestForNavigation` (dual-frequency L1 + L5 GNSS) and zero heading filter (`kCLHeadingFilterNone`) for sub-meter guidance.
    - **Map Overview Moving (`MainMapView`):** Set `kCLLocationAccuracyBest` with 1.0° heading filter.
    - **Stationary at Stage:** Scale down to `kCLLocationAccuracyHundredMeters` with 15.0m distance filter, saving ~70% GPS power.
    - **Festival Survival Mode (<20% Battery):** Force `kCLLocationAccuracyHundredMeters` with 25.0m distance filter and 5.0° heading filter.

- **`FR-LOC-05: Peer Facing Direction & Vision Cone on Map`**
  - Peer pins rendered on MapKit shall include a `DirectionalHeadingIndicator` comprising:
    1. A translucent 50° field-of-view vision cone (`HeadingVisionCone`) radiating from the avatar pin.
    2. A crisp directional pointer arrow (`arrowtriangle.up.fill`) on the outer rim of the avatar disk.
  - The vision cone shall dynamically rotate according to the friend's broadcast compass heading (`headingDegrees` reconstructed from Byte 16).

- **`FR-LOC-06: Personal Neon Member Color Palette`**
  - Each group member shall select one of 8 high-contrast neon palette colors (`neonGreen`, `electricCyan`, `hotPink`, `brightOrange`, `acidYellow`, `laserPurple`, `vividRed`, `iceBlue`).
  - The color code is transmitted on the wire (Byte 17) and renders as a vivid ring around friend avatar pins on the AMOLED dark map and tactical radar.
  - If unset, a deterministic color shall be assigned based on the hash of the member's initials.

- **`FR-LOC-07: Honest UX Staleness & Uncertainty Badges`**
  - The map shall clearly convey location age and uncertainty radius:
    - Peers unseen for $\ge 30\text{ seconds}$ shall display an amber staleness badge (e.g. *"Last seen 45s ago"*).
    - Peers unseen for $\ge 180\text{ seconds}$ shall dim to 40% opacity and be tagged as *"Offline"*.
    - The map shall render a translucent circle representing the true reported horizontal accuracy radius (± meters).
    - The UI must never interpolate, guess, or present a stale position as live.

- **`FR-LOC-08: Stale Peer Accelerated Cadence & AODV Probing`**
  - When any group peer's location becomes stale ($>30\text{s}$ elapsed since last update), the local device shall:
    1. Accelerate its own location broadcast cadence to 2.0s to refresh reverse routes.
    2. At 45s elapsed, initiate a reactive AODV `ROUTE_REQ` (Type `0x04`) probe.
    3. Upon receiving a probe, the target friend shall reply with `ROUTE_RESP` (Type `0x05`) accompanied by an immediate 3-ping response burst at 2.0s intervals.

- **`FR-LOC-09: AMOLED Pitch Black Dark Mode`**
  - All map overlays, background canvas views, and sheets shall utilize pure `#000000` AMOLED pitch-black backgrounds, consuming 0 mW on OLED screen pixels and saving ~35% display power outdoors.

---

### 3.3 Feature Area 3: Tactical Navigation & Spatial Finding

- **`FR-NAV-01: Festival Tactical Polar Radar (60M Forward-Up Projection)`**
  - Navigating toward friends in dense crowds shall feature a dedicated polar tactical radar interface (`RadarView`).
  - The radar disk shall represent a 60-meter circular zone with concentric range rings at 15m, 30m, and 60m, along with 24 angle ticks in 15° increments.
  - **Forward-Up Orientation:** The radar disk shall continuously rotate with device magnetometer heading (`CLHeading`), ensuring that the top of the screen ("12 o'clock") always represents the physical direction the user is facing in the crowd.

- **`FR-NAV-02: 60-Meter Perimeter Clamping`**
  - Group members located beyond 60.0 meters shall not disappear from view; they shall be clamped to the outer rim of the radar disk along their relative bearing.
  - Clamped blips shall display an outward-pointing chevron arrow and a prominent metric distance badge (e.g. *"142m"*), guaranteeing uninterrupted spatial awareness.

- **`FR-NAV-03: Dual Selection Interaction & Clock Guidance`**
  - The user can select a target friend by tapping their blip on the radar disk or swiping through the bottom friend card carousel deck (`RadarFriendCard`).
  - Selecting a friend draws a glowing cyan targeting vector line from the center marker to the blip.
  - The HUD banner shall display real-time relative clock guidance (*"Ahead"*, *"1 o'clock"*, *"9 o'clock"*), distance in meters, battery %, and staleness.

- **`FR-NAV-04: Apple U1/U2 Ultra-Wideband Precision Finding (<8 Meters)`**
  - When the user approaches within ~5–8 meters of a selected friend, the interface shall support transition to Apple NearbyInteraction (UWB) precision finding (`PrecisionFindingOverlay`).
  - UWB discovery tokens (~297 bytes) shall be exchanged out-of-band across the mesh using 25-byte fragments inside Type `0x08` packets (`UWBTokenExchangePayload`), strictly limited to direct 1-hop delivery (`uwbHopLimit = 1`).
  - The active UWB session shall render an AirTag-style 3D directional guidance arrow (`simd_float3`), centimeter-level distance readout, coaching hints (*"Move closer"*, *"Facing target"*), and rhythmic distance-scaled haptic pulses.
  - Idle UWB sessions shall automatically time out after 30 seconds of inactivity to protect battery life.

- **`FR-NAV-05: Sensor Simulation Fallback for Non-UWB Hardware`**
  - On hardware lacking Apple U1/U2 chips (e.g. iPhone SE, iPad, or iOS Simulator), the application shall automatically fall back to sensor-assisted navigation (`NearbyInteractionService.swift`).
  - Relative distance shall be derived from GNSS coordinates, and relative angle shall be computed from magnetometer heading deltas, driving the exact same directional UI seamlessly.

- **`FR-NAV-06: Visual Finder Beacon (Screen Strobe Torch)`**
  - The navigation view shall provide a 1-tap "Strobe" button that converts the entire iPhone display into a high-visibility, high-contrast flashing neon beacon to wave above the crowd.
  - The strobe view shall support synchronizing with the rear camera LED torch (continuous, 1 Hz pulse, 4 Hz fast strobe, SOS Morse code).
  - The torch strobe shall automatically time out after 60 seconds to prevent thermal load and excessive battery drain.

---

### 3.4 Feature Area 4: Single Active Meeting Point & Setter Lock Rule

- **`FR-MTG-01: Single Active Meeting Point Invariant`**
  - A group session shall have strictly **ONE active meeting point** at any given moment.
  - Multiple concurrent meeting points are explicitly prohibited to eliminate conflicting group instructions in chaotic festival environments.

- **`FR-MTG-02: Proposing a Meeting Point`**
  - Any group member may propose an initial meeting point by long-pressing a coordinate on `MainMapView` or tapping "Set Meeting Point".
  - The proposer selects a scheduled meetup time via quick preset chips (*"Right Now"*, *"In 15m"*, *"In 30m"*, *"In 1h"*) or a custom time picker.
  - The meeting point is assigned a dynamic title based on the proposer's initials and scheduled time (e.g. *"DNA's Meetup • 10:30 PM (in 15m)"*).
  - The proposal is serialized into a 30-byte `MeetingUpdatePayload` (Type `0x03`) and flooded across the mesh with `hopLimit = 15`.

- **`FR-MTG-03: Setter Lock Rule Enforcement`**
  - Upon broadcast of a meeting point, the proposer becomes the authoritative **Setter** (`setterInitials` / `setterSlot`).
  - **Setter Privileges:** The Setter possesses exclusive authority to:
    1. Update the rendezvous location coordinates.
    2. Adjust the scheduled meetup time.
    3. Unset (cancel) the meeting point.
  - **Non-Setter Constraints:** While an active meeting point exists:
    1. Non-setters are strictly locked out from proposing new meeting points or modifying the existing one.
    2. Long-pressing the map by a non-setter shall trigger an alert haptic and display a locked toast: *"Only [Setter] can unset or change the active rendezvous"*.
    3. Meeting proposal sheets shall render in locked read-only state with disabled broadcast buttons for non-setters.
    4. Inbound mesh proposal or cancellation packets (Type `0x03`) originating from any node other than the authoritative Setter shall be dropped by the protocol engine (`applyInboundUpdate`).

- **`FR-MTG-04: One-Tap Attendance Synchronization (RSVP)`**
  - Non-setter members shall interact with the active meeting point strictly through 1-tap RSVP confirmations:
    - *"I'll be there"* (`attendanceState = .attending`).
    - *"Can't make it"* (`attendanceState = .declined`).
  - Attendance state is shared across group peers via ACK packets (`Type 0x06`) or meeting status tallies, rendering live attendance avatars on the meeting card.

- **`FR-MTG-05: 25-Meter Proximity Auto-Arrival Geofencing`**
  - When an attendee physically walks within **25.0 meters** of the active rendezvous coordinates, their attendance state shall automatically transition to *"Arrived"* (`attendanceState = .atMeetingPoint`).
  - The app shall display a haptic notification welcoming the user to the meeting point.

- **`FR-MTG-06: 1-Hour Auto-Expiration Cutoff`**
  - An active meeting point shall automatically expire and clear from the map **3,600 seconds (1 hour)** after the scheduled meetup time, preventing obsolete rendezvous clutter.
  - Upon auto-expiration, the Setter Lock releases, allowing any group member to establish a fresh meeting point.

---

### 3.5 Feature Area 5: Festival Group Mesh Chat & Quick Preset Chips

- **`FR-CHT-01: Dedicated 56-Byte Mesh Chat Datagram (Type 0x07)`**
  - Offline text communication shall be transmitted via a dedicated packet type: `PacketType.chatMessage = 0x07`.
  - The 30-byte encrypted payload layout must strictly adhere to:
    - Bytes 0..1: `senderInitials` (UInt16 big-endian, 2-byte Base-27 compressed initials).
    - Bytes 2..5: `timestamp` (UInt32 big-endian Unix epoch seconds).
    - Bytes 6..7: `messageId` (UInt16 big-endian unique per-message identifier).
    - Byte 8: `recipientSlot` (UInt8, `0xFF` for broadcast to all group members, or $0 \dots 7$ for unicast).
    - Byte 9: `textLength` (UInt8, clamped $0 \dots 20$).
    - Bytes 10..29: `textData` (20 bytes UTF-8 encoded text, zero-padded at tail).

- **`FR-CHT-02: Strict 20-Byte Text Limit & ByteMeterView`**
  - The text input field in `ChatSheetView` shall enforce a hard boundary of **maximum 20 UTF-8 bytes**.
  - A real-time `ByteMeterView` indicator shall display current byte consumption (`X / 20 B`) with dynamic color coding:
    - Green: $\le 14$ bytes.
    - Orange: $15 \dots 19$ bytes.
    - Red: 20 bytes (input clamped; typing/pasting blocked beyond 20 bytes).
  - Multi-byte characters (emojis, accented characters) must be measured by their true UTF-8 byte count, preventing half-character slicing.

- **`FR-CHT-03: Quick-Tap Festival Preset Chips`**
  - To enable fast, one-handed communication in loud, jostling festival crowds, the chat sheet shall feature 6 pre-validated quick preset chips:
    1. *"Beer line"* (9 bytes)
    2. *"At Main Stage"* (13 bytes)
    3. *"Restroom"* (8 bytes)
    4. *"Where are you?"* (14 bytes)
    5. *"On my way"* (9 bytes)
    6. *"Lost"* (4 bytes)
  - Tapping a preset chip immediately populates and transmits the message across the mesh.

- **`FR-CHT-04: Transparent Per-Recipient Delivery State Machine`**
  - Every sent chat message shall display an honest delivery state indicator:
    - `locallyAccepted`: Enqueued in outbox queue.
    - `forwardedToNextHop`: Transmitted to immediate neighbor node over AWDL.
    - `relayedByMesh`: Confirmed relayed by an intermediate mesh hop (`ACKPayload` Type `0x06` status `0x02`).
    - `deliveredToRecipient`: Confirmed received by recipient friend device (`ACKPayload` status `0x01`).
    - `deliveryTimedOut`: Unconfirmed after 2 retries and 15.0 seconds.
  - Broadcast messages shall render per-recipient breakdown pills (e.g. *"Delivered to 3/3"* or *"Delivered to 2/3"*).

- **`FR-CHT-05: Jittered Acknowledgments & Anti-Collision Backoff`**
  - When receiving a chat message, the recipient device shall return an `ACKPayload` (Type `0x06`).
  - To prevent synchronized radio packet collisions when multiple group members receive a broadcast message simultaneously, ACKs must introduce randomized transmission jitter ($0.0 \dots 0.35$ seconds).
  - Senders shall support up to 2 retransmissions with exponential backoff (0.5s initial delay, 1.5x multiplier).

- **`FR-CHT-06: Ephemeral In-Memory Chat History (Max 50 Messages)`**
  - The application shall retain up to **50 recent chat messages** in volatile memory (`maxHistory = 50`).
  - Chat history must **never be written to disk** (zero SQLite, zero CoreData, zero UserDefaults).
  - All chat messages shall be permanently purged from RAM upon leaving the group session.

- **`FR-CHT-07: Anti-Spam Cooldown & Survival Mode Suspension`**
  - The chat interface shall enforce an anti-spam cooldown of **3.0 seconds** between outgoing messages.
  - If device battery drops below 20% (Festival Survival Mode), outgoing chat transmission shall be disabled to preserve power for emergency SOS.

---

### 3.6 Feature Area 6: Emergency SOS & Inactivity Guard Watchdog

- **`FR-EMG-01: Manual SOS Trigger (3-Second Continuous Hold)`**
  - The SOS button (`SOSButtonView`) shall require an uninterrupted **3.0-second continuous press-and-hold** to trigger emergency dispatch.
  - The button shall render an animated circular progress ring filling over 3 seconds, accompanied by escalating haptic pulses every 0.5s.
  - Releasing the button prior to 3.0 seconds shall immediately cancel activation, preventing accidental pocket misfires while dancing.

- **`FR-EMG-02: Urgent Transmission Preemption & Extended Hop Budget`**
  - Triggering SOS shall immediately synthesize an `SOSPayload` (Type `0x02`, `emergencyType = 0x01` manual).
  - The packet shall insert into the head-of-line Tier 1 urgent lane in `PriorityOutboxQueue`, preempting all ordinary location pings and chat messages.
  - The packet shall flood the mesh with an extended `hopLimit = 15` to maximize penetration through dense crowd obstacles.
  - The rate limiter shall grant emergency traffic a dedicated burst capacity of up to **4.0 packets/second**.

- **`FR-EMG-03: Acoustic Siren & CoreHaptics Alarm`**
  - Upon receiving an authenticated SOS packet matching the group's key, the receiver device shall:
    1. Synthesize an alternating two-tone square wave siren via `AVAudioEngine` at maximum system volume, designed to pierce 100+ dB concert sound environments.
    2. Trigger continuous high-intensity vibration loops via `CoreHaptics`.
    3. Display a prominent full-screen crimson distress alert banner (`IncomingSOSAlertBannerView`) showing sender initials, distance, and relative bearing.
  - The receiver shall track 32-bit `sosEventId` to prevent triggering duplicate sirens for the same emergency incident.

- **`FR-EMG-04: Rogue Stranger Packet Dropping`**
  - Intermediate stranger nodes forward SOS packets blindly without decrypting them.
  - However, an incoming SOS packet must pass full ChaCha20-Poly1305 MAC tag verification using the local group's symmetric key before triggering audio sirens or haptics.
  - Stranger packets or corrupted datagrams must be silently dropped, preventing crowd panics or griefing attacks.

- **`FR-EMG-05: Autonomous "Man Down" Inactivity Guard Watchdog`**
  - The application shall include an autonomous motion-monitoring background watchdog (`InactivityGuardService`).
  - **Opt-In Requirement:** The watchdog shall be disabled by default and require explicit user opt-in.
  - **Stillness Detection:** Samples `CMMotionManager.accelerometerData` at 10 Hz. If acceleration vector magnitude variance remains $< 0.15g$ and zero screen touches occur for **180 seconds (3 minutes)**, the device enters the pre-alarm warning state.

- **`FR-EMG-06: 30-Second Pre-Alarm Warning Countdown`**
  - Upon detecting 3 minutes of immobility, the app shall present a full-screen warning modal: *"Are you okay? Auto-SOS in 30s"*.
  - The warning state shall execute silent, escalating haptic vibration pulses and visual flashing for **30 seconds**.
  - **Cancellation:** The user may dismiss the alarm by tapping "I'M OK" or simply picking up / moving the phone (detected via motion threshold $>0.15g$).
  - **Automatic Dispatch:** If no user action or movement occurs within 30 seconds, the app shall automatically broadcast an authenticated emergency SOS packet with `emergencyType = 0x04` (`inactivity`).
  - Receiving peers shall visually distinguish the alert as *"Inactivity / Man Down Alert"*.

- **`FR-EMG-07: Honest SOS Delivery Feedback`**
  - The sender's screen shall display transparent SOS delivery progression:
    - `localSending`: Enqueued locally.
    - `searchingPeers`: Actively broadcasting over AWDL radio.
    - `relayedAck`: Confirmed relayed by at least one intermediate mesh hop.
    - `deliveredToFriend`: Confirmed received by a group friend device via return ACK.
  - The UI must never display "Delivered" until an authenticated friend ACK arrives.

- **`FR-EMG-08: SOS Cancellation Workflow`**
  - The distressed attendee shall be able to cancel an active SOS alert by tapping "Cancel SOS" and entering a 1-second confirmation press.
  - A cancellation packet (`emergencyType = 0x00`) shall be flooded across the mesh, silencing audio sirens on group members' devices.

---

### 3.7 Feature Area 7: Mesh Networking & Blind Stranger Relaying

- **`FR-MSH-01: Invariant 56-Byte Wire Datagram Standard`**
  - All communication over peer-to-peer radio shall strictly conform to a fixed **56-byte wire datagram**:
    - **Bytes 0..9 (10B Cleartext Envelope):**
      - Byte 0: `versionAndType` (4 bits version `0x03` | 4 bits packet type $0x01 \dots 0x08$).
      - Byte 1: `hopLimit` (UInt8, $1 \dots 15$, immutable, sealed in AAD).
      - Byte 2: `hopCount` (UInt8, mutable, incremented per relay, masked to `0x00` in AAD).
      - Bytes 3..5: `sessionId` (UInt24 big-endian session identifier).
      - Bytes 6..9: `sequenceNumber` (UInt32 big-endian, partitioned: 8-bit `memberSlot` + 24-bit counter).
    - **Bytes 10..39 (30B Encrypted Payload):** Ciphertext sealed with ChaCha20 symmetric stream cipher.
    - **Bytes 40..55 (16B Poly1305 Auth Tag):** 128-bit MAC tag verifying payload ciphertext and envelope AAD.

- **`FR-MSH-02: Zero-Knowledge Blind Relaying`**
  - Devices participating in the mesh shall relay encrypted packets for other festival attendees without possessing their group keys (`PacketForwarder.swift`).
  - Relay nodes shall inspect only the 10-byte cleartext envelope to check `sessionId`, `sequenceNumber`, and `hopCount`.
  - Relay nodes cannot decrypt the 30-byte payload containing coordinates, chat, or identities.
  - To allow relays to mutate `hopCount` without breaking cryptographic integrity, the sender computes the Poly1305 MAC over Associated Authenticated Data (AAD) with Byte 2 (`hopCount`) masked to `0x00`.

- **`FR-MSH-03: Multi-Hop Forwarding & Ceiling Enforcement`**
  - Upon receiving a packet:
    1. If `hopCount >= hopLimit`, the packet shall be discarded immediately.
    2. If `hopCount < hopLimit`, the relay shall increment `hopCount` by 1 and enqueue the packet for retransmission.
  - Standard packets (location pings, chat) shall enforce a maximum budget of **8 hops**.
  - Emergency SOS packets shall enforce a maximum budget of **15 hops**.

- **`FR-MSH-04: SeenPacketCache 1,024-Entry Deduplication`**
  - To eliminate circular forwarding loops and mesh broadcast storms, every node shall maintain an actor-isolated LRU deduplication cache (`SeenPacketCache`).
  - The cache shall index a compact 7-byte composite key: `(sessionId: 3B, sequenceNumber: 4B)`.
  - The mutable `hopCount` must be excluded from the key, ensuring identical identity across all hops.
  - The cache shall hold up to **1,024 entries** with a sliding Time-To-Live (TTL) of **300.0 seconds (5 minutes)**. Duplicate packets must be dropped immediately.

- **`FR-MSH-05: Dual-Lane Token Bucket Rate Limiter`**
  - Outgoing forwarded mesh traffic shall be traffic-shaped through a dual-lane token bucket limiter (`ForwardingRateLimiter`):
    - **Ordinary Relay Lane:** Rate = **2.0 pkts/sec**, Burst Capacity = **4.0 tokens** (used for routine location pings and chat).
    - **Urgent SOS Lane:** Rate = **4.0 pkts/sec**, Burst Capacity = **8.0 tokens** (reserved exclusively for emergency SOS and rendezvous updates).
  - Forwarded packets exceeding bucket capacity shall be dropped from the relay head.

- **`FR-MSH-06: Bonjour Service Discovery & Peering Policy`**
  - Devices shall advertise and discover peers over Apple Wireless Direct Link (AWDL) using Bonjour service type `_teekum._tcp`.
  - Bonjour TXT records shall broadcast a `relay: 1/0` flag indicating whether the node is currently accepting stranger relay traffic.
  - **Peering Rule:**
    - Devices with matching `sessionId` always peer.
    - Stranger devices peer only if both devices have relaying enabled and battery $\ge 20\%$.
  - The neighbor table shall maintain up to **8 direct active TCP connections** (64 known peers), pruning inactive links after 6.0 seconds of silence.
  - Symmetric connection tie-breaking (`localPeerId < remotePeerId`) shall resolve simultaneous bidirectional connection attempts.

- **`FR-MSH-07: AODV Reactive Route Discovery Engine`**
  - For directed point-to-point queries when direct contact is lost:
    - Node broadcasts a Route Request (`ROUTE_REQ` Type `0x04`).
    - Intermediate nodes cache reverse paths (15.0s TTL).
    - Destination replies with a unicast Route Reply (`ROUTE_RESP` Type `0x05`).
    - Confirmed routes are cached in `RoutingTable` with a 30.0s TTL up to 8 hops.

- **`FR-MSH-08: Stream Message Framing & Resynchronization`**
  - Because TCP is a continuous byte stream, `StreamMessageFramer` shall prepend a 2-byte magic header `0x544B` ("TK") to every 56-byte datagram on the wire (58-byte stream frame).
  - The framer shall handle TCP chunk fragmentation, buffer partial reads, extract complete 56-byte datagrams, and resynchronize upon encountering stream corruption.

- **`FR-MSH-09: Communal Relay Policy Modes`**
  - Users shall have 3 selectable relay modes in `RelaySettingsSheet`:
    1. **Always Active:** Continuously forwards stranger traffic while battery $\ge 20\%$.
    2. **Timed 30 Min:** Forwards stranger traffic for 30 minutes, then automatically transitions to Disabled.
    3. **Disabled:** Forwards group traffic only; strictly refuses stranger relaying.

---

### 3.8 Feature Area 8: Battery Governance & Festival Survival Mode

- **`FR-BAT-01: 8-Hour Festival Battery Consumption Budget`**
  - The application shall target an overall battery drain of **<3% to 5% per hour** under standard festival operating conditions:
    - ~80% of time in pocket / resting: ~0.3% to 0.5% / hr.
    - ~20% of time active screen navigation: ~6% to 7% / hr.
    - Stranger relaying (when active): ~0.5% / hr.
  - Expected total battery consumption over an 8-hour event: **~15% to 18%**.

- **`FR-BAT-02: Motion-Aware GPS Baseband Sleep (CoreMotion)`**
  - The app shall continuously query `CMMotionActivityManager`.
  - When the attendee is stationary (standing still watching a stage, resting, or dancing in place), CoreLocation GPS hardware shall power down or throttle to low-power coarse updates, saving ~70% GPS battery.
  - Walking or running shall automatically wake high-accuracy GPS within 2 seconds.

- **`FR-BAT-03: Hard 20% Cutoff (Festival Survival Mode)`**
  - The app shall monitor `UIDevice.current.batteryLevel`.
  - The moment battery level drops below **20%** (or the user enables iOS Low Power Mode):
    1. **Terminate Stranger Relaying:** Instantly close stranger AWDL connections and purge relay queues.
    2. **Terminate Background Location Indicator:** Dismantle the persistent background session to stop socket listening.
    3. **Throttle GPS:** Drop location checks to once every 60–120 seconds or strictly on-demand.
    4. **Suspend Chat:** Disable outgoing mesh chat transmissions.
    5. **Preserve Life Safety:** Reserve remaining battery strictly for receiving emergency SOS alerts and viewing the cached offline meeting map.

- **`FR-BAT-04: Micro-Burst Radio Duty-Cycling`**
  - AWDL packet transmissions shall complete in $<1\text{ ms}$, allowing CPU and radio basebands to return immediately to low-power deep sleep states (C-states).

- **`FR-BAT-05: Coalescing Priority Outbox Queue`**
  - Normal periodic location pings in `PriorityOutboxQueue` shall coalesce: a new GPS fix immediately overwrites an unsent older fix in the outbox queue, preventing obsolete coordinate backlog.

- **`FR-BAT-06: Centralized Configuration Architecture (`TeeKumConfiguration.swift`)`**
  - All tuneable timings, broadcast cadences, rate limits, retry counts, and battery thresholds shall reside in `TeeKumConfiguration.swift`, enabling field tuning without touching networking or UI services.

---

### 3.9 Feature Area 9: ActivityKit Live Activity & Background Execution

- **`FR-BG-01: Active Background Session via Status Indicator`**
  - To prevent iOS from suspending `Network.framework` sockets and terminating AWDL mesh relaying while the iPhone is locked in a pocket, the app shall configure `showsBackgroundLocationIndicator = true` and `allowsBackgroundLocationUpdates = true` on `CLLocationManager`.
  - Apple's official blue location status indicator / Dynamic Island pill grants the app continuous background execution privileges.
  - GPS hardware remains asleep via `CoreMotion` when stationary; radio sockets wake up for $<1\text{ms}$ per packet relay.

- **`FR-BG-02: ActivityKit Dynamic Island Companion`**
  - When a group session is active, the app shall present a Live Activity (`SessionActivityWidget`) supporting all 4 Dynamic Island layouts:
    - `compactLeading`: Displays session name and member count pill.
    - `compactTrailing`: Displays closest friend distance (e.g. *"34m"*).
    - `minimal`: Renders animated mesh pulse dot.
    - `expanded`: Renders full telemetry HUD with closest friend initials, bearing arrow, active meeting countdown, and relay status toggle.

- **`FR-BG-03: Lock Screen Live Activity Controls`**
  - The Lock Screen Live Activity widget shall display:
    1. Group session name and active peer count.
    2. Closest friend name, distance, and bearing.
    3. Active meeting point title and countdown timer.
    4. 1-tap interactive deep-link buttons: "Locate Friend", "Meeting Point", and "Toggle Relay".

- **`FR-BG-04: Background SOS Alert Delivery`**
  - When an incoming emergency SOS datagram is received while the phone is locked, the background process shall:
    1. Wake the screen and trigger local system notifications via `UNUserNotificationCenter`.
    2. Fire high-intensity acoustic audio sirens and haptics via `SOSAudioAlert`.
    3. Update the Live Activity banner with emergency crimson alert styling.

- **`FR-BG-05: Background Pre-Permission Primers`**
  - The app shall present informative pre-permission education screens *before* triggering Apple system dialogs for Location ("Always"), Local Network, and Bluetooth, preventing irreversible accidental "Don't Allow" taps.

---

### 3.10 Feature Area 10: On-Device Diagnostics & Simulation Lab

- **`FR-DBG-01: On-Device Debug HUD Sheet (`DiagnosticsView`)`**
  - Accessible via a discrete gesture on the map, the Debug HUD shall display:
    - Real-time peer signal strength (RSSI in dBm) for all connected AWDL neighbors.
    - Active peer count, packets sent, packets received, packets dropped.
    - True CoreLocation GPS accuracy (± meters) and measurement age.
    - Active cryptographic key fingerprint (SHA-256 truncated hex).

- **`FR-DBG-02: 1-Tap Automated Triage Health Audit`**
  - The Mesh Debugger (`MeshDebuggerView`) shall provide an automated 1-tap triage health check that audits:
    1. Bluetooth & AWDL radio hardware state.
    2. CoreLocation authorization status.
    3. Battery level and Survival Mode state.
    4. Group session validity and Keychain key presence.
    5. CryptoKit ChaChaPoly encryption readiness.
  - Each subsystem shall display a clear Pass / Warn / Fail badge.

- **`FR-DBG-03: Live 56-Byte Packet Stream & Bitfield Inspector`**
  - The debugger shall maintain a rolling log of all inbound, outbound, and relayed 56-byte datagrams.
  - Users can filter by packet type (`LocationPing`, `SOS`, `Meeting`, `RouteReq`, `RouteResp`, `ACK`, `Chat`, `UWB`, `Dropped`).
  - Tapping a packet renders an interactive visual breakdown of the 10-byte cleartext envelope, 30-byte payload, and 16-byte Poly1305 MAC tag.

- **`FR-DBG-04: Synthetic Packet Injector`**
  - The debugger shall allow developers to inject synthetic frames directly into the radio pipeline:
    - Valid location pings with custom coordinates.
    - Manual emergency SOS alerts.
    - Fault-injection packets: corrupted Poly1305 MAC tags, sequence number replays, or oversized payloads to verify security filters.

- **`FR-DBG-05: Virtual Multi-Node Topology Sandbox`**
  - The app shall include an in-memory mesh topology simulator (`MeshTopologySimulator`) capable of simulating 3-node and 4-node topologies (e.g. Alice $\leftrightarrow$ Relay $\leftrightarrow$ Bob).
  - Developers can dynamically simulate radio link breaks, node failures, and battery drops to observe real-time AODV route discovery and convergence without needing multiple physical iPhones.

- **`FR-DBG-06: Telemetry JSON Export`**
  - Diagnostic logs and mesh performance counters shall be exportable as JSON via the standard iOS `ShareLink` for post-event analysis.

---

### 3.11 Feature Area 11: Apple Watch Companion App (`TeeKumWatch`, Planned Phase 4)

- **`FR-WAT-01: Tethered Companion Architecture (`WCSession`)`**
  - The Apple Watch application (`TeeKumWatch`) shall operate strictly as a tethered companion extension communicating with the host iPhone via `WatchConnectivity` (`WCSession`).
  - Standalone mesh node execution on watchOS is explicitly prohibited to preserve watch battery and adhere to Apple ad-hoc networking boundaries.

- **`FR-WAT-02: High-Intensity Wrist Taptic Siren for SOS`**
  - In response to an incoming group emergency SOS alert, the watch shall trigger persistent, high-intensity wrist haptic patterns (`WKHapticType.failure` / `.stop`) to penetrate 100+ dB concert sound environments.

- **`FR-WAT-03: Discrete 3-Second Wrist SOS Trigger`**
  - The watch interface shall feature a 3-second continuous hold emergency SOS button on the wrist.
  - Firing the wrist SOS commands the host iPhone via `WCSession.sendMessage` to dispatch an urgent SOS packet across the mesh immediately.

- **`FR-WAT-04: Heads-Up Wrist Compass & Directional Navigation`**
  - When actively navigating toward a friend, the watch shall render a heads-up compass disk showing relative bearing arrow, metric distance, and facing alignment haptics.
  - Coordinate streaming from iPhone to watch shall be strictly gated to active on-screen watch navigation sessions.

- **`FR-WAT-05: 1-Tap Meeting Point RSVP Cards`**
  - Active meeting point proposals shall surface on the watch as glanceable cards with 1-tap RSVP buttons (*"On my way"*, *"Can't make it"*), synced back to the iPhone via `updateApplicationContext`.

- **`FR-WAT-06: watchOS Smart Stack Integration`**
  - The watch shall mirror active session status in the watchOS Smart Stack leveraging existing `TeeKumWidgets` Live Activity attributes.

---

### 3.12 Feature Area 12: Multi-Floor & Differential Barometric Elevation (Planned Phase 4)

- **`FR-ALT-01: Wire Format Allocation for Elevation Telemetry`**
  - The 12 reserved bytes (Bytes 18..29) of `LocationPingPayload` shall allocate 3 bytes for elevation:
    - Byte 18: `floorLevel: Int8` (signed integer, range $-128 \dots +126$; `0x7F` = Auto/Unknown).
    - Bytes 19..20: `barometricPressure: UInt16` (centi-hPa: $(\text{hPa} - 800) \times 100$, ~8cm resolution).
    - Bytes 21..29: 9 bytes reserved padding (initialized to `0x00`).
  - This preserves the invariant 56-byte wire datagram format.

- **`FR-ALT-02: Peer-to-Peer Differential Barometry`**
  - The application shall sample ambient air pressure via `CMAltimeter`.
  - Relative vertical separation between two co-located attendees shall be computed using the barometric differential formula:
    $$\Delta h \approx 8.43 \times \Delta P \text{ (meters)}$$
  - Differential comparison between co-located phones cancels out regional atmospheric weather pressure shifts without requiring cloud weather servers or Apple IMDF indoor maps.

- **`FR-ALT-03: Moving Median Pressure Filter`**
  - Barometric samples shall pass through a 5-sample moving median filter to reject HVAC pressure surges and elevator drafts.

- **`FR-ALT-04: 2D Map Floor Switcher Filter`**
  - `MainMapView` shall render a multi-floor selector pill (`All`, `B1`, `L1`, `L2`, `L3`).
  - Friends located on different vertical levels shall display dimmed avatar pins tagged with vertical floor delta badges (e.g. *"+2 Floors"*).

- **`FR-ALT-05: Vertical Arrival Warning in Tactical Radar`**
  - When horizontal distance is $< 10\text{ meters}$ but vertical separation is $\ge 3.0\text{ meters}$, `FinderBeaconView` and `RadarView` shall display a prominent elevation warning (*"Target Above on Level 2 — Take Stairs"*), preventing "0-meter arrival" confusion.

- **`FR-ALT-06: Manual Floor Override Selection`**
  - In venues where barometric pressure is unavailable or uncalibrated, users shall be able to manually select their current floor level from a picker sheet, which overrides the broadcast `floorLevel` byte.

---

## 4. Non-Functional Requirements (NFR)

### 4.1 Performance & Latency
- **`NFR-PERF-01: Sub-Millisecond Frame Processing`**
  - Cleartext envelope inspection, LRU cache lookup, and forwarding decisions must execute in $<1.0\text{ ms}$ per packet on iPhone 12 or newer hardware.
- **`NFR-PERF-02: UI Responsiveness`**
  - Tactical radar rotation and map pin animations must maintain a smooth 60 FPS refresh rate.
  - Text input in `ChatSheetView` must update `ByteMeterView` with zero detectable keystroke lag ($<16\text{ ms}$).
- **`NFR-PERF-03: Multi-Hop Propagation Latency`**
  - Emergency SOS alerts must propagate across 3 intermediate mesh hops in $<350\text{ ms}$ over clear AWDL links.

### 4.2 Battery & Resource Consumption
- **`NFR-BAT-01: Strict Hourly Battery Budget`**
  - The app must consume no more than **3.0% to 5.0% battery per hour** during typical festival usage (idle pocket monitoring with periodic navigation).
- **`NFR-BAT-02: Instant Survival Mode Enforcement`**
  - At 20% battery or Low Power Mode, all stranger packet relaying, background socket listening, and non-essential GPS polling must cease within 500 ms.
- **`NFR-BAT-03: Memory Footprint Ceiling`**
  - Total resident RAM usage of the primary app target must remain below **60 MB** during extended 8-hour sessions.

### 4.3 Security & Cryptographic Integrity
- **`NFR-SEC-01: Authenticated Encryption (AEAD)`**
  - All sensitive payloads must be encrypted with standard RFC 8439 ChaCha20-Poly1305. Custom or unauthenticated encryption algorithms are strictly prohibited.
- **`NFR-SEC-02: Envelope AAD Binding`**
  - The 128-bit Poly1305 MAC tag must cover envelope Associated Authenticated Data with `hopCount` masked to `0x00`, preventing envelope tampering while allowing legitimate hop increments.
- **`NFR-SEC-03: Secure Hardware Key Storage`**
  - Session symmetric keys must be stored in the iOS Keychain with device-unlock accessibility. Keys must never touch unencrypted files or logging streams.

### 4.4 Privacy & Anonymity
- **`NFR-PRIV-01: Zero Persistent Location History`**
  - The app shall not persist any historical coordinate traces to disk. All friend positions are strictly in-memory and wiped on session teardown.
- **`NFR-PRIV-02: URL Fragment Privacy Guard`**
  - Symmetric keys in shareable universal links must be placed after the `#` fragment identifier, ensuring keys are never transmitted across HTTP proxy headers.
- **`NFR-PRIV-03: Pseudonymous Wire Identity`**
  - Users are identified on the wire solely by 2-byte Base-27 compressed initials. Real names, phone numbers, and device IDs are never transmitted.

### 4.5 Engineering & Architectural Quality
- **`NFR-ENG-01: Zero External Dependencies`**
  - The codebase must import only first-party Apple SDK frameworks (`Network`, `CoreLocation`, `CoreMotion`, `CryptoKit`, `NearbyInteraction`, `MapKit`, `ActivityKit`, `AVFoundation`, `SwiftUI`). No third-party package managers or pods.
- **`NFR-ENG-02: Pure MVVM Architecture`**
  - Pure MVVM with modern Swift Observation (`@Observable`). No UIKit window coordinators (no MVVM+C).
- **`NFR-ENG-03: Strict Actor Isolation & Concurrency`**
  - UI components reside on `@MainActor`. All radio networking, cryptographic operations, routing tables, and packet caches reside in isolated Swift `actor`s. Zero legacy locks or dispatch semaphores inside actors.
- **`NFR-ENG-04: Automated Regression Quality Gate`**
  - All 18 automated test suites (220+ tests) must pass with a 100% pass rate before any release or milestone completion.

---

> **End of Feature Requirements Document**  
> *Author:* Senior Product Owner & Requirements Engineer  
> *Next Document:* [User Stories Specification (USER_STORIES.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/product/USER_STORIES.md)
