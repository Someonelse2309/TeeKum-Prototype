//
//  ColorPickerView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI

/// Reusable palette selector displaying the 8 curated AMOLED neon colors for TeeKum members.
public struct ColorPickerPaletteView: View {
    @Binding public var selectedColor: MemberColor
    public var onSelect: ((MemberColor) -> Void)? = nil
    
    public init(selectedColor: Binding<MemberColor>, onSelect: ((MemberColor) -> Void)? = nil) {
        self._selectedColor = selectedColor
        self.onSelect = onSelect
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(MemberColor.selectableColors) { color in
                    Button {
                        selectedColor = color
                        onSelect?(color)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 38, height: 38)
                                .shadow(color: color.swiftUIColor.opacity(selectedColor == color ? 0.7 : 0.25), radius: selectedColor == color ? 6 : 2)
                            
                            if selectedColor == color {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2.5)
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.85))
                            }
                        }
                        .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.name)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }
}

/// Compact bottom sheet for changing personal color code mid-session.
public struct ColorPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding public var selectedColor: MemberColor
    public let userInitials: String
    public var onSave: (MemberColor) -> Void
    
    public init(
        selectedColor: Binding<MemberColor>,
        userInitials: String,
        onSave: @escaping (MemberColor) -> Void
    ) {
        self._selectedColor = selectedColor
        self.userInitials = userInitials
        self.onSave = onSave
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Preview avatar
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.85))
                                .frame(width: 80, height: 80)
                            
                            Circle()
                                .stroke(selectedColor.swiftUIColor, lineWidth: 3)
                                .frame(width: 80, height: 80)
                                .shadow(color: selectedColor.swiftUIColor.opacity(0.6), radius: 10)
                            
                            Text(userInitials.isEmpty ? "ME" : userInitials)
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundStyle(selectedColor.swiftUIColor)
                        }
                        
                        Text(selectedColor.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(selectedColor.swiftUIColor)
                    }
                    .padding(.top, 16)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CHOOSE YOUR FESTIVAL COLOR")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.gray)
                        
                        ColorPickerPaletteView(selectedColor: $selectedColor)
                    }
                    .padding(.horizontal, 16)
                    
                    Text("Your color illuminates your pin on the map and your blip on friends' tactical radars. Emergency SOS will still flash urgent red.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    Spacer()
                    
                    Button {
                        onSave(selectedColor)
                        dismiss()
                    } label: {
                        Text("Apply Color")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(selectedColor.swiftUIColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: selectedColor.swiftUIColor.opacity(0.4), radius: 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Personal Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onSave(selectedColor)
                        dismiss()
                    }
                    .foregroundStyle(Color.white)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
