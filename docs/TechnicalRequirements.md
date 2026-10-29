# TeeKum

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
| **D7 — 54-Byte Binary Packet (Protocol v2), 16-Bit Session ID & Coordinate Quantization** | CoreLocation `Double` (`CLLocationDegrees`) coordinates are quantized into big-endian signed 32-bit integers `Int32` (`degrees * 1_000_000`) for ~11 cm resolution. Wire packets are fixed at 54 bytes (8B cleartext envelope + 30B encrypted payload + 16B Poly1305 authentication tag). Group session ID is 16 bits (`UInt16`, `0x0001...0xFFFF`) derived via SHA-256 over timestamp, GPS coordinates, and CSPRNG salt. |
| **D8 — 2-Byte Base-27 1-to-3 Letter Sender Initials & Serverless QR Group Formation** | Ephemeral member identification inside the 30-byte encrypted payload is compressed from 4 bytes down to exactly 2 bytes (`UInt16`) using base-27 radix encoding of 1 to 3 uppercase letters ($A \dots Z$, e.g. "D", "AB", "DNA", total $18,278 \le 65,535$). Every packet is self-describing, rendering member avatars instantly on the receiving map/radar and completely eliminating runtime P2P radio handshakes. Group formation and 256-bit key exchange are handled serverless via CoreImage QR barcode generation and AVFoundation camera scanning. |

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
TeeKum/
├── App/
│   └── TeeKumApp.swift              // Entry point & root state view switcher
├── Models/
│   ├── Member.swift                   // Member model (id, name, lastSeen)
│   ├── LocationPin.swift              // CoreLocation Coordinate (Double), accuracy, timestamp
│   ├── Status.swift                   // Festival activity status enum & target references
│   ├── MeetingPoint.swift             // Single active rendezvous point model & attendance
│   └── Packet.swift                   // 54-byte binary packet layout (Protocol v2), encoding & decoding
├── Views/
│   ├── MainMapView.swift              // MapKit view, friend pins, status pills, Live Sharing toggle
│   ├── GroupPairingView.swift         // QR barcode display & camera scanner / Link share sheet
│   ├── StatusPickerView.swift         // One-handed horizontal status chips carousel
│   ├── SOSButtonView.swift            // 3-second hold emergency button & visual progress ring
│   ├── FinderBeaconView.swift         // 360° Compass arrow -> UWB precision radar & strobe torch
│   ├── MeetingPointsView.swift        // Meeting point proposal sheet & attendance cards
│   └── DiagnosticsView.swift          // Debug HUD sheet (live RSSI dBm, peer count, packet counters)
├── ViewModels/
│   ├── MapViewModel.swift             // Map viewport state, friend pins, offline filtering
│   ├── GroupSessionViewModel.swift    // Group session lifecycle, QR/Link pairing, member roster
│   ├── MeetingPointViewModel.swift    // Single active meeting point state & attendance sync
│   └── SOSViewModel.swift             // 3-second hold countdown & honest delivery status
├── Services/
│   ├── LocationService.swift          // CoreLocation wrapper & adaptive battery sampling
│   ├── PeerTransportService.swift     // Network.framework P2P datagram transmission (actor)
│   ├── CryptoService.swift            // ChaChaPoly/AES-GCM encryption & Keychain store (actor)
│   └── SessionStorage.swift           // SQLite ephemeral crash-recovery snapshot (actor)
├── docs/
│   ├── TechnicalRequirements.md       // Technical system requirements specification
│   ├── Architecture.md
│   └── AGENT_PROMPT.md                // AI coding agent onboarding & task playbook
└── Tests/
    └── UnitTests/
        ├── PacketCodecTests.swift     // 54-byte packet codec roundtrip & quantization tests
        └── CryptoSecurityTests.swift  // Tamper rejection & replay attack defense tests
```

---

## 4. Unit Testing Strategy

[Placeholder — Will be discussed and populated when test implementation begins.]

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
- [x] Review decisions D1–D8 from /grill-me sessions are recorded in the Approved Decisions table.
- [x] 54-byte binary packet wire format (Protocol v2), 2-byte Base-26 initials codec (zero handshake), 16-bit session ID derivation, envelope separation, and CoreLocation `Double` quantization are documented.
- [x] Unit Testing Strategy is maintained as a placeholder as agreed.
- [x] 4-branch Git workflow (`main`, `develop`, `prod`, `feat/*`) and commit conventions are established.

### Open Decisions for Future Phases

Implementation of custom vector venue floorplans (Phase 3), Apple Watch haptic companion extension (Phase 3), and large stadium-scale multi-hop mesh experiments (Phase 2). These topics are scheduled for development in subsequent phases once the Phase 1 direct offline MVP is fully verified on physical iPhones.
