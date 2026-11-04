//
//  NearbyInteractionService.swift
//  TeeKum Prototype
//
//  Created by Nicho on 04/11/26.
//

import Foundation
import NearbyInteraction
import simd
import UIKit
import CryptoKit
import Observation

/// Current state of Ultra-Wideband (UWB) precision ranging.
public enum UWBRangingState: Equatable, Sendable {
    case idle
    case unsupported
    case requestingToken
    case active
    case outOfRange
    case failed(String)
}

/// Service managing native Apple NearbyInteraction (`NISession`) lifecycle,
/// out-of-band discovery token exchange over the 56-byte wire protocol,
/// precision 3D direction/centimeter distance tracking, and AirTag-style haptics.
@Observable
@MainActor
public final class NearbyInteractionService: NSObject, NISessionDelegate {
    public static let shared = NearbyInteractionService()
    
    // MARK: - Observable State
    
    public private(set) var isSupported: Bool = false
    public private(set) var isSimulated: Bool = false
    public private(set) var rangingState: UWBRangingState = .idle
    public private(set) var activeTargetMemberId: String?
    public private(set) var activeTargetMemberName: String?
    public private(set) var currentDistance: Float?
    public private(set) var currentDirection: simd_float3?
    public private(set) var currentHorizontalAngle: Float?
    public private(set) var lastUpdate: Date?
    
    // MARK: - Internal Session State
    
    private var currentSession: NISession?
    private var currentPeerToken: NIDiscoveryToken?
    
    // Multi-fragment packet assembly buffer keyed by sequenceId -> (fragmentIndex -> chunk Data)
    private var inboundFragmentBuffer: [UInt8: [UInt8: Data]] = [:]
    private var inboundFragmentTotalCounts: [UInt8: UInt8] = [:]
    
    // Sequence generator for outbound transfers
    private var nextSequenceId: UInt8 = 1
    
    // Haptics & Timeout Tasks
    private var timeoutTask: Task<Void, Never>?
    private var hapticTask: Task<Void, Never>?
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let heavyFeedback = UIImpactFeedbackGenerator(style: .heavy)
    private let lightFeedback = UIImpactFeedbackGenerator(style: .light)
    
    // MARK: - Initialization
    
    override public init() {
        super.init()
        self.isSupported = NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
        if !self.isSupported {
            self.rangingState = .unsupported
        }
    }
    
    // MARK: - Public Precision Finding Actions
    
    /// Starts an Ultra-Wideband precision finding session targeting the specified member.
    /// Falls back seamlessly to sensor-assisted simulation (GPS distance + compass relative bearing)
    /// when running on Simulator, devices without U1/U2 chips, or when mesh transports are offline.
    public func startPrecisionFinding(
        for member: Member,
        session: GroupSession? = nil,
        transport: (any PeerTransport)? = nil,
        userLocation: LocationPin? = nil,
        currentHeading: Double? = nil
    ) async {
        // Stop any active previous session
        stopSessionInternal()
        
        activeTargetMemberId = member.id
        activeTargetMemberName = member.name
        
        guard isSupported, let groupSession = session, let radioTransport = transport else {
            // Enter Sensor-Assisted Simulation fallback mode
            isSimulated = true
            rangingState = .active
            updateSimulatedTelemetry(for: member, userLocation: userLocation, currentHeading: currentHeading)
            startHapticLoop()
            return
        }
        
        isSimulated = false
        rangingState = .requestingToken
        
        // Create NISession and retrieve our ephemeral discovery token
        let niSession = NISession()
        niSession.delegate = self
        self.currentSession = niSession
        
        guard let localToken = niSession.discoveryToken else {
            // Fallback to simulated mode if token acquisition fails
            isSimulated = true
            rangingState = .active
            updateSimulatedTelemetry(for: member, userLocation: userLocation, currentHeading: currentHeading)
            startHapticLoop()
            return
        }
        
        do {
            let tokenData = try NSKeyedArchiver.archivedData(withRootObject: localToken, requiringSecureCoding: true)
            let seqId = getNextSequenceId()
            
            // Fragment the token data into 25-byte chunks
            let payloads = fragmentTokenData(tokenData, action: .tokenRequest, sequenceId: seqId)
            
            // Dispatch urgent wire packets over local radio transport
            for payload in payloads {
                let wireData = try encryptPayload(payload, session: groupSession, memberSlot: groupSession.memberSlot)
                try await radioTransport.sendPacket(wireData, to: member.id)
            }
            
            // Schedule timeout watchdog
            startTimeoutWatchdog(seconds: TeeKumConfiguration.Navigation.uwbSessionTimeoutSeconds)
            
        } catch {
            isSimulated = true
            rangingState = .active
            updateSimulatedTelemetry(for: member, userLocation: userLocation, currentHeading: currentHeading)
            startHapticLoop()
        }
    }
    
