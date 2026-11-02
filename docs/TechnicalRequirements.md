# TeeKum

> **Current implementation — 2026-11-02:** Read [Phase 1 review and connection/data guide](PHASE_1_REVIEW.md) before using the historical specifications below. The reviewed app uses Protocol v3 with 66-byte frames (8-byte envelope + 12-byte random nonce + 30-byte ciphertext + 16-byte tag), private per-group keys, and encrypted SwiftData recovery. Phase 2 expanded hops/stranger relaying remain deferred. All phones must use the revised build. The guide takes precedence over conflicting older implementation/background-execution claims.


**Technical Requirements · Fantasix Team**
**Last updated:** 27 October 2026  
**Status:** Planning document; distinguishing the current prototype from planned MVP integration.

---

## 1. Project Overview

**App name:** TeeKum  
**Team name:** Fantasix  
**Team members:** Adiat (Developer), Daffa (Developer), Hasan (Developer), Nicho (Developer), Ayu (Designer), Ivanna (Designer)
**Platform and minimum version:** iOS 17+  
**UI framework:** SwiftUI (Modern Swift Observation `@Observable`, Pure MVVM)  

**Description:**  
TeeKum is an offline-first iOS app designed to help friends locate one another in crowded concerts, music festivals, and large venues where cellular data or internet access is weak or unavailable. Users form private groups, share their real-time coordinates and current activity status, view friends on an offline map, establish meeting points, and navigate directly toward a selected person.

The system is designed to be completely serverless (*100% serverless*). Devices communicate directly peer-to-peer (Phase 1 MVP) via Apple Wireless Direct Link (AWDL) and Wi-Fi Direct using `Network.framework`. Devices can also opportunistically relay encrypted packets across a multi-hop mesh network for fellow festival attendees (Phase 2). Relay participation is entirely opt-in, and privacy is strictly guaranteed through end-to-end authenticated encryption (zero-knowledge relaying).

### 1.1 Scope and Product Decisions

- **100% Serverless:** No cloud backend, external databases, or user accounts are required. Groups are formed either offline (via QR barcodes) or online (via URL share links) with symmetric encryption keys embedded directly inside the URL fragment.
- **Location + Status Coded Hash:** Periodic updates transmit location coordinates and current status together. Status strings are processed locally, and only a 1-byte compact coded hash is broadcast over the air to minimize radio bandwidth.
- **SOS Is Exceptional:** The SOS emergency button requires a 3-second continuous press-and-hold to prevent accidental triggers while dancing. SOS packets are dispatched immediately through an urgent priority path, preempting normal queues, and receive maximum forwarding priority.
- **User-Controlled Live Sharing:** Users maintain complete control via a *Live Sharing* toggle on the map screen. When OFF, GPS polling and broadcasting are paused to preserve battery and privacy while watching performances. When ON, updates are broadcast every 3–5 seconds while moving, or 15–30 seconds while stationary.
- **Single Active Meeting Point:** A group has strictly one active meeting point at any given time to eliminate confusion. Friends confirm attendance with a single tap (*"I'll be there"*).
- **Compass to Ultra-Wideband Transition:** Long-range navigation (>8m) utilizes a 360° magnetic compass arrow calculating GPS bearing, then transitions automatically and seamlessly to an Ultra-Wideband (Nearby Interaction U1/U2) precision radar upon approaching within ~5–8 meters.
- **Visual Strobe Beacon:** A 1-tap button turns the screen into a high-visibility, high-contrast flashing neon torch to hold above dark, dense crowds.
- **Communal Mesh Compact (Phase 2):** Group membership is an all-in community agreement: joining a group requires agreeing to be a mesh relay node (*"Join the Mesh: Relay for others while others relay for you. Battery-protected; shuts off at 20%"*). Participating devices forward multi-hop encrypted packets for group members and blindly relay encrypted packets for outside festival attendees. Relaying is strictly zero-knowledge (only 4-byte cleartext header inspected; payloads remain AES-GCM encrypted), rate-capped at $\le 2$ pkts/sec with 256 LRU deduplication, and automatically suspends at 20% battery.
- **Festival Survival Mode:** When device battery drops below 20% or enters Low Power Mode, the app automatically suspends stranger mesh relaying, terminates background execution, and throttles GPS sampling to reserve battery strictly for emergency SOS and viewing the offline meeting map.
- **Radical Simplicity:** Engineered with a pure MVVM architecture without Coordinators (no MVVM+C) and built with 100% native Apple frameworks (zero third-party dependencies).

### 1.2 Approved Review Decisions

