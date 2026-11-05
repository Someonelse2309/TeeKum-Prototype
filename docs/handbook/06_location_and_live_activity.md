# TeeKum Code Handbook — Volume 06: Location & Background Services

This volume examines the Core Location GPS and compass heading streams, Core Motion activity classifiers, adaptive publishing cadence engines, ActivityKit Dynamic Island controllers, and background system notification handlers in TeeKum.

---

## 📑 Included Files

1. [`TeeKum Prototype/Core/Location/LocationService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Location/LocationService.swift) — Authoritative GPS positioning, CoreMotion activity detection, and adaptive cadence scheduler.
2. [`TeeKum Prototype/Core/Location/LocationPublisher.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Location/LocationPublisher.swift) — Coordinates 30-byte `LocationPingPayload` packing, monotonic counter incrementing, and radio dispatch.
3. [`TeeKum Prototype/Core/Location/LocationServiceProtocol.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Location/LocationServiceProtocol.swift) — Interface defining location services for unit test mocking.
4. [`TeeKum Prototype/Core/LiveActivity/LiveActivityManager.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/LiveActivity/LiveActivityManager.swift) — ActivityKit Dynamic Island and Lock Screen companion manager.
5. [`TeeKum Prototype/Core/Notifications/NotificationService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Notifications/NotificationService.swift) — In-app HUD toasts and iOS local notification dispatch.

---

# 1. Authoritative Positioning: `LocationService.swift`

## 1.1 State & Hardware Managers

```swift
@Observable
@MainActor
public final class LocationService: NSObject, CLLocationManagerDelegate, LocationServiceProvider {
    private let locationManager: CLLocationManager
    #if os(iOS) && canImport(CoreMotion)
    private let motionActivityManager: CMMotionActivityManager?
    private let motionQueue = OperationQueue()
    #endif
    
    public private(set) var currentLocation: LocationPin?
    public private(set) var currentHeading: CLLocationDirection?
    public private(set) var isStationary: Bool = false
    public var hasDistantPeers: Bool = false
    public var hasStalePeers: Bool = false
    public var isLiveSharingEnabled: Bool = true
    public private(set) var isSurvivalModeActive: Bool = false
    public private(set) var currentBatteryLevel: Float = 1.0
```

### iOS Hardware Configuration
```swift
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
    self.locationManager.distanceFilter = kCLDistanceFilterNone
    self.locationManager.activityType = .fitness
    self.locationManager.pausesLocationUpdatesAutomatically = false
    self.locationManager.allowsBackgroundLocationUpdates = true
    self.locationManager.showsBackgroundLocationIndicator = true
```

* `activityType = .fitness`: Informs iOS that the user is on foot (walking, dancing, or running across festival grounds), optimizing Kalman filter algorithms for pedestrian speeds.
* `pausesLocationUpdatesAutomatically = false`: Crucial invariant. Prevents iOS from killing location updates when the user stands still near a music stage for 10 minutes.
* `allowsBackgroundLocationUpdates = true`: Keeps GPS active when the phone is locked in a pocket.

---

## 1.2 Motion-Aware Adaptive Cadence Engine

Continuously firing high-power GPS and AWDL radio bursts every 2 seconds drains the iPhone battery in ~4 hours. `LocationService` calculates an **adaptive duty cycle**:

```
+-----------------------------------+-----------------------------------+
| System & User Condition           | Requested Publishing Cadence      |
+-----------------------------------+-----------------------------------+
| Moving / Walking on foot          | 4.0 seconds                       |
| Stationary / Standing at a stage  | 20.0 seconds (saves 80% battery)  |
| Distant Peer (>30m or <-75 dBm)   | 2.0 seconds (accelerated link)    |
| Stale Peer (within recovery window| 2.0 seconds (recovery burst)      |
| Festival Survival (<20% battery)  | 60.0 seconds (preserves phone)    |
+-----------------------------------+-----------------------------------+
```

```swift
    public var targetPublishingInterval: TimeInterval {
        if isSurvivalModeActive {
            return cadenceConfig.survivalInterval // 60s
        }
        if hasStalePeers || hasDistantPeers {
            return cadenceConfig.distantPeerInterval // 2s
        }
        if isStationary {
            return cadenceConfig.stationaryInterval // 20s
        }
        return cadenceConfig.movingInterval // 4s
    }
```

### CoreMotion Detection
* Uses `CMMotionActivityManager` on its own private background `OperationQueue`.
* When `activity.stationary == true`, flags `isStationary = true`, immediately down-throttling radio transmissions without sacrificing location accuracy when walking resumes.

---

# 2. Location Publisher: `LocationPublisher.swift`

`LocationPublisher` bridges physical sensor measurements into sealed wire datagrams:

```swift
    public func publishLocation(coordinate: CLLocationCoordinate2D, accuracy: Double) async {
        guard let session = sessionProvider() else { return }
        
        let counter = monotonicCounter
        monotonicCounter &+= 1
        
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .locationPing,
            hopLimit: PacketConstants.defaultHopLimit,
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: CleartextEnvelope.makeSequenceNumber(
                memberSlot: session.memberSlot,
                counter: counter
            )
        )
        
        let payload = LocationPingPayload(
            coordinate: coordinate,
            timestamp: Date(),
            accuracy: UInt8(min(255, max(0, Int(accuracy.rounded())))),
            senderInitials: session.localInitials,
            batteryLevel: locationService.currentBatteryLevel.asBatteryPercentage,
            heading: UInt8(min(255, max(0, Int(((locationService.currentHeading ?? 0.0) * 255.0 / 360.0).rounded())))),
            colorCode: session.localColorCode
        )
```

### Wire Packing Details
* `monotonicCounter &+= 1`: Safe wrapping increment of the local monotonic sequence counter.
* `batteryLevel`: Quantized float-to-byte percentage.
* `heading`: Maps $0^\circ \dots 360^\circ$ into $0 \dots 255$ (`UInt8`).
* Coalesces battery, heading, and GPS into a single unfragmented 30-byte datagram.

---

# 3. Dynamic Island Companion: `LiveActivityManager.swift`

ActivityKit provides Lock Screen and Dynamic Island telemetry so users do not need to keep the app open in their hands.

```swift
@MainActor
public final class LiveActivityManager: LiveActivityManaging {
    public static let shared = LiveActivityManager()
    private var activeActivity: Activity<SessionActivityAttributes>?
```

### Dynamic Island State Content
```swift
    let state = SessionActivityAttributes.ContentState(
        peerCount: peerCount,
        meetingPointName: meetingPoint?.name,
        meetingPointDistance: dist,
        meetingPointTime: meetingPoint?.targetTime.formattedMeetupTime,
        isSOSActive: isSOSActive,
        sosSenderInitials: sosSenderInitials,
        relayStatusText: relayStatusText,
        relayModeText: relayModeText,
        timedRelayRemainingSeconds: timedRelayRemainingSeconds,
        isRelayActive: isRelayActive
    )
```

* Displays active peer count in the Dynamic Island pill.
* Displays distance to current meeting point (e.g., *"Main Stage: 120m away"*).
* If an SOS is broadcast, turns into a flashing emergency siren widget showing the victim's initials and distance.

---

# 4. In-App HUD Banners: `NotificationService.swift`

```swift
@Observable
@MainActor
public final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationService()
    public var activeToast: InAppToast? = nil
    
    public func presentToast(_ toast: InAppToast, durationSeconds: Double = 4.0) {
        dismissTask?.cancel()
        activeToast = toast
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            activeToast = nil
        }
    }
}
```

* Displays non-blocking, tactile top toasts for festival events (e.g., *"DNA: Meet at Ferris Wheel in 15m"*).
* Automatically dismisses after 4 seconds using a cancellable `Task.sleep` without blocking the main UI thread.

---

Proceed to **[Volume 07: Feature — SOS & Inactivity Guard](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/07_feature_sos.md)**.
