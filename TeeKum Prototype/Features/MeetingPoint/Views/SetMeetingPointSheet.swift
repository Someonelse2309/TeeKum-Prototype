//
//  SetMeetingPointSheet.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import SwiftUI
import CoreLocation

/// Compact bottom sheet presented when a user long-presses anywhere on the festival map
/// to set a rendezvous time and broadcast the new group rendezvous point over the mesh.
public struct SetMeetingPointSheet: View {
    public let coordinate: CLLocationCoordinate2D
    public let activeMeetingPoint: MeetingPoint?
    public let isLocked: Bool
    public let lockReason: String?
    public let onConfirm: (_ meetupTime: Date, _ isRightNow: Bool, _ coordinate: CLLocationCoordinate2D) -> Void
    public let onCancel: () -> Void
    
    @State private var selectedPreset: MeetingTimePreset = .rightNow
    @State private var customDate: Date = Date().addingTimeInterval(900)
    @State private var isCustomTime: Bool = false
    
    public init(
        coordinate: CLLocationCoordinate2D,
        activeMeetingPoint: MeetingPoint?,
        isLocked: Bool = false,
        lockReason: String? = nil,
        onConfirm: @escaping (_ meetupTime: Date, _ isRightNow: Bool, _ coordinate: CLLocationCoordinate2D) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.coordinate = coordinate
        self.activeMeetingPoint = activeMeetingPoint
        self.isLocked = isLocked
        self.lockReason = lockReason
        self.onConfirm = onConfirm
        self.onCancel = onCancel
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
            VStack(alignment: .leading, spacing: 18) {
                // Header with Coordinates & Active Replacement Warning
                VStack(alignment: .leading, spacing: 6) {
                    if isLocked {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(.yellow)
                            Text(lockReason ?? "Rendezvous is locked by the setter.")
                                .font(.caption.bold())
                                .foregroundStyle(.yellow)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.15))
                        .clipShape(Capsule())
                    } else if let active = activeMeetingPoint {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption2.bold())
                                .foregroundStyle(.yellow)
                            Text("Updates active rendezvous: \(active.formattedTitle)")
                                .font(.caption.bold())
                                .foregroundStyle(.yellow)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
                        Text(String(format: "Pinned Spot: %.5f°, %.5f°", coordinate.latitude, coordinate.longitude))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                
                // Section: When to Meet
                VStack(alignment: .leading, spacing: 10) {
                    Text("WHEN TO MEET")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray)
                        .tracking(0.5)
                    
                    // Quick Preset Chips
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
                                        : Color.white.opacity(0.10)
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
                    
                    // Custom Time Picker Toggle & Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isCustomTime.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isCustomTime ? "checkmark.circle.fill" : "clock")
                                    .font(.system(size: 13, weight: .bold))
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
                            .background(Color.white.opacity(0.06))
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
                }
                
                // Summary Preview Card
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "figure.walk.motion")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RENDEZVOUS TARGET")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
                        Text(isRightNowSelection ? "Meet Right Now" : "Meet at \(computedMeetupDate.formattedMeetupTime)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                }
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Spacer()
                
                // Primary Broadcast Action
                Button {
                    guard !isLocked else { return }
                    onConfirm(computedMeetupDate, isRightNowSelection, coordinate)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isLocked ? "lock.fill" : (activeMeetingPoint != nil ? "arrow.triangle.2.circlepath" : "mappin.and.ellipse"))
                        Text(isLocked ? "Rendezvous Locked" : (activeMeetingPoint != nil ? "Broadcast Updated Rendezvous" : "Broadcast Rendezvous"))
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isLocked ? Color.gray.opacity(0.3) : Color.yellow)
                    .foregroundStyle(isLocked ? Color.gray : Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: isLocked ? Color.clear : Color.yellow.opacity(0.3), radius: 6)
                }
                .disabled(isLocked)
            }
            .padding(20)
            .background(Color(red: 0.08, green: 0.08, blue: 0.10).ignoresSafeArea())
            .navigationTitle("Set Rendezvous")
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
