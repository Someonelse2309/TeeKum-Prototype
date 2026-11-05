//
//  MapViewModel.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import Observation
import CoreLocation

/// Pure MVVM ViewModel governing the primary festival MapKit interface,
/// Live Sharing toggle state, friend pin rendering, location age/accuracy display,
/// and non-intrusive status pills.
@Observable
@MainActor
public final class MapViewModel {
    
    /// Reference to the authoritative location service provider.
    public var locationService: LocationServiceProvider? {
        didSet {
            if let service = locationService {
                self.isLiveSharingEnabled = service.isLiveSharingEnabled
                self.currentHeading = service.currentHeading
                service.onHeadingUpdate = { [weak self] heading in
                    self?.currentHeading = heading
                }
            }
        }
    }
    
    /// Master toggle: when ON, coordinates are published; when OFF, ordinary broadcasting is paused.
    public var isLiveSharingEnabled: Bool = true {
        didSet {
            if let locationService, locationService.isLiveSharingEnabled != isLiveSharingEnabled {
                locationService.isLiveSharingEnabled = isLiveSharingEnabled
            }
        }
    }
    
    /// Target friend currently selected for directed navigation.
    public var selectedMember: Member?
    
    /// Backing store for user location when no service is attached.
    private var _userLocation: LocationPin?
    
    /// Current magnetic compass heading in degrees (0..<360), tracked for reactive UI updates.
    public var currentHeading: CLLocationDirection?
    
    /// Current user's local location.
    public var userLocation: LocationPin? {
        get {
            locationService?.currentLocation ?? _userLocation
        }
        set {
            _userLocation = newValue
        }
    }
    
    /// Horizontal accuracy uncertainty radius in meters.
    public var horizontalAccuracy: CLLocationAccuracy? {
        userLocation?.horizontalAccuracy
    }
    
    /// Seconds elapsed since the current location was measured.
    public var locationAge: TimeInterval? {
        locationService?.locationAge
    }
    
    /// True when the user's current location measurement is stale.
    public var isLocationStale: Bool {
        locationService?.isLocationStale ?? false
    }
    
    /// True when GPS receiver is available and functioning.
    public var isGPSAvailable: Bool {
        locationService?.isGPSAvailable ?? true
    }
    
    /// True when device battery is <20% or in Low Power Mode.
    public var isFestivalSurvivalMode: Bool {
        locationService?.isSurvivalModeActive ?? false
    }
    
    /// Non-intrusive status pill message displayed at the top of the map.
    public var statusPillMessage: String {
        guard let locationService else {
            return isLiveSharingEnabled ? "Live Sharing Active" : "Live Sharing Paused"
        }
        
        let auth = locationService.authorizationStatus
        if auth == .denied || auth == .restricted {
            return "Permission Denied"
        }
        
        if locationService.isSurvivalModeActive {
            return "Survival Mode (<20%)"
        }
        
        if !isLiveSharingEnabled {
            return "Live Sharing Paused"
        }
        
        if !locationService.isGPSAvailable || locationService.isLocationStale {
            return "Live Sharing Active (GPS Weak)"
        }
        
        return "Live Sharing Active"
    }
    
    public init(
        locationService: LocationServiceProvider? = nil,
        isLiveSharingEnabled: Bool = true,
        selectedMember: Member? = nil
    ) {
        self.locationService = locationService
        self.isLiveSharingEnabled = locationService?.isLiveSharingEnabled ?? isLiveSharingEnabled
        self.selectedMember = selectedMember
        self.currentHeading = locationService?.currentHeading
        locationService?.onHeadingUpdate = { [weak self] heading in
            self?.currentHeading = heading
        }
    }
    
    /// Toggles the user-controlled Live Sharing master switch.
    public func toggleLiveSharing() {
        isLiveSharingEnabled.toggle()
    }
    
    /// Selects a friend to initiate directed radar / navigation.
    public func selectMemberForNavigation(_ member: Member) {
        self.selectedMember = member
    }
    
    /// Clears active navigation target.
    public func clearNavigationTarget() {
        self.selectedMember = nil
    }
    
    /// Enables or disables high-precision navigation mode on the location service.
    public func setTacticalRadarActive(_ active: Bool) {
        locationService?.setTacticalRadarActive(active)
    }
    
    /// Computes straight-line distance in meters to a given member.
    public func distance(to member: Member) -> CLLocationDistance? {
        guard let memberCoord = member.coordinate else { return nil }
        return userLocation?.distance(to: memberCoord)
    }
    
    /// Computes forward bearing in degrees to a given member.
    public func bearing(to member: Member) -> Double? {
        guard let memberCoord = member.coordinate else { return nil }
        return userLocation?.bearing(to: memberCoord)
    }
    
    /// Requests the freshest available location immediately for emergency SOS.
    public func getLatestLocationForSOS() -> LocationPin? {
        locationService?.getLatestLocationForSOS() ?? userLocation
    }
}
