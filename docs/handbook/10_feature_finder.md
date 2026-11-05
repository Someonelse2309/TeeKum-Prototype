# TeeKum Code Handbook — Volume 10: Feature — Precision Finder & Radar (Definitive Deep-Dive)

This volume provides an exhaustive, method-by-method architectural deep-dive into the real-time Tactical Radar, polar-to-Cartesian screen coordinate projections, forward-up relative bearing transforms, Metal GPU rendering acceleration (`.drawingGroup()`), and the crowd visual strobe beacon in TeeKum.

---

## 📑 Included Source Files

1. [`TeeKum Prototype/Features/Finder/Views/Radar/RadarView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarView.swift) (151 lines) — Full tactical radar engine, target selection, and coordinate projection math.
2. [`TeeKum Prototype/Features/Finder/Views/FinderBeaconView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/FinderBeaconView.swift) (394 lines) — Full-screen crowd finder integrating the radar with a multi-color strobe torch.
3. [`TeeKum Prototype/Features/Finder/Views/Radar/RadarTheme.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarTheme.swift) (130 lines) — Geometry thresholds, distance ranges (15m, 30m, 60m), and color schemes.
4. [`TeeKum Prototype/Features/Finder/Views/Radar/RadarGridBackground.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarGridBackground.swift) (150 lines) — Concentric distance rings, crosshairs, and perimeter degree tick marks.
5. [`TeeKum Prototype/Features/Finder/Views/Radar/RadarBlipView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarBlipView.swift) (160 lines) — Peer blip avatar, edge-clamped directional indicator, and selection state.
6. [`TeeKum Prototype/Features/Finder/Views/Radar/RadarCenterMarker.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarCenterMarker.swift) (100 lines) — Center user marker with forward-facing orientation arrow.
7. [`TeeKum Prototype/Features/Finder/Views/Radar/RadarFriendCard.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarFriendCard.swift) (180 lines) — Horizontal HUD card displaying distance and tactical clock bearing.

---

# 1. Coordinate Projection Mathematics: `RadarView.swift`

Standard map coordinates are spherical geographic coordinates (Latitude, Longitude). To render them on a 2D radar screen oriented towards the direction the user is currently holding their phone, the radar performs a **two-stage transformation**:

```
[Geographic Coordinates (Lat, Lon)]
                │
                ▼ (Haversine & Forward Azimuth Formula)
[Absolute Bearing (0°..360°) & Great-Circle Distance (m)]
                │
                ▼ (Minus Hardware Compass Heading)
[Relative Bearing: Forward-Up Angle (0°..360°)]
                │
                ▼ (Polar-to-Cartesian Trigonometric Projection)
[Screen Coordinates (x, y) on Canvas]
```

---

## 1.1 The Forward-Up Relative Bearing Formula

```swift
let absoluteBearing = userLoc.bearing(to: targetCoord)
let heading = currentHeading ?? 0.0

// Forward-Up (Heading-Up) Relative Angle
let relativeAngle = (absoluteBearing - heading + 360.0).truncatingRemainder(dividingBy: 360.0)
```

### Mathematical Explanation
* If Bob is due East ($90^\circ$ absolute bearing) and you are facing East ($90^\circ$ heading):
  $$\text{relativeAngle} = (90 - 90 + 360) \pmod{360} = 0^\circ \quad (\text{Straight Ahead})$$
* If you turn North ($0^\circ$ heading):
  $$\text{relativeAngle} = (90 - 0 + 360) \pmod{360} = 90^\circ \quad (\text{To your Right / 3 o'clock})$$

---

## 1.2 Polar-to-Cartesian Screen Projection & Clamping

```swift
    private func computeBlipPosition(
        for member: Member,
        center: CGPoint,
        radius: CGFloat
    ) -> BlipPosition? {
        guard let userLoc = userLocation, let targetCoord = member.coordinate else { return nil }
        
        let dist = userLoc.distance(to: targetCoord)
        let absoluteBearing = userLoc.bearing(to: targetCoord)
        let heading = currentHeading ?? 0.0
        
        let relativeAngle = (absoluteBearing - heading + 360.0).truncatingRemainder(dividingBy: 360.0)
        let isClamped = dist > theme.maxDisplayRange
        let displayDistance = min(dist, theme.maxDisplayRange)
        
        // Polar to Cartesian conversion
        // In navigation, 0° is North (Up) -> dx = sin(rad), dy = -cos(rad)
        let rad = relativeAngle * .pi / 180.0
        let radialFraction = CGFloat(displayDistance / theme.maxDisplayRange)
        let blipRadius = radius * radialFraction
        
        let dx = sin(rad) * blipRadius
        let dy = -cos(rad) * blipRadius
        
        let point = CGPoint(x: center.x + dx, y: center.y + dy)
        return BlipPosition(point: point, distance: dist, relativeBearing: relativeAngle, isClamped: isClamped)
    }
```

### Coordinate Invariants
1. **Navigation vs Standard Cartesian**: In high-school math, $0^\circ$ is East ($+x$) and increases counter-clockwise ($dx = r \cos \theta, dy = r \sin \theta$). In navigation and radar systems, **$0^\circ$ is North (Straight Up)** and increases clockwise.
2. In iOS screen coordinates, the $y$-axis points **downward**:
   $$dx = r \sin(\theta), \quad dy = -r \cos(\theta)$$
3. **Outer Ring Clamping**: If a friend is 140 meters away (beyond `maxDisplayRange = 60m`), their position is clamped to the outer rim ($r = blipRadius$) and rendered with `RadarBlipView(isClamped: true)`, displaying an outward directional arrow so the user knows which direction to walk.

---

# 2. Metal GPU Acceleration: `.drawingGroup()`

```swift
            ZStack {
                // Background Grid, Rings, Guideline, Center, and Blips...
            }
        }
        .drawingGroup() // Metal hardware acceleration for smooth 60fps heading rotation
