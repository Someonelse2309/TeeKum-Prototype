//
//  SessionLiveActivityView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 28/10/26.
//

import SwiftUI
import WidgetKit
import ActivityKit

/// Standalone Lock Screen and Dynamic Island presentation views for the TeeKum Active Session Companion.
public struct SessionLiveActivityView: View {
    let context: ActivityViewContext<SessionActivityAttributes>
    
    public init(context: ActivityViewContext<SessionActivityAttributes>) {
        self.context = context
    }
    
    public var body: some View {
        VStack(spacing: 10) {
            // Top Row: Session Brand & Connected Peers & End Action
            headerRow
            
            // Middle Section: Glanceable Content (SOS / Meeting Point / Mesh Standby)
            if context.state.isSOSActive {
                sosHeroCard
            } else if let meetingName = context.state.meetingPointName {
                meetingPointHeroCard(name: meetingName)
            } else {
                standbyHeroCard
            }
            
            // Bottom Row: Telemetry Indicators & User Tag
            footerRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.10)
                RadialGradient(
                    colors: [
                        accentGlowColor.opacity(0.14),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 200
                )
            }
        )
    }
    
    // MARK: - Header Row
    
    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            // Festival Mesh Brand & Session Name
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(accentGlowColor.opacity(0.20))
                        .frame(width: 22, height: 22)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accentGlowColor)
                }
                
                Text(context.attributes.sessionName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Online Friends Count Pill
            HStack(spacing: 5) {
                Circle()
                    .fill(context.state.directPeerCount > 0 ? Color(red: 0.15, green: 0.90, blue: 0.45) : Color.gray.opacity(0.6))
                    .frame(width: 6, height: 6)
                Text("\(context.state.directPeerCount) \(context.state.directPeerCount == 1 ? "friend" : "friends")")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
            
            // Interactive End Session Button (AppIntent)
            Button(intent: EndSessionIntent()) {
                HStack(spacing: 3) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("End")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.40))
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color.red.opacity(0.18))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End festival session")
        }
    }
    
    // MARK: - Meeting Point Hero Card
    
    private func meetingPointHeroCard(name: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.15))
                    .frame(width: 40, height: 40)
                Circle()
                    .stroke(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.45), lineWidth: 1.5)
                    .frame(width: 40, height: 40)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("ACTIVE RENDEZVOUS")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.9))
                    .tracking(0.6)
                Text(name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let meters = context.state.meetingPointDistanceMeters {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatDistance(meters))
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("away")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.gray)
                }
            }
            
            Link(destination: URL(string: "teekum://meeting")!) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(Color(red: 0.0, green: 0.85, blue: 1.0))
                    .clipShape(Circle())
                    .shadow(color: Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.45), radius: 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }
    
    // MARK: - Standby Hero Card
    
    private var standbyHeroCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.15, green: 0.90, blue: 0.45).opacity(0.15))
                    .frame(width: 38, height: 38)
                Circle()
                    .stroke(Color(red: 0.15, green: 0.90, blue: 0.45).opacity(0.4), lineWidth: 1.5)
                    .frame(width: 38, height: 38)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.15, green: 0.90, blue: 0.45))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("MESH ACTIVE")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.15, green: 0.90, blue: 0.45))
                    .tracking(0.6)
                Text(context.state.directPeerCount > 0 ? "Location sharing live" : "Searching for nearby friends")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Link(destination: URL(string: "teekum://map")!) {
                HStack(spacing: 3) {
                    Text("Map")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5.5)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - SOS Alert Hero Card
    
    private var sosHeroCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.25))
                    .frame(width: 42, height: 42)
                Circle()
                    .stroke(Color.red, lineWidth: 2)
                    .frame(width: 42, height: 42)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.yellow)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("EMERGENCY ALERT")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.red)
                    .tracking(0.8)
                Text("\(context.state.sosSenderInitials ?? "Friend") needs help")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Link(destination: URL(string: "teekum://sos")!) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    Text("FIND")
                }
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.red)
                .clipShape(Capsule())
                .shadow(color: Color.red.opacity(0.55), radius: 5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(red: 0.28, green: 0.05, blue: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.red.opacity(0.6), lineWidth: 1.5)
        )
    }
    
    // MARK: - Footer Row
    
    private var footerRow: some View {
        HStack {
            // Communal Relay Status Pill
            HStack(spacing: 5) {
                Circle()
                    .fill(relayIndicatorColor)
                    .frame(width: 5, height: 5)
                Text(relayStatusSummary)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(relayTextColor)
            }
            
            Spacer()
            
            // Local User Tag
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray.opacity(0.8))
                Text("You: \(context.attributes.userInitials)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray.opacity(0.9))
            }
        }
    }
    
    // MARK: - Helpers
    
    private var accentGlowColor: Color {
        if context.state.isSOSActive {
            return .red
        } else if context.state.meetingPointName != nil {
            return Color(red: 0.0, green: 0.85, blue: 1.0)
        } else {
            return Color(red: 0.15, green: 0.90, blue: 0.45)
        }
    }
    
    private var relayStatusSummary: String {
        if context.state.isRelayActive {
            if let remaining = context.state.timedRelayRemainingSeconds, remaining > 0 {
                let mins = max(1, remaining / 60)
                return "Relaying (\(mins)m left)"
            }
            return "Relaying for festival crowd"
        } else if (context.state.relayStatusText ?? "").contains("Paused") || (context.state.relayStatusText ?? "").contains("<20%") {
            return "Relay paused (low battery)"
        } else {
            return "Mesh peer • Relay off"
        }
    }
    
    private var relayIndicatorColor: Color {
        if context.state.isRelayActive {
            return Color(red: 0.15, green: 0.90, blue: 0.45)
        } else if (context.state.relayStatusText ?? "").contains("Paused") || (context.state.relayStatusText ?? "").contains("<20%") {
            return .yellow
        } else {
            return .gray.opacity(0.7)
        }
    }
    
    private var relayTextColor: Color {
        if context.state.isRelayActive {
            return Color(red: 0.15, green: 0.90, blue: 0.45)
        } else if (context.state.relayStatusText ?? "").contains("Paused") {
            return .yellow
        } else {
            return .gray
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }
}
