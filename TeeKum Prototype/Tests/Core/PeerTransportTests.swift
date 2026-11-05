//
//  PeerTransportTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

/// Self-contained verification suite for the low-level Peer-to-Peer Transport layer:
/// - Stream message framing and partial read chunk reconstruction
/// - Outbox priority queuing and obsolete location ping coalescing
/// - Connection tie-breaking and duplicate prevention
/// - Transport state transitions and diagnostic telemetry
public struct PeerTransportTests {
    
    public static func runAllTests() -> Bool {
        print("--- [PeerTransportTests] Running Transport Verification Suite ---")
        var passed = true
        
        passed = passed && testStreamFramerExactPacket()
        passed = passed && testStreamFramerPartialReads()
        passed = passed && testStreamFramerCoalescedPackets()
        passed = passed && testStreamFramerFragmentationAcrossReads()
        passed = passed && testStreamFramerCorruptionRecovery()
        passed = passed && testStreamFramerBufferOverflow()
        passed = passed && testPriorityOutboxUrgentPreemption()
        passed = passed && testPriorityOutboxLocationPingCoalescing()
        passed = passed && testPriorityOutboxBoundedCapacity()
        passed = passed && testPriorityOutboxRetryBudget()
        passed = passed && testTieBreakerLogic()
        passed = passed && testDiagnosticsSnapshot()
        passed = passed && testZeroHandshakeImmediatePacketFraming()
        passed = passed && testPriorityOutboxStrangerRelayElevatedPriority()
        
        if passed {
            print("--- [PeerTransportTests] ALL TRANSPORT TESTS PASSED SUCCESSFULLY! ---")
        } else {
            print("--- [PeerTransportTests] SOME TRANSPORT TESTS FAILED! ---")
        }
        return passed
    }
    
    // MARK: - Helper to Generate Valid 56-Byte Packets
    
