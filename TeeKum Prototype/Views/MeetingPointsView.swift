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
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var meetingNameInput: String = ""
    @State private var selectedPreset: String? = nil
    
    private let venueLandmarks = VenueLandmark.presets.map(\.name)
    
    public init(
        meetingPointViewModel: MeetingPointViewModel,
        sessionViewModel: GroupSessionViewModel,
        userLocation: LocationPin? = nil
    ) {
        self.meetingPointViewModel = meetingPointViewModel
        self.sessionViewModel = sessionViewModel
        self.userLocation = userLocation
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Current Active Meeting Point Card
                        if let active = meetingPointViewModel.activeMeetingPoint {
                            activeMeetingCard(active)
                        } else {
                            noActiveMeetingCard
                        }
                        
                        // Proposal Section
                        proposalSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Meeting Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
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
                Label("Single Active Meeting Point", systemImage: "mappin.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.yellow)
                    .textCase(.uppercase)
                
                Spacer()
                
                Button("Cancel", role: .destructive) {
                    meetingPointViewModel.cancelMeetingPoint()
                }
                .font(.caption.bold())
                .foregroundStyle(.red)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(active.name)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                
                Text(String(format: "Location: %.5f°, %.5f°", active.coordinate.latitude, active.coordinate.longitude))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.gray)
            }
            
            Divider().background(Color.gray.opacity(0.3))
            
            // Attendance Summary
            VStack(alignment: .leading, spacing: 8) {
                Text("Group Attendance")
                    .font(.caption.bold())
                    .foregroundStyle(.gray)
                
                let attendingCount = active.attendance.values.filter { $0 == .attending || $0 == .atMeetingPoint }.count
                let totalMembers = max(1, sessionViewModel.members.count + 1)
                
                HStack {
                    Text("\(attendingCount) of \(totalMembers) attending")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                    
                    Spacer()
                }
            }
            
            // 1-Tap Response Buttons
            if let localSession = sessionViewModel.activeSession {
                HStack(spacing: 12) {
                    Button {
                        meetingPointViewModel.respond(status: .attending, memberId: localSession.localInitials)
                    } label: {
                        Label("I'll be there", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(meetingPointViewModel.localAttendanceStatus == .attending ? Color.green : Color(white: 0.2))
                            .foregroundStyle(meetingPointViewModel.localAttendanceStatus == .attending ? Color.black : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Button {
                        meetingPointViewModel.respond(status: .cantMakeIt, memberId: localSession.localInitials)
                    } label: {
                        Label("Can't make it", systemImage: "xmark.circle.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(meetingPointViewModel.localAttendanceStatus == .cantMakeIt ? Color.red.opacity(0.3) : Color(white: 0.2))
                            .foregroundStyle(meetingPointViewModel.localAttendanceStatus == .cantMakeIt ? Color.red : Color.gray)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding()
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
        )
    }
    
    private var noActiveMeetingCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.largeTitle)
                .foregroundStyle(.gray)
            
            Text("No Active Meeting Point")
                .font(.headline)
                .foregroundStyle(.white)
            
            Text("Propose a rendezvous spot below so your group knows where to meet if separated.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Proposal Section
    
    private var proposalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Propose New Rendezvous")
                .font(.headline)
                .foregroundStyle(.white)
            
            // Venue Presets
            Text("Official Venue Landmarks")
                .font(.caption.bold())
                .foregroundStyle(.gray)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(venueLandmarks, id: \.self) { landmark in
                        Button {
                            selectedPreset = landmark
                            meetingNameInput = landmark
                        } label: {
                            Text(landmark)
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedPreset == landmark ? Color.yellow.opacity(0.3) : Color(white: 0.15))
                                .foregroundStyle(selectedPreset == landmark ? .yellow : .white)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            
            // Custom Name Input
            TextField("Custom spot name (e.g. Ferris Wheel)", text: $meetingNameInput)
                .padding()
                .background(Color(white: 0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            
            // Propose Button
            Button {
                proposeCurrentMeeting()
            } label: {
                Label("Set as Group Meeting Point", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.yellow)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(meetingNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func proposeCurrentMeeting() {
        guard let session = sessionViewModel.activeSession else { return }
        let name = meetingNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        let landmark = VenueLandmark.preset(for: name)
        let landmarkId = landmark?.id
        let coord = landmark?.coordinate ?? userLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 33.6803, longitude: -116.2366)
        
        meetingPointViewModel.proposeMeetingPoint(
            name: name,
            coordinate: coord,
            targetTime: Date().addingTimeInterval(1800), // 30 min default
            proposerId: session.localInitials,
            landmarkId: landmarkId
        )
        
        dismiss()
    }
}