| Decision | Agreed Behavior |
| :--- | :--- |
| **D1 — 100% Serverless Group Pairing** | Groups are formed without cloud servers. A shareable link (`teekum://join#key=Base64Key&sid=%04X&name=GroupName`) carries the 256-bit symmetric encryption key and 16-bit session ID in the URL fragment for online sharing (iMessage/WhatsApp), while an on-screen QR barcode renders the exact same URL string for offline camera scanning at the venue. |
| **D2 — User-Controlled Live Sharing Toggle** | Location broadcasting only occurs when the user enables the *Live Sharing* toggle. When relaxing or watching a show, users turn sharing off to preserve privacy and battery. Emergency SOS alerts broadcast immediately regardless of toggle state. |
| **D3 — Single Active Meeting Point** | Exactly one active rendezvous spot is permitted per group at a time. Any member can propose a meeting point (venue landmark, custom pin, or current location), and friends respond with 1-tap confirmation (*"I'll be there"* or *"Can't make it"*). |
| **D4 — Continuous Directional Finding** | Long-range guidance (>8m) displays a 360° compass arrow and estimated meter distance. Once within ~5–8 meters, the interface smoothly transitions to centimeter-accurate Nearby Interaction (UWB) radar, paired with a 1-tap flashing Screen Strobe beacon. |
| **D5 — Communal Mesh Compact & Background Execution** | **Phase 1 MVP:** Live Activity (`ActivityKit`) displays session status, active meeting point, connected peer count, and emergency SOS alerts across the Dynamic Island and Lock Screen, keeping the app alive in the pocket via Apple's official location status indicator (`showsBackgroundLocationIndicator = true` and `allowsBackgroundLocationUpdates = true`).<br>**Phase 2 Mesh Compact:** Group membership requires an explicit "Join the Mesh" consent agreement during pairing. Once in a group, the device acts as a continuous background relay for fellow group members and blindly forwards stranger festival packets (zero-knowledge, 2 pkts/sec rate cap, 256 LRU deduplication cache). Relaying is an inseparable condition of staying in the group, with an automatic hard shutoff at 20% battery (Festival Survival Mode). |
| **D6 — Festival Survival Mode (Hard 20% Cutoff)** | Automatic critical battery detection. When battery reaches 20% (or Low Power Mode), stranger mesh relaying and background sessions are instantly terminated, reducing CoreLocation sampling to once every 1–2 minutes or on-demand, reserving remaining power strictly for SOS and meeting maps. |
| **D7 — 54-Byte Binary Packet (Protocol v2), 16-Bit Session ID & Coordinate Quantization** | CoreLocation `Double` (`CLLocationDegrees`) coordinates are quantized into big-endian signed 32-bit integers `Int32` (`degrees * 1_000_000`) for ~11 cm resolution. Wire packets are fixed at 54 bytes (8B cleartext envelope + 30B encrypted payload + 16B Poly1305 authentication tag). Group session ID is 16 bits (`UInt16`, `0x0001...0xFFFF`) derived via SHA-256 over timestamp, GPS coordinates, and CSPRNG salt. See [docs/PAYLOAD_GUIDE.md](PAYLOAD_GUIDE.md) for the complete byte-by-byte visual breakdown. |
| **D8 — 2-Byte Base-27 1-to-3 Letter Sender Initials & Serverless QR Group Formation** | Ephemeral member identification inside the 30-byte encrypted payload is compressed from 4 bytes down to exactly 2 bytes (`UInt16`) using base-27 radix encoding of 1 to 3 uppercase letters ($A \dots Z$, e.g. "D", "AB", "DNA", total $18,278 \le 65,535$). Every packet is self-describing, rendering member avatars instantly on the receiving map/radar and completely eliminating runtime P2P radio handshakes. Group formation and 256-bit key exchange are handled serverless via CoreImage QR barcode generation and AVFoundation camera scanning. |
| **D9 — Phase 2 Expanded 2-Byte Hop Control (hopLimit & hopCount UInt8)** | In Phase 2 multi-hop mesh development, expand hop control from a single 1-byte nibble split (`hopLimit: 4 bits`, `hopCount: 4 bits`, range 0..15) into two dedicated 8-bit bytes (`hopLimit: UInt8` and `hopCount: UInt8`, range 0..255). To maintain cryptographic integrity and prevent unauthenticated broadcast storm attacks, `hopLimit` is authenticated verbatim in ChaCha20-Poly1305 AEAD Associated Data (AAD), while `hopCount` is masked to `0x00` in AAD and incremented by intermediate relays. The total 54-byte datagram size is preserved by absorbing 1 byte from the inner payload's 8-byte reserved padding. |

---

## 2. Technologies and Frameworks

This project utilizes **100% Native Apple Frameworks (Zero External Packages / Zero Backend)** to ensure maximum stability, minimal binary footprint, zero supply-chain vulnerabilities, and instant compilation times.

### 2.1 Technology Overview

| Technology | Type | Why we use it | Used in which component |
| :--- | :--- | :--- | :--- |
| **Network.framework** | Apple Framework | Sends and receives 54-byte binary datagrams peer-to-peer offline via AWDL (Wi-Fi Direct & Bluetooth) | `Services/PeerTransportService.swift` |
| **CoreLocation** | Apple Framework | Retrieves GPS coordinates (`CLLocationDegrees` as `Double`), magnetic compass heading, and horizontal accuracy | `Services/LocationService.swift` |
| **CoreMotion** | Apple Framework | Detects physical movement (walking vs stationary) via motion coprocessor to sleep GPS and save ~70% battery | `Services/LocationService.swift` |
| **CryptoKit** | Apple Framework | Authenticated encryption (ChaCha20-Poly1305 / AES-256-GCM), symmetric key exchange, and tamper verification | `Services/CryptoService.swift` |
| **NearbyInteraction** | Apple Framework | High-precision relative distance and 3D directional pointing (Ultra-Wideband U1/U2) within a 5–8 meter radius | `Views/FinderBeaconView.swift` |
| **MapKit** | Apple Framework | Renders venue maps, friend pins, accuracy circles, and rendezvous points using cached offline map data | `Views/MainMapView.swift` |
| **ActivityKit** | Apple Framework | Presents persistent session status, friend proximity, and interactive communal relay approval on Lock Screen & Dynamic Island | `Views/DiagnosticsView.swift` & Widgets |
| **Security (Keychain)** | Apple Framework | Securely stores 256-bit group session encryption keys inside the iOS Keychain / Secure Enclave | `Services/CryptoService.swift` |
| **libsqlite3** | Native C Library | Lightweight local SQLite database for ephemeral session crash-recovery if the app is backgrounded by iOS | `Services/SessionStorage.swift` |

---

### 2.2 Technology Details

#### Network.framework (Peer-to-Peer Transport)

> *Reference Documentation:* See [docs/NETWORKING.md](NETWORKING.md) for the complete networking architecture, protocol specifications, flow control pipelines, and connection lifecycle diagrams.

