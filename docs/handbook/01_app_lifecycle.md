# TeeKum Code Handbook — Volume 01: App Lifecycle & Root Navigation

This volume provides an exhaustive, code-block by code-block breakdown of the application entry point, root view container, thread-safe session bridging, and shared UI presentation formatters.

---

## 📑 Included Files

1. [`TeeKum Prototype/App/TeeKumApp.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/App/TeeKumApp.swift) — Application entry point, dependency injection, lifecycle management, and test runners.
2. [`TeeKum Prototype/App/AppRootView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/App/AppRootView.swift) — Root view switcher toggling between pairing and the active map session.
3. [`TeeKum Prototype/Shared/UI/Formatters.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Shared/UI/Formatters.swift) — Low-level bit quantization, distance, battery, date, and clock direction formatters.
4. [`TeeKum Prototype/Shared/UI/InAppToastView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Shared/UI/InAppToastView.swift) — Floating HUD alert banner for real-time mesh events.

---

# 1. `TeeKumApp.swift`

## 1.1 `SessionHolder` Class

```swift
/// Thread-safe Sendable wrapper to provide synchronous access to the active GroupSession
/// across actors and non-isolated closures without violating actor isolation boundaries.
public final class SessionHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _session: GroupSession?
    
    public init(session: GroupSession? = nil) {
        self._session = session
    }
    
    public var session: GroupSession? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _session
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _session = newValue
        }
    }
}
```

### Line-by-Line Breakdown
* `public final class SessionHolder: @unchecked Sendable`: Declares a reference type that can be passed freely across concurrent boundaries. The `@unchecked Sendable` attribute disables the Swift 6 compiler check for data races on mutable properties because thread-safety is manually guaranteed via mutual exclusion.
* `private let lock = NSLock()`: A POSIX-backed mutual exclusion primitive from Darwin/Foundation. Unlike an `actor`, `NSLock` allows **synchronous**, non-`await` property read/write access.
* `private var _session: GroupSession?`: The backing storage holding the immutable snapshot of the active mesh group session (keys, session ID, local initials).
* `public var session: GroupSession?`: Computed property wrapper with synchronized getter and setter.
* `lock.lock(); defer { lock.unlock() }`: Acquires the mutex before reading or writing `_session`, and guarantees that the lock is released when the stack frame unwinds (even if an unexpected crash or return occurs).

### Concurrency & Memory Safety
* **Why not an `actor`?** Many high-frequency audio or radio delegate callbacks require synchronous, non-blocking access to the current session key. Calling `await actor.session` inside an audio render loop or tight byte framing loop would introduce thread hopping and latency.
* **Why `final`?** Prevents subclassing, allowing the compiler to perform devirtualization (direct memory function pointer calling instead of vtable dispatch).

### Edge Cases & Pitfalls
* **Lock Contention**: The critical section inside `lock.lock()` is strictly a pointer copy (nanoseconds). It never executes heavy business logic or network I/O, preventing priority inversions.

---

## 1.2 `TeeKumApp` Struct & Stored Properties

```swift
@main
struct TeeKumApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var sessionViewModel = GroupSessionViewModel()
    @State private var locationService: LocationService
    @State private var mapViewModel: MapViewModel
    @State private var sosViewModel = SOSViewModel()
    @State private var meetingPointViewModel = MeetingPointViewModel()
    @State private var locationPublisher: LocationPublisher?
    private let seenPacketCache = SeenPacketCache()
    private let cryptoService = CryptoService()
    private let peerTransport: PeerTransportService
    private let relayPolicyManager: RelayPolicyManager
    private let routingTable: RoutingTable
    private let routeDiscoveryService: RouteDiscoveryService
    private let chatMessageEngine: ChatMessageEngine
    @State private var chatViewModel: ChatViewModel
    @State private var packetRouter: PacketRouter?
    private let sessionHolder: SessionHolder
```

### Line-by-Line Breakdown
* `@main`: The Swift compiler attribute indicating that this type represents the binary executable's entry point (`main()` function).
* `struct TeeKumApp: App`: Adopts SwiftUI's `App` protocol, replacing the legacy `UIApplicationDelegate` boilerplate.
* `@Environment(\.scenePhase)`: Observes system application state changes (`.active`, `.inactive`, `.background`).
* `@State private var ...`: View-model references wrapped in `@State` to tie their life cycle to the root scene graph, ensuring they persist across SwiftUI body evaluations.
* `private let seenPacketCache = SeenPacketCache()`: Instantiates the actor-isolated bloom/ring deduplication cache.
* `private let cryptoService = CryptoService()`: Instantiates the AES-GCM-256 actor.
* `private let peerTransport: PeerTransportService`: Radio controller managing Apple MultipeerConnectivity sessions.
* `private let relayPolicyManager: RelayPolicyManager`: Manages communal mesh participation modes and battery limits.

