//
//  PacketRouter.swift
//  TeeKum Prototype
//
//  Created by Fantasix Team.
//

import Foundation
import CoreLocation
import CryptoKit

/// Authoritative coordinator responsible for inbound 56-byte binary datagram routing.
///
/// Responsibilities:
/// 1. Demuxes 8 PacketTypes (0x01..0x08) to corresponding domain ViewModels and Engines.
/// 2. Performs authenticated ChaCha20-Poly1305 decryption against session symmetric key.
/// 3. Executes zero-knowledge blind relaying for stranger packets across the communal mesh.
/// 4. Manages multi-hop relay loop suppression via `SeenPacketCache` and hop count limits.
/// 5. Dispatches in-app notifications for incoming chat and meeting proposals.
@MainActor
public final class PacketRouter {
    
    // MARK: - Dependencies
    
    private let cryptoService: CryptoServiceProvider
    private let peerTransport: any PeerTransport & MeshTransport
    private let relayPolicyManager: RelayPolicyManager
    private let routeDiscoveryService: RouteDiscoveryService
    private let chatMessageEngine: ChatMessageEngine
    private let seenPacketCache: SeenPacketCache
    
    // Feature ViewModels / Presenters
    private weak var sessionViewModel: GroupSessionViewModel?
    private weak var sosViewModel: SOSViewModel?
    private weak var meetingPointViewModel: MeetingPointViewModel?
    private weak var chatViewModel: ChatViewModel?
    
    // MARK: - Initialization
    
    public init(
        cryptoService: CryptoServiceProvider,
        peerTransport: any PeerTransport & MeshTransport,
        relayPolicyManager: RelayPolicyManager,
        routeDiscoveryService: RouteDiscoveryService,
        chatMessageEngine: ChatMessageEngine,
        seenPacketCache: SeenPacketCache,
        sessionViewModel: GroupSessionViewModel,
        sosViewModel: SOSViewModel,
        meetingPointViewModel: MeetingPointViewModel,
        chatViewModel: ChatViewModel
    ) {
        self.cryptoService = cryptoService
        self.peerTransport = peerTransport
        self.relayPolicyManager = relayPolicyManager
        self.routeDiscoveryService = routeDiscoveryService
        self.chatMessageEngine = chatMessageEngine
        self.seenPacketCache = seenPacketCache
        self.sessionViewModel = sessionViewModel
        self.sosViewModel = sosViewModel
        self.meetingPointViewModel = meetingPointViewModel
        self.chatViewModel = chatViewModel
    }
    
    // MARK: - Primary Inbound Routing
    
    /// Routes an incoming datagram from `peerTransport.inboundPackets`.
    public func routeInboundPacket(_ inbound: InboundPacket, for session: GroupSession) async {
        let raw = inbound.rawPacket
        let envelope = raw.envelope
        
        // 1. Stranger Packet Check: Route to Communal Relay if SID does not match
        guard envelope.sessionId == session.sessionId else {
            await handleStrangerRelayPacket(inbound)
            return
        }
        
        // 2. Immediate ACK Processing (SOS delivery tracking & Chat per-recipient receipts)
        if envelope.type == .ack {
            guard let payload = try? await cryptoService.open(
                ciphertext: raw.ciphertext, envelope: envelope, authTag: raw.authTag,
                using: SymmetricKey(data: session.symmetricKeyData)
            ), let ack = try? ACKPayload.deserialize(from: payload),
                abs(Date().timeIntervalSince(ack.ackTimestamp)) <= CarryMessageStore.retention,
                ack.responderInitials != session.localInitials else { return }
            await sosViewModel?.processInboundPacket(inbound)
            _ = await chatMessageEngine.processDeliveryACK(rawPacket: raw, fromPeerId: inbound.sourcePeerId)
            await peerTransport.retainReceivedForCarry(raw, excludingPeerId: inbound.sourcePeerId)
            await relayMeshPacketIfNeeded(inbound, for: session)
            return
        }
        
        // 3. Process SOS Packets through SOSViewModel (triggers sirens, haptics, incoming alert HUD)
        if envelope.type == .sos {
            await sosViewModel?.processInboundPacket(inbound)
        }
        
        // 4. Authenticated AEAD Decryption with Session Symmetric Key
        let key = SymmetricKey(data: session.symmetricKeyData)
        guard let decrypted = try? await cryptoService.open(
            ciphertext: raw.ciphertext,
            envelope: envelope,
            authTag: raw.authTag,
            using: key
        ) else {
            // Decryption failure fallback: If packet is an emergency SOS, still relay multi-hop
            if envelope.type == .sos {
                await relayMeshPacketIfNeeded(inbound, for: session)
            }
            return
        }
        
        // 5. Payload Demux by Type
        switch envelope.type {
        case .sos:
            await handleDecryptedSOS(decrypted, inbound: inbound, session: session)
            await relayMeshPacketIfNeeded(inbound, for: session)
            
        case .locationPing:
            handleDecryptedLocationPing(decrypted, inbound: inbound, session: session)
            await relayMeshPacketIfNeeded(inbound, for: session)
            
        case .meetingUpdate:
            handleDecryptedMeetingUpdate(decrypted, session: session)
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
            
        case .chatMessage:
            guard let chat = try? ChatMessagePayload.deserialize(from: decrypted),
                  abs(Date().timeIntervalSince(chat.timestamp)) <= CarryMessageStore.retention,
                  chat.senderInitials != session.localInitials else { return }
            await peerTransport.retainReceivedForCarry(raw, excludingPeerId: inbound.sourcePeerId)
            await handleDecryptedChatMessage(inbound: inbound)
            await relayMeshPacketIfNeeded(inbound, for: session)
            
        default:
            break
        }
    }
    
