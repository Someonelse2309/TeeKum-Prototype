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
    
    // MARK: - Meeting Point Locking & Setter Rules
    
    /// Evaluates whether the specified member initials are permitted to set or update the active rendezvous.
    /// Rule: When someone sets a meeting point, another person cannot set the meeting point
    /// before the setter unsets the meeting point or it auto-expires.
    public func canSetMeetingPoint(by proposerId: String) -> Bool {
        checkExpiration()
        guard let active = activeMeetingPoint, !active.isExpired else {
            // No active rendezvous exists; any group member is free to propose!
            return true
        }
        let sanitized = InitialsCodec.sanitize(proposerId)
        // If an active rendezvous exists, ONLY the original setter is permitted to update or move it.
        return active.proposerId == sanitized
    }
    
    /// Evaluates whether the specified member initials are permitted to unset (cancel) the active rendezvous.
    /// Rule: Only the setter can unset the meeting point.
    public func canUnsetMeetingPoint(by callerId: String) -> Bool {
        guard let active = activeMeetingPoint else { return false }
        let sanitized = InitialsCodec.sanitize(callerId)
        return active.proposerId == sanitized
    }
    
    /// Returns true if an active rendezvous is currently set by someone other than the local user.
    public var isLockedByOtherSetter: Bool {
        checkExpiration()
        guard let active = activeMeetingPoint, !active.isExpired else { return false }
        guard let local = sessionProvider?()?.localInitials else { return false }
        return active.proposerId != InitialsCodec.sanitize(local)
    }
    
    /// Returns true if the active rendezvous was proposed by the local user.
    public var isLocalUserSetter: Bool {
        checkExpiration()
        guard let local = sessionProvider?()?.localInitials else { return false }
        return canUnsetMeetingPoint(by: local)
    }
    
    /// The initials of the member who set the active meeting point, or nil if none.
    public var currentSetterId: String? {
        checkExpiration()
        return activeMeetingPoint?.proposerId
    }
    
    /// Proposes a new rendezvous point (or updates the existing rendezvous if proposed by the setter)
    /// and broadcasts the proposal over the mesh network with a higher TTL (15 hops).
    /// Returns `true` if accepted and broadcast; returns `false` if blocked by another active setter.
    @discardableResult
    public func proposeMeetingPoint(
        coordinate: CLLocationCoordinate2D,
        meetupTime: Date = Date(),
        isRightNow: Bool = false,
        anchorToProposerGPS: Bool = false,
        proposerId: String,
        arrivalRadiusMeters: Double = 25.0
    ) -> Bool {
        let sanitizedProposer = InitialsCodec.sanitize(proposerId)
        guard canSetMeetingPoint(by: sanitizedProposer) else {
            print("[MeetingPointViewModel] Blocked rendezvous proposal by '\(sanitizedProposer)': active rendezvous locked by setter '\(activeMeetingPoint?.proposerId ?? "")'")
            return false
        }
        
        let point = MeetingPoint(
            coordinate: coordinate,
            meetupTime: meetupTime,
            createdAt: Date(),
            proposerId: sanitizedProposer,
            isRightNow: isRightNow,
            anchorToProposerGPS: anchorToProposerGPS,
            arrivalRadiusMeters: arrivalRadiusMeters,
            attendance: [sanitizedProposer: .attending]
        )
        self.activeMeetingPoint = point
        self.localAttendanceStatus = .attending
        
        Task { [weak self] in
            await self?.broadcastMeetingUpdate(action: .propose, meetingPoint: point)
        }
        return true
    }
    
    /// Checks whether the user has reached the active rendezvous spot and auto-broadcasts arrival.
    public func checkArrival(userLocation: CLLocationCoordinate2D) {
        checkExpiration()
        guard let point = activeMeetingPoint else { return }
        guard localAttendanceStatus != .atMeetingPoint else { return }
        
        let pointLoc = CLLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
        let userLoc = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let distance = userLoc.distance(from: pointLoc)
        
        if distance <= point.arrivalRadiusMeters {
            let localInitials = sessionProvider?()?.localInitials ?? point.proposerId
            respond(status: .atMeetingPoint, memberId: localInitials)
        }
    }
    
    /// Automatically clears the rendezvous if more than 1 hour has elapsed past the scheduled time.
    public func checkExpiration() {
        guard let point = activeMeetingPoint else { return }
        if point.isExpired {
            self.activeMeetingPoint = nil
            self.localAttendanceStatus = nil
        }
    }
    
    /// Responds with 1-tap confirmation and broadcasts attendance to the mesh.
    public func respond(status: AttendanceStatus, memberId: String) {
        guard var point = activeMeetingPoint else { return }
        point.attendance[memberId] = status
        self.activeMeetingPoint = point
        
        let localInitials = sessionProvider?()?.localInitials ?? point.proposerId
        if memberId == localInitials {
            self.localAttendanceStatus = status
        }
        
        let action: MeetingAction = (status == .cantMakeIt) ? .decline : .accept
        Task { [weak self] in
            await self?.broadcastMeetingUpdate(action: action, meetingPoint: point)
        }
    }
    
    /// Cancels (unsets) the current active meeting point and broadcasts cancellation over the mesh.
    /// Rule: Only the setter who created the meeting point can unset it.
    /// Returns `true` if cancelled; returns `false` if blocked because caller is not the setter.
    @discardableResult
    public func cancelMeetingPoint(callerId: String? = nil) -> Bool {
        guard let point = activeMeetingPoint else { return false }
        let caller = callerId ?? sessionProvider?()?.localInitials ?? point.proposerId
        guard canUnsetMeetingPoint(by: caller) else {
            print("[MeetingPointViewModel] Blocked rendezvous cancellation by '\(caller)': only setter '\(point.proposerId)' can unset this meeting point")
            return false
        }
        
        self.activeMeetingPoint = nil
        self.localAttendanceStatus = nil
        
        Task { [weak self] in
            await self?.broadcastMeetingUpdate(action: .cancel, meetingPoint: point)
        }
        return true
    }
    
    /// Syncs the current active meeting point to newly connected or late-joining peers.
    public func syncActiveMeetingPointToPeers() async {
        guard let point = activeMeetingPoint else { return }
        await broadcastMeetingUpdate(action: .propose, meetingPoint: point)
    }
    
    /// Applies an authenticated inbound meeting update received over the mesh (without re-broadcasting).
    /// Enforces the lock rule: When someone sets a meeting point, another person cannot set the
    /// meeting point before the setter unsets the meeting point.
    /// Returns `true` if applied; `false` if rejected by the lock rule.
    @discardableResult
    public func applyInboundUpdate(_ update: MeetingUpdatePayload) -> Bool {
        switch update.action {
        case .propose:
            checkExpiration()
            // Lock rule: If an active unexpired meeting point exists, another person cannot set it before setter unsets it.
            if let existing = activeMeetingPoint, !existing.isExpired {
                guard existing.proposerId == update.senderInitials else {
                    print("[MeetingPointViewModel] Inbound proposal from '\(update.senderInitials)' rejected; active rendezvous locked by setter '\(existing.proposerId)'")
                    return false
                }
            }
            
            let mp = MeetingPoint(
                id: update.meetingPointId,
                coordinate: update.coordinate,
                meetupTime: update.meetupTime,
                createdAt: update.createdAt,
                proposerId: update.senderInitials,
                isRightNow: update.isRightNow,
                anchorToProposerGPS: update.anchorToProposerGPS,
                arrivalRadiusMeters: Double(update.arrivalRadiusMeters),
                attendance: [update.senderInitials: update.attendanceStatus]
            )
            if !mp.isExpired {
                self.activeMeetingPoint = mp
                // If the local user is not the proposer, reset local attendance so they can respond
                if let localInitials = sessionProvider?()?.localInitials, update.senderInitials != localInitials {
                    self.localAttendanceStatus = nil
                }
                return true
            }
            return false
            
        case .cancel:
            guard let existing = activeMeetingPoint, existing.id == update.meetingPointId else {
                return false
            }
            // Lock rule: Only the setter who proposed this rendezvous can cancel it over the mesh.
            guard existing.proposerId == update.senderInitials else {
                print("[MeetingPointViewModel] Inbound cancel from '\(update.senderInitials)' rejected; only setter '\(existing.proposerId)' can unset this rendezvous")
                return false
            }
            self.activeMeetingPoint = nil
            self.localAttendanceStatus = nil
            return true
            
        case .accept, .decline:
            if var mp = activeMeetingPoint, mp.id == update.meetingPointId {
                mp.attendance[update.senderInitials] = update.attendanceStatus
                self.activeMeetingPoint = mp
                if let localInitials = sessionProvider?()?.localInitials, update.senderInitials == localInitials {
                    self.localAttendanceStatus = update.attendanceStatus
                }
                return true
            }
            return false
        }
    }
    
    /// Assembles, cryptographically seals, and broadcasts a 56-byte meeting wire packet.
    /// Setting or updating the meeting point uses a higher TTL (hopLimit = 15) to propagate
    /// across wide multi-kilometer festival grounds.
    public func broadcastMeetingUpdate(action: MeetingAction, meetingPoint: MeetingPoint) async {
        guard let session = sessionProvider?(), let cryptoService, let transport else {
            return
        }
        
        let radiusByte = UInt8(min(100, max(5, meetingPoint.arrivalRadiusMeters.rounded())))
        let payload = MeetingUpdatePayload(
            coordinate: meetingPoint.coordinate,
            meetupTime: meetingPoint.meetupTime,
            createdAt: meetingPoint.createdAt,
            action: action,
            attendanceStatus: localAttendanceStatus ?? .attending,
            meetingPointId: meetingPoint.id,
            senderInitials: session.localInitials,
            arrivalRadiusMeters: radiusByte,
            isRightNow: meetingPoint.isRightNow,
            anchorToProposerGPS: meetingPoint.anchorToProposerGPS
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