**What it is:**  
`Network.framework` is Apple's modern low-level networking library. In this application, `NWListener` and `NWConnection` are configured with peer-to-peer Bonjour (`includePeerToPeer: true`) to establish direct datagram connections over Apple Wireless Direct Link (AWDL) and Wi-Fi Direct. This is the exact underlying protocol powering Apple AirDrop, allowing 54-byte binary packets to transmit in single-digit milliseconds without cellular data or Wi-Fi routers.

**Setup required:**
- Add `NSLocalNetworkUsageDescription` to `Info.plist` (e.g., *"This app uses the local network to discover and connect with friends at concerts without internet"*).
- Add `NSBonjourServices` array to `Info.plist` declaring the custom service type (e.g., `_teekum._udp`).

**Methods / functions / classes we use:**

| Method / Function / Class | What it does | How we use it in our app | File |
| :--- | :--- | :--- | :--- |
| `NWListener` | Listens for inbound connections from nearby devices without a central server. | Operated by `PeerTransportService` to accept incoming peer links over AWDL. | `PeerTransportService.swift` |
| `NWConnection` | Manages a bi-directional transmission channel to a specific peer. | Sends and receives 54-byte binary datagrams to neighboring devices. | `PeerTransportService.swift` |
| `NWParameters.peerToPeer` | Enables peer-to-peer radio transport options (AWDL and Wi-Fi Direct). | Configured on listeners and connections to operate offline without Wi-Fi routers. | `PeerTransportService.swift` |
| `NWBrowser` | Scans for nearby peers advertising the group's Bonjour service. | Discovers friend devices and eligible relays within a 30–50 meter radio range. | `PeerTransportService.swift` |
| `send(content:contentContext:isComplete:completion:)` | Transmits raw binary data across an active connection. | Enqueues encrypted 54-byte packets into the radio outbox queue. | `PeerTransportService.swift` |

**Code example from our project:**

```swift
import Foundation
import Network

actor PeerTransportService {
    private var listener: NWListener?
    private var activeConnections: [String: NWConnection] = [:]
    
    func startAdvertisingAndListening(serviceType: String) throws {
        let params = NWParameters.udp
        params.includePeerToPeer = true
        
        let listener = try NWListener(using: params)
        listener.service = NWListener.Service(name: UUID().uuidString, type: serviceType)
        listener.newConnectionHandler = { [weak self] newConn in
            Task { await self?.handleIncomingConnection(newConn) }
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }
    
    func sendPacket(data: Data, to connection: NWConnection) async throws {
        guard data.count == 54 else { throw TransportError.invalidPacketSize }
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receivePacket(from: connection)
    }
    
    private func receivePacket(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 54, maximumLength: 54) { [weak self] content, _, _, error in
            if let data = content, data.count == 54 {
                Task { await self?.processInboundPacket(data) }
            }
            if error == nil { self?.receivePacket(from: connection) }
        }
    }
    
    private func processInboundPacket(_ data: Data) {
        // Dispatched to the 6-step Inbound Ingestion Pipeline
    }
}
```

---

#### CoreLocation

**What it is:**  
`CoreLocation` delivers device geographical coordinates (latitude, longitude, accuracy) and magnetic compass heading. Coordinates are represented natively as `CLLocationDegrees` (`Double`). In this application, `LocationService` manages adaptive battery sampling (every 3–5s while walking, 15–30s while stationary) and quantizes 64-bit `Double` coordinates into 32-bit `Int32` integers for binary transmission.

**Setup required:**
- Add `NSLocationWhenInUseUsageDescription` to `Info.plist`.
- Enable *Background Modes* (Location Updates) in Signing & Capabilities for emergency SOS navigation.

**Methods / functions / classes we use:**

| Method / Function / Class | What it does | How we use it in our app | File |
| :--- | :--- | :--- | :--- |
| `CLLocationManager` | Central controller for configuring and receiving location and heading updates. | Managed in `LocationService` to monitor GPS coordinates and compass orientation. | `LocationService.swift` |
| `CLLocationCoordinate2D` | Stores latitude and longitude as 64-bit `Double` (`CLLocationDegrees`). | Standard representation of device and peer positions on the map. | `LocationPin.swift` |
| `CLLocation.horizontalAccuracy` | Provides coordinate uncertainty radius in meters (`Double`). | Renders visual accuracy circles on the map and populates the packet accuracy byte. | `LocationService.swift` |
| `startUpdatingLocation()` | Initiates periodic GPS positioning callbacks. | Activated only when the *Live Sharing* master toggle is enabled. | `LocationService.swift` |
| `startUpdatingHeading()` | Initiates built-in magnetometer sensor callbacks. | Drives the 360° directional arrow during navigation toward a friend. | `LocationService.swift` |

---

#### CoreMotion

**What it is:**  
`CoreMotion` accesses data generated by the iPhone's low-power motion coprocessor, accelerometer, and gyroscope. In this application, `CMMotionActivityManager` detects whether the user is actively walking or stationary (e.g., standing still watching a band or dancing in place). By feeding this motion state into `LocationService`, the app automatically powers down or throttles the battery-hungry GPS receiver when the user is not moving, saving ~70% of GPS power consumption during long festival hours.

**Setup required:**
- Add `NSMotionUsageDescription` to `Info.plist` (e.g., *"This app monitors motion activity to power down GPS when you are stationary, conserving battery during long festival hours"*).
- Check `CMMotionActivityManager.isActivityAvailable()` at runtime before requesting updates.

**Methods / functions / classes we use:**

