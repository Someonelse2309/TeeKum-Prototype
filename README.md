# TeeKum — Offline-First Concert & Festival Mesh Navigation

[![Platform](https://img.shields.io/badge/Platform-iOS%2017.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9%20%2F%20Swift%206%20Ready-orange.svg)](https://swift.org)
[![Frameworks](https://img.shields.io/badge/Dependencies-0%20External%20(100%25%20Apple%20Native)-green.svg)](docs/knowledge_transfer/TECH_STACK.md)
[![Architecture](https://img.shields.io/badge/Architecture-Pure%20MVVM%20%2B%20Actors-purple.svg)](docs/knowledge_transfer/ARCHITECTURE.md)
[![Tests](https://img.shields.io/badge/Tests-18%20Suites%20%2F%20220%20Passing%20(100%25)-brightgreen.svg)](docs/knowledge_transfer/DEVELOPMENT_GUIDELINES.md#10-testing-expectations--quality-gates)

> **TeeKum** is a decentralized, serverless, ad-hoc peer-to-peer mesh navigation and communication iOS app engineered specifically for cellular-denied concert and music festival environments. When 50,000 to 100,000 attendees overwhelm cellular towers, TeeKum enables friends to locate one another, synchronize meeting points, exchange group chat messages, and dispatch emergency SOS alerts directly between iPhones over Apple Wireless Direct Link (AWDL) and Wi-Fi Direct.

---

## Key Capabilities

1. **100% Serverless Group Pairing:** Form private groups in seconds without cloud accounts, databases, or phone numbers via in-person AVFoundation QR barcode scanning or offline/online URL fragment links (`teekum://join#key=...`).
2. **Pure Location Telemetry (Option B):** Periodic location frames transmit coordinates (~11cm `Int32` quantization), accuracy, battery %, facing compass heading ($0^\circ \dots 360^\circ$), and personal neon member color.
3. **Tactical Polar Radar & Directional Guidance:** High-contrast 60m AMOLED polar radar (`RadarView`) rotating dynamically with device compass heading (Forward-Up), with 60m perimeter clamping and clock-face guidance (*"Ahead"*, *"2 o'clock"*).
4. **Apple Ultra-Wideband (U1/U2) Precision Finding:** Centimeter-accurate directional guidance (<8 meters) via Apple `NearbyInteraction` (`NISession`) with sensor-assisted simulation fallback.
5. **Festival Group Mesh Chat & Quick Preset Chips:** Compact 20-byte UTF-8 multi-hop text engine (`Type 0x07`) with instant festival preset chips (*"Beer line"*, *"At Main Stage"*, *"Restroom"*, *"Lost"*), character byte metering, and per-recipient delivery confirmation (`sent` $\rightarrow$ `relayed` $\rightarrow$ `delivered`).
6. **Single Active Meeting Point & Setter Lock Rule:** Synchronize a single group rendezvous landmark with dynamic countdowns. The setter holds an exclusive lock until unset or expired (1-hour cutoff); non-setter interaction is strictly RSVP (*"I'll be there"*, *"Can't make it"*, *"Arrived"*).
7. **Emergency SOS & Man Down Inactivity Guard:** 3-second continuous hold emergency trigger dispatching high-priority multi-hop SOS sirens; plus CoreMotion accelerometer stillness watchdog detecting 180s stillness with a 30-second silent pre-alarm countdown before auto-broadcasting `SOSType.inactivity` (`Type 0x04`).
8. **Zero-Knowledge Communal Mesh Relaying:** Blind multi-hop packet forwarding across attendee phones (max 8–15 hops) with 10-byte cleartext envelopes, ChaCha20-Poly1305 encrypted payloads, dual-lane rate limiting (2.0 pkts/s normal, 4.0 pkts/s SOS), and automatic shutoff at 20% battery (Festival Survival Mode).
9. **Lock Screen Live Activity & Dynamic Island:** Persistent background pocket execution (`showsBackgroundLocationIndicator = true`) displaying connected peers, rendezvous distance, and communal relay controls.
10. **On-Device Mesh Debugger & Diagnostic Lab:** Secret in-app diagnostic suite with 1-tap automated health triage, live 56-byte packet inspector, synthetic/fault packet injector, and virtual multi-node topology sandbox.

---

## Repository Structure & Targets

```text
TeeKum Prototype/
├── agent.md                              # Symlink to docs/agent.md (Master Agent Instructions)
├── README.md                             # Project overview, setup, build, and test instructions
├── TeeKum Prototype.xcodeproj            # Xcode project file (Schemes: Main App & Widgets)
├── Config/                               # Target Info.plist and entitlements configuration
│   ├── Info.plist                        # Main target permissions (AWDL, Location, Bonjour)
│   └── Widgets-Info.plist                # Widget extension configuration
├── TeeKum Prototype/                     # Primary iOS Application Target
│   ├── App/                              # App entry point (TeeKumApp.swift), test runner bridge
│   ├── Models/                           # 56B packet wire format, entities, codecs, master config
│   ├── Services/                         # Background actor services (transport, crypto, routing)
│   ├── ViewModels/                       # Pure MVVM @Observable @MainActor state stores
│   ├── Views/                            # SwiftUI presentation views, Tactical Radar, MapKit
│   │   └── Components/                   # Reusable UI components, message bubbles, chips
│   │       └── Radar/                    # Polar radar grid, blips, cards, UWB overlay
│   └── Tests/                            # 18 automated regression test suites (220 tests)
├── TeeKumWidgets/                        # ActivityKit Dynamic Island & Lock Screen Extension
│   ├── SessionActivityAttributes.swift   # ActivityKit attributes contract
│   ├── SessionActivityWidget.swift       # Widget configuration
│   ├── SessionLiveActivityView.swift     # Expanded and compact Dynamic Island views
│   └── TeeKumWidgetBundle.swift          # Widget bundle entry point
└── docs/                                 # Comprehensive Documentation Suite
    ├── agent.md                          # Master agent instructions and product principles
    ├── TechnicalRequirements.md          # Technical specifications and requirements
    ├── DEVELOPMENT_LOG.md                # Continuous chronological development ledger
    ├── knowledge_transfer/               # Standalone 11-document knowledge transfer package
    ├── Phase 1/                          # Historical Phase 1 specifications and reports
    ├── Phase 2/                          # Historical Phase 2 specifications and reports
    └── phase3/                           # Phase 3 chat, wire protocol, and test specifications
```

---

## Setup & Installation

### Prerequisites
- **macOS:** macOS Sonoma 14.0+ or macOS Sequoia 15.0+
- **Xcode:** Xcode 15.0+ or Xcode 16.0+ (Tested on Xcode 27.1 / Swift 5.10 toolchain)
- **iOS Deployment Target:** iOS 17.0+
- **Hardware (Optional for RF testing):** Two or more physical iPhones with active Wi-Fi and Bluetooth radios (iPhone 11+ for UWB Nearby Interaction).

### Zero External Dependencies
TeeKum relies **100% on native Apple frameworks**. There are no CocoaPods, Carthage dependencies, or Swift Package Manager (SPM) packages to resolve or install. Clone the repository and build immediately:

```bash
git clone https://github.com/Someonelse2309/TeeKum-Prototype.git
cd "TeeKum Prototype"
```

---

## Build Instructions

### Building via Xcode GUI
1. Open `TeeKum Prototype.xcodeproj` in Xcode.
2. Select the `TeeKum Prototype` scheme.
3. Select a destination (e.g., `iPhone 18 Pro` simulator or a connected physical iPhone).
4. Press `Cmd + B` to build, or `Cmd + R` to run.

### Building via Command Line (`xcodebuild`)
```bash
xcodebuild -scheme "TeeKum Prototype" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath .derivedData \
  build
```

---

## Automated Test Execution

TeeKum includes **18 automated test suites containing 220 unit and integration tests** compiled directly into the application test harness.

### Running All 18 Test Suites (Headless Simulator Runner)

Ensure an iOS simulator is booted, then run:

```bash
# 1. Install the build artifact onto the booted simulator
xcrun simctl install booted .derivedData/Build/Products/Debug-iphonesimulator/TeeKum\ Prototype.app

# 2. Launch the test harness headlessly and stream results to stdout
xcrun simctl launch --console booted com.academy.teekum.TeeKum-Prototype -runAllTests -exitAfterTests
```

### Expected Output
The runner executes all 18 test suites in sequence and exits with code `0`:
```text
>>> RUNNING ALL AUTOMATED TESTS <<<
ALL CODEC TESTS PASSED SUCCESSFULLY!
--- [PeerTransportTests] ALL TRANSPORT TESTS PASSED SUCCESSFULLY! ---
>>> ALL 13 MESH TRANSPORT & NEIGHBOR TESTS PASSED <<<
>>> ALL 12 BLIND RELAY SECURITY TESTS PASSED <<<
>>> ALL 14 AODV ROUTE DISCOVERY TESTS PASSED <<<
--- [CryptoSecurityTests] ALL CRYPTOGRAPHIC TESTS PASSED SUCCESSFULLY! ---
--- [LocationPublishingTests] ALL 15 LOCATION TESTS PASSED SUCCESSFULLY! ---
--- [UIStateTests] ✓ ALL 14 UI STATE TEST SUITES PASSED ---
--- [SOSEndToEndTests] ✓ ALL 11 SOS VERIFICATION SUITES PASSED ---
>>> ALL 11 MULTI-HOP SOS VERIFICATION SUITES PASSED <<<
>>> ALL LIVE ACTIVITY TESTS PASSED <<<
>>> ALL 12 RELAY & BATTERY POLICY TESTS PASSED <<<
>>> ALL 12 MESH FAILURE & CONVERGENCE TESTS PASSED <<<
--- [MeshDebuggerTests] ✓ ALL 10 MESH DEBUGGER TESTS PASSED ---
>>> ALL 16 CHAT MESSAGING & MESH INTEGRATION TESTS PASSED <<<
>>> ALL 11 CHAT UI & VIEWMODEL TESTS PASSED (100%) <<<
--- [InactivityGuardTests] ✓ ALL 9 INACTIVITY TESTS PASSED ---
ALL NEARBY INTERACTION TESTS PASSED!
>>> ALL AUTOMATED TEST RUNS FINISHED <<<
```

### Test Suite Inventory (18 Suites / 220 Tests)

| Suite # | Test File | Tests | Scope & Subsystems Verified |
| :---: | :--- | :---: | :--- |
| **1** | [`PacketCodecTests.swift`](TeeKum%20Prototype/Tests/PacketCodecTests.swift) | 20 | 56-byte wire layout, endianness, Base-27 initials, coordinate quantization, all 8 payload codecs |
| **2** | [`PeerTransportTests.swift`](TeeKum%20Prototype/Tests/PeerTransportTests.swift) | 14 | Stream framer, chunk reassembly, back-to-back datagrams, priority outbox FIFO preemption |
| **3** | [`NeighborDiscoveryTests.swift`](TeeKum%20Prototype/Tests/NeighborDiscoveryTests.swift) | 13 | Bonjour `_teekum._tcp` peering, TXT relay flag, peer tie-breaking, RSSI signal tracking |
| **4** | [`RoutingForwardingTests.swift`](TeeKum%20Prototype/Tests/RoutingForwardingTests.swift) | 12 | Blind relaying, hopCount incrementation, max 8-hop ceiling, 7-byte LRU deduplication, rate limits |
| **5** | [`RouteDiscoveryTests.swift`](TeeKum%20Prototype/Tests/RouteDiscoveryTests.swift) | 14 | AODV on-demand discovery (`ROUTE_REQ`/`ROUTE_RESP`), reverse path caching, stale peer probing |
| **6** | [`CryptoSecurityTests.swift`](TeeKum%20Prototype/Tests/CryptoSecurityTests.swift) | 13 | RFC 8439 ChaCha20-Poly1305 AEAD, AAD tamper detection, hopCount masking, replay prevention |
| **7** | [`LocationPublishingTests.swift`](TeeKum%20Prototype/Tests/LocationPublishingTests.swift) | 15 | Live Sharing switch, adaptive cadence (3–5s / 15–30s), stale recovery, dynamic GNSS accuracy |
| **8** | [`UIStateTests.swift`](TeeKum%20Prototype/Tests/UIStateTests.swift) | 14 | Pairing lifecycle, freshness badges, Setter Lock Rule, Tactical Radar polar projection |
| **9** | [`SOSEndToEndTests.swift`](TeeKum%20Prototype/Tests/SOSEndToEndTests.swift) | 11 | 3-second hold gesture, immediate queue preemption, honest delivery state transitions |
| **10** | [`MultiHopSOSTests.swift`](TeeKum%20Prototype/Tests/MultiHopSOSTests.swift) | 11 | Multi-hop flood propagation, reverse-route ACKs, honest delivery progression across hops |
| **11** | [`LiveActivityTests.swift`](TeeKum%20Prototype/Tests/LiveActivityTests.swift) | 6 | ActivityKit presentation lifecycle across Lock Screen & Dynamic Island, relay toggle Intent |
| **12** | [`RelayPolicyTests.swift`](TeeKum%20Prototype/Tests/RelayPolicyTests.swift) | 12 | 3 relay modes (Always, Timed 30m, Disabled), hard 20% battery cutoff, compact consent gate |
| **13** | [`MeshFailureIntegrationTests.swift`](TeeKum%20Prototype/Tests/MeshFailureIntegrationTests.swift) | 12 | Multi-node topologies (linear, star), network partitions, loop prevention, stream corruption resync |
| **14** | [`MeshDebuggerTests.swift`](TeeKum%20Prototype/Tests/MeshDebuggerTests.swift) | 10 | 1-tap automated triage, 56B packet inspector, synthetic packet injection, virtual lab sandbox |
| **15** | [`ChatMessagingEngineTests.swift`](TeeKum%20Prototype/Tests/ChatMessagingEngineTests.swift) | 16 | 20-byte UTF-8 payload codec, FIFO outbox, backoff retries, transparent per-recipient delivery ACKs |
| **16** | [`ChatUITests.swift`](TeeKum%20Prototype/Tests/ChatUITests.swift) | 11 | ChatSheetView, message bubbles, preset chips, ByteMeterView 20B clamp, badge counts |
| **17** | [`InactivityGuardTests.swift`](TeeKum%20Prototype/Tests/InactivityGuardTests.swift) | 9 | Man Down stillness detector, 180s timeout, 30s silent pre-alarm countdown, auto-SOS dispatch |
| **18** | [`NearbyInteractionTests.swift`](TeeKum%20Prototype/Tests/NearbyInteractionTests.swift) | 7 | UWB 30B token exchange, 12-fragment reassembly, 1-hop limit, simulation & sensor fallback |
| **TOTAL** | **18 TEST SUITES** | **220** | **100% PASS RATE ACROSS ALL SUBSYSTEMS** |

---

## Documentation Directory

The project includes an exhaustive, authoritative documentation suite:

| Document | Description |
| :--- | :--- |
| [`agent.md`](docs/agent.md) | **Master Agent Instructions:** Core product principles, architecture, wire layouts, and developer rules. |
| [`docs/knowledge_transfer/README.md`](docs/knowledge_transfer/README.md) | **Knowledge Transfer Master Index:** Entry point and reading tracks for engineers and AI agents. |
| [`docs/knowledge_transfer/HANDOFF_CHECKLIST.md`](docs/knowledge_transfer/HANDOFF_CHECKLIST.md) | **11-Gate Pre-Flight Checklist:** Mandatory verification steps before writing code. |
| [`docs/knowledge_transfer/PROJECT_OVERVIEW.md`](docs/knowledge_transfer/PROJECT_OVERVIEW.md) | **System Mission & Realities:** Festival realities, personas, usage scenarios, and 11 invariants. |
| [`docs/knowledge_transfer/TECH_STACK.md`](docs/knowledge_transfer/TECH_STACK.md) | **Technology Stack Audit:** Deep dive into native frameworks and zero-dependency architecture. |
| [`docs/knowledge_transfer/ARCHITECTURE.md`](docs/knowledge_transfer/ARCHITECTURE.md) | **System Architecture:** 6-layer topology, actor isolation boundaries, and `SessionHolder` bridge. |
| [`docs/knowledge_transfer/ARCHITECTURAL_DECISIONS.md`](docs/knowledge_transfer/ARCHITECTURAL_DECISIONS.md) | **ADR Catalog:** 20 binding Architectural Decision Records with trade-offs and rationale. |
| [`docs/knowledge_transfer/PROTOCOL_SPECIFICATION.md`](docs/knowledge_transfer/PROTOCOL_SPECIFICATION.md) | **56-Byte Wire Protocol:** Bitfield layouts, Nonce derivation, and ChaCha20-Poly1305 AEAD. |
| [`docs/knowledge_transfer/FEATURE_STATUS.md`](docs/knowledge_transfer/FEATURE_STATUS.md) | **Feature Inventory:** Granular implementation status across Phases 1, 2, 3, and 4. |
| [`docs/knowledge_transfer/DEVELOPMENT_GUIDELINES.md`](docs/knowledge_transfer/DEVELOPMENT_GUIDELINES.md) | **Engineering Standards:** Pre-implementation inspection rules, coding conventions, and MVVM rules. |
| [`docs/knowledge_transfer/DEVELOPMENT_ROADMAP.md`](docs/knowledge_transfer/DEVELOPMENT_ROADMAP.md) | **Development Roadmap:** Active baseline, milestone status, and remaining Phase 4 backlog. |
| [`docs/knowledge_transfer/KNOWN_ISSUES.md`](docs/knowledge_transfer/KNOWN_ISSUES.md) | **Technical Debt Catalog:** Prioritized register of 24 forensic issues and hardware limits. |
| [`docs/TechnicalRequirements.md`](docs/TechnicalRequirements.md) | **Technical Requirements:** Formal functional and non-functional specifications. |
| [`docs/DEVELOPMENT_LOG.md`](docs/DEVELOPMENT_LOG.md) | **Continuous Development Ledger:** Reverse-chronological ledger of all agent/developer changes. |

---

## Protected Architecture (8 Golden Rules)

Incoming engineers and AI coding agents must strictly adhere to the following invariants:

1. **Fixed 56-Byte Wire Standard:** Never alter `PacketConstants.wirePacketSize == 56`. Every packet must be padded or partitioned to exactly 56 bytes.
2. **RFC 8439 Cryptography:** Never build custom cryptographic primitives or bypass `CryptoKit.ChaChaPoly`. Outer envelopes are cleartext; inner payloads are ciphertext; `hopCount` at Byte 2 is masked to `0x00` in AAD.
3. **Pure MVVM (Zero Coordinators):** Keep views observing `@Observable @MainActor` ViewModels. ViewModels invoke background `actor` services. Never introduce UIKit Navigation Coordinators.
4. **Zero External Dependencies:** Every single file imports strictly official Apple SDK frameworks (`Network`, `CryptoKit`, `NearbyInteraction`, `CoreMotion`, `ActivityKit`, `MapKit`). Never add SPM packages, CocoaPods, or Carthage frameworks.
5. **Single Active Meeting Point & Setter Lock Rule:** Maintain strictly one active group rendezvous. Only the setter can modify or unset it until it auto-expires (1-hour cutoff). Non-setters are restricted to RSVP actions.
6. **Hard 20% Cutoff (Festival Survival Mode):** Instantly terminate stranger mesh relaying, clear relay buffers, and throttle GNSS when battery drops below 20% or enters Low Power Mode.
7. **Pre-Implementation Inspection Protocol:** Before creating new services, types, or configurations, thoroughly inspect existing implementations in `Services/`, `Models/`, and `TeeKumConfiguration.swift` to prevent redundant parallel structures.
8. **Continuous Reverse-Chronological Logging:** Every development task, refactor, bug fix, or documentation update must be recorded at the top of [`docs/DEVELOPMENT_LOG.md`](docs/DEVELOPMENT_LOG.md) before concluding work.