    // MARK: - Decrypted Payload Handlers
    
    private func handleDecryptedSOS(_ decrypted: Data, inbound: InboundPacket, session: GroupSession) async {
        guard let sos = try? SOSPayload.deserialize(from: decrypted) else { return }
        guard sos.senderInitials != session.localInitials else { return }
        
        let resolvedName = sos.senderInitials
        let memberColor = MemberColor.resolve(code: sos.colorCode, initials: sos.senderInitials)
        
        let member = Member(
            id: sos.senderInitials,
            name: resolvedName,
            lastSeen: inbound.receivedAt,
            coordinate: sos.coordinate,
            horizontalAccuracy: CLLocationAccuracy(sos.accuracy),
            isEmergency: true,
            batteryLevel: Float(sos.batteryLevel) / 100.0,
            heading: sessionViewModel?.members.first(where: { $0.id == sos.senderInitials })?.heading,
            isDirectPeer: inbound.rawPacket.envelope.hopCount == 0,
            rssi: inbound.receivedRssi,
            color: memberColor
        )
        sessionViewModel?.updateMember(member)
        
        // Update sender label on incoming emergency banner
        if var alert = sosViewModel?.activeIncomingAlert, alert.id == sos.sosEventId {
            alert.senderName = resolvedName
            sosViewModel?.activeIncomingAlert = alert
        }
    }
    
    private func handleDecryptedLocationPing(_ decrypted: Data, inbound: InboundPacket, session: GroupSession) {
        guard let ping = try? LocationPingPayload.deserialize(from: decrypted) else { return }
        guard ping.senderInitials != session.localInitials else { return }
        
        let resolvedName = ping.senderInitials
        let memberColor = MemberColor.resolve(code: ping.colorCode, initials: ping.senderInitials)
        let existingEmergency = sessionViewModel?.members.first(where: { $0.id == ping.senderInitials })?.isEmergency ?? false
        
        let member = Member(
            id: ping.senderInitials,
            name: resolvedName,
            lastSeen: inbound.receivedAt,
            coordinate: ping.coordinate,
            horizontalAccuracy: CLLocationAccuracy(ping.accuracy),
            isEmergency: existingEmergency,
            batteryLevel: Float(ping.batteryLevel) / 100.0,
            heading: ping.headingDegrees,
            isDirectPeer: inbound.rawPacket.envelope.hopCount == 0,
            rssi: inbound.receivedRssi,
            color: memberColor
        )
        sessionViewModel?.updateMember(member)
    }
    
