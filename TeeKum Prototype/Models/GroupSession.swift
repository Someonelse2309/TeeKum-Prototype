//
//  GroupSession.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CryptoKit

/// Decoded details from a serverless share link or QR barcode invite.
public struct GroupSessionInvite: Equatable, Sendable {
    public let sessionId: UInt32
    public let sessionName: String
    public let keyData: Data
    
    public init(sessionId: UInt32, sessionName: String, keyData: Data) {
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.keyData = keyData
    }
}

/// Active ephemeral group session model representing local participation.
public struct GroupSession: Identifiable, Equatable, Sendable, Codable {
    public var id: UInt32 { sessionId }
    
    /// 32-bit big-endian hash identifying the group session network.
    public let sessionId: UInt32
    
    /// Human-friendly name for the group (e.g., "Coachella Crew").
    public let sessionName: String
    
    /// 256-bit symmetric key bytes used for authenticated payload encryption.
    public let symmetricKeyData: Data
    
    /// Ephemeral 32-bit ID assigned to this local device within the session.
    public let localMemberId: UInt32
    
    /// Local user's chosen display name.
    public var localMemberName: String
    
    /// Whether this device initiated the group creation.
    public let isHost: Bool
    
    /// Timestamp when session was established.
    public let createdAt: Date
    
    public init(
        sessionId: UInt32 = UInt32.random(in: 1...UInt32.max),
        sessionName: String,
        symmetricKeyData: Data,
        localMemberId: UInt32 = UInt32.random(in: 1...UInt32.max),
        localMemberName: String,
        isHost: Bool,
        createdAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.symmetricKeyData = symmetricKeyData
        self.localMemberId = localMemberId
        self.localMemberName = localMemberName
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
        
        let keyBase64 = symmetricKeyData.base64EncodedString()
        let sidHex = String(format: "%08X", sessionId)
        let safeName = sessionName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Group"
        
        components.percentEncodedFragment = "key=\(keyBase64)&sid=\(sidHex)&name=\(safeName)"
        return components.url ?? URL(string: "teekum://join")!
    }
    
    /// Parses an incoming universal link or QR barcode string into a `GroupSessionInvite`.
    public static func parseInvite(from url: URL) -> GroupSessionInvite? {
        guard let scheme = url.scheme?.lowercased(), scheme == "teekum" else { return nil }
        let host = (url.host ?? "").lowercased()
        guard host == "join" || url.path.lowercased().contains("join") else { return nil }
        
        let rawPayload = (url.fragment?.isEmpty == false ? url.fragment : url.query) ?? ""
        guard !rawPayload.isEmpty else { return nil }
        
        var keyData: Data?
        var sessionId: UInt32?
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
                sessionId = UInt32(clean, radix: 16)
            case "name":
                sessionName = value.removingPercentEncoding ?? value
            default:
                break
            }
        }
        
        guard let validKey = keyData, validKey.count == 32,
              let validSid = sessionId,
              let validName = sessionName else {
            return nil
        }
        
        return GroupSessionInvite(sessionId: validSid, sessionName: validName, keyData: validKey)
    }
}
