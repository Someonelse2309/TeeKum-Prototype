import CoreLocation
import CryptoKit
import Foundation

@MainActor
enum Phase1RegressionTests {
    static func runAllTests() async -> Bool {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            print("[Phase1 regression] \(condition ? "PASS" : "FAIL"): \(name)")
            if !condition { failures += 1 }
        }

        let location = LocationService()
        location.simulateLocation(coordinate: .init(latitude: -6.2, longitude: 106.8), accuracy: 5)
        location.clearSessionState()
        check(location.currentLocation == nil && location.currentHeading == nil,
              "Session teardown clears local GPS and compass caches")
        let first = GroupSession(localInitials: "ONE")
        let second = GroupSession(localInitials: "TWO")
        check(first.symmetricKeyData != second.symmetricKeyData, "New groups do not share a global secret")
        do {
            let store = try SessionRecoveryStore(memoryOnly: true)
            try store.save(first)
            check(try store.load() == first, "Encrypted SwiftData recovery roundtrip")
            try store.recordSOSEvent(42, session: first)
            _ = try store.load()
            check(store.seenSOSEventIDs.contains(42), "SOS deduplication evidence survives recovery")
            try store.purge()
            check(try store.load() == nil, "Leaving removes the recoverable session")
            try store.save(first)
            check(try store.load(now: first.createdAt.addingTimeInterval(13 * 3600)) == nil,
                  "Expired sessions are purged")
        } catch {
            check(false, "SwiftData recovery: \(error)")
        }

        let model = SessionConnectionModel()
        model.sessionViewModel = GroupSessionViewModel(activeSession: first, inMemoryStorage: true)
        model.handlePeerUpdates([PeerInfo(id: "untrusted", displayName: "FAKE")], for: first)
        check(model.sessionViewModel.members.isEmpty, "Discovery never inserts unauthenticated friends")
        let measuredAt = Date.now.addingTimeInterval(-120)
        let payload = LocationPingPayload(coordinate: .init(latitude: -6.2, longitude: 106.8),
            timestamp: measuredAt, accuracy: 12, statusCode: .available,
            senderInitials: "TWO", batteryLevel: 75, heading: 128)
        let envelope = CleartextEnvelope(type: .locationPing, sessionId: first.sessionId, sequenceNumber: 1)
        do {
            let crypto = CryptoService()
            let key = SymmetricKey(data: first.symmetricKeyData)
            let wire = try await crypto.sealPacket(payload: payload.serialize(), envelope: envelope, using: key)
            var forged = wire
            forged.authTag[0] ^= 1
            await model.handleInboundPacket(InboundPacket(rawPacket: forged, sourcePeerId: "untrusted"), for: first)
            check(model.sessionViewModel.members.isEmpty && model.relayedPacketCache.isEmpty,
                  "Invalid authentication cannot update the map or enter the relay cache")
            await model.handleInboundPacket(InboundPacket(rawPacket: wire, sourcePeerId: "trusted"), for: first)
            check(abs((model.sessionViewModel.members.first?.lastSeen.timeIntervalSince(measuredAt) ?? 999)) < 1,
                  "A freshly received old fix remains visibly stale")
            let older = Member(id: "TWO", lastSeen: measuredAt.addingTimeInterval(-10),
                coordinate: .init(latitude: 1, longitude: 1))
            model.sessionViewModel.updateMember(older)
            check(model.sessionViewModel.members.first?.coordinate?.latitude == -6.2,
                  "Delayed fixes cannot replace newer coordinates")
            var relayed = wire
            relayed.envelope.hopCount = 1
            let opened = try await crypto.openPacket(relayed, using: key)
            check(opened.payload == payload.serialize(), "Hop mutation preserves authenticated payload")
            let expiredSOS = SOSPayload(coordinate: payload.coordinate, accuracy: 12,
                senderInitials: "TWO", batteryLevel: 75, sentAt: .now.addingTimeInterval(-600))
            let sosEnvelope = CleartextEnvelope(type: .sos, sessionId: first.sessionId, sequenceNumber: 2)
            let expiredWire = try await crypto.sealPacket(payload: expiredSOS.serialize(), envelope: sosEnvelope, using: key)
            await model.handleInboundPacket(InboundPacket(rawPacket: expiredWire, sourcePeerId: "trusted"), for: first)
            check(model.sessionViewModel.members.first?.status.code != .sos,
                  "An expired SOS cannot revive an emergency state")
            let legacy = Data(repeating: 0, count: 54)
            check((try? RawWirePacket.fromWireData(legacy)) == nil, "Legacy frames are explicitly rejected")
        } catch {
            check(false, "Authenticated ingress: \(error)")
        }
        print("[Phase1RegressionTests] \(failures == 0 ? "ALL PASSED" : "FAILED")")
        return failures == 0
    }
}
