# TeeKum Phase 2 — Physical Device Mesh Transport & Neighbor Test Instructions

> **Document Version:** 1.0  
> **Status:** APPROVED PHYSICAL TEST PROTOCOL  
> **Target:** Agent 1 (Mesh Transport & Neighbor Management)  
> **Target Platform:** iOS 17.0+ Physical iPhones (AWDL / Wi-Fi Direct)  
> **Zero Cloud Dependency:** Verified strictly offline without internet connectivity.

---

## 1. Test Objective & Equipment Requirements

This document provides step-by-step instructions for physical-device validation of the Phase 2 Mesh Transport layer (`PeerTransportService`, `NeighborTable`, and `ForwardingRateLimiter`).

### Equipment:
- **Minimum Setup:** 2 physical iPhones (iPhone A, iPhone B) running iOS 17.0+.
- **Recommended Multi-Hop Setup:** 3 physical iPhones (iPhone A, iPhone B [Relay], iPhone C).
- **Physical Connectivity:** Wi-Fi and Bluetooth toggled ON in iOS Settings (Airplane Mode with Wi-Fi & BT enabled is recommended to eliminate cellular data contamination).
- **Zero Cloud / Zero Internet:** Personal Hotspot disabled, Wi-Fi routers disconnected. All communication traverses native Apple Wireless Direct Link (AWDL).

---

## 2. Test Cases & Verification Matrix

