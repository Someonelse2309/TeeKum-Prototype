import SwiftUI
import Observation
import CoreLocation
import CryptoKit

/// Owns the session connection tasks and authenticated roster outside SwiftUI view values.
@Observable
@MainActor
final class SessionConnectionModel {
    var sessionViewModel = GroupSessionViewModel()
    var locationService: LocationService
    var mapViewModel: MapViewModel
    var sosViewModel = SOSViewModel()
    var meetingPointViewModel = MeetingPointViewModel()
    var locationPublisher: LocationPublisher?
    var relayedPacketCache: [Data: Date] = [:]
    var receivedPacketCache: [Data: Date] = [:]
    var authenticatedDirectLinks: [String: String] = [:]
    let cryptoService = CryptoService()
    let peerTransport = PeerTransportService()
    
    init() {
        let service = LocationService()
        locationService = service
        mapViewModel = MapViewModel(locationService: service)
    }
    
    // MARK: - Session Lifecycle
    
    @MainActor
    func runSessionLifecycle(session: GroupSession) async {
        // Ask only once the user has accepted group participation.
        guard await locationService.requestPermissions(), !Task.isCancelled else {
            sessionViewModel.errorMessage = "Location access is unavailable. SOS can still send without a GPS fix."
            if Task.isCancelled { return }
            await startSessionServices(session: session)
            return
        }
        try? locationService.startTracking()
        await startSessionServices(session: session)
    }