    private func handleDecryptedMeetingUpdate(_ decrypted: Data, session: GroupSession) {
        guard let update = try? MeetingUpdatePayload.deserialize(from: decrypted) else { return }
        guard let applied = meetingPointViewModel?.applyInboundUpdate(update), applied else { return }
        
        if update.senderInitials != session.localInitials {
            let actionText: String
            switch update.action {
            case .propose: actionText = "proposed rendezvous"
            case .accept:  actionText = "is attending"
            case .cancel:  actionText = "canceled rendezvous"
            case .decline: actionText = "declined"
            }
            
            let displayTitle = meetingPointViewModel?.activeMeetingPoint?.formattedTitle ?? "\(update.senderInitials)'s Rendezvous"
            NotificationService.shared.notifyMeetingPoint(
                proposerInitials: update.senderInitials,
                meetingPointName: displayTitle,
                actionName: actionText
            )
        }
    }
    
    private func handleDecryptedChatMessage(inbound: InboundPacket) async {
        guard let outcome = try? await chatMessageEngine.handleInboundPacket(inbound) else { return }
        
        switch outcome {
        case .deliveredLocally(let message), .deliveredLocallyAndRelayed(let message, _):
            if !message.isLocalSender {
                let isSheetOpen = chatViewModel?.isChatSheetPresented ?? false
                NotificationService.shared.notifyChatMessage(
                    senderInitials: message.senderInitials,
                    text: message.text,
                    isSheetOpen: isSheetOpen,
                    onTap: { [weak chatViewModel] in
                        chatViewModel?.isChatSheetPresented = true
                    }
                )
            }
        default:
            break
        }
    }
    
    // MARK: - Multi-Hop Group Relay
    
    /// Relays encrypted in-group packets to all peer connections if hop budget remains.
    public func relayMeshPacketIfNeeded(_ inbound: InboundPacket, for session: GroupSession) async {
        let envelope = inbound.rawPacket.envelope
        guard envelope.hopCount < envelope.hopLimit else { return }
        
        // Prevent forwarding packets originating locally on this device
        if envelope.memberSlot == session.memberSlot {
            return
        }
        
        // Prevent routing loops: deduplicate via 1,024-entry LRU cache
        let packetKey = PacketKey(wirePacket: inbound.rawPacket)
        let isDuplicate = await seenPacketCache.isDuplicateAndRecord(packetKey)
        if isDuplicate {
            return
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
            print("[PacketRouter] Failed to relay mesh packet: \(error)")
        }
    }
    
    // MARK: - Stranger Mesh Packet Relay (Zero-Knowledge)
    
    /// Relays foreign packets across the communal mesh without decrypting or logging content.
    public func handleStrangerRelayPacket(_ inbound: InboundPacket) async {
        let envelope = inbound.rawPacket.envelope
        
        // 1. Verify communal relay policy permits relaying (opt-in + battery > 20%)
        let policyState = await relayPolicyManager.currentState()
        guard policyState.isRelayPermitted else {
            await relayPolicyManager.recordDropEvent(reason: .policyDisabled)
            return
        }
        
        // 2. Bound hop limit enforcement (max 8 hops)
        guard envelope.hopCount < envelope.hopLimit else {
            await relayPolicyManager.recordDropEvent(reason: .hopLimitExceeded)
            return
        }
        
        await peerTransport.retainReceivedForCarry(inbound.rawPacket, excludingPeerId: inbound.sourcePeerId)

        // 3. Deduplicate via 5-minute LRU cache
        let packetKey = PacketKey(wirePacket: inbound.rawPacket)
        let isDuplicate = await seenPacketCache.isDuplicateAndRecord(packetKey)
        if isDuplicate {
            await relayPolicyManager.recordDropEvent(reason: .duplicate)
            return
        }
        
        // 4. Rate-limited blind forwarding to neighboring direct links
        do {
            let wireData = try inbound.rawPacket.toWireData()
            let directPeers = await peerTransport.activeNeighbors()
            let eligible = directPeers.filter { $0.id != inbound.sourcePeerId }
            var forwarded = false
            for peer in eligible {
                do {
                    _ = try await peerTransport.forwardFrame(wireData, to: peer.id)
                    forwarded = true
                } catch {
                    print("[PacketRouter] Forward to stranger relay peer \(peer.id) failed: \(error)")
                }
            }
            if forwarded {
                await relayPolicyManager.recordForwardEvent(type: envelope.type)
            }
        } catch {
            print("[PacketRouter] Stranger relay dropped: \(error)")
        }
    }
}
