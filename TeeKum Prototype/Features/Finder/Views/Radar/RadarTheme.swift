//
//  RadarTheme.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI

/// Styling and geometry configuration for the reusable Tactical Radar.
/// Allows fast adjustments to the color palette, distance ranges, line widths, and marker sizes.
public struct RadarTheme: Sendable {
    // MARK: - Color Palette
    
    /// Radial background gradient colors (Center to Edge).
    public var backgroundCenterColor: Color
    public var backgroundEdgeColor: Color
    
    /// Grid concentric rings and boundary stroke color.
    public var ringColor: Color
    
    /// Crosshair lines stroke color.
    public var crosshairColor: Color
    
    /// Perimeter angle tick marks color.
    public var tickColor: Color
    
    /// Distance label and unit text color.
    public var labelColor: Color
    
    /// Cardinal and heading indicator color.
    public var headingIndicatorColor: Color
    
    /// User center marker primary and glow colors.
    public var userMarkerColor: Color
    public var userMarkerGlowColor: Color
    
    /// Blip status colors.
    public var normalBlipColor: Color
    public var selectedBlipColor: Color
    public var emergencyBlipColor: Color
    public var staleBlipColor: Color
    
    /// Directional bearing guide line color.
    public var guideLineColor: Color
    
    // MARK: - Geometry & Ranges
    
    /// Concentric distance ring intervals in meters. Default: [15.0, 30.0, 60.0].
    public var concentricRanges: [Double]
    
    /// Maximum display range before clamping peers to the outer ring in meters. Default: 60.0.
    public var maxDisplayRange: Double
    
    /// Ring stroke line width.
    public var ringLineWidth: CGFloat
    
    /// Crosshair stroke line width.
    public var crosshairLineWidth: CGFloat
    
    /// Guide line stroke width.
    public var guideLineWidth: CGFloat
    
    /// User center marker size in points.
    public var userMarkerSize: CGFloat
    
    /// Peer blip diameter in points.
    public var blipSize: CGFloat
    
    // MARK: - Typography
    
    /// Font for range badges (e.g., "15m", "30m", "60m+").
    public var labelFont: Font
    
    /// Font for member initials inside blips.
    public var initialsFont: Font
    
    public init(
        backgroundCenterColor: Color = Color(red: 0.04, green: 0.12, blue: 0.28),
        backgroundEdgeColor: Color = Color(red: 0.01, green: 0.03, blue: 0.08),
        ringColor: Color = Color.cyan.opacity(0.38),
        crosshairColor: Color = Color.cyan.opacity(0.22),
        tickColor: Color = Color.cyan.opacity(0.45),
        labelColor: Color = Color.cyan.opacity(0.85),
        headingIndicatorColor: Color = Color.cyan,
        userMarkerColor: Color = Color.cyan,
        userMarkerGlowColor: Color = Color.cyan.opacity(0.55),
        normalBlipColor: Color = Color.green,
        selectedBlipColor: Color = Color.yellow,
        emergencyBlipColor: Color = Color.red,
        staleBlipColor: Color = Color.orange,
        guideLineColor: Color = Color.cyan.opacity(0.75),
        concentricRanges: [Double] = [15.0, 30.0, 60.0],
        maxDisplayRange: Double = 60.0,
        ringLineWidth: CGFloat = 1.5,
        crosshairLineWidth: CGFloat = 1.0,
        guideLineWidth: CGFloat = 1.5,
        userMarkerSize: CGFloat = 28.0,
        blipSize: CGFloat = 36.0,
        labelFont: Font = .system(size: 10, weight: .bold, design: .monospaced),
        initialsFont: Font = .system(size: 11, weight: .black, design: .rounded)
    ) {
        self.backgroundCenterColor = backgroundCenterColor
        self.backgroundEdgeColor = backgroundEdgeColor
        self.ringColor = ringColor
        self.crosshairColor = crosshairColor
        self.tickColor = tickColor
        self.labelColor = labelColor
        self.headingIndicatorColor = headingIndicatorColor
        self.userMarkerColor = userMarkerColor
        self.userMarkerGlowColor = userMarkerGlowColor
        self.normalBlipColor = normalBlipColor
        self.selectedBlipColor = selectedBlipColor
        self.emergencyBlipColor = emergencyBlipColor
        self.staleBlipColor = staleBlipColor
        self.guideLineColor = guideLineColor
        self.concentricRanges = concentricRanges
        self.maxDisplayRange = maxDisplayRange
        self.ringLineWidth = ringLineWidth
        self.crosshairLineWidth = crosshairLineWidth
        self.guideLineWidth = guideLineWidth
        self.userMarkerSize = userMarkerSize
        self.blipSize = blipSize
        self.labelFont = labelFont
        self.initialsFont = initialsFont
    }
    
    /// Default tactical dark-blue radar theme.
    public static let standard = RadarTheme()
}