| Method / Function / Class | What it does | How we use it in our app | File |
| :--- | :--- | :--- | :--- |
| `CMMotionActivityManager` | Manages motion activity updates from the low-power motion coprocessor. | Monitored in `LocationService` to govern adaptive GPS sampling. | `LocationService.swift` |
| `CMMotionActivityManager.isActivityAvailable()` | Checks whether the current device supports motion activity tracking. | Verifies hardware motion capability before subscribing to activity updates. | `LocationService.swift` |
| `startActivityUpdates(to:withHandler:)` | Subscribes to live motion state changes on a background queue. | Delivers `CMMotionActivity` events (`stationary`, `walking`, `running`) to trigger GPS power-down. | `LocationService.swift` |
| `CMMotionActivity.stationary` | Boolean flag indicating whether the device is currently stationary. | When `true`, instructs `LocationService` to pause high-accuracy GPS and sleep. | `LocationService.swift` |
| `CMMotionActivity.confidence` | Rating (`low`, `medium`, `high`) of motion detection accuracy. | Filters out brief micro-movements to avoid false GPS wakeups. | `LocationService.swift` |

**Code example from our project:**

```swift
import CoreLocation
import CoreMotion
import Foundation

final class LocationSamplingPolicy {
    private let motionManager = CMMotionActivityManager()
    private let operationQueue = OperationQueue()
    private(set) var isStationary: Bool = false
    
    func startMotionMonitoring(onMotionStateChanged: @escaping (Bool) -> Void) {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        
        motionManager.startActivityUpdates(to: operationQueue) { [weak self] activity in
            guard let activity = activity, activity.confidence != .low else { return }
            let stationary = activity.stationary
            if self?.isStationary != stationary {
                self?.isStationary = stationary
                DispatchQueue.main.async {
                    onMotionStateChanged(stationary)
                }
            }
        }
    }
}
```

**Challenges or limits we found (optional):**
- **Dancing in Place:** At a concert, rhythmic dancing in place can occasionally be classified as walking; the sampling policy pairs motion activity with a small CoreLocation displacement filter to prevent false continuous GPS locks.
- **Classification Lag:** The motion coprocessor requires ~2–3 seconds of continuous motion to transition confidence from low to high; initial walking pings use a conservative 5-second fallback.

---

#### CryptoKit

**What it is:**  
`CryptoKit` is Apple's native hardware-accelerated cryptographic framework. In this application, `CryptoKit` provides authenticated symmetric encryption (ChaCha20-Poly1305 / AES-256-GCM) to seal the 30-byte inner payload with a 16-byte authentication tag, while binding the 8-byte cleartext outer envelope as Associated Authenticated Data (AAD).

**Setup required:**
- Import `CryptoKit`. No special `Info.plist` entries required.

**Methods / functions / classes we use:**

| Method / Function / Class | What it does | How we use it in our app | File |
| :--- | :--- | :--- | :--- |
| `SymmetricKey` | Represents a 256-bit symmetric key for a group session. | Generated on group creation and exchanged via URL fragment or QR barcode. | `CryptoService.swift` |
| `ChaChaPoly.seal(_:using:nonce:authenticating:)` | Encrypts payload and computes a 16-byte Poly1305 authentication tag over ciphertext and AAD. | Encrypts 30 bytes of private coordinates and binds the 8-byte outer envelope as AAD. | `CryptoService.swift` |
| `ChaChaPoly.open(_:using:authenticating:)` | Decrypts ciphertext and verifies the Poly1305 tag against AAD. | Validates inbound packets; forged packets or altered envelope fields are dropped instantly. | `CryptoService.swift` |
| `ChaChaPoly.Nonce(data:)` | Creates a unique 96-bit initialization vector per packet. | Derived from 16-bit session ID (2B) + 32-bit sequence number (4B) + version/type (1B) + 5-byte domain tag "TKM02" (5B). | `CryptoService.swift` |

---

#### NearbyInteraction

**What it is:**  
`NearbyInteraction` leverages Apple's Ultra-Wideband (UWB U1/U2) chip available on iPhone 11 and later. In this application, it solves the *"Last 10 Meters in the Dark"* problem by computing high-precision relative distance and 3D directional vectors (accurate to centimeters) toward a friend's device within an 8-meter radius.

**Setup required:**
- Add `NSNearbyInteractionUsageDescription` to `Info.plist`.
- Check device compatibility at runtime via `NISession.isSupported`.

**Methods / functions / classes we use:**

| Method / Function / Class | What it does | How we use it in our app | File |
| :--- | :--- | :--- | :--- |
| `NISession` | Coordinates an active Ultra-Wideband distance and direction tracking session. | Activated when a user approaches within ~5–8 meters of a targeted friend. | `FinderBeaconView.swift` |
| `NIDiscoveryToken` | Ephemeral radio token exchanged between peers to pair a UWB session. | Exchanged over the local peer-to-peer transport to initiate UWB ranging. | `FinderBeaconView.swift` |
| `session(_:didUpdate:)` | Delegate callback delivering distance (`Float` meters) and direction (`simd_float3`). | Updates the close-range precision radar arrow on the screen. | `FinderBeaconView.swift` |

---

#### MapKit

**What it is:**  
`MapKit` renders venue maps, friend pins, navigation paths, and festival landmarks. In this application, MapKit utilizes Apple's offline cached map capabilities (*MapKit Offline Map System*), ensuring base maps, streets, and venue footprints remain visible without cellular data.

**Setup required:**
- Import `MapKit`. Requires location authorization to display user location.

**Methods / functions / classes we use:**

| Method / Function / Class | What it does | How we use it in our app | File |
| :--- | :--- | :--- | :--- |
| `Map` (SwiftUI) | Declarative container for presenting camera viewports, overlays, and annotations. | Renders the primary festival map interface in `MainMapView`. | `MainMapView.swift` |
| `Annotation` | Displays custom interactive map pins at specified coordinates. | Renders friend avatars, current status emoji badges, and meeting point icons. | `MainMapView.swift` |
| `MapCircle` | Renders a geographic circle overlay with an explicit radius in meters. | Displays coordinate accuracy rings that fade as signals degrade in crowds. | `MainMapView.swift` |

