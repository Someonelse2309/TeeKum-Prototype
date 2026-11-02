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
    
    /// Throttled publishing interval in survival mode (<20% battery).
    public var survivalInterval: TimeInterval
    
    /// Duration after which a location fix is marked stale for the UI.
    public var staleThreshold: TimeInterval
    
    public init(
        movingInterval: TimeInterval = 4.0,
        stationaryInterval: TimeInterval = 20.0,
        survivalInterval: TimeInterval = 60.0,
        staleThreshold: TimeInterval = 30.0
    ) {
        self.movingInterval = movingInterval
        self.stationaryInterval = stationaryInterval
        self.survivalInterval = survivalInterval
        self.staleThreshold = staleThreshold
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
    
    /// Latest true-north compass heading in degrees (0..<360).
    var currentHeading: CLLocationDirection? { get }
    
    /// Motion coprocessor activity state (`true` if user is standing/dancing in place; `false` if walking).
    var isStationary: Bool { get }
    
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
    
    /// Time elapsed in seconds since the current location was measured by hardware GPS (nil if no fix acquired yet).
    var locationAge: TimeInterval? { get }
    
    /// Local user status to coalesce into the next normal location ping.
    var currentStatus: UserStatus { get }
    
    /// Current target publishing interval in seconds based on movement, stationary state, and battery.
    var currentCadenceInterval: TimeInterval { get }
    
    /// Configurable cadence settings.
    var cadenceConfig: CadenceConfiguration { get set }
    
    /// Async stream yielding location pings ready for radio publishing.
    var publishedPings: AsyncStream<(location: LocationPin, status: UserStatus)> { get }
    
    /// Requests standard iOS CoreLocation permissions with friendly educational primer.
    func requestPermissions() async -> Bool
    
    /// Starts adaptive GPS sampling and CoreMotion activity tracking.
    func startTracking() throws
    
    /// Pauses GPS receiver and stops compass monitoring to conserve battery.
    func stopTracking()
    
    /// Updates local user status immediately without creating a separate ordinary network packet.
    func updateStatus(_ status: UserStatus)
    
    /// Retrieves the latest available location immediately for emergency SOS dispatch.
    /// Does not wait for a fresh GPS fix or a normal ping interval, and operates regardless of Live Sharing state.
    func getLatestLocationForSOS() -> LocationPin?
    
    /// Recreates the publishedPings stream and continuation to recover from cancellation.
    func resetPublishedPingsStream()
}

extension LocationServiceProvider {
    public func resetPublishedPingsStream() {}
}
