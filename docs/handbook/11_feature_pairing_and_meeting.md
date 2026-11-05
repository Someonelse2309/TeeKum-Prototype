# TeeKum Code Handbook — Volume 11: Feature — Group Pairing & Meeting Points

This volume provides an exhaustive, line-by-line architectural analysis of TeeKum's serverless group pairing engine, CoreImage QR code synthesis, AVFoundation camera scanning pipeline, RFC 3986 URL fragment cryptographic key exchange, personal neon color-coding, and the distributed single-active rendezvous point concurrency mutex.

---

## 📑 Included Source Files

* **Pairing & Onboarding**:
  * [`TeeKum Prototype/Features/Pairing/ViewModels/GroupSessionViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/ViewModels/GroupSessionViewModel.swift) — 212 lines: Reactive MVVM session lifecycle, 3-letter initials onboarding, and local roster coordinator.
  * [`TeeKum Prototype/Core/Models/GroupSession.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/GroupSession.swift) — 172 lines: Ephemeral session domain model, default auto-mesh derivation, and URL fragment encoder/decoder.
  * [`TeeKum Prototype/Core/Models/GroupSessionInvite.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/GroupSessionInvite.swift) — 21 lines: Decoded invite parameters transfer object.
  * [`TeeKum Prototype/Features/Pairing/Views/QRCodeView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/Views/QRCodeView.swift) — 130 lines: CoreImage affine nearest-neighbor QR barcode renderer and AirDrop share sheet presenter.
  * [`TeeKum Prototype/Features/Pairing/Views/QRScannerView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/Views/QRScannerView.swift) — 438 lines: Native AVFoundation camera capture session, permissions state machine, and simulator fallback.
  * [`TeeKum Prototype/Features/Pairing/Views/GroupPairingView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/Pairing/Views/GroupPairingView.swift) — Onboarding navigation and group creation/joining sheet.
