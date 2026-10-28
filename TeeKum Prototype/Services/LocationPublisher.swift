//
//  LocationPublisher.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation
import CryptoKit
import Observation

/// High-level publishing coordinator integrating:
/// 1. `LocationServiceProvider` (local location state & adaptive cadence scheduler).
/// 2. `GroupSession` provider (ephemeral session ID, symmetric key, local member ID).
/// 3. `CryptoServiceProvider` (ChaCha20-Poly1305 / AES-GCM AEAD sealing with AAD envelope binding).
/// 4. `PeerTransport` (Network.framework AWDL datagram broadcast with priority outbox coalescing).
///
/// Responsibilities:
/// - Packages location + status together into 30-byte `LocationPingPayload`.
/// - Stops ordinary location broadcasting when Live Sharing is OFF.
/// - Guarantees status updates are included in the next regular ping without sending separate status packets.
/// - Keeps emergency SOS dispatch completely independent from normal location publication.
@Observable
@MainActor
public final class LocationPublisher {
    
    // MARK: - Dependencies
    
    public let locationService: LocationServiceProvider
    private let sessionProvider: @Sendable () -> GroupSession?
    public let cryptoService: CryptoServiceProvider
    public let transport: PeerTransport
    
    // MARK: - State Properties
    
    /// Monotonic sequence counter for outbound packets.
    public private(set) var monotonicCounter: UInt32 = 1
    
    /// Total number of ordinary location pings published over the air.
    public private(set) var publishedPingsCount: Int = 0
    
    /// Total number of emergency SOS alerts dispatched.
    public private(set) var dispatchedSOSCount: Int = 0
    
    /// Background listening task observing `locationService.publishedPings`.
    private var listeningTask: Task<Void, Never>?
    
    /// True when publisher is actively listening and broadcasting.
    public private(set) var isRunning: Bool = false
    
    // MARK: - Initialization
    
    public init(
        locationService: LocationServiceProvider,
        sessionProvider: @escaping @Sendable () -> GroupSession?,
        cryptoService: CryptoServiceProvider,
        transport: PeerTransport
    ) {
        self.locationService = locationService
        self.sessionProvider = sessionProvider
        self.cryptoService = cryptoService
        self.transport = transport
    }
    
    // MARK: - Lifecycle Controls
    
