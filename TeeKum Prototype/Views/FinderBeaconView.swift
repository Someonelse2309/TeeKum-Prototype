//
//  FinderBeaconView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI
import CoreLocation

/// Full-screen Tactical Radar and visual crowd finder beacon.
/// Replaces the legacy compass dial with a dynamic 15m/30m/60m tactical radar
/// that displays all group members, allows targeting/highlighting a friend,
/// and retains the high-visibility neon strobe torch to wave above crowds.
public struct FinderBeaconView: View {
    public let members: [Member]
    public let userLocation: LocationPin?
    public let currentHeading: CLLocationDirection?
    public let locationService: (any LocationServiceProvider)?
    public let userColor: Color?
    public let session: GroupSession?
    public let peerTransport: (any PeerTransport)?
    public let onDismiss: () -> Void
    
    @ObservedObject private var nearbyService = NearbyInteractionService.shared
    @State private var selectedMember: Member?
    @State private var isStrobeActive: Bool = false
    @State private var strobeColorIndex: Int = 0
    @State private var strobeTask: Task<Void, Never>?
    
    private let strobeColors: [Color] = [.yellow, .cyan, .green, .white]
    
    /// Primary initializer supporting the multi-peer tactical radar and UWB precision finding.
    public init(
        members: [Member],
        initialSelectedMember: Member? = nil,
        userLocation: LocationPin? = nil,
        currentHeading: CLLocationDirection? = nil,
        locationService: (any LocationServiceProvider)? = nil,
        userColor: Color? = nil,
        session: GroupSession? = nil,
        peerTransport: (any PeerTransport)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.members = members
        self._selectedMember = State(initialValue: initialSelectedMember)
        self.userLocation = userLocation
        self.currentHeading = currentHeading
        self.locationService = locationService
        self.userColor = userColor
        self.session = session
        self.peerTransport = peerTransport
        self.onDismiss = onDismiss
    }
    
    /// Legacy convenience initializer for single-friend navigation.
    public init(
        friend: Member,
        userLocation: LocationPin? = nil,
        currentHeading: CLLocationDirection? = nil,
        locationService: (any LocationServiceProvider)? = nil,
        session: GroupSession? = nil,
        peerTransport: (any PeerTransport)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.init(
            members: [friend],
            initialSelectedMember: friend,
            userLocation: userLocation,
            currentHeading: currentHeading,
            locationService: locationService,
            session: session,
            peerTransport: peerTransport,
            onDismiss: onDismiss
        )
    }
    
    public var body: some View {
        ZStack {
            if isStrobeActive {
                strobeView
            } else {
                normalRadarView
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            locationService?.setTacticalRadarActive(true)
        }
        .onDisappear {
            locationService?.setTacticalRadarActive(false)
            Task {
                await nearbyService.stopPrecisionFinding(session: session, transport: peerTransport)
            }
        }
    }
    
    // MARK: - Normal Tactical Radar View
    
    private var normalRadarView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 12) {
                // MARK: - Top Header Bar
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(selectedMember != nil ? "NAVIGATING TO" : "FESTIVAL RADAR")
                                .font(.caption.bold().monospaced())
                                .foregroundStyle(selectedMember != nil ? .yellow : .cyan)
                            
                            if selectedMember == nil {
                                Text("(\(members.count) Friends)")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }
                        }
                        
