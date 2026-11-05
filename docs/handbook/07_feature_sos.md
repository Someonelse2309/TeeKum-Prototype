# TeeKum Code Handbook — Volume 07: Feature — SOS & Inactivity Guard

This volume breaks down the emergency life-safety subsystem in TeeKum, covering the 3-second continuous hold gesture, immediate radio dispatch, multi-hop siren forwarding, honest delivery feedback states, accelerometer-based immobility detection ("Man Down" Auto-SOS), and audio-haptic alerting.

---

## 📑 Included Files

1. [`TeeKum Prototype/Features/SOS/ViewModels/SOSViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/ViewModels/SOSViewModel.swift) — Primary ViewModel governing the 3-second trigger, bounded retries, and incoming siren banners.
2. [`TeeKum Prototype/Features/SOS/Services/SOSForwardingEngine.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Services/SOSForwardingEngine.swift) — Multi-hop route selector (`directPeer`, `knownRoute`, `boundedFlooding`).
3. [`TeeKum Prototype/Features/SOS/Services/InactivityGuardService.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Services/InactivityGuardService.swift) — Accelerometer stillness and screen inactivity monitor with 30-second pre-alarm countdown.
4. [`TeeKum Prototype/Features/SOS/Services/SOSAudioAlert.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Services/SOSAudioAlert.swift) — Hardware audio chime synthesis and haptic generator.
5. [`TeeKum Prototype/Features/SOS/Views/SOSButtonView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Views/SOSButtonView.swift) — The prominent red emergency button with continuous circular progress ring.
6. [`TeeKum Prototype/Features/SOS/Views/IncomingSOSAlertBannerView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Views/IncomingSOSAlertBannerView.swift) — Screen-wide emergency siren banner presenting distance, direction, and dismiss controls.
7. [`TeeKum Prototype/Features/SOS/Views/RecipientAckBreakdownView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/SOS/Views/RecipientAckBreakdownView.swift) — Detailed sheet breaking down delivery receipts across all group members.

---

# 1. Honest Delivery Feedback: `SOSViewModel.swift`

In life-safety mesh systems, **falsely reassuring the victim** that help is on the way when packets are dropping is dangerous. `SOSViewModel` implements four strictly defined delivery feedback states:

```
+-------------------+-------------------------------------------------------------+
| Delivery State    | Honest Technical Meaning                                    |
+-------------------+-------------------------------------------------------------+
| LOCAL_SENDING     | Sealed wire datagram has been queued onto local radio link. |
| SEARCHING_PEERS   | Dispatched without direct peers; radio actively scanning.   |
| RELAY_ACK         | Intermediary stranger relayed the packet (NOT confirmed).   |
| DELIVERED_TO_FRIEND| Confirmed decrypted and acknowledged on a FRIEND device.    |
+-------------------+-------------------------------------------------------------+
```

---

## 1.1 The 3-Second Hold Gesture & Cancellation

Accidental taps at a music festival must never dispatch emergency sirens to friends' phones. `SOSViewModel` enforces a continuous 3.0-second hold:

```swift
    public func startHoldPress() {
        guard deliveryState == .idle || deliveryState == .failed else { return }
        holdProgress = 0.0
        
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            let stepInterval: Double = 0.05
            let totalSteps = Int(holdThresholdSeconds / stepInterval) // 60 steps
            
            for step in 1...totalSteps {
                try? await Task.sleep(nanoseconds: UInt64(stepInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                holdProgress = Double(step) / Double(totalSteps)
            }
            
            // 3.0 seconds elapsed continuously! Trigger emergency dispatch
            await triggerSOS(type: currentEmergencyType)
        }
    }
    
    public func cancelHoldPress() {
        holdTask?.cancel()
        holdTask = nil
        holdProgress = 0.0
    }
```

### UX Rationale
* If the user lifts their finger at 2.8 seconds, `cancelHoldPress()` executes. `holdTask` is cancelled, progress snaps back to 0.0, and **zero radio packets are broadcast**.

---

## 1.2 Bypassing Ordinary Intervals

```swift
    public func triggerSOS(type: SOSType = .general) async {
        deliveryState = .localSending
        retryCount = 0
        
        let eventId = UInt32.random(in: 1...UInt32.max)
        self.activeSOSEventId = eventId
        
        // Immediate priority dispatch: Does NOT wait for GPS lock or cadence timers
        await dispatchSOSWirePacket(eventId: eventId, type: type)
        startBoundedRetries(eventId: eventId, type: type)
    }
```

* Emergency SOS packets enter `PriorityOutboxQueue.urgentLane` immediately. They bypass ordinary location ping timers and are given the highest hop limit (`sosHopLimit = 15`).

---

# 2. "Man Down" Inactivity Guard: `InactivityGuardService.swift`

The Inactivity Guard detects if an attendee collapses, becomes unconscious, or falls into a crowd surge without being able to press the SOS button.

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

## 2.1 Hybrid Sensor Motion Detection

```swift
    private func evaluateMotionSample(acceleration: CMAcceleration) {
        // Calculate total gravitational magnitude vector
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        
        // At rest, magnitude equals 1.0g (Earth gravity)
        let delta = abs(magnitude - 1.0)
        
        if delta > motionThresholdG { // Default: 0.05g
            // Movement detected! User is active
            registerActivity()
        }
    }
```

### The 30-Second Silent Warning Countdown
1. If the device experiences zero motion ($|g - 1.0| < 0.05g$) and zero screen touches for 15 minutes (`inactivityStillnessDuration`), the service enters `.warning(remainingSeconds: 30)`.
2. **Crucial Invariant**: During this 30-second window, **NO loud sirens sound**. The phone vibrates gently with increasing haptic pulses and displays a prominent *"Are you OK?"* dialog.
3. If the user picks up their phone, changes position, or taps *"I'm OK"*, the countdown is immediately aborted.
4. If the countdown reaches 0 seconds without response, `onTriggerSOS?()` automatically broadcasts an emergency alert with `SOSType.inactivity`.

---

# 3. Multi-Hop SOS Forwarding: `SOSForwardingEngine.swift`

When an SOS is dispatched, the engine inspects the network topology:

```swift
public enum RouteChoice: Equatable, Sendable {
    case directPeer(peerId: String)
    case knownRoute(nextHop: String, hopCount: UInt8)
    case boundedFlooding(neighborCount: Int)
    case none
}
```

* If a direct connection to a group friend exists, unicasts directly (`directPeer`).
* If a multi-hop path was previously learned, forwards along the recorded next-hop (`knownRoute`).
* If routes are uncertain or broken, defaults to **bounded multi-hop flooding** to all direct radio neighbors, ensuring the emergency reaches someone in range.

---

# 4. Audio-Haptic Feedback: `SOSAudioAlert.swift`

```swift
public final class DefaultSOSAudioAlerter: SOSAudioAlerting {
    public func triggerEmergencyAlertFeedback() {
        #if os(iOS) && canImport(AudioToolbox)
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

* Combines high-priority system chimes with `UINotificationFeedbackGenerator(.error)` heavy haptics, alerting the user even inside loud festival environments.

---

Proceed to **[Volume 08: Feature — Offline P2P Chat](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/08_feature_chat.md)**.
