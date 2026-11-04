//
//  RadarBlipView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI
import CoreLocation

/// Reusable marker representing an individual group member on the radar.
/// Renders member initials, status indication, selection highlight ring,
/// and directional edge-clamping indicator when the peer is beyond 60 meters.
public struct RadarBlipView: View {
    public let member: Member
    public let distance: CLLocationDistance?
    public let relativeBearing: Double
    public let isClamped: Bool
    public let isSelected: Bool
    public let theme: RadarTheme
    public let onTap: () -> Void
    
    public init(
        member: Member,
        distance: CLLocationDistance?,
        relativeBearing: Double,
        isClamped: Bool,
        isSelected: Bool,
        theme: RadarTheme = .standard,
        onTap: @escaping () -> Void
    ) {
        self.member = member
        self.distance = distance
        self.relativeBearing = relativeBearing
        self.isClamped = isClamped
        self.isSelected = isSelected
        self.theme = theme
        self.onTap = onTap
    }
    
    private var isEmergency: Bool {
        member.isEmergency
    }
    
    private var isStale: Bool {
        member.isStale(threshold: 60)
    }
    
    private var memberBaseColor: Color {
        member.color.swiftUIColor
    }
    
    private var markerColor: Color {
        if isEmergency {
            return theme.emergencyBlipColor
        } else if isSelected {
            return theme.selectedBlipColor
        } else if isStale {
            return theme.staleBlipColor
        } else {
            return memberBaseColor
        }
    }
    
    public var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onTap()
        } label: {
            ZStack {
                // MARK: - Selected / Emergency Outer Highlight Ring
                if isSelected || isEmergency {
                    Circle()
                        .stroke(markerColor.opacity(0.5), lineWidth: 3)
                        .frame(width: theme.blipSize + 12, height: theme.blipSize + 12)
                        .shadow(color: markerColor.opacity(0.8), radius: 6)
                }
                
                // MARK: - Clamped Beyond 60m Directional Arrow
                if isClamped {
                    // Arrow pointing outward along relative bearing
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(markerColor)
                        .offset(y: -(theme.blipSize / 2 + 7))
                        .rotationEffect(.degrees(relativeBearing))
                }
                
                // MARK: - Main Blip Circle
                Circle()
                    .fill(Color.black.opacity(0.88))
                    .frame(width: theme.blipSize, height: theme.blipSize)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? theme.selectedBlipColor : (isEmergency ? theme.emergencyBlipColor : (isStale ? memberBaseColor.opacity(0.6) : memberBaseColor)), lineWidth: isSelected ? 2.5 : 1.5)
                    )
                    .shadow(color: (isSelected ? theme.selectedBlipColor : memberBaseColor).opacity(isSelected ? 0.6 : 0.35), radius: isSelected ? 8 : 4)
                
                // Member initials
                Text(member.initials)
                    .font(theme.initialsFont)
                    .foregroundStyle(isEmergency ? theme.emergencyBlipColor : (isSelected ? theme.selectedBlipColor : memberBaseColor))
                    .lineLimit(1)
                
                // MARK: - Status Badge Corner Overlay
                VStack {
                    HStack {
                        Spacer()
                        if isEmergency {
                            Circle()
                                .fill(theme.emergencyBlipColor)
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Circle().stroke(Color.black, lineWidth: 1.5)
                                )
                        } else if isStale {
                            Circle()
                                .fill(theme.staleBlipColor)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle().stroke(Color.black, lineWidth: 1)
                                )
                        }
                    }
                    Spacer()
                }
                .frame(width: theme.blipSize, height: theme.blipSize)
                
                // MARK: - Clamped Distance Badge
                if isClamped, let dist = distance {
                    VStack {
                        Spacer()
                        Text(formatDistance(dist))
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(markerColor.opacity(0.85))
                            .clipShape(Capsule())
                            .offset(y: theme.blipSize / 2 + 6)
                    }
                    .frame(width: theme.blipSize, height: theme.blipSize)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(member.name), \(distance != nil ? "\(Int(distance!)) meters" : "unknown distance")")
        .accessibilityHint(isSelected ? "Selected target" : "Double-tap to highlight and track this friend")
    }
    
    private func formatDistance(_ dist: CLLocationDistance) -> String {
        if dist >= 1000.0 {
            return String(format: "%.1fk", dist / 1000.0)
        } else {
            return "\(Int(dist))m"
        }
    }
}
