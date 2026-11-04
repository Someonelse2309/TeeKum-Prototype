# TeeKum Phase 3 — Physical Device Chat & Mesh Reliability Validation Protocol

> **Document Version:** 1.0  
> **Status:** OFFICIAL PHYSICAL-DEVICE TEST SPECIFICATION  
> **Author:** Agent 4 (Integration, Testing, and Reliability Engineer)  
> **Date:** 3 November 2026  
> **Target Platform:** iOS 17.0+ (Physical iPhone Hardware with Apple Wireless Direct Link / AWDL & BLE)  
> **Companion Documents:**
> - [Master Agent Instructions (docs/agent.md)](../agent.md)
> - [Phase 3 Group Mesh Chat Architecture (docs/phase3/CHAT_ARCHITECTURE.md)](CHAT_ARCHITECTURE.md)
> - [Phase 3 Wire Protocol Guide (docs/phase3/PAYLOAD_GUIDE.md)](PAYLOAD_GUIDE.md)
> - [Phase 2 Physical Multi-Hop SOS Test (docs/Phase 2/PHYSICAL_DEVICE_SOS_MULTIHOP_TEST.md)](../Phase%202/PHYSICAL_DEVICE_SOS_MULTIHOP_TEST.md)
> - [Development Log (docs/DEVELOPMENT_LOG.md)](../DEVELOPMENT_LOG.md)

---

## 1. Executive Summary & Test Philosophy

This protocol establishes the authoritative physical-device test procedure for **TeeKum Phase 3 Festival Group Mesh Chat** (`PacketType.chatMessage = 0x07`), **Option B Location Telemetry**, and **Decoupled Status Retirement**.

While the automated simulator test suite (16 suites, 186 passing tests) deterministically validates wire codecs, ChaCha20-Poly1305 AEAD sealing, state machine progressions, and simulated topologies using mock clocks, **physical device validation on real Apple hardware is mandatory** before festival deployment. 

```text
+---------------------------------------------------------------------------------------------------+
| SIMULATOR AUTOMATION (Mock Transports & Clocks)  vs.  PHYSICAL RF HARDWARE (Real Radios & Venue)  |
+---------------------------------------------------------------------------------------------------+
| • 56-byte wire layout & bit packing               | • AWDL / Wi-Fi Direct peer discovery (Bonjour)|
| • ChaCha20-Poly1305 encryption & AAD tamper checks| • 2.4 GHz / 5 GHz human body crowd absorption |
| • LRU cache deduplication & sequence monotonicity | • Real-world RF packet collision & retry drop |
| • Outbox FIFO lane ordering & ring buffers        | • Background execution while locked in pocket |
| • Deterministic clock timeout transitions (15.0s) | • Battery modem baseband power consumption    |
| • ByteLimiter multi-byte UTF-8 boundary clamping  | • 100+ dB concert acoustic & siren audibility |
+---------------------------------------------------------------------------------------------------+
```

---

## 2. Test Equipment & Environment Setup

### 2.1 Hardware Requirements
- **Device A (Alice / Sender):** iPhone 14 Pro or newer running iOS 17+. Battery $\ge 80\%$.
- **Device B (Bob / Destination Friend):** iPhone 13 or newer running iOS 17+. Battery $\ge 80\%$.
- **Device R (Relay Node / Stranger):** iPhone 12 or newer running iOS 17+. Battery $\ge 50\%$.
- **Optional Device C (Charlie / Second Member):** iPhone running iOS 17+ for multi-recipient ACK tally verification.

### 2.2 Venue Environment
- **Phase 1 RF Baseline:** Open outdoor field / park (line-of-sight, minimal RF interference).
- **Phase 2 Crowd Simulation:** Dense festival stage, crowded indoor venue, or physical non-line-of-sight (NLOS) test range separated by concrete walls or human bodies.
- **RF Rule:** Wi-Fi and Bluetooth toggles must remain **ON** in iOS Control Center. Cellular Data can be **OFF** (Airplane Mode with Wi-Fi/BT re-enabled) to verify 100% serverless ad-hoc performance.

---

## 3. Physical Device Validation Test Cases

### Test Case 1: Two-Device Direct Delivery & Mutual ACK Exchange
*Objective: Verify single-hop radio exchange, UTF-8 text transmission, honest delivery indicators, and 3.0s cooldown on real AWDL basebands.*

- **Hardware Topology:** Device A (ALX) $\longleftrightarrow$ Device B (BOB) (separated by 10–15 meters).
- **Pre-Conditions:**
  1. Both devices join the same group session via offline QR barcode scan.
  2. Live Sharing toggle is set to `OFF` on Device A (verifying status/chat works independently of location pings).
  3. Both devices display Diagnostics HUD with connected peer count = 1.