    /// Updates simulated telemetry (distance and 3D angle) when running in sensor-assisted mode.
    public func updateSimulatedTelemetry(
        for member: Member,
        userLocation: LocationPin?,
        currentHeading: Double?
    ) {
        guard isSimulated, activeTargetMemberId == member.id else { return }
        if let userLoc = userLocation, let targetCoord = member.coordinate {
            let dist = Float(userLoc.distance(to: targetCoord))
            self.currentDistance = dist
            
            let bearing = userLoc.bearing(to: targetCoord)
            let heading = currentHeading ?? 0.0
            var relDeg = bearing - heading
            while relDeg > 180 { relDeg -= 360 }
            while relDeg < -180 { relDeg += 360 }
            
            let rad = Float(relDeg * .pi / 180.0)
            self.currentHorizontalAngle = rad
            self.currentDirection = simd_float3(sin(rad), 0, -cos(rad))
            self.lastUpdate = Date()
        } else {
            if self.currentDistance == nil {
                self.currentDistance = 4.2
                self.currentHorizontalAngle = 0.0
                self.currentDirection = simd_float3(0, 0, -1)
                self.lastUpdate = Date()
            }
        }
    }
    
    /// Stops the active precision finding session, sends a stop packet to the peer, and releases hardware.
    public func stopPrecisionFinding(
        session: GroupSession?,
        transport: (any PeerTransport)?
    ) async {
        if let targetId = activeTargetMemberId, let session = session, let transport = transport {
            let stopPayload = UWBTokenExchangePayload(
                action: .stopRanging,
                sequenceId: getNextSequenceId(),
                fragmentIndex: 0,
                totalFragments: 1,
                fragmentData: Data()
            )
            if let wireData = try? encryptPayload(stopPayload, session: session, memberSlot: session.memberSlot) {
                try? await transport.sendPacket(wireData, to: targetId)
            }
        }
        
        stopSessionInternal()
        rangingState = isSupported ? .idle : .unsupported
    }
    
    // MARK: - Inbound Packet Handling
    
