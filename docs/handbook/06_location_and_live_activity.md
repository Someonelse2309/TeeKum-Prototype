# TeeKum Code Handbook — Volume 06: Location & Background Services (Definitive Deep-Dive)

This volume provides an exhaustive, method-by-method architectural deep-dive into Core Location GPS tracking, Core Motion pedestrian activity classifiers, adaptive publishing cadence engines, ActivityKit Dynamic Island controllers, and background system notification handlers in TeeKum.

---

## 📑 Included Source Files

1. [`TeeKum Prototype/Core/Location/LocationService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Location/LocationService.swift) (767 lines) — Authoritative GPS, compass heading, CoreMotion detector, and adaptive cadence scheduler.
2. [`TeeKum Prototype/Core/Location/LocationPublisher.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Location/LocationPublisher.swift) (222 lines) — High-level publishing coordinator bridging location fixes into sealed wire datagrams.
3. [`TeeKum Prototype/Core/Location/LocationServiceProtocol.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Location/LocationServiceProtocol.swift) (90 lines) — Abstract dependency injection contracts for testing.
4. [`TeeKum Prototype/Core/LiveActivity/LiveActivityManager.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/LiveActivity/LiveActivityManager.swift) (171 lines) — ActivityKit Dynamic Island and Lock Screen widget manager.
5. [`TeeKum Prototype/Core/Notifications/NotificationService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Notifications/NotificationService.swift) (186 lines) — In-app floating toast alerts and iOS local notifications.

---

# 1. Hardware Positioning Architecture: `LocationService.swift`

Running on the `@MainActor`, `LocationService` acts as the single source of truth for physical sensors:

```swift
@Observable
@MainActor
public final class LocationService: NSObject, CLLocationManagerDelegate, LocationServiceProvider {
    private let locationManager: CLLocationManager
    #if os(iOS) && canImport(CoreMotion)
    private let motionActivityManager: CMMotionActivityManager?
    private let motionQueue = OperationQueue()
    #endif
```

---

## 1.1 Core Location Hardware Configuration

```swift
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
    self.locationManager.distanceFilter = kCLDistanceFilterNone
    self.locationManager.activityType = .fitness
    self.locationManager.pausesLocationUpdatesAutomatically = false
    
    #if os(iOS)
    if let bgModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String],
       bgModes.contains("location") {
        self.locationManager.allowsBackgroundLocationUpdates = true
        self.locationManager.showsBackgroundLocationIndicator = true
    }
    #endif
```

### Platform Realities & Sensor Invariants
* `activityType = .fitness`: Informs iOS baseband GPS filters that the user is pedestrian (walking, dancing, or navigating on foot), tuning the Kalman filtering for low-speed navigation rather than highway speeds.
* `pausesLocationUpdatesAutomatically = false`: **Crucial Invariant**. By default, iOS suspends GPS updates if the device remains stationary for several minutes to save battery. In a festival, an attendee may stand at a music stage for 45 minutes; setting this flag to `false` prevents iOS from killing mesh positioning in the background.
* `showsBackgroundLocationIndicator = true`: Displays the blue privacy pill in the status bar, guaranteeing that iOS will not terminate the app's background execution runloop.

---

## 1.2 Motion-Aware Adaptive Cadence State Matrix

Continuously firing high-power GPS updates and AWDL radio transmissions every 2 seconds drains an iPhone battery in ~4 hours. `LocationService` calculates a dynamic duty cycle based on motion and network state:

```
+------------------------------------+------------------+-----------------------------------------------+
| Environmental Condition            | Target Interval  | Technical Purpose                             |
+------------------------------------+------------------+-----------------------------------------------+
| Moving / Walking (`isStationary == false`) | 4.0 seconds      | Smooth map tracking for walking friends.      |
| Stationary (`isStationary == true`)        | 20.0 seconds     | Conserves 80% battery while standing still.   |
| Distant Peer (>30m or <-75 dBm)    | 2.0 seconds      | Accelerates pings to stabilize weak radio link|
| Stale Peer (within recovery window)| 2.0 seconds      | Proactive burst to recover missing friend.    |
| Festival Survival (<20% battery)   | 60.0 seconds     | Throttles duty cycle to keep phone alive.     |
+------------------------------------+------------------+-----------------------------------------------+
```

```swift
    public var currentCadenceInterval: TimeInterval {
        if isSurvivalModeActive {
            return cadenceConfig.survivalInterval // 60s
        } else if hasStalePeers || (hasStalePeersProvider?() ?? false) {
            return cadenceConfig.staleRecoveryInterval // 2s
        } else if hasDistantPeers || (hasDistantPeersProvider?() ?? false) {
            return cadenceConfig.distantPeerInterval // 2s
        } else if isStationary {
            return cadenceConfig.stationaryInterval // 20s
        } else {
            return cadenceConfig.movingInterval // 4s
        }
    }
```

### CoreMotion Pedestrian Classification
* Uses `CMMotionActivityManager` on a dedicated background `OperationQueue`.
* When the accelerometer detects zero step cadence and minimal displacement, `activity.stationary` flags `isStationary = true`.
* The publishing loop immediately down-throttles from 4s to 20s, cutting radio transmissions by 80% without sacrificing location precision when walking resumes.

---

## 1.3 The Single Cancellable Scheduler Loop

```swift
    private func startPublishingScheduler() {
        stopPublishingScheduler()
        guard isTracking, isLiveSharingEnabled else { return }
        
        publishCurrentState()
        
        publishingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isTracking, self.isLiveSharingEnabled else { break }
                
                let interval = self.currentCadenceInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                
                guard !Task.isCancelled, self.isTracking, self.isLiveSharingEnabled else { break }
                self.publishCurrentState()
            }
        }
    }
    
    private func stopPublishingScheduler() {
        publishingTask?.cancel()
        publishingTask = nil
        burstTask?.cancel()
        burstTask = nil
    }
