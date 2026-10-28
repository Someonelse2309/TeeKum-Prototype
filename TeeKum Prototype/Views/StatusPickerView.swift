//
//  StatusPickerView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI

/// Pure MVVM View providing a 1-handed horizontal quick-tap status carousel
/// using the documented compact festival status code enum.
public struct StatusPickerView: View {
    public let selectedCode: StatusCode
    public let onStatusSelected: (StatusCode) -> Void
    
    /// Statuses available for ordinary quick-tap updates (excluding SOS which requires a 3s hold).
    private let availableStatuses: [StatusCode] = [
        .available,
        .omw,
        .lost,
        .exploring,
        .wait,
        .comeToMe,
        .gettingDrinks,
        .restroom,
        .foodMerch,
        .atMeetingPoint,
        .medical,
        .cancelMeeting
    ]
    
    public init(
        selectedCode: StatusCode = .available,
        onStatusSelected: @escaping (StatusCode) -> Void
    ) {
        self.selectedCode = selectedCode
        self.onStatusSelected = onStatusSelected
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Current Status", systemImage: "sparkles")
                    .font(.caption2.bold())
                    .foregroundStyle(.gray)
                    .textCase(.uppercase)
                
                Spacer()
                
                Text("Tap to update group")
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.8))
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableStatuses, id: \.self) { status in
                        let isSelected = status == selectedCode
                        
                        Button {
                            let generator = UISelectionFeedbackGenerator()
                            generator.selectionChanged()
                            onStatusSelected(status)
                        } label: {
                            HStack(spacing: 6) {
                                Text(status.emoji)
                                    .font(.subheadline)
                                
                                Text(status.title)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44) // 44pt touch target for 1-handed outdoors
                            .background(
                                isSelected
                                    ? Color.green.opacity(0.25)
                                    : Color(white: 0.15)
                            )
                            .foregroundStyle(isSelected ? .green : .white)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.green : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(status.title) status")
                        .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        .accessibilityHint("Double tap to set your status to \(status.title)")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