* **Meeting Points & Rendezvous**:
  * [`TeeKum Prototype/Features/MeetingPoint/ViewModels/MeetingPointViewModel.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/MeetingPoint/ViewModels/MeetingPointViewModel.swift) — 326 lines: Distributed single-active rendezvous locking engine, geofenced arrival auto-detection, and mesh broadcaster.
  * [`TeeKum Prototype/Core/Models/MeetingPoint.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Models/MeetingPoint.swift) — 129 lines: Domain entity for rendezvous location, target time, arrival radius, and attendance mapping.
  * [`TeeKum Prototype/Core/Messaging/Payloads/MeetingUpdatePayload.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Core/Messaging/Payloads/MeetingUpdatePayload.swift) — 30-byte binary wire payload serializer/deserializer.
  * [`TeeKum Prototype/Features/MeetingPoint/Views/SetMeetingPointSheet.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/MeetingPoint/Views/SetMeetingPointSheet.swift) — 234 lines: Map long-press bottom sheet with preset chips and custom time picker.
  * [`TeeKum Prototype/Features/MeetingPoint/Views/MeetingPointPinView.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Features/MeetingPoint/Views/MeetingPointPinView.swift) — 50 lines: MapKit neon cyan rendezvous pin annotation with dynamic time countdown.

---

# 1. Serverless Group Pairing State Machine: `GroupSessionViewModel.swift`

TeeKum operates entirely without central servers, cloud user accounts, or SMS authentication gateways. When friends gather in remote music festivals or dense cellular dead zones, pairing must happen instantaneously and securely peer-to-peer.

```swift
@Observable
@MainActor
public final class GroupSessionViewModel {
    public var activeSession: GroupSession?
    public var members: [Member] = []
    public var localUserName: String = ""
    public var localColor: MemberColor = .unset
    public var newGroupName: String = ""
    public var errorMessage: String?
    public var pendingInvite: GroupSessionInvite? = nil
    public var isConnecting: Bool = false
    
    public var hasActiveSession: Bool {
        activeSession != nil
    }
    
    public var keyFingerprint: String? {
        activeSession?.symmetricKeyData.prefix(4).map { String(format: "%02hhx", $0) }.joined()
    }
    
    public var inviteURL: URL? {
        activeSession?.inviteURL()
    }
```

### Line-by-Line Architectural Breakdown
* Lines 13–15 (`@Observable @MainActor public final class GroupSessionViewModel`):
  * Marked `@Observable` to leverage Swift 5.9's Observation macro, registering fine-grained property accessors without `@Published` object-will-change overhead.
  * Isolated to `@MainActor` to guarantee all UI-bound mutations execute strictly on the main runloop, preventing SwiftUI rendering race conditions.
* Lines 17–38 (State Properties):
  * `activeSession`: Holds the currently active `GroupSession` entity containing the 256-bit symmetric encryption key and 16-bit session identifier. `nil` when the user is in an onboarding or unpaired state.
  * `members`: Roster of discovered and verified peer members participating in the active session.
  * `localUserName`: The user's chosen 1-to-3 uppercase letter initials (e.g., `"DNA"`).
  * `localColor`: The user's neon identification color (`MemberColor`) selected during onboarding.
  * `pendingInvite`: Holds an unconfirmed invite when an incoming link or QR code is scanned, awaiting the user's explicit consent to the mesh network agreement before key activation.
* Lines 44–47 (`keyFingerprint`):
  * Extracts the first 4 bytes (`prefix(4)`) of the 32-byte symmetric key and formats them into an 8-character lowercase hexadecimal string (e.g., `"a3f109bc"`).
  * **Zero-Knowledge Security Invariant**: The full 256-bit secret key is never rendered on-screen, logged to os_log, or passed to UI accessibility strings. The 4-byte fingerprint provides sufficient visual entropy for users to compare screens and verify key authenticity without risking shoulder-surfing key compromise.
* Lines 50–52 (`inviteURL`):
  * Dynamically computes the serverless invite URL where the secret key is packed into the URL fragment (`#`).

---

## 1.1 Local Session Persistence & Teardown Lifecycle

```swift
    private static let activeSessionStorageKey = "com.teekum.activeSession"
    private static let localUserNameStorageKey = "com.teekum.localUserName"
    private static let localUserColorStorageKey = "com.teekum.localUserColorCode"
    
    public init(activeSession: GroupSession? = nil) {
        let storedUser = UserDefaults.standard.string(forKey: Self.localUserNameStorageKey) ?? ""
        self.localUserName = storedUser
        
        let storedColorCode = UInt8(UserDefaults.standard.integer(forKey: Self.localUserColorStorageKey))
        self.localColor = MemberColor(rawValue: storedColorCode) ?? .unset
        
        if let activeSession {
            self.activeSession = activeSession
        } else {
            self.activeSession = Self.loadStoredSession()
        }
    }
    
    public func leaveGroup() {
        clearStoredSession()
        self.activeSession = nil
        self.members.removeAll()
        self.errorMessage = nil
        self.isConnecting = false
        Task { @MainActor in
            await LiveActivityManager.shared.endSessionActivity()
        }
    }
```

### Line-by-Line Breakdown
* Lines 58–70 (`init(activeSession:)`):
  * Restores the user's previously configured initials and color code from `UserDefaults`.
  * If no explicit session is injected (standard application launch), loads the persisted session via `loadStoredSession()` JSON decoding. If the app is launched fresh, the user immediately resumes their mesh session without re-pairing.
* Lines 151–160 (`leaveGroup()`):
  * Completely purges the active group session from persistent disk storage via `clearStoredSession()`.
  * Clears memory state: zeroes out `activeSession` and wipes the member roster array `members.removeAll()`.
  * Asynchronously dispatches an ActivityKit lifecycle command: `await LiveActivityManager.shared.endSessionActivity()`, instantly dismissing the iOS Dynamic Island and Lock Screen widget.

---

## 1.2 Festival Auto-Mesh vs. Private Group Creation

TeeKum supports two distinct operational modes:
1. **Public Festival Auto-Mesh**: For zero-setup festivals where strangers and loose acquaintances share an open mesh using a standardized network key.
2. **Private Encrypted Group**: For tight-knit friend groups requiring isolated, cryptographically segregated mesh communication.

```swift
    public func enterAutoMesh(initials: String, colorCode: UInt8? = nil) {
        let cleanInitials = initials.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard InitialsCodec.isValid(cleanInitials) else {
            errorMessage = "Initials must be 1 to 3 uppercase letters (A–Z)."
            return
        }
        
        let color = colorCode ?? localColor.rawValue
        let session = GroupSession(localInitials: cleanInitials, localColorCode: color)
        self.activeSession = session
        self.localUserName = cleanInitials
        self.errorMessage = nil
        saveStoredSession(session)
        UserDefaults.standard.set(cleanInitials, forKey: Self.localUserNameStorageKey)
    }
    
    public func createDraftSession(name: String, localName: String, colorCode: UInt8? = nil) -> GroupSession {
        let cleanInitials = InitialsCodec.sanitize(localName)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = trimmedName.isEmpty ? "Festival Group" : trimmedName
        
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        let keyData = Data(keyBytes)
        
        let color = colorCode ?? localColor.rawValue
        return GroupSession(
            sessionId: UInt16.random(in: 1...UInt16.max),
            sessionName: sessionName,
            symmetricKeyData: keyData,
            localInitials: cleanInitials,
            localColorCode: color,
            isHost: true
        )
    }
```

### Line-by-Line Breakdown
* Lines 84–98 (`enterAutoMesh`):
  * Validates initials using `InitialsCodec.isValid(cleanInitials)` (enforces 1–3 characters from Latin ASCII `A`–`Z`).
  * Instantiates a `GroupSession` with default parameters: `sessionId = 0x7E3A` and `symmetricKeyData = SHA256("TeeKum-Festival-AutoMesh-v2-SecretSeed")`.
  * Instantly saves the session to disk, bringing the node live onto the open festival mesh.
* Lines 101–119 (`createDraftSession`):
  * Pre-allocates a 32-byte array initialized to zeroes: `var keyBytes = [UInt8](repeating: 0, count: 32)`.
  * Calls Apple's Security framework hardware random number generator: `SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)`. This extracts cryptographically secure pseudo-random bytes sourced from the Darwin kernel's `/dev/urandom` and the Apple Secure Enclave hardware entropy source.
  * Generates a non-zero 16-bit random session identifier: `UInt16.random(in: 1...UInt16.max)`.
  * Constructs a draft `GroupSession` with `isHost: true`. This allows the UI to stage and display the QR code before the user commits to activating it.

---

# 2. The RFC 3986 URL Fragment Security Invariant: `GroupSession.swift`

How can a mobile application transmit a 256-bit symmetric encryption key across the internet (e.g., via iMessage, WhatsApp, or email) before the festival starts without leaking the key to cloud servers?

```swift
    public func inviteURL() -> URL {
        var components = URLComponents()
        components.scheme = "teekum"
        components.host = "join"
        
        let keyBase64 = symmetricKeyData.base64EncodedString()
        let sidHex = String(format: "%04X", sessionId)
        let safeName = sessionName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Group"
        
        components.percentEncodedFragment = "key=\(keyBase64)&sid=\(sidHex)&name=\(safeName)"
        return components.url ?? URL(string: "teekum://join")!
    }
```

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                   TEEKUM INVITE URL                                    │
│                                                                                        │
│   teekum://join # key=u0LqW7r8T9x...&sid=7E3A&name=Coachella                           │
│   └──┬──┘  └─┬┘ └─────────────────────────┬─────────────────────────┘                  │
│    Scheme   Host                    URL Fragment (#)                                   │
│                                           │                                            │
│                     ┌─────────────────────┴─────────────────────┐                      │
│                     ▼                                           ▼                      │
│            Web Browser / Cloud Proxy                Recipient Device Client            │
│            "Client-Side Only (RFC 3986)"            Extracted & Handled Offline        │
│            NEVER sent across HTTP network           Decodes 256-bit AES/ChaCha Key     │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### Why Fragment (`#`) Instead of Query (`?`)?
* **RFC 3986 Section 3.5 Specification**: The fragment identifier component of a Uniform Resource Identifier (URI) allows indirect identification of a secondary resource by the user agent. The semantics of a fragment identifier are defined strictly by the client-side software.
* **The Zero-Knowledge Network Invariant**:
  1. Standard HTTP/HTTPS network stacks (including Safari, Chrome, intermediate CDN proxies, Cloudflare, and cellular carrier gateways) **strip the fragment identifier** before sending HTTP GET request headers to the server.
  2. If an invite link is hosted on a web domain (e.g. `https://teekum.app/join#key=...`), a remote web server only sees `GET /join`. The 256-bit symmetric key (`key=...`) never touches the remote server's access logs, TLS termination proxies, or cloud analytics databases.
  3. When handled locally by iOS via the custom URL scheme `teekum://join#...`, `UIApplicationDelegate.openURL` passes the full URL string directly into the app sandbox memory space.

---

## 2.1 Resilient Invite URL Extraction from Chat Boilerplate

Users rarely send raw URLs; messaging apps often wrap links with friendly text:
`"Hey! Join my offline concert crew on TeeKum: Sunset Stage teekum://join#key=aW42...&sid=1A2B&name=Sunset"`

`GroupSession.swift` implements resilient regular expression parsing to reliably extract the invite:

```swift
    public static func extractInviteURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Direct URL parse if the string itself is a clean teekum URL
        if let directURL = URL(string: trimmed),
           let scheme = directURL.scheme?.lowercased(),
           scheme == "teekum" {
            return directURL
        }
        
        // Regex extraction to find teekum:// URL inside any arbitrary text
        let pattern = #"(?i)teekum://join[^\s<>"'\(\)\[\]\{\}]+"#
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        
        var rawMatched = String(text[range])
        
        // Trim trailing sentence punctuation if accidentally attached
        let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?")
        while let last = rawMatched.unicodeScalars.last, trailingPunctuation.contains(last) {
            rawMatched.removeLast()
        }
        
        return URL(string: rawMatched)
    }
```

### Line-by-Line Breakdown
* Lines 100–104 (Fast Path): Checks if the input is already a well-formed URL with scheme `"teekum"`. If so, returns immediately without running regex overhead.
* Lines 108–111 (Regex Substring Extraction):
  * Pattern `(?i)teekum://join[^\s<>"'\(\)\[\]\{\}]+`:
    * `(?i)`: Case-insensitive flag (matches `TEEKUM://`, `Teekum://`, etc.).
    * `teekum://join`: Matches the URI scheme and host.
    * `[^\s<>"'\(\)\[\]\{\}]+`: Captures all contiguous characters until encountering whitespace, HTML tags, quotes, or bracket wrappers commonly injected by chat markdown renderers.
* Lines 116–119 (Trailing Punctuation Sanitization):
  * When users type `"Join us at teekum://join#key=...!."`, the trailing punctuation (`.`, `!`, `?`) would otherwise corrupt the Base64 key payload. The loop strips these trailing unicode scalars backwards until a valid token character is reached.

---

## 2.2 Deserialization and Security Validation

```swift
    public static func parseInvite(from url: URL) -> GroupSessionInvite? {
        guard let scheme = url.scheme?.lowercased(), scheme == "teekum" else { return nil }
        let host = (url.host ?? "").lowercased()
        guard host == "join" || url.path.lowercased().contains("join") else { return nil }
        
        let rawPayload = (url.fragment?.isEmpty == false ? url.fragment : url.query) ?? ""
        guard !rawPayload.isEmpty else { return nil }
        
        var keyData: Data?
        var sessionId: UInt16?
        var sessionName: String?
        
        let pairs = rawPayload.split(separator: "&")
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1])
            
            switch key {
            case "key":
                let clean = value.removingPercentEncoding ?? value
                keyData = Data(base64Encoded: clean) ?? Data(base64Encoded: clean.replacingOccurrences(of: " ", with: "+"))
            case "sid":
                let clean = value.removingPercentEncoding ?? value
                sessionId = UInt16(clean, radix: 16) ?? UInt16(clean)
            case "name":
                sessionName = value.removingPercentEncoding ?? value
            default:
                break
            }
        }
        
        guard let validKey = keyData, validKey.count == 32,
              let validSid = sessionId,
              let validName = sessionName else {
            return nil
        }
        
        return GroupSessionInvite(sessionId: validSid, sessionName: validName, keyData: validKey)
    }
```

### Security Validations Enforced
1. **Fallback Payload Extraction**: Accepts parameters in either the URL fragment (`url.fragment`) or query string (`url.query`) for backwards compatibility with legacy web redirects.
2. **Base64 Space-to-Plus Repair**: In HTTP query parameters, plus signs (`+`) can be mutated into spaces (`%20` or `" "`). The parser repairs this: `clean.replacingOccurrences(of: " ", with: "+")`.
3. **Exact Cryptographic Key Length Check**:
   ```swift
   guard let validKey = keyData, validKey.count == 32
   ```
   If the decoded key byte array is not exactly 32 bytes (256 bits), the invite is rejected immediately. This prevents zero-padding attacks or truncated keys from being loaded into ChaCha20-Poly1305.

---

# 3. CoreImage High-Contrast QR Code Synthesis: `QRCodeView.swift`

At night inside crowded festival grounds, phone cameras struggle with low-light focus, lens smudges, and colored strobe lights. A standard blurred QR code will fail to scan.

```swift
public struct QRCodeView: View {
    public let url: URL
    public let title: String
    public let subtitle: String?
    public let keyFingerprint: String?
    
    @State private var qrImage: UIImage?
    
    // ... body definition ...
    
    private func generateQRCode() {
        let string = url.absoluteString
        guard let data = string.data(using: .utf8) else { return }
        
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let output = filter.outputImage else { return }
        
        // Nearest-neighbor scaling for high-contrast crisp pixels
        let targetSize: CGFloat = 432
        let scale = targetSize / output.extent.size.width
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        if let cgImage = context.createCGImage(transformed, from: transformed.extent) {
            self.qrImage = UIImage(cgImage: cgImage)
        }
    }
}
```

```swift
    if let qrImage {
        Image(uiImage: qrImage)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: 216, height: 216)
```

### Optical Engineering Mechanics
1. **Error Correction Level "M"**:
   * CIFilter supports four levels: `L` (7%), `M` (15%), `Q` (25%), `H` (30%).
   * Level `M` recovers from 15% barcode destruction or optical glare while maintaining an optimal module grid density (under 45×45 modules). Level `H` produces overly dense modules that fail on older iPhone lenses at arm's length.
2. **The Bilinear Anti-Aliasing Blurring Trap**:
   * Standard CoreGraphics and UIKit image scaling applies bilinear or bicubic filtering. When a 37×37 module QR bitmap is scaled up to 432×432 pixels on a Retina display, bilinear interpolation blends black module boundaries into gray gradients.
   * `CGAffineTransform(scaleX: scale, y: scale)` applied directly to the vector `CIImage` pipeline scales the coordinate grid before rasterization.
   * In SwiftUI, `.interpolation(.none)` forces the GPU Metal fragment shader to use nearest-neighbor pixel sampling:
     $$\text{Sample}(u, v) = \text{Texel}(\lfloor u \cdot W \rfloor, \lfloor v \cdot H \rfloor)$$
     This guarantees module transitions occur as a binary step function ($0 \rightarrow 1$), maximizing edge contrast for the scanning camera.

---

# 4. Native AVFoundation Camera QR Scanner & Permission Lifecycle: `QRScannerView.swift`

`QRScannerView` manages real-time optical capture using Apple's AVFoundation framework, implementing a three-stage permission flow and a simulator testing fallback.

```swift
public struct QRScannerView: View {
    public let onCodeScanned: (String) -> Void
    public let onCancel: (() -> Void)?
    
    @State private var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var manualLinkInput: String = ""
    @State private var isRequestingPermission: Bool = false
```

```
┌────────────────────────────────────────────────────────────────────────┐
│                    AVAuthorizationStatus Lifecycle                     │
│                                                                        │
│                       [.notDetermined]                                 │
│                              │                                         │
│                 User taps "Enable Camera"                              │
│                              │                                         │
│               AVCaptureDevice.requestAccess()                          │
│                     ┌────────┴────────┐                                │
│                     ▼                 ▼                                │
│               [.authorized]     [.denied / .restricted]                │
│                     │                 │                                │
│             Hardware Active     Direct to iOS Settings                 │
│         AVCaptureSession Starts (UIApplication.openSettingsURLString)  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4.1 AVFoundation Controller Bridge: `AVCaptureScannerRepresentable`

```swift
#if !targetEnvironment(simulator)
struct AVCaptureScannerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        context.coordinator.viewController = controller
        return controller
    }
    
    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
    
    static func dismantleUIViewController(_ uiViewController: ScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }
    
    final class Coordinator: NSObject, ScannerViewControllerDelegate {
        let onCodeScanned: (String) -> Void
        weak var viewController: ScannerViewController?
        private var hasScanned: Bool = false
        
        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }
        
        func didScanCode(_ code: String) {
            guard !hasScanned else { return }
            hasScanned = true
            
            viewController?.stopScanning()
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            onCodeScanned(code)
        }
    }
}
#endif
```

### Architectural Breakdown
* Lines 310–328 (`UIViewControllerRepresentable`):
  * Bridges UIKit's high-performance camera pipeline into SwiftUI without lifecycle memory leaks.
  * `dismantleUIViewController`: Invoked automatically when SwiftUI tears down the view hierarchy, immediately turning off camera hardware and sensor clocks.
* Lines 330–350 (`Coordinator` & One-Shot Debounce Lock):
  * `hasScanned`: An atomic flag ensuring only the first optical recognition frame triggers the callback. Without this gate, a user pointing a camera at a QR code would fire 60 callbacks per second, spawning dozens of duplicate session join requests.
  * Immediately invokes `viewController?.stopScanning()` to freeze the preview feed.
  * Triggers tactile feedback via Apple's Taptic Engine: `UINotificationFeedbackGenerator().notificationOccurred(.success)`.

---

## 4.2 Hardware Capture Session Setup: `ScannerViewController`

```swift
final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: ScannerViewControllerDelegate?
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var metadataOutput: AVCaptureMetadataOutput?
    private let sessionQueue = DispatchQueue(label: "com.teekum.scanner.session")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }
