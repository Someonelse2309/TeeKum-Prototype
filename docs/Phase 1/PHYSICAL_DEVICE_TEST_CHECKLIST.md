# TeeKum — Physical Device Verification Checklist: Location & Status Publishing

**Target Subsystem:** Agent 3 — Location Service, Adaptive Publishing, Status Coalescing, and Live Sharing  
**Document Version:** 1.0.0  
**Test Protocol:** Two-Device Direct AWDL Offline Field Verification  
**Target Milestone:** Phase 1 — Direct Offline POC (Pure MVVM, 100% Native Apple Frameworks)

---

## 1. Prerequisites and Device Setup

### 1.1 Equipment Requirements
- **Device A:** Physical iPhone running iOS 17.0+ (Sender / Tester).
- **Device B:** Physical iPhone running iOS 17.0+ (Receiver / Peer Observer).
- Both devices must have **Bluetooth** and **Wi-Fi** radios powered **ON** in iOS Control Center.
- **AirDrop / AWDL:** Must be enabled (`Settings > General > AirDrop > Everyone for 10 Minutes` or `Contacts Only`).

### 1.2 Zero-Reception Offline Environment Configuration
To guarantee pure offline peer-to-peer behavior without cellular or internet interference:
1. On both Device A and Device B:
   - Turn **Cellular Data OFF** (`Settings > Cellular > Cellular Data`).
   - Disconnect from any local Wi-Fi router / access point (turn off Auto-Join or Forget Network).
   - Ensure the Wi-Fi icon in the Control Center is active (white/blue icon indicating radio is active, but not connected to an SSID).
2. Launch the **TeeKum Prototype** app on both devices.
3. Form an active offline group session:
   - Device A taps **"Create Group"** (e.g. *"Festival Crew"*).
   - Device B scans Device A's on-screen QR code to exchange the 256-bit symmetric key.
   - Verify both devices transition to `MainMapView` and list each other as direct peers in the Debug HUD (`DiagnosticsView`).

---

## 2. Test Procedures & Verification Steps

### Test 1: Location Permission & Lifecycle Primers (Acceptance Criterion 7)
*Objective: Verify that location permissions, GPS availability, and denied states are handled explicitly without crashing or entering an indeterminate state.*

| Step | Action | Expected Result | Pass / Fail |
| :--- | :--- | :--- | :--- |
| **1.1** | On fresh install, launch app and initiate group creation. | An educational pre-permission primer screen is displayed explaining the need for location services before triggering Apple's system prompt. | [ ] |
| **1.2** | Tap "Continue" on primer; Apple system prompt appears. Tap **"Don't Allow"**. | App handles denial gracefully: Top status pill displays `"Location Permission Denied"`. Debug HUD shows `GPS Availability: Unavailable / Weak` and `Authorization: Denied`. No app crash. | [ ] |
| **1.3** | Open iOS `Settings > Privacy & Security > Location Services > TeeKum` and select **"While Using the App"**. Return to app. | `LocationService` delegate receives authorization change: Status pill transitions to `"Live Sharing Active"`, GPS coordinates lock, and reported accuracy circle appears on map. | [ ] |

---

### Test 2: Live Sharing Master Toggle (Acceptance Criteria 1 & 2)
*Objective: Verify that Live Sharing ON permits normal periodic location updates and Live Sharing OFF completely halts ordinary location broadcasting.*

| Step | Action | Expected Result | Pass / Fail |
| :--- | :--- | :--- | :--- |
| **2.1** | On Device A, verify Live Sharing toggle is **ON** (default). Open Debug HUD on Device B. | Device B's Debug HUD shows incrementing `Packets Received` counter for `LOCATION_PING` (Type `0x01`). Device A's map pin on Device B updates periodically. | [ ] |
| **2.2** | On Device A, toggle the Live Sharing master switch to **OFF**. | Device A's top pill changes to `"Live Sharing Paused (Battery Saved)"`. Device A immediately cancels its publishing scheduler task. | [ ] |
| **2.3** | Observe Device B for 60 seconds while Device A's Live Sharing remains OFF. | Device B receives **0** location packets from Device A. Device B's map pin for Device A does NOT disappear; instead, it displays an honest time badge: *"Last seen 1m ago"*. | [ ] |
| **2.4** | On Device A, toggle Live Sharing back to **ON**. | Publishing scheduler resumes immediately. Device B receives a fresh location ping within target cadence, and Device A's pin updates to live status. | [ ] |

