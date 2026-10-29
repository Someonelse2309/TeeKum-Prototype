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
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Leading
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(context.state.isSOSActive ? .red : Color(red: 0.1, green: 0.9, blue: 0.4))
                        Text(context.attributes.sessionName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 4)
                }
                
                // Expanded Trailing
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(context.state.directPeerCount > 0 ? Color(red: 0.1, green: 0.9, blue: 0.4) : Color.gray)
                            .frame(width: 6, height: 6)
                        Text("\(context.state.directPeerCount)P")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.trailing, 4)
                }
                
                // Expanded Center / Bottom
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isSOSActive {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("SOS: \(context.state.sosSenderInitials ?? "PEER")")
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                            Spacer()
                            Link(destination: URL(string: "teekum://sos")!) {
                                Text("FIND")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 6)
                    } else if let meetingName = context.state.meetingPointName {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("MEETING POINT")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.gray)
                                Text(meetingName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let meters = context.state.meetingPointDistanceMeters {
                                Text("\(Int(meters))m")
                                    .font(.system(size: 14, weight: .black, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
                            }
                            Link(destination: URL(string: "teekum://meeting")!) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.black)
                                    .padding(6)
                                    .background(Color(red: 0.0, green: 0.85, blue: 1.0))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 6)
                    } else {
                        Text("Connected to Festival Mesh")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.gray)
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
                            .foregroundStyle(context.state.directPeerCount > 0 ? Color(red: 0.1, green: 0.9, blue: 0.4) : Color.gray)
                    }
                    Text("\(context.state.directPeerCount)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            } compactTrailing: {
                // Compact Trailing
                if context.state.isSOSActive {
                    Text("SOS")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(.red)
                } else if let meters = context.state.meetingPointDistanceMeters {
                    Text("\(Int(meters))m")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
                } else {
                    Text(context.attributes.userInitials)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            } minimal: {
                // Minimal
                if context.state.isSOSActive {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(context.state.directPeerCount > 0 ? Color(red: 0.1, green: 0.9, blue: 0.4) : Color.gray)
                }
            }
        }
    }
}