    /// Processes an inbound 30-byte UWBTokenExchangePayload received over the peer-to-peer radio.
    public func handleInboundUWBPayload(
        _ payload: UWBTokenExchangePayload,
        fromPeerId: String,
        session: GroupSession,
        transport: any PeerTransport
    ) async {
        guard isSupported else { return }
        
        switch payload.action {
        case .tokenRequest:
            // Peer is requesting to start ranging with us. Assemble peer's token fragments.
            if let assembledTokenData = processInboundFragment(payload) {
                do {
                    guard let peerToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: assembledTokenData) else {
                        return
                    }
                    
                    // Stop previous session if active
                    stopSessionInternal()
                    
                    // Setup local NISession
                    let niSession = NISession()
                    niSession.delegate = self
                    self.currentSession = niSession
                    self.currentPeerToken = peerToken
                    self.activeTargetMemberId = fromPeerId
                    
                    // Respond with our local token fragments
                    if let localToken = niSession.discoveryToken {
                        let localData = try NSKeyedArchiver.archivedData(withRootObject: localToken, requiringSecureCoding: true)
                        let respSeqId = getNextSequenceId()
                        let respPayloads = fragmentTokenData(localData, action: .tokenResponse, sequenceId: respSeqId)
                        
                        for p in respPayloads {
                            let wireData = try encryptPayload(p, session: session, memberSlot: session.memberSlot)
                            try await transport.sendPacket(wireData, to: fromPeerId)
                        }
                    }
                    
                    // Start ranging
                    let config = NINearbyPeerConfiguration(peerToken: peerToken)
                    niSession.run(config)
                    self.rangingState = .active
                    startTimeoutWatchdog(seconds: TeeKumConfiguration.Navigation.uwbSessionTimeoutSeconds)
                    startHapticLoop()
                    
                } catch {
                    // Ignore malformed token
                }
            }
            
        case .tokenResponse:
            // Peer responded with its token fragments for our active request.
            if let assembledTokenData = processInboundFragment(payload) {
                do {
                    guard let peerToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: assembledTokenData) else {
                        return
                    }
                    
                    guard let niSession = currentSession else { return }
                    self.currentPeerToken = peerToken
                    
                    let config = NINearbyPeerConfiguration(peerToken: peerToken)
                    niSession.run(config)
                    self.rangingState = .active
                    startTimeoutWatchdog(seconds: TeeKumConfiguration.Navigation.uwbSessionTimeoutSeconds)
                    startHapticLoop()
                    
                } catch {
                    rangingState = .failed("Peer token unarchiving failed.")
                    stopSessionInternal()
                }
            }
            
