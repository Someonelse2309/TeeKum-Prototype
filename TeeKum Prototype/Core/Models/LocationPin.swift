//
//  LocationPin.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation

/// Canonical geographic location measurement representation for TeeKum.
public struct LocationPin: Equatable, Hashable, Sendable {
    /// Geographical coordinate (64-bit IEEE 754 Double precision degrees).
    public let coordinate: CLLocationCoordinate2D
    
    /// Estimated horizontal accuracy uncertainty radius in meters.
    public let horizontalAccuracy: CLLocationAccuracy
    
    /// Exact UTC timestamp when the measurement was taken by the hardware GPS receiver.
    /// Note: Intermediary relays must NEVER mutate or refresh this timestamp.
    public let timestamp: Date
    
    /// Optional device magnetic heading at measurement time (0..<360 degrees).
    public let heading: CLLocationDirection?
    
    public init(
        coordinate: CLLocationCoordinate2D,
        horizontalAccuracy: CLLocationAccuracy,
        timestamp: Date = Date(),
        heading: CLLocationDirection? = nil
    ) {
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
        self.heading = heading
    }
    
    // MARK: - Fixed 56-Byte Wire Quantization Helpers
    
    /// Conversion constant between Double degrees and Int32 wire quantization (~11cm resolution).
    public static let coordinateScalingFactor: Double = 1_000_000.0
    
    /// Quantized big-endian signed 32-bit integer representing latitude (`degrees * 1_000_000`).
    public var rawLatitude: Int32 {
        Int32((coordinate.latitude * Self.coordinateScalingFactor).rounded())
    }
    
    /// Quantized big-endian signed 32-bit integer representing longitude (`degrees * 1_000_000`).
    public var rawLongitude: Int32 {
        Int32((coordinate.longitude * Self.coordinateScalingFactor).rounded())
    }
    
    /// Compact single-byte horizontal accuracy in meters (clamped 0...255).
    public var rawAccuracyByte: UInt8 {
        UInt8(min(255.0, max(0.0, horizontalAccuracy.rounded())))
    }
    
    /// Dequantizes 32-bit signed raw wire coordinates back into a native `CLLocationCoordinate2D`.
    public static func dequantize(latitudeRaw: Int32, longitudeRaw: Int32) -> CLLocationCoordinate2D {
        let lat = Double(latitudeRaw) / Self.coordinateScalingFactor
        let lon = Double(longitudeRaw) / Self.coordinateScalingFactor
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    // MARK: - Navigation Computations
    public func distance(to target: CLLocationCoordinate2D) -> CLLocationDistance {
        let currentLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let targetLoc = CLLocation(latitude: target.latitude, longitude: target.longitude)
        return currentLoc.distance(from: targetLoc)
    }
    
    /// Computes the forward bearing (azimuth) in degrees (0..<360) from this location to a target.
    public func bearing(to target: CLLocationCoordinate2D) -> Double {
        let lat1 = coordinate.latitude * .pi / 180.0
        let lon1 = coordinate.longitude * .pi / 180.0
        let lat2 = target.latitude * .pi / 180.0
        let lon2 = target.longitude * .pi / 180.0
        
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radiansBearing = atan2(y, x)
        
        let degrees = radiansBearing * 180.0 / .pi
        return (degrees + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
    
    public static func == (lhs: LocationPin, rhs: LocationPin) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.horizontalAccuracy == rhs.horizontalAccuracy &&
        lhs.timestamp == rhs.timestamp &&
        lhs.heading == rhs.heading
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(horizontalAccuracy)
        hasher.combine(timestamp)
    }
}

// MARK: - CoreLocation Conformance

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

extension CLLocationCoordinate2D: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
}

