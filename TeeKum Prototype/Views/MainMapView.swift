//
//  MainMapView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI
import MapKit

/// Pure MVVM View rendering the offline MapKit festival preview, Live Sharing master toggle,
/// friend annotations with honest freshness indicators, quick-tap status picker,
/// and 3-second hold emergency SOS button.
public struct MainMapView: View {
    @Bindable var mapViewModel: MapViewModel
    @Bindable var sessionViewModel: GroupSessionViewModel
    @Bindable var sosViewModel: SOSViewModel
    @Bindable var meetingPointViewModel: MeetingPointViewModel
    var relayPolicyManager: RelayPolicyManager?
    var peerTransport: PeerTransportService?
    
    public enum ScreenMode: String, CaseIterable, Sendable {
        case normal = "Normal"
        case debugging = "Debugging"
    }
    
    @State private var screenMode: ScreenMode = .normal
    @State private var isShowingDiagnostics: Bool = false
    @State private var isShowingGroupQR: Bool = false
    @State private var isShowingMeetingPoints: Bool = false
    @State private var isShowingNavigationBeacon: Bool = false
    @State private var isShowingLeaveAlert: Bool = false
    @State private var isShowingRelaySettings: Bool = false
    @State private var relayState: RelayPolicyState?
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    
    // Interactive Map-Pointing for Meeting Points
    @State private var droppedPinCoordinate: CLLocationCoordinate2D? = nil
    @State private var isShowingDroppedPinSheet: Bool = false
    @State private var droppedPinName: String = ""
    @State private var lastTouchPoint: CGPoint? = nil
    