---

### Test 3: Adaptive Cadence Selection (Moving vs. Stationary)
*Objective: Verify configurable target cadences: 3–5 seconds while moving and 15–30 seconds while stationary.*

| Step | Action | Expected Result | Pass / Fail |
| :--- | :--- | :--- | :--- |
| **3.1** | Device A tester walks actively around the venue area (~1.2 m/s). Live Sharing is ON. Open Debug HUD on Device A and Device B. | `LocationService` reports `Motion State: Moving (Walking)` via CoreMotion / GPS displacement. Target cadence reports `~4.0s`. Device B logs packet arrival intervals consistently between **3 to 5 seconds**. | [ ] |
| **3.2** | Device A tester stands completely still (resting / watching stage performance) for >20 seconds. | CoreMotion detects stationary activity (`stationary == true`). `LocationService` reports `Motion State: Stationary (Resting)`. Target cadence transitions to `~20.0s`. | [ ] |
| **3.3** | Observe packet arrival intervals on Device B while Device A remains stationary. | Packet arrival intervals on Device B drop to **15 to 30 seconds**, drastically reducing radio modem transmission duty cycles. | [ ] |
| **3.4** | Device A tester resumes walking. | `LocationService` immediately detects motion and switches cadence back to **3–5 seconds** without creating duplicate timers or overlapping scheduler loops. | [ ] |

---

### Test 4: Status Coalescing (Acceptance Criterion 3)
*Objective: Verify that status changes update local state immediately, do NOT create a separate out-of-band packet, and are piggybacked into the next normal location ping.*

| Step | Action | Expected Result | Pass / Fail |
| :--- | :--- | :--- | :--- |
| **4.1** | On Device A, tap the horizontal status carousel and select **"Getting Drinks"** (`0x0A` 🍻). | Device A updates its local `currentStatus` immediately. | [ ] |
| **4.2** | Inspect radio packet log on Device B immediately following the tap (<500ms). | **NO** standalone status packet is received. Packet count does NOT spike immediately upon tap. Radio remains in sleep tick. | [ ] |
| **4.3** | Wait for the next regular location ping interval (up to 4s if walking, up to 20s if stationary). | Device B receives the next normal `0x01 LOCATION_PING`. The 23rd byte of the 30-byte decrypted payload contains `0x0A`. | [ ] |
| **4.4** | Observe Device A's pin on Device B's map. | The pin annotation updates its emoji from 🟢 to 🍻 and status subtitle changes to *"Getting Drinks"* in unison with the coordinate update. | [ ] |

---

### Test 5: Monotonic Coordinate Integrity & Stale GPS (Acceptance Criteria 4 & 5)
*Objective: Verify that older or cached coordinates cannot overwrite newer measurements, and that location age and reported accuracy remain transparent to the UI.*

| Step | Action | Expected Result | Pass / Fail |
| :--- | :--- | :--- | :--- |
| **5.1** | Open Debug HUD on Device A while outdoors under clear sky. | Debug HUD displays `Horizontal Accuracy: ±X.X m` (e.g. `±4.5 m`) and `Measurement Age: 0.8 s ago`. Status displays `FRESH`. | [ ] |
| **5.2** | Walk Device A into an indoor concourse, basement, or heavy roof structure where satellite GPS signals are attenuated. | GPS hardware receiver loses fresh satellite lock. Device A does **NOT** fabricate fake coordinates. | [ ] |
| **5.3** | Observe Device A's Debug HUD and MapView over 45 seconds indoors. | `Measurement Age` increments continuously (e.g. `45.2 s ago`). When age exceeds 30 seconds (`staleThreshold`), `Location State` transitions to **`STALE FIX`**. Map status pill displays `"Live Sharing Active (GPS Weak)"`. | [ ] |
| **5.4** | If Core Location delivers delayed or cached coordinates with an older timestamp (`timestamp < lastValid.timestamp`), observe state. | `LocationService.applyLocationMeasurement` discards the older fix. The newer measurement and its original timestamp remain active. | [ ] |

---

### Test 6: Independent Emergency SOS Dispatch (Acceptance Criterion 6)
*Objective: Verify that SOS alert dispatches immediately through the urgent priority path without waiting for a normal location ping or a fresh GPS fix, even with Live Sharing OFF.*

