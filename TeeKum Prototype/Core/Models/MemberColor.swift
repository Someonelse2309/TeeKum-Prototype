//
//  MemberColor.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI

/// 1-byte coded color enum for personal member color-coding in TeeKum.
/// Optimized for AMOLED #000000 dark mode with vibrant neon festival colors.
/// Pure Red is intentionally excluded and strictly reserved for Emergency SOS.
public enum MemberColor: UInt8, CaseIterable, Identifiable, Sendable {
    case unset          = 0x00
    case neonPink       = 0x01
    case electricPurple = 0x02
    case skyBlue        = 0x03
    case limeMint       = 0x04
    case brightTeal     = 0x05
    case neonAmber      = 0x06
    case coralPeach     = 0x07
    case lavender       = 0x08
    
    public var id: UInt8 { rawValue }
    
    public var name: String {
        switch self {
        case .unset:          return "Automatic"
        case .neonPink:       return "Neon Pink"
        case .electricPurple: return "Electric Purple"
        case .skyBlue:        return "Sky Blue"
        case .limeMint:       return "Lime Mint"
        case .brightTeal:     return "Bright Teal"
        case .neonAmber:      return "Neon Amber"
        case .coralPeach:     return "Coral Peach"
        case .lavender:       return "Lavender"
        }
    }
    
    /// The display color in SwiftUI.
    public var swiftUIColor: Color {
        switch self {
        case .unset:
            return Color(red: 0.0, green: 0.85, blue: 1.0)
        case .neonPink:
            return Color(red: 1.0, green: 0.18, blue: 0.45) // #FF2E73
        case .electricPurple:
            return Color(red: 0.69, green: 0.32, blue: 0.87) // #AF52DE
        case .skyBlue:
            return Color(red: 0.0, green: 0.82, blue: 1.0) // #00D2FF
        case .limeMint:
            return Color(red: 0.19, green: 0.82, blue: 0.35) // #30D158
        case .brightTeal:
            return Color(red: 0.0, green: 0.96, blue: 0.83) // #00F5D4
        case .neonAmber:
            return Color(red: 1.0, green: 0.84, blue: 0.04) // #FFD60A
        case .coralPeach:
            return Color(red: 1.0, green: 0.39, blue: 0.51) // #FF6482
        case .lavender:
            return Color(red: 0.82, green: 0.74, blue: 1.0) // #D0BCFF
        }
    }
    
    /// The 8 active selectable palette colors for user selection.
    public static var selectableColors: [MemberColor] {
        allCases.filter { $0 != .unset }
    }
    
    /// Resolves the color code into a specific `MemberColor`.
    /// If `code == 0x00` (unset / legacy zero-padding) or invalid, deterministically hashes `initials` mod 8.
    public static func resolve(code: UInt8, initials: String) -> MemberColor {
        if let specific = MemberColor(rawValue: code), specific != .unset {
            return specific
        }
        return deterministicColor(for: initials)
    }
    
    /// Deterministically maps 1 to 3 uppercase initials into one of the 8 neon palette colors.
    public static func deterministicColor(for initials: String) -> MemberColor {
        let clean = initials.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return .skyBlue }
        
        let hash = clean.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) }
        let index = abs(hash) % 8 // 0...7
        let raw = UInt8(index + 1) // 1...8
        return MemberColor(rawValue: raw) ?? .skyBlue
    }
}
