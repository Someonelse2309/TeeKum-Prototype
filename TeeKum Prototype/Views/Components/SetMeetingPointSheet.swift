//
//  SetMeetingPointSheet.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import SwiftUI
import CoreLocation

/// Compact bottom sheet presented when a user long-presses anywhere on the festival map
/// to choose a premade location name from a dropdown menu and broadcast a new group rendezvous point over the mesh.
public struct SetMeetingPointSheet: View {
    public let coordinate: CLLocationCoordinate2D
    public let activeMeetingPoint: MeetingPoint?
    public let onConfirm: (String, CLLocationCoordinate2D) -> Void
    public let onCancel: () -> Void
    
    @State private var selectedLocation: String
    
    public init(
        coordinate: CLLocationCoordinate2D,
        initialName: String = PremadeMeetingLocation.defaultName,
        activeMeetingPoint: MeetingPoint?,
        onConfirm: @escaping (String, CLLocationCoordinate2D) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.coordinate = coordinate
        self.activeMeetingPoint = activeMeetingPoint
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        let initial = initialName.isEmpty ? PremadeMeetingLocation.defaultName : initialName
        _selectedLocation = State(initialValue: initial)
    }
    
    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Inline notice if replacing an existing active meeting point
                if let active = activeMeetingPoint {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2.bold())
                            .foregroundStyle(.yellow)
                        Text("Replaces active spot: \(active.name)")
                            .font(.caption.bold())
                            .foregroundStyle(.yellow)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.15))
                    .clipShape(Capsule())
                }
                
                // Exact GPS coordinate subtitle
                Text(String(format: "Location: %.5f°, %.5f°", coordinate.latitude, coordinate.longitude))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.gray)
                
                // Premade Location Dropdown Menu (No custom name textfield)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meetup Location")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)
                        .textCase(.uppercase)
                    
                    Menu {
                        ForEach(PremadeMeetingLocation.allLocations, id: \.self) { location in
                            Button {
                                selectedLocation = location
                            } label: {
                                HStack {
                                    Text(location)
                                    if selectedLocation == location {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.yellow)
                            
                            Text(selectedLocation)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(.gray)
                        }
                        .padding(14)
                        .background(Color(white: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                
                Spacer()
                
                // Primary Broadcast Button
                Button {
                    onConfirm(selectedLocation, coordinate)
                } label: {
                    Label("Broadcast Meeting Point", systemImage: "mappin.and.ellipse")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.yellow)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(20)
            .background(Color(white: 0.12).ignoresSafeArea())
            .navigationTitle("Set Meeting Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(.gray)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