---

## 1.3 `init()` Dependency Injection Graph

```swift
    init() {
        let initialSessionVM = GroupSessionViewModel()
        self._sessionViewModel = State(initialValue: initialSessionVM)
        let holder = SessionHolder(session: initialSessionVM.activeSession)
        self.sessionHolder = holder
        
        let service = LocationService()
        _locationService = State(initialValue: service)
        _mapViewModel = State(initialValue: MapViewModel(locationService: service))
        let transport = PeerTransportService()
        self.peerTransport = transport
        self.relayPolicyManager = RelayPolicyManager(transport: transport)
        let routing = RoutingTable()
        self.routingTable = routing
        self.routeDiscoveryService = RouteDiscoveryService(
            routingTable: routing,
            neighborTable: transport.neighborTable,
            transport: transport,
            cryptoService: cryptoService
        )
        let chatEngine = ChatMessageEngine(
            transport: transport,
            cryptoService: cryptoService,
            routingTable: routing,
            neighborTable: transport.neighborTable,
            rateLimiter: transport.rateLimiter
        )
        self.chatMessageEngine = chatEngine
        self._chatViewModel = State(initialValue: ChatViewModel(chatService: chatEngine))
        
        // Clean up any lingering Live Activities if app launched without an active session
        if !initialSessionVM.hasActiveSession {
            Task { @MainActor in
                await LiveActivityManager.shared.cleanupDanglingActivities()
            }
        }
    }
```

### Line-by-Line Breakdown
* `let initialSessionVM = GroupSessionViewModel()`: Loads any previously persisted session from the Keychain/UserDefaults synchronously.
* `_sessionViewModel = State(initialValue: ...)`: Explicit initialization of the underlying SwiftUI `@State` storage box before view layout begins.
* `let holder = SessionHolder(...)`: Bridges the initial session into the non-isolated concurrency holder.
* `RouteDiscoveryService(...)`: Wires proactive AODV route discovery with the routing table, neighbor table, radio transport, and cryptographic service.
* `ChatMessageEngine(...)`: Wires the offline chat engine with outbox retries, rate limiting, and neighbor awareness.
* `if !initialSessionVM.hasActiveSession`: If the user launched the app after a crash or device reboot without an active session, an asynchronous task immediately cleans up any orphaned iOS Live Activity widgets on the Lock Screen.

---

## 1.4 Dynamic Scene & Telemetry Observers

```swift
    var body: some Scene {
        WindowGroup {
            AppRootView(...)
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    locationService.updateBatteryState()
                    if sessionViewModel.hasActiveSession {
                        locationService.publishCurrentState()
                    }
                }
            }
            .onChange(of: locationService.isLowPowerMode) { _, isLowPower in
                chatViewModel.updateBattery(
                    level: locationService.currentBatteryLevel,
                    isLowPower: isLowPower
                )
                Task {
                    await relayPolicyManager.updatePowerMetrics(
                        batteryLevel: locationService.currentBatteryLevel,
                        isLowPowerMode: isLowPower
                    )
                    await chatMessageEngine.setBatteryLevel(
                        locationService.currentBatteryLevel,
                        isLowPowerMode: isLowPower
                    )
                    if locationService.isSurvivalModeActive {
                        await LiveActivityManager.shared.endSessionActivity()
                    }
                    await updateLiveActivityTelemetry()
                }
            }
```

### Engineering Analysis
* `.preferredColorScheme(.dark)`: Locks the UI into high-contrast night mode to conserve OLED battery power during festivals.
* `.onChange(of: scenePhase)`: When transitioning back to `.active`, updates battery statistics and immediately broadcasts a fresh location ping so nearby friends get current coordinates after screen unlock.
* `.onChange(of: locationService.isLowPowerMode)`: Dynamically informs the `relayPolicyManager`. If the battery hits critical low power, communal packet forwarding is throttled or killed to save the user's phone for emergency calls.

---

## 1.5 Session Lifecycle: `runSessionLifecycle`