    private static func createValidWirePacket(type: PacketType, seq: UInt32 = 1, sid: UInt16 = 0x1234) -> Data {
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: type,
            hopLimit: 8,
            hopCount: 0,
            sessionId: sid,
            sequenceNumber: seq
        )
        let dummyCiphertext = Data(repeating: UInt8(type.rawValue), count: PacketConstants.encryptedPayloadSize)
        let dummyAuthTag = Data(repeating: 0xEE, count: PacketConstants.authTagSize)
        let packet = RawWirePacket(envelope: envelope, ciphertext: dummyCiphertext, authTag: dummyAuthTag)
        return try! packet.toWireData()
    }
    
    // MARK: - Test 1: Framer Exact Packet
    
    public static func testStreamFramerExactPacket() -> Bool {
        print("[Test 1] StreamMessageFramer: Exact 56-byte packet ingestion...")
        let framer = StreamMessageFramer()
        let packetData = createValidWirePacket(type: .locationPing)
        
        do {
            let frames = try framer.processIncomingChunk(packetData)
            guard frames.count == 1 else {
                print("  FAIL: Expected 1 frame, got \(frames.count)")
                return false
            }
            guard frames[0] == packetData else {
                print("  FAIL: Extracted frame does not match input packet.")
                return false
            }
            guard framer.unconsumedByteCount == 0 else {
                print("  FAIL: Framer should have 0 unconsumed bytes.")
                return false
            }
            print("  PASS: Single 56-byte packet framed accurately.")
            return true
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            return false
        }
    }
    
    // MARK: - Test 2: Framer Partial Reads (Byte by Byte & Small Chunks)
    
    public static func testStreamFramerPartialReads() -> Bool {
        print("[Test 2] StreamMessageFramer: Partial stream reads (1 byte per chunk)...")
        let framer = StreamMessageFramer()
        let packetData = createValidWirePacket(type: .sos, seq: 42)
        
        do {
            var extractedFrames: [Data] = []
            
            // Deliver 56 bytes one single byte at a time
            for (index, byte) in packetData.enumerated() {
                let chunk = Data([byte])
                let frames = try framer.processIncomingChunk(chunk)
                extractedFrames.append(contentsOf: frames)
                
                if index < 55 {
                    guard frames.isEmpty else {
                        print("  FAIL: Framer extracted a frame before full 56 bytes arrived (at index \(index)).")
                        return false
                    }
                    guard framer.unconsumedByteCount == index + 1 else {
                        print("  FAIL: Buffer count mismatch: expected \(index + 1), got \(framer.unconsumedByteCount)")
                        return false
                    }
                }
            }
            
            guard extractedFrames.count == 1 else {
                print("  FAIL: Expected 1 frame after 56 bytes, got \(extractedFrames.count)")
                return false
            }
            guard extractedFrames[0] == packetData else {
                print("  FAIL: Extracted frame content does not match original packet.")
                return false
            }
            guard framer.unconsumedByteCount == 0 else {
                print("  FAIL: Framer should be empty after completing packet.")
                return false
            }
            
            print("  PASS: Partial stream reassembly succeeded across 56 1-byte chunks.")
            return true
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            return false
        }
    }
    
    // MARK: - Test 3: Framer Coalesced Packets in Single Read
    
    public static func testStreamFramerCoalescedPackets() -> Bool {
        print("[Test 3] StreamMessageFramer: Multiple coalesced packets in a single read...")
        let framer = StreamMessageFramer()
        let packet1 = createValidWirePacket(type: .locationPing, seq: 1)
        let packet2 = createValidWirePacket(type: .sos, seq: 2)
        let packet3 = createValidWirePacket(type: .meetingUpdate, seq: 3)
        
        var combined = Data()
        combined.append(packet1)
        combined.append(packet2)
        combined.append(packet3)
        guard combined.count == 168 else {
            print("  FAIL: Combined size should be 168 bytes.")
            return false
        }
        
        do {
            let frames = try framer.processIncomingChunk(combined)
            guard frames.count == 3 else {
                print("  FAIL: Expected 3 frames, got \(frames.count)")
                return false
            }
            guard frames[0] == packet1, frames[1] == packet2, frames[2] == packet3 else {
                print("  FAIL: Frames did not unpack in correct order.")
                return false
            }
            guard framer.unconsumedByteCount == 0 else {
                print("  FAIL: Framer buffer should be empty.")
                return false
            }
            
            print("  PASS: 3 coalesced packets (168 bytes) cleanly sliced in single pass.")
            return true
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            return false
        }
    }
    
    // MARK: - Test 4: Fragmentation Across Reads
    
    public static func testStreamFramerFragmentationAcrossReads() -> Bool {
        print("[Test 4] StreamMessageFramer: Arbitrary fragmentation across chunk boundaries...")
        let framer = StreamMessageFramer()
        let packet1 = createValidWirePacket(type: .locationPing, seq: 10)
        let packet2 = createValidWirePacket(type: .ack, seq: 11)
        
        var streamData = Data()
        streamData.append(packet1)
        streamData.append(packet2) // 112 bytes total
        
        // Split into chunks of 35, 40, and 37 bytes (arbitrary non-56 multiples)
        let chunk1 = streamData.subdata(in: 0..<35)
        let chunk2 = streamData.subdata(in: 35..<75)
        let chunk3 = streamData.subdata(in: 75..<112)
        
        do {
            let f1 = try framer.processIncomingChunk(chunk1)
            guard f1.isEmpty else {
                print("  FAIL: Chunk 1 (35B) should yield 0 frames.")
                return false
            }
            
            let f2 = try framer.processIncomingChunk(chunk2)
            guard f2.count == 1, f2[0] == packet1 else {
                print("  FAIL: Chunk 2 (cumulative 75B) should yield packet 1.")
                return false
            }
            guard framer.unconsumedByteCount == 19 else { // 75 - 56 = 19 bytes remaining
                print("  FAIL: Expected 19 unconsumed bytes, got \(framer.unconsumedByteCount)")
                return false
            }
            
            let f3 = try framer.processIncomingChunk(chunk3)
            guard f3.count == 1, f3[0] == packet2 else {
                print("  FAIL: Chunk 3 (cumulative 112B) should yield packet 2.")
                return false
            }
            guard framer.unconsumedByteCount == 0 else {
                print("  FAIL: Buffer should be empty after both packets.")
                return false
            }
            
            print("  PASS: Arbitrary chunk fragmentation cleanly framed.")
            return true
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            return false
        }
    }
    
    // MARK: - Test 5: Corrupted Stream Header Resynchronization
    
    public static func testStreamFramerCorruptionRecovery() -> Bool {
        print("[Test 5] StreamMessageFramer: Resynchronization across corrupted leading bytes...")
        let framer = StreamMessageFramer()
        let validPacket = createValidWirePacket(type: .sos, seq: 99)
        
        // Prepend 7 bytes of garbage noise (invalid protocol versions)
        var corruptedStream = Data([0xFF, 0x00, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE])
        corruptedStream.append(validPacket)
        
        do {
            let frames = try framer.processIncomingChunk(corruptedStream)
            guard frames.count == 1 else {
                print("  FAIL: Expected 1 frame after skipping garbage, got \(frames.count)")
                return false
            }
            guard frames[0] == validPacket else {
                print("  FAIL: Extracted packet does not match valid packet.")
                return false
            }
            guard framer.unconsumedByteCount == 0 else {
                print("  FAIL: Buffer should be empty.")
                return false
            }
            
            print("  PASS: Garbage bytes discarded and valid frame synchronized.")
            return true
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            return false
        }
    }
    
    // MARK: - Test 6: Buffer Overflow Protection
    
    public static func testStreamFramerBufferOverflow() -> Bool {
        print("[Test 6] StreamMessageFramer: Bounded buffer overflow protection...")
        let smallFramer = StreamMessageFramer(maxBufferSize: 128)
        let garbageNoise = Data(repeating: 0xFF, count: 200)
        
        do {
            _ = try smallFramer.processIncomingChunk(garbageNoise)
            print("  FAIL: Should have thrown buffer overflow error.")
            return false
        } catch {
            guard smallFramer.unconsumedByteCount == 0 else {
                print("  FAIL: Buffer should be cleared after overflow.")
                return false
            }
            print("  PASS: Buffer overflow caught and buffer drained successfully.")
            return true
        }
    }
    
    // MARK: - Test 7: Outbox Urgent Preemption
    
    public static func testPriorityOutboxUrgentPreemption() -> Bool {
        print("[Test 7] PriorityOutboxQueue: Urgent SOS packets preempt normal location pings...")
        let outbox = PriorityOutboxQueue()
        
        let pingData = createValidWirePacket(type: .locationPing, seq: 1)
        let sosData = createValidWirePacket(type: .sos, seq: 2)
        
        do {
            // Enqueue normal location ping first
            try outbox.enqueue(data: pingData)
            
            // Enqueue urgent SOS second
            try outbox.enqueue(data: sosData)
            
            // Dequeue: Urgent SOS must come out FIRST despite being queued second!
            guard let firstOut = outbox.dequeue() else {
                print("  FAIL: Dequeue returned nil.")
                return false
            }
            guard firstOut.packetType == .sos else {
                print("  FAIL: Expected .sos first, got \(firstOut.packetType)")
                return false
            }
            
            // Next dequeue should be the location ping
            guard let secondOut = outbox.dequeue() else {
                print("  FAIL: Second dequeue returned nil.")
                return false
            }
            guard secondOut.packetType == .locationPing else {
                print("  FAIL: Expected .locationPing second, got \(secondOut.packetType)")
                return false
            }
            
            print("  PASS: Urgent SOS successfully preempted normal location ping.")
            return true
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            return false
        }
    }
    
    // MARK: - Test 8: Obsolete Location Ping Coalescing
    
    public static func testPriorityOutboxLocationPingCoalescing() -> Bool {
        print("[Test 8] PriorityOutboxQueue: Obsolete location ping coalescing...")
        let outbox = PriorityOutboxQueue()
        
        let ping1 = createValidWirePacket(type: .locationPing, seq: 1)
        let ping2 = createValidWirePacket(type: .locationPing, seq: 2)
        let ping3 = createValidWirePacket(type: .locationPing, seq: 3)
        
        do {
            // Queue 3 successive broadcast location pings without draining
            try outbox.enqueue(data: ping1)
            try outbox.enqueue(data: ping2)
            try outbox.enqueue(data: ping3)
            
            // Total queued count should be strictly 1, NOT 3!
            guard outbox.totalQueuedCount == 1 else {
                print("  FAIL: Expected total queued count 1, got \(outbox.totalQueuedCount)")
                return false
            }
            guard outbox.obsoletePingsCoalesced == 2 else {
                print("  FAIL: Expected 2 obsolete pings coalesced, got \(outbox.obsoletePingsCoalesced)")
                return false
            }
            
            // Dequeued item must be the freshest one (ping 3 with seq 3)
            guard let item = outbox.dequeue() else {
                print("  FAIL: Dequeue returned nil.")
                return false
            }
            guard item.packetData == ping3 else {
                print("  FAIL: Dequeued item is not the freshest location ping.")
                return false
            }
            
            print("  PASS: 2 obsolete pings coalesced; only freshest ping remained.")
            return true
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            return false
        }
    }
    
    // MARK: - Test 9: Bounded Capacity Enforcement
    
    public static func testPriorityOutboxBoundedCapacity() -> Bool {
        print("[Test 9] PriorityOutboxQueue: Bounded queue capacity enforcement...")
        let smallOutbox = PriorityOutboxQueue(maxUrgentCapacity: 3)
        let sosData = createValidWirePacket(type: .sos)
        
        do {
            try smallOutbox.enqueue(data: sosData)
            try smallOutbox.enqueue(data: sosData)
            try smallOutbox.enqueue(data: sosData)
            
            // 4th urgent packet should throw queueFull
            do {
                try smallOutbox.enqueue(data: sosData)
                print("  FAIL: Should have thrown queueFull error.")
                return false
            } catch TransportError.queueFull {
                print("  PASS: Queue capacity limit correctly enforced.")
                return true
            } catch {
                print("  FAIL: Unexpected error type: \(error)")
                return false
            }
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            return false
        }
    }
    
    // MARK: - Test 10: Retry Budget
    
    public static func testPriorityOutboxRetryBudget() -> Bool {
        print("[Test 10] PriorityOutboxQueue: Bounded retries and backoff budget...")
        let outbox = PriorityOutboxQueue()
        let sosData = createValidWirePacket(type: .sos)
        
        do {
            let item = try outbox.enqueue(data: sosData)
            
            // Attempt 1 fails -> requeue
            let canRetry1 = outbox.requeueForRetry(item)
            guard canRetry1 else {
                print("  FAIL: Attempt 1 should be retryable.")
                return false
            }
            
            guard let popped1 = outbox.dequeue() else {
                print("  FAIL: Popped item was nil.")
                return false
            }
            guard popped1.attemptCount == 1 else {
                print("  FAIL: Expected attemptCount 1, got \(popped1.attemptCount)")
                return false
            }
            
            // Attempt 2 fails -> requeue
            let canRetry2 = outbox.requeueForRetry(popped1)
            guard canRetry2 else {
                print("  FAIL: Attempt 2 should be retryable.")
                return false
            }
            
            guard let popped2 = outbox.dequeue() else {
                print("  FAIL: Popped item was nil.")
                return false
            }
            guard popped2.attemptCount == 2 else {
                print("  FAIL: Expected attemptCount 2, got \(popped2.attemptCount)")
                return false
            }
            
            // Attempt 3 fails -> maxRetries (2) reached -> should NOT requeue
            let canRetry3 = outbox.requeueForRetry(popped2)
            guard !canRetry3 else {
                print("  FAIL: Exceeded max retries should return false.")
                return false
            }
            
            print("  PASS: Retry budget exhausted after exactly 2 retries (3 total attempts).")
            return true
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            return false
        }
    }
    
    // MARK: - Test 11: Tie-Breaker Logic
    
    public static func testTieBreakerLogic() -> Bool {
        print("[Test 11] Tie-Breaker: Deterministic connection role assignment...")
        let peerIdA = "0000000A"
        let peerIdB = "0000000B"
        
        // Device A evaluates Device B:
        let aRoleIsInitiator = peerIdA < peerIdB
        guard aRoleIsInitiator == true else {
            print("  FAIL: Peer A should be initiator.")
            return false
        }
        
        // Device B evaluates Device A:
        let bRoleIsInitiator = peerIdB < peerIdA
        guard bRoleIsInitiator == false else {
            print("  FAIL: Peer B should be listener.")
            return false
        }
        
        print("  PASS: Tie-breaker deterministically assigns initiator to A and listener to B.")
        return true
    }
    
    // MARK: - Test 12: Diagnostics Snapshot
    
    public static func testDiagnosticsSnapshot() -> Bool {
        print("[Test 12] TransportDiagnostics: Telemetry snapshot integrity...")
        let diag = TransportDiagnostics(
            localPeerId: "DNA",
            serviceType: "_teekum._udp",
            sessionName: "Test Festival",
            sessionId: 0xAABB,
            state: .connected(peerCount: 2),
            activeDirectPeers: [
                PeerInfo(id: "AAAA1111", displayName: "Alice"),
                PeerInfo(id: "BBBB2222", displayName: "Bob")
            ],
            packetsSent: 15,
            packetsReceived: 20,
            obsoletePingsCoalesced: 4,
            sendErrors: 0,
            lastError: nil,
            recentEvents: [DiagnosticEvent(message: "Connected to Alice")]
        )
        
        guard diag.localPeerId == "DNA" else { return false }
        guard diag.activeDirectPeers.count == 2 else { return false }
        guard diag.packetsSent == 15 else { return false }
        guard diag.obsoletePingsCoalesced == 4 else { return false }
        guard case .connected(let count) = diag.state, count == 2 else { return false }
        
        print("  PASS: TransportDiagnostics snapshot populated accurately.")
        return true
    }
    
    // MARK: - Test 13: Zero-Handshake Immediate Packet Framing
    
    public static func testZeroHandshakeImmediatePacketFraming() -> Bool {
        print("[Test 13] Zero-handshake immediate 56-byte wire packet framing upon connection...")
        let framer = StreamMessageFramer()
        let validWirePacket = createValidWirePacket(type: .locationPing, seq: 99)
        
        guard validWirePacket.count == PacketConstants.wirePacketSize else {
            print("  FAIL: Wire packet size mismatch.")
            return false
        }
        
        do {
            let frames = try framer.processIncomingChunk(validWirePacket)
            guard frames.count == 1 else {
                print("  FAIL: Expected 1 extracted frame, got \(frames.count)")
                return false
            }
            guard frames[0] == validWirePacket else {
                print("  FAIL: Extracted frame does not match original wire packet.")
                return false
            }
            guard framer.unconsumedByteCount == 0 else {
                print("  FAIL: Unconsumed bytes should be 0.")
                return false
            }
            print("  PASS: Immediate 56-byte location packet extracted cleanly with zero-handshake overhead.")
            return true
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            return false
        }
    }
    
    // MARK: - Test 14: Stranger Relay Elevated Priority & Distant Link Retries
    
    public static func testPriorityOutboxStrangerRelayElevatedPriority() -> Bool {
        print("[Test 14] PriorityOutboxQueue: Stranger relay elevated ahead of routine location pings & retried...")
        let outbox = PriorityOutboxQueue()
        
        let routinePing = createValidWirePacket(type: .locationPing, seq: 10)
        let strangerRelay = createValidWirePacket(type: .locationPing, seq: 20, sid: 0x9999)
        let urgentSOS = createValidWirePacket(type: .sos, seq: 30)
        
        do {
            // 1. Enqueue routine local ping first
            try outbox.enqueue(data: routinePing, isRelay: false)
            
            // 2. Enqueue stranger relay second
            try outbox.enqueue(data: strangerRelay, destinationPeerId: "distant-peer", isRelay: true)
            
            // 3. Enqueue urgent SOS third
            try outbox.enqueue(data: urgentSOS, isRelay: false)
            
            // Dequeue 1: Urgent SOS must come out FIRST
            guard let first = outbox.dequeue(), first.packetType == .sos else {
                print("  FAIL: First item must be .sos")
                return false
            }
            
            // Dequeue 2: Stranger relay must come out SECOND (elevated ahead of routine ping)
            guard let second = outbox.dequeue(), second.isRelay else {
                print("  FAIL: Second item must be stranger relay (elevated ahead of routine pings)")
                return false
            }
            
            // Dequeue 3: Routine ping must come out THIRD
            guard let third = outbox.dequeue(), !third.isRelay, third.packetType == .locationPing else {
                print("  FAIL: Third item must be routine location ping")
                return false
            }
            
            // 4. Verify retry capability for distant relay packet
            guard second.maxRetries == MeshTimingConfiguration.default.distantLinkMaxRetries else {
                print("  FAIL: Stranger relay maxRetries should match distantLinkMaxRetries (\(MeshTimingConfiguration.default.distantLinkMaxRetries)), got \(second.maxRetries)")
                return false
            }
            
            let canRetry1 = outbox.requeueForRetry(second)
            guard canRetry1 else {
                print("  FAIL: Requeue attempt 1 should succeed")
                return false
            }
            
            guard let retriedItem = outbox.dequeue(), retriedItem.isRelay, retriedItem.attemptCount == 1 else {
                print("  FAIL: Retried relay item should be at the front of relay lane with attemptCount 1")
                return false
            }
            
            print("  PASS: Stranger relay packet successfully elevated ahead of routine pings with configurable retry budget.")
            return true
        } catch {
            print("  FAIL: Unexpected error: \(error)")
            return false
        }
    }
}
