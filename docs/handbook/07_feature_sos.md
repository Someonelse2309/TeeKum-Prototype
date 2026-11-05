# TeeKum Code Handbook — Volume 07: Feature — SOS & Inactivity Guard (Definitive Deep-Dive)

This volume provides an exhaustive, method-by-method architectural deep-dive into the emergency SOS life-safety subsystem, the 3-second continuous hold state machine, bounded retries, honest delivery feedback states, accelerometer-based immobility detection ("Man Down" Auto-SOS), and audio-haptic alerting in TeeKum.

---

## 📑 Included Source Files

1. [`TeeKum Prototype/Features/SOS/ViewModels/SOSViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/ViewModels/SOSViewModel.swift) (686 lines) — Primary ViewModel governing the 3-second trigger, bounded retries, siren banners, and honest delivery state transitions.
2. [`TeeKum Prototype/Features/SOS/Services/SOSForwardingEngine.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Services/SOSForwardingEngine.swift) (280 lines) — Multi-hop route selector (`directPeer`, `knownRoute`, `boundedFlooding`).
3. [`TeeKum Prototype/Features/SOS/Services/InactivityGuardService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Services/InactivityGuardService.swift) (317 lines) — Accelerometer stillness and screen inactivity monitor with 30-second silent warning countdown.
4. [`TeeKum Prototype/Features/SOS/Services/SOSAudioAlert.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Services/SOSAudioAlert.swift) (59 lines) — Hardware audio chime synthesis and haptic generator.
5. [`TeeKum Prototype/Features/SOS/Views/SOSButtonView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Views/SOSButtonView.swift) (374 lines) — The prominent red emergency button with continuous circular progress ring.
6. [`TeeKum Prototype/Features/SOS/Views/IncomingSOSAlertBannerView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Views/IncomingSOSAlertBannerView.swift) (220 lines) — Screen-wide emergency siren banner presenting distance, direction, and dismiss controls.
7. [`TeeKum Prototype/Features/SOS/Views/RecipientAckBreakdownView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Views/RecipientAckBreakdownView.swift) (247 lines) — Detailed sheet breaking down delivery receipts across all group members.

---

# 1. Honest Delivery Feedback: `SOSViewModel.swift`

In life-safety systems, **giving false reassurance** that help is on the way when packets are dropping over the air is dangerous. `SOSViewModel` implements four technical delivery states:

```
+-------------------+-------------------------------------------------------------+
| Delivery State    | Honest Technical Meaning                                    |
+-------------------+-------------------------------------------------------------+
| LOCAL_SENDING     | Sealed 56B packet has been enqueued onto local radio socket.|
| SEARCHING_PEERS   | Radio has zero direct peers; actively scanning for links.   |
| RELAY_ACK         | Intermediary stranger relayed the packet (NOT confirmed).   |
| DELIVERED_TO_FRIEND| Confirmed decrypted and acknowledged on a FRIEND device.    |
+-------------------+-------------------------------------------------------------+
```

---

## 1.1 The 3-Second Hold State Machine

Accidental taps in a crowded concert crowd must never sound emergency sirens on friends' phones:

```swift
    public func handlePressBegan() {
        guard deliveryState == .idle || deliveryState == .searchingPeers || deliveryState.isFailed else { return }
        holdStartTime = dateProvider()
        holdProgress = 0.0
        deliveryState = .countdown(remainingSeconds: holdThresholdSeconds)
    }
    
    public func updateProgress(elapsedSeconds: Double) {
        let progress = min(1.0, elapsedSeconds / holdThresholdSeconds)
        self.holdProgress = progress
        let remaining = max(0.0, holdThresholdSeconds - elapsedSeconds)
        self.deliveryState = .countdown(remainingSeconds: remaining)
        
        if progress >= 1.0 {
            triggerSOS(emergencyType: currentEmergencyType)
        }
    }
    
    public func handlePressCancelled() {
        if case .countdown = deliveryState {
            holdStartTime = nil
            holdProgress = 0.0
            deliveryState = .idle
        }
    }
```

### State Machine Analysis
* If the user presses the button, `deliveryState` transitions to `.countdown(3.0s)`.
* Every 50ms, `updateProgress` updates the circular progress trim on `SOSButtonView`.
* **Early Release Invariant**: If the user lifts their finger at 2.8 seconds, `handlePressCancelled()` immediately cancels the countdown, resets progress to 0.0, and **zero radio packets are broadcast**.

---

## 1.2 Bounded Retries & Honest Location Timestamps

```swift
    public func broadcastSOSWirePacket(eventId: UInt32, emergencyType: SOSType, session: GroupSession) async {
        guard let cryptoService, let transport else { return }
        
        // Freshest available coordinate without pretending an old fix is new
        let latestLocation = locationService?.getLatestLocationForSOS()
        
        let coordinate: CLLocationCoordinate2D
        let timestamp: Date
        let accuracy: UInt8
        
        if let latestLocation {
            coordinate = latestLocation.coordinate
            timestamp = latestLocation.timestamp // Original hardware GPS measurement time
            accuracy = latestLocation.rawAccuracyByte
        } else {
            coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
            timestamp = Date(timeIntervalSince1970: 0)
            accuracy = 255
        }
```

### The Truth-in-Telemetry Rule
* If GPS was lost 2 minutes ago because the user walked into an underground bunker, TeeKum transmits the last known coordinate **with its original 2-minute-old timestamp**.
* It **never manufactures** a fresh timestamp. Responders see the exact age of the location fix, preventing them from searching the wrong area if the victim was moving.

---

## 1.3 Route Selection: Known Next-Hop vs Bounded Flooding

```swift
        // Route Selection: Prefer known usable route when available
        var routeUsed = false
        if let routingTable = routingTable {
            let neighbors = await neighborTable?.activeNeighbors() ?? []
            let connectedPeerIds = Set(neighbors.map(\.id))
            for neighbor in neighbors where neighbor.isGroupMember {
                if let route = await routingTable.findRoute(to: neighbor.id),
                   route.isFresh,
                   connectedPeerIds.contains(route.nextHopPeerId) {
                    self.currentRouteChoice = .knownRoute(nextHop: route.nextHopPeerId, hopCount: route.hopCount)
                    _ = try await meshTransport.sendFrame(wireData, to: route.nextHopPeerId)
                    routeUsed = true
                    break
                }
            }
        }
        
        if !routeUsed {
            let directCount = await neighborTable?.activeNeighbors().count ?? 0
            self.currentRouteChoice = directCount > 0 ? .boundedFlooding(neighborCount: directCount) : .none
            try await transport.broadcastPacket(wireData)
        }
```

* **Tier 1 (Known Route)**: If an active unexpired path exists in `RoutingTable`, unicasts directly along the recorded next-hop (`RouteChoice.knownRoute`).
* **Tier 2 (Bounded Flooding)**: If routing tables are empty or degraded, falls back to multi-hop flooding across up to 15 hops (`RouteChoice.boundedFlooding`), maximizing the likelihood that nearby festival attendees hear the distress call.

---

# 2. "Man Down" Inactivity Guard: `InactivityGuardService.swift`

The Inactivity Guard automatically triggers an SOS alert if an attendee collapses or loses consciousness in a remote area:

```swift
@Observable
@MainActor
public final class InactivityGuardService {
    public var isEnabled: Bool = false // Opt-in default
    public private(set) var state: InactivityGuardState = .disabled
    public private(set) var countdownRemaining: Double = 0.0
    public private(set) var lastActivityTimestamp: Date
```

---

## 2.1 Accelerometer Stillness Detection Math

```swift
    private func evaluateMotionSample(acceleration: CMAcceleration) {
        // Compute Euclidean magnitude of 3-axis accelerometer vector
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        
        // At rest on Earth, magnitude equals exactly 1.0g (gravity)
        let delta = abs(magnitude - 1.0)
        
        if delta > motionThresholdG { // Default: 0.05g
            // Movement detected! User is walking or dancing
            registerActivity()
        }
    }
```

### The 30-Second Silent Warning Countdown
1. If the device experiences zero motion ($\Delta g < 0.05g$) and zero screen touches for 15 minutes (`inactivityStillnessDuration`), the service transitions to `.warning(remainingSeconds: 30)`.
2. **The Golden Invariant: NO Loud Sirens**. During this 30-second window, the phone emits gentle haptic pulses and displays a prominent visual banner: *"Are you OK? Tap to cancel"*. This prevents embarrassing loud false alarms if the user fell asleep at a festival campsite.
3. **Effortless Cancellation**: If the user picks up the phone (triggering $\Delta g > 0.05g$) or taps *"I'm OK"*, the countdown immediately aborts.
4. If the countdown reaches 0 without response, the service calls `onTriggerSOS?()`, broadcasting an emergency alert with `SOSType.inactivity`.

---

# 3. Audio & Haptic Alerts: `SOSAudioAlert.swift`

```swift
public final class DefaultSOSAudioAlerter: SOSAudioAlerting {
    public func triggerEmergencyAlertFeedback() {
        #if os(iOS) && canImport(AudioToolbox)
        // System Sound 1005: High-priority SMS alert / warning chime
        AudioServicesPlayAlertSound(SystemSoundID(1005))
        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        #endif
        
        #if os(iOS) && canImport(UIKit)
        Task { @MainActor in
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
        }
        #endif
    }
}
```

### Hardware Constraints & Platform Realities
* **Silent Switch Behavior**: Standard system audio calls (`AudioServicesPlayAlertSound`) respect the iPhone physical mute switch. When muted, `AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)` and `UINotificationFeedbackGenerator(.error)` fire heavy tactile vibrations.
* Bypassing the hardware mute switch requires Apple's restricted **Critical Alerts** entitlement (`UNAuthorizationOptions.criticalAlert`), which requires special developer licensing from Apple. In offline peer-to-peer operation, heavy haptics guarantee sensory notification even in loud concert environments.

---

Proceed to **[Volume 08: Feature — Offline P2P Chat](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/08_feature_chat.md)**.