```swift
    @MainActor
    private func runSessionLifecycle(session: GroupSession) async {
        sessionHolder.session = session
        let holder = self.sessionHolder
        
        // 1. Start Location Tracking
        try? locationService.startTracking()
        
        // 2. Start Live Activity Companion & Request Notifications
        await LiveActivityManager.shared.startSessionActivity(session: session)
        NotificationService.shared.requestAuthorization()
        
        // 3. Configure SOS
        sosViewModel.configure(
            locationService: locationService,
            sessionProvider: { holder.session },
            cryptoService: cryptoService,
            transport: peerTransport,
            memberNameResolver: { senderInitials in
                senderInitials
            }
        )
```

### Line-by-Line Breakdown
* `@MainActor private func runSessionLifecycle(...) async`: Pinned to the main thread to safely mutate view-model state and launch background asynchronous streams.
* `try? locationService.startTracking()`: Initializes `CLLocationManager` updates with distance filters.
* `LiveActivityManager.shared.startSessionActivity(session:)`: Launches the Dynamic Island widget displaying friend counts and distance.
* `sosViewModel.configure(...)`: Injects closures allowing the SOS module to access current location and peer cryptographic keys without creating retain cycles.

---

## 1.6 Inbound Mesh Stream Dispatcher & Peer Supervisor

```swift
        let inboundStream = await peerTransport.inboundPackets
        let peerUpdatesStream = await peerTransport.peerUpdates
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await inbound in inboundStream {
                    guard !Task.isCancelled else { break }
                    await router.routeInboundPacket(inbound, for: session)
                }
            }
            
            group.addTask { @MainActor in
                for await peers in peerUpdatesStream {
                    guard !Task.isCancelled else { break }
                    handlePeerUpdates(peers, for: session)
                    if peers.contains(where: { $0.isDirectLink }) {
                        locationService.publishCurrentState()
                        await meetingPointViewModel.syncActiveMeetingPointToPeers()
                    }
                }
            }
```

### Concurrency Mechanics
* `await withTaskGroup(of: Void.self)`: Spawns structured concurrent child tasks. If the parent session is terminated, cancelling this group automatically cancels both `for await` loops.
* `for await inbound in inboundStream`: Asynchronously consumes wire datagrams coming from the radio as soon as they arrive on the network thread.
* `if peers.contains(where: { $0.isDirectLink })`: Whenever a new direct peer connects over AWDL, the app immediately announces its own location and syncs the current meeting point beacon.

---

## 1.7 Two-Tier Stale Peer Recovery Loop

```swift
            // Stage 2 Check: On-demand AODV ROUTE_REQ staggered across multiple stale peers
            if now.timeIntervalSince(lastGlobalRouteReqDispatch) >= timing.staleRouteReqStaggerInterval {
                let eligibleMembers = sessionViewModel.members.filter {
                    $0.isEligibleForStaleRouteDiscovery(
                        now: now,
                        staleThreshold: timing.stalePeerThreshold,
                        routeReqDelay: timing.staleRouteReqDelay,
                        recoveryTimeout: timing.staleRecoveryTimeout
                    ) && now.timeIntervalSince(lastRouteReqTimes[$0.id] ?? .distantPast) >= 10.0
                }.sorted { $0.lastSeen < $1.lastSeen }
                
                if let target = eligibleMembers.first {
                    lastGlobalRouteReqDispatch = now
                    lastRouteReqTimes[target.id] = now
                    Task {
                        _ = try? await routeDiscoveryService.initiateDiscovery(
                            to: target.id,
                            session: session,
                            timeout: 3.0
                        )
                    }
                }
            }
```

### Wire & Routing Logic
* **Problem**: In a festival, a friend walks behind a stage and their direct Wi-Fi link drops.
* **Tier 1**: Accelerate local location ping cadence from 15s down to 5s in case they are just out of range.
* **Tier 2**: If they remain missing after 45s, dispatch a multi-hop `ROUTE_REQ` through other festival attendees to rebuild the route before declaring them lost.
* **Rate Staggering**: Global dispatches are throttled so multiple stale friends do not congest the radio with broadcast storms.

---

# 2. `AppRootView.swift`

```swift
/// Plain root view that presents either GroupPairingView or MainMapView based on session state.
struct AppRootView: View {
    @Bindable var sessionViewModel: GroupSessionViewModel
    var mapViewModel: MapViewModel
    var sosViewModel: SOSViewModel
    var meetingPointViewModel: MeetingPointViewModel
    var chatViewModel: ChatViewModel
    var relayPolicyManager: RelayPolicyManager
    var peerTransport: PeerTransportService
    
    var onSessionStart: (GroupSession) async -> Void
    var onSessionEnd: () async -> Void
    
    var body: some View {
        Group {
            if sessionViewModel.hasActiveSession, let session = sessionViewModel.activeSession {
                MainMapView(...)
                .task(id: session.sessionId) {
                    await onSessionStart(session)
                }
            } else {
                GroupPairingView(...)
                .task {
                    await onSessionEnd()
                }
            }
        }
    }
}
```

