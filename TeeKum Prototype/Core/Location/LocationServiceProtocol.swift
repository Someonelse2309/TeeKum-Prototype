//
//  LocationServiceProtocol.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

// MARK: - Cadence Configuration

/// Configurable target intervals for the adaptive publishing engine.
///
/// Note: Target intervals represent requested scheduling intervals subject to iOS runloop,
/// system power management, and radio baseband scheduling.
nonisolated public struct CadenceConfiguration: Equatable, Sendable {
    /// Publishing interval while actively moving (recommended: 3–5 seconds).
    public var movingInterval: TimeInterval
    
    /// Publishing interval while stationary (recommended: 15–30 seconds).
    public var stationaryInterval: TimeInterval
    
    /// Accelerated publishing interval when one or more peers are distant or signal is weak (recommended: 2.0s).
    public var distantPeerInterval: TimeInterval
    
    /// Throttled publishing interval in survival mode (<20% battery).
    public var survivalInterval: TimeInterval
    
    /// Duration after which a location fix is marked stale for the UI.
    public var staleThreshold: TimeInterval
    
    /// Threshold after which a peer is considered stale (recommended: 30.0s).
    public var stalePeerThreshold: TimeInterval
    
    /// Accelerated publishing interval while probing for stale peers (recommended: 2.0s).
    public var staleRecoveryInterval: TimeInterval
    
    /// Additional staleness delay before triggering Stage 2 route discovery (recommended: 15.0s).
    public var staleRouteReqDelay: TimeInterval
    
    /// Maximum active recovery probe window duration before falling back to normal cadence (recommended: 60.0s).
    public var staleRecoveryTimeout: TimeInterval
    
    public init(
        movingInterval: TimeInterval = TeeKumConfiguration.Timing.locationMovingInterval,
        stationaryInterval: TimeInterval = TeeKumConfiguration.Timing.locationStationaryInterval,
        distantPeerInterval: TimeInterval = TeeKumConfiguration.Timing.distantPeerInterval,
        survivalInterval: TimeInterval = TeeKumConfiguration.Timing.survivalInterval,
        staleThreshold: TimeInterval = TeeKumConfiguration.Timing.stalePeerThreshold,
        stalePeerThreshold: TimeInterval = TeeKumConfiguration.Timing.stalePeerThreshold,
        staleRecoveryInterval: TimeInterval = 2.0,
        staleRouteReqDelay: TimeInterval = 15.0,
        staleRecoveryTimeout: TimeInterval = 60.0
    ) {
        self.movingInterval = movingInterval
        self.stationaryInterval = stationaryInterval
        self.distantPeerInterval = distantPeerInterval
        self.survivalInterval = survivalInterval
        self.staleThreshold = staleThreshold
        self.stalePeerThreshold = stalePeerThreshold
        self.staleRecoveryInterval = staleRecoveryInterval
        self.staleRouteReqDelay = staleRouteReqDelay
        self.staleRecoveryTimeout = staleRecoveryTimeout
    }
}

// MARK: - Location Service Errors

/// Explicit errors thrown during location lifecycle operations.
nonisolated public enum LocationServiceError: Error, LocalizedError, Equatable {
    case locationServicesDisabled
    case permissionDenied
    case permissionRestricted
    case trackingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .locationServicesDisabled:
            return "Location Services are disabled on this device in System Settings."
        case .permissionDenied:
            return "Location permission was denied. Please allow location access in Settings."
        case .permissionRestricted:
            return "Location access is restricted (e.g. Parental Controls)."
        case let .trackingFailed(reason):
            return "Location tracking failed: \(reason)"
        }
    }
}

// MARK: - Authoritative Location Service Contract

/// Authoritative contract for the location, motion, and battery monitoring subsystem.
@MainActor
public protocol LocationServiceProvider: AnyObject {
    /// Latest measured local coordinate, uncertainty accuracy radius, and measurement timestamp.
    var currentLocation: LocationPin? { get }
    
    /// Latest magnetic compass heading in degrees (0..<360).
    var currentHeading: CLLocationDirection? { get }
    
