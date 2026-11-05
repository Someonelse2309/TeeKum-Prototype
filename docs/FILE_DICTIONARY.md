# TeeKum — Codebase File Dictionary & Architecture Reference

> **Audience:** Engineering Team, New Hires, and System Auditors  
> **Target Scope:** 100% of all Swift source and test files in `TeeKum Prototype/`  
> **Last Updated:** 5 November 2026 (Modular Architecture Refactoring)

---

## Table of Contents
1. [App Root & Lifecycle (`App/`)](#1-app-root--lifecycle-app)
2. [Features Layer (`Features/`)](#2-features-layer-features)
   - [Pairing & Group Formation](#21-pairing--group-formation-featurespairing)
   - [Map & Location Visualizer](#22-map--location-visualizer-featuresmap)
   - [Festival Group Mesh Chat](#23-festival-group-mesh-chat-featureschat)
   - [Meeting Points & Dynamic Rendezvous](#24-meeting-points--dynamic-rendezvous-featuresmeetingpoint)
   - [Emergency SOS & Inactivity Guard](#25-emergency-sos--inactivity-guard-featuressos)
   - [Tactical Radar & Directional Finder](#26-tactical-radar--directional-finder-featuresfinder)
   - [Diagnostics & Simulation Lab](#27-diagnostics--simulation-lab-featuresdiagnostics)
3. [Core Messaging & Wire Protocols (`Core/Messaging/`)](#3-core-messaging--wire-protocols-coremessaging)
   - [Protocol Enums & Codec Errors](#31-protocol-enums-coremessagingenums)
   - [Wire Models & Envelope](#32-wire-models-coremessagingmodels)
   - [30-Byte Payloads](#33-30-byte-payloads-coremessagingpayloads)
   - [Codecs, Routing & Outbox](#34-codecs-routing--outbox-coremessaging)
4. [Core Mesh Networking (`Core/Mesh/`)](#4-core-mesh-networking-coremesh)
5. [Core Transport Layer (`Core/Transport/`)](#5-core-transport-layer-coretransport)
6. [Core Domain Models & Enums (`Core/Models/`)](#6-core-domain-models--enums-coremodels)
7. [Core Platform Services (`Security/`, `Location/`, `Notifications/`, `LiveActivity/`)](#7-core-platform-services)
8. [Shared Design System & Formatters (`Shared/UI/`)](#8-shared-design-system--formatters-sharedui)
9. [Automated Regression Test Suites (`Tests/`)](#9-automated-regression-test-suites-tests)

---

## 1. App Root & Lifecycle (`App/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`App/TeeKumApp.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/App/TeeKumApp.swift) | `struct TeeKumApp: App`, `final class SessionHolder` | **The Composition Root.** Declares top-level `@State` view models and services, manages `scenePhase` foreground/background transitions, evaluates battery level shifts to trigger Festival Survival Mode (<20%), runs the headless CLI automated test runner (`-runAllTests`), and provides a thread-safe `SessionHolder` lock wrapper for nonisolated closures. |
| [`App/AppRootView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/App/AppRootView.swift) | `struct AppRootView: View` | **Presentation Switcher.** Decoupled SwiftUI root. Inspects `sessionViewModel.hasActiveSession`: renders `MainMapView` when paired and active, or `GroupPairingView` when in the onboarding/unpaired state. Manages session startup and teardown tasks cleanly. |

---

## 2. Features Layer (`Features/`)

### 2.1 Pairing & Group Formation (`Features/Pairing/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Features/Pairing/Views/GroupPairingView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/Views/GroupPairingView.swift) | `struct GroupPairingView: View` | **Onboarding & Group Creation UI.** Renders the create-group form, initials text input (1–3 letters), color picker chips, invite deep-link entry, and scan-to-join camera trigger. |
| [`Features/Pairing/Views/QRCodeView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/Views/QRCodeView.swift) | `struct QRCodeView: View` | **QR Barcode Display.** Renders the current group's 256-bit symmetric encryption key and 24-bit session ID into a high-contrast `CoreImage` QR barcode for offline camera scanning, paired with a native iOS `ShareLink`. |
| [`Features/Pairing/Views/QRScannerView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/Views/QRScannerView.swift) | `struct QRScannerView: UIViewControllerRepresentable` | **Camera Capture Bridge.** Wraps `AVFoundation`'s `AVCaptureSession` and `AVCaptureMetadataOutput` to scan QR barcodes on venue floors without internet. Forwards raw strings to `GroupSessionViewModel`. |
| [`Features/Pairing/Views/MeshAgreementView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/Views/MeshAgreementView.swift) | `struct MeshAgreementView: View` | **Communal Relay Consent.** Bottom sheet presenting the ethical mesh pact (*"Relay for others while others relay for you; shuts off at 20% battery"*) before activating session relay participation. |
| [`Features/Pairing/Views/ColorPickerView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/Views/ColorPickerView.swift) | `struct ColorPickerView: View` | **Color Selection Grid.** Horizontal palette of 8 high-visibility neon colors (`MemberColor`) enabling quick personal identification on map pins and radar disks. |
| [`Features/Pairing/ViewModels/GroupSessionViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/ViewModels/GroupSessionViewModel.swift) | `@Observable @MainActor class GroupSessionViewModel` | **Session & Roster State.** Validates user initials (`A-Z`), manages active member roster, derives 256-bit CSPRNG symmetric keys via `SecRandomCopyBytes`, parses `teekum://join#key=...` invite links, and handles session persistence in `UserDefaults`. |

---

### 2.2 Map & Location Visualizer (`Features/Map/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Features/Map/Views/MainMapView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/MainMapView.swift) | `struct MainMapView: View` | **Primary MapKit Surface.** Renders offline-cached map regions, friend pins, accuracy uncertainty rings, dropped meeting points, and overlays floating action controls (Live Sharing toggle, SOS button, Chat button, Radar button). |
| [`Features/Map/Views/FriendDetailView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/FriendDetailView.swift) | `struct FriendDetailView: View` | **Friend Inspection Card.** Presented upon selecting a friend pin. Shows exact compass bearing (`180° S`), distance in meters, battery percentage, last sample age, and a 1-tap shortcut to open the Tactical Radar. |
| [`Features/Map/Views/FriendPinAnnotationView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/FriendPinAnnotationView.swift) | `struct FriendPinAnnotationView: View` | **Map Avatar Pin.** High-contrast circle showing friend initials, color-coded neon border, direct link radio badge, and emergency pulsing halos. |
| [`Features/Map/Views/HeadingVisionCone.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/HeadingVisionCone.swift) | `struct HeadingVisionCone: View` | **Facing Direction Beam.** A 50° translucent luminous vision cone drawn on the map canvas rotated to match the friend's physical magnetic compass orientation. |
| [`Features/Map/Views/RelaySettingsSheet.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/RelaySettingsSheet.swift) | `struct RelaySettingsSheet: View` | **Communal Relay Control.** Settings sheet allowing users to toggle between Always Active, Timed 30-Minute, or Disabled relay modes, showing real-time dropped and forwarded packet counters. |
| [`Features/Map/ViewModels/MapViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/ViewModels/MapViewModel.swift) | `@Observable @MainActor class MapViewModel` | **Map State Coordinator.** Tracks selected member pin, map camera viewport, heading rotation, and commands dynamic CoreLocation receiver accuracy scaling. |

---

### 2.3 Festival Group Mesh Chat (`Features/Chat/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Features/Chat/Views/ChatSheetView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Views/ChatSheetView.swift) | `struct ChatSheetView: View` | **Non-Intrusive Chat Drawer.** Docked bottom sheet over `MainMapView` presenting message history, input bar, quick preset chips, unread count badge, and individual per-peer ACK receipts. |
| [`Features/Chat/Views/ChatMessageBubbleView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Views/ChatMessageBubbleView.swift) | `struct ChatMessageBubbleView: View` | **Message Bubble UI.** Distinguishes local vs incoming bubbles, shows sender initials in personal member color, timestamp, and honest delivery ticks (single grey = relayed; double green = confirmed by friend). |
| [`Features/Chat/Views/PresetChipsView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Views/PresetChipsView.swift) | `struct PresetChipsView: View` | **1-Tap Quick Status Chips.** Scrollable chips ("Beer line", "At Main Stage", "Restroom", "Where are you?") allowing rapid festival communication without typing. |
| [`Features/Chat/Views/ByteMeterView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Views/ByteMeterView.swift) | `struct ByteMeterView: View` | **Capacity Meter.** Visual live gauge showing exact remaining capacity out of the 20-byte UTF-8 wire budget, turning amber at 16 bytes and red at 20 bytes. |
| [`Features/Chat/ViewModels/ChatViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/ViewModels/ChatViewModel.swift) | `@Observable @MainActor class ChatViewModel` | **Chat Presentation ViewModel.** Validates text input (1..20 bytes), tracks draft state, manages 3.0s cooldown rate limiting, unread badges, and binds to `ChatMessageEngine`. |
| [`Features/Chat/Services/ChatMessageEngine.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Services/ChatMessageEngine.swift) | `actor ChatMessageEngine: ChatMessagingService` | **Chat Protocol Engine.** Encodes 20-byte UTF-8 packets (`0x07`), dispatches in Tier 3 FIFO, manages 2 retries, tracks delivery state separately for every group member (`Delivered M/N`), and stores at most 50 messages strictly in RAM (zero disk persistence). |
| [`Features/Chat/Services/ChatMessagingService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Chat/Services/ChatMessagingService.swift) | `protocol ChatMessagingService: Actor` | **Chat Contract.** Dependency-inversion protocol defining chat sending, ephemeral history retrieval, and asynchronous message update streams. |

---

### 2.4 Meeting Points & Dynamic Rendezvous (`Features/MeetingPoint/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Features/MeetingPoint/Views/MeetingPointsView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/MeetingPoint/Views/MeetingPointsView.swift) | `struct MeetingPointsView: View` | **Active Rendezvous Banner.** Displays active meeting point, live countdown timer ("in 15m"), dynamic proposer title, and 1-tap RSVP buttons (*"I'll be there"*, *"Arrived"*, *"Can't make it"*). |
| [`Features/MeetingPoint/Views/SetMeetingPointSheet.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/MeetingPoint/Views/SetMeetingPointSheet.swift) | `struct SetMeetingPointSheet: View` | **Meeting Proposal Form.** Allows proposing a rendezvous at current GPS or long-pressed map pin, choosing quick time presets (*"Right Now"*, *"In 15m"*, *"In 30m"*, *"In 1h"*). |
| [`Features/MeetingPoint/Views/MeetingPointPinView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/MeetingPoint/Views/MeetingPointPinView.swift) | `struct MeetingPointPinView: View` | **Map Rendezvous Pin.** Glowing golden amber icon (`mappin.and.ellipse`) marking the rendezvous coordinate on MapKit with auto-arrival 25m boundary circle. |
| [`Features/MeetingPoint/ViewModels/MeetingPointViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/MeetingPoint/ViewModels/MeetingPointViewModel.swift) | `@Observable @MainActor class MeetingPointViewModel` | **Rendezvous Business Logic.** Enforces the **Setter Lock Rule** (only the proposer can cancel; others can only RSVP), manages 1-hour auto-TTL expiration, calculates 25m auto-arrival, and broadcasts updates (`0x03`). |

---

### 2.5 Emergency SOS & Inactivity Guard (`Features/SOS/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Features/SOS/Views/SOSButtonView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Views/SOSButtonView.swift) | `struct SOSButtonView: View` | **3-Second Hold Button.** Emergency trigger requiring continuous 3-second physical press with circular haptic progress ring to eliminate accidental triggers while dancing. |
| [`Features/SOS/Views/IncomingSOSAlertBannerView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Views/IncomingSOSAlertBannerView.swift) | `struct IncomingSOSAlertBannerView: View` | **Emergency Full-Screen HUD.** High-priority pulsating red banner surfaced upon receiving distress alerts, displaying friend name, battery level, distance, and 1-tap navigation CTA. |
| [`Features/SOS/Views/RecipientAckBreakdownView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Views/RecipientAckBreakdownView.swift) | `struct RecipientAckBreakdownView: View` | **Delivery Checklist.** Per-peer confirmation checklist distinguishing which friends have received the SOS alert vs which peers only relayed it. |
| [`Features/SOS/ViewModels/SOSViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/ViewModels/SOSViewModel.swift) | `@Observable @MainActor class SOSViewModel` | **Emergency State Machine.** Manages 3-second hold countdown, cancellation on early release, urgent Tier 1 priority queue dispatch, honest delivery states, and siren audio alerts. |
| [`Features/SOS/Services/SOSForwardingEngine.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Services/SOSForwardingEngine.swift) | `actor SOSForwardingEngine` | **Multi-Hop SOS Actor.** Prefers known unexpired routes in `RoutingTable`; falls back to bounded flooding (max 8 hops) when none exist. Deduplicates `sosEventId` and routes return ACKs. |
| [`Features/SOS/Services/SOSAudioAlert.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Services/SOSAudioAlert.swift) | `final class SOSAudioAlert` | **High-Decibel Siren.** Uses `AVAudioPlayer` to generate maximum-volume continuous sirens and `UIImpactFeedbackGenerator` haptic alarms for 100+ dB concert environments. |
| [`Features/SOS/Services/InactivityGuardService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Services/InactivityGuardService.swift) | `final class InactivityGuardService` | **"Man Down" Fall Monitor.** Observes `CoreMotion` accelerometer/gyro stillness. When stillness exceeds threshold (3m), triggers a 30s silent pre-alarm countdown before auto-broadcasting SOS (`SOSType.inactivity = 0x04`). |

---

### 2.6 Tactical Radar & Directional Finder (`Features/Finder/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Features/Finder/Views/FinderBeaconView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/FinderBeaconView.swift) | `struct FinderBeaconView: View` | **Close-Range Navigation Container.** Hosts the 60m Polar Tactical Radar and provides a 1-tap switcher to engage the high-visibility visual screen strobe torch. |
| [`Features/Finder/Views/Radar/RadarView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarView.swift) | `struct RadarView: View` | **60m Forward-Up Polar Radar Canvas.** Projects friends onto a forward-facing circular disk with 15m, 30m, and 60m range rings, rotating smoothly with device magnetometer heading. Distant peers (>60m) clamp to the perimeter with directional arrows. |
| [`Features/Finder/Views/Radar/RadarBlipView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarBlipView.swift) | `struct RadarBlipView: View` | **Radar Member Blip.** Renders member initials, neon color halo, and distance tag clamped to the circular radar boundary. |
| [`Features/Finder/Views/Radar/RadarCenterMarker.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarCenterMarker.swift) | `struct RadarCenterMarker: View` | **User Position Marker.** Glowing user reticle at radar center with 0° forward heading notch. |
| [`Features/Finder/Views/Radar/RadarFriendCard.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarFriendCard.swift) | `struct RadarFriendCard: View` | **Bottom Carousel Target Card.** Glanceable card showing selected peer's clock bearing (*"2 o'clock"*), distance in meters, and battery percentage. |
| [`Features/Finder/Views/Radar/RadarGridBackground.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarGridBackground.swift) | `struct RadarGridBackground: View` | **Concentric Range Grid.** Draws concentric range rings at 15m, 30m, and 60m, crosshair axes, and 15° perimeter ticks. |
| [`Features/Finder/Views/Radar/RadarTheme.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarTheme.swift) | `enum RadarTheme` | **Radar Design Tokens.** Colors, sweep animation constants, and range ring line styles. |

---

### 2.7 Diagnostics & Simulation Lab (`Features/Diagnostics/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Features/Diagnostics/Views/DiagnosticsView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/Views/DiagnosticsView.swift) | `struct DiagnosticsView: View` | **Debug Telemetry HUD.** Shows radio connection state, AWDL neighbor counts, measured packet rates, battery voltage, and 1-tap automated health triage. |
| [`Features/Diagnostics/Views/MeshDebuggerView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/Views/MeshDebuggerView.swift) | `struct MeshDebuggerView: View` | **Live Packet Inspector & Lab.** Displays live 56-byte binary packet hex dumps, bitfield inspector, packet injector, and virtual multi-node topology controls. |
| [`Features/Diagnostics/ViewModels/MeshDebuggerViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/ViewModels/MeshDebuggerViewModel.swift) | `@Observable @MainActor class MeshDebuggerViewModel` | **Debugger State Coordinator.** Manages live packet log streams, bitfield filters, and simulated multi-node mesh topology commands. |
| [`Features/Diagnostics/Services/MeshDiagnostics.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/Services/MeshDiagnostics.swift) | `final class MeshDiagnostics` | **Telemetry Metrics Engine.** Accumulates measured packet counters, average latencies, dropped packet counts, and route hop distributions. |
| [`Features/Diagnostics/Services/MeshTopologySimulator.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Diagnostics/Services/MeshTopologySimulator.swift) | `actor MeshTopologySimulator` | **Virtual Multi-Node Sandbox.** In-memory simulator modeling 3-to-5 virtual iPhones communicating across ad-hoc hops with real-time link breaking for zero-radio automated testing. |

---

## 3. Core Messaging & Wire Protocols (`Core/Messaging/`)

### 3.1 Protocol Enums (`Core/Messaging/Enums/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Core/Messaging/Enums/PacketType.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Enums/PacketType.swift) | `enum PacketType: UInt8` | **Wire Message Discriminators.** Types `0x01` through `0x08`: LocationPing (`0x01`), SOS (`0x02`), MeetingUpdate (`0x03`), RouteReq (`0x04`), RouteResp (`0x05`), ACK (`0x06`), ChatMessage (`0x07`), UWBTokenExchange (`0x08`). |
| [`Core/Messaging/Enums/SOSType.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Enums/SOSType.swift) | `enum SOSType: UInt8` | **Distress Categories.** General (`0x00`), Medical (`0x01`), Separated (`0x02`), Security (`0x03`), Inactivity / Man Down (`0x04`). |
| [`Core/Messaging/Enums/ACKStatus.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Enums/ACKStatus.swift) | `enum ACKStatus: UInt8` | **Wire Delivery Receipt Codes.** DeliveredToFriend (`0x01`) vs RelayedByMeshHop (`0x02`). |
| [`Core/Messaging/Enums/PacketCodecError.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Enums/PacketCodecError.swift) | `enum PacketCodecError: Error` | **Wire Validation Errors.** Localized error cases for buffer underflows, invalid packet sizes, unsupported versions, text overruns, and coordinate out-of-bounds. |

---

### 3.2 Wire Models (`Core/Messaging/Models/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Core/Messaging/Models/PacketConstants.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Models/PacketConstants.swift) | `enum PacketConstants` | **Protocol Layout Invariants.** Declares exact wire sizes: 56-byte wire datagram, 10-byte cleartext envelope, 30-byte encrypted payload, 16-byte Poly1305 MAC tag, 12-byte Nonce, and domain tag `"TKM3"`. |
| [`Core/Messaging/Models/CleartextEnvelope.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Models/CleartextEnvelope.swift) | `struct CleartextEnvelope` | **10-Byte Cleartext Header.** Serializes version (4b), type (4b), hopLimit (1B), hopCount (1B), sessionId (3B / 24-bit), and sequenceNumber (4B). Derives the 10-byte AAD (masking hopCount to `0x00`) and the 12-byte deterministic Nonce. |
| [`Core/Messaging/Models/RawWirePacket.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Models/RawWirePacket.swift) | `struct RawWirePacket` | **56-Byte Datagram Assembler.** Combines envelope (10B), ciphertext (30B), and Poly1305 tag (16B) into exactly 56 bytes for radio sockets, and slices incoming binary buffers. |

---

### 3.3 30-Byte Payloads (`Core/Messaging/Payloads/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Core/Messaging/Payloads/LocationPingPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/LocationPingPayload.swift) | `struct LocationPingPayload` | **Type 0x01.** Option B pure telemetry: Quantized signed 32-bit lat/lon (~11cm resolution), timestamp, horizontal accuracy, 2-byte compressed initials, battery, heading (0..255), color code, and 12-byte reserved zero padding. |
| [`Core/Messaging/Payloads/SOSPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/SOSPayload.swift) | `struct SOSPayload` | **Type 0x02.** Emergency alert: Coordinates, timestamp, accuracy, 32-bit unique event ID, sender initials, emergency type (including inactivity), battery level, and color code. |
| [`Core/Messaging/Payloads/MeetingUpdatePayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/MeetingUpdatePayload.swift) | `struct MeetingUpdatePayload` | **Type 0x03.** Dynamic rendezvous: Coordinates, meetup target time, proposal timestamp, action code (`0x01` propose, `0x02` accept, `0x04` cancel), meeting ID, sender initials, and arrival radius. |
| [`Core/Messaging/Payloads/RouteReqPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/RouteReqPayload.swift) | `struct RouteReqPayload` | **Type 0x04.** AODV route request: Originator initials, target initials, 32-bit discovery nonce, route hop cost, and 21 bytes reserved padding. |
| [`Core/Messaging/Payloads/RouteRespPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/RouteRespPayload.swift) | `struct RouteRespPayload` | **Type 0x05.** AODV route response: Originator initials, target initials, matching discovery nonce, and hop cost. |
| [`Core/Messaging/Payloads/ACKPayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/ACKPayload.swift) | `struct ACKPayload` | **Type 0x06.** Delivery acknowledgment: Acknowledged sequence number, sender initials, receipt timestamp, ACK status code, measured RSSI, event ID, and responder initials. |
| [`Core/Messaging/Payloads/ChatMessagePayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/ChatMessagePayload.swift) | `struct ChatMessagePayload` | **Type 0x07.** Festival chat: 2-byte sender initials, 4-byte timestamp, 1-byte text length ($0 \dots 20$), exactly 20 UTF-8 content bytes, and 3-byte reserved zero padding. |

---

### 3.4 Codecs, Routing & Outbox (`Core/Messaging/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Core/Messaging/PacketCodec.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/PacketCodec.swift) | `enum PacketCodec`, `struct PacketWriter`, `struct PacketReader` | **Safe Buffer Codec.** Provides bounds-checked binary reading/writing to eliminate underflow bugs. Centralizes coordinate quantization (`CLLocationDegrees` $\leftrightarrow$ signed big-endian `Int32`), compass heading quantization ($0 \dots 255$), and timestamp conversions. |
| [`Core/Messaging/PacketRouter.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/PacketRouter.swift) | `@MainActor final class PacketRouter` | **Inbound Packet Demux.** Inspects 10-byte cleartext envelopes. Forwards stranger packets to zero-knowledge blind relaying; opens in-group packets with ChaCha20-Poly1305 symmetric keys; routes payloads to Chat, SOS, Meeting Point, or Location handlers; prevents routing loops via `SeenPacketCache`. |
| [`Core/Messaging/InitialsCodec.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/InitialsCodec.swift) | `enum InitialsCodec` | **Base-27 Radix Codec.** Compresses 1 to 3 uppercase letters (`A...Z`) into exactly 2 bytes (`UInt16`, $18,278 \le 65,535$ combinations), eliminating runtime radio name handshakes. |
| [`Core/Messaging/PriorityOutboxQueue.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/PriorityOutboxQueue.swift) | `actor PriorityOutboxQueue` | **Dual-Lane Outbox.** Prioritizes urgent Tier 1 Emergency SOS packets and Tier 3 Chat packets ahead of periodic location pings, coalescing obsolete pings when radio links are backlogged. |

---

## 4. Core Mesh Networking (`Core/Mesh/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Core/Mesh/RoutingTable.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/RoutingTable.swift) | `actor RoutingTable: RoutingTableManaging` | **AODV Route Cache.** Tracks next-hop peer IDs, hop counts (metric), and route expiration timestamps (default 60s TTL), automatically invalidating broken links upon packet transmission failures. |
| [`Core/Mesh/NeighborTable.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/NeighborTable.swift) | `actor NeighborTable: NeighborManaging` | **Direct Radio Peering Roster.** Maintains direct AWDL link observations, hardware RSSI (dBm), direct link flags, and heartbeat freshness timestamps. |
| [`Core/Mesh/RouteDiscoveryService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/RouteDiscoveryService.swift) | `actor RouteDiscoveryService` | **On-Demand AODV Engine.** Broadcasts bounded `ROUTE_REQ` (RREQ) packets when no route exists for a peer, handles intermediate node caching, and unicasts `ROUTE_RESP` (RREP) back to originator. |
| [`Core/Mesh/PacketForwarder.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/PacketForwarder.swift) | `actor PacketForwarder` | **Blind Zero-Knowledge Relay.** Inspects only the 10-byte cleartext envelope, validates hopLimit $\le 8$, increments hopCount, preserves encrypted payload and Poly1305 MAC tag, and broadcasts to adjacent radio peers. |
| [`Core/Mesh/ForwardingRateLimiter.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/ForwardingRateLimiter.swift) | `actor ForwardingRateLimiter: ForwardingBudgetManaging` | **Dual-Lane Token Bucket.** Limits ordinary stranger relay forwarding to $\le 2$ pkts/sec (capacity 4 tokens) while providing a dedicated high-priority SOS lane (burst up to 4 pkts/sec) that preempts normal traffic. |
| [`Core/Mesh/SeenPacketCache.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/SeenPacketCache.swift) | `actor SeenPacketCache` | **1,024-Entry LRU Sliding Window.** Prevents multi-hop broadcast storms and replay attacks by deduplicating packets based on 7-byte composite key `(sessionId: 3B, sequenceNumber: 4B)` with a 5-minute expiration. |
| [`Core/Mesh/RelayPolicyManager.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/RelayPolicyManager.swift) | `actor RelayPolicyManager` | **Communal Mesh Policy.** Governs the 3 relay participation modes (Always Active, Timed 30 Min, Disabled) and enforces the hard 20% battery survival cutoff. |
| [`Core/Mesh/MeshProtocols.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/MeshProtocols.swift) | `protocol MeshClock`, `struct PacketKey` | **Testable Mesh Contracts.** Defines deterministic mock clocks (`TestMeshClock`, `SystemMeshClock`) for virtual time-stepping in unit tests, and defines the canonical 7-byte `PacketKey`. |
| [`Core/Mesh/MeshTimingConfiguration.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/MeshTimingConfiguration.swift) | `struct MeshTimingConfiguration` | **Hardware Tuning Constants.** Centralizes timing parameters: 30s stale peer threshold, 60s route TTL, 2.0s accelerated cadence, and 3.0s discovery timeouts. |

---

## 5. Core Transport Layer (`Core/Transport/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Core/Transport/PeerTransport.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Transport/PeerTransport.swift) | `protocol PeerTransport`, `struct InboundPacket`, `struct PeerInfo` | **Transport Contract & Models.** Injectable abstraction decoupling radio sockets from packet processing, declaring async streams for inbound datagrams and peer link state updates. |
| [`Core/Transport/PeerTransportService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Transport/PeerTransportService.swift) | `actor PeerTransportService: PeerTransport` | **Apple Wireless Direct Link Engine.** Configures `NWListener` and `NWBrowser` using Bonjour (`_teekum._tcp`) with `includePeerToPeer: true`. Manages simultaneous incoming and outgoing `NWConnection` sockets, connection pools, and automatic reconnects. |
| [`Core/Transport/StreamMessageFramer.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Transport/StreamMessageFramer.swift) | `final class StreamMessageFramer` | **56-Byte Stream Slicer.** Solves TCP/AWDL stream fragmentation by buffering partial chunks, slicing exact 56-byte frames, handling coalesced reads, and resynchronizing across corrupted leading bytes. |
| [`Core/Transport/SimulatedMeshTransport.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Transport/SimulatedMeshTransport.swift) | `actor SimulatedMeshTransport: MeshTransport` | **Zero-Radio Test Double.** In-memory simulated radio transport routing packets directly between virtual nodes without opening physical Wi-Fi or Bluetooth sockets. |

---

## 6. Core Domain Models & Enums (`Core/Models/`)

### 6.1 Domain Enums (`Core/Models/Enums/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Core/Models/Enums/MemberColor.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/MemberColor.swift) | `enum MemberColor: UInt8` | **8 Festival Colors.** Cyan, Lime, Orange, Yellow, Magenta, Purple, Coral, Mint (1 byte on wire; resolves deterministically if unassigned). |
| [`Core/Models/Enums/MeetingAction.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/MeetingAction.swift) | `enum MeetingAction: UInt8` | **Rendezvous Actions.** Propose (`0x01`), Accept (`0x02`), Decline (`0x03`), Cancel (`0x04`). |
| [`Core/Models/Enums/AttendanceStatus.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/AttendanceStatus.swift) | `enum AttendanceStatus: UInt8` | **RSVP States.** Attending (*"I'll be there"*), CantMakeIt (*"Can't make it"*), AtMeetingPoint (*"Arrived"*). |
| [`Core/Models/Enums/MeetingTimePreset.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/MeetingTimePreset.swift) | `enum MeetingTimePreset: Int` | **Meetup Time Offsets.** Right Now (0m), In 15m, In 30m, In 1h. |
| [`Core/Models/Enums/SOSDeliveryState.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/SOSDeliveryState.swift) | `enum SOSDeliveryState` | **Honest SOS Delivery Machine.** Idle, Countdown, LocalSending, RelayedAck, DeliveredToFriend, SearchingPeers, Failed. |
| [`Core/Models/Enums/RouteChoice.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/RouteChoice.swift) | `enum RouteChoice` | **Forwarding Path Classification.** DirectPeer, KnownRoute, BoundedFlooding, None. |
| [`Core/Models/Enums/AcknowledgementStage.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/AcknowledgementStage.swift) | `enum AcknowledgementStage: String` | **ACK Wire Verification Stages.** `IDLE`, `LOCAL_SENDING`, `SEARCHING_PEERS`, `RELAY_ACK`, `DELIVERED_TO_FRIEND`, `DELIVERY_TIMED_OUT`. |
| [`Core/Models/Enums/ChatDeliveryState.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/ChatDeliveryState.swift) | `enum ChatDeliveryState` | **Aggregated Chat Delivery.** LocallyAccepted, ForwardedToNextHop, RelayedByMesh, Delivered (M of N confirmed), DeliveryTimedOut. |
| [`Core/Models/Enums/RecipientDeliveryState.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/RecipientDeliveryState.swift) | `enum RecipientDeliveryState` | **Per-Friend Delivery State.** Individually tracks delivery progression for every single recipient of a chat message. |
| [`Core/Models/Enums/InboundChatOutcome.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/InboundChatOutcome.swift) | `enum InboundChatOutcome` | **Inbound Chat Demux Result.** DeliveredLocally, DeliveredLocallyAndRelayed, AckProcessed, RelayedStranger, DroppedDuplicate. |
| [`Core/Models/Enums/ChatEngineError.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Enums/ChatEngineError.swift) | `enum ChatEngineError: Error` | **Localized Chat Errors.** Cooldown active, text length invalid, battery throttled, survival mode active. |

---

### 6.2 Domain Entities (`Core/Models/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Core/Models/Member.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/Member.swift) | `struct Member: Identifiable` | **Group Peer Entity.** Holds member identity (initials), name, latest GPS coordinate, uncertainty radius, heading, battery level, direct link flag, RSSI, color, and calculates staleness ($>30\text{s}$). |
| [`Core/Models/GroupSession.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/GroupSession.swift) | `struct GroupSession: Identifiable, Codable` | **Active Session Entity.** Holds 16-bit session hash, group display name, 256-bit symmetric key bytes, local initials, and host status. |
| [`Core/Models/GroupSessionInvite.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/GroupSessionInvite.swift) | `struct GroupSessionInvite` | **Parsed Invite Payload.** Unpacks the Base64 symmetric key and session ID carried in URL fragments (`teekum://join#key=...`). |
| [`Core/Models/ChatMessage.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/ChatMessage.swift) | `struct ChatMessage: Identifiable` | **In-Memory Chat Entity.** Strictly ephemeral in-memory model holding message UUID, sequence number, sender initials, text content, per-recipient delivery dictionary, and overall delivery state. |
| [`Core/Models/MeetingPoint.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/MeetingPoint.swift) | `struct MeetingPoint: Identifiable` | **Rendezvous Entity.** Proposer initials, GPS coordinate, target meetup time, arrival radius (25m), and attendance map. Enforces the Single Active Meeting Point invariant. |
| [`Core/Models/LocationPin.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/LocationPin.swift) | `struct LocationPin` | **Geographic Pin Math.** Houses the global `coordinateScalingFactor` ($1,000,000.0$) and coordinate quantization conversions. |
| [`Core/Models/IncomingSOSAlert.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/IncomingSOSAlert.swift) | `struct IncomingSOSAlert: Identifiable` | **Distress Event Entity.** Originator initials, display name, distress category, measured GPS coordinates, accuracy, battery, and receipt timestamp. |
| [`Core/Models/SOSDiagnostics.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/SOSDiagnostics.swift) | `struct SOSDiagnostics` | **SOS Audit Snapshot.** Captures event ID, hop counts, retries, route choice, and delivery stage for diagnostic display. |
| [`Core/Models/SessionActivityAttributes.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/SessionActivityAttributes.swift) | `struct SessionActivityAttributes: ActivityAttributes` | **ActivityKit Contract.** Shared attributes compiled into both App and Widget Extension targets for Dynamic Island and Lock Screen mirroring. |
| [`Core/Models/TeeKumConfiguration.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/TeeKumConfiguration.swift) | `enum TeeKumConfiguration` | **Central Configuration Matrix.** Defines protocol version, wire packet byte budgets, timing constants, battery cutoffs (20%), and GNSS distance filters. |

---

## 7. Core Platform Services

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Core/Security/CryptoServiceProtocol.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Security/CryptoServiceProtocol.swift) | `protocol CryptoServiceProvider: Actor` | **Cryptographic Contract.** Defines symmetric key generation, authenticated sealing with AAD, tamper-evident decryption, and Keychain storage methods. |
| [`Core/Security/CryptoService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Security/CryptoService.swift) | `actor CryptoService: CryptoServiceProvider` | **CryptoKit AEAD Engine.** Performs ChaCha20-Poly1305 sealing and opening. Binds 10-byte cleartext envelope as AAD (masking `hopCount` to `0x00`), builds 12-byte nonces, drops tampered packets, and stores 256-bit keys in iOS Keychain. |
| [`Core/Location/LocationServiceProtocol.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Location/LocationServiceProtocol.swift) | `protocol LocationServiceProtocol` | **Location Sensor Contract.** Abstract contract for coordinates, accuracy, compass heading, motion activity, and battery updates. |
| [`Core/Location/LocationService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Location/LocationService.swift) | `@Observable @MainActor class LocationService` | **Dynamic GNSS & CoreMotion Engine.** Evaluates Option B dynamic accuracy: engages dual-frequency GPS (`BestForNavigation`) when Tactical Radar is active, dropping back to 100m when stationary via `CMMotionActivity` to save ~70% battery. Monitors battery levels and Low Power Mode. |
| [`Core/Location/LocationPublisher.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Location/LocationPublisher.swift) | `final class LocationPublisher` | **Adaptive Broadcast Scheduler.** Schedules location pings based on motion state: broadcasts every 3–5s while moving, 15–30s while stationary, accelerates to 2.0s when peers are distant or stale, and silences broadcasts when Live Sharing is toggled OFF. |
| [`Core/Notifications/NotificationService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Notifications/NotificationService.swift) | `@MainActor final class NotificationService` | **In-App Toast & Alert Dispatcher.** Displays non-intrusive floating toasts for incoming chat messages and rendezvous proposals, and triggers local notifications when the app is in the background. |
| [`Core/LiveActivity/LiveActivityManager.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/LiveActivity/LiveActivityManager.swift) | `actor LiveActivityManager` | **ActivityKit Lifecycle Controller.** Starts, updates, and terminates Dynamic Island and Lock Screen Live Activities reflecting connected peer counts, active rendezvous countdowns, and SOS alerts. |

---

## 8. Shared Design System & Formatters (`Shared/UI/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Shared/UI/Formatters.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Shared/UI/Formatters.swift) | Extensions on `CLLocationDistance`, `Float`, `Double`, `Date` | **Centralized Value Formatters.** High-performance formatters avoiding allocations during 60Hz UI renders: formats distance (`12m`, `1.4km`), battery percentages, SF Symbols, clock bearings (*"2 o'clock"*), and cached `DateFormatter` singletons. |
| [`Shared/UI/InAppToastView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Shared/UI/InAppToastView.swift) | `struct InAppToastView: View`, `struct InAppToast` | **Floating HUD Banner.** Top-docked animated banner presenting peer connection alerts, meeting proposals, and chat notifications without obscuring navigation maps. |

---

## 9. Automated Regression Test Suites (`Tests/`)

### 9.1 Feature View & ViewModel Tests (`Tests/Features/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Tests/Features/ChatUITests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Features/ChatUITests.swift) | `enum ChatUITests` | **11 Tests (100% Pass).** Tests chat message bubble rendering, honest delivery state progression (relayed $\neq$ delivered), preset chip selection, 20-byte clamping, unread badges, and conversation teardown purges. |
| [`Tests/Features/UIStateTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Features/UIStateTests.swift) | `enum UIStateTests` | **13 Tests (100% Pass).** Tests session creation, serverless QR invite parsing, initials sanitization, single active meeting point rules, setter locks, and teardown state resets. |
| [`Tests/Features/MeshDebuggerTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Features/MeshDebuggerTests.swift) | `enum MeshDebuggerTests` | **10 Tests (100% Pass).** Tests live 56-byte packet stream logging, bitfield bitmasking, corrupted MAC packet injection, and virtual topology link breaking. |

---

### 9.2 Core Protocol, Codec & Security Tests (`Tests/Core/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Tests/Core/PacketCodecTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/PacketCodecTests.swift) | `enum PacketCodecTests` | **20 Tests (100% Pass).** Validates bit-for-bit serialization, Int32 coordinate quantization ($<11\text{cm}$ resolution), 10-byte cleartext envelope, deterministic AEAD test vectors, Base-27 initials codec, and regression across all 8 PacketTypes. |
| [`Tests/Core/CryptoSecurityTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/CryptoSecurityTests.swift) | `enum CryptoSecurityTests` | **13 Tests (100% Pass).** Verifies ChaCha20-Poly1305 authenticated encryption, envelope AAD binding, hop-count mask verification, wrong-key rejection, and tamper rejection. |
| [`Tests/Core/PeerTransportTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/PeerTransportTests.swift) | `enum PeerTransportTests` | **14 Tests (100% Pass).** Tests 56-byte stream framing, 1-byte chunk reassembly, coalesced reads, garbled byte resync, and priority outbox preemption (SOS over pings). |
| [`Tests/Core/NeighborDiscoveryTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/NeighborDiscoveryTests.swift) | `enum NeighborDiscoveryTests` | **13 Tests (100% Pass).** Tests direct link detection, RSSI updates, heartbeat expiration, and peer roster synchronization. |
| [`Tests/Core/RouteDiscoveryTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/RouteDiscoveryTests.swift) | `enum RouteDiscoveryTests` | **14 Tests (100% Pass).** Tests AODV RREQ broadcast flooding, reverse route establishment, intermediate node caching, and unicast RREP response routing. |
| [`Tests/Core/RoutingForwardingTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/RoutingForwardingTests.swift) | `enum RoutingForwardingTests` | **12 Tests (100% Pass).** Tests zero-knowledge blind forwarding, hop limit enforcement ($\le 8$), hop count incrementation, and duplicate drop verification. |
| [`Tests/Core/RelayPolicyTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Mesh/RelayPolicyManager.swift) | `enum RelayPolicyTests` | **12 Tests (100% Pass).** Tests Always Active, 30-minute auto-expiry timer, Disabled relay modes, and hard 20% battery cutoff enforcement. |
| [`Tests/Core/InactivityGuardTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/InactivityGuardTests.swift) | `enum InactivityGuardTests` | **9 Tests (100% Pass).** Tests accelerometer stillness detection, 30s pre-alarm countdown, physical motion cancellation, and auto-dispatch of `SOSType.inactivity` (`0x04`). |
| [`Tests/Core/LocationPublishingTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/LocationPublishingTests.swift) | `enum LocationPublishingTests` | **15 Tests (100% Pass).** Tests dynamic cadence (moving vs stationary), distant peer acceleration, Live Sharing OFF silence, and Survival Mode throttle. |
| [`Tests/Core/LiveActivityTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/LiveActivityTests.swift) | `enum LiveActivityTests` | **6 Tests (100% Pass).** Tests Lock Screen and Dynamic Island telemetry mirroring, meeting point updates, and SOS alert priority. |

---

### 9.3 Multi-Peer Integration Tests (`Tests/Integration/`)

| File Path | Primary Types | Role & Explanation |
| :--- | :--- | :--- |
| [`Tests/Integration/SOSEndToEndTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Integration/SOSEndToEndTests.swift) | `enum SOSEndToEndTests` | **11 Tests (100% Pass).** End-to-end integration: 3s hold trigger $\rightarrow$ Tier 1 priority queue $\rightarrow$ radio broadcast $\rightarrow$ peer siren audio $\rightarrow$ return delivery ACK. |
| [`Tests/Integration/MultiHopSOSTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Integration/MultiHopSOSTests.swift) | `enum MultiHopSOSTests` | **11 Tests (100% Pass).** Tests 3-node simulated relay: Alice $\rightarrow$ Stranger Relay $\rightarrow$ Bob, verifying zero-knowledge preservation and honest `relayedAck` delivery state. |
| [`Tests/Integration/MeshFailureIntegrationTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Integration/MeshFailureIntegrationTests.swift) | `enum MeshFailureIntegrationTests` | **12 Tests (100% Pass).** Tests network partition recovery, link breaks, route invalidation, and AODV re-discovery. |
| [`Tests/Integration/ChatMessagingEngineTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Integration/ChatMessagingEngineTests.swift) | `enum ChatMessagingEngineTests` | **16 Tests (100% Pass).** End-to-end multi-peer chat across direct and relayed hops, 3.0s cooldown enforcement, and per-recipient ACK receipts. |