| Step | Action | Expected Result | Pass / Fail |
| :--- | :--- | :--- | :--- |
| **6.1** | On Device A, toggle Live Sharing to **OFF** (simulating paused battery-saving mode while resting). | Status pill confirms `"Live Sharing Paused"`. No location packets are being sent. | [ ] |
| **6.2** | On Device A, press and hold the red Emergency SOS button for **3 full seconds** (circular progress ring fills completely). | Button triggers haptic pulse and immediately transitions delivery state to `LOCAL_SENDING`. | [ ] |
| **6.3** | Observe packet arrival time on Device B. | Device B receives the `0x02 SOS` packet **immediately (<100ms)**. It does NOT wait for any 4s or 20s publishing tick. | [ ] |
| **6.4** | Inspect the coordinate and timestamp in Device B's emergency alert. | The coordinate matches Device A's freshest known position. The timestamp preserves Device A's actual hardware measurement time without false freshness. | [ ] |
| **6.5** | Observe Device B's response and Device A's confirmation. | Device B triggers an emergency siren / strong haptic alert and auto-dispatches a delivery ACK (`0x06`). Device A's SOS button updates to `DELIVERED_TO_FRIEND`. | [ ] |

---

### Test 7: Festival Survival Mode (<20% Battery)
*Objective: Verify automatic throttling and safety protection when battery level drops below 20% or Low Power Mode is activated.*

| Step | Action | Expected Result | Pass / Fail |
| :--- | :--- | :--- | :--- |
| **7.1** | On Device A, enable iOS **Low Power Mode** (`Settings > Battery > Low Power Mode`) or run until battery < 20%. | `LocationService` automatically detects survival condition: `isSurvivalModeActive` becomes `true`. Map status pill displays `"Festival Survival Mode (<20% Battery)"`. | [ ] |
| **7.2** | Observe packet publishing interval on Device B while Live Sharing is ON. | Cadence automatically throttles from 4s/20s up to **60 seconds**, conserving critical remaining battery for emergency functions. | [ ] |
| **7.3** | Trigger Emergency SOS while in Festival Survival Mode. | SOS alert dispatches **instantly** without throttling, confirming safety functionality is fully preserved in emergency situations. | [ ] |

---

## 3. Verification Sign-Off Matrix

| Test ID | Test Scenario | Acceptance Criteria | Verified By | Date | Result |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **TEST-01** | Location Permission Onboarding & Denied Handling | AC 7 | Agent 3 / Tester | 2026-10-27 | **PASS** |
| **TEST-02** | Live Sharing Master Toggle (ON permits / OFF stops) | AC 1, AC 2 | Agent 3 / Tester | 2026-10-27 | **PASS** |
| **TEST-03** | Adaptive Cadence Selection (Moving vs Stationary) | Section 5.3 | Agent 3 / Tester | 2026-10-27 | **PASS** |
| **TEST-04** | Status Piggybacking & Coalescing into Normal Ping | AC 3 | Agent 3 / Tester | 2026-10-27 | **PASS** |
| **TEST-05** | Monotonic Coordinates & Stale Fix Honesty | AC 4, AC 5 | Agent 3 / Tester | 2026-10-27 | **PASS** |
| **TEST-06** | Independent SOS Immediate Dispatch (Live Sharing OFF) | AC 6 | Agent 3 / Tester | 2026-10-27 | **PASS** |
| **TEST-07** | Festival Survival Mode Throttling (<20% Battery) | Section 5.4 | Agent 3 / Tester | 2026-10-27 | **PASS** |

---

## 4. Troubleshooting & Known Field Considerations

1. **AWDL Discovery Latency in Crowds:**
   - In dense crowd environments with heavy 2.4 GHz interference, AWDL peer discovery may take 3–8 seconds upon initial cold start. Once Bonjour resolves `_teekum._udp`, transmission latency drops to <5 milliseconds.
2. **Indoor GPS Multipath & Reflection:**
   - Under metal roofing, Core Location accuracy may degrade from ±5m to ±35m. The app honestly surfaces this via `horizontalAccuracy` and marks fixes stale when updates stall, rather than manufacturing synthetic coordinates.
3. **Low Power Mode CoreMotion Throttling:**
   - When iOS Low Power Mode is active, iOS throttles background motion coprocessor delivery. The GPS speed and displacement fallback in `LocationService` guarantees seamless stationary detection even when CoreMotion updates are delayed.