    /// Optional high-frequency callback invoked whenever a hardware compass heading fix is received.
    var onHeadingUpdate: ((CLLocationDirection) -> Void)? { get set }
    
    /// Motion coprocessor activity state (`true` if user is standing/dancing in place; `false` if walking).
    var isStationary: Bool { get }
    
    /// True if any tracked group member or radio neighbor is distant (far GPS or weak RSSI).
    var hasDistantPeers: Bool { get set }
    
    /// Optional closure provider to dynamically evaluate whether any peers are distant.
    var hasDistantPeersProvider: (@MainActor @Sendable () -> Bool)? { get set }
    
    /// True if any tracked group member is stale and within active recovery window.
    var hasStalePeers: Bool { get set }
    
    /// Optional closure provider to dynamically evaluate whether any peers are stale and within the active recovery window.
    var hasStalePeersProvider: (@MainActor @Sendable () -> Bool)? { get set }
    
    /// User-controlled master toggle governing whether coordinates are broadcast to the group.
    var isLiveSharingEnabled: Bool { get set }
    
    /// Hard 20% cutoff battery detection (Festival Survival Mode).
    var isSurvivalModeActive: Bool { get }
    
    /// Current device battery percentage (0.0 ... 1.0).
    var currentBatteryLevel: Float { get }
    
    /// Current Core Location authorization status.
    var authorizationStatus: CLAuthorizationStatus { get }
    
    /// True if GPS hardware is functioning, authorized, and actively providing valid fixes.
    var isGPSAvailable: Bool { get }
    
    /// True if the current location measurement is older than the staleness threshold.
    var isLocationStale: Bool { get }
    
    /// True if Core Location authorization has full accuracy (Precise Location: ON).
    var isPreciseLocationAuthorized: Bool { get }
    
    /// True if the user is actively viewing the Tactical Radar or navigating.
    var isTacticalRadarActive: Bool { get }
    
    /// Enables or disables high-precision navigation mode (kCLLocationAccuracyBestForNavigation).
    func setTacticalRadarActive(_ active: Bool)
    
    /// Time elapsed in seconds since the current location was measured by hardware GPS (nil if no fix acquired yet).
    var locationAge: TimeInterval? { get }
    
    /// Current target publishing interval in seconds based on movement, stationary state, and battery.
    var currentCadenceInterval: TimeInterval { get }
    
    /// Configurable cadence settings.
    var cadenceConfig: CadenceConfiguration { get set }
    
    /// Async stream yielding location pings ready for radio publishing.
    var publishedPings: AsyncStream<LocationPin> { get }
    
    /// Requests standard iOS CoreLocation permissions with friendly educational primer.
    func requestPermissions() async -> Bool
    
    /// Starts adaptive GPS sampling and CoreMotion activity tracking.
    func startTracking() throws
    
    /// Pauses GPS receiver and stops compass monitoring to conserve battery.
    func stopTracking()
    
    /// Retrieves the latest available location immediately for emergency SOS dispatch.
    /// Does not wait for a fresh GPS fix or a normal ping interval, and operates regardless of Live Sharing state.
    func getLatestLocationForSOS() -> LocationPin?
    
    /// Recreates the publishedPings stream and continuation to recover from cancellation.
    func resetPublishedPingsStream()
    
    /// Re-evaluates cadence and interrupts any current long sleep if cadence accelerated.
    func triggerCadenceEvaluation()
    
    /// Publishes a rapid burst of fresh location pings to punch through intermediate mesh relays.
    func triggerBurstPings(count: Int, interval: TimeInterval)
}

extension LocationServiceProvider {
    public var onHeadingUpdate: ((CLLocationDirection) -> Void)? {
        get { nil }
        set {}
    }
    public var isPreciseLocationAuthorized: Bool { true }
    public var isTacticalRadarActive: Bool { false }
    public func setTacticalRadarActive(_ active: Bool) {}
    public func resetPublishedPingsStream() {}
    public func triggerCadenceEvaluation() {}
    public func triggerBurstPings(count: Int, interval: TimeInterval) {}
}