### Architectural Analysis
* `@Bindable var sessionViewModel`: Swift Observation macro property wrapper allowing SwiftUI to create two-way bindings to properties of an `@Observable` class.
* `.task(id: session.sessionId)`: SwiftUI lifecycle modifier. Whenever `sessionId` changes, the previous asynchronous task is cancelled, and `onSessionStart` is invoked for the new session.
* `.task` on `GroupPairingView`: When the session ends, automatically triggers `onSessionEnd()` to tear down radio sessions, clear in-memory caches, and stop location publishers.

---

# 3. `Formatters.swift`

## 3.1 Distance & Battery Quantization

```swift
extension CLLocationDistance {
    public func formattedDistance(spaced: Bool = true, includeSuffix: Bool = false) -> String {
        let text: String
        let space = spaced ? " " : ""
        if self >= 1000.0 {
            text = String(format: "%.1f\(space)km", self / 1000.0)
        } else {
            text = String(format: "%.0f\(space)m", self)
        }
        return includeSuffix ? "\(text) away" : text
    }
}

extension Float {
    public var asBatteryPercentage: UInt8 {
        UInt8(min(100, max(0, Int((self * 100.0).rounded()))))
    }
}
```

### Bit Math & Semantics
* `formattedDistance`: Avoids expensive `MeasurementFormatter` allocations by using raw string formatting with microsecond execution speed.
* `asBatteryPercentage`: Normalizes a `0.0...1.0` iOS battery float into an 8-bit unsigned integer `UInt8(0...100)` to fit into exactly 1 byte on the wire datagram.

---

## 3.2 Coordinate Scaling Factor & Compass Quantization

```swift
extension CLLocationCoordinate2D {
    public var rawLatitude: Int32 {
        Int32((latitude * LocationPin.coordinateScalingFactor).rounded())
    }
    
    public var rawLongitude: Int32 {
        Int32((longitude * LocationPin.coordinateScalingFactor).rounded())
    }
}

extension CLLocationDirection {
    public var quantizedHeadingByte: UInt8 {
        UInt8(min(255, max(0, Int((self * 255.0 / 360.0).rounded()))))
    }
    
    public static func fromHeadingByte(_ byte: UInt8) -> CLLocationDirection {
        Double(byte) * 360.0 / 255.0
    }
}
```

### Mathematical Mechanics
* **Fixed-Point Scaling**: Multiplies double-precision latitude/longitude by `10,000,000` (scaling factor). This preserves 7 decimal digits of precision (~11mm resolution) while packing the coordinate into a signed 32-bit integer (`Int32`, 4 bytes) instead of an 8-byte double (`Double`).
* **Heading Quantization**: Maps `0.0° .. 359.99°` into `0 .. 255` (`UInt8`), saving 7 bytes per packet while retaining 1.4° angular resolution—more than sufficient for radar direction cones.

---

## 3.3 Tactical Clock Direction

```swift
extension Double {
    public var clockDirection: String {
        let normalized = (self + 360.0).truncatingRemainder(dividingBy: 360.0)
        let hour = Int((normalized + 15.0) / 30.0) % 12
        let displayHour = hour == 0 ? 12 : hour
        if displayHour == 12 {
            return "Ahead"
        } else if displayHour == 6 {
            return "Behind"
        } else {
            return "\(displayHour) o'clock"
        }
    }
}
```

### Trigonometric Rationale
* Converts a bearing angle in degrees into human-intuitive directions (e.g. *"Bob is at your 2 o'clock"*). Adding `15.0°` before dividing by `30.0°` (360° / 12 hours) creates centered 30° bins for each clock hour.

---

# 4. `InAppToastView.swift`

```swift
public struct InAppToastView: View {
    let toast: InAppToast
    let onDismiss: () -> Void
    
    public init(toast: InAppToast, onDismiss: @escaping () -> Void) {
        self.toast = toast
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        Button {
            toast.action?()
            onDismiss()
        } label: {
            HStack(spacing: 12) { ... }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.12))
                    .shadow(color: Color.black.opacity(0.6), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(toast.accentColor.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
```

### SwiftUI Performance & Design
* Encapsulates tap actions and auto-dismissal into a reusable tactile banner.
* High shadow elevation (`radius: 12`) and translucent border stroke ensure readability over 3D satellite map terrain.

---

Proceed to **[Volume 02: Wire Protocol & Domain Models](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/02_models_and_wire_types.md)**.
