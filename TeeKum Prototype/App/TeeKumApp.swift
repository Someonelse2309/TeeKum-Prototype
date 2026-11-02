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
    @Environment(\.scenePhase) private var scenePhase
    @State private var sessionViewModel = GroupSessionViewModel()
    @State private var locationService: LocationService
    @State private var mapViewModel: MapViewModel
    @State private var sosViewModel = SOSViewModel()
    @State private var meetingPointViewModel = MeetingPointViewModel()
    @State private var locationPublisher: LocationPublisher?
    @State private var relayedPacketCache: Set<String> = []
    private let cryptoService = CryptoService()
    private let peerTransport: PeerTransportService
    private let relayPolicyManager: RelayPolicyManager
    private let routingTable: RoutingTable
    private let routeDiscoveryService: RouteDiscoveryService
    
    init() {
        let service = LocationService()
        _locationService = State(initialValue: service)
        _mapViewModel = State(initialValue: MapViewModel(locationService: service))
        let transport = PeerTransportService()
        self.peerTransport = transport
        self.relayPolicyManager = RelayPolicyManager(transport: transport)
        let routing = RoutingTable()
        self.routingTable = routing
        self.routeDiscoveryService = RouteDiscoveryService(
            routingTable: routing,
            neighborTable: transport.neighborTable,
            transport: transport,
            cryptoService: cryptoService
        )
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if sessionViewModel.hasActiveSession, let session = sessionViewModel.activeSession {
                    MainMapView(
                        mapViewModel: mapViewModel,
                        sessionViewModel: sessionViewModel,
                        sosViewModel: sosViewModel,
                        meetingPointViewModel: meetingPointViewModel,
                        relayPolicyManager: relayPolicyManager,
                        peerTransport: peerTransport
                    )
                    .task(id: session.sessionId) {
                        await runSessionLifecycle(session: session)
                    }
                } else {
                    GroupPairingView(
                        sessionViewModel: sessionViewModel,
                        relayPolicyManager: relayPolicyManager,
                        peerTransport: peerTransport
                    )
                        .task {
                            await stopActiveSession()
                        }
                }
            }
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && sessionViewModel.hasActiveSession {
                    locationService.publishCurrentState()
                }
            }
            .onChange(of: locationService.currentBatteryLevel) { _, level in
                Task {
                    await relayPolicyManager.updatePowerMetrics(
                        batteryLevel: level,
                        isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
                    )
                    await updateLiveActivityTelemetry()
                }
            }
            .onChange(of: locationService.isSurvivalModeActive) { _, isSurvival in
                Task {
                    await relayPolicyManager.updatePowerMetrics(
                        batteryLevel: locationService.currentBatteryLevel,
                        isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
                    )
                    if isSurvival {
                        await LiveActivityManager.shared.endSessionActivity()
                    }
                    await updateLiveActivityTelemetry()
                }
            }
            .onChange(of: meetingPointViewModel.activeMeetingPoint) { _, _ in
                Task {
                    await updateLiveActivityTelemetry()
                }
            }
            .onChange(of: sosViewModel.activeIncomingAlert) { _, _ in
                Task {
                    await updateLiveActivityTelemetry()
                }
            }
            .onChange(of: sosViewModel.deliveryState) { _, _ in
                Task {
                    await updateLiveActivityTelemetry()
                }
            }
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
                    _ = await NeighborDiscoveryTests.runAllTests()
                    fflush(stdout)
                    _ = await RoutingForwardingTests.runAllTests()
                    fflush(stdout)
                    _ = await RouteDiscoveryTests.runAllTests()
                    fflush(stdout)
                    _ = await CryptoSecurityTests.runAllTests()
                    fflush(stdout)
                    _ = await LocationPublishingTests.runAllTests()
                    fflush(stdout)
                    _ = await UIStateTests.runAllTests()
                    fflush(stdout)
                    _ = await SOSEndToEndTests.runAllTests()
                    fflush(stdout)
                    _ = await MultiHopSOSTests.runAllTests()
                    fflush(stdout)
                    _ = await LiveActivityTests.runAllTests()
                    fflush(stdout)
                    _ = await RelayPolicyTests.runAllTests()
                    fflush(stdout)
                    _ = await MeshFailureIntegrationTests.runAllTests()
                    fflush(stdout)
                    _ = await MeshDebuggerTests.runAllTests()
                    fflush(stdout)
                    print(">>> ALL AUTOMATED TEST RUNS FINISHED <<<")
                    fflush(stdout)
                } else {
                    if ProcessInfo.processInfo.arguments.contains("-runMeshDebuggerTests") {
                        _ = await MeshDebuggerTests.runAllTests()
                        fflush(stdout)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-runMeshFailureTests") {
                        _ = await MeshFailureIntegrationTests.runAllTests()
                        fflush(stdout)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-runUITests") {
                        _ = await UIStateTests.runAllTests()
                        fflush(stdout)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-runSOSTests") {
                        _ = await SOSEndToEndTests.runAllTests()
                        fflush(stdout)
                        _ = await MultiHopSOSTests.runAllTests()
                        fflush(stdout)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-runMultiHopSOSTests") {
                        _ = await MultiHopSOSTests.runAllTests()
                        fflush(stdout)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-runRelayPolicyTests") {
                        _ = await RelayPolicyTests.runAllTests()
                        fflush(stdout)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-simulateSession") {
                        let dummyKey = Data(repeating: 0x55, count: 32)
                        let session = GroupSession(
                            sessionId: 0x4321,
                            sessionName: "Festival Crew",
                            symmetricKeyData: dummyKey,
                            localInitials: "NIC"
                        )
                        sessionViewModel.setActiveSession(session)
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
        
        // 2. Start Live Activity Companion
        await LiveActivityManager.shared.startSessionActivity(session: session)
        
        // 3. Configure SOS
        sosViewModel.configure(
            locationService: locationService,
            sessionProvider: { session },
            cryptoService: cryptoService,
            transport: peerTransport,
            memberNameResolver: { senderInitials in
                senderInitials
            }
        )
        
        // 4. Configure Meeting Point
        meetingPointViewModel.configure(
            sessionProvider: { session },
            cryptoService: cryptoService,
            transport: peerTransport
        )
        
        // 4. Start Radio Transport
        do {
            // Synchronize in-memory relay policy manager if user opted into Communal Mesh Compact
            let savedModeRaw = UserDefaults.standard.string(forKey: "com.teekum.relay.participationMode")
            if let savedMode = RelayParticipationMode(rawValue: savedModeRaw ?? ""), savedMode == .communalRelayActive {
                await relayPolicyManager.setParticipationMode(.communalRelayActive)
            }
            
            try await peerTransport.start(serviceType: "_teekum._tcp", session: session)
            let policyState = await relayPolicyManager.currentState()
            await peerTransport.setRelayParticipation(enabled: policyState.isRelayPermitted)
        } catch {
            print("[TeeKumApp] Radio transport failed to start: \(error)")
        }
        
        // 4. Configure Adaptive Distant & Stale Peer Cadence & Publisher
        await routeDiscoveryService.setOnTargetReached { [weak locationService] originator in
            Task { @MainActor in
                locationService?.triggerBurstPings(
                    count: MeshTimingConfiguration.default.staleResponseBurstCount,
                    interval: MeshTimingConfiguration.default.staleResponseBurstInterval
                )
            }
        }
        
        locationService.hasDistantPeersProvider = { [weak sessionViewModel, weak locationService] in
            guard let sessionViewModel else { return false }
            
            // Check if any friend pin is beyond the distant threshold (e.g. 30m)
            if let localCoord = locationService?.currentLocation?.coordinate {
                let localLoc = CLLocation(latitude: localCoord.latitude, longitude: localCoord.longitude)
                let threshold = MeshTimingConfiguration.default.distantDistanceThresholdMeters
                for member in sessionViewModel.members {
                    if let coord = member.coordinate {
                        let memberLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                        if localLoc.distance(from: memberLoc) >= threshold {
                            return true
                        }
                    }
                }
            }
            
            // Check if any peer has low RSSI <= threshold (e.g. -75 dBm)
            let rssiThreshold = MeshTimingConfiguration.default.distantRSSIThreshold
            for member in sessionViewModel.members {
                if let rssi = member.rssi, rssi <= rssiThreshold {
                    return true
                }
            }
            
            return false
        }
        
        locationService.hasStalePeersProvider = { [weak sessionViewModel] in
            guard let sessionViewModel else { return false }
            let now = Date()
            let timing = MeshTimingConfiguration.default
            return sessionViewModel.members.contains {
                $0.isWithinStaleRecoveryWindow(
                    now: now,
                    staleThreshold: timing.stalePeerThreshold,
                    recoveryTimeout: timing.staleRecoveryTimeout
                )
            }
        }
        
        let publisher = LocationPublisher(
            locationService: locationService,
            sessionProvider: { session },
            cryptoService: cryptoService,
            transport: peerTransport
        )
        self.locationPublisher = publisher
        publisher.start()
        
        // 5. Inbound Packets, Peer Updates, and Stale Supervisor
        let inboundStream = await peerTransport.inboundPackets
        let peerUpdatesStream = await peerTransport.peerUpdates
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await inbound in inboundStream {
                    guard !Task.isCancelled else { break }
                    await handleInboundPacket(inbound, for: session)
                }
            }
            
            group.addTask { @MainActor in
                for await peers in peerUpdatesStream {
                    guard !Task.isCancelled else { break }
                    handlePeerUpdates(peers, for: session)
                    if peers.contains(where: { $0.isDirectLink }) {
                        locationService.publishCurrentState()
                        await meetingPointViewModel.syncActiveMeetingPointToPeers()
                    }
                }
            }
            
            // 6. Stale Peer Accelerated Cadence & Two-Tier AODV Probe Supervisor
            group.addTask { @MainActor in
                var lastGlobalRouteReqDispatch: Date = .distantPast
                var lastRouteReqTimes: [String: Date] = [:]
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { break }
                    
                    let now = Date()
                    let timing = MeshTimingConfiguration.default
                    
                    // Stage 1 Check: Accelerate cadence while any peer is stale within recovery window (30s < age <= 90s)
                    let anyStale = sessionViewModel.members.contains {
                        $0.isWithinStaleRecoveryWindow(
                            now: now,
                            staleThreshold: timing.stalePeerThreshold,
                            recoveryTimeout: timing.staleRecoveryTimeout
                        )
                    }
                    if anyStale != locationService.hasStalePeers {
                        locationService.hasStalePeers = anyStale
                        if anyStale {
                            locationService.triggerCadenceEvaluation()
                        }
                    }
                    
                    // Stage 2 Check: On-demand AODV ROUTE_REQ staggered across multiple stale peers
                    if now.timeIntervalSince(lastGlobalRouteReqDispatch) >= timing.staleRouteReqStaggerInterval {
                        let eligibleMembers = sessionViewModel.members.filter {
                            $0.isEligibleForStaleRouteDiscovery(
                                now: now,
                                staleThreshold: timing.stalePeerThreshold,
                                routeReqDelay: timing.staleRouteReqDelay,
                                recoveryTimeout: timing.staleRecoveryTimeout
                            ) && now.timeIntervalSince(lastRouteReqTimes[$0.id] ?? .distantPast) >= 10.0
                        }.sorted { $0.lastSeen < $1.lastSeen }
                        
                        if let target = eligibleMembers.first {
                            lastGlobalRouteReqDispatch = now
                            lastRouteReqTimes[target.id] = now
                            Task {
                                _ = try? await routeDiscoveryService.initiateDiscovery(
                                    to: target.id,
                                    session: session,
                                    timeout: 3.0
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    private func stopActiveSession() async {
        await LiveActivityManager.shared.endSessionActivity()
        locationPublisher?.stop()
        locationPublisher = nil
        await peerTransport.stop()
        await routeDiscoveryService.setOnTargetReached(nil)
        await routeDiscoveryService.teardown(sessionId: nil)
        locationService.stopTracking()
        locationService.hasDistantPeers = false
        locationService.hasDistantPeersProvider = nil
        locationService.hasStalePeers = false
        locationService.hasStalePeersProvider = nil
        locationService.updateStatus(UserStatus(code: .available))
        sosViewModel.stopListening()
        sosViewModel.reset()
        sosViewModel.dismissIncomingAlert()
        meetingPointViewModel.reset()
        mapViewModel.selectedMember = nil
        relayedPacketCache.removeAll()
    }
    
    // MARK: - Inbound Packet Dispatching
    
    @MainActor
    private func handleInboundPacket(_ inbound: InboundPacket, for session: GroupSession) async {
        let raw = inbound.rawPacket
        let envelope = raw.envelope
        
        guard envelope.sessionId == session.sessionId else {
            // Stranger Packet Relaying (Agent 5: Governed by RelayPolicyManager)
            await handleStrangerRelayPacket(inbound)
            return
        }
        
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
                guard sos.senderInitials != session.localInitials else { return }
                
                let resolvedName = sos.senderInitials
                
                let member = Member(
                    id: sos.senderInitials,
                    name: resolvedName,
                    lastSeen: inbound.receivedAt,
                    coordinate: sos.coordinate,
                    horizontalAccuracy: CLLocationAccuracy(sos.accuracy),
                    status: UserStatus(code: .sos),
                    batteryLevel: Float(sos.batteryLevel) / 100.0,
                    heading: sessionViewModel.members.first(where: { $0.id == sos.senderInitials })?.heading,
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
            guard ping.senderInitials != session.localInitials else { return }
            
            let resolvedName = ping.senderInitials
            
            let member = Member(
                id: ping.senderInitials,
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
            meetingPointViewModel.applyInboundUpdate(update)
            await relayMeshPacketIfNeeded(inbound, for: session)
            
        case .routeReq:
            if let wireData = try? inbound.rawPacket.toWireData() {
                _ = try? await routeDiscoveryService.handleInboundRouteReq(
                    wireData: wireData,
                    fromPeerId: inbound.sourcePeerId,
                    session: session
                )
            }
            
        case .routeResp:
            if let wireData = try? inbound.rawPacket.toWireData() {
                _ = try? await routeDiscoveryService.handleInboundRouteResp(
                    wireData: wireData,
                    fromPeerId: inbound.sourcePeerId,
                    session: session
                )
            }
            
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
        let memberSlot = session.memberSlot
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
    
    // MARK: - Stranger Mesh Packet Relay (Agent 5)
    
    @MainActor
    private func handleStrangerRelayPacket(_ inbound: InboundPacket) async {
        let envelope = inbound.rawPacket.envelope
        
        // 1. Verify policy permits stranger relaying (Opt-in & Battery cut-off)
        let policyState = await relayPolicyManager.currentState()
        guard policyState.isRelayPermitted else {
            await relayPolicyManager.recordDropEvent(reason: .policyDisabled)
            return
        }
        
        // 2. Hop limit bound enforcement (max 8 hops)
        guard envelope.hopCount < envelope.hopLimit else {
            await relayPolicyManager.recordDropEvent(reason: .hopLimitExceeded)
            return
        }
        
        // 3. Deduplicate (5-minute LRU window)
        let cacheKey = "\(envelope.sessionId)-\(envelope.sequenceNumber)"
        if relayedPacketCache.contains(cacheKey) {
            await relayPolicyManager.recordDropEvent(reason: .duplicate)
            return
        }
        relayedPacketCache.insert(cacheKey)
        if relayedPacketCache.count > 1000 { relayedPacketCache.removeAll() }
        
        // 4. Rate-limited blind forwarding via PeerTransportService
        do {
            let wireData = try inbound.rawPacket.toWireData()
            let directPeers = await peerTransport.neighborTable.activeNeighbors()
            let eligible = directPeers.filter { $0.id != inbound.sourcePeerId }
            for peer in eligible {
                do {
                    _ = try await peerTransport.forwardFrame(wireData, to: peer.id)
                } catch {
                    print("[TeeKumApp] Forward to stranger relay peer \(peer.id) failed: \(error)")
                }
            }
            await relayPolicyManager.recordForwardEvent(type: envelope.type)
        } catch {
            print("[TeeKumApp] Stranger relay dropped: \(error)")
        }
    }
    
    @MainActor
    private func handlePeerUpdates(_ peers: [PeerInfo], for session: GroupSession) {
        for peer in peers {
            guard peer.isGroupMember else {
                // Anonymous stranger relay: do NOT expose in member rosters or maps (Zero-Knowledge)
                continue
            }
            guard peer.id != session.localInitials else { continue }
            if let idx = sessionViewModel.members.firstIndex(where: { $0.id == peer.id }) {
                var m = sessionViewModel.members[idx]
                if !peer.displayName.isEmpty {
                    m.name = peer.displayName
                }
                m.isDirectPeer = peer.isDirectLink
                m.rssi = peer.rssi
                if peer.lastSeen > m.lastSeen {
                    m.lastSeen = peer.lastSeen
                }
                sessionViewModel.updateMember(m)
            } else {
                let m = Member(
                    id: peer.id,
                    name: peer.displayName.isEmpty ? peer.id : peer.displayName,
                    lastSeen: peer.lastSeen,
                    isDirectPeer: peer.isDirectLink,
                    rssi: peer.rssi
                )
                sessionViewModel.updateMember(m)
            }
        }
        Task {
            await updateLiveActivityTelemetry()
        }
    }
    
    @MainActor
    private func updateLiveActivityTelemetry() async {
        let directCount = sessionViewModel.members.filter { $0.isDirectPeer }.count
        let isSOS = sosViewModel.activeIncomingAlert != nil || (sosViewModel.deliveryState != .idle && sosViewModel.deliveryState != .searchingPeers)
        let sosSender = sosViewModel.activeIncomingAlert?.senderInitials
        let policyState = await relayPolicyManager.currentState()
        
        let remainingSeconds: Int?
        if let expiry = policyState.timedExpiryDate {
            remainingSeconds = max(0, Int(expiry.timeIntervalSince(Date())))
        } else {
            remainingSeconds = nil
        }
        
        await LiveActivityManager.shared.updateSessionActivity(
            peerCount: directCount,
            meetingPoint: meetingPointViewModel.activeMeetingPoint,
            currentLocation: locationService.currentLocation?.coordinate,
            isSOSActive: isSOS,
            sosSenderInitials: sosSender,
            relayStatusText: policyState.statusDescription(),
            relayModeText: policyState.mode.rawValue,
            timedRelayRemainingSeconds: remainingSeconds,
            isRelayActive: policyState.isRelayPermitted
        )
    }
    
    private func handleIncomingURL(_ url: URL) {
        if url.scheme == "teekum" {
            if url.host == "meeting" {
                // Focused via deep link from Live Activity
                return
            } else if url.host == "sos" {
                // Focused via deep link from Live Activity
                return
            } else if url.host == "relay" {
                // Lock screen deep-link: teekum://relay?action=always / timed / stop
                guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
                let action = components.queryItems?.first(where: { $0.name == "action" })?.value
                Task { @MainActor in
                    if action == "always" {
                        await relayPolicyManager.setParticipationMode(.communalRelayActive)
                    } else if action == "timed" {
                        await relayPolicyManager.setTimedParticipation(durationSeconds: 1800)
                    } else if action == "stop" {
                        await relayPolicyManager.stopRelaying()
                    }
                    await updateLiveActivityTelemetry()
                }
                return
            }
        }
        guard let invite = GroupSession.parseInvite(from: url) else { return }
        sessionViewModel.pendingInvite = invite
    }
}
