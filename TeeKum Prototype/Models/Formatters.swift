//
//  Formatters.swift
//  TeeKum Prototype
//
//  Created by Nicho on 04/11/26.
//

import Foundation
import CoreLocation

// MARK: - Distance Formatting Extension

extension CLLocationDistance {
    /// Formats a distance into a human-readable metric string (e.g. "45 m", "1.2 km").
    ///
    /// - Parameters:
    ///   - spaced: Whether to place a space between the number and unit (e.g. "1.2 km" vs "1.2km"). Default is true.
    ///   - includeSuffix: If true, appends " away" (e.g. "1.2 km away"). Default is false.
    public func formattedDistance(spaced: Bool = true, includeSuffix: Bool = false) -> String {
        let text: String
        let space = spaced ? " " : ""
        if self >= 1000.0 {
            text = String(format: "%.1f\(space)km", self / 1000.0)
        } else {
            text = String(format: "%.0f\(space)m", self)
        }
        return includeSuffix ? "\(text) away" : text
    }
}

// MARK: - Battery Formatting & Quantization Extension

extension Float {
    /// Converts a normalized battery level (0.0 to 1.0) into a clamped 0...100 UInt8 percentage.
    public var asBatteryPercentage: UInt8 {
        UInt8(min(100, max(0, Int((self * 100.0).rounded()))))
    }
    
    /// Formats normalized battery level as a percentage string (e.g. "85%").
    public var formattedBatteryPercentage: String {
        String(format: "%.0f%%", (self * 100.0).rounded())
    }
    
    /// Returns the standard SF Symbol icon name corresponding to this normalized battery level (0.0 to 1.0).
    public var batterySystemImage: String {
        if self <= 0.20 {
            return "battery.25"
        } else if self <= 0.50 {
            return "battery.50"
        } else if self <= 0.75 {
            return "battery.75"
        } else {
            return "battery.100"
        }
    }
}

// MARK: - Relative Date Formatting & Time Display Extensions

extension Date {
    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    
    private static let secondsTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    
    private static let meetupTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
    
    /// Formats date to "HH:mm" (e.g. "14:35") without reallocating formatters.
    public var formattedShortTime: String {
        Self.shortTimeFormatter.string(from: self)
    }

    /// Formats date to "HH:mm:ss" (e.g. "14:35:12") without reallocating formatters.
    public var formattedSecondsTime: String {
        Self.secondsTimeFormatter.string(from: self)
    }

    /// Formats date to "h:mm a" (e.g. "2:35 PM") without reallocating formatters.
    public var formattedMeetupTime: String {
        Self.meetupTimeFormatter.string(from: self)
    }

    /// Formats the elapsed time since this date into a compact festival badge (e.g. "12s ago", "4m ago", "2h ago").
    public func compactTimeAgo(from now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(self))
        if elapsed < 60 {
            return "\(Int(elapsed))s ago"
        }
        let minutes = Int(elapsed / 60)
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = Int(minutes / 60)
        return "\(hours)h ago"
    }
}

// MARK: - Coordinate Quantization Extension

extension CLLocationCoordinate2D {
    /// Big-endian signed 32-bit integer representing latitude (~11cm resolution worldwide).
    public var rawLatitude: Int32 {
        Int32((latitude * LocationPin.coordinateScalingFactor).rounded())
    }
    
    /// Big-endian signed 32-bit integer representing longitude (~11cm resolution worldwide).
    public var rawLongitude: Int32 {
        Int32((longitude * LocationPin.coordinateScalingFactor).rounded())
    }
    
    /// Dequantizes signed 32-bit raw integer coordinates back into a native `CLLocationCoordinate2D`.
    public static func dequantize(latitudeRaw: Int32, longitudeRaw: Int32) -> CLLocationCoordinate2D {
        LocationPin.dequantize(latitudeRaw: latitudeRaw, longitudeRaw: longitudeRaw)
    }
}

// MARK: - Compass Heading Quantization Extension

extension CLLocationDirection {
    /// Quantizes compass heading (0..<360) into a single 1-byte integer (0...255).
    public var quantizedHeadingByte: UInt8 {
        UInt8(min(255, max(0, Int((self * 255.0 / 360.0).rounded()))))
    }
    
    /// Reconstructs compass heading in degrees from a 1-byte quantized integer.
    public static func fromHeadingByte(_ byte: UInt8) -> CLLocationDirection {
        Double(byte) * 360.0 / 255.0
    }
}

// MARK: - Relative Clock Direction Extension

extension Double {
    /// Formats a relative bearing (0..<360 degrees) into a tactical clock direction (e.g. "Ahead", "2 o'clock", "Behind").
    public var clockDirection: String {
        let normalized = (self + 360.0).truncatingRemainder(dividingBy: 360.0)
        let hour = Int((normalized + 15.0) / 30.0) % 12
        let displayHour = hour == 0 ? 12 : hour
        if displayHour == 12 {
            return "Ahead"
        } else if displayHour == 6 {
            return "Behind"
        } else {
            return "\(displayHour) o'clock"
        }
    }
}
