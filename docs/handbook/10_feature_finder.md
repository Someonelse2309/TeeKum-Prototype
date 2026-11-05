# TeeKum Code Handbook — Volume 10: Feature — Precision Finder & Radar

This volume breaks down the real-time Tactical Radar, polar-to-Cartesian coordinate projection mathematics, forward-up relative bearing transforms, Metal GPU rendering pipeline (`.drawingGroup()`), and the high-visibility crowd strobe beacon in TeeKum.

---

## 📑 Included Files

1. [`TeeKum Prototype/Features/Finder/Views/Radar/RadarView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarView.swift) — Full tactical radar engine, target selection, and coordinate projection.
2. [`TeeKum Prototype/Features/Finder/Views/FinderBeaconView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/FinderBeaconView.swift) — Full-screen crowd finder integrating the radar with a multi-color strobe torch.
3. [`TeeKum Prototype/Features/Finder/Views/Radar/RadarTheme.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarTheme.swift) — Configuration model for radar geometry, colors, and range thresholds (15m, 30m, 60m).
4. [`TeeKum Prototype/Features/Finder/Views/Radar/RadarGridBackground.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarGridBackground.swift) — Concentric distance rings, crosshairs, and perimeter degree tick marks.
5. [`TeeKum Prototype/Features/Finder/Views/Radar/RadarBlipView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarBlipView.swift) — Peer blip avatar, edge-clamped directional indicator, and selection state.
6. [`TeeKum Prototype/Features/Finder/Views/Radar/RadarCenterMarker.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarCenterMarker.swift) — Pulsing user location marker with forward-facing orientation arrow.
7. [`TeeKum Prototype/Features/Finder/Views/Radar/RadarFriendCard.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Finder/Views/Radar/RadarFriendCard.swift) — Bottom tactile HUD card displaying distance and tactical clock bearing.

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
    let isClamped = dist > theme.maxDisplayRange
    let displayDistance = min(dist, theme.maxDisplayRange)
    
    // Polar to Cartesian conversion
    // 0° is North (Up) -> dx = sin(rad), dy = -cos(rad)
    let rad = relativeAngle * .pi / 180.0
    let radialFraction = CGFloat(displayDistance / theme.maxDisplayRange)
    let blipRadius = radius * radialFraction
    
    let dx = sin(rad) * blipRadius
    let dy = -cos(rad) * blipRadius
    
    let point = CGPoint(x: center.x + dx, y: center.y + dy)
```

### Trigonometric Coordinate System Invariant
* In standard high school geometry, $0^\circ$ is East ($+x$), and angles increase counter-clockwise ($dx = r \cos \theta, dy = r \sin \theta$).
* In aviation and navigation, **$0^\circ$ is North (Straight Up)**, and angles increase clockwise ($0^\circ \dots 360^\circ$).
* In iOS UIKit/SwiftUI screen coordinates, the $y$-axis points **downward**.
* Therefore:
  $$dx = r \sin(\theta), \quad dy = -r \cos(\theta)$$
* **Outer Edge Clamping**: If a friend is 120m away (beyond `maxDisplayRange = 60m`), their position is clamped to the outer rim ($r = blipRadius$) and rendered with an outward-pointing arrow indicator so you still know which direction to walk.

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
    private let strobeColors: [Color] = [.yellow, .cyan, .green, .white]
```

### Real-World Field Utility
* In a massive festival crowd of 50,000 people, GPS has an uncertainty radius of 5–10 meters. Once you are within 10 meters of a friend, you still need to see them visually in the dark.
* Tapping the **Beacon** button activates full-screen maximum brightness strobing across high-contrast neon colors (`yellow`, `cyan`, `green`, `white`).
* The user holds their iPhone high above their head, providing a physical visual beacon so their friends can spot them across the crowd.

---

Proceed to **[Volume 11: Feature — Group Pairing & Meeting Points](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/11_feature_pairing_and_meeting.md)**.
