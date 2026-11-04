# TeeKum — Comprehensive User Stories Specification

> **Document Type:** Authoritative User Story Catalog & Acceptance Criteria  
> **Target Audience:** Product Owners, QA Engineers, iOS Developers, and AI Coding Agents  
> **Status:** APPROVED BASELINE (Phase 1–3 Implemented, Phase 4 Planned)  
> **Verification Baseline:** 18 Automated Test Suites / 220 Tests Passed (100% Pass Rate)  
> **Companion Documents:**
> - [Feature Requirements Document (FEATURE_REQUIREMENTS.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/product/FEATURE_REQUIREMENTS.md)
> - [Product Backlog (PRODUCT_BACKLOG.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/product/PRODUCT_BACKLOG.md)
> - [Product Decisions & ADRs (PRODUCT_DECISIONS.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/product/PRODUCT_DECISIONS.md)
> - [Master Agent Instructions (agent.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/agent.md)
> - [Technical Requirements Document (docs/TechnicalRequirements.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/TechnicalRequirements.md)

---

## 1. User Story Taxonomy & Governance

Every user story in this document is constructed according to the canonical user story format:
$$\textbf{As a [user role], I want [capability], so that [benefit].}$$

Each story contains:
1. **Story Information:** Unique Story ID, Feature Area, User Role, User Story, User Benefit, Priority (`Critical`, `High`, `Medium`, `Low`), Status (`Implemented`, `Approved`, `In Progress`, `Planned`, `Blocked`, `Deferred`), and Target Phase.
2. **Acceptance Criteria:** Observable behavior specified using `Given / When / Then` scenarios.
3. **Edge Cases:** Specific environmental, radio, power, or session edge conditions.
4. **Dependencies:** Related stories, required actors/services, platform frameworks, wire packet types, and UI components.
5. **Verification Protocol:** Concrete unit, integration, UI, simulator, and physical device test procedures.

---

## 2. Summary Matrix by Phase & Feature Area

| Story ID | Feature Area | User Role | Priority | Status | Target Phase | Summary Title |
| :---: | :--- | :---: | :---: | :---: | :---: | :--- |
| `US-GRP-01` | Group Management | `ROLE-HOST` | `Critical` | `Implemented` | Phase 1 | Serverless Group Formation & Key Generation |
| `US-GRP-02` | Group Management | `ROLE-MBR` | `Critical` | `Implemented` | Phase 1 | Offline In-Person QR Barcode Pairing |
| `US-GRP-03` | Group Management | `ROLE-HOST` | `High` | `Implemented` | Phase 1 | Serverless Universal Link Invite Sharing |
| `US-GRP-04` | Group Management | `ROLE-MBR` | `Critical` | `Implemented` | Phase 2 | Communal Mesh Compact Consent Gating |
| `US-GRP-05` | Group Management | `ROLE-MBR` | `High` | `Implemented` | Phase 1 | Ephemeral Session Teardown & Keychain Purge |
| `US-GRP-06` | Group Management | `ROLE-MBR` | `Medium` | `Implemented` | Phase 1/3 | Personal Neon Member Color Selection |
| `US-LOC-01` | Location & Telemetry | `ROLE-MBR` | `Critical` | `Implemented` | Phase 1 | User-Controlled Live Sharing Master Toggle |
| `US-LOC-02` | Location & Telemetry | `ROLE-MBR` | `High` | `Implemented` | Phase 1 | Motion-Aware Adaptive Cadence (Option B) |
| `US-LOC-03` | Location & Telemetry | `ROLE-MBR` | `High` | `Implemented` | Phase 1/3 | AMOLED Dark Mode Map Preview & Vision Cones |
| `US-LOC-04` | Location & Telemetry | `ROLE-NAV` | `High` | `Implemented` | Phase 1/2 | Honest Staleness & GPS Uncertainty Badges |
| `US-LOC-05` | Location & Telemetry | `ROLE-NAV` | `Medium` | `Implemented` | Phase 2 | Stale Peer Accelerated Cadence & AODV Probe |
| `US-LOC-06` | Location & Telemetry | `ROLE-NAV` | `High` | `Implemented` | Phase 2 | Dynamic Adaptive GNSS Accuracy Scaling |
| `US-NAV-01` | Tactical Navigation | `ROLE-NAV` | `Critical` | `Implemented` | Phase 3 | Festival Tactical Polar Radar (60M Forward-Up) |
| `US-NAV-02` | Tactical Navigation | `ROLE-NAV` | `High` | `Implemented` | Phase 3 | 60M Perimeter Clamping & Dual Selection |
| `US-NAV-03` | Tactical Navigation | `ROLE-NAV` | `High` | `Implemented` | Phase 3 | Apple U1/U2 Ultra-Wideband Precision Finding |
| `US-NAV-04` | Tactical Navigation | `ROLE-NAV` | `Medium` | `Implemented` | Phase 3 | Non-UWB Sensor Simulation Fallback |
| `US-NAV-05` | Tactical Navigation | `ROLE-NAV` | `Medium` | `Implemented` | Phase 3 | Visual Finder Beacon (Screen Strobe Torch) |
| `US-MTG-01` | Meeting Point | `ROLE-MBR` | `High` | `Implemented` | Phase 1 | Proposing a Single Active Rendezvous Point |
| `US-MTG-02` | Meeting Point | `ROLE-MBR` | `Critical` | `Implemented` | Phase 1/2 | Setter Lock Rule Enforcement |
| `US-MTG-03` | Meeting Point | `ROLE-MBR` | `High` | `Implemented` | Phase 1 | 1-Tap Attendance Confirmation (RSVP) |
| `US-MTG-04` | Meeting Point | `ROLE-MBR` | `Medium` | `Implemented` | Phase 1 | 25-Meter Proximity Auto-Arrival Geofencing |
| `US-MTG-05` | Meeting Point | `ROLE-MBR` | `Medium` | `Implemented` | Phase 1 | 1-Hour Meeting Point Auto-Expiration |
| `US-CHT-01` | Mesh Chat | `ROLE-MBR` | `Critical` | `Implemented` | Phase 3 | Sending 20-Byte Multi-Hop Mesh Messages |
| `US-CHT-02` | Mesh Chat | `ROLE-MBR` | `High` | `Implemented` | Phase 3 | Quick-Tap Festival Preset Chips |
| `US-CHT-03` | Mesh Chat | `ROLE-MBR` | `High` | `Implemented` | Phase 3 | Real-Time ByteMeterView Length Clamping |
| `US-CHT-04` | Mesh Chat | `ROLE-MBR` | `High` | `Implemented` | Phase 3 | Transparent Per-Recipient Delivery Tracking |
| `US-CHT-05` | Mesh Chat | `ROLE-MBR` | `Medium` | `Implemented` | Phase 3 | Ephemeral In-Memory Chat History Purge |
| `US-EMG-01` | Emergency SOS | `ROLE-SOS` | `Critical` | `Implemented` | Phase 1 | 3-Second Continuous Hold SOS Trigger |
| `US-EMG-02` | Emergency SOS | `ROLE-SOS` | `Critical` | `Implemented` | Phase 2 | Urgent Queue Preemption & 15-Hop Flooding |
| `US-EMG-03` | Emergency SOS | `ROLE-MBR` | `Critical` | `Implemented` | Phase 1/2 | Acoustic Siren, CoreHaptics & Distress HUD |
| `US-EMG-04` | Emergency SOS | `ROLE-SOS` | `Critical` | `Implemented` | Phase 3 | Autonomous "Man Down" Inactivity Guard |
| `US-EMG-05` | Emergency SOS | `ROLE-SOS` | `High` | `Implemented` | Phase 3 | 30-Second Pre-Alarm Warning Countdown |
| `US-EMG-06` | Emergency SOS | `ROLE-SOS` | `High` | `Implemented` | Phase 2 | Honest SOS Delivery State Feedback |
| `US-EMG-07` | Emergency SOS | `ROLE-SOS` | `Medium` | `Implemented` | Phase 1/2 | Emergency SOS Cancellation Workflow |
| `US-MSH-01` | Mesh Networking | `ROLE-RLY` | `Critical` | `Implemented` | Phase 2 | Zero-Knowledge Blind Stranger Relaying |
| `US-MSH-02` | Mesh Networking | `ROLE-RLY` | `Critical` | `Implemented` | Phase 2 | SeenPacketCache 1,024-Entry Deduplication |
| `US-MSH-03` | Mesh Networking | `ROLE-RLY` | `High` | `Implemented` | Phase 2 | Dual-Lane Token Bucket Rate Limiting |
| `US-MSH-04` | Mesh Networking | `ROLE-MBR` | `Critical` | `Implemented` | Phase 2 | Bonjour AWDL Discovery & Peering Policy |
| `US-MSH-05` | Mesh Networking | `ROLE-MBR` | `High` | `Implemented` | Phase 2 | AODV Reactive Route Discovery Engine |
| `US-MSH-06` | Battery Governance | `ROLE-MBR` | `Critical` | `Implemented` | Phase 2 | Festival Survival Mode & Hard 20% Cutoff |
| `US-MSH-07` | Background Execution| `ROLE-MBR` | `Critical` | `Implemented` | Phase 2 | Background Socket Survival via Status Pill |
| `US-MSH-08` | Background Execution| `ROLE-MBR` | `High` | `Implemented` | Phase 2 | ActivityKit Live Activity & Dynamic Island |
| `US-DBG-01` | Diagnostics & Lab | `ROLE-ENG` | `Medium` | `Implemented` | Phase 1 | On-Device Debug HUD Sheet |
| `US-DBG-02` | Diagnostics & Lab | `ROLE-ENG` | `High` | `Implemented` | Phase 2 | 1-Tap Automated Triage Health Audit |
| `US-DBG-03` | Diagnostics & Lab | `ROLE-ENG` | `High` | `Implemented` | Phase 2 | Live 56-Byte Packet Stream & Inspector |
| `US-DBG-04` | Diagnostics & Lab | `ROLE-ENG` | `Medium` | `Implemented` | Phase 2 | Synthetic Packet & Fault Injection |
| `US-DBG-05` | Diagnostics & Lab | `ROLE-ENG` | `High` | `Implemented` | Phase 2 | Virtual Topology Sandbox Simulation |
| `US-WAT-01` | Apple Watch | `ROLE-WAT` | `High` | `Planned` | Phase 4 | Tethered Watch Companion & Smart Stack |
| `US-WAT-02` | Apple Watch | `ROLE-WAT` | `Critical` | `Planned` | Phase 4 | High-Intensity Wrist Taptic SOS Alerts |
| `US-WAT-03` | Apple Watch | `ROLE-WAT` | `High` | `Planned` | Phase 4 | Discrete 3-Second Wrist SOS Trigger |
| `US-WAT-04` | Apple Watch | `ROLE-WAT` | `High` | `Planned` | Phase 4 | Heads-Up Wrist Compass & Bearing Guidance |
| `US-WAT-05` | Apple Watch | `ROLE-WAT` | `Medium` | `Planned` | Phase 4 | 1-Tap Wrist Meeting Point RSVP |
| `US-ALT-01` | Multi-Floor & Altitude| `ROLE-NAV` | `High` | `Planned` | Phase 4 | Peer-to-Peer Differential Barometry |
| `US-ALT-02` | Multi-Floor & Altitude| `ROLE-NAV` | `Medium` | `Planned` | Phase 4 | 2D Map Multi-Floor Switcher & Badges |
| `US-ALT-03` | Multi-Floor & Altitude| `ROLE-NAV` | `High` | `Planned` | Phase 4 | Vertical Elevation Warning in Tactical Radar |
| `US-ALT-04` | Multi-Floor & Altitude| `ROLE-NAV` | `Medium` | `Planned` | Phase 4 | Manual Floor Selection & Override |

---

## 3. Section I: Group Management & Serverless Pairing

### US-GRP-01: Serverless Group Formation & Key Generation
- **Story Information:**
  - **ID:** `US-GRP-01`
  - **Feature Area:** Group Management
  - **User Role:** `ROLE-HOST` (Group Host)
  - **User Story:** As a group host, I want to create a private group session without an internet connection or user account, so that my friends and I can coordinate securely off-grid.
  - **User Benefit:** Instant group establishment in remote festivals with 0 setup friction and complete anonymity.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 1`
- **Acceptance Criteria:**
  - **Scenario 1: Offline session creation**
    - *Given* an iPhone running TeeKum with zero cellular reception or Wi-Fi,
    - *When* the host enters 1–3 uppercase initials (e.g. "DNA") and taps "Create Group",
    - *Then* the app generates a cryptographically random 256-bit symmetric key (`SecRandomCopyBytes`), commits it to the iOS Keychain, derives a 24-bit session ID, and displays the session dashboard within $<500\text{ ms}$.
- **Edge Cases:**
  - Device storage low: Keychain write must verify success or present an explicit error modal.
  - Non-alphabetic initials: Input clamped to A-Z characters; lowercased input auto-capitalized.
- **Dependencies:**
  - `CryptoService`, `GroupSession`, `InitialsCodec`, `Security.framework`.
- **Verification:**
  - *Unit:* `CryptoSecurityTests.testKeyGenerationAndPersistence`
  - *UI:* `UIStateTests.testGroupCreationFlow`
  - *Device:* Tested on physical iPhone in Airplane Mode.

---

### US-GRP-02: Offline In-Person QR Barcode Pairing
- **Story Information:**
  - **ID:** `US-GRP-02`
  - **Feature Area:** Group Management
  - **User Role:** `ROLE-MBR` (Joining Friend)
  - **User Story:** As a festival attendee, I want to scan my friend's screen QR code with my camera at the venue, so that I can join their private group mesh without typing passwords or needing cell reception.
  - **User Benefit:** Frictionless on-site onboarding in dark, loud festival environments in $<3\text{ seconds}$.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 1`
- **Acceptance Criteria:**
  - **Scenario 1: Camera QR scan**
    - *Given* the host is displaying an offline group QR code,
    - *When* the joiner opens the in-app scanner (`QRScannerView`) and points the camera at the QR code,
    - *Then* the app parses `teekum://join#key=...`, extracts the 256-bit key from the URL fragment, prompts for the Communal Mesh Compact, and joins the session upon agreement.
- **Edge Cases:**
  - Pitch-black crowd: In-app torch toggle turns on rear camera LED flash for illumination.
  - Camera permission denied: Informative primer view prompts user to enable camera in iOS Settings.
  - Simulator execution: Camera fallback provides direct clipboard paste button.
- **Dependencies:**
  - `AVFoundation`, `CoreImage`, `QRScannerView`, `QRCodeView`, `GroupSessionViewModel`.
- **Verification:**
  - *Unit:* `PacketCodecTests.testGroupPairingURIEncoding`
  - *UI:* `UIStateTests.testQRScannerFallbackOnSimulator`
  - *Device:* Validated scanning between two real iPhones in low-light room.

---

### US-GRP-03: Serverless Universal Link Invite Sharing
- **Story Information:**
  - **ID:** `US-GRP-03`
  - **Feature Area:** Group Management
  - **User Role:** `ROLE-HOST` (Group Host)
  - **User Story:** As a group host, I want to share a universal invite link via iMessage or WhatsApp before arriving at the festival, so that my friends can join with one tap while we still have internet at home.
  - **User Benefit:** Pre-event setup convenience eliminating the need to scan QR codes on-site.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 1`
- **Acceptance Criteria:**
  - **Scenario 1: Universal link dispatch & opening**
    - *Given* the host taps "Share Invite Link",
    - *When* a recipient taps the link `teekum://join#key=Base64Key&sid=...` in iMessage,
    - *Then* TeeKum launches, parses the URL fragment, stores the key in Keychain, and opens the main map view.
- **Edge Cases:**
  - Key privacy: The 256-bit key must reside strictly behind the URL fragment `#` to prevent leaking to intermediate web proxies (RFC 3986).
- **Dependencies:**
  - `TeeKumApp.onOpenURL`, `GroupSessionViewModel`.
- **Verification:**
  - *Unit:* `UIStateTests.testDeepLinkParsing`
  - *Integration:* Simulated URL open via `xcrun simctl openurl`.

---

### US-GRP-04: Communal Mesh Compact Consent Gating
- **Story Information:**
  - **ID:** `US-GRP-04`
  - **Feature Area:** Group Management
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee joining a group, I want to explicitly review and accept the Communal Mesh Compact, so that I understand my phone will relay packets for others while others relay for me, with guaranteed battery protection.
  - **User Benefit:** Informed consent, trust, and transparency regarding background battery and radio usage.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Mandatory agreement acceptance**
    - *Given* a user has scanned a QR code or tapped a join link,
    - *When* the pairing URI is decoded,
    - *Then* the app displays `MeshAgreementView` blocking progression until "Agree & Join Mesh" is pressed.
    - *And* if the user taps "Decline", the session key is discarded and peer discovery does not begin.
- **Edge Cases:**
  - User backgrounding app during modal: State persists in memory; returns to modal upon foregrounding.
- **Dependencies:**
  - `MeshAgreementView`, `RelayPolicyManager`, `GroupSessionViewModel`.
- **Verification:**
  - *UI:* `UIStateTests.testCommunalMeshCompactGating`

---

### US-GRP-05: Ephemeral Session Teardown & Keychain Purge
- **Story Information:**
  - **ID:** `US-GRP-05`
  - **Feature Area:** Group Management
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee leaving a festival group, I want all session keys, peer locations, and message history to be wiped from my phone immediately, so that no historical tracking trail remains.
  - **User Benefit:** Absolute privacy by design; no post-event tracking data vulnerability.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 1`
- **Acceptance Criteria:**
  - **Scenario 1: Complete session teardown**
    - *Given* an active group session,
    - *When* the user confirms "Leave Group",
    - *Then* the 256-bit key is deleted from Keychain (`SecItemDelete`), radio sockets are closed, `SeenPacketCache` and `RoutingTable` are purged from RAM, Live Activities terminate, and the UI switches to `GroupPairingView`.
- **Edge Cases:**
  - App crash during session: Session marked invalid on next launch; orphaned Keychain items purged.
- **Dependencies:**
  - `GroupSessionViewModel.leaveGroup`, `CryptoService`, `LiveActivityManager`.
- **Verification:**
  - *Unit:* `UIStateTests.testEphemeralTeardownAndPurge`

---

### US-GRP-06: Personal Neon Member Color Selection
- **Story Information:**
  - **ID:** `US-GRP-06`
  - **Feature Area:** Group Management
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As a group member, I want to choose a personal neon avatar color, so that my friends can immediately distinguish my pin on the AMOLED dark map and tactical radar.
  - **User Benefit:** Visual disambiguation in crowded multi-member groups.
  - **Priority:** `Medium` | **Status:** `Implemented` | **Target Phase:** `Phase 1/3`
- **Acceptance Criteria:**
  - **Scenario 1: Selecting a neon color**
    - *Given* the user is setting up or viewing their profile,
    - *When* selecting from the 8-color neon palette (`neonGreen`, `electricCyan`, `hotPink`, etc.),
    - *Then* the selected color code ($1 \dots 8$) is embedded into Byte 17 of `LocationPingPayload` and renders as a vivid neon ring on friends' maps.
- **Dependencies:**
  - `MemberColor`, `ColorPickerView`, `LocationPingPayload`.
- **Verification:**
  - *Unit:* `PacketCodecTests.testMemberColorWireEncoding`

---

## 4. Section II: Location & Coordination

### US-LOC-01: User-Controlled Live Sharing Master Toggle
- **Story Information:**
  - **ID:** `US-LOC-01`
  - **Feature Area:** Location & Coordination
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee watching a performance, I want to pause location sharing with a single tap, so that I can conserve phone battery and enjoy privacy while standing at a stage.
  - **User Benefit:** Complete user autonomy over location broadcasting and power consumption.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 1`
- **Acceptance Criteria:**
  - **Scenario 1: Toggling Live Sharing OFF**
    - *Given* Live Sharing is ON and broadcasting every 4s,
    - *When* the user switches the "Live Sharing" toggle to OFF,
    - *Then* periodic GPS broadcasting ceases immediately, CoreLocation powers down, and the top status pill updates to *"Live Sharing Paused"*.
  - **Scenario 2: Emergency SOS bypass**
    - *Given* Live Sharing is OFF,
    - *When* the user triggers Emergency SOS,
    - *Then* coordinates are broadcast immediately regardless of the toggle state.
- **Dependencies:**
  - `LocationPublisher`, `LocationService`, `MainMapView`.
- **Verification:**
  - *Unit:* `LocationPublishingTests.testLiveSharingToggleSuspendsPublishing`
  - *UI:* `UIStateTests.testLiveSharingToggleUI`

---

### US-LOC-02: Motion-Aware Adaptive Cadence (Option B Pure Telemetry)
- **Story Information:**
  - **ID:** `US-LOC-02`
  - **Feature Area:** Location & Coordination
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee moving around a festival, I want my location update rate to automatically scale with my movement, so that my friends get fresh fixes when I'm walking but my battery is saved when I'm stationary.
  - **User Benefit:** ~70% reduction in GPS power consumption without manual intervention.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 1`
- **Acceptance Criteria:**
  - **Scenario 1: Walking cadence**
    - *Given* `CMMotionActivityManager` reports walking/moving,
    - *Then* `LocationPublisher` broadcasts updates every **4.0 seconds**.
  - **Scenario 2: Stationary sleep cadence**
    - *Given* `CMMotionActivityManager` reports stationary for $\ge 30\text{s}$,
    - *Then* `LocationPublisher` scales the broadcast interval down to **20.0 seconds**.
- **Dependencies:**
  - `CoreMotion`, `LocationPublisher`, `LocationService`.
- **Verification:**
  - *Unit:* `LocationPublishingTests.testAdaptiveCadenceMovingVsStationary`

---

### US-LOC-03: AMOLED Dark Mode Map Preview & Vision Cones
- **Story Information:**
  - **ID:** `US-LOC-03`
  - **Feature Area:** Location & Coordination
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee checking my phone at night, I want to see an AMOLED true-black map displaying my friends' positions and facing vision cones, so that I can orient myself without night-blindness or heavy battery drain.
  - **User Benefit:** Outdoor visibility at night, 35% display power savings, and peer orientation awareness.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 1/3`
- **Acceptance Criteria:**
  - **Scenario 1: Viewing map pins and vision cones**
    - *Given* group members are sharing location,
    - *When* opening `MainMapView`,
    - *Then* each friend is rendered as a neon circular avatar with their initials, accompanied by a 50° translucent vision cone rotating with their live compass heading (`headingDegrees`).
- **Dependencies:**
  - `MapKit`, `HeadingVisionCone`, `FriendPinAnnotationView`, `MainMapView`.
- **Verification:**
  - *Unit:* `LocationPublishingTests.testPeerHeadingDegreesAndOrientationVisualization`
  - *UI:* `UIStateTests.testMapRenderingFriendPins`

---

### US-LOC-04: Honest Staleness & GPS Uncertainty Badges
- **Story Information:**
  - **ID:** `US-LOC-04`
  - **Feature Area:** Location & Coordination
  - **User Role:** `ROLE-NAV` (Navigating Friend)
  - **User Story:** As a navigating attendee, I want to clearly see how old a friend's coordinate fix is and their GPS accuracy radius, so that I never walk toward an obsolete or inaccurate location.
  - **User Benefit:** Transparent, honest navigation preventing wild-goose chases in crowded venues.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 1/2`
- **Acceptance Criteria:**
  - **Scenario 1: Stale coordinate display**
    - *Given* a friend has not transmitted a location update for 45 seconds,
    - *When* viewing their pin on the map,
    - *Then* their avatar displays an amber staleness badge (*"Last seen 45s ago"*), the pin dims slightly, and a translucent accuracy circle reflects their reported uncertainty radius.
- **Dependencies:**
  - `Member`, `Formatters.formatRelativeTime`, `FriendPinAnnotationView`.
- **Verification:**
  - *Unit:* `UIStateTests.testStalePeerVisualIndication`

---

### US-LOC-05: Stale Peer Accelerated Cadence & AODV Probing
- **Story Information:**
  - **ID:** `US-LOC-05`
  - **Feature Area:** Location & Coordination
  - **User Role:** `ROLE-NAV` (Navigating Friend)
  - **User Story:** As a group member losing contact with a friend, I want my app to proactively search for them over the mesh, so that we can reconnect automatically without manual intervention.
  - **User Benefit:** Automated link recovery in dense, RF-attenuated festival crowds.
  - **Priority:** `Medium` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Proactive link recovery**
    - *Given* a group peer has not been seen for $>30\text{ seconds}$,
    - *When* the local device detects the stale threshold,
    - *Then* the local publishing interval accelerates to 2.0s, and at 45s elapsed, an AODV `ROUTE_REQ` (Type `0x04`) is dispatched.
    - *And* when the stale peer receives the probe, it responds with an immediate 3-ping burst at 2.0s intervals.
- **Dependencies:**
  - `RouteDiscoveryService`, `LocationPublisher`, `MeshTimingConfiguration`.
- **Verification:**
  - *Unit:* `RouteDiscoveryTests.testStalePeerBurstProbing`

---

### US-LOC-06: Dynamic Adaptive GNSS Accuracy Scaling
- **Story Information:**
  - **ID:** `US-LOC-06`
  - **Feature Area:** Location & Coordination
  - **User Role:** `ROLE-NAV` (Navigating Friend)
  - **User Story:** As an attendee actively finding a friend, I want maximum GPS accuracy while looking at the radar, but battery-conserving GPS while resting, so that my navigation is precise without draining my phone.
  - **User Benefit:** Sub-meter accuracy when needed; low power consumption when idle.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Radar accuracy engagement**
    - *Given* the user opens `FinderBeaconView` / `RadarView`,
    - *When* `applyDynamicAccuracy()` runs,
    - *Then* CoreLocation engages `kCLLocationAccuracyBestForNavigation` (dual-frequency L1+L5) and 0° heading filter.
  - **Scenario 2: Return to map**
    - *When* the user closes the radar view,
    - *Then* CoreLocation drops back to `kCLLocationAccuracyBest` with 1.0° heading filter.
- **Dependencies:**
  - `LocationService`, `FinderBeaconView`.
- **Verification:**
  - *Unit:* `LocationPublishingTests.testDynamicAdaptiveAccuracyScaling`

---

## 5. Section III: Tactical Navigation & Spatial Finding

### US-NAV-01: Festival Tactical Polar Radar (60M Forward-Up Projection)
- **Story Information:**
  - **ID:** `US-NAV-01`
  - **Feature Area:** Tactical Navigation
  - **User Role:** `ROLE-NAV` (Navigating Attendee)
  - **User Story:** As an attendee lost in a crowded festival, I want a forward-up tactical radar showing my friends relative to the direction I am facing, so that I can walk straight toward them without deciphering a rotating street map.
  - **User Benefit:** Instant directional orientation in disorienting, dark festival crowds.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 3`
- **Acceptance Criteria:**
  - **Scenario 1: Forward-up polar display**
    - *Given* the user is holding their phone in a crowd,
    - *When* opening `FinderBeaconView`,
    - *Then* a 60m circular polar radar displays concentric rings (15m, 30m, 60m), rotates with the phone's compass heading so "Up" is always straight ahead, and renders group member blips at their relative range and angle.
- **Dependencies:**
  - `RadarView`, `RadarGridBackground`, `RadarBlipView`, `FinderBeaconView`.
- **Verification:**
  - *Unit:* `UIStateTests.testTacticalRadarForwardUpPolarMath`

---

### US-NAV-02: 60M Perimeter Clamping & Dual Selection
- **Story Information:**
  - **ID:** `US-NAV-02`
  - **Feature Area:** Tactical Navigation
  - **User Role:** `ROLE-NAV` (Navigating Attendee)
  - **User Story:** As an attendee tracking separated friends, I want friends beyond 60 meters to remain visible on the outer rim of my radar, so that I never lose track of where they are.
  - **User Benefit:** Unbroken 360-degree spatial awareness across the entire venue.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 3`
- **Acceptance Criteria:**
  - **Scenario 1: Outer perimeter clamping**
    - *Given* a friend is 142 meters away at bearing 45°,
    - *When* viewing the tactical radar,
    - *Then* their blip is clamped to the 60m outer ring at 45°, rendered with an outward chevron arrow and a badge reading *"142m"*.
  - **Scenario 2: Inspecting friend**
    - *When* tapping their blip or swiping to their card in the bottom carousel,
    - *Then* a cyan targeting line is drawn to the blip and the HUD displays relative clock guidance (*"2 o'clock"*).
- **Dependencies:**
  - `RadarView`, `RadarFriendCard`, `RadarTheme`.
- **Verification:**
  - *Unit:* `UIStateTests.testRadarPerimeterClampingAndSelection`

---

### US-NAV-03: Apple U1/U2 Ultra-Wideband Precision Finding
- **Story Information:**
  - **ID:** `US-NAV-03`
  - **Feature Area:** Tactical Navigation
  - **User Role:** `ROLE-NAV` (Navigating Attendee)
  - **User Story:** As an attendee within 8 meters of a friend in a pitch-black crowd, I want centimeter-precise directional guidance on my screen, so that I can walk directly to them even when I cannot see them.
  - **User Benefit:** AirTag-style precision finding in dark, dense crowds (<8 meters).
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 3`
- **Acceptance Criteria:**
  - **Scenario 1: Precision finding activation**
    - *Given* the user is within 8m of a friend and both have U1/U2 iPhones,
    - *When* tapping "Start Precision Finding",
    - *Then* discovery tokens are exchanged over direct 1-hop mesh packets (`Type 0x08`), and `PrecisionFindingOverlay` displays a dynamic 3D directional arrow, centimeter readout, and haptic pulses.
- **Dependencies:**
  - `NearbyInteraction`, `NearbyInteractionService`, `PrecisionFindingOverlay`.
- **Verification:**
  - *Unit:* `NearbyInteractionTests.testTokenFragmentationAndReassembly`
  - *Device:* Tested on two physical iPhone 15 Pro devices.

---

### US-NAV-04: Non-UWB Sensor-Assisted Simulation Fallback
- **Story Information:**
  - **ID:** `US-NAV-04`
  - **Feature Area:** Tactical Navigation
  - **User Role:** `ROLE-NAV` (Navigating Attendee)
  - **User Story:** As an attendee using an iPhone without a UWB chip (e.g. iPhone SE), I want the directional finder to still guide me using GPS and compass, so that I get a seamless navigation experience on any device.
  - **User Benefit:** Universal hardware compatibility without app crashes or feature lockout.
  - **Priority:** `Medium` | **Status:** `Implemented` | **Target Phase:** `Phase 3`
- **Acceptance Criteria:**
  - **Scenario 1: Automated fallback**
    - *Given* `NISession.isSupported == false`,
    - *When* opening the precision finding overlay,
    - *Then* `NearbyInteractionService` transparently computes distance from GNSS coordinates and bearing from magnetometer heading, driving the 3D directional arrow smoothly.
- **Dependencies:**
  - `NearbyInteractionService`, `CoreLocation`.
- **Verification:**
  - *Unit:* `NearbyInteractionTests.testSensorSimulationFallback`

---

### US-NAV-05: Visual Finder Beacon (Screen Strobe Torch)
- **Story Information:**
  - **ID:** `US-NAV-05`
  - **Feature Area:** Tactical Navigation
  - **User Role:** `ROLE-NAV` (Separated Attendee)
  - **User Story:** As an attendee waiting for my friend in a dark crowd, I want to turn my phone into a flashing neon strobe torch to wave in the air, so that my friend can spot me visually from 20 meters away.
  - **User Benefit:** High-visibility visual beacon cutting through darkness and flashing concert lights.
  - **Priority:** `Medium` | **Status:** `Implemented` | **Target Phase:** `Phase 3`
- **Acceptance Criteria:**
  - **Scenario 1: Strobe torch activation**
    - *Given* the user is in `FinderBeaconView`,
    - *When* tapping "Strobe Torch",
    - *Then* the screen pulses full-screen high-contrast neon strobe synchronized with the camera LED flash at 4 Hz, automatically shutting off after 60 seconds to protect battery.
- **Dependencies:**
  - `FinderBeaconView`, `AVFoundation` (`torchMode`).
- **Verification:**
  - *UI:* `UIStateTests.testFinderBeaconTorchToggle`

---

## 6. Section IV: Single Active Meeting Point

### US-MTG-01: Proposing a Single Active Rendezvous Point
- **Story Information:**
  - **ID:** `US-MTG-01`
  - **Feature Area:** Meeting Point
  - **User Role:** `ROLE-MBR` (Group Member)
  - **User Story:** As a group member, I want to drop a single meeting point on the map with a scheduled time, so that my friends know exactly where and when we are regrouping.
  - **User Benefit:** Instant group rendezvous coordination without endless back-and-forth messaging.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 1`
- **Acceptance Criteria:**
  - **Scenario 1: Creating a rendezvous point**
    - *Given* no meeting point is currently active,
    - *When* a member long-presses a coordinate on `MainMapView`,
    - *Then* `SetMeetingPointSheet` opens with preset times (*"Right Now"*, *"In 15m"*, *"In 30m"*, *"In 1h"*), and tapping "Set" broadcasts `MeetingUpdatePayload` (Type `0x03`, 15 hops) across the mesh.
- **Dependencies:**
  - `MeetingPointViewModel`, `SetMeetingPointSheet`, `MeetingPointPinView`.
- **Verification:**
  - *Unit:* `UIStateTests.testMeetingPointCreationAndBroadcast`

---

### US-MTG-02: Setter Lock Rule Enforcement
- **Story Information:**
  - **ID:** `US-MTG-02`
  - **Feature Area:** Meeting Point
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As a group member, I want only the original meeting proposer (Setter) to be able to change or cancel the meeting point, so that other members cannot accidentally overwrite or delete our rendezvous spot.
  - **User Benefit:** Prevention of conflicting rendezvous instructions and accidental overwrites in chaotic crowds.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 1/2`
- **Acceptance Criteria:**
  - **Scenario 1: Non-setter long-press locked out**
    - *Given* Alice has set an active meeting point,
    - *When* Bob long-presses the map to set a new meeting point,
    - *Then* the app triggers an alert haptic and displays a locked toast: *"Only Alice can unset or change the active rendezvous"*, and Bob's broadcast button remains disabled.
  - **Scenario 2: Inbound rogue update rejected**
    - *Given* Bob attempts to forge a Type `0x03` packet to change the meeting point,
    - *When* group members' protocol engines receive it,
    - *Then* `applyInboundUpdate` validates `setterInitials == activeSetter` and silently drops Bob's unauthorized packet.
- **Dependencies:**
  - `MeetingPointViewModel.applyInboundUpdate`, `MainMapView`.
- **Verification:**
  - *Unit:* `UIStateTests.testMeetingPointSetterLockRule`

---

### US-MTG-03: 1-Tap Attendance Confirmation (RSVP)
- **Story Information:**
  - **ID:** `US-MTG-03`
  - **Feature Area:** Meeting Point
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee receiving a meeting point update, I want to tap "I'll be there" or "Can't make it", so that my group knows who is attending.
  - **User Benefit:** Real-time attendance visibility across the mesh without typing messages.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 1`
- **Acceptance Criteria:**
  - **Scenario 1: Confirming attendance**
    - *Given* an active meeting point notification banner,
    - *When* the user taps "I'll be there",
    - *Then* their attendance state updates to `.attending` and is shared across the mesh via ACK packets (`Type 0x06`).
- **Dependencies:**
  - `MeetingPointsView`, `MeetingPointViewModel`, `ACKPayload`.
- **Verification:**
  - *Unit:* `UIStateTests.testMeetingPointAttendanceRSVP`

---

### US-MTG-04: 25-Meter Proximity Auto-Arrival Geofencing
- **Story Information:**
  - **ID:** `US-MTG-04`
  - **Feature Area:** Meeting Point
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee arriving at the meeting landmark, I want the app to automatically mark me as "Arrived", so that I don't have to pull out my phone to confirm I'm there.
  - **User Benefit:** Zero-effort automatic status synchronization upon physical arrival.
  - **Priority:** `Medium` | **Status:** `Implemented` | **Target Phase:** `Phase 1`
- **Acceptance Criteria:**
  - **Scenario 1: Auto-arrival detection**
    - *Given* an active meeting point at coordinate $C$,
    - *When* the user's GPS position approaches within **25.0 meters** of $C$,
    - *Then* the attendance state automatically transitions to `.atMeetingPoint` and displays a confirmation toast.
- **Dependencies:**
  - `MeetingPointViewModel.checkProximityToMeetingPoint`.
- **Verification:**
  - *Unit:* `UIStateTests.testMeetingPointAutoArrivalGeofence`

---

### US-MTG-05: 1-Hour Meeting Point Auto-Expiration
- **Story Information:**
  - **ID:** `US-MTG-05`
  - **Feature Area:** Meeting Point
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee, I want past meeting points to disappear after 1 hour, so that outdated rendezvous spots don't clutter the map and the Setter Lock is released.
  - **User Benefit:** Clean map interface and automatic release of proposer locks for future meetups.
  - **Priority:** `Medium` | **Status:** `Implemented` | **Target Phase:** `Phase 1`
- **Acceptance Criteria:**
  - **Scenario 1: Automatic expiration**
    - *Given* an active meeting point scheduled for 10:00 PM,
    - *When* the clock reaches 11:00 PM (3,600s elapsed post-meetup),
    - *Then* the meeting pin is automatically removed from the map and the Setter Lock clears.
- **Dependencies:**
  - `MeetingPointViewModel`, `TeeKumConfiguration.Rendezvous.autoExpirationSeconds`.
- **Verification:**
  - *Unit:* `UIStateTests.testMeetingPointAutoExpiration`

---

## 7. Section V: Festival Group Mesh Chat

### US-CHT-01: Sending 20-Byte Multi-Hop Mesh Messages
- **Story Information:**
  - **ID:** `US-CHT-01`
  - **Feature Area:** Mesh Chat
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee with zero cellular data, I want to send a short text message across the multi-hop mesh to my group, so that we can communicate without internet.
  - **User Benefit:** True offline group text messaging across crowded festival grounds.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 3`
- **Acceptance Criteria:**
  - **Scenario 1: Sending custom text**
    - *Given* the user is in `ChatSheetView`,
    - *When* typing "Meet at main stage" (18 bytes) and tapping Send,
    - *Then* the message is encrypted into a 56-byte datagram (`Type 0x07`), enqueued into the FIFO chat outbox lane, and flooded across the mesh up to `chatHopLimit = 8`.
- **Dependencies:**
  - `ChatMessageEngine`, `ChatViewModel`, `ChatSheetView`, `Packet.ChatMessagePayload`.
- **Verification:**
  - *Unit:* `ChatMessagingEngineTests.testChatSerializationAndOutboxDispatch`

---

### US-CHT-02: Quick-Tap Festival Preset Chips
- **Story Information:**
  - **ID:** `US-CHT-02`
  - **Feature Area:** Mesh Chat
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee walking through a loud, jostling crowd, I want to tap a preset chip like "Beer line" or "Lost" with one hand, so that I can send updates instantly without typing on a keyboard.
  - **User Benefit:** Ultra-fast, one-handed tactical communication in crowded environments.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 3`
- **Acceptance Criteria:**
  - **Scenario 1: 1-Tap preset dispatch**
    - *Given* `ChatSheetView` is open above the keyboard,
    - *When* tapping the preset chip *"Beer line"*,
    - *Then* the message is immediately populated, sealed, and broadcast across the mesh in $<50\text{ ms}$.
- **Dependencies:**
  - `PresetChipsView`, `ChatSheetView`, `ChatMessageEngine`.
- **Verification:**
  - *UI:* `ChatUITests.testPresetChipsPopulateAndSend`

---

### US-CHT-03: Real-Time ByteMeterView Length Clamping
- **Story Information:**
  - **ID:** `US-CHT-03`
  - **Feature Area:** Mesh Chat
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee typing a message, I want to see a live byte counter that prevents me from typing beyond 20 UTF-8 bytes, so that my message never gets truncated or malformed on the wire.
  - **User Benefit:** Clear visual boundaries guaranteeing 100% wire protocol compliance.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 3`
- **Acceptance Criteria:**
  - **Scenario 1: Byte limit enforcement**
    - *Given* a user typing in the chat field,
    - *When* UTF-8 byte count reaches 20,
    - *Then* `ByteMeterView` turns red (`20/20 B`) and further keystrokes or pastes are strictly clamped.
- **Dependencies:**
  - `ByteMeterView`, `ChatSheetView`.
- **Verification:**
  - *UI:* `ChatUITests.testByteMeterClampingAndColorStates`

---

### US-CHT-04: Transparent Per-Recipient Delivery Tracking
- **Story Information:**
  - **ID:** `US-CHT-04`
  - **Feature Area:** Mesh Chat
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee sending a chat message, I want to know which of my friends actually received it, so that I don't assume someone got a message when they were out of range.
  - **User Benefit:** Honest communication preventing missed rendezvous or false assumptions.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 3`
- **Acceptance Criteria:**
  - **Scenario 1: Multi-recipient delivery feedback**
    - *Given* a 4-person group,
    - *When* an outbound chat message receives ACKs (`Type 0x06`) from 2 friends,
    - *Then* the message bubble displays a chip reading *"Delivered to 2/3"*, and tapping it opens `RecipientAckBreakdownView` detailing individual peer states.
- **Dependencies:**
  - `ChatMessageBubbleView`, `RecipientAckBreakdownView`, `ChatMessageEngine`.
- **Verification:**
  - *Unit:* `ChatMessagingEngineTests.testPerRecipientAckTracking`

---

### US-CHT-05: Ephemeral In-Memory Chat History Purge
- **Story Information:**
  - **ID:** `US-CHT-05`
  - **Feature Area:** Mesh Chat
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee, I want chat messages to live only in memory (up to 50 messages) and be wiped when the session ends, so that my personal festival chats are never stored permanently.
  - **User Benefit:** Complete ephemeral privacy; zero forensic chat logs left on device.
  - **Priority:** `Medium` | **Status:** `Implemented` | **Target Phase:** `Phase 3`
- **Acceptance Criteria:**
  - **Scenario 1: Chat buffer ceiling & teardown**
    - *Given* 50 messages exist in memory,
    - *When* a 51st message arrives,
    - *Then* the oldest message is dropped ($O(1)$ FIFO buffer).
    - *And* when "Leave Group" is tapped, all 50 messages are instantly cleared from RAM.
- **Dependencies:**
  - `ChatViewModel`, `ChatMessageEngine`.
- **Verification:**
  - *Unit:* `ChatMessagingEngineTests.testChatBufferCapacityAndPurge`

---

## 8. Section VI: Emergency SOS & Inactivity Guard Watchdog

### US-EMG-01: Manual 3-Second Continuous Hold SOS Trigger
- **Story Information:**
  - **ID:** `US-EMG-01`
  - **Feature Area:** Emergency SOS
  - **User Role:** `ROLE-SOS` (Distressed Member)
  - **User Story:** As an attendee in a crowd crush or medical emergency, I want to press and hold the SOS button for 3 seconds to call for help, so that I can signal my friends reliably without accidental misfires while dancing.
  - **User Benefit:** Fail-safe emergency dispatch immune to accidental pocket taps.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 1`
- **Acceptance Criteria:**
  - **Scenario 1: Successful 3-second hold**
    - *Given* the user is in distress,
    - *When* continuously pressing the SOS button for **3.0 seconds**,
    - *Then* the circular progress ring completes, haptic pulses escalate, and the app broadcasts an authenticated `SOSPayload` (Type `0x02`, `emergencyType = 0x01`).
  - **Scenario 2: Accidental release**
    - *When* the user releases before 3.0 seconds,
    - *Then* the countdown cancels immediately and no packet is sent.
- **Dependencies:**
  - `SOSButtonView`, `SOSViewModel`, `PriorityOutboxQueue`.
- **Verification:**
  - *Unit:* `SOSEndToEndTests.testManualSOSHoldAndDispatch`

---

### US-EMG-02: Urgent Queue Preemption & 15-Hop Flooding
- **Story Information:**
  - **ID:** `US-EMG-02`
  - **Feature Area:** Emergency SOS
  - **User Role:** `ROLE-SOS` (Distressed Member)
  - **User Story:** As an attendee in danger, I want my emergency alert to cut to the front of all transmission queues and flood across 15 mesh hops, so that my friends receive it even through dense crowd attenuation.
  - **User Benefit:** Maximum emergency packet reach and minimum transmission latency.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Queue preemption**
    - *Given* normal location pings and chat messages in the outbox queue,
    - *When* an SOS alert is triggered,
    - *Then* it inserts into Tier 1 head-of-line in `PriorityOutboxQueue`, transmits immediately with `hopLimit = 15`, and utilizes the dedicated 4.0 pkts/s rate limit lane.
- **Dependencies:**
  - `PriorityOutboxQueue`, `ForwardingRateLimiter`, `PacketForwarder`.
- **Verification:**
  - *Unit:* `MultiHopSOSTests.testSOSQueuePreemptionAndExtendedHops`

---

### US-EMG-03: Acoustic Siren, CoreHaptics & Distress HUD
- **Story Information:**
  - **ID:** `US-EMG-03`
  - **Feature Area:** Emergency SOS
  - **User Role:** `ROLE-MBR` (Receiving Friend)
  - **User Story:** As a group member in a 100+ dB concert, I want my phone to blare an acoustic siren and vibrate aggressively when a friend triggers SOS, so that I notice the emergency immediately despite loud music.
  - **User Benefit:** Unmissable life-safety alerting cutting through deafening sound environments.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 1/2`
- **Acceptance Criteria:**
  - **Scenario 1: Inbound SOS alert reception**
    - *Given* an authenticated SOS packet arrives from friend "AL",
    - *When* Poly1305 MAC verification succeeds,
    - *Then* `SOSAudioAlert` plays an alternating two-tone square wave siren at system volume, triggers continuous vibration loops, and displays `IncomingSOSAlertBannerView` showing AL's distance and bearing.
- **Dependencies:**
  - `SOSAudioAlert`, `AVAudioEngine`, `CoreHaptics`, `IncomingSOSAlertBannerView`.
- **Verification:**
  - *Unit:* `SOSEndToEndTests.testDuplicateSirenSuppression`

---

### US-EMG-04: Autonomous "Man Down" Inactivity Guard Watchdog
- **Story Information:**
  - **ID:** `US-EMG-04`
  - **Feature Area:** Emergency SOS
  - **User Role:** `ROLE-SOS` (Incapacitated Attendee)
  - **User Story:** As an attendee who has collapsed unconscious and dropped my phone, I want the app to detect my immobility and broadcast an emergency alert automatically, so that my friends can find me even if I cannot press the button.
  - **User Benefit:** Automated life-safety rescue for unconscious or incapacitated attendees.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 3`
- **Acceptance Criteria:**
  - **Scenario 1: Stillness detection**
    - *Given* Inactivity Guard is enabled,
    - *When* the phone experiences variance $<0.15g$ and zero screen touches for **180 seconds (3 minutes)**,
    - *Then* the device enters the 30-second pre-alarm warning countdown.
- **Dependencies:**
  - `InactivityGuardService`, `CoreMotion`, `SOSViewModel`.
- **Verification:**
  - *Unit:* `InactivityGuardTests.testStillnessDetectionTimer`

---

### US-EMG-05: 30-Second Pre-Alarm Warning Countdown
- **Story Information:**
  - **ID:** `US-EMG-05`
  - **Feature Area:** Emergency SOS
  - **User Role:** `ROLE-SOS` (Attendee)
  - **User Story:** As an attendee whose phone is resting still on a table, I want a 30-second silent vibration warning before an auto-SOS is sent, so that I can cancel false alarms by simply picking up the phone.
  - **User Benefit:** Elimination of false emergency panics when phone is stationary.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 3`
- **Acceptance Criteria:**
  - **Scenario 1: Motion-based dismissal**
    - *Given* the 30-second pre-alarm modal is flashing,
    - *When* the user picks up the phone (accelerometer motion $>0.15g$) or taps "I'M OK",
    - *Then* the alarm immediately resets with 0 packets transmitted.
  - **Scenario 2: Countdown expiry dispatch**
    - *When* 30 seconds elapse without motion or touch,
    - *Then* an authenticated auto-SOS (`emergencyType = 0x04` inactivity) is broadcast across 15 hops.
- **Dependencies:**
  - `InactivityGuardService`, `SOSViewModel`.
- **Verification:**
  - *Unit:* `InactivityGuardTests.testPreAlarmCountdownAndAutoSOSDispatch`

---

### US-EMG-06: Honest SOS Delivery State Feedback
- **Story Information:**
  - **ID:** `US-EMG-06`
  - **Feature Area:** Emergency SOS
  - **User Role:** `ROLE-SOS` (Distressed Member)
  - **User Story:** As an attendee who fired an SOS, I want to see the honest delivery progress of my distress call, so that I know whether it has only reached a nearby relay or has been confirmed by my friends.
  - **User Benefit:** Psychological reassurance and honest awareness of delivery state.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Delivery state progression**
    - *Given* an active SOS broadcast,
    - *Then* the UI transitions honestly: `localSending` $\rightarrow$ `searchingPeers` $\rightarrow$ `relayedAck` $\rightarrow$ `deliveredToFriend`.
    - *And* "Delivered" is never displayed unless an authenticated return ACK from a group member arrives.
- **Dependencies:**
  - `SOSDeliveryState`, `SOSViewModel`.
- **Verification:**
  - *Unit:* `SOSEndToEndTests.testSOSDeliveryStateTransitions`

---

### US-EMG-07: Emergency SOS Cancellation Workflow
- **Story Information:**
  - **ID:** `US-EMG-07`
  - **Feature Area:** Emergency SOS
  - **User Role:** `ROLE-SOS` (Distressed Member)
  - **User Story:** As an attendee who has recovered from a minor panic, I want to cancel my active SOS alert, so that my friends' sirens stop sounding and they know I am safe.
  - **User Benefit:** Immediate group de-escalation once an emergency is resolved.
  - **Priority:** `Medium` | **Status:** `Implemented` | **Target Phase:** `Phase 1/2`
- **Acceptance Criteria:**
  - **Scenario 1: Cancelling SOS**
    - *Given* an active SOS incident,
    - *When* the user holds "Cancel SOS" for 1 second,
    - *Then* an emergency cancellation datagram (`emergencyType = 0x00`) is flooded across the mesh, immediately silencing sirens on group members' devices.
- **Dependencies:**
  - `SOSViewModel`, `SOSAudioAlert.stopSiren`.
- **Verification:**
  - *Unit:* `SOSEndToEndTests.testSOSCancellationSilencesSirens`

---

## 9. Section VII: Mesh Networking & Background Governance

### US-MSH-01: Zero-Knowledge Blind Stranger Relaying
- **Story Information:**
  - **ID:** `US-MSH-01`
  - **Feature Area:** Mesh Networking
  - **User Role:** `ROLE-RLY` (Stranger Relay Node)
  - **User Story:** As a festival attendee, I want my phone to relay encrypted packets for strangers without being able to see their coordinates or chat, so that I can help the community without compromising anyone's privacy.
  - **User Benefit:** Reciprocal crowd mesh connectivity with strict zero-knowledge privacy.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Blind packet forwarding**
    - *Given* stranger node Bob receives a 56-byte packet for Alice's group,
    - *When* Bob's `PacketForwarder` inspects the 10-byte cleartext envelope,
    - *Then* Bob verifies `hopCount < hopLimit`, increments `hopCount` on the wire, and retransmits the datagram without decrypting or logging the 30-byte payload.
- **Dependencies:**
  - `PacketForwarder`, `Packet.swift` (Masked AAD invariant).
- **Verification:**
  - *Unit:* `RoutingForwardingTests.testBlindStrangerRelayingPreservesPayload`

---

### US-MSH-02: SeenPacketCache 1,024-Entry Deduplication
- **Story Information:**
  - **ID:** `US-MSH-02`
  - **Feature Area:** Mesh Networking
  - **User Role:** `ROLE-RLY` (Relay Node)
  - **User Story:** As a relay node in a dense crowd, I want my phone to ignore duplicate packets, so that my radio is not bogged down by endless circular forwarding loops or broadcast storms.
  - **User Benefit:** Stable, loop-free multi-hop mesh routing and battery preservation.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Dropping duplicates**
    - *Given* a packet with key `(sessionId: 3B, sequenceNumber: 4B)` is in `SeenPacketCache`,
    - *When* the identical datagram arrives from another peer link,
    - *Then* it is dropped immediately in $<0.2\text{ ms}$ without queuing or retransmission.
- **Dependencies:**
  - `SeenPacketCache` (1,024 entries, 300s TTL).
- **Verification:**
  - *Unit:* `RoutingForwardingTests.testDuplicateSuppressionViaSeenPacketCache`

---

### US-MSH-03: Dual-Lane Token Bucket Rate Limiting
- **Story Information:**
  - **ID:** `US-MSH-03`
  - **Feature Area:** Mesh Networking
  - **User Role:** `ROLE-RLY` (Relay Node)
  - **User Story:** As a relay node, I want forwarded traffic to be rate-limited, so that rogue or chatty nodes cannot drain my battery with high-frequency packet flooding.
  - **User Benefit:** Guaranteed battery protection against denial-of-service packet storms.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Ordinary traffic cap**
    - *Given* an influx of ordinary location pings and chat messages,
    - *When* forwarding rate exceeds **2.0 packets/second**,
    - *Then* excess packets are dropped from the relay head.
  - **Scenario 2: Emergency SOS burst**
    - *When* emergency SOS packets arrive,
    - *Then* they utilize the dedicated urgent lane allowing bursts up to **4.0 packets/second**.
- **Dependencies:**
  - `ForwardingRateLimiter`.
- **Verification:**
  - *Unit:* `RelayPolicyTests.testDualLaneRateLimiter`

---

### US-MSH-04: Bonjour AWDL Discovery & Peering Policy
- **Story Information:**
  - **ID:** `US-MSH-04`
  - **Feature Area:** Mesh Networking
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee, I want my phone to discover nearby iPhones over Apple Wireless Direct Link (AWDL) automatically, so that we form direct ad-hoc links without configuring Wi-Fi settings.
  - **User Benefit:** Zero-configuration peer-to-peer radio transport.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Peer discovery & tie-breaking**
    - *Given* two iPhones running TeeKum within 40m,
    - *When* `NWBrowser` detects `_teekum._tcp`,
    - *Then* deterministic tie-breaking (`localPeerId < remotePeerId`) establishes a single bidirectional TCP stream, adding the peer to `NeighborTable`.
- **Dependencies:**
  - `PeerTransportService`, `NeighborTable`, `Network.framework`.
- **Verification:**
  - *Unit:* `NeighborDiscoveryTests.testBonjourPeeringAndTieBreaking`

---

### US-MSH-05: AODV Reactive Route Discovery Engine
- **Story Information:**
  - **ID:** `US-MSH-05`
  - **Feature Area:** Mesh Networking
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee seeking a friend across multiple crowd clusters, I want my app to find a multi-hop route on demand, so that we can exchange messages beyond direct radio reach.
  - **User Benefit:** Multi-hop connectivity bridging separated crowd clusters.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Route discovery request/reply**
    - *Given* peer Bob is 3 hops away,
    - *When* Alice initiates a Route Request (`ROUTE_REQ` Type `0x04`),
    - *Then* intermediate nodes establish reverse routing entries, Bob replies with `ROUTE_RESP` (Type `0x05`), and Alice caches the confirmed forward path (30s TTL).
- **Dependencies:**
  - `RouteDiscoveryService`, `RoutingTable`, `Packet.swift`.
- **Verification:**
  - *Unit:* `RouteDiscoveryTests.testAODVRouteDiscoveryAndCaching`

---

### US-MSH-06: Festival Survival Mode & Hard 20% Battery Cutoff
- **Story Information:**
  - **ID:** `US-MSH-06`
  - **Feature Area:** Battery Governance
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee whose battery is running low at the end of the night, I want my phone to stop relaying stranger packets automatically at 20% battery, so that my remaining power is saved for emergency SOS and my meeting map.
  - **User Benefit:** Elimination of stranded attendee risk due to dead phone batteries.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Hard 20% cutoff trigger**
    - *Given* battery drops below 20% or enters Low Power Mode,
    - *When* `RelayPolicyManager` detects the threshold,
    - *Then* stranger relaying halts, background listening closes, GPS throttles to 60s, and a warning banner indicates *"Festival Survival Mode Active"*.
- **Dependencies:**
  - `RelayPolicyManager`, `LocationPublisher`, `UIDevice.batteryLevel`.
- **Verification:**
  - *Unit:* `RelayPolicyTests.testHardTwentyPercentSurvivalCutoff`

---

### US-MSH-07: Background Socket Survival via Status Pill
- **Story Information:**
  - **ID:** `US-MSH-07`
  - **Feature Area:** Background Execution
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee with my phone locked in my pocket, I want mesh relaying and emergency SOS listening to stay alive, so that our group mesh doesn't collapse when screens are off.
  - **User Benefit:** Continuous crowd mesh connectivity without keeping screens powered on.
  - **Priority:** `Critical` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Background execution maintenance**
    - *Given* an active group session,
    - *When* the user locks their screen and puts the phone in their pocket,
    - *Then* `showsBackgroundLocationIndicator = true` keeps `NWListener` and `NWConnection` sockets active in the background, while `CoreMotion` safely sleeps the GPS receiver.
- **Dependencies:**
  - `LocationService`, `CoreLocation` background modes.
- **Verification:**
  - *Unit:* `LocationPublishingTests.testBackgroundLocationIndicatorConfiguration`
  - *Device:* Tested locked in pocket for 30 minutes over AWDL.

---

### US-MSH-08: ActivityKit Live Activity & Dynamic Island
- **Story Information:**
  - **ID:** `US-MSH-08`
  - **Feature Area:** Background Execution
  - **User Role:** `ROLE-MBR` (Attendee)
  - **User Story:** As an attendee glancing at my Lock Screen or Dynamic Island, I want to see our active meeting point distance and connected peers without unlocking my phone, so that I can stay coordinated effortlessly.
  - **User Benefit:** Zero-friction glanceable coordination on Lock Screen and Dynamic Island.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Lock Screen & Dynamic Island rendering**
    - *Given* an active session,
    - *When* viewing the Dynamic Island or Lock Screen,
    - *Then* `SessionActivityWidget` displays closest friend distance, active rendezvous countdown, and relay status controls.
- **Dependencies:**
  - `ActivityKit`, `SessionActivityWidget`, `LiveActivityManager`.
- **Verification:**
  - *Unit:* `LiveActivityTests.testLiveActivityLifecycleAndPayload`

---

## 10. Section VIII: Diagnostics & Virtual Simulation Lab

### US-DBG-01: On-Device Debug HUD Sheet
- **Story Information:**
  - **ID:** `US-DBG-01`
  - **Feature Area:** Diagnostics
  - **User Role:** `ROLE-ENG` (QA Engineer / Field Tester)
  - **User Story:** As a field engineer at a concert, I want to inspect live peer RSSI signal strength (dBm) and packet counters, so that I can verify RF performance in real crowd environments.
  - **User Benefit:** Instant on-device observability without attaching Xcode debuggers.
  - **Priority:** `Medium` | **Status:** `Implemented` | **Target Phase:** `Phase 1`
- **Acceptance Criteria:**
  - **Scenario 1: Viewing Debug HUD**
    - *Given* an active session,
    - *When* opening `DiagnosticsView`,
    - *Then* the sheet renders connected peer RSSI in dBm, packet throughput counters, true GPS accuracy (±m), and key fingerprint.
- **Dependencies:**
  - `DiagnosticsView`, `MeshDiagnostics`.
- **Verification:**
  - *UI:* `UIStateTests.testDiagnosticsHUDDisplay`

---

### US-DBG-02: 1-Tap Automated Triage Health Audit
- **Story Information:**
  - **ID:** `US-DBG-02`
  - **Feature Area:** Diagnostics
  - **User Role:** `ROLE-ENG` (Engineer)
  - **User Story:** As an engineer diagnosing an issue, I want a 1-tap automated health triage check, so that I can instantly verify radio hardware, permissions, encryption, and battery state.
  - **User Benefit:** Sub-second root cause diagnosis of on-device radio or permission failures.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Automated triage execution**
    - *Given* `MeshDebuggerView` is open,
    - *When* tapping "Run Triage Audit",
    - *Then* the triage engine audits Bluetooth/AWDL, Location authorization, Survival Mode, Keychain keys, and ChaChaPoly readiness, surfacing Pass/Warn/Fail badges.
- **Dependencies:**
  - `MeshDebuggerViewModel`, `MeshDebuggerView`.
- **Verification:**
  - *Unit:* `MeshDebuggerTests.testAutomatedTriageAudit`

---

### US-DBG-03: Live 56-Byte Wire Packet Inspector
- **Story Information:**
  - **ID:** `US-DBG-03`
  - **Feature Area:** Diagnostics
  - **User Role:** `ROLE-ENG` (Protocol Engineer)
  - **User Story:** As a protocol engineer, I want to inspect live 56-byte binary datagrams broken down into envelope, payload, and MAC tag, so that I can verify bitfield alignment on physical devices.
  - **User Benefit:** Byte-level wire transparency during field debugging.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Packet inspection**
    - *Given* active mesh radio traffic,
    - *When* tapping any datagram in the rolling packet log,
    - *Then* `MeshDebuggerView` displays an interactive breakdown: 10B cleartext envelope, 30B encrypted payload, and 16B Poly1305 MAC tag hex values.
- **Dependencies:**
  - `MeshDebuggerView`, `Formatters.hexDump`.
- **Verification:**
  - *Unit:* `MeshDebuggerTests.testPacketInspectorBitfieldBreakdown`

---

### US-DBG-04: Synthetic Packet & Fault Injection
- **Story Information:**
  - **ID:** `US-DBG-04`
  - **Feature Area:** Diagnostics
  - **User Role:** `ROLE-ENG` (QA Engineer)
  - **User Story:** As a QA tester, I want to inject synthetic packets and corrupted MAC tags, so that I can verify cryptographic tamper rejection and rate limiting on physical devices.
  - **User Benefit:** On-device fault injection and boundary verification without external RF hardware.
  - **Priority:** `Medium` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Fault injection rejection**
    - *When* injecting a synthetic frame with a corrupted Poly1305 MAC tag,
    - *Then* `CryptoService` drops the packet, logs a verification failure, and increments the tamper rejection counter.
- **Dependencies:**
  - `MeshDebuggerViewModel`, `CryptoService`.
- **Verification:**
  - *Unit:* `MeshDebuggerTests.testFaultInjectionTamperRejection`

---

### US-DBG-05: Virtual Multi-Node Topology Sandbox Simulation
- **Story Information:**
  - **ID:** `US-DBG-05`
  - **Feature Area:** Diagnostics
  - **User Role:** `ROLE-ENG` (Architect / QA Engineer)
  - **User Story:** As a developer testing multi-hop mesh routing, I want to simulate 3-node and 4-node topologies in memory and break links dynamically, so that I can verify AODV convergence on a single test device.
  - **User Benefit:** Rapid multi-hop routing regression verification without needing multiple physical iPhones.
  - **Priority:** `High` | **Status:** `Implemented` | **Target Phase:** `Phase 2`
- **Acceptance Criteria:**
  - **Scenario 1: Multi-node topology simulation**
    - *Given* `MeshTopologySimulator` simulating Alice $\leftrightarrow$ Relay $\leftrightarrow$ Bob,
    - *When* the user toggles "Break Link A-R",
    - *Then* route discovery re-triggers and packets re-converge over available paths.
- **Dependencies:**
  - `MeshTopologySimulator`, `SimulatedMeshTransport`.
- **Verification:**
  - *Unit:* `MeshFailureIntegrationTests.testTopologyPartitionAndReconvergence`

---

## 11. Section IX: Apple Watch Companion (`TeeKumWatch`, Planned Phase 4)

### US-WAT-01: Tethered Watch Companion & Smart Stack
- **Story Information:**
  - **ID:** `US-WAT-01`
  - **Feature Area:** Apple Watch
  - **User Role:** `ROLE-WAT` (Watch User)
  - **User Story:** As an attendee wearing an Apple Watch, I want my watch to mirror my group's status in the watchOS Smart Stack, so that I can check on my friends by raising my wrist.
  - **User Benefit:** Glanceable wrist awareness without taking an iPhone out of a pocket in dense crowds.
  - **Priority:** `High` | **Status:** `Planned` | **Target Phase:** `Phase 4`
- **Acceptance Criteria:**
  - **Scenario 1: Wrist Smart Stack mirroring**
    - *Given* an active TeeKum session on the host iPhone,
    - *When* raising the wrist,
    - *Then* the watchOS Smart Stack card displays closest friend distance, active meeting point, and session name via `WatchConnectivity` (`WCSession`).
- **Dependencies:**
  - `WatchConnectivity`, `TeeKumWatch` target (to be created), `ActivityKit`.
- **Verification:**
  - *Unit:* Planned `WatchSessionSyncTests`
  - *Device:* Requires paired physical iPhone and Apple Watch.

---

### US-WAT-02: High-Intensity Wrist Taptic SOS Alerts
- **Story Information:**
  - **ID:** `US-WAT-02`
  - **Feature Area:** Apple Watch
  - **User Role:** `ROLE-WAT` (Watch User)
  - **User Story:** As an attendee in a 105 dB stage environment, I want high-intensity wrist Taptic Engine vibration when a friend triggers SOS, so that I feel the distress call immediately even if I cannot hear the iPhone siren.
  - **User Benefit:** Tactile emergency alerting guaranteed to penetrate extreme ambient acoustics.
  - **Priority:** `Critical` | **Status:** `Planned` | **Target Phase:** `Phase 4`
- **Acceptance Criteria:**
  - **Scenario 1: Wrist emergency haptics**
    - *Given* an inbound authenticated SOS alert on the host iPhone,
    - *When* forwarded via `WCSession.sendMessage`,
    - *Then* the watch triggers rapid, high-intensity haptic pulses (`WKHapticType.failure`) continuously until acknowledged.
- **Dependencies:**
  - `WatchKit` (`WKInterfaceDevice.play`), `WatchConnectivity`.
- **Verification:**
  - *Device:* Physical Apple Watch testing in high-noise venue.

---

### US-WAT-03: Discrete 3-Second Wrist SOS Trigger
- **Story Information:**
  - **ID:** `US-WAT-03`
  - **Feature Area:** Apple Watch
  - **User Role:** `ROLE-WAT` (Distressed Member)
  - **User Story:** As an attendee experiencing distress in a crowd crush who cannot reach my pocket, I want to trigger emergency SOS from my watch, so that I can summon help discreetly.
  - **User Benefit:** Hands-free emergency signaling when phone access is physically blocked.
  - **Priority:** `High` | **Status:** `Planned` | **Target Phase:** `Phase 4`
- **Acceptance Criteria:**
  - **Scenario 1: Wrist SOS dispatch**
    - *Given* the user is wearing an Apple Watch,
    - *When* holding the on-screen watch SOS button for 3 seconds,
    - *Then* the watch sends an immediate high-priority command to the host iPhone to dispatch an emergency SOS datagram across the mesh.
- **Dependencies:**
  - `WCSession`, `PriorityOutboxQueue`.
- **Verification:**
  - *Integration:* Planned watchOS-to-iOS IPC test harness.

---

### US-WAT-04: Heads-Up Wrist Compass & Bearing Guidance
- **Story Information:**
  - **ID:** `US-WAT-04`
  - **Feature Area:** Apple Watch
  - **User Role:** `ROLE-WAT` (Navigating Member)
  - **User Story:** As an attendee walking toward a friend, I want a directional compass arrow and distance readout on my wrist with alignment haptics, so that I can navigate with my hands free.
  - **User Benefit:** Effortless heads-up crowd navigation without holding an iPhone in front of the face.
  - **Priority:** `High` | **Status:** `Planned` | **Target Phase:** `Phase 4`
- **Acceptance Criteria:**
  - **Scenario 1: Wrist compass navigation**
    - *Given* an active navigation target,
    - *When* viewing the watch navigation view,
    - *Then* the watch displays a rotating compass arrow, distance in meters, and fires a subtle tap (`WKHapticType.directionUp`) when facing directly toward the target.
- **Dependencies:**
  - `CoreLocation` heading on watchOS, `WatchConnectivity`.
- **Verification:**
  - *Device:* Field validation on Apple Watch.

---

### US-WAT-05: 1-Tap Wrist Meeting Point RSVP
- **Story Information:**
  - **ID:** `US-WAT-05`
  - **Feature Area:** Apple Watch
  - **User Role:** `ROLE-WAT` (Watch User)
  - **User Story:** As an attendee receiving a meeting point update on my wrist, I want to tap "I'll be there" or "Can't make it", so that I can RSVP in one second without unlocking my iPhone.
  - **User Benefit:** Quick, one-second meeting confirmations directly from the wrist.
  - **Priority:** `Medium` | **Status:** `Planned` | **Target Phase:** `Phase 4`
- **Acceptance Criteria:**
  - **Scenario 1: Wrist RSVP**
    - *When* tapping "I'll be there" on the watch meeting card,
    - *Then* the response syncs to the iPhone via `updateApplicationContext` and broadcasts across the mesh.
- **Dependencies:**
  - `WatchConnectivity`, `MeetingPointViewModel`.
- **Verification:**
  - *Integration:* Planned `WatchRSVPSyncTests`.

---

## 12. Section X: Multi-Floor & Altitude Awareness (Planned Phase 4)

### US-ALT-01: Peer-to-Peer Differential Barometry
- **Story Information:**
  - **ID:** `US-ALT-01`
  - **Feature Area:** Multi-Floor & Altitude
  - **User Role:** `ROLE-NAV` (Navigating Member)
  - **User Story:** As an attendee in a multi-story stadium or arena, I want my app to calculate vertical separation using atmospheric pressure comparison with my friends' phones, so that we know who is on a balcony or bleacher level without internet.
  - **User Benefit:** Sub-meter vertical elevation tracking without indoor GPS or cloud map infrastructure.
  - **Priority:** `High` | **Status:** `Planned` | **Target Phase:** `Phase 4`
- **Acceptance Criteria:**
  - **Scenario 1: Differential barometric calculation**
    - *Given* co-located devices sampling pressure via `CMAltimeter`,
    - *When* computing vertical distance,
    - *Then* the app calculates $\Delta h \approx 8.43 \times \Delta P$ meters, canceling regional atmospheric weather shifts.
- **Dependencies:**
  - `CoreMotion` (`CMAltimeter`), `LocationPingPayload` (Bytes 18..20).
- **Verification:**
  - *Unit:* Planned `DifferentialBarometryTests`.

---

### US-ALT-02: 2D Map Multi-Floor Switcher & Elevation Badges
- **Story Information:**
  - **ID:** `US-ALT-02`
  - **Feature Area:** Multi-Floor & Altitude
  - **User Role:** `ROLE-NAV` (Navigating Member)
  - **User Story:** As an attendee looking at a stadium map, I want a floor switcher pill (`All`, `L1`, `L2`, `L3`) and vertical delta badges on friend pins, so that I can see which level each person is on.
  - **User Benefit:** Clear multi-story spatial separation preventing confusion in tiered arenas.
  - **Priority:** `Medium` | **Status:** `Planned` | **Target Phase:** `Phase 4`
- **Acceptance Criteria:**
  - **Scenario 1: Floor filtering**
    - *When* tapping "L2" on the floor switcher,
    - *Then* members on Level 2 remain brightly highlighted, while members on other levels dim and display elevation badges (e.g. *"-1 Floor"*).
- **Dependencies:**
  - `MainMapView`, `MapViewModel`.
- **Verification:**
  - *UI:* Planned `MultiFloorMapFilterTests`.

---

### US-ALT-03: Vertical Elevation Warning in Tactical Radar
- **Story Information:**
  - **ID:** `US-ALT-03`
  - **Feature Area:** Tactical Navigation
  - **User Role:** `ROLE-NAV` (Navigating Member)
  - **User Story:** As an attendee approaching a friend who is on a mezzanine directly above me, I want the radar to tell me they are on a higher level, so that I don't look around in confusion when horizontal distance says "0 meters".
  - **User Benefit:** Prevention of "0-meter arrival" confusion in multi-story stadium venues.
  - **Priority:** `High` | **Status:** `Planned` | **Target Phase:** `Phase 4`
- **Acceptance Criteria:**
  - **Scenario 1: Elevation arrival alert**
    - *Given* horizontal distance is $<10\text{m}$ but vertical delta $\ge 3.0\text{m}$,
    - *When* viewing the tactical radar,
    - *Then* the screen displays a prominent banner: *"Target Above on Level 2 — Take Stairs"*.
- **Dependencies:**
  - `RadarView`, `FinderBeaconView`.
- **Verification:**
  - *Unit:* Planned `RadarVerticalElevationWarningTests`.

---

### US-ALT-04: Manual Floor Selection & Calibrated Override
- **Story Information:**
  - **ID:** `US-ALT-04`
  - **Feature Area:** Multi-Floor & Altitude
  - **User Role:** `ROLE-NAV` (Attendee)
  - **User Story:** As an attendee in a venue where barometers are erratic due to HVAC vents, I want to manually select my floor level, so that my friends still know what floor I am on.
  - **User Benefit:** Robust manual override when automatic environmental sensors are noisy.
  - **Priority:** `Medium` | **Status:** `Planned` | **Target Phase:** `Phase 4`
- **Acceptance Criteria:**
  - **Scenario 1: Manual floor selection**
    - *When* the user selects "Mezzanine (L2)" in their profile sheet,
    - *Then* `floorLevel` byte on the wire sets to 2, overriding automatic barometric classification.
- **Dependencies:**
  - `LocationService`, `LocationPingPayload`.
- **Verification:**
  - *Unit:* Planned `ManualFloorOverrideTests`.

---

> **End of User Stories Specification**  
> *Author:* Senior Product Owner & Requirements Engineer  
> *Next Document:* [Product Backlog (PRODUCT_BACKLOG.md)](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/product/PRODUCT_BACKLOG.md)
