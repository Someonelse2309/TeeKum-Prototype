# TeeKum Phase 2 — Physical Device Multi-Hop SOS Test Plan

> **Document Version:** 1.0  
> **Status:** APPROVED PHYSICAL TEST PROTOCOL  
> **Target:** Agent 4 (Multi-Hop SOS Delivery & Reliability Specialist)  
> **Target Platform:** iOS 17.0+ Physical iPhones (AWDL / Wi-Fi Direct)  
> **Zero Cloud Dependency:** Verified strictly offline without cellular, internet, or backend servers.

---

## 1. Test Objectives & Hardware Requirements

This document specifies the physical-device verification protocol for **TeeKum Phase 2 Multi-Hop SOS Dispatch and Acknowledgment**.

The primary objective is to prove that an emergency SOS triggered on a distressed device successfully navigates through intermediary relays to an out-of-direct-radio-range group member, emits a return delivery acknowledgment, suppresses duplicate alerts, prevents unauthorized sirens, and honestly conveys delivery states to the distressed user at every stage.

### Hardware & Equipment
1. **Minimum Device Count:** 3 physical iPhones (iPhone A, iPhone B, iPhone C) running iOS 17.0 or newer.
2. **Recommended Device Count:** 5 physical iPhones for multi-relay linear and diamond topology verification.
3. **RF Isolation / Distance Requirements:**
   - Outdoor festival ground, athletic field, or long corridor (> 70 meters), OR
   - RF-attenuation shielding (RF bags / Faraday enclosures / metallic lockers) to simulate radio horizon boundaries where direct AWDL link between Phone A and Phone C cannot be established.
4. **Radio Configuration:**
   - Airplane Mode: **ON** on all devices (cellular data and internet connectivity strictly severed).
   - Wi-Fi: **ON** (AWDL / Wi-Fi Direct active, disconnected from local Wi-Fi routers).
   - Bluetooth: **ON** (for Apple Multipeer / AWDL discovery).
   - Personal Hotspot: **OFF**.

---

## 2. Test Topologies

### Topology 1: Linear 3-Node Relay
```text
[Phone A: Distressed] <---- AWDL (25m) ----> [Phone B: Relay Node] <---- AWDL (25m) ----> [Phone C: Friend Recipient]
(Session 0x4321)                             (Communal Relay: ON)                          (Session 0x4321)
      |                                              |                                            |
      + - - - - - - - - - - - - [No Direct AWDL (> 50m)] - - - - - - - - - - - - - - - - - - - - +
```

### Topology 2: Multi-Hop 4-Node Chain
```text
[Phone A: Distressed] <---> [Phone R1: Relay] <---> [Phone R2: Relay] <---> [Phone C: Friend Recipient]
```

### Topology 3: Diamond Multi-Path Topology
```text
                             +---> [Phone R1: Relay 1] ---+
                             |                            |
[Phone A: Distressed] -------+                            +-------> [Phone C: Friend Recipient]
                             |                            |
                             +---> [Phone R2: Relay 2] ---+
```

---

## 3. Physical Test Matrix

| Test ID | Test Case | Scenario / Configuration | Expected Physical Outcome | Acceptance Criteria |
| :--- | :--- | :--- | :--- | :--- |
| **PHY-SOS-01** | Phase 1 Direct SOS Baseline | Phone A and C directly adjacent (< 5m) on same session | Immediate siren on Phone C; Phone A displays `DELIVERED_TO_FRIEND` (0 hops) in < 200 ms. | Phase 1 regression test clean; no multi-hop overhead penalty. |
| **PHY-SOS-02** | 1-Relay Multi-Hop SOS Delivery | Phone A & C out of range; Phone B acts as intermediary stranger relay | Phone A: `LOCAL_SENDING` -> `RELAY_ACK` (1 hop) -> `DELIVERED_TO_FRIEND` (2 hops). Phone B stays silent. Phone C sounds full siren. | No false sirens on Phone B; honest stage progression on Phone A. |
| **PHY-SOS-03** | 3-Hop Multi-Relay Linear Chain | Phone A -> R1 -> R2 -> Charlie across 75m corridor | Packet hops R1 and R2; `hopCount` arrives as 2 at Charlie; ACK returns to Alice; Alice HUD displays `lastDeliveredHopCount == 3`. | Bounded hop limit enforced; full round-trip ACK returns across multiple relays. |
| **PHY-SOS-04** | Out-of-Range Friend / Relay-Only Delivery | Charlie turned off; Alice triggers SOS via Relay B | Phone A transitions to `RELAY_ACK`; retries 3 times; stays on `RELAY_ACK` without claiming friend delivery. | UI NEVER claims `DELIVERED_TO_FRIEND` without friend's authenticated MAC. |
| **PHY-SOS-05** | Relay Disconnect Mid-Flight | Relay B powered off during Alice's dispatch | Alice detects link drop; attempts bounded flooding; transitions honestly to `SEARCHING_PEERS`. | No frozen UI; clear indication of searching for reachable peers. |
| **PHY-SOS-06** | Diamond Topology Duplicate Suppression | Alice sends SOS; forwarded simultaneously by R1 and R2 | Charlie receives packet twice; siren triggers on FIRST packet; duplicate is dropped; ACK returned; `duplicatesSuppressed` +1. | Zero duplicate siren loops or repeated audio alerts on recipient. |
| **PHY-SOS-07** | Unauthorized Stranger & Tamper Rejection | Stranger device D (different group key) injects SOS packet | Charlie rejects packet at Poly1305 authentication stage; 0 sirens triggered; 0 state mutations. | Zero unauthenticated sirens under adversarial or stranger presence. |
| **PHY-SOS-08** | Urgent Lane Priority Under Congestion | Relay B flooded with 2 pkts/sec location traffic | Emergency SOS packet bypasses ordinary outbox queue; forwarded immediately on urgent lane. | Emergency SOS latency < 500 ms despite active background congestion. |
| **PHY-SOS-09** | Relay Battery Cutoff Guardrail (<20%) | Relay B drops below 20% battery or enables Low Power Mode | Communal relaying auto-disables; Alice falls back to bounded flooding; UI informs user. | Battery safety guarantees preserved on volunteer relay devices. |
| **PHY-SOS-10** | 3-Second Hold Gesture Ergonomics | Press and hold SOS button on Phone A | Haptic rumble ramps over 3.0s; releasing before 3.0s cancels dispatch; holding full 3.0s dispatches immediately. | Zero accidental dispatches; seamless haptic feedback. |

