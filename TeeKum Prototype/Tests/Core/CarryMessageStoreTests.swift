import Foundation

nonisolated enum CarryMessageStoreTests {
    static func runAllTests() -> Bool {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func frame(_ sequence: UInt32 = 1, type: PacketType = .chatMessage, hop: UInt8 = 0) -> Data {
            try! RawWirePacket(envelope: CleartextEnvelope(type: type, hopLimit: 8, hopCount: hop,
                                                          sessionId: 123, sequenceNumber: sequence),
                               ciphertext: Data(repeating: 42, count: 30),
                               authTag: Data(repeating: 7, count: 16)).toWireData()
        }
        var sender = CarryMessageStore()
        let original = frame()
        sender.remember(original, isForeign: false, now: now)
        assert(sender.nextTransmission(to: [], now: now) == nil)
        let first = sender.nextTransmission(to: ["B"], now: now.addingTimeInterval(60))!
        assert(first.data == original)
        sender.markAttempt(first.data, to: "B", now: now.addingTimeInterval(60))
        assert(sender.nextTransmission(to: ["B"], now: now.addingTimeInterval(61)) == nil)
        assert(sender.nextTransmission(to: ["B", "C"], now: now.addingTimeInterval(61))?.peer == "C")
        sender.disconnected("B")
        assert(sender.nextTransmission(to: ["B"], now: now.addingTimeInterval(62)) != nil)

        // B takes opaque custody, leaves A, and encounters C minutes later.
        var relay = CarryMessageStore()
        let forwarded = frame(hop: 1)
        relay.remember(forwarded, isForeign: true, now: now)
        assert(relay.nextTransmission(to: [], now: now) == nil)
        let carried = relay.nextTransmission(to: ["C"], now: now.addingTimeInterval(180))!
        assert(carried.data == forwarded && carried.isForeign)
        assert(carried.data.suffix(46) == original.suffix(46))
        // Looped packets neither reset hops nor extend custody.
        relay.remember(frame(hop: 3), isForeign: true, now: now.addingTimeInterval(590))
        assert(relay.nextTransmission(to: ["C"], now: now.addingTimeInterval(599))?.data == forwarded)
        assert(relay.nextTransmission(to: ["C"], now: now.addingTimeInterval(600)) == nil)

        // An unreliable edge link needs a retry while the 15-second chat ACK window is open.
        var edge = CarryMessageStore()
        edge.remember(forwarded, isForeign: true, now: now)
        edge.markAttempt(forwarded, to: "C", now: now)
        assert(edge.nextTransmission(to: ["C"], now: now.addingTimeInterval(2)) != nil,
               "Relay retries must occur before chat's 15-second ACK timeout")

        edge.markAttempt(forwarded, to: "C", now: now.addingTimeInterval(2))
        edge.markAttempt(forwarded, to: "C", now: now.addingTimeInterval(4))
        assert(edge.nextTransmission(to: ["C"], now: now.addingTimeInterval(6)) == nil)
        assert(edge.nextTransmission(to: ["C"], now: now.addingTimeInterval(34)) != nil)
        assert(edge.nextTransmission(to: ["D"], now: now.addingTimeInterval(6))?.peer == "D")
        var sources = CarryMessageStore()
        sources.remember(forwarded, isForeign: true, excludingPeerId: "A", now: now)
        assert(sources.nextTransmission(to: ["A"], now: now) == nil)
        sources.remember(frame(hop: 2), isForeign: true, excludingPeerId: "C", now: now)
        assert(sources.nextTransmission(to: ["A", "C"], now: now) == nil)
        assert(sources.nextTransmission(to: ["D"], now: now)?.data == forwarded)

        var ackStore = CarryMessageStore()
        let ack = frame(2, type: .ack, hop: 8)
        ackStore.remember(ack, isForeign: false, now: now)
        assert(ackStore.nextTransmission(to: ["A"], now: now.addingTimeInterval(120))?.data == ack)
        ackStore.remember(frame(3, type: .locationPing), isForeign: false, now: now)
        ackStore.markAttempt(ack, to: "A", now: now)
        assert(ackStore.nextTransmission(to: ["A"], now: now) == nil)

        var bounded = CarryMessageStore(capacity: 2)
        bounded.remember(frame(1), isForeign: true, now: now)
        bounded.remember(frame(2), isForeign: false, now: now)
        bounded.remember(frame(3), isForeign: true, now: now)
        assert(bounded.nextTransmission(to: ["C"], now: now)?.data == frame(2))
        bounded.removeForeign()
        bounded.markAttempt(frame(2), to: "C", now: now)
        assert(bounded.nextTransmission(to: ["C"], now: now) == nil)
        bounded.removeAll()
        assert(bounded.nextTransmission(to: ["D"], now: now) == nil)
        bounded.remember(Data([1, 2]), isForeign: false, now: now)
        var malformed = frame()
        malformed[1] = 255
        bounded.remember(malformed, isForeign: false, now: now)
        assert(bounded.nextTransmission(to: ["D"], now: now) == nil)
        print("CarryMessageStoreTests passed: delayed encounters, ACK custody, fairness, reconnect, expiry, bounds, policy, malformed frames")
        return true
    }
}