```

### Hardware Threading Invariant
* **Dedicated Serial GCD Queue (`sessionQueue`)**:
  * `AVCaptureSession.startRunning()` and `stopRunning()` are synchronous, blocking system calls that communicate across Mach ports with the iOS camera daemon (`mediaserverd`).
  * If called on the Main Actor, `startRunning()` will block the main thread for 200–500ms, causing UI dropped frames and animation stutter.
  * TeeKum strictly isolates capture session state changes to `sessionQueue.async`.

```swift
    private func setupCamera() {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            return
        }
        
        let metaOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metaOutput) {
            captureSession.addOutput(metaOutput)
            metaOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metaOutput.metadataObjectTypes = [.qr]
            self.metadataOutput = metaOutput
        } else {
            return
        }
        
        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.previewLayer = preview
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else { return }
        delegate?.didScanCode(stringValue)
    }
```

### Line-by-Line Breakdown
* Lines 400–413 (`AVCaptureDeviceInput`): Obtains the default wide-angle video camera and attaches it as an input port to the capture session.
* Lines 415–423 (`AVCaptureMetadataOutput`):
  * Restricts optical parsing exclusively to `[.qr]`. By disabling barcode formats like EAN-13, Code 128, and Aztec, the DSP image recognition pipeline saves CPU cycles and battery power.
  * Dispatches recognition callbacks directly to `DispatchQueue.main` for rapid UI synchronization.

---

# 5. Distributed Rendezvous Concurrency Mutex: `MeetingPointViewModel.swift`

In a peer-to-peer network without a central database, if Alice sets a meeting point at *"Main Stage at 10:00 PM"* and Bob sets a meeting point at *"Ferris Wheel at 9:30 PM"*, state diverges. If multiple points clutter the UI, friends get lost.

TeeKum enforces an **offline distributed single-active mutex** with strict ownership semantics.

```swift
@Observable
@MainActor
public final class MeetingPointViewModel {
    /// Strictly ONE active meeting point per group at any given time.
    public var activeMeetingPoint: MeetingPoint?
    
