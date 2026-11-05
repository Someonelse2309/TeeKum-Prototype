//
//  RadarGridBackground.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI

/// Reusable background component rendering the tactical radar grid.
/// Draws concentric distance rings, crosshairs, radial degree ticks, and range labels.
public struct RadarGridBackground: View {
    public let radius: CGFloat
    public let theme: RadarTheme
    
    public init(radius: CGFloat, theme: RadarTheme = .standard) {
        self.radius = radius
        self.theme = theme
    }
    
    public var body: some View {
        ZStack {
            // MARK: - Radial Gradient Background Disk
            Circle()
                .fill(
                    RadialGradient(
                        colors: [theme.backgroundCenterColor, theme.backgroundEdgeColor],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
                .frame(width: radius * 2, height: radius * 2)
                .overlay(
                    Circle()
                        .stroke(theme.ringColor, lineWidth: theme.ringLineWidth * 1.5)
                        .shadow(color: theme.ringColor.opacity(0.4), radius: 8)
                )
            
            // MARK: - Crosshairs
            // Vertical axis line
            Rectangle()
                .fill(theme.crosshairColor)
                .frame(width: theme.crosshairLineWidth, height: radius * 2)
            
            // Horizontal axis line
            Rectangle()
                .fill(theme.crosshairColor)
                .frame(width: radius * 2, height: theme.crosshairLineWidth)
            
            // Diagonal subtle guide lines (45° and 135°)
            Rectangle()
                .fill(theme.crosshairColor.opacity(0.4))
                .frame(width: theme.crosshairLineWidth, height: radius * 2)
                .rotationEffect(.degrees(45))
            
            Rectangle()
                .fill(theme.crosshairColor.opacity(0.4))
                .frame(width: theme.crosshairLineWidth, height: radius * 2)
                .rotationEffect(.degrees(135))
            
            // MARK: - Concentric Distance Rings
            ForEach(theme.concentricRanges, id: \.self) { range in
                let fraction = CGFloat(min(1.0, range / theme.maxDisplayRange))
                let ringDiameter = radius * 2 * fraction
                
                Circle()
                    .stroke(
                        theme.ringColor,
                        style: StrokeStyle(
                            lineWidth: theme.ringLineWidth,
                            dash: range < theme.maxDisplayRange ? [4, 4] : []
                        )
                    )
                    .frame(width: ringDiameter, height: ringDiameter)
            }
            
            // MARK: - Perimeter Degree Ticks (Every 15°, Cardinal 90° Ticks Longer)
            ForEach(0..<24, id: \.self) { index in
                let angle = Double(index) * 15.0
                let isCardinal = index % 6 == 0 // 0°, 90°, 180°, 270°
                let tickHeight: CGFloat = isCardinal ? 10.0 : 5.0
                let tickWidth: CGFloat = isCardinal ? 2.0 : 1.0
                
                Rectangle()
                    .fill(isCardinal ? theme.headingIndicatorColor : theme.tickColor)
                    .frame(width: tickWidth, height: tickHeight)
                    .offset(y: -radius + (tickHeight / 2))
                    .rotationEffect(.degrees(angle))
            }
            
            // MARK: - Forward "Ahead" Indicator (12 o'clock)
            VStack(spacing: 2) {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(theme.headingIndicatorColor)
                    .rotationEffect(.degrees(180))
                
                Spacer()
            }
            .frame(height: radius * 2 + 16)
            
            // MARK: - Range Metric Labels
            ForEach(theme.concentricRanges, id: \.self) { range in
                let fraction = CGFloat(min(1.0, range / theme.maxDisplayRange))
                let labelText = range >= theme.maxDisplayRange ? "\(Int(range))m+" : "\(Int(range))m"
                let yOffset = -(radius * fraction)
                
                Text(labelText)
                    .font(theme.labelFont)
                    .foregroundStyle(theme.labelColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .offset(x: 18, y: yOffset)
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}
