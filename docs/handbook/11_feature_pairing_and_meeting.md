# TeeKum Code Handbook — Volume 11: Feature — Group Pairing & Meeting Points

This volume details the serverless rendezvous pairing system, CoreImage QR code generator and AVFoundation scanner, URL fragment cryptographic key exchange, personal neon color-coding, and the single-active meeting point distributed concurrency locking engine in TeeKum.

---

## 📑 Included Files

* **Pairing & Onboarding**:
  * [`TeeKum Prototype/Features/Pairing/ViewModels/GroupSessionViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/ViewModels/GroupSessionViewModel.swift)
  * [`TeeKum Prototype/Features/Pairing/Views/GroupPairingView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/Views/GroupPairingView.swift)
  * [`TeeKum Prototype/Features/Pairing/Views/ColorPickerView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/Views/ColorPickerView.swift)
  * [`TeeKum Prototype/Features/Pairing/Views/MeshAgreementView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/Views/MeshAgreementView.swift)
  * [`TeeKum Prototype/Features/Pairing/Views/QRCodeView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/Views/QRCodeView.swift)
  * [`TeeKum Prototype/Features/Pairing/Views/QRScannerView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/Views/QRScannerView.swift)
* **Meeting Points & Landmarks**:
  * [`TeeKum Prototype/Features/MeetingPoint/ViewModels/MeetingPointViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/MeetingPoint/ViewModels/MeetingPointViewModel.swift)
  * [`TeeKum Prototype/Features/MeetingPoint/Views/MeetingPointsView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/MeetingPoint/Views/MeetingPointsView.swift)
  * [`TeeKum Prototype/Features/MeetingPoint/Views/SetMeetingPointSheet.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/MeetingPoint/Views/SetMeetingPointSheet.swift)
  * [`TeeKum Prototype/Features/MeetingPoint/Views/MeetingPointPinView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/MeetingPoint/Views/MeetingPointPinView.swift)

---

# 1. Serverless Group Pairing: `GroupSessionViewModel.swift`

TeeKum operates without backend authentication databases or cloud user accounts. Group pairing is established using **cryptographic rendezvous**:

```swift
@Observable
@MainActor
public final class GroupSessionViewModel {
    public var activeSession: GroupSession?
    public var members: [Member] = []
    public var localUserName: String = ""
    public var localColor: MemberColor = .unset
```

---

## 1.1 The URL Fragment Key Security Invariant

```swift
    public var inviteURL: URL? {
        activeSession?.inviteURL()
    }
```

```swift
    // Generated URL structure:
    // teekum://join?id=7E3A&name=Festival#dB34...256bitSymmetricKey...
```

* **Why Fragment (`#`)?**:
  * RFC 3986 specifies that the fragment component of a URL is strictly client-side.
  * If a user copies and pastes this link into SMS, WhatsApp, or an email, web servers and intermediate network proxies **never receive the fragment**.
  * The 256-bit symmetric encryption key is transferred directly between physical devices without cloud exposure.

---

## 1.2 Nearest-Neighbor QR Code Generation: `QRCodeView.swift`

```swift
    private func generateQRCode(from url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M" // 15% error correction
        
        guard let outputImage = filter.outputImage else { return nil }
        
        // Scale up using nearest-neighbor interpolation to prevent blur
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
```

### Visual Artifact Prevention
* Default CoreImage scaling uses bilinear interpolation, causing QR code squares to blur and camera scanners to fail.
* Applying an affine matrix transform (`CGAffineTransform(scaleX: 10, y: 10)`) followed by SwiftUI `.interpolation(.none)` produces razor-sharp pixel edges that scan instantly even under dim festival lighting.

---

# 2. Distributed Meeting Point Lock: `MeetingPointViewModel.swift`

Without a central database, if Alice sets a meeting point at *"Main Stage at 10 PM"* and Bob sets a meeting point at *"Food Trucks at 9:30 PM"*, distributed state can rapidly conflict.

`MeetingPointViewModel` enforces an **offline distributed mutex**:

```swift
    /// Evaluates whether member initials are permitted to update or move the rendezvous.
    public func canSetMeetingPoint(by proposerId: String) -> Bool {
        checkExpiration()
        guard let active = activeMeetingPoint, !active.isExpired else {
            // No active rendezvous exists; any group member is free to propose!
            return true
        }
        let sanitized = InitialsCodec.sanitize(proposerId)
        // If an active rendezvous exists, ONLY the original setter is permitted to update it.
        return active.proposerId == sanitized
    }
    
    /// Evaluates whether member initials are permitted to cancel the rendezvous.
    public func canUnsetMeetingPoint(by callerId: String) -> Bool {
        guard let active = activeMeetingPoint else { return false }
        let sanitized = InitialsCodec.sanitize(callerId)
        return active.proposerId == sanitized
    }
```

### Distributed Concurrency Invariants
1. **Single Active Landmark**: There is strictly **ONE** active meeting point per festival group.
2. **Setter Ownership**: Only the friend who originally proposed the landmark (`proposerId`) can move or cancel it.
3. **Auto-Expiration**: Once the target meetup time passes (`Date() > targetTime`), the lock releases automatically, allowing any attendee to set the next rendezvous landmark.

---

# 3. 1-Tap Attendance Synchronization

When an attendee views the active landmark on their map, they tap one of three status buttons:
* **"On My Way"** (`AttendanceStatus.onTheWay`)
* **"I'm Here"** (`AttendanceStatus.arrived`)
* **"Can't Make It"** (`AttendanceStatus.cannotMakeIt`)

```swift
    public func updateAttendanceStatus(_ status: AttendanceStatus) async {
        self.localAttendanceStatus = status
        
        // Broadcasts attendance update packet (Type 0x03) across the mesh
        await broadcastMeetingPointPacket(action: .attendanceUpdate, status: status)
    }
```

* Packed into the 30-byte `MeetingUpdatePayload` and broadcast across up to 15 hops.
* Every member's HUD pin updates to display attendee counts (e.g. *"3 Arrived, 2 On The Way"*).

---

Proceed to **[Volume 12: Feature — Mesh Diagnostics & Simulation](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/12_feature_diagnostics.md)**.
