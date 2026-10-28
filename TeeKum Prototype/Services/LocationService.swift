//
//  LocationService.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation
#if canImport(CoreMotion)
import CoreMotion
#endif
#if canImport(UIKit)
import UIKit
#endif
import Observation

/// Authoritative Core Location & Core Motion service managing:
/// 1. Local location state (latest coordinate, accuracy, measurement timestamp).
/// 2. Motion-aware adaptive publishing cadence (3–5s moving, 15–30s stationary).
/// 3. Status coalescing into the next regular location update (no separate status packets).
/// 4. Live Sharing master toggle (stops broadcasting when disabled).
/// 5. Stale coordinate detection, GPS availability, and explicit permission state for the UI.
/// 6. Independent immediate location access for emergency SOS dispatch.
///
/// Note on Platform Behavior:
/// Target intervals represent requested scheduling cadences subject to iOS runloop,
/// system power management, and radio baseband scheduling. Stationary intervals reduce
/// GPS and radio duty cycles without making rigid power or battery percentage guarantees.
@Observable
@MainActor
public final class LocationService: NSObject, CLLocationManagerDelegate, LocationServiceProvider {
    
    // MARK: - Core Location & Motion Hardware
    
    private let locationManager: CLLocationManager
    #if os(iOS) && canImport(CoreMotion)
    private let motionActivityManager: CMMotionActivityManager?
    private let motionQueue = OperationQueue()
    #endif
    
    /// Injectable date provider for deterministic time-based testing.
    private let dateProvider: @Sendable () -> Date
    
    // MARK: - State Properties
    
    /// Latest measured local coordinate, uncertainty accuracy radius, and measurement timestamp.
    public private(set) var currentLocation: LocationPin?
    
    /// Latest magnetic compass heading in degrees (0..<360).
    public private(set) var currentHeading: CLLocationDirection?
    
    /// Motion state (`true` if user is stationary/resting; `false` if walking/moving).
    public private(set) var isStationary: Bool = false
    
    /// Master toggle governing whether coordinates are broadcast to the group.
    public var isLiveSharingEnabled: Bool {
        didSet {
            handleLiveSharingToggleChanged()
        }
    }
    
    /// True when device battery is <20% or in Low Power Mode (Festival Survival Mode).
    public private(set) var isSurvivalModeActive: Bool = false
    
    /// Current device battery percentage (0.0 ... 1.0).
    public private(set) var currentBatteryLevel: Float = 1.0
    
    /// Current Core Location authorization status.
    public private(set) var authorizationStatus: CLAuthorizationStatus
    
    /// True if GPS hardware is functioning, authorized, and actively providing valid fixes.
    public private(set) var isGPSAvailable: Bool = false
    
    /// Local user status to coalesce into the next normal location ping.
    public private(set) var currentStatus: UserStatus = UserStatus(code: .available)
    
    /// Configurable cadence settings (moving, stationary, survival, stale threshold).
    public var cadenceConfig: CadenceConfiguration
    
    /// True if location updates and motion monitoring are currently running.
    public private(set) var isTracking: Bool = false
    
    // MARK: - Single Cancellable Scheduler Loop
    
    /// Active publishing scheduler task. Strictly one task runs at a time.
    private var publishingTask: Task<Void, Never>?
    
    /// Continuation for async permission requests.
    private var permissionContinuation: CheckedContinuation<Bool, Never>?
    
    // MARK: - Publication Callbacks & Streams
    
    /// Direct closure callback invoked when a location ping is ready to publish.
    public var onPublishLocationPing: ((LocationPin, UserStatus) -> Void)?
    
    /// Async stream yielding location pings for reactive consumers.
    public let publishedPings: AsyncStream<(location: LocationPin, status: UserStatus)>
    private let publishedPingsContinuation: AsyncStream<(location: LocationPin, status: UserStatus)>.Continuation
    
    // MARK: - Initialization
    
