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
    @Bindable var chatViewModel: ChatViewModel
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
    @State private var isShowingColorPicker: Bool = false
    @State private var radarInitialMember: Member? = nil
    @State private var relayState: RelayPolicyState?
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var hasInitialZoomedToUser: Bool = false
    @State private var isSatelliteView: Bool = false
    
    // Interactive Map-Pointing for Meeting Points
    @State private var droppedPinCoordinate: CLLocationCoordinate2D? = nil
    @State private var isShowingDroppedPinSheet: Bool = false
    @State private var lastTouchPoint: CGPoint? = nil
    
    @MainActor
    public init(
        mapViewModel: MapViewModel,
        sessionViewModel: GroupSessionViewModel,
        sosViewModel: SOSViewModel,
        meetingPointViewModel: MeetingPointViewModel,
        chatViewModel: ChatViewModel,
        relayPolicyManager: RelayPolicyManager? = nil,
        peerTransport: PeerTransportService? = nil
    ) {
        self.mapViewModel = mapViewModel
        self.sessionViewModel = sessionViewModel
        self.sosViewModel = sosViewModel
        self.meetingPointViewModel = meetingPointViewModel
        self.chatViewModel = chatViewModel
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
                    
                    if let toast = NotificationService.shared.activeToast {
                        InAppToastView(toast: toast) {
                            NotificationService.shared.dismissToast()
                        }
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    if let alert = sosViewModel.activeIncomingAlert {
                        incomingSOSBanner(for: alert)
                    }
                    
                    // Right Floating Map Tools Palette
                    HStack {
                        Spacer()
                        floatingMapTools
                    }
                    
                    Spacer()
                    
                    // Bottom Docked Controls
                    bottomControlsDock
                }
                .animation(.easeInOut(duration: 0.25), value: NotificationService.shared.activeToast)
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
        .sheet(isPresented: $chatViewModel.isChatSheetPresented) {
            ChatSheetView(viewModel: chatViewModel)
        }
        .sheet(isPresented: $isShowingMeetingPoints) {
            MeetingPointsView(
                meetingPointViewModel: meetingPointViewModel,
                sessionViewModel: sessionViewModel,
                userLocation: mapViewModel.userLocation,
                onPickOnMap: {
                    NotificationService.shared.showInAppToast(
                        InAppToast(
                            title: "Choose on Map",
                            message: "Long-press anywhere on the festival map to drop a rendezvous pin.",
                            systemImage: "hand.tap.fill",
                            accentColor: Color(red: 0.0, green: 0.85, blue: 1.0)
                        )
                    )
                }
            )
        }
        .sheet(isPresented: $isShowingDroppedPinSheet, onDismiss: {
            droppedPinCoordinate = nil
        }) {
            if let coord = droppedPinCoordinate {
                let isLocked = meetingPointViewModel.isLockedByOtherSetter
                let setter = meetingPointViewModel.currentSetterId ?? ""
                SetMeetingPointSheet(
                    coordinate: coord,
                    activeMeetingPoint: meetingPointViewModel.activeMeetingPoint,
                    isLocked: isLocked,
                    lockReason: isLocked ? "Locked by \(setter). Only \(setter) can change it." : nil,
                    onConfirm: { meetupTime, isRightNow, chosenCoord in
                        if let session = sessionViewModel.activeSession {
                            meetingPointViewModel.proposeMeetingPoint(
                                coordinate: chosenCoord,
                                meetupTime: meetupTime,
                                isRightNow: isRightNow,
                                anchorToProposerGPS: false,
                                proposerId: session.localInitials,
                                arrivalRadiusMeters: 25.0
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
                .presentationDetents([.fraction(0.48), .medium])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $mapViewModel.selectedMember) { member in
            FriendDetailView(
                member: member,
                userLocation: mapViewModel.userLocation,
                onStartNavigation: {
                    radarInitialMember = member
                    mapViewModel.selectedMember = nil
                    isShowingNavigationBeacon = true
                },
                onDismiss: {
                    mapViewModel.clearNavigationTarget()
                }
            )
        }
        .sheet(isPresented: $isShowingColorPicker) {
            ColorPickerSheet(
                selectedColor: Binding(
                    get: { sessionViewModel.localColor },
                    set: { sessionViewModel.setLocalColor($0) }
                ),
                userInitials: sessionViewModel.localUserName,
                onSave: { newColor in
                    sessionViewModel.setLocalColor(newColor)
                }
            )
        }
        .fullScreenCover(isPresented: $isShowingNavigationBeacon) {
            FinderBeaconView(
                members: sessionViewModel.members,
                initialSelectedMember: radarInitialMember,
                userLocation: mapViewModel.userLocation,
                currentHeading: mapViewModel.currentHeading,
                locationService: mapViewModel.locationService,
                userColor: sessionViewModel.localColor.swiftUIColor,
                session: sessionViewModel.activeSession,
                peerTransport: peerTransport,
                onDismiss: {
                    radarInitialMember = nil
                    isShowingNavigationBeacon = false
                }
            )
            .onAppear {
                mapViewModel.setTacticalRadarActive(true)
            }
            .onDisappear {
                mapViewModel.setTacticalRadarActive(false)
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
        .onAppear {
            if !hasInitialZoomedToUser, let userLoc = mapViewModel.userLocation {
                mapCameraPosition = .camera(MapCamera(centerCoordinate: userLoc.coordinate, distance: 400))
                hasInitialZoomedToUser = true
            }
        }
        .onChange(of: mapViewModel.userLocation) { _, newLoc in
            if !hasInitialZoomedToUser, let userLoc = newLoc {
                mapCameraPosition = .camera(MapCamera(centerCoordinate: userLoc.coordinate, distance: 400))
                hasInitialZoomedToUser = true
            }
            if let userLoc = newLoc {
                meetingPointViewModel.checkArrival(userLocation: userLoc.coordinate)
            }
        }
    }
    
    // MARK: - MapKit View
    
    private var venueMapView: some View {
        MapReader { proxy in
            Map(position: $mapCameraPosition) {
                UserAnnotation {
                    ZStack {
                        if let heading = mapViewModel.currentHeading {
                            DirectionalHeadingIndicator(
                                heading: heading,
                                color: sessionViewModel.localColor.swiftUIColor,
                                avatarRadius: 16,
                                coneRadius: 36,
                                fovAngle: 50
                            )
                        }
                        
                        Circle()
                            .fill(sessionViewModel.localColor.swiftUIColor.opacity(0.25))
                            .frame(width: 32, height: 32)
                        Circle()
                            .stroke(sessionViewModel.localColor.swiftUIColor, lineWidth: 2.5)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.black.opacity(0.85)))
                        Text(sessionViewModel.localUserName.isEmpty ? "ME" : sessionViewModel.localUserName)
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(sessionViewModel.localColor.swiftUIColor)
                    }
                    .shadow(color: sessionViewModel.localColor.swiftUIColor.opacity(0.5), radius: 6)
                }
                
                // Friend Annotations with Honest Freshness Indicators
                ForEach(sessionViewModel.members) { member in
                    if let coord = member.coordinate {
                        Annotation("", coordinate: coord) {
                            FriendPinAnnotationView(member: member)
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
                        MeetingPointPinView(meetingPoint: mp)
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
            .mapStyle(isSatelliteView ? .hybrid(elevation: .flat, pointsOfInterest: .excludingAll) : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
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
            
            Text("Rendezvous Spot")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.85))
                .foregroundStyle(.yellow)
                .clipShape(Capsule())
        }
    }
    
    private func handleMapLongPress(at coordinate: CLLocationCoordinate2D) {
        if let active = meetingPointViewModel.activeMeetingPoint,
           !active.isExpired,
           let localInitials = sessionViewModel.activeSession?.localInitials,
           active.proposerId != localInitials {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            NotificationService.shared.showInAppToast(
                InAppToast(
                    title: "Rendezvous Locked",
                    message: "Only \(active.proposerId) can unset or change the active rendezvous.",
                    systemImage: "lock.fill",
                    accentColor: Color.yellow
                )
            )
            return
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        droppedPinCoordinate = coordinate
        isShowingDroppedPinSheet = true
    }
    
    // MARK: - Top Session Bar
    
    private var topSessionBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(sessionViewModel.activeSession?.sessionName ?? "Festival Group")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
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
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right Side Controls: Mode Switcher + Leave Button
            HStack(spacing: 8) {
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
                            .padding(.vertical, 6)
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
                        .padding(.vertical, 6)
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
                
                // Leave Group Button
                Button {
                    isShowingLeaveAlert = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.bold())
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Leave group session")
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
    
    // MARK: - Right Floating Map Tools Palette
    
    private var floatingMapTools: some View {
        VStack(spacing: 8) {
            // Festival Group Chat Button
            Button {
                chatViewModel.isChatSheetPresented = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.subheadline.bold())
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.75))
                        .foregroundStyle(chatViewModel.unreadCount > 0 ? Color(red: 0.0, green: 0.85, blue: 1.0) : .white)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    chatViewModel.unreadCount > 0
                                        ? Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.8)
                                        : Color.white.opacity(0.2),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(
                            color: chatViewModel.unreadCount > 0
                                ? Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.5)
                                : .clear,
                            radius: 6
                        )
                    
                    if chatViewModel.unreadCount > 0 {
                        Text("\(min(99, chatViewModel.unreadCount))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(red: 1.0, green: 0.18, blue: 0.45))
                            .clipShape(Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .accessibilityLabel("Open Festival Group Chat\(chatViewModel.unreadCount > 0 ? ", \(chatViewModel.unreadCount) unread messages" : "")")
            
            // Festival Tactical Radar Button (Glowing Cyan)
            Button {
                radarInitialMember = nil
                isShowingNavigationBeacon = true
            } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.subheadline.bold())
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.75))
                    .foregroundStyle(.cyan)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.cyan.opacity(0.5), lineWidth: 1.5))
                    .shadow(color: .cyan.opacity(0.4), radius: 6)
            }
            .accessibilityLabel("Open Festival Tactical Radar")
            
            // Recenter on User Location Button
            Button {
                if let userLoc = mapViewModel.userLocation {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        mapCameraPosition = .camera(MapCamera(centerCoordinate: userLoc.coordinate, distance: 400))
                    }
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.subheadline.bold())
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.75))
                    .foregroundStyle(mapViewModel.userLocation != nil ? sessionViewModel.localColor.swiftUIColor : .gray)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .accessibilityLabel("Recenter on my location")
            
            // Satellite / Hybrid View Toggle Button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSatelliteView.toggle()
                }
            } label: {
                Image(systemName: isSatelliteView ? "globe.americas.fill" : "map.fill")
                    .font(.subheadline.bold())
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.75))
                    .foregroundStyle(isSatelliteView ? .cyan : .white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(isSatelliteView ? Color.cyan.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1))
            }
            .accessibilityLabel(isSatelliteView ? "Switch to standard map" : "Switch to satellite map")
            
            // Personal Color Selector Button
            Button {
                isShowingColorPicker = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.75))
                        .frame(width: 40, height: 40)
                    Circle()
                        .fill(sessionViewModel.localColor.swiftUIColor)
                        .frame(width: 22, height: 22)
                        .shadow(color: sessionViewModel.localColor.swiftUIColor.opacity(0.6), radius: 4)
                    Circle()
                        .stroke(sessionViewModel.localColor.swiftUIColor.opacity(0.7), lineWidth: 1.5)
                        .frame(width: 40, height: 40)
                }
            }
            .accessibilityLabel("Change personal color")
            
            // Meeting Point Button
            Button {
                isShowingMeetingPoints = true
            } label: {
                Image(systemName: meetingPointViewModel.activeMeetingPoint != nil ? "mappin.circle.fill" : "mappin.circle")
                    .font(.subheadline.bold())
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.75))
                    .foregroundStyle(meetingPointViewModel.activeMeetingPoint != nil ? .yellow : .white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .accessibilityLabel("Meeting points")
            
            // Group QR Barcode Button
            Button {
                isShowingGroupQR = true
            } label: {
                Image(systemName: "qrcode")
                    .font(.subheadline.bold())
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.75))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .accessibilityLabel("Group QR Code")
            
            // Communal Relay Button (Agent 5)
            if relayPolicyManager != nil {
                Button {
                    isShowingRelaySettings = true
                } label: {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.subheadline.bold())
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.75))
                        .foregroundStyle(relayButtonColor)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .accessibilityLabel("Communal Relay Settings")
            }
            
            // Diagnostics HUD Button
            Button {
                isShowingDiagnostics = true
            } label: {
                Image(systemName: "waveform.path.ecg")
                    .font(.subheadline.bold())
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.75))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .accessibilityLabel("Diagnostics HUD")
        }
        .padding(.trailing, 12)
        .padding(.top, 8)
    }
    
    // MARK: - Incoming SOS Alert Banner
    
    private func incomingSOSBanner(for alert: IncomingSOSAlert) -> some View {
        IncomingSOSAlertBannerView(
            alert: alert,
            onDismiss: {
                sosViewModel.dismissIncomingAlert()
            },
            onTap: {
                if alert.coordinate.latitude != 0 && alert.coordinate.longitude != 0 {
                    withAnimation {
                        mapCameraPosition = .camera(MapCamera(centerCoordinate: alert.coordinate, distance: 300))
                    }
                }
            }
        )
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
                    .foregroundStyle(relayButtonColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(relayCardTitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(relayButtonColor)
                    
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
}