                        Text(selectedMember?.name ?? "360° Tactical Radar")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.gray)
                    }
                    .accessibilityLabel("Close Radar")
                }
                .padding(.horizontal)
                .padding(.top, 12)
                
                // MARK: - Selected Target Status Pill / HUD
                if let target = selectedMember {
                    selectedTargetHUD(for: target)
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "scope")
                            .font(.caption)
                            .foregroundStyle(.cyan)
                        Text("Tap any blip or card below to lock onto a friend")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    .padding(.vertical, 4)
                }
                
                // MARK: - Main Radar Canvas
                if let target = selectedMember,
                   nearbyService.rangingState == .active,
                   nearbyService.activeTargetMemberId == target.id {
                    PrecisionFindingOverlay(
                        targetMember: target,
                        distanceMeters: nearbyService.currentDistance,
                        direction: nearbyService.currentDirection,
                        horizontalAngle: nearbyService.currentHorizontalAngle,
                        rangingState: nearbyService.rangingState,
                        onStop: {
                            Task {
                                await nearbyService.stopPrecisionFinding(session: session, transport: peerTransport)
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    RadarView(
                        members: members,
                        userLocation: userLocation,
                        currentHeading: currentHeading,
                        selectedMember: $selectedMember,
                        theme: .standard,
                        userColor: userColor
                    )
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // MARK: - Bottom Horizontal Friend Cards Carousel
                if !members.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(members) { member in
                                let dist = computeDistance(to: member)
                                let bearing = computeRelativeBearing(to: member)
                                
                                RadarFriendCard(
                                    member: member,
                                    distance: dist,
                                    relativeBearing: bearing,
                                    isSelected: selectedMember?.id == member.id,
                                    theme: .standard,
                                    onTap: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                            if selectedMember?.id == member.id {
                                                selectedMember = nil
                                            } else {
                                                selectedMember = member
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 56)
                }
                
                // MARK: - Visual Screen Strobe Torch Button
                VStack(spacing: 6) {
                    Button {
                        startStrobe()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "flashlight.on.fill")
                                .font(.headline)
                            Text("HOLD UP VISUAL STROBE TORCH")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.yellow)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: Color.yellow.opacity(0.35), radius: 6)
                    }
                    .accessibilityLabel("Activate visual strobe torch")
                    .accessibilityHint("Turns screen into a flashing neon beacon to wave above crowds.")
                    
                    Text("Hold screen in the air to help friends visually spot you in the crowd.")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
    }
    
    // MARK: - Selected Target HUD Banner
    
    private func selectedTargetHUD(for target: Member) -> some View {
        let dist = computeDistance(to: target)
        let relBearing = computeRelativeBearing(to: target)
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Target Initials Badge
                Text(target.initials)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .padding(8)
                    .background(Color.yellow)
                    .foregroundStyle(.black)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(target.name)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    }
                    
                    HStack(spacing: 8) {
                        if let d = dist {
                            Text(d < 8.0 ? "VERY CLOSE (<8m)" : (d >= 1000 ? String(format: "%.1f km", d / 1000.0) : String(format: "%.0f m", d)))
                                .font(.caption.bold().monospaced())
                                .foregroundStyle(d < 8.0 ? .yellow : .green)
                        } else {
                            Text("No GPS Fix")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        
                        if let bearing = relBearing {
                            Text("• \(clockDirection(for: bearing))")
                                .font(.caption.bold())
                                .foregroundStyle(.cyan)
                        }
                    }
                }
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMember = nil
                    }
                } label: {
                    Text("Clear")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.15))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            
            // Ultra-Wideband Precision Finding Action Bar
            HStack(spacing: 8) {
                if nearbyService.isSupported {
                    if nearbyService.rangingState == .active && nearbyService.activeTargetMemberId == target.id {
                        Button {
                            Task {
                                await nearbyService.stopPrecisionFinding(session: session, transport: peerTransport)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.circle.fill")
                                Text("Stop Precision Finding")
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.25))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                        }
                    } else {
                        Button {
                            guard let session = session, let transport = peerTransport else { return }
                            Task {
                                await nearbyService.startPrecisionFinding(for: target, session: session, transport: transport)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                Text(nearbyService.rangingState == .requestingToken ? "Requesting UWB..." : "Start Precision Finding")
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.25))
                            .foregroundStyle(.cyan)
                            .clipShape(Capsule())
                        }
                        .disabled(nearbyService.rangingState == .requestingToken || session == nil || peerTransport == nil)
                    }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        Text("Precision Finding requires iPhone 11+ with U1/U2 chip")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
        )
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
                
                Text((selectedMember?.name ?? "HERE").uppercased())
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                
                Text("LOOK HERE!")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.85))
                
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
    
    // MARK: - Computations
    
    private func computeDistance(to member: Member) -> CLLocationDistance? {
        guard let userCoord = userLocation?.coordinate, let friendCoord = member.coordinate else { return nil }
        let uLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        let fLoc = CLLocation(latitude: friendCoord.latitude, longitude: friendCoord.longitude)
        return uLoc.distance(from: fLoc)
    }
    
    private func computeRelativeBearing(to member: Member) -> Double? {
        guard let userLoc = userLocation, let friendCoord = member.coordinate else { return nil }
        let bearingToTarget = userLoc.bearing(to: friendCoord)
        let heading = currentHeading ?? 0.0
        let relative = bearingToTarget - heading
        return (relative + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
    
    private func clockDirection(for relativeAngle: Double) -> String {
        let normalized = (relativeAngle + 360.0).truncatingRemainder(dividingBy: 360.0)
        let hour = Int((normalized + 15.0) / 30.0) % 12
        let displayHour = hour == 0 ? 12 : hour
        if displayHour == 12 {
            return "Ahead"
        } else if displayHour == 6 {
            return "Behind"
        } else {
            return "\(displayHour) o'clock"
        }
    }
}
