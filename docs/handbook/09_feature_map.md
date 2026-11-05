# TeeKum Code Handbook — Volume 09: Feature — Main Map & Spatial Awareness (Definitive Deep-Dive)

This volume provides an exhaustive, method-by-method architectural deep-dive into the primary MapKit spatial canvas, custom directional friend pins, $52^\circ$ vision cone geometry, live sharing toggle controls, friend detail telemetry inspectors, and communal mesh settings in TeeKum.

---

## 📑 Included Source Files

1. [`TeeKum Prototype/Features/Map/ViewModels/MapViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/ViewModels/MapViewModel.swift) (161 lines) — Presentation ViewModel managing live sharing state, status pills, and heading streams.
2. [`TeeKum Prototype/Features/Map/Views/MainMapView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/MainMapView.swift) (876 lines) — Main MapKit canvas rendering friend annotations, meeting point pins, and floating action palettes.
3. [`TeeKum Prototype/Features/Map/Views/FriendPinAnnotationView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/FriendPinAnnotationView.swift) (118 lines) — Custom friend pin avatar with initials, neon outline, and heading pointer.
4. [`TeeKum Prototype/Features/Map/Views/HeadingVisionCone.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/HeadingVisionCone.swift) (109 lines) — Geometric $52^\circ$ field-of-view radial gradient wedge.
5. [`TeeKum Prototype/Features/Map/Views/FriendDetailView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/FriendDetailView.swift) (351 lines) — Telemetry inspector displaying friend distance, battery, signal RSSI, and age.
6. [`TeeKum Prototype/Features/Map/Views/RelaySettingsSheet.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/RelaySettingsSheet.swift) (407 lines) — Opt-in modal governing communal packet forwarding and battery cutoffs.

---

# 1. Map Presentation Engine: `MapViewModel.swift`

```swift
@Observable
@MainActor
public final class MapViewModel {
    public var locationService: LocationServiceProvider? {
        didSet {
            if let service = locationService {
                self.isLiveSharingEnabled = service.isLiveSharingEnabled
                self.currentHeading = service.currentHeading
                service.onHeadingUpdate = { [weak self] heading in
                    self?.currentHeading = heading
                }
            }
        }
    }
    
    public var isLiveSharingEnabled: Bool = true {
        didSet {
            if let locationService, locationService.isLiveSharingEnabled != isLiveSharingEnabled {
                locationService.isLiveSharingEnabled = isLiveSharingEnabled
            }
        }
    }
```

### Architectural Analysis & Rosetta Stone
* **Weak Capture**: `service.onHeadingUpdate = { [weak self] heading in self?.currentHeading = heading }` ensures that high-frequency hardware heading updates cannot cause memory retain cycles between `LocationService` and `MapViewModel`.
* **Synchronized State**: Mutating `isLiveSharingEnabled` immediately propagates down to `LocationService.isLiveSharingEnabled`, pausing background radio broadcasts.

---

## 1.1 Dynamic Status Pill Messages

```swift
    public var statusPillMessage: String {
        guard let locationService else {
            return isLiveSharingEnabled ? "Live Sharing Active" : "Live Sharing Paused"
        }
        
        let auth = locationService.authorizationStatus
        if auth == .denied || auth == .restricted {
            return "Permission Denied"
        }
        if locationService.isSurvivalModeActive {
            return "Survival Mode (<20%)"
        }
        if !isLiveSharingEnabled {
            return "Live Sharing Paused"
        }
        if locationService.isLocationStale {
            return "GPS Searching..."
        }
        return "Live Sharing Active"
    }
```

* Renders non-intrusive status pills at the top of the map to inform the user of GPS availability and battery survival throttling without modal alerts.

---

# 2. Main MapKit Canvas: `MainMapView.swift`

`MainMapView` (876 lines) serves as the primary operational HUD for attendees:

```swift
public struct MainMapView: View {
    // ViewModels
    @Bindable var mapViewModel: MapViewModel
    @Bindable var sessionViewModel: GroupSessionViewModel
    @Bindable var sosViewModel: SOSViewModel
    @Bindable var meetingPointViewModel: MeetingPointViewModel
    @Bindable var chatViewModel: ChatViewModel
    var relayPolicyManager: RelayPolicyManager?
    var peerTransport: PeerTransportService?
```

