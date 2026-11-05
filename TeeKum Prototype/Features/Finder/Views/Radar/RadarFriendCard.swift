//
//  RadarFriendCard.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI
import CoreLocation

/// Reusable horizontal card representing a group member in the bottom dock of the radar.
public struct RadarFriendCard: View {
    public let member: Member
    public let distance: CLLocationDistance?
    public let relativeBearing: Double?
    public let isSelected: Bool
    public let theme: RadarTheme
    public let onTap: () -> Void
    
    public init(
        member: Member,
        distance: CLLocationDistance?,
        relativeBearing: Double?,
        isSelected: Bool,
        theme: RadarTheme = .standard,
        onTap: @escaping () -> Void
    ) {
        self.member = member
        self.distance = distance
        self.relativeBearing = relativeBearing
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
    
    private var borderColor: Color {
        if isEmergency {
            return theme.emergencyBlipColor
        } else if isSelected {
            return theme.selectedBlipColor
        } else {
            return Color.white.opacity(0.15)
        }
    }
    
    public var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            HStack(spacing: 10) {
                // Initials Avatar with Status Emoji
                ZStack {
                    Circle()
                        .fill(isEmergency ? theme.emergencyBlipColor : (isSelected ? theme.selectedBlipColor : member.color.swiftUIColor.opacity(0.2)))
                        .frame(width: 38, height: 38)
                        .overlay(
                            Circle().stroke(member.color.swiftUIColor, lineWidth: isSelected ? 2 : 1)
                        )
                    
                    Text(member.initials)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(isEmergency ? .white : (isSelected ? .black : member.color.swiftUIColor))
                }
                .frame(width: 38, height: 38)
                
                // Name & Distance Details
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(member.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        if isEmergency {
                            Text("SOS")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }
                    }
                    
                    HStack(spacing: 6) {
                        // Formatted Distance
                        if let dist = distance {
                            Text(formatDistance(dist))
                                .font(.caption.bold().monospaced())
                                .foregroundStyle(dist <= 15.0 ? .green : (dist <= 30.0 ? .yellow : .white.opacity(0.8)))
                        } else {
                            Text("No Fix")
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                        
                        // Clock Direction Hint
                        if let bearing = relativeBearing {
                            Text("• \(bearing.clockDirection)")
                                .font(.caption2)
                                .foregroundStyle(.cyan.opacity(0.9))
                        }
                    }
                }
                
                // Battery Indicator (if available)
                if let battery = member.batteryLevel {
                    VStack {
                        Image(systemName: battery.batterySystemImage)
                            .font(.system(size: 10))
                            .foregroundStyle(battery <= 0.2 ? .red : .gray)
                        Text(battery.formattedBatteryPercentage)
                            .font(.system(size: 8).monospaced())
                            .foregroundStyle(.gray)
                    }
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.yellow.opacity(0.12) : Color.black.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? theme.selectedBlipColor.opacity(0.4) : Color.clear, radius: 6)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Formatters
    
    private func formatDistance(_ dist: CLLocationDistance) -> String {
        if dist < 8.0 {
            return "NEARBY (<8m)"
        }
        return dist.formattedDistance()
    }
}