        case .stopRanging:
            // Peer stopped precision finding
            if activeTargetMemberId == fromPeerId {
                stopSessionInternal()
                rangingState = .idle
            }
        }
    }
    
    // MARK: - NISessionDelegate
    
    public func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let peerObject = nearbyObjects.first else { return }
        
        self.currentDistance = peerObject.distance
        self.currentDirection = peerObject.direction
        self.currentHorizontalAngle = peerObject.horizontalAngle
        self.lastUpdate = Date()
        
        if peerObject.distance != nil || peerObject.direction != nil {
            self.rangingState = .active
            // Refresh activity watchdog
            startTimeoutWatchdog(seconds: TeeKumConfiguration.Navigation.uwbSessionTimeoutSeconds)
        }
    }
    
    public func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        self.rangingState = .outOfRange
    }
    
    public func sessionWasSuspended(_ session: NISession) {
        self.rangingState = .outOfRange
    }
    
    public func sessionSuspensionEnded(_ session: NISession) {
        if let peerToken = currentPeerToken, let niSession = currentSession {
            let config = NINearbyPeerConfiguration(peerToken: peerToken)
            niSession.run(config)
            self.rangingState = .active
        }
    }
    
    public func session(_ session: NISession, didInvalidateWith error: Error) {
        self.rangingState = .failed(error.localizedDescription)
        stopSessionInternal()
    }
    
    // MARK: - Internal Helpers
    
    private func stopSessionInternal() {
        timeoutTask?.cancel()
        timeoutTask = nil
        hapticTask?.cancel()
        hapticTask = nil
        
        currentSession?.pause()
        currentSession?.invalidate()
        currentSession = nil
        currentPeerToken = nil
        
        isSimulated = false
        activeTargetMemberId = nil
        activeTargetMemberName = nil
        currentDistance = nil
        currentDirection = nil
        currentHorizontalAngle = nil
        lastUpdate = nil
    }
    
    private func getNextSequenceId() -> UInt8 {
        let seq = nextSequenceId
        nextSequenceId = nextSequenceId == 255 ? 1 : nextSequenceId + 1
        return seq
    }
    
    private func fragmentTokenData(_ data: Data, action: UWBAction, sequenceId: UInt8) -> [UWBTokenExchangePayload] {
        let chunkSize = UWBTokenExchangePayload.maxFragmentDataBytes
        let totalCount = UInt8(ceil(Double(data.count) / Double(chunkSize)))
        var payloads: [UWBTokenExchangePayload] = []
        
        for idx in 0..<totalCount {
            let start = Int(idx) * chunkSize
            let end = min(start + chunkSize, data.count)
            let chunk = data.subdata(in: start..<end)
            
            let p = UWBTokenExchangePayload(
                action: action,
                sequenceId: sequenceId,
                fragmentIndex: idx,
                totalFragments: totalCount,
                fragmentData: chunk
            )
            payloads.append(p)
        }
        return payloads
    }
    
    private func processInboundFragment(_ payload: UWBTokenExchangePayload) -> Data? {
        let seq = payload.sequenceId
        var fragments = inboundFragmentBuffer[seq] ?? [:]
        fragments[payload.fragmentIndex] = payload.fragmentData
        inboundFragmentBuffer[seq] = fragments
        inboundFragmentTotalCounts[seq] = payload.totalFragments
        
        if fragments.count == Int(payload.totalFragments) {
            // All fragments received; assemble contiguous buffer in ascending index order
            var fullData = Data()
            for i in 0..<payload.totalFragments {
                if let part = fragments[i] {
                    fullData.append(part)
                } else {
                    return nil // Missing slice
                }
            }
            // Clean up buffer
            inboundFragmentBuffer.removeValue(forKey: seq)
            inboundFragmentTotalCounts.removeValue(forKey: seq)
            return fullData
        }
        return nil
    }
    
    private func encryptPayload(_ payload: UWBTokenExchangePayload, session: GroupSession, memberSlot: UInt8) throws -> Data {
        let rawPayload = payload.serialize()
        let envelope = CleartextEnvelope(
            version: PacketConstants.protocolVersion,
            type: .uwbTokenExchange,
            hopLimit: PacketConstants.uwbHopLimit,
            hopCount: 0,
            sessionId: UInt16(session.sessionId & 0xFFFF),
            sequenceNumber: CleartextEnvelope.makeSequenceNumber(memberSlot: memberSlot, counter: UInt32.random(in: 1...0xFFFFFF))
        )
        
        let nonceData = envelope.constructNonce()
        guard let nonce = try? ChaChaPoly.Nonce(data: nonceData) else {
            throw PacketCodecError.payloadSerializationFailed
        }
        
        let symKey = SymmetricKey(data: session.symmetricKeyData)
        let sealedBox = try ChaChaPoly.seal(
            rawPayload,
            using: symKey,
            nonce: nonce,
            authenticating: envelope.authenticatedAssociatedData()
        )
        
        let rawPacket = RawWirePacket(
            envelope: envelope,
            ciphertext: Data(sealedBox.ciphertext),
            authTag: Data(sealedBox.tag)
        )
        return try rawPacket.toWireData()
    }
    
    private func startTimeoutWatchdog(seconds: Double) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.handleTimeout()
        }
    }
    
    private func handleTimeout() {
        if rangingState == .requestingToken || rangingState == .active {
            stopSessionInternal()
            rangingState = isSupported ? .idle : .unsupported
        }
    }
    
    // MARK: - AirTag-Style Rhythmic Proximity Haptics
    
    private func startHapticLoop() {
        hapticTask?.cancel()
        hapticTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, self.rangingState == .active else { break }
                let dist = self.currentDistance
                
                let delaySeconds: Double
                if let d = dist {
                    if d < 1.0 {
                        // Very close (<1m): Rapid double-pulse
                        self.heavyFeedback.impactOccurred(intensity: 1.0)
                        delaySeconds = 0.22
                    } else if d < 2.5 {
                        // Close (1-2.5m): Medium pulse
                        self.impactFeedback.impactOccurred(intensity: 0.8)
                        delaySeconds = 0.45
                    } else if d < 5.0 {
                        // Moderate (2.5-5m): Gentle pulse
                        self.lightFeedback.impactOccurred(intensity: 0.5)
                        delaySeconds = 0.85
                    } else {
                        delaySeconds = 1.5
                    }
                } else {
                    delaySeconds = 2.0
                }
                
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }
    }
}