---

## 2.1 Floating Action Palette & Gesture Mapping

1. **Top HUD Bar**: Displays active group name, live peer count, and battery indicator.
2. **Right Floating Tools**:
   * **Radar Button**: Opens `FinderBeaconView` for close-range crowd navigation.
   * **Chat Button**: Opens `ChatSheetView` with unread message badge.
   * **Relay Shield**: Displays communal mesh forwarding status and opens `RelaySettingsSheet`.
3. **Bottom Dock**: Prominent 3-second continuous hold emergency SOS button (`SOSButtonView`).
4. **Map Long-Press**: Long-pressing anywhere on the map captures coordinates and opens `SetMeetingPointSheet` to drop a shared landmark.

---

# 3. Vision Cone Geometry: `HeadingVisionCone.swift`

```swift
public struct VisionConeShape: Shape, Sendable {
    public var fovAngle: Double // 50° to 52° field-of-view
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        let startAngle = Angle(degrees: -90.0 - (fovAngle / 2.0))
        let endAngle = Angle(degrees: -90.0 + (fovAngle / 2.0))
        
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
```

```swift
    public var body: some View {
        VisionConeShape(fovAngle: fovAngle)
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        color.opacity(0.40),
                        color.opacity(0.18),
                        color.opacity(0.0)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            .rotationEffect(.degrees(heading))
    }
```

### Trigonometric Construction
* Slices a circular wedge of $52^\circ$ centered at $(midX, midY)$.
* Shifting angles by $-90^\circ$ aligns $0^\circ$ with North (Straight Up).
* The radial gradient creates a soft flashlight beam pointing in the exact compass heading reported by the remote friend's phone over the mesh.

---

# 4. Custom Friend Pin: `FriendPinAnnotationView.swift`

```swift
public struct FriendPinAnnotationView: View {
    public let member: Member
    
    public var body: some View {
        let isStale = member.isStale()
        let isEmergency = member.isEmergency
        let memberColor = member.color.swiftUIColor
        let pinAccentColor = isEmergency ? Color.red : (isStale ? memberColor.opacity(0.6) : memberColor)
```

### State-Driven Rendering
* **Pulsing Pure Red Ring**: If `member.isEmergency == true`, overrides personal colors with Pure Red and animates an expanding ring.
* **Directional Pointer**: If `member.heading` is available, renders `DirectionalHeadingIndicator` showing vision cone and rim arrow.
* **Stale Fix (>30s)**: Dims opacity to 0.6 and displays relative age badge (e.g. *"45s ago"*).

---

# 5. Telemetry Inspector: `FriendDetailView.swift`

Tapping any friend pin presents `FriendDetailView` (351 lines), showing full physical telemetry:
1. **Distance & Bearing**: Displays formatted distance (e.g. *"140 m away"*) and tactical clock direction (*"2 o'clock"*).
2. **Radio Link Quality**: Shows signal strength in dBm (e.g. `"-68 dBm"`) and connection status (Direct 1-Hop Peer vs Multi-Hop Relay).
3. **Freshness & Battery**: Displays battery level percentage and exact seconds since last authenticated packet arrival.

---

# 6. Communal Relay Settings: `RelaySettingsSheet.swift`

```swift
public struct RelaySettingsSheet: View {
    let relayPolicyManager: RelayPolicyManager
    // Participation Modes:
    // 1. .communalRelayActive (Always active forwarding)
    // 2. .timedParticipation (30-minute festival volunteer mode)
    // 3. .disabled (Forwarding off)
```

* **User Sovereignty**: Users explicitly control whether their device participates in stranger packet forwarding.
* **Immediate Drain**: Selecting "Disabled" immediately purges all queued stranger packets from memory and updates Bonjour TXT records to notify neighboring peers.

---

Proceed to **[Volume 10: Feature — Precision Finder & Radar](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/10_feature_finder.md)**.