    /// User attendance response to the current active proposal.
    public var localAttendanceStatus: AttendanceStatus?
    
    public var sessionProvider: (@Sendable () -> GroupSession?)?
    public var cryptoService: CryptoServiceProvider?
    public var transport: PeerTransport?
    
    private var monotonicCounter: UInt32 = 1
```

---

## 5.1 Distributed Concurrency Rules & Ownership Locking

```swift
    public func canSetMeetingPoint(by proposerId: String) -> Bool {
        checkExpiration()
        guard let active = activeMeetingPoint, !active.isExpired else {
            // No active rendezvous exists; any group member is free to propose!
            return true
        }
        let sanitized = InitialsCodec.sanitize(proposerId)
        // If an active rendezvous exists, ONLY the original setter is permitted to update or move it.
        return active.proposerId == sanitized
    }
    
    public func canUnsetMeetingPoint(by callerId: String) -> Bool {
        guard let active = activeMeetingPoint else { return false }
        let sanitized = InitialsCodec.sanitize(callerId)
        return active.proposerId == sanitized
    }
```

```
┌────────────────────────────────────────────────────────────────────────┐
│              Distributed Meeting Point Concurrency Mutex               │
│                                                                        │
│   State A: No Active Rendezvous (or active point is expired)           │
│   ├── Any member (Alice, Bob, Carol) can propose a new meeting point.  │
│                                                                        │
│   State B: Alice proposes "DNA's Meetup @ 10:00 PM"                    │
│   ├── Mutex Lock acquired: Proposer = "DNA"                            │
│   ├── Bob ("BOB") attempts to propose "BOB's Meetup @ 9:30 PM":        │
│   │   └── ❌ BLOCKED by canSetMeetingPoint() (Setter mismatch)        │
│   ├── Carol ("CAR") attempts to cancel the meeting point:              │
│   │   └── ❌ BLOCKED by canUnsetMeetingPoint() (Only setter unsets)    │
│   ├── Alice ("DNA") moves the pin to another coordinate:               │
│   │   └── ✅ PERMITTED (Setter matches active.proposerId)              │
│   └── Clock passes 11:00 PM (1 hour past scheduled meetupTime):        │
│       └── ⏰ Auto-expires! Mutex automatically releases to State A     │
└────────────────────────────────────────────────────────────────────────┘
```

### The Three Concurrency Invariants
1. **Single-Active Mutex**: At any given millisecond, a group can have at most one active meeting point.
2. **Setter Ownership**: Only the member who set the meeting point (`active.proposerId`) is authorized to change its coordinates, change its time, or cancel it over the wire.
3. **Deterministic Auto-Expiration**:
   ```swift
   public var isExpired: Bool {
       Date().timeIntervalSince(meetupTime) > 3600
   }
   ```
   A meeting point remains locked until exactly 1 hour (3600 seconds) after its scheduled `meetupTime`. This prevents orphaned locks if the original setter loses their phone or runs out of battery.

---

## 5.2 Geofenced Arrival Auto-Detection

```swift
    public func checkArrival(userLocation: CLLocationCoordinate2D) {
        checkExpiration()
        guard let point = activeMeetingPoint else { return }
        guard localAttendanceStatus != .atMeetingPoint else { return }
        
        let pointLoc = CLLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
        let userLoc = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let distance = userLoc.distance(from: pointLoc)
        
        if distance <= point.arrivalRadiusMeters {
            let localInitials = sessionProvider?()?.localInitials ?? point.proposerId
            respond(status: .atMeetingPoint, memberId: localInitials)
        }
    }
```

### Line-by-Line Breakdown
* Lines 146–149:
  * Verifies expiration first.
  * If `localAttendanceStatus == .atMeetingPoint`, skips calculation to avoid redundant wire broadcasts.
* Lines 151–153 (`CLLocation.distance`):
  * Computes great-circle surface distance in meters using Apple's WGS84 geodesic ellipsoid model:
    $$s = 2R \arcsin \left( \sqrt{\sin^2\left(\frac{\Delta \phi}{2}\right) + \cos \phi_1 \cos \phi_2 \sin^2\left(\frac{\Delta \lambda}{2}\right)} \right)$$
* Lines 155–158:
  * When `distance <= point.arrivalRadiusMeters` (default: 25.0 meters), automatically triggers `respond(status: .atMeetingPoint)` and broadcasts the arrival update over the mesh network.

---

## 5.3 High-TTL Mesh Wire Broadcast: `broadcastMeetingUpdate`

Meeting updates are critical group events; unlike periodic GPS pings, a meeting proposal must reach friends across the entire festival grounds, even if separated by 10 to 15 relay hops.

```swift
    public func broadcastMeetingUpdate(action: MeetingAction, meetingPoint: MeetingPoint) async {
        guard let session = sessionProvider?(), let cryptoService, let transport else {
            return
        }
        
        let radiusByte = UInt8(min(100, max(5, meetingPoint.arrivalRadiusMeters.rounded())))
        let payload = MeetingUpdatePayload(
            coordinate: meetingPoint.coordinate,
            meetupTime: meetingPoint.meetupTime,
            createdAt: meetingPoint.createdAt,
            action: action,
            attendanceStatus: localAttendanceStatus ?? .attending,
            meetingPointId: meetingPoint.id,
            senderInitials: session.localInitials,
            arrivalRadiusMeters: radiusByte,
            isRightNow: meetingPoint.isRightNow,
            anchorToProposerGPS: meetingPoint.anchorToProposerGPS
        )
        
        let payloadData = payload.serialize()
        let memberSlot = session.memberSlot
        let seq = CleartextEnvelope.makeSequenceNumber(memberSlot: memberSlot, counter: monotonicCounter)
        monotonicCounter &+= 1
        
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .meetingUpdate,
            hopLimit: PacketConstants.meetingPointHopLimit, // Higher TTL: 15 hops instead of 8
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: seq
        )
        