    /// Starts observing the location service and broadcasting pings when Live Sharing is active.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        
        // If an initial location is already known, broadcast it immediately
        if let initialLoc = locationService.currentLocation, locationService.isLiveSharingEnabled {
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                await self.handleLocationPingReady(location: initialLoc, status: self.locationService.currentStatus)
            }
        }
        
        listeningTask?.cancel()
        listeningTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await (location, status) in self.locationService.publishedPings {
                guard !Task.isCancelled, self.isRunning else { break }
                await self.handleLocationPingReady(location: location, status: status)
            }
        }
    }
    
    /// Stops observing and broadcasting ordinary location pings.
    public func stop() {
        isRunning = false
        listeningTask?.cancel()
        listeningTask = nil
    }
    
    // MARK: - Ordinary Location & Status Publishing
    
    /// Assembles, seals, and broadcasts a 56-byte wire packet carrying location + status.
    /// Strictly suppressed if Live Sharing is disabled.
    public func handleLocationPingReady(location: LocationPin, status: UserStatus) async {
        // Acceptance Criterion 2: Live Sharing OFF prevents ordinary location broadcasting
        guard locationService.isLiveSharingEnabled else { return }
        
        guard let session = sessionProvider() else {
            // No active session to encrypt or address packets to
            return
        }
        
        let batteryPct = UInt8(min(100, max(0, Int((locationService.currentBatteryLevel * 100).rounded()))))
        let headingByte: UInt8
        if let heading = locationService.currentHeading {
            headingByte = UInt8(min(255, max(0, Int((heading * 255.0 / 360.0).rounded()))))
        } else {
            headingByte = 0
        }
        
        // Acceptance Criterion 3: Status is included in the normal location update
        let payload = LocationPingPayload(
            coordinate: location.coordinate,
            timestamp: location.timestamp, // Preserves hardware measurement timestamp
            accuracy: location.rawAccuracyByte,
            statusCode: status.code,
            targetRefId: status.targetRefId,
            senderId: session.localMemberId,
            batteryLevel: batteryPct,
            heading: headingByte
        )
        
        let payloadData = payload.serialize()
        
        let memberSlot = UInt8(session.localMemberId & 0xFF)
        let seq = CleartextEnvelope.makeSequenceNumber(memberSlot: memberSlot, counter: monotonicCounter)
        monotonicCounter &+= 1
        
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .locationPing,
            hopLimit: PacketConstants.defaultHopLimit,
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: seq
        )
        
        do {
            let key = SymmetricKey(data: session.symmetricKeyData)
            let sealed = try await cryptoService.seal(payload: payloadData, envelope: envelope, using: key)
            let wirePacket = RawWirePacket(envelope: envelope, ciphertext: sealed.ciphertext, authTag: sealed.authTag)
            let wireData = try wirePacket.toWireData()
            
            try await transport.broadcastPacket(wireData)
            publishedPingsCount += 1
        } catch {
            // Failed transmissions are handled by transport / retry policy
        }
    }
    
    // MARK: - Independent SOS Emergency Dispatch (Acceptance Criterion 6)
    
    /// Immediately packages and broadcasts an urgent SOS emergency alert.
    ///
    /// Operating Guarantees:
    /// - Operates completely independently from the normal publishing interval.
    /// - Requests the latest available location without waiting for a fresh GPS fix or normal ping.
    /// - Operates unconditionally even when Live Sharing is disabled.
    /// - Enqueued with urgent priority in the transport outbox.
    public func dispatchSOS(emergencyType: SOSType = .general) async throws {
        guard let session = sessionProvider() else {
            throw LocationServiceError.trackingFailed("Cannot dispatch SOS without an active group session.")
        }
        
        // Grab latest available location without waiting for a normal ping
        let latestLocation = locationService.getLatestLocationForSOS()
        
        let coordinate: CLLocationCoordinate2D
        let timestamp: Date
        let accuracy: UInt8
        
        if let latestLocation {
            coordinate = latestLocation.coordinate
            timestamp = latestLocation.timestamp
            accuracy = latestLocation.rawAccuracyByte
        } else {
            // Fallback if device has acquired zero fixes since boot
            coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
            timestamp = Date(timeIntervalSince1970: 0)
            accuracy = 255
        }
        
        let batteryPct = UInt8(min(100, max(0, Int((locationService.currentBatteryLevel * 100).rounded()))))
        
        let sosPayload = SOSPayload(
            coordinate: coordinate,
            timestamp: timestamp,
            accuracy: accuracy,
            sosEventId: UInt32.random(in: 1...UInt32.max),
            senderId: session.localMemberId,
            emergencyType: emergencyType,
            batteryLevel: batteryPct
        )
        
        let payloadData = sosPayload.serialize()
        
        let memberSlot = UInt8(session.localMemberId & 0xFF)
        let seq = CleartextEnvelope.makeSequenceNumber(memberSlot: memberSlot, counter: monotonicCounter)
        monotonicCounter &+= 1
        
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .sos,
            hopLimit: PacketConstants.defaultHopLimit,
            hopCount: 0,
            sessionId: session.sessionId,
            sequenceNumber: seq
        )
        
        let key = SymmetricKey(data: session.symmetricKeyData)
        let sealed = try await cryptoService.seal(payload: payloadData, envelope: envelope, using: key)
        let wirePacket = RawWirePacket(envelope: envelope, ciphertext: sealed.ciphertext, authTag: sealed.authTag)
        let wireData = try wirePacket.toWireData()
        
        try await transport.broadcastPacket(wireData)
        dispatchedSOSCount += 1
    }
}
