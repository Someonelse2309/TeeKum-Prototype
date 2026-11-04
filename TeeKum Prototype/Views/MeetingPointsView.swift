//
//  MeetingPointsView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI
import CoreLocation

/// Pure MVVM View governing the Single Active Meeting Point proposals
/// and 1-tap attendance synchronization.
public struct MeetingPointsView: View {
    @Bindable var meetingPointViewModel: MeetingPointViewModel
    @Bindable var sessionViewModel: GroupSessionViewModel
    public let userLocation: LocationPin?
    public var onPickOnMap: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPreset: MeetingTimePreset = .rightNow
    @State private var customDate: Date = Date().addingTimeInterval(900)
    @State private var isCustomTime: Bool = false
    @State private var locationMode: LocationMode = .currentLocation
    
    public enum LocationMode: String, CaseIterable, Identifiable {
        case currentLocation = "My Location"
        case pickOnMap = "Pick on Map"
        
        public var id: String { rawValue }
    }
    
    public init(
        meetingPointViewModel: MeetingPointViewModel,
        sessionViewModel: GroupSessionViewModel,
        userLocation: LocationPin? = nil,
        onPickOnMap: (() -> Void)? = nil
    ) {
        self.meetingPointViewModel = meetingPointViewModel
        self.sessionViewModel = sessionViewModel
        self.userLocation = userLocation
        self.onPickOnMap = onPickOnMap
    }
    
    private var computedMeetupDate: Date {
        if isCustomTime {
            return customDate
        } else {
            return selectedPreset.targetDate()
        }
    }
    
    private var isRightNowSelection: Bool {
        !isCustomTime && selectedPreset == .rightNow
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.10).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Current Active Meeting Point Card
                        if let active = meetingPointViewModel.activeMeetingPoint {
                            activeMeetingCard(active)
                        } else {
                            noActiveMeetingNotice
                        }
                        
                        // Proposal Section
                        proposalSection
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Rendezvous")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Active Meeting Card
    
    private func activeMeetingCard(_ active: MeetingPoint) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("ACTIVE RENDEZVOUS", systemImage: "mappin.circle.fill")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
                    .tracking(0.6)
                
                Spacer()
                
                let localInitials = sessionViewModel.activeSession?.localInitials ?? ""
                if active.proposerId == localInitials {
                    Button("Cancel", role: .destructive) {
                        meetingPointViewModel.cancelMeetingPoint(callerId: localInitials)
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.15))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                        Text("Set by \(active.proposerId)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.yellow.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(active.title)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
                    Text(active.timeDescription)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
                    
                    if let userLoc = userLocation {
                        Text("•")
                            .foregroundStyle(.gray)
                        let dist = userLoc.distance(to: active.coordinate)
                        Text(dist.formattedDistance(spaced: false, includeSuffix: true))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                
                Text(String(format: "GPS: %.5f°, %.5f°", active.coordinate.latitude, active.coordinate.longitude))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.gray)
            }
            
            Divider().background(Color.white.opacity(0.15))
            
