//
//  MeetingPointViewModel.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import Observation
import CoreLocation
import CryptoKit

/// Pure MVVM ViewModel governing the Single Active Meeting Point and 1-tap attendance synchronization.
@Observable
@MainActor
public final class MeetingPointViewModel {
    /// Strictly ONE active meeting point per group at any given time.
    public var activeMeetingPoint: MeetingPoint?
    
    /// User attendance response to the current active proposal.
    public var localAttendanceStatus: AttendanceStatus?
    
    // MARK: - Injected Dependencies
    public var sessionProvider: (@Sendable () -> GroupSession?)?
    public var cryptoService: CryptoServiceProvider?
    public var transport: PeerTransport?
    
    /// Monotonic sequence counter for outbound meeting packets
    private var monotonicCounter: UInt32 = 1
    
    public init(
        activeMeetingPoint: MeetingPoint? = nil,
        sessionProvider: (@Sendable () -> GroupSession?)? = nil,
        cryptoService: CryptoServiceProvider? = nil,
        transport: PeerTransport? = nil
    ) {
        self.activeMeetingPoint = activeMeetingPoint
        self.sessionProvider = sessionProvider
        self.cryptoService = cryptoService
        self.transport = transport
    }
    
    /// Reconfigures session dependencies.
    public func configure(
        sessionProvider: (@Sendable () -> GroupSession?)? = nil,
        cryptoService: CryptoServiceProvider? = nil,
        transport: PeerTransport? = nil
    ) {
        if let sessionProvider { self.sessionProvider = sessionProvider }
        if let cryptoService { self.cryptoService = cryptoService }
        if let transport { self.transport = transport }
    }
    
    /// Resets all meeting state and dependency references upon session teardown.
    public func reset() {
        self.activeMeetingPoint = nil
        self.localAttendanceStatus = nil
        self.sessionProvider = nil
        self.cryptoService = nil
        self.transport = nil
    }
    
    /// Proposes a new rendezvous point (replaces any previous active meeting point)
    /// and broadcasts the proposal over the mesh network with a higher TTL (15 hops).
    public func proposeMeetingPoint(
        name: String,
        coordinate: CLLocationCoordinate2D,
        targetTime: Date? = nil,
        proposerId: String,
        landmarkId: UInt32? = nil
    ) {
        let point = MeetingPoint(
            name: name,
            coordinate: coordinate,
            targetTime: targetTime,
            proposerId: proposerId,
            landmarkId: landmarkId,
            attendance: [proposerId: .attending]
        )
        self.activeMeetingPoint = point
        self.localAttendanceStatus = .attending
        
        Task { [weak self] in
            await self?.broadcastMeetingUpdate(action: .propose, meetingPoint: point)
        }
    }
    
    /// Responds with 1-tap confirmation and broadcasts attendance to the mesh.
    public func respond(status: AttendanceStatus, memberId: String) {
        guard var point = activeMeetingPoint else { return }
        point.attendance[memberId] = status
        self.activeMeetingPoint = point
        self.localAttendanceStatus = status
        
        let action: MeetingAction = (status == .attending) ? .accept : .decline
        Task { [weak self] in
            await self?.broadcastMeetingUpdate(action: action, meetingPoint: point)
        }
    }
    
    /// Cancels the current meeting point and broadcasts cancellation over the mesh.
    public func cancelMeetingPoint() {
        guard let point = activeMeetingPoint else { return }
        self.activeMeetingPoint = nil
        self.localAttendanceStatus = nil
        
        Task { [weak self] in
            await self?.broadcastMeetingUpdate(action: .cancel, meetingPoint: point)
        }
    }
    
    /// Syncs the current active meeting point to newly connected or late-joining peers.
    public func syncActiveMeetingPointToPeers() async {
        guard let point = activeMeetingPoint else { return }
        await broadcastMeetingUpdate(action: .propose, meetingPoint: point)
    }
    
    /// Applies an authenticated inbound meeting update received over the mesh (without re-broadcasting).
    public func applyInboundUpdate(_ update: MeetingUpdatePayload) {
        switch update.action {
        case .propose:
            let displayName = VenueLandmark.preset(for: update.landmarkId)?.name ?? update.customLabel ?? "Festival Rendezvous"
            let mp = MeetingPoint(
                id: update.meetingPointId,
                name: displayName,
                coordinate: update.coordinate,
                targetTime: update.meetupTime,
                proposerId: update.senderInitials,
                landmarkId: update.landmarkId,
                attendance: [update.senderInitials: update.attendanceStatus]
            )
            self.activeMeetingPoint = mp
            // If the local user is not the proposer, reset local attendance so they can respond
            if let localInitials = sessionProvider?()?.localInitials, update.senderInitials != localInitials {
                self.localAttendanceStatus = nil
            }
            
        case .cancel:
            if activeMeetingPoint?.id == update.meetingPointId {
                self.activeMeetingPoint = nil
                self.localAttendanceStatus = nil
            }
            
        case .accept, .decline:
            if var mp = activeMeetingPoint, mp.id == update.meetingPointId {
                mp.attendance[update.senderInitials] = update.attendanceStatus
                self.activeMeetingPoint = mp
                if let localInitials = sessionProvider?()?.localInitials, update.senderInitials == localInitials {
                    self.localAttendanceStatus = update.attendanceStatus
                }
            }
        }
    }
    
    /// Assembles, cryptographically seals, and broadcasts a 56-byte meeting wire packet.
    /// Setting or updating the meeting point uses a higher TTL (hopLimit = 15) to propagate
    /// across wide multi-kilometer festival grounds.
    public func broadcastMeetingUpdate(action: MeetingAction, meetingPoint: MeetingPoint) async {
        guard let session = sessionProvider?(), let cryptoService, let transport else {
            return
        }
        
        let payload = MeetingUpdatePayload(
            coordinate: meetingPoint.coordinate,
            meetupTime: meetingPoint.targetTime ?? Date(),
            action: action,
            attendanceStatus: localAttendanceStatus ?? .attending,
            meetingPointId: meetingPoint.id,
            senderInitials: session.localInitials,
            landmarkId: meetingPoint.landmarkId,
            customLabel: meetingPoint.name
        )
        
        let payloadData = payload.serialize()
        let memberSlot = session.memberSlot
        let seq = CleartextEnvelope.makeSequenceNumber(memberSlot: memberSlot, counter: monotonicCounter)
        monotonicCounter &+= 1
        
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .meetingUpdate,
            hopLimit: PacketConstants.meetingPointHopLimit, // Higher TTL: 15 hops instead of 8
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: seq
        )
        
        do {
            let key = SymmetricKey(data: session.symmetricKeyData)
            let sealed = try await cryptoService.seal(payload: payloadData, envelope: envelope, using: key)
            let wirePacket = RawWirePacket(envelope: envelope, ciphertext: sealed.ciphertext, authTag: sealed.authTag)
            let wireData = try wirePacket.toWireData()
            
            // Broadcast packet into urgent priority queue
            try await transport.broadcastPacket(wireData)
        } catch {
            print("[MeetingPointViewModel] Failed to broadcast meeting update: \(error)")
        }
    }
}
