# Chat relay and store–carry–forward

The production `PeerTransportService` now keeps up to 256 encrypted chat/ACK frames in memory for the active session. Sending without any ready peers still takes custody. Authenticated group chat and ACK packets are retained by `PacketRouter` before immediate forwarding; foreign packets are retained only under the existing communal relay policy, without decrypting them.

A paced worker checks ready connections every 500 ms and submits at most one stored frame through the existing priority outbox, using the ordinary forwarding token budget. Each frame/peer pair is retried no more often than every 30 seconds; a disconnected peer becomes eligible again on reconnect. New peers are automatically eligible. This is bounded replay, not a message-inventory negotiation protocol.

## Delivery behavior

- A → B → C can forward immediately while links exist. The default chat hop limit remains 8 forwarding increments; the original transmission has hop count 0. Delivery at the final permitted hop is allowed; further forwarding is not.
- If C is absent, B retains the encrypted frame. When B later meets C, it forwards it without needing A nearby.
- ACKs also take custody, so confirmation can travel back in a later encounter. Only a recipient ACK marks delivery; transport submission does not.
- The existing 15-second ACK timeout ends rapid sender retries. UI now labels this **Unconfirmed**, because carry can still deliver later. A late ACK updates a retained outgoing history item.
- Retry copies preserve ciphertext, authentication tag, and the already-incremented hop count. Duplicate custody does not refresh the expiry or reset hops.
- Group chat is accepted only within 10 minutes of its authenticated timestamp (device clocks should agree). Each carrier retains a frame for at most 10 minutes from first custody; foreign relays cannot inspect the encrypted timestamp. Frames may be evicted earlier at capacity.
- Location and SOS alerts are not carried as stale updates. ACK packets use the shared ACK format and can include acknowledgements for other features.
- Carry replay pauses below 20% battery or in Low Power Mode. Disabling communal relay purges foreign custody; own-group communication remains independent of that opt-in.
- Leaving/changing sessions, stopping the transport, or process termination clears custody. There is no disk persistence. iOS suspension pauses execution; this implementation does not promise continuous background relay.
- Every intermediary must run TeeKum with an active transport. No distance in meters is enforced or guaranteed. Delivery depends on radio encounters, hop budget, expiry, queue capacity, and device availability.

## Changed components

| Component | Responsibility |
|---|---|
| `Core/Transport/CarryMessageStore.swift` | Bounded ciphertext custody, expiry, per-peer retry scheduling |
| `Core/Transport/PeerTransportService.swift` | Capture outbound frames, retain inbound relay copies, replay to ready links, lifecycle/policy cleanup |
| `Core/Messaging/PacketRouter.swift` | Authenticate group custody and approve stranger custody |
| `Features/Chat/Services/ChatMessageEngine.swift` | Final-hop delivery, timestamp validation, authentication before dedup |
| `Core/Messaging/Models/CleartextEnvelope.swift` | Reject hop limits beyond protocol maximum |
| `App/TeeKumApp.swift` | Propagate battery state to carry replay |
| Chat model and message bubble | Honest unconfirmed-delivery wording |

## Verification

Run `bash scripts/test-carry.sh` for custody scheduling and bounds. Run `bash scripts/test-chat.sh` for the chat engine suite plus an encrypted A → B, delayed B → C, delayed ACK-return scenario. The host suite explicitly skips the iOS-only SOS ViewModel assertion; that assertion remains in the in-app suite.

Before claiming physical range or reliable venue delivery, use three iPhones on the same build:

1. Keep the apps active and join the same group. Put A near B and C out of range of both. Send from A and verify B receives.
2. Disconnect A from the test (disable its radios), then bring B near C within ten minutes. Verify C receives the original message exactly once.
3. Bring B back near A. Verify the delayed recipient ACK updates A's message.
4. Repeat with A initially alone, connecting B only after the initial ACK timeout.
5. Repeat with a continuous chain where endpoints cannot communicate directly; check duplicate suppression and final-hop delivery.
6. Check foreign-session relays with communal relay enabled, then disable it and confirm retained foreign frames stop forwarding.
7. Verify expiry, low battery/Low Power Mode, leaving the group, and app termination. Confirm old location/SOS alerts are not resurrected.

The fixed wire protocol and pre-existing identity/key scheme are unchanged. This change does not establish a production security guarantee or guaranteed end-to-end delivery.