            // Attendance Summary
            VStack(alignment: .leading, spacing: 8) {
                let attendingCount = active.attendance.values.filter { $0 == .attending || $0 == .atMeetingPoint }.count
                let arrivedCount = active.attendance.values.filter { $0 == .atMeetingPoint }.count
                let totalMembers = max(1, sessionViewModel.members.count + 1)
                
                HStack {
                    Text("Attendance: \(attendingCount) of \(totalMembers) Confirmed")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    if arrivedCount > 0 {
                        Text("\(arrivedCount) Arrived")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.15, green: 0.90, blue: 0.45))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(Color(red: 0.15, green: 0.90, blue: 0.45).opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                
                // Attendance Member Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(active.attendance.keys.sorted()), id: \.self) { initials in
                            let status = active.attendance[initials] ?? .attending
                            HStack(spacing: 4) {
                                Text(initials)
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                if status == .atMeetingPoint {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(red: 0.15, green: 0.90, blue: 0.45))
                                } else if status == .attending {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
                                } else {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            
            // 1-Tap Response Buttons
            if let localSession = sessionViewModel.activeSession {
                HStack(spacing: 8) {
                    Button {
                        meetingPointViewModel.respond(status: .attending, memberId: localSession.localInitials)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("I'll be there")
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(meetingPointViewModel.localAttendanceStatus == .attending ? Color(red: 0.0, green: 0.85, blue: 1.0) : Color.white.opacity(0.10))
                        .foregroundStyle(meetingPointViewModel.localAttendanceStatus == .attending ? Color.black : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        meetingPointViewModel.respond(status: .atMeetingPoint, memberId: localSession.localInitials)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                            Text("Arrived")
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(meetingPointViewModel.localAttendanceStatus == .atMeetingPoint ? Color(red: 0.15, green: 0.90, blue: 0.45) : Color.white.opacity(0.10))
                        .foregroundStyle(meetingPointViewModel.localAttendanceStatus == .atMeetingPoint ? Color.black : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        meetingPointViewModel.respond(status: .cantMakeIt, memberId: localSession.localInitials)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Can't")
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(meetingPointViewModel.localAttendanceStatus == .cantMakeIt ? Color.red.opacity(0.3) : Color.white.opacity(0.10))
                        .foregroundStyle(meetingPointViewModel.localAttendanceStatus == .cantMakeIt ? Color.red : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.35), lineWidth: 1.5)
        )
    }
    
    private var noActiveMeetingNotice: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 32))
                .foregroundStyle(.gray)
            
            Text("No Active Rendezvous")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text("Rally your festival squad right now or schedule a meetup time below.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Proposal Section
    
    private var proposalSection: some View {
        Group {
            let localInitials = sessionViewModel.activeSession?.localInitials ?? ""
            if let active = meetingPointViewModel.activeMeetingPoint,
               !active.isExpired,
               active.proposerId != localInitials {
                rendezvousLockedNotice(setterId: active.proposerId)
            } else {
                activeProposalForm(isUpdate: meetingPointViewModel.activeMeetingPoint != nil && !meetingPointViewModel.activeMeetingPoint!.isExpired)
            }
        }
    }
    
    private func rendezvousLockedNotice(setterId: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.yellow)
            }
            
            Text("Rendezvous Locked")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text("Set by \(setterId). Another member cannot set the meeting point until \(setterId) unsets this rendezvous.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.gray)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func activeProposalForm(isUpdate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isUpdate ? "UPDATE RENDEZVOUS" : "PROPOSE RENDEZVOUS")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.gray)
                .tracking(0.6)
            
            // Location Trigger Mode (My Location vs Pick on Map)
            VStack(alignment: .leading, spacing: 8) {
                Text("WHERE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)
                
                HStack(spacing: 10) {
                    Button {
                        locationMode = .currentLocation
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                            Text("My GPS Location")
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(locationMode == .currentLocation ? Color(red: 0.0, green: 0.85, blue: 1.0) : Color.white.opacity(0.08))
                        .foregroundStyle(locationMode == .currentLocation ? Color.black : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        locationMode = .pickOnMap
                        dismiss()
                        onPickOnMap?()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "map.fill")
                            Text("Pick on Map")
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(locationMode == .pickOnMap ? Color(red: 0.0, green: 0.85, blue: 1.0) : Color.white.opacity(0.08))
                        .foregroundStyle(locationMode == .pickOnMap ? Color.black : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Time Preset Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("WHEN")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)
                
                HStack(spacing: 8) {
                    ForEach(MeetingTimePreset.allCases) { preset in
                        Button {
                            selectedPreset = preset
                            isCustomTime = false
                        } label: {
                            Text(preset.title)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    (!isCustomTime && selectedPreset == preset)
                                    ? Color.yellow
                                    : Color.white.opacity(0.08)
                                )
                                .foregroundStyle(
                                    (!isCustomTime && selectedPreset == preset)
                                    ? Color.black
                                    : Color.white
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Custom time toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCustomTime.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCustomTime ? "checkmark.circle.fill" : "clock")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isCustomTime ? .yellow : .gray)
                        Text(isCustomTime ? "Using Custom Clock Time" : "Pick specific time tonight...")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(isCustomTime ? .white : .gray)
                        Spacer()
                        Image(systemName: isCustomTime ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.gray)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                
                if isCustomTime {
                    DatePicker(
                        "Meetup Time",
                        selection: $customDate,
                        in: Date()...,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .padding(.horizontal, 4)
                }
            }
            
            // Primary Propose Button
            Button {
                proposeCurrentMeeting()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isUpdate ? "arrow.triangle.2.circlepath" : "mappin.and.ellipse")
                    Text(isUpdate ? "Broadcast Updated Rendezvous" : "Broadcast Rendezvous")
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.yellow)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.yellow.opacity(0.3), radius: 6)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func proposeCurrentMeeting() {
        guard let session = sessionViewModel.activeSession else { return }
        let coord = userLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 33.6803, longitude: -116.2366)
        
        meetingPointViewModel.proposeMeetingPoint(
            coordinate: coord,
            meetupTime: computedMeetupDate,
            isRightNow: isRightNowSelection,
            anchorToProposerGPS: locationMode == .currentLocation,
            proposerId: session.localInitials,
            arrivalRadiusMeters: 25.0
        )
        
        dismiss()
    }
}