    public init(
        cadenceConfig: CadenceConfiguration = CadenceConfiguration(),
        isLiveSharingEnabled: Bool = true,
        locationManager: CLLocationManager = CLLocationManager(),
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cadenceConfig = cadenceConfig
        self.isLiveSharingEnabled = isLiveSharingEnabled
        self.locationManager = locationManager
        self.dateProvider = dateProvider
        self.authorizationStatus = locationManager.authorizationStatus
        
        #if os(iOS) && canImport(CoreMotion)
        self.motionActivityManager = CMMotionActivityManager.isActivityAvailable() ? CMMotionActivityManager() : nil
        #endif
        
        var streamContinuation: AsyncStream<(location: LocationPin, status: UserStatus)>.Continuation!
        self.publishedPings = AsyncStream { streamContinuation = $0 }
        self.publishedPingsContinuation = streamContinuation
        
        super.init()
        
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.distanceFilter = kCLDistanceFilterNone
        self.locationManager.activityType = .fitness
        self.locationManager.pausesLocationUpdatesAutomatically = false
        
        updateBatteryState()
    }
    
    // MARK: - Computed Properties for UI
    
    /// Seconds elapsed since the current location was measured by hardware GPS (nil if no fix acquired).
    public var locationAge: TimeInterval? {
        guard let loc = currentLocation else { return nil }
        return max(0, dateProvider().timeIntervalSince(loc.timestamp))
    }
    
    /// True if the current location fix is older than the staleness threshold.
    public var isLocationStale: Bool {
        guard let age = locationAge else { return true }
        return age > cadenceConfig.staleThreshold
    }
    
    /// Current target publishing interval in seconds based on movement, stationary state, and battery.
    public var currentCadenceInterval: TimeInterval {
        if isSurvivalModeActive {
            return cadenceConfig.survivalInterval
        } else if isStationary {
            return cadenceConfig.stationaryInterval
        } else {
            return cadenceConfig.movingInterval
        }
    }
    
    // MARK: - Permissions & Lifecycle
    
