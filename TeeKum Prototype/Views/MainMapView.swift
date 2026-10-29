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
    
    @State private var isShowingDiagnostics: Bool = false
    @State private var isShowingGroupQR: Bool = false
    @State private var isShowingMeetingPoints: Bool = false
    @State private var isShowingNavigationBeacon: Bool = false
    @State private var isShowingLeaveAlert: Bool = false
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    
    public init(
        mapViewModel: MapViewModel,
        sessionViewModel: GroupSessionViewModel,
        sosViewModel: SOSViewModel,
        meetingPointViewModel: MeetingPointViewModel
    ) {
        self.mapViewModel = mapViewModel
        self.sessionViewModel = sessionViewModel
        self.sosViewModel = sosViewModel
        self.meetingPointViewModel = meetingPointViewModel
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
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
        }
        // Sheets
        .sheet(isPresented: $isShowingDiagnostics) {
            DiagnosticsView(sessionViewModel: sessionViewModel, mapViewModel: mapViewModel)
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
    }
    
    // MARK: - MapKit View
    
    private var venueMapView: some View {
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
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .ignoresSafeArea()
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
