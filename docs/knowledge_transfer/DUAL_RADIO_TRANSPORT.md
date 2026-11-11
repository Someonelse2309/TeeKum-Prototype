# BLE + Apple peer-to-peer Wi-Fi

TeeKum now starts Core Bluetooth alongside the existing Network.framework transport. Both feed the same PacketRouter, chat engine, encrypted 56-byte packet format, hop limits, duplicate suppression, priority outbox and carry store. This stage adds the second radio; it does not implement Wi-Fi Aware, persistent custody, or inventory-based synchronization.

## BLE link

`BLEPeerLink` runs on the main actor and uses Core Bluetooth's main delegate queue. Every phone publishes one service, scans for that service, connects as a central and accepts subscriptions as a peripheral. Writes with response carry traffic from central to peripheral; notifications carry traffic in the reverse direction. The service and characteristic UUIDs are fixed across TeeKum builds.

The codec prefixes each fragment with its offset within the existing frame. Fragment size respects the peer's negotiated write/notification capacity. A receiver rejects missing/out-of-order/oversized fragments; a new offset-zero fragment starts a new frame. Writes wait for completion; notifications wait for Core Bluetooth's readiness callback when its buffer is full. Each link queue is bounded to 256 fragments. Connections/subscriptions are bounded to eight per role.

Bluetooth packets use `ble-p:<UUID>` or `ble-c:<UUID>` link identifiers in diagnostics. Wi-Fi uses its existing peer identifiers. A device can have multiple links, so diagnostic connection counts are **link counts, not unique people**. Member identity still comes from authenticated payloads. BLE links start as unclassified/non-group links in diagnostics. Foreign-message relay still passes through PacketRouter's communal participation policy.

Broadcast packets go over both available transports. A relay can receive via one and send via the other. The existing message identity and dedup suppress repeated chat delivery. The carry worker includes BLE links and can replay retained chat/ACK frames on later encounters. Transport submission is not a recipient delivery receipt.

## iOS settings and lifetime

`Config/Info.plist` contains the Bluetooth usage description and `bluetooth-central` / `bluetooth-peripheral` background modes. Permission is requested when a session starts the managers. Denied/off/unsupported radio states appear in diagnostic events.

Background modes do not guarantee continuous scanning, execution, or delivery. State restoration and disk-backed custody are not implemented in this stage; process termination/session teardown loses the in-memory carry queue. Keep both apps visible for initial tests. Bluetooth fallback does not promise a greater range than Wi-Fi or Android's Coded PHY mode.

## Physical acceptance checks

Install the same new build on all phones and allow Bluetooth permissions.

1. **BLE only:** Turn Wi-Fi off in Settings, leave Bluetooth on, open both apps and join the same group. Wait for `ble-` peers in diagnostics. Send chat both ways; verify final recipient ACK, not just queue acceptance.
2. **Wi-Fi only:** With Bluetooth off, repeat the existing direct Wi-Fi test.
3. **Both radios:** Enable both; send one chat and confirm it appears once. Turn one radio off and check delivery via the remaining radio.
4. **Mixed path:** A has only Bluetooth; B has both; C has only Wi-Fi. Keep A and C unable to link directly. Verify A → B → C and the return ACK.
5. **Carry:** Let A send to B while C is absent. Remove A; bring B to C within ten minutes. Verify delivery, then reconnect B with A to return the ACK.
6. **Reconnect:** Walk out of range and back with apps visible. Check new BLE discovery and resumed carry.
7. **Lifecycle:** Deny Bluetooth, turn it off/on, leave/rejoin a group, and enable Low Power Mode. Verify errors are visible and old session frames are not sent after teardown.

## Automated verification

- `bash scripts/test-carry.sh`: carry scheduling and BLE fragment boundaries, malformed input, incomplete frames and consecutive packets.
- `bash scripts/test-chat.sh`: chat encryption, multi-hop, duplicates, late carry delivery and ACK, retry and battery behavior. The iOS-only SOS ViewModel assertion is explicitly skipped on the Mac host.
- Core transport including BLE can be typechecked on the Mac host. Radio delegates, OS permission dialogs and physical reach still require real iPhones.
