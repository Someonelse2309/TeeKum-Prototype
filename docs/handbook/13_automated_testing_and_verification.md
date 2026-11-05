# TeeKum Code Handbook — Volume 13: Automated Testing & Verification

This volume details the test engineering architecture, deterministic actor testing patterns, mock radio transports, injected virtual clocks, adversarial threat simulations, and verification suites covering all 18 automated test suites (208 unit and integration tests) in TeeKum.

---

## 📑 Included Test Suites

| Suite Class / Enum | Test Domain | Core Invariant Verified |
| :--- | :--- | :--- |
| [`PacketCodecTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/PacketCodecTests.swift) | Binary Wire Codecs | 56-byte wire layout, 7 payload serializers, Base-27 initials |
| [`PeerTransportTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/PeerTransportTests.swift) | Transport & Framing | `StreamMessageFramer` sliding window, connection tie-breaking |
| [`NeighborDiscoveryTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/NeighborDiscoveryTests.swift) | 1-Hop Neighbor Management | Neighbor health, heartbeats, stale pruning after 6.0s |
| [`RoutingForwardingTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/RoutingForwardingTests.swift) | Blind Relay & Threat Model | 12 security tests: replay attacks, tampering, 4-hop relay |
| [`RouteDiscoveryTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/RouteDiscoveryTests.swift) | Reactive AODV Discovery | RREQ/RREP discovery, reverse route recording, timeouts |
| [`CryptoSecurityTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/CryptoSecurityTests.swift) | Cryptographic Integrity | AEAD ChaCha20-Poly1305, AAD masking, 96-bit nonce derivation |
| [`LocationPublishingTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/LocationPublishingTests.swift) | Positioning & Cadence | Adaptive intervals (4s moving, 20s stationary, 60s survival) |
| [`UIStateTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Features/UIStateTests.swift) | Presentation State | MVVM observation, color pickers, status pills |
| [`SOSEndToEndTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Integration/SOSEndToEndTests.swift) | Emergency SOS Pipeline | 3-second hold gesture, priority dispatch, siren triggering |
| [`MultiHopSOSTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Integration/MultiHopSOSTests.swift) | Multi-Hop Emergency Flooding | Stranger blind relaying of SOS alerts across intermediate nodes |
| [`LiveActivityTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/LiveActivityTests.swift) | ActivityKit Integration | Dynamic Island telemetry, peer counts, and cleanup |
| [`RelayPolicyTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/RelayPolicyTests.swift) | Communal Mesh & Battery | Opt-in modes, timed 30m sessions, 20% battery cutoff |
| [`MeshFailureIntegrationTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Integration/MeshFailureIntegrationTests.swift) | Fault Tolerance & Recovery | Broken link recovery, route re-discovery, packet drops |
| [`MeshDebuggerTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Features/MeshDebuggerTests.swift) | Diagnostic Sniffing | Packet logging, direction filters, manual packet injectors |
| [`ChatMessagingEngineTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Integration/ChatMessagingEngineTests.swift) | P2P Chat Messaging | 20-byte text packing, 5 delivery states, outbox retries |
| [`ChatUITests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Features/ChatUITests.swift) | Chat UI & Byte Meter | ByteMeterView colors (cyan -> amber -> red), preset chips |
| [`InactivityGuardTests.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/Tests/Core/InactivityGuardTests.swift) | Man-Down Detection | Accelerometer stillness, 30s silent countdown, auto-SOS |

---

# 1. The Core Testing Philosophy: Zero Hardware Dependency

Testing physical mesh networks typically requires gathering 5 engineers with physical iPhones and walking across a park. While essential for field validation, physical tests cannot be run on a continuous integration (CI) server.

TeeKum solves this with **dependency injection of abstract primitives**:
1. **`MeshClock`**: Injects a controllable virtual clock (`TestMeshClock`). Tests can advance time by 30 seconds instantly (`clock.advance(by: 30)`) without using fragile, slow `Task.sleep` calls.
2. **`SimulatedMeshTransport`**: In-memory virtual radio transport that routes packets between actors over memory buffers, complete with configurable artificial latency and random packet drop rates (`transport.packetDropRate = 0.30`).

---

# 2. Concurrency Actor Testing Patterns

Testing Swift actors requires careful handling of asynchronous boundaries and reentrancy:

```swift
    // Pattern: Testing actor-isolated state transitions
    let forwarder = PacketForwarder(
        routingTable: routingTable,
        rateLimiter: rateLimiter,
        neighborTable: neighborTable,
        seenPacketCache: seenPacketCache,
        clock: testClock
    )
    
    // Asynchronous invocation within structured TaskGroup
    let decision = await forwarder.evaluateInboundPacket(wireData: packetData, fromPeerId: "PEER_B")
    guard case .dropDuplicate = decision else {
        print("FAIL: Expected duplicate drop, got \(decision)")
        return false
    }
```

---

# 3. Adversarial Threat Model Testing: `RoutingForwardingTests.swift`

`RoutingForwardingTests` verifies that the mesh remains secure even in the presence of malicious or buggy peers:

```swift
    public static func testOutsiderForgedSOSRejection() async -> Bool {
        // An attacker creates an unauthenticated SOS packet with an unknown session ID
        let forgedPacket = createForgedPacket(sessionId: 0xDEAD)
        let decision = await forwarder.evaluateInboundPacket(wireData: forgedPacket, fromPeerId: "ATTACKER")
        
        // Verifies the packet is rejected and group member rosters remain untouched
        guard decision == .dropSecurityVerificationFailed || decision == .dropPolicyDisabled else {
            return false
        }
        return true
    }
```

### Threat Scenarios Verified
1. **Ciphertext Tampering**: Modifying even 1 bit of the encrypted payload causes the 16-byte Poly1305 authentication tag check to fail, dropping the packet immediately.
2. **Replay Attacks**: Capturing a valid packet and re-transmitting it 2 seconds later is instantly suppressed by `SeenPacketCache` and monotonic sequence enforcement.
3. **Hop Limit Tampering**: Forging `hopLimit` to 255 causes immediate rejection because the forwarder clamps limits to `effectiveLimit` (max 15 hops).

---

# 4. Continuous Verification via Environment Flags

In [`TeeKumApp.swift`](file:///Users/nicho/Developer/TeeKum%20Prototype/TeeKum%20Prototype/App/TeeKumApp.swift), the application entry point checks environment variables on launch:

```swift
let envRunner = ProcessInfo.processInfo.environment["TEST_RUNNER"]
let args = ProcessInfo.processInfo.arguments
let shouldExit = args.contains("-exitAfterTests")

if args.contains("-runAllTests") || envRunner == "all" {
    print(">>> RUNNING ALL AUTOMATED TESTS <<<")
    _ = PacketCodecTests.runAllTests()
    _ = PeerTransportTests.runAllTests()
    _ = await NeighborDiscoveryTests.runAllTests()
    _ = await RoutingForwardingTests.runAllTests()
    _ = await RouteDiscoveryTests.runAllTests()
    _ = await CryptoSecurityTests.runAllTests()
    _ = await LocationPublishingTests.runAllTests()
    _ = await UIStateTests.runAllTests()
    _ = await SOSEndToEndTests.runAllTests()
    _ = await MultiHopSOSTests.runAllTests()
    _ = await LiveActivityTests.runAllTests()
    _ = await RelayPolicyTests.runAllTests()
    _ = await MeshFailureIntegrationTests.runAllTests()
    _ = await MeshDebuggerTests.runAllTests()
    _ = await ChatMessagingEngineTests.runAllTests()
    _ = await ChatUITests.runAllTests()
    _ = await InactivityGuardTests.runAllTests()
    print(">>> ALL AUTOMATED TEST RUNS FINISHED <<<")
    if shouldExit {
        exit(0)
    }
}
```

### Running Tests from Command Line
```bash
xcrun simctl launch <SIMULATOR_UUID> com.teekum.prototype -runAllTests -exitAfterTests
```
* Runs all 18 test suites directly in the iOS simulator and outputs pass/fail diagnostics to stdout.

---

Return to **[Volume 00: Master Index & Architecture Blueprint](file:///Users/nicho/Developer/TeeKum%20Prototype/docs/handbook/00_index_and_architecture.md)**.