---

## 4. Detailed Step-by-Step Test Procedures

### Procedure 1: 1-Relay Multi-Hop SOS Delivery (PHY-SOS-02)

#### Setup:
1. Configure **iPhone A** (Alice) and **iPhone C** (Charlie) to share Group Session `0x4321` via QR code pairing.
2. Configure **iPhone B** (Bob) as an independent device with Communal Relaying enabled (`Relaying for Festival: ON`), on a different group or no group.
3. Position devices in a line:
   - Alice (0 meters).
   - Bob (25 meters).
   - Charlie (55 meters).
4. Verify on Alice's Diagnostics HUD that Charlie is **NOT** visible in direct peer list (RSSI = 0 or disconnected), while Bob is connected.

#### Execution:
1. On iPhone A, press and hold the red **Emergency SOS** button for exactly 3 seconds until the haptic pulse fires and the emergency banner appears.
2. Observe iPhone A screen:
   - Within 50 ms: Status reads `Broadcasting SOS...` (`LOCAL_SENDING`).
   - Within 150 ms: Status updates to `Relayed by nearby device (1 hop)` (`RELAY_ACK`).
3. Observe iPhone B screen:
   - Phone B's screen does **NOT** present an SOS modal or audio alert.
   - Phone B's Diagnostics HUD increments `Relayed Packets` counter by 1.
4. Observe iPhone C screen:
   - Within 300 ms: iPhone C initiates the full-volume emergency audio siren and continuous haptic pattern.
   - Screen displays Alice's initials (`AL`), GPS distance, and compass vector.
   - Diagnostics HUD shows `Received SOS: 1 hop`.
5. Observe iPhone A screen after iPhone C responds:
   - Within 600 ms: iPhone A transitions to `Delivered to Charlie (2 hops)` (`DELIVERED_TO_FRIEND`).
   - Emergency banner turns solid green with confirmed delivery timestamp.

#### Pass Criteria:
- Phone A transitions: `LOCAL_SENDING` -> `RELAY_ACK` -> `DELIVERED_TO_FRIEND`.
- Phone B remains silent (zero false alarms).
- Total roundtrip latency < 1.0 second.

---

### Procedure 2: Out-of-Range Friend / Honest Relay State (PHY-SOS-04)

#### Setup:
1. iPhone A (Alice) paired with iPhone C (Charlie).
2. iPhone B (Bob) acting as relay in radio contact with Alice.
3. Power down iPhone C or place iPhone C in an RF-shielded Faraday pouch.

#### Execution:
1. On iPhone A, trigger the 3-second SOS hold gesture.
2. Observe iPhone A screen:
   - Status updates from `LOCAL_SENDING` to `RELayed by nearby device (1 hop)`.
   - The UI shows `Waiting for friend confirmation...` with retry counter ticking (`Retry 1/3`, `Retry 2/3`, `Retry 3/3`).