        do {
            let key = SymmetricKey(data: session.symmetricKeyData)
            let sealed = try await cryptoService.seal(payload: payloadData, envelope: envelope, using: key)
            let wirePacket = RawWirePacket(envelope: envelope, ciphertext: sealed.ciphertext, authTag: sealed.authTag)
            let wireData = try wirePacket.toWireData()
            
            // Broadcast packet into urgent priority queue
            try await transport.broadcastPacket(wireData)
        } catch {
            print("[MeetingPointViewModel] Failed to broadcast meeting update: \(error)")
        }
    }
```

### Protocol & Bit Packing Mechanics
* **Extended TTL (`PacketConstants.meetingPointHopLimit = 15`)**:
  * Standard location pings use `hopLimit = 8` to bound RF broadcast noise.
  * Meeting point updates and SOS alerts use `hopLimit = 15`, enabling them to traverse large multi-stage venues.
* **Non-Collision Nonce Construction**:
  * `CleartextEnvelope.makeSequenceNumber(memberSlot: memberSlot, counter: monotonicCounter)`:
    $$\text{seq} = (\text{memberSlot} \ll 24) \mid (\text{counter} \ \& \ \text{0x00FFFFFF})$$
  * Partitions the 32-bit counter space by member slot, mathematically preventing ChaCha20-Poly1305 nonce reuse across group members sharing the symmetric group key.
* **30-Byte Payload Serialization (`MeetingUpdatePayload`)**:
  * Packed into exactly 30 bytes:
    * Bytes 0–3: Latitude fixed-point $\times 10^7$ (`Int32`).
    * Bytes 4–7: Longitude fixed-point $\times 10^7$ (`Int32`).
    * Bytes 8–11: Meetup timestamp (`UInt32` Unix seconds).
    * Bytes 12–15: Created timestamp (`UInt32` Unix seconds).
    * Byte 16: Action opcode (`0x01 = propose`, `0x02 = cancel`, `0x03 = accept`, `0x04 = decline`).
    * Byte 17: Attendance status byte.
    * Bytes 18–21: Meeting point unique ID (`UInt32`).
    * Bytes 22–23: Sender initials radix-27 encoded (`UInt16`).
    * Byte 24: Arrival radius in meters (`UInt8`).
    * Byte 25: Flags (`bit 0 = isRightNow`, `bit 1 = anchorToGPS`).
    * Bytes 26–29: Reserved zero-padding.

---

## 5.4 Inbound Mesh Packet Verification & Mutex Guard

```swift
    @discardableResult
    public func applyInboundUpdate(_ update: MeetingUpdatePayload) -> Bool {
        switch update.action {
        case .propose:
            checkExpiration()
            // Lock rule: If an active unexpired meeting point exists, another person cannot set it before setter unsets it.
            if let existing = activeMeetingPoint, !existing.isExpired {
                guard existing.proposerId == update.senderInitials else {
                    print("[MeetingPointViewModel] Inbound proposal from '\(update.senderInitials)' rejected; active rendezvous locked by setter '\(existing.proposerId)'")
                    return false
                }
            }
            
            let mp = MeetingPoint(
                id: update.meetingPointId,
                coordinate: update.coordinate,
                meetupTime: update.meetupTime,
                createdAt: update.createdAt,
                proposerId: update.senderInitials,
                isRightNow: update.isRightNow,
                anchorToProposerGPS: update.anchorToProposerGPS,
                arrivalRadiusMeters: Double(update.arrivalRadiusMeters),
                attendance: [update.senderInitials: update.attendanceStatus]
            )
            if !mp.isExpired {
                self.activeMeetingPoint = mp
                if let localInitials = sessionProvider?()?.localInitials, update.senderInitials != localInitials {
                    self.localAttendanceStatus = nil
                }
                return true
            }
            return false
            
        case .cancel:
            guard let existing = activeMeetingPoint, existing.id == update.meetingPointId else {
                return false
            }
            // Lock rule: Only the setter who proposed this rendezvous can cancel it over the mesh.
            guard existing.proposerId == update.senderInitials else {
                print("[MeetingPointViewModel] Inbound cancel from '\(update.senderInitials)' rejected; only setter '\(existing.proposerId)' can unset this rendezvous")
                return false
            }
            self.activeMeetingPoint = nil
            self.localAttendanceStatus = nil
            return true
            
        case .accept, .decline:
            if var mp = activeMeetingPoint, mp.id == update.meetingPointId {
                mp.attendance[update.senderInitials] = update.attendanceStatus
                self.activeMeetingPoint = mp
                if let localInitials = sessionProvider?()?.localInitials, update.senderInitials == localInitials {
                    self.localAttendanceStatus = update.attendanceStatus
                }
                return true
            }
            return false
        }
    }
