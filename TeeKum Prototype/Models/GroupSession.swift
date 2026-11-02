//
//  GroupSession.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CryptoKit

/// Decoded details from a serverless share link or QR barcode invite.
nonisolated public struct GroupSessionInvite: Equatable, Sendable {
    public let sessionId: UInt16
    public let sessionName: String
    public let keyData: Data
    
    public init(sessionId: UInt16, sessionName: String, keyData: Data) {
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.keyData = keyData
    }
}

/// Active ephemeral group session model representing local participation.
/// Connects to nearby peers sharing this private group’s invite key.
nonisolated public struct GroupSession: Identifiable, Equatable, Sendable, Codable {
    public var id: UInt16 { sessionId }
    
    /// 16-bit session hash identifying the active festival network.
    public let sessionId: UInt16
    
    /// Human-friendly name for the session (e.g., "Festival Mesh").
    public let sessionName: String
    
    /// 256-bit symmetric key bytes used for authenticated payload encryption.
    public let symmetricKeyData: Data
    
    /// Local user's 3-letter initials (e.g. "DNA").
    public var localInitials: String
    
    /// Backward-compatibility alias for display name.
    public var localMemberName: String { localInitials }
    
    /// Backward-compatibility alias for member ID (3-letter initials).
    public var localMemberId: String { localInitials }
    
    /// True if the user initiated the session (or host role).
    public let isHost: Bool
    
    /// Backward-compatibility slot calculation.
    public var memberSlot: UInt8 {
        let bytes = InitialsCodec.encode(localInitials) ?? [0, 0]
        return bytes[0] ^ bytes[1]
    }
    
    /// Timestamp when session was established.
    public let createdAt: Date
    
    /// Each newly created group has its own private key; there is no universal festival secret.
    public static var defaultSymmetricKeyData: Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }
    public static var defaultSessionId: UInt16 { UInt16.random(in: 1...UInt16.max) }

    public init(
        sessionId: UInt16 = GroupSession.defaultSessionId,
        sessionName: String = "Festival Mesh",
        symmetricKeyData: Data = GroupSession.defaultSymmetricKeyData,
        localInitials: String,
        memberSlot: UInt8? = nil,
        isHost: Bool = true,
        createdAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.symmetricKeyData = symmetricKeyData
        self.localInitials = InitialsCodec.sanitize(localInitials)
        self.isHost = isHost
        self.createdAt = createdAt
    }
    
    // MARK: - Serverless Share Link & QR Encoding
    
    /// Generates a serverless invite URL where the 256-bit key is packed into the URL fragment (#).
    /// Using the URL fragment guarantees that if tapped on the web, the key is never transmitted
    /// to any remote HTTP web server.
    public func inviteURL() -> URL {
        var components = URLComponents()
        components.scheme = "teekum"
        components.host = "join"
        
        var fragment = URLComponents()
        fragment.queryItems = [
            URLQueryItem(name: "key", value: symmetricKeyData.base64EncodedString()),
            URLQueryItem(name: "sid", value: String(format: "%04X", sessionId)),
            URLQueryItem(name: "name", value: sessionName)
        ]
        components.percentEncodedFragment = fragment.percentEncodedQuery
        return components.url ?? URL(string: "teekum://join")!
    }
    
    /// Extracts a `teekum://join...` URL from any arbitrary string (e.g. copied share message, email, or chat).
    /// Uses regex matching to locate the offline link even when embedded inside boilerplate text such as:
    /// `"Join my offline concert group on TeeKum: Festival Crew teekum://join#key=...&sid=...&name=..."`.
    public static func extractInviteURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Direct URL parse if the string itself is a clean teekum URL
        if let directURL = URL(string: trimmed),
           let scheme = directURL.scheme?.lowercased(),
           scheme == "teekum" {
            return directURL
        }
        
        // Regex extraction to find teekum:// URL inside any arbitrary text
        // Matches teekum://join followed by query or fragment parameters
        let pattern = #"(?i)teekum://join[^\s<>"'\(\)\[\]\{\}]+"#
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        
        var rawMatched = String(text[range])
        
        // Trim trailing sentence punctuation if accidentally attached
        let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?")
        while let last = rawMatched.unicodeScalars.last, trailingPunctuation.contains(last) {
            rawMatched.removeLast()
        }
        
        return URL(string: rawMatched)
    }
    
    /// Parses an incoming string (raw text, copied share message, or direct URL) into a `GroupSessionInvite`.
    public static func parseInvite(from text: String) -> GroupSessionInvite? {
        guard let url = extractInviteURL(from: text) else { return nil }
        return parseInvite(from: url)
    }
    
    /// Parses an incoming universal link or QR barcode string into a `GroupSessionInvite`.
    public static func parseInvite(from url: URL) -> GroupSessionInvite? {
        guard let scheme = url.scheme?.lowercased(), scheme == "teekum" else { return nil }
        let host = (url.host ?? "").lowercased()
        guard host == "join" || url.path.lowercased().contains("join") else { return nil }
        
        let rawPayload = (url.fragment?.isEmpty == false ? url.fragment : url.query) ?? ""
        guard !rawPayload.isEmpty else { return nil }
        
        var keyData: Data?
        var sessionId: UInt16?
        var sessionName: String?
        
        let pairs = rawPayload.split(separator: "&")
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1])
            
            switch key {
            case "key":
                let clean = value.removingPercentEncoding ?? value
                keyData = Data(base64Encoded: clean) ?? Data(base64Encoded: clean.replacingOccurrences(of: " ", with: "+"))
            case "sid":
                let clean = value.removingPercentEncoding ?? value
                sessionId = UInt16(clean, radix: 16) ?? UInt16(clean)
            case "name":
                sessionName = value.removingPercentEncoding ?? value
            default:
                break
            }
        }
        
        guard let validKey = keyData, validKey.count == 32,
              let validSid = sessionId, validSid != 0,
              let validName = sessionName else {
            return nil
        }
        
        return GroupSessionInvite(sessionId: validSid, sessionName: validName, keyData: validKey)
    }
}