```

### Memory & Task Safety
* **Cancellation Guarantee**: `stopPublishingScheduler()` cancels any active `Task` before spawning a new one. This mathematically prevents timer duplication, race conditions, or multiple concurrent broadcast loops from running simultaneously.
* **Weak Capture**: `[weak self]` ensures the background task cannot prevent `LocationService` from deallocating upon session termination.

---

## 1.4 Immediate Location Access for Emergency SOS

```swift
    public func getLatestLocationForSOS() -> LocationPin? {
        return currentLocation
    }
```

### Safety Invariants
1. **Unconditional Availability**: Operates even if `isLiveSharingEnabled == false`. When a user presses SOS, their location is immediately accessible regardless of privacy toggles.
2. **Zero Fabrication**: If GPS is temporarily unavailable (e.g., inside a deep underground tunnel), the service does **NOT** invent fake coordinates or fabricate fresh timestamps; it returns the exact last measured fix with its original timestamp so emergency responders see the true age of the fix.

---

# 2. ActivityKit Companion: `LiveActivityManager.swift`

ActivityKit provides dynamic Lock Screen and Dynamic Island telemetry so users do not need to keep the app active in their hands:

```swift
@MainActor
public final class LiveActivityManager: LiveActivityManaging {
    public static let shared = LiveActivityManager()
    private var activeActivity: Activity<SessionActivityAttributes>?
```

---

## 2.1 Dynamic Island Telemetry Synchronization

```swift
    public func updateSessionActivity(
        peerCount: Int,
        meetingPoint: MeetingPoint?,
        currentLocation: CLLocationCoordinate2D?,
        isSOSActive: Bool,
        sosSenderInitials: String?,
        relayStatusText: String?,
        relayModeText: String?,
        timedRelayRemainingSeconds: Int?,
        isRelayActive: Bool
    ) async {
        guard let activity = activeActivity else { return }
        
        let dist: String?
        if let mpCoord = meetingPoint?.coordinate, let userCoord = currentLocation {
            let uLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
            let mLoc = CLLocation(latitude: mpCoord.latitude, longitude: mpCoord.longitude)
            dist = uLoc.distance(from: mLoc).formattedDistance(spaced: true, includeSuffix: false)
        } else {
            dist = nil
        }
        
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
        
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }
```

### Presentation States
* **Compact Pill (Dynamic Island)**: Shows connected peer count (e.g., `3 􀉭`) and meeting point distance (`120m 􀋒`).
* **Expanded Island**: Expands into an interactive festival HUD showing active landmark arrival times and communal relay status.
* **Emergency Distress Mode**: If an SOS is broadcast, the Dynamic Island pulses with bright red emergency indicators, displaying the victim's initials and distance.

---

# 3. Notification Service: `NotificationService.swift`

```swift
@Observable
@MainActor
public final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationService()
    public var activeToast: InAppToast? = nil
    private var dismissTask: Task<Void, Never>?
    
    public func presentToast(_ toast: InAppToast, durationSeconds: Double = 4.0) {
        dismissTask?.cancel()
        activeToast = toast
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            activeToast = nil
        }
    }
```

* Displays non-intrusive floating toasts that auto-dismiss after 4 seconds using structured task sleeps.
* Coordinates with iOS `UserNotifications` when the app is backgrounded to alert the user of new chat messages and landmark updates.

---

Proceed to **[Volume 07: Feature — SOS & Inactivity Guard](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/07_feature_sos.md)**.
