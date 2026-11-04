//
//  FriendDetailView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI
import CoreLocation

/// Pure MVVM View presenting comprehensive friend telemetry:
/// latest known status, measurement age, reported accuracy, connection state,
/// and relative distance/bearing.
public struct FriendDetailView: View {
    public let member: Member
    public let userLocation: LocationPin?
    public let onStartNavigation: () -> Void
    public let onDismiss: () -> Void
    
    @State private var currentTime: Date = Date()
    
    public init(
        member: Member,
        userLocation: LocationPin? = nil,
        onStartNavigation: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.member = member
        self.userLocation = userLocation
        self.onStartNavigation = onStartNavigation
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header Member Card
                        headerCard
                        
                        // Location & Freshness Telemetry Card
                        freshnessCard
                        
                        // Radio Connection State Card
                        connectionCard
                        
                        // Relative Distance & Navigation Action
                        if member.coordinate != nil {
                            navigationCard
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .task {
                // Update freshness clock periodically while open
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    currentTime = Date()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header
    
    private var headerCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(member.isEmergency ? Color.red.opacity(0.3) : member.color.swiftUIColor.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle().stroke(member.isEmergency ? Color.red : member.color.swiftUIColor, lineWidth: 2)
                    )
                
                Text(member.initials)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(member.isEmergency ? .red : member.color.swiftUIColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    
                    if member.isEmergency {
                        Text("SOS")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 8) {
                    Text("Initials: \(member.id)")
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(member.color.swiftUIColor)
                    
                    if let battery = member.batteryLevel {
                        HStack(spacing: 3) {
                            Image(systemName: battery.batterySystemImage)
                                .font(.caption2)
                            Text(battery.formattedBatteryPercentage)
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(battery > 0.2 ? .green : .red)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Freshness & Accuracy
    
    private var freshnessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Location & Freshness", systemImage: "clock.arrow.circlepath")
                .font(.caption.bold())
                .foregroundStyle(.gray)
                .textCase(.uppercase)
            
            let isStale = member.isStale(threshold: 60)
            
            // Freshness Banner (Never show stale as live)
            HStack(spacing: 10) {
                Image(systemName: isStale ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isStale ? .orange : .green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isStale ? "STALE LOCATION FIX" : "LIVE LOCATION FIX")
                        .font(.subheadline.bold())
                        .foregroundStyle(isStale ? .orange : .green)
                    
                    Text(isStale
                         ? "Measured \(timeAgo(since: member.lastSeen)). Do not rely on for live positioning."
                         : "Measured \(timeAgo(since: member.lastSeen)). Within 60s freshness window.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((isStale ? Color.orange : Color.green).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Divider().background(Color.gray.opacity(0.3))
            
            // Reported Accuracy
            HStack {
                Text("Reported GPS Accuracy")
                    .font(.footnote)
                    .foregroundStyle(.gray)
                
                Spacer()
                
                if let acc = member.horizontalAccuracy {
                    Text(String(format: "±%.1f m (%@)", acc, accuracyDescription(acc)))
                        .font(.footnote.bold())
                        .foregroundStyle(acc <= 15 ? .green : (acc <= 40 ? .yellow : .orange))
                } else {
                    Text("Unknown / Not Reported")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                }
            }
            
            // Coordinate String
            if let coord = member.coordinate {
                HStack {
                    Text("Coordinate")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                    Spacer()
                    Text(String(format: "%.6f°, %.6f°", coord.latitude, coord.longitude))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.gray)
                }
            }
            
            // Facing Orientation / Heading
            if let heading = member.heading {
                HStack {
                    Text("Facing Orientation")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: "location.north.circle.fill")
                            .font(.caption)
                            .foregroundStyle(member.color.swiftUIColor)
                            .rotationEffect(.degrees(heading))
                        Text(String(format: "%.0f° (%@)", heading, cardinalDirection(heading)))
                            .font(.footnote.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding()
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Connection State
    
    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Radio Connection State", systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption.bold())
                .foregroundStyle(.gray)
                .textCase(.uppercase)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.isDirectPeer ? "Direct 1-Hop Radio Link (AWDL)" : "Multi-Hop Mesh Connection")
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text(member.isDirectPeer ? "Direct peer-to-peer Wi-Fi / BLE" : "Reachable via relay nodes")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                
                Spacer()
                
                if let rssi = member.rssi {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(rssi) dBm")
                            .font(.subheadline.bold().monospaced())
                            .foregroundStyle(rssiColor(rssi))
                        
                        Text(rssiDescription(rssi))
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
        .padding()
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Navigation
    
    private var navigationCard: some View {
        VStack(spacing: 12) {
            if let userLoc = userLocation, let friendCoord = member.coordinate {
                let dist = userLoc.distance(to: friendCoord)
                let bearing = userLoc.bearing(to: friendCoord)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Estimated Distance")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        Text(dist.formattedDistance())
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Relative Bearing")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        Text(String(format: "%.0f° %@", bearing, cardinalDirection(bearing)))
                            .font(.title3.bold().monospaced())
                            .foregroundStyle(.green)
                    }
                }
                .padding(.bottom, 4)
            }
            
            Button {
                onStartNavigation()
            } label: {
                Label("Track in Radar", systemImage: "scope")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Track \(member.name) in Tactical Radar")
            .accessibilityHint("Opens 360 degree tactical radar and crowd finding beacon.")
        }
        .padding()
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Helper Formatters
    
    private func timeAgo(since date: Date) -> String {
        let elapsed = max(0, currentTime.timeIntervalSince(date))
        if elapsed < 5 { return "just now" }
        return date.compactTimeAgo(from: currentTime)
    }
    
    private func accuracyDescription(_ accuracy: CLLocationAccuracy) -> String {
        if accuracy <= 10 { return "High" }
        if accuracy <= 25 { return "Good" }
        if accuracy <= 50 { return "Fair" }
        return "Degraded"
    }
    
    private func rssiDescription(_ rssi: Int8) -> String {
        if rssi >= -65 { return "Strong" }
        if rssi >= -80 { return "Medium" }
        return "Weak"
    }
    
    private func rssiColor(_ rssi: Int8) -> Color {
        if rssi >= -65 { return .green }
        if rssi >= -80 { return .yellow }
        return .orange
    }
    
    private func cardinalDirection(_ degrees: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5).truncatingRemainder(dividingBy: 360.0) / 45.0)
        return dirs[max(0, min(7, index))]
    }
}