    /// Requests standard iOS CoreLocation permissions with explicit handling of denied/restricted states.
    public func requestPermissions() async -> Bool {
        guard CLLocationManager.locationServicesEnabled() else {
            isGPSAvailable = false
            return false
        }
        
        let currentStatus = self.authorizationStatus
        
        switch currentStatus {
        #if os(iOS)
        case .authorizedWhenInUse, .authorizedAlways:
            isGPSAvailable = true
            return true
        #else
        case .authorizedAlways:
            isGPSAvailable = true
            return true
        #endif
        case .denied, .restricted:
            isGPSAvailable = false
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                self.permissionContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }
        @unknown default:
            isGPSAvailable = false
            return false
        }
    }
    
    /// Starts adaptive GPS sampling, CoreMotion activity tracking, and publishing scheduler.
    public func startTracking() throws {
        guard CLLocationManager.locationServicesEnabled() else {
            isGPSAvailable = false
            throw LocationServiceError.locationServicesDisabled
        }
        
        let status = self.authorizationStatus
        
        switch status {
        case .denied:
            isGPSAvailable = false
            throw LocationServiceError.permissionDenied
        case .restricted:
            isGPSAvailable = false
            throw LocationServiceError.permissionRestricted
        case .notDetermined:
            // Request and start
            locationManager.requestWhenInUseAuthorization()
        #if os(iOS)
        case .authorizedWhenInUse, .authorizedAlways:
            break
        #else
        case .authorizedAlways:
            break
        #endif
        @unknown default:
            break
        }
        
        isTracking = true
        #if os(iOS)
        isGPSAvailable = (status == .authorizedWhenInUse || status == .authorizedAlways)
        #else
        isGPSAvailable = (status == .authorizedAlways)
        #endif
        
        locationManager.startUpdatingLocation()
        
        #if os(iOS)
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        #endif
        
        startMotionTracking()
        updateBatteryState()
        
        if isLiveSharingEnabled {
            startPublishingScheduler()
        }
    }
    
    /// Pauses GPS receiver and stops compass and motion monitoring to conserve battery.
    /// Preserves the last known valid coordinate in memory so SOS and UI can continue to read it.
    public func stopTracking() {
        isTracking = false
        stopPublishingScheduler()
        
        locationManager.stopUpdatingLocation()
        #if os(iOS)
        locationManager.stopUpdatingHeading()
        #endif
        
        stopMotionTracking()
    }
    
    // MARK: - Status Coalescing (Acceptance Criteria 3)
    
    /// Updates local user status immediately.
    /// Does NOT send a separate ordinary status packet over the air; the new status
    /// is coalesced and included into the next normal location ping.
    public func updateStatus(_ status: UserStatus) {
        self.currentStatus = status
    }
    
    // MARK: - Emergency SOS Location Access (Acceptance Criteria 6)
    
    /// Retrieves the latest available location immediately for emergency SOS dispatch.
    /// Does not wait for a fresh GPS fix or a normal ping interval, and operates
    /// unconditionally even when Live Sharing is disabled.
    /// Preserves the exact hardware measurement timestamp without modification.
    public func getLatestLocationForSOS() -> LocationPin? {
        return currentLocation
    }
    
    // MARK: - Live Sharing Master Toggle (Acceptance Criteria 1 & 2)
    
    private func handleLiveSharingToggleChanged() {
        if isLiveSharingEnabled {
            if isTracking {
                startPublishingScheduler()
            }
        } else {
            // Live Sharing OFF prevents ordinary location broadcasting
            stopPublishingScheduler()
        }
    }
    
    // MARK: - Publishing Scheduler Engine
    
    /// Starts the periodic publishing scheduler.
    /// Cancels any existing loop first to ensure duplicate timers or concurrent loops are never created.
    private func startPublishingScheduler() {
        stopPublishingScheduler()
        
        guard isTracking, isLiveSharingEnabled else { return }
        
        // Broadcast current location fix immediately upon scheduler start
        publishCurrentState()
        
        publishingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isTracking, self.isLiveSharingEnabled else { break }
                
                let interval = self.currentCadenceInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                
                guard !Task.isCancelled, self.isTracking, self.isLiveSharingEnabled else { break }
                
                self.publishCurrentState()
            }
        }
    }
    
    /// Cancels the publishing scheduler loop.
    private func stopPublishingScheduler() {
        publishingTask?.cancel()
        publishingTask = nil
    }
    
    /// Dispatches the latest useful location and current user status together.
    /// If no valid location fix has been acquired yet, does not manufacture fake coordinates.
    public func publishCurrentState() {
        guard isLiveSharingEnabled else { return }
        guard let location = currentLocation else {
            // Do not manufacture new coordinates when GPS is unavailable
            return
        }
        
        let status = currentStatus
        onPublishLocationPing?(location, status)
        publishedPingsContinuation.yield((location, status))
    }
    
    // MARK: - Monotonic Location Updates & Validation (Acceptance Criteria 4)
    
    /// Evaluates and applies a location measurement.
    /// Enforces:
    /// 1. Positive horizontal accuracy (discards negative invalid fixes).
    /// 2. Monotonic timestamp ordering (older coordinates cannot overwrite newer measurements).
    /// 3. Preserves original measurement timestamp.
    public func applyLocationMeasurement(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0 else {
            // Discard invalid GPS fix
            return
        }
        
        if let existing = currentLocation {
            // An older coordinate cannot overwrite a newer valid measurement
            guard location.timestamp >= existing.timestamp else {
                return
            }
        }
        
        let newPin = LocationPin(
            coordinate: location.coordinate,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp,
            heading: currentHeading
        )
        
        let isFirstFix = (self.currentLocation == nil)
        self.currentLocation = newPin
        self.isGPSAvailable = true
        
        if isFirstFix && isLiveSharingEnabled && isTracking {
            publishCurrentState()
        }
        
        // GPS speed fallback for motion detection if CoreMotion is unavailable
        #if os(iOS) && canImport(CoreMotion)
        if motionActivityManager == nil {
            evaluateGPSSpeedForStationary(location.speed)
        }
        #else
        evaluateGPSSpeedForStationary(location.speed)
        #endif
    }
    
    private func evaluateGPSSpeedForStationary(_ speed: CLLocationSpeed) {
        if speed >= 0.8 {
            setStationaryState(false)
        } else if speed >= 0 && speed < 0.3 {
            setStationaryState(true)
        }
    }
    
    // MARK: - Core Location Delegate Callbacks
    
    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for location in locations {
                self.applyLocationMeasurement(location)
            }
        }
    }
    
    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard newHeading.headingAccuracy >= 0 else { return }
            self.currentHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }
    
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = newStatus
            
            switch newStatus {
            #if os(iOS)
            case .authorizedWhenInUse, .authorizedAlways:
                self.isGPSAvailable = true
                self.permissionContinuation?.resume(returning: true)
                self.permissionContinuation = nil
                if self.isTracking {
                    self.locationManager.startUpdatingLocation()
                    if CLLocationManager.headingAvailable() {
                        self.locationManager.startUpdatingHeading()
                    }
                }
            #else
            case .authorizedAlways:
                self.isGPSAvailable = true
                self.permissionContinuation?.resume(returning: true)
                self.permissionContinuation = nil
                if self.isTracking {
                    self.locationManager.startUpdatingLocation()
                }
            #endif
            case .denied, .restricted:
                self.isGPSAvailable = false
                self.permissionContinuation?.resume(returning: false)
                self.permissionContinuation = nil
            case .notDetermined:
                break
            @unknown default:
                self.isGPSAvailable = false
                self.permissionContinuation?.resume(returning: false)
                self.permissionContinuation = nil
            }
        }
    }
    
    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let clError = error as? CLError {
                if clError.code == .denied {
                    self.isGPSAvailable = false
                }
            }
        }
    }
    
    // MARK: - Motion Monitoring
    
    private func startMotionTracking() {
        #if os(iOS) && canImport(CoreMotion)
        guard let motionActivityManager else { return }
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        
        motionActivityManager.startActivityUpdates(to: motionQueue) { [weak self] activity in
            guard let activity else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // User is stationary if stationary flag is true and not walking/running
                let stationary = activity.stationary && !activity.walking && !activity.running
                self.setStationaryState(stationary)
            }
        }
        #endif
    }
    
    private func stopMotionTracking() {
        #if os(iOS) && canImport(CoreMotion)
        motionActivityManager?.stopActivityUpdates()
        #endif
    }
    
    private func setStationaryState(_ stationary: Bool) {
        guard isStationary != stationary else { return }
        self.isStationary = stationary
        
        // When motion state changes, restart scheduler to adopt new cadence immediately
        if isTracking && isLiveSharingEnabled {
            startPublishingScheduler()
        }
    }
    
    // MARK: - Battery & Survival Mode Monitoring
    
    public func updateBatteryState() {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawLevel = UIDevice.current.batteryLevel
        // UIDevice returns -1.0 if monitoring is unsupported (e.g. simulator)
        let battery = rawLevel >= 0 ? rawLevel : 1.0
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        #else
        let battery: Float = 1.0
        let isLowPower = false
        #endif
        
        applyBatteryLevel(battery, isLowPower: isLowPower)
    }
    
    public func applyBatteryLevel(_ level: Float, isLowPower: Bool = false) {
        self.currentBatteryLevel = min(1.0, max(0.0, level))
        let survival = (currentBatteryLevel < 0.20) || isLowPower
        
        if isSurvivalModeActive != survival {
            self.isSurvivalModeActive = survival
            if isTracking && isLiveSharingEnabled {
                startPublishingScheduler()
            }
        }
    }
    
    // MARK: - Simulation & Testing Hooks
    
    /// Simulates a location update for deterministic unit testing.
    public func simulateLocation(
        coordinate: CLLocationCoordinate2D,
        accuracy: CLLocationAccuracy = 5.0,
        timestamp: Date? = nil,
        speed: CLLocationSpeed = -1.0
    ) {
        let ts = timestamp ?? dateProvider()
        let location = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: accuracy,
            course: 0,
            speed: speed,
            timestamp: ts
        )
        applyLocationMeasurement(location)
    }
    
    /// Simulates heading update for deterministic testing.
    public func simulateHeading(_ heading: CLLocationDirection) {
        self.currentHeading = heading
        if let current = currentLocation {
            self.currentLocation = LocationPin(
                coordinate: current.coordinate,
                horizontalAccuracy: current.horizontalAccuracy,
                timestamp: current.timestamp,
                heading: heading
            )
        }
    }
    
    /// Simulates stationary motion state for testing adaptive cadence selection.
    public func simulateMotionActivity(stationary: Bool) {
        setStationaryState(stationary)
    }
    
    /// Simulates authorization status change for testing permission handling.
    public func simulateAuthorizationStatus(_ status: CLAuthorizationStatus) {
        self.authorizationStatus = status
        switch status {
        #if os(iOS)
        case .authorizedWhenInUse, .authorizedAlways:
            self.isGPSAvailable = true
        #else
        case .authorizedAlways:
            self.isGPSAvailable = true
        #endif
        case .denied, .restricted:
            self.isGPSAvailable = false
        case .notDetermined:
            break
        @unknown default:
            self.isGPSAvailable = false
        }
    }
    
    /// Triggers an immediate publish for testing publisher logic synchronously.
    public func triggerImmediatePublish() {
        publishCurrentState()
    }
}
