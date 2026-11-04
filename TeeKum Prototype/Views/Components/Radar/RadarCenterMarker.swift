//
//  RadarCenterMarker.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI

/// Reusable center marker rendering the local user position and orientation on the radar.
public struct RadarCenterMarker: View {
    public let theme: RadarTheme
    public let userColor: Color?
    
    public init(theme: RadarTheme = .standard, userColor: Color? = nil) {
        self.theme = theme
        self.userColor = userColor
    }
    
    private var markerColor: Color {
        userColor ?? theme.userMarkerColor
    }
    
    public var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .stroke(markerColor.opacity(0.4), lineWidth: 2)
                .frame(width: theme.userMarkerSize * 1.5, height: theme.userMarkerSize * 1.5)
            
            // Solid center disk
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: theme.userMarkerSize, height: theme.userMarkerSize)
                .overlay(
                    Circle()
                        .stroke(markerColor, lineWidth: 2)
                )
            
            // Forward-pointing orientation arrow
            Image(systemName: "location.north.fill")
                .font(.system(size: theme.userMarkerSize * 0.55, weight: .bold))
                .foregroundStyle(markerColor)
                .shadow(color: markerColor, radius: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your position, facing forward")
    }
}