    @MainActor
    func startSessionServices(session: GroupSession) async {
        guard !Task.isCancelled else { return }
        
        // 2. Start Live Activity Companion
        await LiveActivityManager.shared.startSessionActivity(session: session)
        
        // 3. Configure SOS
        sosViewModel.configure(
            locationService: locationService,
            sessionProvider: { [weak sessionModel = sessionViewModel] in sessionModel?.activeSession },
            cryptoService: cryptoService,
            transport: peerTransport,
            memberNameResolver: { senderInitials in
                senderInitials
            }
        )
        
        sosViewModel.restoreSeenEvents(sessionViewModel.recoveredSOSEventIDs)

        // 4. Configure Meeting Point
        meetingPointViewModel.configure(
            sessionProvider: { [weak sessionModel = sessionViewModel] in sessionModel?.activeSession },
            cryptoService: cryptoService,
            transport: peerTransport
        )
        
        // 4. Start Radio Transport
        do {
            try await peerTransport.start(serviceType: "_teekum._tcp", session: session)
        } catch {
            print("[TeeKumApp] Radio transport failed to start: \(error)")
        }
        
        // 4. Start Location Publisher
        let publisher = LocationPublisher(
            locationService: locationService,
            sessionProvider: { [weak sessionModel = sessionViewModel] in sessionModel?.activeSession },
            cryptoService: cryptoService,
            transport: peerTransport
        )
        self.locationPublisher = publisher
        publisher.start()
        
        // 5. Inbound Packets and Peer Updates
        let inboundStream = await peerTransport.inboundPackets
        let peerUpdatesStream = await peerTransport.peerUpdates
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.consumePackets(inboundStream, session: session) }
            group.addTask { await self.consumePeers(peerUpdatesStream, session: session) }
            group.addTask { await self.monitorExpiry(session: session) }
        }
    }

    private func monitorExpiry(session: GroupSession) async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            guard sessionViewModel.activeSession == session else { return }
            sessionViewModel.expireSessionIfNeeded()
        }
    }

    private func consumePackets(_ stream: AsyncStream<InboundPacket>, session: GroupSession) async {
        for await inbound in stream {
            guard !Task.isCancelled else { break }
            await handleInboundPacket(inbound, for: session)
        }
    }

    private func consumePeers(_ stream: AsyncStream<[PeerInfo]>, session: GroupSession) async {
        for await peers in stream {
            guard !Task.isCancelled else { break }
            handlePeerUpdates(peers, for: session)
            if peers.contains(where: { $0.isDirectLink }) {
                locationService.publishCurrentState()
                await meetingPointViewModel.syncActiveMeetingPointToPeers()
            }
        }
    }

    @MainActor
    func stopActiveSession() async {
        locationPublisher?.stop()
        locationPublisher = nil
        locationService.clearSessionState()
        sosViewModel.stopListening()
        sosViewModel.reset()
        sosViewModel.dismissIncomingAlert()
        meetingPointViewModel.reset()
        mapViewModel.selectedMember = nil
        relayedPacketCache.removeAll()
        receivedPacketCache.removeAll()
        authenticatedDirectLinks.removeAll()
        await peerTransport.stop()
        await LiveActivityManager.shared.endSessionActivity()
        await cryptoService.replayFilter.purge()
    }
    
    // MARK: - Inbound Packet Dispatching
    
    @MainActor
    func handleInboundPacket(_ inbound: InboundPacket, for session: GroupSession) async {
        let raw = inbound.rawPacket
        let envelope = raw.envelope
        
        guard envelope.sessionId == session.sessionId else { return }
        
        // Authentication precedes every UI change and all forwarding, including SOS/ACK.
        let key = SymmetricKey(data: session.symmetricKeyData)
        guard let decrypted = try? await cryptoService.open(
            ciphertext: raw.ciphertext, envelope: envelope, authTag: raw.authTag, using: key
        ), sessionViewModel.activeSession == session else { return }
        if envelope.type == .sos {
            guard let payload = try? SOSPayload.deserialize(from: decrypted),
                  abs(Date.now.timeIntervalSince(payload.sentAt)) <= 300 else { return }
            await sosViewModel.processInboundPacket(inbound)
            if sosViewModel.activeIncomingAlert?.id == payload.sosEventId {
                sessionViewModel.recordSOSEvent(payload.sosEventId)
            }
        } else if envelope.type == .ack {
            await sosViewModel.processInboundPacket(inbound)
        }

        var normalized = raw
        normalized.envelope.hopCount = 0
        guard let bytes = try? normalized.toWireData() else { return }
        let fingerprint = Data(SHA256.hash(data: bytes))
        let now = Date.now
        receivedPacketCache = receivedPacketCache.filter { now.timeIntervalSince($0.value) < 300 }
        guard receivedPacketCache[fingerprint] == nil else { return }
        if receivedPacketCache.count >= 256, let oldest = receivedPacketCache.min(by: { $0.value < $1.value })?.key {
            receivedPacketCache.removeValue(forKey: oldest)
        }
        receivedPacketCache[fingerprint] = now

        switch envelope.type {
        case .sos:
            if let sos = try? SOSPayload.deserialize(from: decrypted) {
                guard sos.senderInitials != session.localInitials else { return }
                
                let resolvedName = sos.senderInitials
                
                let member = Member(
                    id: sos.senderInitials,
                    name: resolvedName,
                    lastSeen: sos.timestamp,
                    coordinate: sos.timestamp.timeIntervalSince1970 > 0 ? sos.coordinate : nil,
                    horizontalAccuracy: CLLocationAccuracy(sos.accuracy),
                    status: UserStatus(code: .sos),
                    batteryLevel: Float(sos.batteryLevel) / 100.0,
                    heading: sessionViewModel.members.first(where: { $0.id == sos.senderInitials })?.heading,
                    isDirectPeer: envelope.hopCount == 0,
                    rssi: inbound.receivedRssi
                )
                if envelope.hopCount == 0 { authenticatedDirectLinks[member.id] = inbound.sourcePeerId }
                sessionViewModel.updateMember(member)
                
                // Update incoming alert sender name with resolved name
                if var alert = sosViewModel.activeIncomingAlert, alert.id == sos.sosEventId {
                    alert.senderName = resolvedName
                    sosViewModel.activeIncomingAlert = alert
                }
            }
            
            // Re-broadcast / forward SOS across the mesh to all other peers
            await relayMeshPacketIfNeeded(inbound, for: session)
            
        case .locationPing:
            guard let ping = try? LocationPingPayload.deserialize(from: decrypted) else { return }
            guard ping.senderInitials != session.localInitials else { return }
            
            let resolvedName = ping.senderInitials
            
            let member = Member(
                id: ping.senderInitials,
                name: resolvedName,
                lastSeen: ping.timestamp,
                coordinate: ping.coordinate,
                horizontalAccuracy: CLLocationAccuracy(ping.accuracy),
                status: UserStatus(code: ping.statusCode),
                batteryLevel: Float(ping.batteryLevel) / 100.0,
                heading: CLLocationDirection(ping.heading) * 360 / 255,
                isDirectPeer: envelope.hopCount == 0,
                rssi: inbound.receivedRssi
            )
            if envelope.hopCount == 0 { authenticatedDirectLinks[member.id] = inbound.sourcePeerId }
            sessionViewModel.updateMember(member)
            
            await relayMeshPacketIfNeeded(inbound, for: session)
            
        case .meetingUpdate:
            guard let update = try? MeetingUpdatePayload.deserialize(from: decrypted),
                  update.senderInitials != session.localInitials else { return }
            meetingPointViewModel.applyInboundUpdate(update)
            await relayMeshPacketIfNeeded(inbound, for: session)
            
        case .ack:
            if let ack = try? ACKPayload.deserialize(from: decrypted), ack.responderInitials != session.localInitials {
                await relayMeshPacketIfNeeded(inbound, for: session)
            }
        default:
            break
        }
    }
    
    // MARK: - Multi-Hop Mesh Forwarding
    
    @MainActor
    func relayMeshPacketIfNeeded(_ inbound: InboundPacket, for session: GroupSession) async {
        let envelope = inbound.rawPacket.envelope
        guard envelope.hopCount < envelope.hopLimit else { return }
        
        // Same-group authenticated rebroadcast only; Phase 2 stranger routing is not implemented.
        var normalized = inbound.rawPacket
        normalized.envelope.hopCount = 0
        guard let normalizedBytes = try? normalized.toWireData() else { return }
        let cacheKey = Data(SHA256.hash(data: normalizedBytes))
        let now = Date.now
        relayedPacketCache = relayedPacketCache.filter { now.timeIntervalSince($0.value) < 300 }
        guard relayedPacketCache[cacheKey] == nil else { return }
        if relayedPacketCache.count >= 256, let oldest = relayedPacketCache.min(by: { $0.value < $1.value })?.key {
            relayedPacketCache.removeValue(forKey: oldest)
        }
        relayedPacketCache[cacheKey] = now

        var relayedEnvelope = envelope
        relayedEnvelope.hopCount &+= 1
        
        let relayedWirePacket = RawWirePacket(
            envelope: relayedEnvelope,
            ciphertext: inbound.rawPacket.ciphertext,
            authTag: inbound.rawPacket.authTag
        )
        
        do {
            let wireData = try relayedWirePacket.toWireData()
            let peers = await peerTransport.getDiagnostics().activeDirectPeers
            for peer in peers where peer.isDirectLink && peer.id != inbound.sourcePeerId {
                try await peerTransport.sendPacket(wireData, to: peer.id)
            }
        } catch {
            print("[TeeKumApp] Failed to relay mesh packet: \(error)")
        }
    }
    
    @MainActor
    func handlePeerUpdates(_ peers: [PeerInfo], for session: GroupSession) {
        // Bonjour and TCP readiness are not proof of group membership.
        let readyIDs = Set(peers.filter(\.isDirectLink).map(\.id))
        for var member in sessionViewModel.members {
            member.isDirectPeer = authenticatedDirectLinks[member.id].map { readyIDs.contains($0) } ?? false
            sessionViewModel.updateMember(member)
        }
        Task {
            await updateLiveActivityTelemetry()
        }
    }
    
    @MainActor
    func updateLiveActivityTelemetry() async {
        let directCount = sessionViewModel.members.count(where: { $0.isDirectPeer })
        let isSOS = sosViewModel.activeIncomingAlert != nil || (sosViewModel.deliveryState != .idle && sosViewModel.deliveryState != .searchingPeers)
        let sosSender = sosViewModel.activeIncomingAlert?.senderInitials
        await LiveActivityManager.shared.updateSessionActivity(
            peerCount: directCount,
            meetingPoint: meetingPointViewModel.activeMeetingPoint,
            currentLocation: locationService.currentLocation?.coordinate,
            isSOSActive: isSOS,
            sosSenderInitials: sosSender
        )
    }
    
    func handleIncomingURL(_ url: URL) {
        if url.scheme == "teekum" {
            if url.host == "meeting" {
                // Focused via deep link from Live Activity
                return
            } else if url.host == "sos" {
                // Focused via deep link from Live Activity
                return
            }
        }
        guard let invite = GroupSession.parseInvite(from: url) else { return }
        sessionViewModel.pendingInvite = invite
    }
}
