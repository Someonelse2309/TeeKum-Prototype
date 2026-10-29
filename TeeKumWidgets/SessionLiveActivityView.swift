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
        ZStack {
            Color.black
            
            if context.state.isSOSActive {
                sosBannerView
            } else {
                normalSessionBannerView
            }
        }
        .padding(14)
        .background(Color.black)
    }
    
    // MARK: - Normal Session Banner
    
    private var normalSessionBannerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Session Name & Direct Peers
            HStack {
                Label {
                    Text(context.attributes.sessionName.uppercased())
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(Color(red: 0.1, green: 0.9, blue: 0.4)) // Neon green
                } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(Color(red: 0.1, green: 0.9, blue: 0.4))
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(context.state.directPeerCount > 0 ? Color(red: 0.1, green: 0.9, blue: 0.4) : Color.gray)
                        .frame(width: 8, height: 8)
                    Text("\(context.state.directPeerCount) PEERS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(white: 0.15))
                .clipShape(Capsule())
            }
            
            Divider().background(Color(white: 0.2))
            
            // Meeting Point Info or Standby Status
            HStack(alignment: .center) {
                if let meetingName = context.state.meetingPointName {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MEETING POINT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.gray)
                        Text(meetingName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    if let meters = context.state.meetingPointDistanceMeters {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatDistance(meters))
                                .font(.system(size: 16, weight: .black, design: .monospaced))
                                .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0)) // Cyber cyan
                            Text("AWAY")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.gray)
                        }
                    }
                    
                    Link(destination: URL(string: "teekum://meeting")!) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(8)
                            .background(Color(red: 0.0, green: 0.85, blue: 1.0))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 6)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.slash")
                            .foregroundStyle(.gray)
                        Text("No active meeting point set")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.gray)
                    }
                    Spacer()
                    
                    Link(destination: URL(string: "teekum://map")!) {
                        Text("OPEN MAP")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                }
            }
            
            Divider().background(Color(white: 0.2))
            
            // Communal Relay Status & Interactive Controls
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(relayIndicatorColor)
                        .frame(width: 7, height: 7)
                    Text(context.state.relayStatusText ?? "RELAY: OFF")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(relayTextColor)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Deep link control surface: Timed 30m, Always, or Stop
                HStack(spacing: 6) {
                    Link(destination: URL(string: "teekum://relay?action=timed")!) {
                        Text("30m")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(white: 0.2))
                            .clipShape(Capsule())
                    }
                    
                    Link(destination: URL(string: "teekum://relay?action=always")!) {
                        Text("Always")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(white: 0.2))
                            .clipShape(Capsule())
                    }
                    
                    if context.state.isRelayActive {
                        Link(destination: URL(string: "teekum://relay?action=stop")!) {
                            Text("Stop")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }
    
    private var relayIndicatorColor: Color {
        if context.state.isRelayActive {
            return Color(red: 0.1, green: 0.9, blue: 0.4)
        } else if (context.state.relayStatusText ?? "").contains("Paused") || (context.state.relayStatusText ?? "").contains("<20%") {
            return .yellow
        } else {
            return .gray
        }
    }
    
    private var relayTextColor: Color {
        if context.state.isRelayActive {
            return Color(red: 0.1, green: 0.9, blue: 0.4)
        } else if (context.state.relayStatusText ?? "").contains("Paused") {
            return .yellow
        } else {
            return .gray
        }
    }
    
    // MARK: - SOS Emergency Alert Banner
    
    private var sosBannerView: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("EMERGENCY SOS ALERT")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text("CRITICAL")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MEMBER CALLING FOR HELP:")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(context.state.sosSenderInitials ?? "UNKNOWN PEER")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                }
                Spacer()
                
                Link(destination: URL(string: "teekum://sos")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        Text("TRACK")
                    }
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(10)
        .background(Color(red: 0.35, green: 0.05, blue: 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red, lineWidth: 1.5)
        )
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }
}