```

### Junior Developer Rosetta Stone: Why `.drawingGroup()`?
* The radar contains 3 concentric circular paths, 4 crosshair lines, 12 perimeter angle tick marks, a dashed guideline, and multiple member blips.
* As the user turns their body, Core Location emits heading updates at **60 Hz** (60 times per second).
* Without `.drawingGroup()`, SwiftUI re-evaluates and rasterizes dozens of separate CoreAnimation vector layers every 16 milliseconds, causing CPU thermal throttling and frame drops.
* `.drawingGroup()` instructs SwiftUI to composite all subviews into a single offscreen **Metal GPU render target** (`CAMetalLayer`). Rendering is offloaded directly to the Apple Silicon GPU shader cores, maintaining a locked 60/120 FPS.

---

# 3. Crowd Strobe Torch: `FinderBeaconView.swift`

```swift
    @State private var isStrobeActive: Bool = false
    @State private var strobeColorIndex: Int = 0
    @State private var strobeTask: Task<Void, Never>?
    private let strobeColors: [Color] = [.yellow, .cyan, .green, .white]
    
    private func startStrobe() {
        isStrobeActive = true
        strobeTask?.cancel()
        strobeTask = Task { @MainActor in
            while isStrobeActive {
                try? await Task.sleep(nanoseconds: 80_000_000) // 80ms flash cadence
                guard !Task.isCancelled, isStrobeActive else { break }
                strobeColorIndex = (strobeColorIndex + 1) % strobeColors.count
            }
        }
    }
```

### Real-World Field Utility
* In a massive festival crowd of 50,000 people, GPS has an uncertainty radius of 5–10 meters. Once you are within 10 meters of a friend, you still need to see them visually in the dark.
* Tapping the **Beacon** button activates full-screen maximum brightness strobing across high-contrast neon colors (`yellow`, `cyan`, `green`, `white`) at an 80ms cadence.
* The user holds their iPhone high above their head, providing a physical visual beacon so their friends can spot them across the crowd.

---

Proceed to **[Volume 11: Feature — Group Pairing & Meeting Points](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/11_feature_pairing_and_meeting.md)**.