    public init(
        mapViewModel: MapViewModel,
        sessionViewModel: GroupSessionViewModel,
        sosViewModel: SOSViewModel,
        meetingPointViewModel: MeetingPointViewModel,
        relayPolicyManager: RelayPolicyManager? = nil,
        peerTransport: PeerTransportService? = nil
    ) {
        self.mapViewModel = mapViewModel
        self.sessionViewModel = sessionViewModel
        self.sosViewModel = sosViewModel
        self.meetingPointViewModel = meetingPointViewModel
        self.relayPolicyManager = relayPolicyManager
        self.peerTransport = peerTransport
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if screenMode == .debugging {
                MeshDebuggerView(
                    viewModel: MeshDebuggerViewModel(
                        peerTransport: peerTransport,
                        groupSessionViewModel: sessionViewModel,
                        locationService: mapViewModel.locationService,
                        relayPolicyManager: relayPolicyManager
                    ),
                    onToggleToNormalMode: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            screenMode = .normal
                        }
                    }
                )
                .transition(.opacity)
            } else {
                // MapKit Offline Venue Preview
                venueMapView
                
                // Floating UI Overlay Controls
                VStack(spacing: 0) {
                    // Top Status Pill & Session Bar
                    topSessionBar
                    
                    if let alert = sosViewModel.activeIncomingAlert {
                        incomingSOSBanner(for: alert)
                    }
                    
                    Spacer()
                    
                    // Bottom Docked Controls
                    bottomControlsDock
                }
                .transition(.opacity)
            }
        }
        // Sheets
        .sheet(isPresented: $isShowingDiagnostics) {
            DiagnosticsView(
                sessionViewModel: sessionViewModel,
                mapViewModel: mapViewModel,
                sosViewModel: sosViewModel,
                relayPolicyManager: relayPolicyManager,
                peerTransport: peerTransport
            )
        }
        .sheet(isPresented: $isShowingRelaySettings) {
            if let manager = relayPolicyManager {
                RelaySettingsSheet(
                    relayPolicyManager: manager,
                    currentBatteryLevel: mapViewModel.locationService?.currentBatteryLevel ?? 1.0,
                    isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
                )
            }
        }
        .sheet(isPresented: $isShowingGroupQR) {
            groupQRSheet
        }
        .sheet(isPresented: $isShowingMeetingPoints) {
            MeetingPointsView(
                meetingPointViewModel: meetingPointViewModel,
                sessionViewModel: sessionViewModel,
                userLocation: mapViewModel.userLocation
            )
        }
        .sheet(isPresented: $isShowingDroppedPinSheet, onDismiss: {
            droppedPinCoordinate = nil
        }) {
            if let coord = droppedPinCoordinate {
                SetMeetingPointSheet(
                    coordinate: coord,
                    initialName: droppedPinName,
                    activeMeetingPoint: meetingPointViewModel.activeMeetingPoint,
                    onConfirm: { name, chosenCoord in
                        if let session = sessionViewModel.activeSession {
                            meetingPointViewModel.proposeMeetingPoint(
                                name: name,
                                coordinate: chosenCoord,
                                targetTime: Date().addingTimeInterval(1800),
                                proposerId: session.localInitials,
                                landmarkId: nil
                            )
                        }
                        isShowingDroppedPinSheet = false
                        droppedPinCoordinate = nil
                    },
                    onCancel: {
                        isShowingDroppedPinSheet = false
                        droppedPinCoordinate = nil
                    }
                )
                .presentationDetents([.fraction(0.35), .medium])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $mapViewModel.selectedMember) { member in
            FriendDetailView(
                member: member,
                userLocation: mapViewModel.userLocation,
                onStartNavigation: {
                    mapViewModel.selectedMember = nil
                    isShowingNavigationBeacon = true
                },
                onDismiss: {
                    mapViewModel.clearNavigationTarget()
                }
            )
        }
        .fullScreenCover(isPresented: $isShowingNavigationBeacon) {
            if let targetFriend = sessionViewModel.members.first {
                FinderBeaconView(
                    friend: targetFriend,
                    userLocation: mapViewModel.userLocation,
                    currentHeading: mapViewModel.currentHeading,
                    onDismiss: {
                        isShowingNavigationBeacon = false
                    }
                )
            }
        }
        .alert("Leave Group Session?", isPresented: $isShowingLeaveAlert) {
            Button("Leave Group", role: .destructive) {
                sessionViewModel.leaveGroup()
            }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("Leaving will wipe ephemeral cryptographic keys and disconnect you from this mesh network.")
        }
        .task {
            if let manager = relayPolicyManager {
                self.relayState = await manager.currentState()
                for await state in manager.stateUpdates {
                    self.relayState = state
                }
            }
        }
    }
    
    // MARK: - MapKit View
    
    private var venueMapView: some View {
        MapReader { proxy in
            Map(position: $mapCameraPosition) {
                UserAnnotation()
                
                // Friend Annotations with Honest Freshness Indicators
                ForEach(sessionViewModel.members) { member in
                    if let coord = member.coordinate {
                        Annotation("", coordinate: coord) {
                            friendPinView(for: member)
                                .onTapGesture {
                                    mapViewModel.selectMemberForNavigation(member)
                                }
                        }
                        .annotationTitles(.hidden)
                    }
                }
                
                // Active Single Meeting Point Annotation
                if let mp = meetingPointViewModel.activeMeetingPoint {
                    Annotation("", coordinate: mp.coordinate) {
                        meetingPointPinView(for: mp)
                            .onTapGesture {
                                isShowingMeetingPoints = true
                            }
                    }
                    .annotationTitles(.hidden)
                }
                
                // Temporary Dropped Pin Annotation
                if let droppedCoord = droppedPinCoordinate {
                    Annotation("", coordinate: droppedCoord) {
                        temporaryDroppedPinView
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        lastTouchPoint = value.location
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5, maximumDistance: 15)
                    .onEnded { _ in
                        guard let touch = lastTouchPoint,
                              let coord = proxy.convert(touch, from: .local) else { return }
                        handleMapLongPress(at: coord)
                    }
            )
        }
    }
    
    // MARK: - Friend Pin View
    
    private func friendPinView(for member: Member) -> some View {
        let isStale = member.isStale(threshold: 60)
        let isEmergency = member.status.code.isEmergency
        
        return VStack(spacing: 4) {
            ZStack {
                // Outer ring
                if isEmergency {
                    Circle()
                        .stroke(Color.red.opacity(0.6), lineWidth: 4)
                        .frame(width: 52, height: 52)
                }
                
                Circle()
                    .stroke(
                        isEmergency ? Color.red : (isStale ? Color.orange : Color.green),
                        lineWidth: isEmergency ? 3 : 2
                    )
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(Color.black.opacity(0.8))
                    )
                
                Text(member.status.code.emoji)
                    .font(.system(size: 22))
                
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
                        .foregroundStyle(isEmergency ? .red : .white)
                }
                
                if isEmergency {
                    Text("EMERGENCY")
                        .font(.system(size: 7).bold())
                        .foregroundStyle(.red)
                } else if isStale {
                    Text("Stale • \(relativeAge(since: member.lastSeen))")
                        .font(.system(size: 8).bold())
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.85))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isEmergency ? Color.red.opacity(0.7) : (isStale ? Color.orange.opacity(0.5) : Color.clear), lineWidth: 1)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(member.name), status \(member.status.code.title)")
        .accessibilityValue(isStale ? "Stale location measured \(relativeAge(since: member.lastSeen))" : "Live location")
        .accessibilityHint("Double tap to view friend details and navigation.")
    }
    
    // MARK: - Meeting Point Pin
    
    private func meetingPointPinView(for mp: MeetingPoint) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.yellow)
                .shadow(color: .yellow.opacity(0.5), radius: 6)
            
            Text(mp.name)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.85))
                .foregroundStyle(.yellow)
                .clipShape(Capsule())
        }
    }
    
    // MARK: - Temporary Dropped Pin (Interactive Long-Press)
    
    private var temporaryDroppedPinView: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.yellow.opacity(0.8), lineWidth: 2)
                    .frame(width: 44, height: 44)
                
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 30))
                    .foregroundStyle(.yellow)
                    .shadow(color: .yellow.opacity(0.9), radius: 8)
            }
            
            Text(droppedPinName.isEmpty ? PremadeMeetingLocation.defaultName : droppedPinName)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.85))
                .foregroundStyle(.yellow)
                .clipShape(Capsule())
        }
    }
    
    private func handleMapLongPress(at coordinate: CLLocationCoordinate2D) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        droppedPinCoordinate = coordinate
        droppedPinName = PremadeMeetingLocation.defaultName
        isShowingDroppedPinSheet = true
    }
    
    // MARK: - Top Session Bar
    
    private var topSessionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(sessionViewModel.activeSession?.sessionName ?? "Festival Group")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text("(\(sessionViewModel.members.count + 1))")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)
                }
                
                // Non-intrusive Status Pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusPillColor)
                        .frame(width: 7, height: 7)
                    
                    Text(mapViewModel.statusPillMessage)
                        .font(.caption2.bold())
                        .foregroundStyle(statusPillColor)
                }
            }
            
            Spacer()
            
            // Home Screen Mode Switcher (Normal <-> Debugging)
            HStack(spacing: 2) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        screenMode = .normal
                    }
                } label: {
                    Text("Map")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(screenMode == .normal ? Color.green : Color.clear)
                        .foregroundStyle(screenMode == .normal ? .black : .gray)
                        .clipShape(Capsule())
                }
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        screenMode = .debugging
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform.path.badge.gearshape")
                            .font(.system(size: 9).bold())
                        Text("Debug")
                            .font(.caption2.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(screenMode == .debugging ? Color.yellow : Color.clear)
                    .foregroundStyle(screenMode == .debugging ? .black : .gray)
                    .clipShape(Capsule())
                }
            }
            .padding(2)
            .background(Color.black.opacity(0.7))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
            .accessibilityLabel("Toggle Debugging and Normal Mode")
            
            // Meeting Point Button
            Button {
                isShowingMeetingPoints = true
            } label: {
                Image(systemName: meetingPointViewModel.activeMeetingPoint != nil ? "mappin.circle.fill" : "mappin.circle")
                    .font(.subheadline.bold())
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .foregroundStyle(meetingPointViewModel.activeMeetingPoint != nil ? .yellow : .white)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Meeting points")
            
            // Group QR Barcode Button
            Button {
                isShowingGroupQR = true
            } label: {
                Image(systemName: "qrcode")
                    .font(.subheadline.bold())
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Group QR Code")
            
            // Communal Relay Button (Agent 5)
            if relayPolicyManager != nil {
                Button {
                    isShowingRelaySettings = true
                } label: {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.subheadline.bold())
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .foregroundStyle(relayButtonColor)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Communal Relay Settings")
            }
            
            // Diagnostics HUD Button
            Button {
                isShowingDiagnostics = true
            } label: {
                Image(systemName: "waveform.path.ecg")
                    .font(.subheadline.bold())
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Diagnostics HUD")
            
            // Leave Group Button
            Button {
                isShowingLeaveAlert = true
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.bold())
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Leave group session")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
    
    // MARK: - Incoming SOS Alert Banner
    
    private func incomingSOSBanner(for alert: IncomingSOSAlert) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(.yellow)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("EMERGENCY SOS")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white)
                        .clipShape(Capsule())
                    
                    Text(alert.senderName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                
                Text("\(alert.emergencyType.title) • Battery \(alert.batteryLevel)%")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            
            Spacer()
            
            Button("Dismiss") {
                sosViewModel.dismissIncomingAlert()
            }
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.2))
            .clipShape(Capsule())
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 0.85, green: 0.1, blue: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .shadow(color: .red.opacity(0.5), radius: 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .contentShape(Rectangle())
        .onTapGesture {
            if alert.coordinate.latitude != 0 && alert.coordinate.longitude != 0 {
                withAnimation {
                    mapCameraPosition = .camera(MapCamera(centerCoordinate: alert.coordinate, distance: 300))
                }
            }
        }
    }
    
    // MARK: - Bottom Controls Dock
    
    private var bottomControlsDock: some View {
        VStack(spacing: 10) {
            // Live Sharing Master Toggle Card
            liveSharingMasterCard
            
            // Communal Relay Status Card (Agent 5)
            if let manager = relayPolicyManager {
                communalRelayCard(manager)
            }
            
            // 1-Handed Quick-Tap Status Picker
            StatusPickerView(selectedCode: mapViewModel.currentStatus.code) { newStatus in
                mapViewModel.updateUserStatus(UserStatus(code: newStatus))
                if newStatus == .cancelMeeting {
                    meetingPointViewModel.cancelMeetingPoint()
                } else if newStatus == .atMeetingPoint, let initials = sessionViewModel.activeSession?.localInitials {
                    meetingPointViewModel.respond(status: .atMeetingPoint, memberId: initials)
                }
            }
            
            // 3-Second Hold Emergency SOS Trigger
            SOSButtonView(sosViewModel: sosViewModel)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
    
    // MARK: - Live Sharing Master Card
    
    private var liveSharingMasterCard: some View {
        HStack(spacing: 12) {
            Image(systemName: mapViewModel.isLiveSharingEnabled ? "location.fill" : "location.slash")
                .font(.title3)
                .foregroundStyle(mapViewModel.isLiveSharingEnabled ? .green : .gray)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(mapViewModel.isLiveSharingEnabled ? "Live Sharing: ON" : "Live Sharing: PAUSED")
                    .font(.subheadline.bold())
                    .foregroundStyle(mapViewModel.isLiveSharingEnabled ? .green : .white)
                
                Text(mapViewModel.isLiveSharingEnabled
                     ? "Publishing adaptive GPS pings to group"
                     : "Broadcasting paused • Battery saved")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { mapViewModel.isLiveSharingEnabled },
                set: { _ in mapViewModel.toggleLiveSharing() }
            ))
            .labelsHidden()
            .tint(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live Sharing master toggle")
        .accessibilityValue(mapViewModel.isLiveSharingEnabled ? "On" : "Paused")
        .accessibilityHint("Toggle to start or pause location broadcasting to group members.")
    }
    
    // MARK: - Communal Relay Card (Agent 5)
    
    private func communalRelayCard(_ manager: RelayPolicyManager) -> some View {
        Button {
            isShowingRelaySettings = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title3)
                    .foregroundStyle(relayCardColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(relayCardTitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(relayCardColor)
                    
                    Text(relayCardSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                
                Spacer()
                
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.bold())
                    .foregroundStyle(.gray)
                    .padding(6)
                    .background(Color(white: 0.18))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Communal Relay Settings")
        .accessibilityValue(relayCardTitle)
        .accessibilityHint("Tap to manage stranger relaying, 30-minute timer, and battery policy.")
    }
    
    private var relayButtonColor: Color {
        guard let state = relayState else { return .gray }
        if state.isRelayPermitted {
            return Color(red: 0.1, green: 0.9, blue: 0.4) // Green
        } else if state.batteryLevel < 0.20 || state.isLowPowerModeActive {
            return .yellow
        } else {
            return .gray
        }
    }
    
    private var relayCardColor: Color {
        relayButtonColor
    }
    
    private var relayCardTitle: String {
        guard let state = relayState else { return "Relay: OFF" }
        return "Relay: \(state.statusDescription())"
    }
    
    private var relayCardSubtitle: String {
        guard let state = relayState else { return "Stranger forwarding disabled" }
        if state.isRelayPermitted {
            return "Forwarding packets for festival crowd (≤2 pkts/s)"
        } else if state.batteryLevel < 0.20 {
            return "Suspended to preserve battery (<20% cutoff)"
        } else if state.isLowPowerModeActive {
            return "Suspended due to Low Power Mode"
        } else {
            return "Stranger forwarding disabled • Battery saved"
        }
    }
    
    // MARK: - Latecomers Group QR Sheet
    
    private var groupQRSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let session = sessionViewModel.activeSession {
                    VStack(spacing: 20) {
                        QRCodeView(
                            url: session.inviteURL(),
                            title: session.sessionName,
                            subtitle: "Display this barcode to friends at the concert. Scanning exchanges cryptographic keys with zero cell reception.",
                            keyFingerprint: sessionViewModel.keyFingerprint
                        )
                        .padding()
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Group QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingGroupQR = false
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Status Pill Helpers
    
    private var statusPillColor: Color {
        if !mapViewModel.isLiveSharingEnabled {
            return .orange
        }
        if mapViewModel.isFestivalSurvivalMode {
            return .yellow
        }
        if !mapViewModel.isGPSAvailable || mapViewModel.isLocationStale {
            return .orange
        }
        return .green
    }
    
    private func relativeAge(since date: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 { return "\(Int(elapsed))s" }
        let minutes = Int(elapsed / 60)
        return "\(minutes)m"
    }
}