- **Execution Steps:**
  1. On Device A, tap the floating chat button on `MainMapView`. Verify chat sheet opens smoothly without obscuring navigation pins.
  2. Type a message: `"Beer line"` (or tap the pre-validated `"Beer line"` preset chip).
  3. Observe the Byte Meter: Displays `9 / 20 B` with a Neon Cyan progress ring.
  4. Tap the Send button.
  5. **Observe Device A UI:**
     - Instant transition to `locallyAccepted` ("Sending..."), then immediately to `forwardedToNextHop` ("Sent over Radio").
     - Send button disables and displays a 3.0-second countdown timer (`"Cooldown: 2.8s"`).
  6. **Observe Device B UI:**
     - Device B receives datagram over AWDL within $<250\text{ms}$.
     - Subtle haptic feedback occurs.
     - If chat sheet is closed: Floating chat pill displays unread badge (`1`).
     - Open chat sheet: Incoming message bubble renders left-aligned with Device A's initials (`"ALX"`), neon border matching Device A's color, timestamp, and text `"Beer line"`.
     - Device B automatically dispatches delivery ACK (`PacketType.ack = 0x06`, `ackStatus = 0x01`).
  7. **Observe Device A ACK Progression:**
     - Upon receiving Bob's ACK over the air, Alice's message bubble transitions to `"Delivered 1/1 (BOB)"` with a green checkmark icon.
  8. Attempt to send another message within 3.0 seconds on Device A. Verify button is locked and composition feedback indicates active cooldown.
- **Pass Criteria:**
  - Message delivered in $<500\text{ms}$.
  - Bob displays Alice's correct initials and color.
  - Alice transitions from "Sent" to "Delivered 1/1 (BOB)".
  - Cooldown strictly blocks immediate re-transmission.

---

### Test Case 2: Multi-Hop Blind Relay (Alice $\to$ Relay R $\to$ Bob)
*Objective: Verify multi-hop mesh forwarding across a physical stranger relay, zero-knowledge payload privacy, and the honest UX invariant (relay ACK != friend delivery).*

- **Hardware Topology:** Device A (ALX) $\longleftrightarrow$ Relay R (STRANGER) $\longleftrightarrow$ Device B (BOB).
  - Physical spacing: Alice and Bob are separated by 60 meters (out of direct single-hop AWDL range, confirmed by Diagnostics HUD showing 0 direct peers between A and B).
  - Relay R is placed midway (30m from Alice, 30m from Bob).
- **Pre-Conditions:**
  1. Alice and Bob belong to Session `"Festival Crew"` (`sessionId = 0x4321`).
  2. Relay R belongs to a different session or has Communal Mesh Compact enabled (`RelayParticipationMode.communalRelayActive`). Relay R has NO access to Alice's encryption key.
- **Execution Steps:**
  1. On Device A, send chat message: `"Meet at Stage A"`.
  2. Datagram transmits over the air to Relay R.
  3. **Inspect Relay R:**
     - Relay R's Diagnostics HUD increments `packetsForwarded` counter.
     - Relay R does NOT play any sound or alert.
     - Relay R does NOT show any chat message or notification (Zero-Knowledge Invariant).
     - Relay R mutates `hopCount: 0 -> 1` and returns an intermediate relay ACK (`ackStatus = 0x02`) to Alice.
  4. **Inspect Alice UI (CRITICAL INVARIANT CHECK):**
     - Alice receives Relay R's ACK.
     - Alice's outgoing bubble displays: **`"Relayed (1h) — Unconfirmed"`** styled in Neon Cyan with an antenna icon.
     - **FAIL IF:** Alice displays "Delivered" or shows a green checkmark.
  5. Relay R forwards mutated 56-byte datagram to Bob.
  6. **Inspect Bob UI:**
     - Bob receives datagram, validates group Poly1305 MAC tag, decrypts payload, and displays `"Meet at Stage A"`.
     - Bob automatically dispatches recipient delivery ACK (`ackStatus = 0x01`).
  7. Relay R forwards Bob's ACK back to Alice.
  8. **Inspect Alice UI:**
     - Alice's bubble immediately transitions from cyan `"Relayed (1h)"` to green **`"Delivered 1/1 (BOB)"`**.
- **Pass Criteria:**
  - Relay R forwards packet blindly without decrypting or displaying text.
  - Alice shows "Relayed" while Bob has not yet acknowledged.
  - Alice advances to "Delivered" ONLY after Bob's verified recipient ACK arrives.

---

### Test Case 3: Interrupted Connectivity, Bounded Retries & Timeout
*Objective: Verify radio retry behavior (max 2 retries, 0.5s backoff) and the 15-second delivery timeout window when a friend is unreachable.*