---

#### ActivityKit

**What it is:**  
`ActivityKit` manages Live Activities presented across the iPhone Lock Screen, StandBy, and Dynamic Island. In this application, ActivityKit displays ongoing session status and friend proximity passively, and presents interactive prompts for *Communal Relay* approval when nearby peers require a mesh forwarding hop.

**Setup required:**
- Add `NSSupportsLiveActivities = YES` to `Info.plist`.
- Create a Widget Extension target containing an `ActivityConfiguration`.

**Methods / functions / classes we use:**

| Method / Function / Class | What it does | How we use it in our app | File |
| :--- | :--- | :--- | :--- |
| `ActivityAttributes` | Protocol defining static and dynamic properties of a Live Activity. | Encapsulates festival session data, group name, and relay approval states. | `RelayActivityAttributes.swift` |
| `LiveActivityIntent` | Protocol enabling interactive buttons directly on the Lock Screen (iOS 17+). | Powers **[Approve Relay]** and **[Decline]** actions without unlocking the device. | `RelayAppIntents.swift` |
| `Activity.request(...)` | Starts a Live Activity instance on Dynamic Island and Lock Screen. | Called upon creating or joining an active festival session. | `DiagnosticsView.swift` |

---

#### Security (Keychain Services)

**What it is:**  
The `Security` framework provides hardware-backed credential and key storage within the Secure Enclave. In this application, the 256-bit symmetric session key is stored in the iOS Keychain during active sessions, and is permanently purged when the user leaves the group or ends the session.

**Setup required:**
- Import `Security`.

**Methods / functions / classes we use:**

| Method / Function / Class | What it does | How we use it in our app | File |
| :--- | :--- | :--- | :--- |
| `SecItemAdd(_:_:)` | Stores a secret item in the iOS Keychain database. | Saves the symmetric session key extracted from a QR barcode or URL link. | `CryptoService.swift` |
| `SecItemCopyMatching(_:_:)` | Retrieves a secret item from the Keychain using query attributes. | Reads the symmetric key when decrypting incoming packets. | `CryptoService.swift` |
| `SecItemDelete(_:)` | Permanently deletes a secret item from the Keychain. | Purges session keys when the user taps *"Leave Group"* or the session expires. | `CryptoService.swift` |

---

#### libsqlite3 (Native SQLite)

**What it is:**  
`libsqlite3` is the native C database engine pre-installed on all iOS devices. In this application, SQLite is utilized strictly as an ephemeral crash-recovery store. If a user switches to the Camera app to record a 4K concert video and iOS temporarily suspends the app in the background, this snapshot ensures active group membership and member states are restored upon relaunch. The database is wiped clean upon session teardown.

**Setup required:**
- `import SQLite3` (built into iOS; zero third-party dependencies).

**Methods / functions / classes we use:**

| Method / Function / Class | What it does | How we use it in our app | File |
| :--- | :--- | :--- | :--- |
| `sqlite3_open_v2(...)` | Opens a connection to a local database file in the Application Support directory. | Initializes the ephemeral session SQLite storage. | `SessionStorage.swift` |
| `sqlite3_prepare_v2(...)` | Compiles an SQL query string into an efficient byte-code statement. | Prepares queries for updating member states and checking deduplication caches. | `SessionStorage.swift` |
| `sqlite3_step(...)` | Executes a compiled SQL statement. | Writes latest coordinate snapshots and reads recovery state. | `SessionStorage.swift` |
| `sqlite3_finalize(...)` | Finalizes a prepared statement and frees allocated memory. | Prevents memory leaks on background actor threads. | `SessionStorage.swift` |

---

## 3. Architecture

### 3.1 Architecture Name

**Architecture:** Pure MVVM (Model–View–ViewModel) built with modern Swift Observation (`@Observable`), designed with *Radical Simplicity* without Coordinators (no MVVM+C).

### 3.2 Why We Chose It

1. **Elimination of Boilerplate:** Avoids complicated Coordinator routing patterns. Navigation is handled natively by SwiftUI using `NavigationStack` and simple root-level state switching (`if hasActiveSession { MainMapView() } else { GroupPairingView() }`).
2. **Performance & Battery Efficiency:** Swift Observation (`@Observable`) updates views only when specific observed properties change. This prevents expensive view re-rendering and eliminates Combine `@Published` boilerplate.
3. **Clear Boundary Separation:**
   - **Views:** Declarative SwiftUI components with zero radio or cryptographic logic.
   - **ViewModels:** Manage screen state, formatting, and user actions.
   - **Services (Actors):** Manage asynchronous, thread-sensitive tasks (P2P radio, outbox queues, CryptoKit encryption, SQLite writes) safely using Swift `actor`s to eliminate data races.
4. **Single-Target Focus:** Dedicated 100% to a single iOS iPhone target to ensure radio stability in physical venues.

### 3.3 Architecture Diagram

```text
┌─────────────────────────────────────────────────────────────┐
│                       SwiftUI Views                         │
│  (MainMapView, GroupPairingView, FinderBeaconView, etc.)    │
└──────────────────────────────┬──────────────────────────────┘
                               │ Observes (@Observable)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                    SwiftUI ViewModels                       │
│  (MapViewModel, GroupSessionViewModel, SOSViewModel, etc.)   │
└──────────────────────────────┬──────────────────────────────┘
                               │ Calls async
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                  Native Services (Actors)                   │
│   ┌─────────────────────┐       ┌───────────────────────┐   │
│   │ PeerTransportService│       │    CryptoService      │   │
│   │ (Network.framework) │       │      (CryptoKit)      │   │
│   └──────────┬──────────┘       └───────────┬───────────┘   │
│              │                              │               │
│   ┌──────────┴──────────┐       ┌───────────┴───────────┐   │
│   │   LocationService   │       │    SessionStorage     │   │
│   │    (CoreLocation)   │       │      (SQLite3)        │   │
│   └─────────────────────┘       └───────────────────────┘   │
└──────────────────────────────┬──────────────────────────────┘
                               │ Serializes / Encrypts
                               ▼
┌─────────────────────────────────────────────────────────────┐
│      54-Byte Wire Packet (Protocol v2) (AWDL / Wi-Fi)       │
│  [8B Cleartext Envelope] + [30B Ciphertext] + [16B Tag]     │
└─────────────────────────────────────────────────────────────┘
```

