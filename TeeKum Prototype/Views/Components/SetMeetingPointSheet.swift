//
//  SetMeetingPointSheet.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import SwiftUI
import CoreLocation

/// Compact bottom sheet presented when a user long-presses anywhere on the festival map
/// to enter a landmark name and broadcast a new group rendezvous point over the mesh.
public struct SetMeetingPointSheet: View {
    public let coordinate: CLLocationCoordinate2D
    public let activeMeetingPoint: MeetingPoint?
    public let onConfirm: (String, CLLocationCoordinate2D) -> Void
    public let onCancel: () -> Void
    
    @State private var nameInput: String
    
    public init(
        coordinate: CLLocationCoordinate2D,
        initialName: String = "",
        activeMeetingPoint: MeetingPoint?,
        onConfirm: @escaping (String, CLLocationCoordinate2D) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.coordinate = coordinate
        self.activeMeetingPoint = activeMeetingPoint
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _nameInput = State(initialValue: initialName)
    }
    
    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
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
                
                // Landmark Name Input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Landmark Name")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)
                        .textCase(.uppercase)
                    
                    TextField("Enter landmark name (e.g. Sound Booth, Ferris Wheel)", text: $nameInput)
                        .font(.subheadline)
                        .padding(12)
                        .background(Color(white: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                // Primary Broadcast Button
                Button {
                    let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalName = trimmed.isEmpty ? String(format: "Meeting Point (%.4f, %.4f)", coordinate.latitude, coordinate.longitude) : trimmed
                    onConfirm(finalName, coordinate)
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