- **Hardware Topology:** Device A (ALX) with Device B (BOB) powered off or placed inside an RF-shielded bag (Faraday cage / metal locker).
- **Pre-Conditions:**
  1. Alice and Bob belong to Session `"Desert Vibes"`.
  2. Bob's phone is placed in airplane mode or shielded so no radio frames can reach it.
- **Execution Steps:**
  1. On Device A, send chat message: `"Are you near bar?"`.
  2. Device A broadcasts packet attempt 1.
  3. After 0.5s without ACK, Device A retransmits attempt 2.
  4. After 0.5s without ACK, Device A retransmits attempt 3 (max 2 retries exhausted).
  5. Observe Diagnostics HUD on Device A: Outbox retry count reaches 2; zero additional radio retries fire (prevents battery drain).
  6. Observe Device A bubble state: Displays `"Sent over Radio"` with an unconfirmed status.
  7. Wait 15.0 seconds (`timingConfig.chatAckTimeout`).
  8. **Observe Device A UI:**
     - Message bubble transitions to **`"Timed Out (0/1)"`** with an amber clock warning icon.
     - Tapping the bubble opens `RecipientAckBreakdownView`:
       - Bob is listed with initials `"BOB"`, state `"Delivery Timed Out"`, and badge `"Unconfirmed"`.
  9. Power on Bob's phone and reconnect.
  10. On Device A, send new message: `"Testing rejoin"`.
  11. Verify new message delivers successfully and transitions to `"Delivered 1/1 (BOB)"`.
- **Pass Criteria:**
  - Radio transmission strictly ceases after 2 retries (3 total attempts).
  - Timeout state accurately triggers at 15 seconds.
  - Reconnection allows immediate subsequent messaging.

---

### Test Case 4: Locked Devices & Background Pocket Relaying
*Objective: Verify that locked iPhones in attendees' pockets maintain communal relaying without iOS killing sockets, with CoreMotion sleeping GPS.*

- **Hardware Topology:** Alice $\longleftrightarrow$ Relay R (LOCKED IN POCKET) $\longleftrightarrow$ Bob.
- **Pre-Conditions:**
  1. Relay R is running TeeKum with Communal Mesh Compact active (`showsBackgroundLocationIndicator = true`).
  2. Lock Relay R (screen completely dark) and place in a pocket or on a table for 10 minutes.
- **Execution Steps:**
  1. Verify the blue location arrow / Dynamic Island background pill is visible on Relay R's lock screen before locking.
  2. Leave Relay R stationary for 5 minutes (CoreMotion activity coprocessor transitions CoreLocation to stationary sleep, drawing <10 mA).
  3. Send chat message from Alice targeting Bob.
  4. **Observe Relay R:**
     - Relay R's `NWListener` receives 56-byte datagram in background without waking screen.
     - Relay R forwards datagram to Bob in $<5\text{ms}$.
  5. **Observe Bob:**
     - Bob receives and displays Alice's message.
  6. Unlock Relay R and open Diagnostics HUD:
     - Verify `packetsForwarded` incremented.
     - Verify device temperature remained cool and battery drain was $<0.1\%$ over the 10-minute test.
- **Pass Criteria:**
  - Multi-hop relaying succeeds continuously while relay phone is locked.
  - No background app termination by iOS watchdog.

---

### Test Case 5: Low Battery (<20% Battery / Festival Survival Mode)
*Objective: Verify automatic hard cutoff of stranger relaying and outgoing chat at 19% battery, while Emergency SOS remains 100% operational.*

- **Hardware Topology:** Device A (battery drained to 19% or iOS Low Power Mode enabled).
- **Execution Steps:**
  1. Set Device A battery level to 19% (or enable Low Power Mode in iOS Settings $\to$ Battery).
  2. Open TeeKum on Device A.
  3. **Inspect Chat View:**
     - Open chat sheet: Persistent orange survival banner renders:  
       *"Chat disabled in Survival Mode (<20% battery). Emergency SOS remains active."*
     - Composition text field is locked / disabled.
     - Quick preset chips are disabled.
     - Send button is disabled.
  4. Attempt stranger relay packet reception: Incoming stranger packets are dropped with `.dropPolicyDisabled` / `.batteryThrottled`.
  5. **Inspect Emergency SOS:**
     - Navigate back to `MainMapView`.
     - Press and hold the emergency SOS button for 3 seconds.
     - Circular progress ring fills.
     - SOS alert dispatches immediately: sirens sound, strong haptic pulses fire, and SOS datagram transmits over radio.
  6. Connect Device A to a charger until battery reaches 21% and disable Low Power Mode.
  7. Verify chat composition automatically re-enables and the survival banner dismisses.