```

### Distributed Defense Invariants
* **Hijacking Rejection (`.propose`)**: If Mallory broadcasts a rogue rendezvous proposal packet, the node inspects `existing.proposerId`. If an unexpired rendezvous is already active from Alice, Mallory's packet is dropped silently.
* **Rogue Cancellation Rejection (`.cancel`)**: Even if a packet is cryptographically authenticated under the shared group key, only the sender whose initials match `existing.proposerId` can unset the point.
* **Attendance Consensus (`.accept`, `.decline`)**: Attendance status maps are updated in-place keyed by member initials (`update.senderInitials`), guaranteeing consensus without race conditions.

---

# 6. MapKit Presentation: `SetMeetingPointSheet.swift` & `MeetingPointPinView.swift`

## 6.1 Preset Rendezvous Timing: `SetMeetingPointSheet.swift`

When a user long-presses on the festival map, `SetMeetingPointSheet` presents quick-selection chips:

```swift
public enum MeetingTimePreset: String, CaseIterable, Identifiable {
    case rightNow = "Right Now"
    case in15Minutes = "In 15m"
    case in30Minutes = "In 30m"
    case in1Hour = "In 1h"
    
    public var id: String { rawValue }
    
    public func targetDate(from base: Date = Date()) -> Date {
        switch self {
        case .rightNow:
            return base
        case .in15Minutes:
            return base.addingTimeInterval(15 * 60)
        case .in30Minutes:
            return base.addingTimeInterval(30 * 60)
        case .in1Hour:
            return base.addingTimeInterval(60 * 60)
        }
    }
}
```

```swift
    if isLocked {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2.bold())
                .foregroundStyle(.yellow)
            Text(lockReason ?? "Rendezvous is locked by the setter.")
                .font(.caption.bold())
                .foregroundStyle(.yellow)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.yellow.opacity(0.15))
        .clipShape(Capsule())
    }
