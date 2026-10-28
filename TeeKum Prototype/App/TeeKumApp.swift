//
//  TeeKumApp.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI
import CoreLocation
import CryptoKit

@main
struct TeeKumApp: App {
    @State private var sessionViewModel = GroupSessionViewModel()
    @State private var locationService: LocationService
    @State private var mapViewModel: MapViewModel
    @State private var sosViewModel = SOSViewModel()
    @State private var meetingPointViewModel = MeetingPointViewModel()
    @State private var locationPublisher: LocationPublisher?
    @State private var relayedPacketCache: Set<String> = []
    private let cryptoService = CryptoService()
    private let peerTransport = PeerTransportService()
    
    init() {
        let service = LocationService()
        _locationService = State(initialValue: service)
        _mapViewModel = State(initialValue: MapViewModel(locationService: service))
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if sessionViewModel.hasActiveSession, let session = sessionViewModel.activeSession {
                    MainMapView(
                        mapViewModel: mapViewModel,
                        sessionViewModel: sessionViewModel,
                        sosViewModel: sosViewModel,
                        meetingPointViewModel: meetingPointViewModel
                    )
                    .task(id: session.sessionId) {
                        await runSessionLifecycle(session: session)
                    }
                } else {
                    GroupPairingView(sessionViewModel: sessionViewModel)
                        .task {
                            await stopActiveSession()
                        }
                }
            }
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .task {
                if ProcessInfo.processInfo.arguments.contains("-runAllTests") {
                    print(">>> RUNNING ALL AUTOMATED TESTS <<<")
                    fflush(stdout)
                    _ = PacketCodecTests.runAllTests()
                    fflush(stdout)
                    _ = PeerTransportTests.runAllTests()
                    fflush(stdout)
                    _ = await CryptoSecurityTests.runAllTests()
                    fflush(stdout)
                    _ = await LocationPublishingTests.runAllTests()
                    fflush(stdout)
                    _ = await UIStateTests.runAllTests()
                    fflush(stdout)
                    _ = await SOSEndToEndTests.runAllTests()
                    fflush(stdout)
                    print(">>> ALL AUTOMATED TEST RUNS FINISHED <<<")
                    fflush(stdout)
                } else {
                    if ProcessInfo.processInfo.arguments.contains("-runUITests") {
                        _ = await UIStateTests.runAllTests()
                        fflush(stdout)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-runSOSTests") {
                        _ = await SOSEndToEndTests.runAllTests()
                        fflush(stdout)
                    }
                }
            }
        }
    }
    
    // MARK: - Session Lifecycle
    
    @MainActor
    private func runSessionLifecycle(session: GroupSession) async {
        // 1. Start Location Tracking
        try? locationService.startTracking()
        
        // 2. Configure SOS
        sosViewModel.configure(
            locationService: locationService,
            sessionProvider: { session },
            cryptoService: cryptoService,
            transport: peerTransport,
            memberNameResolver: { [weak sessionViewModel] senderId in
                sessionViewModel?.members.first(where: { $0.id == senderId })?.name
            }
        )
        
        // 3. Start Radio Transport
        do {
            try await peerTransport.start(serviceType: "_teekum._tcp", session: session)
        } catch {
            print("[TeeKumApp] Radio transport failed to start: \(error)")
        }
        
        // 4. Start Location Publisher
        let publisher = LocationPublisher(
            locationService: locationService,
            sessionProvider: { session },
            cryptoService: cryptoService,
            transport: peerTransport
        )
        self.locationPublisher = publisher
        publisher.start()
        
        // 5. Inbound Packets and Peer Updates
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await inbound in peerTransport.inboundPackets {
                    guard !Task.isCancelled else { break }
                    await handleInboundPacket(inbound, for: session)
                }
            }
            
            group.addTask { @MainActor in
                for await peers in peerTransport.peerUpdates {
                    guard !Task.isCancelled else { break }
                    handlePeerUpdates(peers, for: session)
                    if peers.contains(where: { $0.isDirectLink }) {
                        locationService.publishCurrentState()
                    }
                }
            }
        }
    }
    
    @MainActor
    private func stopActiveSession() async {
        locationPublisher?.stop()
        locationPublisher = nil
        await peerTransport.stop()
        locationService.stopTracking()
        locationService.updateStatus(UserStatus(code: .available))
        sosViewModel.stopListening()
        sosViewModel.reset()
        sosViewModel.dismissIncomingAlert()
        meetingPointViewModel.cancelMeetingPoint()
        mapViewModel.selectedMember = nil
        relayedPacketCache.removeAll()
    }
    
    // MARK: - Inbound Packet Dispatching
    
    @MainActor
    private func handleInboundPacket(_ inbound: InboundPacket, for session: GroupSession) async {
        let raw = inbound.rawPacket
        let envelope = raw.envelope
        
        guard envelope.sessionId == session.sessionId else { return }
        
        // 1. Process ACK packets through SOSViewModel and relay if multi-hop
        if envelope.type == .ack {
            await sosViewModel.processInboundPacket(inbound)
            await relayMeshPacketIfNeeded(inbound, for: session)
            return
        }
        
        // 2. Process SOS packets through SOSViewModel (siren, haptics, incoming alert, delivery ACK)
        if envelope.type == .sos {
            await sosViewModel.processInboundPacket(inbound)
        }
        
        // 3. Decrypt with session symmetric key
        let key = SymmetricKey(data: session.symmetricKeyData)
        guard let decrypted = try? await cryptoService.open(
            ciphertext: raw.ciphertext,
            envelope: envelope,
            authTag: raw.authTag,
            using: key
        ) else {
            // If decryption fails (e.g. unknown payload or blind mesh relay), still forward SOS
            if envelope.type == .sos {
                await relayMeshPacketIfNeeded(inbound, for: session)
            }
            return
        }
        
        switch envelope.type {
        case .sos:
            if let sos = try? SOSPayload.deserialize(from: decrypted) {
                guard sos.senderId != session.localMemberId else { return }
                
                let existingName = sessionViewModel.members.first(where: { $0.id == sos.senderId })?.name
                let resolvedName = existingName ?? "Friend \(String(format: "%04X", sos.senderId & 0xFFFF))"
                
                let member = Member(
                    id: sos.senderId,
                    name: resolvedName,
                    lastSeen: inbound.receivedAt,
                    coordinate: sos.coordinate,
                    horizontalAccuracy: CLLocationAccuracy(sos.accuracy),
                    status: UserStatus(code: .sos),
                    batteryLevel: Float(sos.batteryLevel) / 100.0,
                    heading: sessionViewModel.members.first(where: { $0.id == sos.senderId })?.heading,
                    isDirectPeer: envelope.hopCount == 0,
                    rssi: inbound.receivedRssi
                )
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
            guard ping.senderId != session.localMemberId else { return }
            
            let existingName = sessionViewModel.members.first(where: { $0.id == ping.senderId })?.name
            let resolvedName = existingName ?? "Friend \(String(format: "%04X", ping.senderId & 0xFFFF))"
            
            let member = Member(
                id: ping.senderId,
                name: resolvedName,
                lastSeen: inbound.receivedAt,
                coordinate: ping.coordinate,
                horizontalAccuracy: CLLocationAccuracy(ping.accuracy),
                status: UserStatus(code: ping.statusCode),
                batteryLevel: Float(ping.batteryLevel) / 100.0,
                heading: CLLocationDirection(ping.heading),
                isDirectPeer: envelope.hopCount == 0,
                rssi: inbound.receivedRssi
            )
            sessionViewModel.updateMember(member)
            
            await relayMeshPacketIfNeeded(inbound, for: session)
            
        case .meetingUpdate:
            guard let update = try? MeetingUpdatePayload.deserialize(from: decrypted) else { return }
            switch update.action {
            case .propose:
                let mp = MeetingPoint(
                    id: update.meetingPointId,
                    name: "Festival Rendezvous",
                    coordinate: update.coordinate,
                    targetTime: update.meetupTime,
                    proposerId: update.senderId,
                    landmarkId: update.landmarkId,
                    attendance: [update.senderId: update.attendanceStatus]
                )
                meetingPointViewModel.activeMeetingPoint = mp
            case .cancel:
                if meetingPointViewModel.activeMeetingPoint?.id == update.meetingPointId {
                    meetingPointViewModel.cancelMeetingPoint()
                }
            case .accept, .decline:
                if var mp = meetingPointViewModel.activeMeetingPoint, mp.id == update.meetingPointId {
                    mp.attendance[update.senderId] = update.attendanceStatus
                    meetingPointViewModel.activeMeetingPoint = mp
                }
            }
            
            await relayMeshPacketIfNeeded(inbound, for: session)
            
        default:
            break
        }
    }
    
    // MARK: - Multi-Hop Mesh Forwarding
    
    @MainActor
    private func relayMeshPacketIfNeeded(_ inbound: InboundPacket, for session: GroupSession) async {
        let envelope = inbound.rawPacket.envelope
        guard envelope.hopCount < envelope.hopLimit else { return }
        
        // Prevent forwarding packets that originated locally on this device
        let memberSlot = UInt8(session.localMemberId & 0xFF)
        if envelope.memberSlot == memberSlot {
            return
        }
        
        // Prevent routing loops: relay each unique session sequence number at most once
        let cacheKey = "\(envelope.sessionId)-\(envelope.sequenceNumber)"
        if relayedPacketCache.contains(cacheKey) {
            return
        }
        relayedPacketCache.insert(cacheKey)
        
        // Bounded cache maintenance
        if relayedPacketCache.count > 1000 {
            relayedPacketCache.removeAll()
        }
        
        var relayedEnvelope = envelope
        relayedEnvelope.hopCount &+= 1
        
        let relayedWirePacket = RawWirePacket(
            envelope: relayedEnvelope,
            ciphertext: inbound.rawPacket.ciphertext,
            authTag: inbound.rawPacket.authTag
        )
        
        do {
            let wireData = try relayedWirePacket.toWireData()
            try await peerTransport.broadcastPacket(wireData)
        } catch {
            print("[TeeKumApp] Failed to relay mesh packet: \(error)")
        }
    }
    
    @MainActor
    private func handlePeerUpdates(_ peers: [PeerInfo], for session: GroupSession) {
        for peer in peers {
            guard let peerIdNum = UInt32(peer.id, radix: 16), peerIdNum != session.localMemberId else { continue }
            if let idx = sessionViewModel.members.firstIndex(where: { $0.id == peerIdNum }) {
                var m = sessionViewModel.members[idx]
                if !peer.displayName.isEmpty {
                    m.name = peer.displayName
                }
                m.isDirectPeer = peer.isDirectLink
                m.rssi = peer.rssi
                sessionViewModel.updateMember(m)
            } else {
                let m = Member(
                    id: peerIdNum,
                    name: peer.displayName.isEmpty ? "Friend \(String(format: "%04X", peerIdNum & 0xFFFF))" : peer.displayName,
                    lastSeen: peer.lastSeen,
                    isDirectPeer: peer.isDirectLink,
                    rssi: peer.rssi
                )
                sessionViewModel.updateMember(m)
            }
        }
    }
    
    private func handleIncomingURL(_ url: URL) {
        if let invite = GroupSession.parseInvite(from: url) {
            let name = sessionViewModel.localUserName.isEmpty ? "Friend" : sessionViewModel.localUserName
            sessionViewModel.joinGroup(invite: invite, localName: name)
        }
    }
}