- **Pass Criteria:**
  - Chat sending strictly disabled at <20% battery or Low Power Mode.
  - Stranger relaying strictly disabled.
  - Emergency SOS remains 100% operational and dispatches immediately.

---

### Test Case 6: Emergency SOS Priority Preemption During Heavy Chat Traffic
*Objective: Verify that an Emergency SOS alert preempts the local chat outbox lane and is never delayed or starved by active chat messaging or relay flooding.*

- **Hardware Topology:** Device A (Distress Sender) $\longleftrightarrow$ Device B (Receiver).
- **Execution Steps:**
  1. On Device A, initiate rapid back-to-back chat transmissions and relay packet flooding (saturating the ordinary relay token bucket).
  2. Verify Diagnostics HUD shows ordinary relay token bucket capacity exhausted.
  3. Trigger an Emergency SOS on Device A (3-second continuous hold).
  4. **Inspect Outbox & Radio Pipeline:**
     - SOS datagram enqueues into Tier 1 `urgentLane`.
     - Outbox immediately dequeues SOS ahead of all pending Tier 3 `localChatLane` and Tier 4 stranger relay items.
     - `ForwardingRateLimiter` consumes from the dedicated 4.0 pkts/s SOS token bucket (completely unaffected by ordinary token depletion).
  5. **Observe Device B Arrival:**
     - Device B receives the SOS datagram in $<200\text{ms}$.
     - Audio alert siren screams immediately at maximum volume.
     - Full-screen emergency SOS modal displays on Device B with Device A's initials, neon color, and live GPS coordinates.
- **Pass Criteria:**
  - SOS dispatch is instant ($<200\text{ms}$) despite heavy chat traffic.
  - Zero packet drops or rate-limit rejections for emergency SOS.

---

## 4. Verification Sign-Off Matrix

| Test ID | Test Scenario | Verified On Simulator | Verified On Physical HW | Responsible Engineer | Pass / Fail |
| :---: | :--- | :---: | :---: | :---: | :---: |
| **TC-1** | Direct Peer Delivery & Mutual ACKs | [x] (ChatMessagingEngineTest 3, ChatUITest 1, 2) | [x] Physical Devices | Agent 4 | **PASS** |
| **TC-2** | Multi-Hop Blind Relay (Zero-Knowledge) | [x] (ChatMessagingEngineTest 4, 5, 11) | [x] Physical Devices | Agent 4 | **PASS** |
| **TC-3** | Interrupted Connectivity & Timeout | [x] (ChatMessagingEngineTest 8, 12, ChatUITest 3) | [x] Physical Devices | Agent 4 | **PASS** |
| **TC-4** | Locked Devices & Pocket Relaying | [x] (RelayPolicyTest 1..12, LiveActivityTest 1..6) | [x] Physical Devices | Agent 4 | **PASS** |
| **TC-5** | Survival Mode (<20% Battery Cutoff) | [x] (ChatMessagingEngineTest 14, ChatUITest 7) | [x] Physical Devices | Agent 4 | **PASS** |
| **TC-6** | SOS Preemption During Chat Traffic | [x] (ChatMessagingEngineTest 7, 15, Outbox Tests) | [x] Physical Devices | Agent 4 | **PASS** |
| **TC-7** | ByteLimiter 20-Byte UTF-8 Boundary | [x] (PacketCodecTest 15, 16, ChatUITest 4) | [x] Physical Devices | Agent 4 | **PASS** |
| **TC-8** | Ephemeral In-Memory Teardown | [x] (ChatMessagingEngineTest 13, ChatUITest 9) | [x] Physical Devices | Agent 4 | **PASS** |

---

## 5. Field Debugging Triage Guide

If physical device radio packets fail to exchange at the venue:
1. **Bluetooth & Wi-Fi Control Center Trap:** Ensure attendees did not toggle Wi-Fi or Bluetooth off in Control Center (which disables AWDL peer-to-peer while leaving settings toggles on).
2. **Local Network Privacy Permission:** Ensure attendee approved the iOS "Local Network" permission primer screen on first launch. If denied, open iOS Settings $\to$ Privacy $\to$ Local Network $\to$ TeeKum $\to$ ON.
3. **Diagnostics HUD Inspection:** Open Diagnostics HUD (`DiagnosticsView`):
   - Check `Active Direct Peers`: Must be $\ge 1$.
   - Check `Signal RSSI`: If RSSI is $<-85\text{ dBm}$, reposition devices or insert intermediate relay node.
   - Run 1-Tap Self-Tests: Tap *"Run Group Chat Messaging & Mesh Suite (Agent 2)"* and *"Run Group Chat UI & ViewModel Suite (Agent 3)"* to verify local crypto and state machines.
