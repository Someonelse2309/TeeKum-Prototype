//
//  InitialsCodec.swift
//  TeeKum Prototype
//
//  Created by Nicho on 28/10/26.
//

import Foundation

/// Codec to compress 1 to 3 uppercase letters (A–Z) into 2 bytes using Base-27 radix encoding,
/// and decode 2 bytes back into 1, 2, or 3 letters.
///
/// Mathematical guarantee:
/// - 1 letter: 26 combinations
/// - 2 letters: 26 * 26 = 676 combinations
/// - 3 letters: 26 * 26 * 26 = 17,576 combinations
/// - Total: 18,278 combinations < 65,536 (2^16), fitting cleanly into exactly 2 bytes (UInt16).
nonisolated public enum InitialsCodec {
    
    // MARK: - Encode
    
    /// Encodes 1 to 3 uppercase letters (A–Z) into 2 big-endian bytes.
    /// Returns nil if string length is not between 1 and 3 letters in the range A–Z.
    public static func encode(_ initials: String) -> [UInt8]? {
        let letters = Array(initials.uppercased().utf8)
        
        // Must be 1 to 3 uppercase letters A–Z (ASCII 65..90)
        guard letters.count >= 1 && letters.count <= 3,
              letters.allSatisfy({ $0 >= 65 && $0 <= 90 }) else {
            return nil
        }
        
        // Convert to numbers: A=1..Z=26, empty=0
        let a = Int(letters[0]) - 64
        let b = letters.count >= 2 ? (Int(letters[1]) - 64) : 0
        let c = letters.count >= 3 ? (Int(letters[2]) - 64) : 0
        
        // Base-27 positional formula: (a * 729) + (b * 27) + c
        let number = (a * 729) + (b * 27) + c
        
        // Split into 2 bytes (big-endian)
        let highByte = UInt8(number / 256)
        let lowByte = UInt8(number % 256)
        
        return [highByte, lowByte]
    }
    
    /// Helper to encode to a single UInt16.
    public static func encodeToUInt16(_ initials: String) -> UInt16? {
        guard let bytes = encode(initials) else { return nil }
        return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    }
    
    // MARK: - Decode
    
    /// Decodes 2 bytes back into 1 to 3 uppercase letters (A–Z).
    /// Returns nil if bytes.count != 2 or value is not within valid ranges.
    public static func decode(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 2 else {
            return nil
        }
        
        let number = (Int(bytes[0]) * 256) + Int(bytes[1])
        
        // Valid range: minimum is "A" (1 * 729 = 729), maximum is "ZZZ" (19,682)
        guard number >= 729 && number <= 19682 else {
            return nil
        }
        
        let a = number / 729
        let b = (number % 729) / 27
        let c = number % 27
        
        // Range validation
        guard a >= 1 && a <= 26, b <= 26, c <= 26 else {
            return nil
        }
        
        // Structural validation: cannot have c > 0 if b == 0 (no letter 3 without letter 2)
        guard !(b == 0 && c > 0) else {
            return nil
        }
        
        var letterBytes: [UInt8] = [UInt8(a + 64)]
        if b > 0 {
            letterBytes.append(UInt8(b + 64))
        }
        if c > 0 {
            letterBytes.append(UInt8(c + 64))
        }
        
        return String(bytes: letterBytes, encoding: .utf8)
    }
    
    /// Helper to decode from a single UInt16.
    public static func decodeFromUInt16(_ value: UInt16) -> String? {
        let high = UInt8((value >> 8) & 0xFF)
        let low = UInt8(value & 0xFF)
        return decode([high, low])
    }
    
    /// Sanitizes an arbitrary input string to produce a valid 1 to 3-letter uppercase initial.
    /// E.g. "Alex" -> "ALE", "Jo" -> "JO", "A" -> "A", " d.n.a! " -> "DNA"
    public static func sanitize(_ input: String) -> String {
        let letters = input.uppercased().filter { $0 >= "A" && $0 <= "Z" }
        if letters.isEmpty {
            return "A"
        }
        return String(letters.prefix(3))
    }
    
    /// Validates whether a candidate string is a valid 1 to 3-letter uppercase initial (A–Z).
    public static func isValid(_ initials: String) -> Bool {
        let trimmed = initials.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count >= 1 && trimmed.count <= 3 else { return false }
        return trimmed.allSatisfy { $0 >= "A" && $0 <= "Z" }
    }
}
