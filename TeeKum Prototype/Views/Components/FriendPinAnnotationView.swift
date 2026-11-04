//
//  FriendPinAnnotationView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 04/11/26.
//

import SwiftUI
import CoreLocation

/// Renders a member pin annotation on the MapKit canvas.
///
/// Features:
/// - Directional heading cone (50° field of view) and rim arrow pointer.
/// - Pulsing emergency ring for distress status.
/// - Initials avatar disk with personal neon color stroke.
/// - Stale indicator badge and relative age label.
public struct FriendPinAnnotationView: View {
    public let member: Member
    
    public init(member: Member) {
        self.member = member
    }
    
    public var body: some View {
        let isStale = member.isStale()
        let isEmergency = member.isEmergency
        let memberColor = member.color.swiftUIColor
        let pinAccentColor = isEmergency ? Color.red : (isStale ? memberColor.opacity(0.6) : memberColor)
        
        VStack(spacing: 4) {
            ZStack {
                // Directional Heading Indicator (Vision Cone + Perimeter Pointer)
                if let heading = member.heading {
                    DirectionalHeadingIndicator(
                        heading: heading,
                        color: pinAccentColor,
                        avatarRadius: 22,
                        coneRadius: 44,
                        fovAngle: 52
                    )
                }
                
                // Outer ring
                if isEmergency {
                    Circle()
                        .stroke(Color.red.opacity(0.6), lineWidth: 4)
                        .frame(width: 52, height: 52)
                }
                
                Circle()
                    .stroke(
                        pinAccentColor,
                        lineWidth: isEmergency ? 3 : 2
                    )
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(Color.black.opacity(0.8))
                    )
                    .shadow(color: isEmergency ? Color.red.opacity(0.8) : memberColor.opacity(0.4), radius: 4)
                
                Text(member.initials)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(isEmergency ? .red : memberColor)
                
                // Stale warning indicator badge
                if isStale {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 10, height: 10)
                        }
                        Spacer()
                    }
                    .frame(width: 44, height: 44)
                }
            }
            .opacity(isStale ? 0.65 : 1.0)
            
            // Name & Freshness Tag
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    if isEmergency {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8).bold())
                            .foregroundStyle(.red)
                    }
                    Text(member.name)
                        .font(.caption2.bold())
                        .foregroundStyle(isEmergency ? .red : memberColor)
                }
                
                if isEmergency {
                    Text("EMERGENCY")
                        .font(.system(size: 7).bold())
                        .foregroundStyle(.red)
                } else if isStale {
                    Text("Stale • \(member.lastSeen.compactTimeAgo())")
                        .font(.system(size: 8).bold())
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.85))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isEmergency ? Color.red.opacity(0.7) : (isStale ? Color.orange.opacity(0.5) : memberColor.opacity(0.4)), lineWidth: 1)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(member.name)\(member.isEmergency ? ", emergency SOS active" : "")\(member.heading.map { ", facing \(Int($0)) degrees" } ?? "")")
        .accessibilityValue(isStale ? "Stale location measured \(member.lastSeen.compactTimeAgo())" : "Live location")
        .accessibilityHint("Double tap to view friend details and navigation.")
    }
}