```

* **Visual Lock Guard**: If another user currently holds the meeting point mutex, the sheet surfaces a yellow lock indicator explaining that only the setter can move the pin, disabling the confirm button.

---

## 6.2 MapKit Rendezvous Pin Annotation: `MeetingPointPinView.swift`

```swift
public struct MeetingPointPinView: View {
    public let meetingPoint: MeetingPoint
    
    public var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.20))
                    .frame(width: 42, height: 42)
                Circle()
                    .stroke(Color(red: 0.0, green: 0.85, blue: 1.0), lineWidth: 2)
                    .frame(width: 42, height: 42)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
            }
            .shadow(color: Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.55), radius: 6)
            
            VStack(spacing: 1) {
                Text(meetingPoint.title)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(meetingPoint.timeDescription)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.85))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.4), lineWidth: 1)
            )
        }
    }
}
```

### Visual Ergonomics
* **Electric Cyan Palette (`#00D9FF`)**:
  * Distinct from green peer friend dots, yellow SOS markers, and white basemap annotations.
  * The 42pt outer halo pulse with a 6pt glow shadow provides clear visibility over dark satellite imagery.
* **Dynamic Time Countdown**:
  * Formats target time dynamically (e.g. `"DNA's Meetup • 10:30 PM (in 15m)"` or `"Right Now"`).
  * Rendered inside an ultra-dense 85% opacity black capsule overlay to maintain legibility regardless of underlying MapKit imagery.

