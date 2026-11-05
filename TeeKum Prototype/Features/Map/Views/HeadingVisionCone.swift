//
//  HeadingVisionCone.swift
//  TeeKum Prototype
//
//  Created by Nicho on 04/11/26.
//

import SwiftUI
import CoreLocation

/// Sector / wedge shape representing an observer's field-of-view facing North (0°).
public struct VisionConeShape: Shape, Sendable {
    public var fovAngle: Double // Field of view in degrees (e.g. 50°)
    
    public init(fovAngle: Double = 50.0) {
        self.fovAngle = fovAngle
    }
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        let startAngle = Angle(degrees: -90.0 - (fovAngle / 2.0))
        let endAngle = Angle(degrees: -90.0 + (fovAngle / 2.0))
        
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// Translucent glowing field-of-view cone pointing in a compass direction.
public struct HeadingVisionCone: View {
    public let color: Color
    public let radius: CGFloat
    public let fovAngle: Double
    
    public init(color: Color, radius: CGFloat = 40, fovAngle: Double = 50) {
        self.color = color
        self.radius = radius
        self.fovAngle = fovAngle
    }
    
    public var body: some View {
        VisionConeShape(fovAngle: fovAngle)
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        color.opacity(0.40),
                        color.opacity(0.18),
                        color.opacity(0.0)
                    ]),
                    center: .center,
                    startRadius: 4,
                    endRadius: radius
                )
            )
            .frame(width: radius * 2, height: radius * 2)
            .allowsHitTesting(false)
    }
}

/// Composite orientation marker rendering both a soft vision cone and a crisp directional pointer.
public struct DirectionalHeadingIndicator: View {
    public let heading: CLLocationDirection
    public let color: Color
    public let avatarRadius: CGFloat
    public let coneRadius: CGFloat
    public let fovAngle: Double
    
    public init(
        heading: CLLocationDirection,
        color: Color,
        avatarRadius: CGFloat = 22,
        coneRadius: CGFloat = 42,
        fovAngle: Double = 52
    ) {
        self.heading = heading
        self.color = color
        self.avatarRadius = avatarRadius
        self.coneRadius = coneRadius
        self.fovAngle = fovAngle
    }
    
    public var body: some View {
        ZStack {
            // Soft Field-of-View Vision Beam
            HeadingVisionCone(color: color, radius: coneRadius, fovAngle: fovAngle)
                .rotationEffect(.degrees(heading))
            
            // Directional Notch / Arrow Pointer on Circle Perimeter
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.8), radius: 3)
                .offset(y: -(avatarRadius + 3.5))
                .rotationEffect(.degrees(heading))
        }
        .allowsHitTesting(false)
    }
}