#### 2-Byte Base-26 Initials Codec (Zero Handshake)
To eliminate out-of-band P2P connection handshakes, each transmitting member's 3-letter initials ($A\dots Z$) are mapped to a 2-byte big-endian integer:
- **Radix Formula:** $\text{number} = (a \times 676) + (b \times 26) + c$, where $a, b, c = \text{ASCII} - 65 \in [0 \dots 25]$.
- **Bit Sizing:** $26^3 = 17{,}576 < 65{,}536$ ($2^{16}$), fitting into exactly 2 bytes (`UInt16`).
- **Zero Handshake:** Receiving peers immediately render 3-letter badges on the map and radar from decrypted packets without an initial P2P greeting exchange.

### 3.4 Components

| Component | What it does | What it must NOT do | Files / folders |
| :--- | :--- | :--- | :--- |
| **Models** | Pure Swift data models (`Member`, `LocationPin`, `Status`, `MeetingPoint`, `Packet`). | Must not import SwiftUI, execute radio calls, or run database queries. | `Models/` |
| **Views** | Declarative UI rendering (maps, compass needle, strobe beacon, 3-second SOS button). | Must not perform cryptographic operations, raw byte serialization, or direct SQLite queries. | `Views/` |
| **ViewModels** | Manage observable screen state (`@Observable`), format relative time, and trigger service actions. | Must not retain view references or open network sockets directly. | `ViewModels/` |
| **Services** | Manage platform subsystems (P2P radio, GPS sampling, CryptoKit encryption, Keychain & SQLite storage). | Must not manage screen navigation or present UI alerts directly. | `Services/` |

### 3.5 Folder Structure

```text
TeeKum Prototype/
├── App/
│   └── TeeKumApp.swift                   // Entry point, root state switcher & URL deep-link router
├── Models/
│   ├── Member.swift                      // Member identity, initials, lastSeen, status, battery, heading
│   ├── LocationPin.swift                 // CoreLocation Coordinate (Double), accuracy, ~11cm Int32 quantization
│   ├── Status.swift                      // 1-byte compact festival activity status hash enum & target references
│   ├── MeetingPoint.swift                // Single active rendezvous point model & PremadeMeetingLocation options
│   ├── GroupSession.swift                // Ephemeral session model, QR / URL fragment link encoder
│   ├── Packet.swift                      // 54-byte binary packet layout (Protocol v2), InitialsCodec, codecs
│   └── SOSDeliveryState.swift            // Honest UX delivery state machine
├── Views/
│   ├── MainMapView.swift                 // MapKit view, friend pins, long-press rendezvous drop, Live Sharing toggle
│   ├── GroupPairingView.swift            // QR barcode display/scanner, URL share, clipboard paste, mesh compact gate
│   ├── StatusPickerView.swift            // One-handed horizontal status chips carousel
│   ├── SOSButtonView.swift               // 3-second hold emergency button & visual circular progress ring
│   ├── FinderBeaconView.swift            // 360° Compass arrow -> UWB precision radar & neon strobe torch
│   ├── MeetingPointsView.swift           // Meeting point proposal sheet, attendance cards, dropdown menu
│   ├── FriendDetailView.swift            // Friend inspection sheet (battery, distance, bearing, directed navigation)
│   ├── DiagnosticsView.swift             // On-device Debug HUD sheet (live RSSI dBm, peer count, packet counters)
│   └── Components/
│       ├── QRCodeView.swift              // CoreImage CIFilter QR generator with ShareLink template
│       ├── QRScannerView.swift           // AVFoundation camera scanner with viewport overlay
│       ├── SetMeetingPointSheet.swift    // Compact bottom sheet with curated location dropdown menu
│       └── MeshAgreementView.swift       // Communal Mesh Compact agreement consent modal
├── ViewModels/
│   ├── MapViewModel.swift                // Map viewport state, friend pins, offline filtering, Live Sharing
│   ├── GroupSessionViewModel.swift       // Group session lifecycle, QR/Link pairing, pendingInvite agreement
│   ├── MeetingPointViewModel.swift       // Single active meeting point state & attendance sync
│   └── SOSViewModel.swift                // 3-second hold countdown & honest delivery status
├── Services/
│   ├── PeerTransport.swift               // Authoritative actor protocol, state streams & diagnostics
│   ├── PeerTransportService.swift        // Network.framework P2P datagram transmission actor (AWDL Bonjour)
│   ├── StreamMessageFramer.swift         // 54-byte binary stream delimiter, chunk reconstruction, resynchronization
│   ├── PriorityOutboxQueue.swift         // Dual-lane outbox: urgent FIFO (SOS/ACK/Meeting) + coalesced Location
│   ├── CryptoServiceProtocol.swift       // Cryptographic service interface
│   ├── CryptoService.swift               // ChaChaPoly AEAD, AAD envelope binding & Keychain store (actor)
│   ├── SessionStorageProtocol.swift      // Ephemeral SQLite crash recovery storage interface
│   ├── LocationServiceProtocol.swift     // Location service contract
│   ├── LocationService.swift             // CoreLocation wrapper & CoreMotion adaptive battery sampling
│   ├── LocationPublisher.swift           // Periodic publishing scheduler & SOS immediate preemption
│   └── SOSAudioAlert.swift               // Emergency siren & haptic notification generator
├── docs/
│   ├── TechnicalRequirements.md          // Technical system requirements specification
│   ├── agent.md                          // Master agent instructions and product principles
│   ├── DEVELOPMENT_LOG.md                // Chronological development log, agent changes & verification records
│   ├── PHASE_1_DEVELOPMENT_REPORT.md     // Phase 1 Direct Offline MVP milestone completion report
│   ├── NETWORKING.md                     // Authoritative networking architecture & protocol guide
│   ├── PAYLOAD_GUIDE.md                  // 54-byte wire protocol & payload developer guide
│   ├── PROTOCOL_SPECIFICATION.md         // Cryptographic message protection specification
│   ├── POC_ACCEPTANCE_REPORT.md          // Final POC integration & verification acceptance report
│   ├── POC_IMPLEMENTATION_PLAN.md        // Milestone implementation plan & file ownership
│   ├── PHYSICAL_DEVICE_SOS_VALIDATION.md // Two-device offline physical test checklist for SOS
│   └── PHYSICAL_DEVICE_TEST_CHECKLIST.md // Two-device offline physical test checklist for location/status
└── Tests/
    ├── PacketCodecTests.swift            // 13 automated tests: 54-byte codec, InitialsCodec, Int32 quantization
    ├── CryptoSecurityTests.swift         // 13 automated tests: ChaChaPoly, AAD tamper, replays, Keychain
    ├── PeerTransportTests.swift          // 12 automated tests: framer chunks, outbox priority, tie-breaking
    ├── LocationPublishingTests.swift     // 11 automated tests: Live Sharing, cadence, piggybacking, monotonic GPS
    ├── SOSEndToEndTests.swift            // 10 automated tests: 3s hold, preemption, ACKs, duplicate sirens
    └── UIStateTests.swift                // 8 automated tests: pairing, freshness, distance/bearing, dropdown
```

