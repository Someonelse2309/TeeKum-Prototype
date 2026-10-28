//
//  FinderBeaconView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI
import CoreLocation

/// Pure MVVM View providing directed 360° compass navigation toward a selected friend
/// and 1-tap high-visibility visual screen strobe torch to hold above festival crowds.
public struct FinderBeaconView: View {
    public let friend: Member
    public let userLocation: LocationPin?
    public let currentHeading: CLLocationDirection?
    public let onDismiss: () -> Void
    
    @State private var isStrobeActive: Bool = false
    @State private var strobeColorIndex: Int = 0
    @State private var strobeTask: Task<Void, Never>?
    
    private let strobeColors: [Color] = [.yellow, .cyan, .green, .white]
    
    public init(
        friend: Member,
        userLocation: LocationPin? = nil,
        currentHeading: CLLocationDirection? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.friend = friend
        self.userLocation = userLocation
        self.currentHeading = currentHeading
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        ZStack {
            if isStrobeActive {
                strobeView
            } else {
                normalCompassView
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Normal Compass Navigation View
    
    private var normalCompassView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Top Header Bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Navigating To")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        Text(friend.name)
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                    
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                
                Spacer()
                
                // 360° Rotating Compass Arrow
                let relativeAngle = computeRelativeBearing()
                let distance = computeDistance()
                
                ZStack {
                    // Outer Compass Dial Ring
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 260, height: 260)
                    
                    // Cardinal Tick Marks
                    ForEach(0..<12) { i in
                        Rectangle()
                            .fill(i % 3 == 0 ? Color.white : Color.gray.opacity(0.4))
                            .frame(width: 2, height: i % 3 == 0 ? 14 : 8)
                            .offset(y: -120)
                            .rotationEffect(.degrees(Double(i) * 30.0))
                    }
                    
                    // Directional Pointer Arrow
                    VStack(spacing: 0) {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.green)
                            .shadow(color: .green.opacity(0.6), radius: 12)
                        Spacer()
                    }
                    .frame(height: 200)
                    .rotationEffect(.degrees(relativeAngle))
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: relativeAngle)
                    
                    // Center Distance Badge
                    VStack(spacing: 4) {
                        if let dist = distance {
                            Text(dist < 8.0 ? "VERY CLOSE" : (dist >= 1000 ? String(format: "%.1f km", dist / 1000.0) : String(format: "%.0f m", dist)))
                                .font(.title3.bold().monospaced())
                                .foregroundStyle(dist < 8.0 ? .yellow : .white)
                            
                            if dist < 8.0 {
                                Text("Within UWB Range (<8m)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.yellow)
                            }
                        } else {
                            Text("No GPS Fix")
                                .font(.footnote)
                                .foregroundStyle(.gray)
                        }
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Compass pointing toward \(friend.name)")
                .accessibilityValue(distance != nil ? "\(Int(distance!)) meters away" : "Distance unknown")
                
                Spacer()
                
                // Bottom Strobe Beacon Button
                VStack(spacing: 12) {
                    Button {
                        startStrobe()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "flashlight.on.fill")
                                .font(.title3)
                            Text("HOLD UP VISUAL STROBE")
                                .font(.headline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.yellow)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .yellow.opacity(0.4), radius: 8)
                    }
                    .accessibilityLabel("Activate visual strobe beacon")
                    .accessibilityHint("Turns screen into a flashing torch to wave above crowds.")
                    
                    Text("Turn your screen into a neon strobe to help your friend spot you above the crowd.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.gray)
                        .padding(.horizontal)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }
    
    // MARK: - Screen Strobe Flasher View
    
    private var strobeView: some View {
        ZStack {
            strobeColors[strobeColorIndex]
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        stopStrobe()
                    } label: {
                        Text("Tap anywhere to exit")
                            .font(.headline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.7))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(.top, 40)
                
                Spacer()
                
                Text(friend.name.uppercased())
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(.black)
                
                Text("LOOK HERE!")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.8))
                
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            stopStrobe()
        }
    }
    
    // MARK: - Strobe Engine
    
    private func startStrobe() {
        isStrobeActive = true
        strobeTask?.cancel()
        strobeTask = Task { @MainActor in
            while isStrobeActive && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000) // 5Hz blink
                guard isStrobeActive, !Task.isCancelled else { break }
                strobeColorIndex = (strobeColorIndex + 1) % strobeColors.count
            }
        }
    }
    
    private func stopStrobe() {
        isStrobeActive = false
        strobeTask?.cancel()
        strobeTask = nil
    }
    
    // MARK: - Math Helpers
    
    private func computeDistance() -> CLLocationDistance? {
        guard let userCoord = userLocation?.coordinate, let friendCoord = friend.coordinate else { return nil }
        let uLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        let fLoc = CLLocation(latitude: friendCoord.latitude, longitude: friendCoord.longitude)
        return uLoc.distance(from: fLoc)
    }
    
    private func computeRelativeBearing() -> Double {
        guard let userLoc = userLocation, let friendCoord = friend.coordinate else { return 0.0 }
        let bearingToTarget = userLoc.bearing(to: friendCoord)
        let heading = currentHeading ?? 0.0
        let relative = bearingToTarget - heading
        return (relative + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
}