3. Allow the retry budget (3 retries at ~3s intervals) to elapse.
4. Observe iPhone A screen after timeout:
   - State remains honestly at `RELAY_ACK` (acknowledged by relay, unconfirmed by friend).
   - The UI **NEVER** transitions to `DELIVERED_TO_FRIEND`.
   - The UI **NEVER** falls back to `SEARCHING_PEERS` (which would falsely wipe out the knowledge that a relay accepted the packet).

#### Pass Criteria:
- Distressed user is honestly informed that their distress beacon was picked up by a nearby peer, but their friend has not yet confirmed reception.

---

### Procedure 3: Diamond Multi-Path Duplicate Suppression (PHY-SOS-06)

#### Setup:
1. Position 4 devices in diamond topology:
   - iPhone A (Alice) at bottom vertex.
   - iPhone R1 (Relay 1) at left vertex.
   - iPhone R2 (Relay 2) at right vertex.
   - iPhone C (Charlie) at top vertex.
2. Alice is within radio range of R1 and R2, but out of range of Charlie.
3. Charlie is within radio range of R1 and R2.

#### Execution:
1. Trigger SOS on iPhone A.
2. Both R1 and R2 receive Alice's SOS frame and forward it to Charlie within milliseconds of each other.
3. Observe iPhone C (Charlie):
   - Emergency siren triggers immediately upon receiving the first frame.
   - Second frame arrives moments later with identical `(senderPeerId, sequenceNumber, eventId)`.
   - In Diagnostics HUD on iPhone C:
     - `Duplicates Suppressed` increments by 1.
     - Audio siren does NOT stutter, restart, or trigger a second notification.
   - iPhone C emits an authenticated ACK frame back towards Alice.

#### Pass Criteria:
- Only one audible alert and alert banner created on recipient device.
- `duplicatesSuppressed` metric increments reliably.

---

### Procedure 4: Unauthorized Stranger & Anti-Tamper Rejection (PHY-SOS-07)

#### Setup:
1. iPhone C (Charlie) in session `0x4321`.
2. iPhone D (Adversary/Stranger) running modified build or un-paired session `0x9999`.

#### Execution:
1. On iPhone D, trigger an SOS broadcast.
2. Packet arrives over AWDL at iPhone C.
3. Observe iPhone C:
   - `CryptoSecurityService` attempts session decryption and Poly1305 MAC tag validation using session `0x4321` key.
   - Authentication fails (`CryptoError.macMismatch` or `sessionMismatch`).
   - Packet is discarded immediately with zero state mutation.
   - iPhone C produces NO sound, NO haptic pulse, and NO UI change.

#### Pass Criteria:
- Strangers cannot trigger sirens or manipulate emergency state on unrelated devices.

---

### Procedure 5: Urgent Queue Priority Under Heavy Congestion (PHY-SOS-08)

#### Setup:
1. Connect iPhone A to iPhone B (Relay).
2. Configure iPhone A to flood ordinary location pings at maximum rate (saturating the 2 pkts/sec ordinary forwarder queue on iPhone B).

#### Execution:
1. Trigger SOS on iPhone A while location queue is full (16 items queued).
2. Inspect packet dispatch on iPhone B:
   - Urgent SOS datagram is placed in `urgentLane` (capacity 4 pkts/sec).
   - Urgent SOS datagram is dequeued ahead of all 16 queued ordinary location datagrams.
   - Forwarding delay for SOS is < 150 ms.

#### Pass Criteria:
- Emergency SOS bypasses ordinary congestion without packet drop.

---

## 5. Verification Sign-Off Checklist

Before releasing Phase 2 Multi-Hop SOS to production or field trials, all boxes must be verified and checked:

- [ ] **PHY-SOS-01:** Direct peer SOS operates with zero regression (Phase 1 baseline preserved).
- [ ] **PHY-SOS-02:** 1-relay multi-hop SOS roundtrip completes in < 1.0s over physical AWDL links.
- [ ] **PHY-SOS-03:** Multi-hop linear relay (3+ hops) decrements hop limits and increments hop counts accurately.
- [ ] **PHY-SOS-04:** Out-of-range friend cleanly halts at `RELAY_ACK` without overstating delivery.
- [ ] **PHY-SOS-05:** Intermediary relay disconnection transitions honestly to `SEARCHING_PEERS`.
- [ ] **PHY-SOS-06:** Duplicate multi-path packets are suppressed by 5-minute cache; zero repeated sirens.
- [ ] **PHY-SOS-07:** Stranger packets fail MAC verification and trigger zero sirens.
- [ ] **PHY-SOS-08:** Urgent priority lane preempts saturated ordinary location queues.
- [ ] **PHY-SOS-09:** Low battery (<20%) or Low Power Mode safely disables communal relaying.
- [ ] **PHY-SOS-10:** 3-second hold gesture triggers reliably with progressive haptics; cancel-on-release verified.

---

*Verified by Agent 4 — TeeKum Multi-Hop SOS & Reliability Specialist.*