---

## 4. Unit Testing Strategy

TeeKum employs a comprehensive, multi-layer testing strategy designed for offline-first, peer-to-peer radio resilience. Because physical radio attenuation cannot be fully emulated in unit tests, testing is partitioned into **Automated Unit & Integration Test Suites** (100% executable on simulator/CI) and **Physical Two-Device Field Protocols** (on real iPhones).

### 4.1 Automated Test Suites (67 Passing Tests)

The automated test harness comprises 6 suites in `TeeKum Prototype/Tests/`, providing 100% pass rate verification across all core subsystems:

| Suite | File | Test Cases | Scope & Verification Coverage |
| :--- | :--- | :---: | :--- |
| **Packet Codec Tests** | `PacketCodecTests.swift` | 13 | 54-byte wire layout enforcement, 8-byte cleartext envelope big-endian serialization/deserialization, 2-byte Base-27 Initials Codec ($A \dots Z$, $18,278 \le 65,535$), Int32 coordinate quantization error (<11 cm), boundary coordinates ($-90^\circ, +90^\circ, -180^\circ, +180^\circ$), payload codecs (`LocationPing`, `SOS`, `MeetingUpdate`, `ACK`, Phase 2 `RouteReq`/`RouteResp`), and serverless URL fragment invite generation/parsing. |
| **Cryptographic Security Tests** | `CryptoSecurityTests.swift` | 13 | ChaCha20-Poly1305 AEAD sealing and opening, tampered ciphertext rejection (zero plaintext leakage), tampered authentication tag rejection, cleartext envelope AAD tampering rejection (version, type, hopLimit, sessionId, sequenceNumber), mutable hopCount invariance (intermediary relays increment hopCount without tag invalidation), wrong key rejection, nonce uniqueness across members via sequence number partitioning, 5-minute sliding LRU duplicate packet rejection, anti-replay monotonic sequence enforcement, stale location state replacement prevention, future timestamp clock skew guard (>300s), and iOS Keychain storage lifecycle & permanent teardown purge. |
| **Peer Transport Tests** | `PeerTransportTests.swift` | 12 | `StreamMessageFramer` 54-byte frame delimiter, chunk fragmentation and partial read assembly, back-to-back datagram batching, corruption resynchronization over corrupted bytes, 64 KB buffer capacity protection, `PriorityOutboxQueue` urgent FIFO preemption (SOS cuts ahead of pings), single-slot location ping coalescing, bounded retry budgets with exponential backoff, hex peer ID tie-breaking, and `TransportDiagnostics` telemetry integrity. |
| **Location & Publishing Tests** | `LocationPublishingTests.swift` | 11 | Live Sharing master switch (ON permits pings, OFF completely halts broadcasting), status changes piggybacked strictly inside next normal update without standalone packets, monotonic coordinate integrity (delayed GPS fixes cannot overwrite newer fixes), UI exposure of location age and accuracy, SOS immediate location acquisition without waiting for interval, denied and authorized location permission handling, adaptive cadence selection (3–5s moving, 15–30s stationary, 60s Survival Mode), cancellable scheduler tasks, zero dummy coordinate manufacturing, and end-to-end `LocationPublisher` packet dispatch. |
| **SOS End-to-End Tests** | `SOSEndToEndTests.swift` | 10 | 3-second continuous hold gesture state machine and early release cancellation, immediate dispatch independent of Live Sharing toggle and normal ping intervals, true hardware timestamp preservation (no false freshness), urgent queue preemption, honest delivery state machine progression (`LOCAL_SENDING` $\rightarrow$ `RELAY_ACK` $\rightarrow$ `DELIVERED_TO_FRIEND`), bounded retries (3 attempts), unauthorized stranger and rogue packet rejection, duplicate suppression (no repeated audible sirens or duplicate alert banners), simulated two-device roundtrip, and empty peer list handling (`SEARCHING_PEERS`). |
| **UI & State Tests** | `UIStateTests.swift` | 8 | Group pairing lifecycle (creation, invite parsing, Communal Mesh Compact agreement gating, teardown), location freshness badges (*"Last seen Xm ago"*), status picker selection, Live Sharing toggle transitions, SOS countdown progress and cancellation, honest delivery state presentation, friend straight-line distance and magnetic forward bearing calculations, and single active meeting point proposal with `PremadeMeetingLocation` dropdown menu selection. |