---

# 7. Edge Cases & Failure Recovery Matrix

| Failure Mode | Root Cause / Trigger | Concurrency / System Impact | TeeKum Recovery Mechanism |
| :--- | :--- | :--- | :--- |
| **Camera Permission Denied** | User tapped "Don't Allow" on system camera prompt. | AVFoundation capture fails; unable to scan QR codes. | Displays `permissionDeniedView` with 1-tap deep link to `UIApplication.openSettingsURLString` and provides manual paste link field. |
| **QR Glare / Low Contrast** | Stage floodlights or low-light phone screens wash out camera sensor. | Image processing pipeline cannot isolate QR markers. | CoreImage generation uses level `"M"` error correction with nearest-neighbor scaling; UI recommends pasting invite link as fallback. |
| **URL Base64 Mutation** | Messaging app converts `+` to spaces or percent-encodes URI characters. | Base64 key payload fails decoding; key length $\ne 32$ bytes. | `GroupSession.parseInvite` automatically replaces spaces with `+` and un-encodes percent escapes before decoding. |
| **Concurrent Rendezvous Collision** | Alice and Bob propose different meeting points at the exact same second. | Race condition in distributed state across partitioned mesh. | Deterministic tie-breaker: first valid packet received locks the mutex. Conflicting proposals are rejected until expiration. |
| **Orphaned Mutex Lock** | Setter proposes a meeting point and their phone battery dies or leaves mesh. | Group members blocked from setting a new meeting point. | Strict 1-hour auto-expiration: `Date().timeIntervalSince(meetupTime) > 3600`. Once expired, mutex unlocks automatically. |
| **Rogue Mutex Hijack Attack** | Malicious group member broadcasts a spoofed cancel packet. | Unauthorized peer attempts to cancel someone else's meetup. | `applyInboundUpdate` validates that packet `senderInitials == existing.proposerId`. Unauthorized cancellations are dropped. |
| **Late Joiner Desynchronization** | Member turns on phone 30 minutes after meeting point was set. | Node has no active meeting point in local state. | `MeetingPointViewModel.syncActiveMeetingPointToPeers()` re-broadcasts active proposal upon new peer transport discovery. |

---

Proceed to **[Volume 12: Feature — Mesh Diagnostics & Simulation](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/12_feature_diagnostics.md)**.
