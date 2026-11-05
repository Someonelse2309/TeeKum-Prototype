# TeeKum Code Handbook — Volume 09: Feature — Main Map & Spatial Awareness

This volume examines the primary MapKit SwiftUI spatial interface, custom directional friend pins, $52^\circ$ vision cone shapes, live sharing toggle controls, friend detail sheets, and communal relay configuration modals in TeeKum.

---

## 📑 Included Files

1. [`TeeKum Prototype/Features/Map/ViewModels/MapViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/ViewModels/MapViewModel.swift) — Presentation ViewModel managing live sharing state, status pills, and heading streams.
2. [`TeeKum Prototype/Features/Map/Views/MainMapView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/MainMapView.swift) — Main MapKit canvas rendering friend annotations, meeting point pins, and floating action buttons.
3. [`TeeKum Prototype/Features/Map/Views/FriendPinAnnotationView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/FriendPinAnnotationView.swift) — Custom friend pin avatar with initials, neon outline, and heading pointer.
4. [`TeeKum Prototype/Features/Map/Views/HeadingVisionCone.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/HeadingVisionCone.swift) — Geometric $52^\circ$ field-of-view radial gradient wedge.
5. [`TeeKum Prototype/Features/Map/Views/FriendDetailView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/FriendDetailView.swift) — Telemetry inspector displaying friend distance, battery, signal RSSI, and age.
6. [`TeeKum Prototype/Features/Map/Views/RelaySettingsSheet.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Map/Views/RelaySettingsSheet.swift) — Opt-in modal governing communal packet forwarding and battery cutoffs.

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
    
    public var selectedMember: Member?
    public var currentHeading: CLLocationDirection?
```

### Architectural Highlights
* **Weak Capture**: `service.onHeadingUpdate = { [weak self] heading in self?.currentHeading = heading }` ensures that hardware heading updates cannot cause memory retain cycles between `LocationService` and `MapViewModel`.
* **Two-Way Toggle Sync**: Changing `isLiveSharingEnabled` immediately pauses radio publication at the `LocationService` hardware layer.

---

# 2. Vision Cone Geometry: `HeadingVisionCone.swift`

When looking at a map, knowing which direction a friend is facing is essential for finding them in a crowded festival crowd.

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

### Trigonometric Precision
* Generates a circular wedge centered at $(midX, midY)$.
* Applying a `RadialGradient` creates an intuitive "flashlight beam" effect pointing in the exact compass heading reported by the remote friend's phone over the mesh.

---

# 3. Friend Map Pin: `FriendPinAnnotationView.swift`

```swift
public struct FriendPinAnnotationView: View {
    public let member: Member
    
    public var body: some View {
        let isStale = member.isStale()
        let isEmergency = member.isEmergency
        let memberColor = member.color.swiftUIColor
        let pinAccentColor = isEmergency ? Color.red : (isStale ? memberColor.opacity(0.6) : memberColor)
```

### Visual State Mapping
* **Emergency Active**: Overrides user color with high-visibility **Pulsing Pure Red** (`Color.red`) and adds a double ring track.
* **Fresh Connection**: Displays personal neon color with sharp outline and active directional heading cone.
* **Stale Fix (>30s)**: Dims opacity to 0.6 and displays a relative age badge (e.g., *"45s ago"*), preventing users from navigating toward outdated coordinates.

---

# 4. Communal Mesh Relay Control: `RelaySettingsSheet.swift`

```swift
public struct RelaySettingsSheet: View {
    @State private var selectedMode: RelayParticipationMode = .disabled
    
    // Modes:
    // 1. .communalRelayActive (Always active forwarding)
    // 2. .timedParticipation (30-minute volunteer session)
    // 3. .disabled (Forwarding turned off)
```

### User Sovereignty Guarantee
* Users are never forced to relay packets. The settings sheet allows choosing between permanent participation, a timed 30-minute festival volunteer mode, or turning relaying off completely.
* Prominently displays the device battery level and automatically disables forwarding if battery drops below 20%.

---

Proceed to **[Volume 10: Feature — Precision Finder & Radar](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/10_feature_finder.md)**.