### 4.2 Test Execution Command & Verification

Automated tests are verified via `xcodebuild`:

```bash
# Full project compilation & build verification
xcodebuild -scheme "TeeKum Prototype" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath .derivedData build \
  CODE_SIGNING_ALLOWED=NO
```

### 4.3 Physical Two-Device Testing Protocol

Physical testing procedures are executed on two iPhones disconnected from Wi-Fi routers and cellular data, detailed in:
- [`docs/PHYSICAL_DEVICE_TEST_CHECKLIST.md`](PHYSICAL_DEVICE_TEST_CHECKLIST.md) — 7-step location, status, and battery field verification.
- [`docs/PHYSICAL_DEVICE_SOS_VALIDATION.md`](PHYSICAL_DEVICE_SOS_VALIDATION.md) — 7-step Emergency SOS, siren audio, and rogue datagram rejection field verification.

---

## 5. Git Workflow

Development is restricted to **four branch types**: `main`, `develop`, `prod`, and `feat/*`.

### 5.1 Branches

| Branch | Purpose | Who can push directly? | Protected? |
| :--- | :--- | :--- | :--- |
| `main` | Stable release candidate, fully integrated and tested. | None (PR only). | Protected. |
| `develop` | Active integration branch for combining and testing features. | None (PR only). | Protected. |
| `prod` | Final production release code tagged for distribution. | Designated Release PIC. | Protected. |
| `feat/*` | Feature development branch branched off `develop`. | Feature developer. | Unprotected. |

### 5.2 Branch Diagram

```text
develop → feat/feature-name → PR to develop → PR to main → PR to prod
```

### 5.3 Merging Rules

| Merge | When does it happen? | Who does it? | What must be true first? |
| :--- | :--- | :--- | :--- |
| `feat/*` → `develop` | Feature is complete and verified locally. | PR owner. | Code review approved and local tests pass without errors. |
| `develop` → `main` | Milestone features are verified as a stable release candidate. | Integration PIC. | Full offline peer-to-peer verification succeeds on physical devices. |
| `main` → `prod` | Final build is verified for release. | Release PIC. | Release certificates signed and final acceptance criteria met. |

### 5.4 Step by Step: How One Feature Moves Through Our Workflow

1. Developer creates a branch `feat/feature-name` from the latest `develop`.
2. Implements focused, modular changes.
3. Opens a Pull Request (PR) to `develop` detailing changes and verification evidence.
4. Reviewer reviews code; developer addresses feedback before merging.
5. Stable features are promoted from `develop` to `main` via PRs.
6. Release-ready builds from `main` are merged into `prod`.

### 5.5 Naming and Commit Conventions

**Branch naming:** `feat/feature-name`, lowercase with hyphens (*kebab-case*).  
**Commit message format:** `type: short description` or `type(scope): short description`.  

| Type | Usage | Example |
| :--- | :--- | :--- |
| `feat:` | New application feature or behavior. | `feat(radio): add network.framework p2p transport` |
| `fix:` | Bug fix or corrected behavior. | `fix(packet): correct int32 coordinate quantization` |
| `docs:` | Documentation updates. | `docs: update technical requirements wire protocol` |
| `refactor:`| Code restructuring without visual or functional changes. | `refactor(crypto): isolate keychain storage actor` |
| `chore:` | Repository maintenance, build settings, or `.gitignore`. | `chore: update xcode build settings` |
| `test:` | Adding or improving tests. | `test(packet): add 54-byte codec roundtrip tests` |

---

## 6. Final Check

- [x] Project description, team, platform, and system architecture are aligned with TeeKum.
- [x] Legacy technologies replaced by the 9 Native Apple Frameworks (Network.framework, CoreLocation, CoreMotion, CryptoKit, NearbyInteraction, MapKit, ActivityKit, Security, libsqlite3).
- [x] Pure MVVM architecture without Coordinators and without dual-target watchOS complexity is defined.
- [x] Review decisions D1–D9 from /grill-me sessions and roadmap reviews are recorded in the Approved Decisions table.
- [x] 54-byte binary packet wire format (Protocol v2), 2-byte Base-27 initials codec (zero handshake), 16-bit session ID derivation, envelope separation, and CoreLocation `Double` quantization are documented.
- [x] Phase 2 2-byte expanded hop control architecture (Decision D9: `hopLimit: UInt8` + `hopCount: UInt8`, range 0..255) is scheduled for multi-hop mesh development.
- [x] Unit Testing Strategy is fully defined and executed across 6 test suites (67 passing tests, 100% pass rate).
- [x] Phase 1 Direct Offline MVP completed and documented in [docs/PHASE_1_DEVELOPMENT_REPORT.md](PHASE_1_DEVELOPMENT_REPORT.md).
- [x] 4-branch Git workflow (`main`, `develop`, `prod`, `feat/*`) and commit conventions are established.

### Open Decisions for Future Phases

Implementation of custom vector venue floorplans (Phase 3), Apple Watch haptic companion extension (Phase 3), and large stadium-scale multi-hop mesh routing with expanded 2-byte hop control (Phase 2, Decision D9). These topics are scheduled for development in subsequent phases once the Phase 1 direct offline MVP is fully verified on physical iPhones.