| Test ID | Title | Scenario | Expected Physical Outcome | Status |
| :--- | :--- | :--- | :--- | :--- |
| **PHY-TR-01** | Direct Neighbor Discovery | iPhone A and B scan on same festival session | Both phones appear in Diagnostics HUD with `state: .connected`, valid RSSI (-40 to -85 dBm), and `isGroup: true`. | Ready |
| **PHY-TR-02** | Stranger Peering (Communal Mesh) | iPhone A (Session `0x1111`), iPhone B (Session `0x2222`) | Phones discover each other over `_teekum._tcp`; appear in Neighbor Table with `isGroup: false`. Radio link established. | Ready |
| **PHY-TR-03** | Blind Opaque Forwarding | 3-Phone Linear Topology: A -> B (Stranger) -> C (A's Group) | Phone B blindly relays A's 54-byte datagram to C; C verifies Poly1305 MAC tag and displays A's pin. `hopCount` incremented to 1. | Ready |
| **PHY-TR-04** | Relay Opt-Out Cancellation | User toggles "Relaying for Festival" OFF on Phone B | Phone B immediately ceases forwarding stranger packets; clears relay outbox; Phone A send reports next-hop failure. | Ready |
| **PHY-TR-05** | Link Disconnection & Recovery | Physical separation or Faraday pouch on Phone B | NWConnection failure detected; Phone B marked `.stale` and removed; upon return, reconnects via exponential backoff. | Ready |
| **PHY-TR-06** | Rate Limiting Budget (2 pkts/sec) | Rapid bursts of ordinary location pings through Phone B | Phone B throttles ordinary traffic at 2 pkts/sec; urgent SOS packets bypass ordinary throttle at 4 pkts/sec. | Ready |

---

## 3. Step-by-Step Test Execution Procedures

### Test 1: Direct Neighbor Discovery & Telemetry (PHY-TR-01)
1. Launch **TeeKum Prototype** on iPhone A and iPhone B.
2. On iPhone A, tap **Create Group** (e.g., session name "Coachella", initials "AL").
3. Display the QR code on iPhone A.
4. On iPhone B, tap **Scan QR Code** and point camera at iPhone A (initials "BO").
5. Both phones join the session.
6. Open the **Diagnostics HUD** on both phones (tap the debug badge in upper-left corner).
7. **Verification Criteria:**
   - Active Peers counter displays `1`.
   - `NeighborTable` lists remote peer with state `connected`.
   - RSSI indicator shows dynamic signal strength (e.g. -45 dBm at 1m, -75 dBm at 15m).
   - Tap **"Ping Direct Peers"** in HUD: Verify round-trip latency (< 25 ms over AWDL).

---

### Test 2: Stranger Peering without Group Key Assumption (PHY-TR-02)
1. Ensure communal relaying is enabled on both phones in Settings/HUD.
2. On iPhone A, create Group **"Stage Left"** (Session ID `0xAAAA`).
3. On iPhone B, create Group **"Camp Oasis"** (Session ID `0xBBBB`).
4. Keep both devices within 10 meters.
5. In the Diagnostics HUD, observe the **Neighbor Registry** section.
6. **Verification Criteria:**
   - iPhone A shows iPhone B in `activeNeighbors` with `isGroupMember = false`.
   - iPhone B shows iPhone A in `activeNeighbors` with `isGroupMember = false`.
   - AWDL socket is in `ready` state without exchanging group keys.
   - Map screen on iPhone A shows **0 friends** (stranger privacy preserved; no friend pins rendered).

---

### Test 3: 3-Device Multi-Hop Blind Forwarding (PHY-TR-03)
```text
[Phone A: Alice (Session 0xBEEF)] ---> [Phone B: Stranger Relay (Session 0x9999)] ---> [Phone C: Bob (Session 0xBEEF)]
```
1. Position the devices in a linear arrangement:
   - Phone A: 0 meters.
   - Phone B: 25 meters from Phone A.
   - Phone C: 50 meters from Phone A (25 meters from Phone B).
   - Ensure Phone A and Phone C are out of direct radio range of one another.
2. Phone A and Phone C share Session `0xBEEF` (via QR barcode pairing).
3. Phone B has an independent stranger session `0x9999` with communal relaying active.
4. On Phone A, trigger an SOS alert (press and hold SOS button for 3 seconds).
5. **Verification Criteria:**
   - **Phone A:** Transition from `LOCAL_SENDING` to `RELAY_ACK` (Phone B acknowledged receipt).
   - **Phone B:** Relays packet blindly to Phone C. Phone B's screen does **NOT** sound the emergency siren (stranger packets do not trigger sirens on relays). Phone B HUD counter `packetsRelayed` increments by 1.
   - **Phone C:** Successfully receives packet, authenticates Poly1305 MAC tag, and sounds the emergency siren with Alice's initials and coordinate pin!
   - Inspect raw envelope at Phone C: `hopCount == 1`.

---

### Test 4: Relay Opt-Out Cancellation & Queue Purge (PHY-TR-04)
1. In the 3-device setup above, navigate to Phone B's Lock Screen or Diagnostics HUD.
2. Toggle **"Communal Mesh Relaying"** to **OFF**.
3. On Phone A, trigger another location ping or test packet targeted at Phone C via Phone B.
4. **Verification Criteria:**
   - Phone B immediately rejects forwarding with `TransportError.relayDisabled`.
   - Phone B's `strangerRelayLane` queue drops to 0 packets immediately.
   - Phone B does not emit radio frames for Phone A's packets.
   - Toggle relay back to **ON**: Normal forwarding resumes immediately.

---

### Test 5: Sudden Link Disconnection & Reconnection (PHY-TR-05)
1. Connect Phone A and Phone B in a direct peer link.
2. Place Phone B inside an RF attenuation pouch (or walk 60+ meters away until AWDL drops).
3. Observe Phone A's Diagnostics HUD.
4. **Verification Criteria:**
   - Within 5 seconds, NWConnection state transitions to `.waiting` or `.failed`.
   - Phone A's `NeighborTable` marks Phone B as `.stale` and then removes Phone B.
   - `SendOutcome` for any packet sent to Phone B returns `.peerNotFound("BO")` and is reported to the caller.
5. Remove Phone B from the pouch / bring back to 2 meters range.
6. **Verification Criteria:**
   - Exponential backoff reconnection triggers (1.0s, 2.0s, 4.0s).
   - Link re-establishes cleanly; Phone B returns to `state: .connected`.

---

### Test 6: Rate Limiting & Congestion Backpressure (PHY-TR-06)
1. Connect Phone A to Stranger Relay Phone B.
2. From Phone A's Diagnostics HUD, run the rapid packet burst test (submitting 10 packets in 1 second).
3. Observe Phone B's forwarding rate limiter.
4. **Verification Criteria:**
   - Phone B forwards the first 4 tokens (burst capacity).
   - Subsequent ordinary packets are throttled to 2 packets/second.
   - Inject an urgent SOS packet during the ordinary throttle: Verify SOS packet is forwarded **immediately** via the dedicated priority token reserve (4 pkts/sec) without waiting for ordinary token refill!

---

## 4. Physical Testing Sign-Off Status

- **Unit & In-Memory Multi-Peer Simulation Status:** 13/13 passing (100% automated simulator pass rate).
- **Physical Device Validation Status:** Pending 3-device venue field test execution following the protocol above.
