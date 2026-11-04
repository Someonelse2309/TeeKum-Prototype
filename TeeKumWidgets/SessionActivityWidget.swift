//
//  SessionActivityWidget.swift
//  TeeKum Prototype
//
//  Created by Nicho on 28/10/26.
//

import SwiftUI
import WidgetKit
import ActivityKit

public struct SessionActivityWidget: Widget {
    public init() {}
    
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            // Lock Screen and StandBy presentation
            SessionLiveActivityView(context: context)
                .activityBackgroundTint(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.95))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Leading
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill((context.state.isSOSActive ? Color.red : Color(red: 0.15, green: 0.90, blue: 0.45)).opacity(0.2))
                                .frame(width: 20, height: 20)
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(context.state.isSOSActive ? .red : Color(red: 0.15, green: 0.90, blue: 0.45))
                        }
                        Text(context.attributes.sessionName)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                
                // Expanded Trailing
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(context.state.directPeerCount > 0 ? Color(red: 0.15, green: 0.90, blue: 0.45) : Color.gray)
                            .frame(width: 5, height: 5)
                        Text("\(context.state.directPeerCount) online")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.trailing, 4)
                }
                
                // Expanded Center / Bottom
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isSOSActive {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("SOS: \(context.state.sosSenderInitials ?? "Friend")")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Link(destination: URL(string: "teekum://sos")!) {
                                Text("FIND")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 4)
                    } else if let meetingName = context.state.meetingPointName {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(meetingName)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if let meters = context.state.meetingPointDistanceMeters {
                                    Text("\(Int(meters))m away")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(.gray)
                                }
                            }
                            
                            Spacer()
                            
                            Link(destination: URL(string: "teekum://meeting")!) {
                                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.black)
                                    .padding(6)
                                    .background(Color(red: 0.0, green: 0.85, blue: 1.0))
                                    .clipShape(Circle())
                            }
                            
                            Button(intent: EndSessionIntent()) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.40))
                                    .padding(6)
                                    .background(Color.red.opacity(0.18))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 4)
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(context.state.isRelayActive ? Color(red: 0.15, green: 0.90, blue: 0.45) : Color.gray)
                                .frame(width: 5, height: 5)
                            Text(context.state.relayStatusText ?? "Festival Mesh Live")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(context.state.isRelayActive ? Color(red: 0.15, green: 0.90, blue: 0.45) : .gray)
                            
                            Spacer()
                            
                            Button(intent: EndSessionIntent()) {
                                Text("End")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.40))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.red.opacity(0.18))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                // Compact Leading
                HStack(spacing: 3) {
                    if context.state.isSOSActive {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(context.state.directPeerCount > 0 ? Color(red: 0.15, green: 0.90, blue: 0.45) : Color.gray)
                    }
                    Text("\(context.state.directPeerCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            } compactTrailing: {
                // Compact Trailing
                if context.state.isSOSActive {
                    Text("SOS")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.red)
                } else if let meters = context.state.meetingPointDistanceMeters {
                    Text("\(Int(meters))m")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
                } else {
                    Text(context.attributes.userInitials)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
            } minimal: {
                // Minimal
                if context.state.isSOSActive {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(context.state.directPeerCount > 0 ? Color(red: 0.15, green: 0.90, blue: 0.45) : Color.gray)
                }
            }
        }
    }
}
