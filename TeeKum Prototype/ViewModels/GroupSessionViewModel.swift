//
//  GroupSessionViewModel.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import Observation

/// Pure MVVM ViewModel managing group session lifecycle, 3-letter initials onboarding,
/// and roster of active peers.
@Observable
@MainActor
public final class GroupSessionViewModel {
    /// Active group session, or nil if user is in unpaired onboarding state.
    public var activeSession: GroupSession?
    
    /// List of members participating in the active session.
    public var members: [Member] = []
    
    /// User's chosen 1 to 3-letter initials.
    public var localUserName: String = ""
    
    /// User's draft group name when creating a new group.
    public var newGroupName: String = ""
    
    /// State banner / error message displayed in UI.
    public var errorMessage: String?
    
    /// Pending group invite awaiting user agreement to the mesh compact before joining.
    public var pendingInvite: GroupSessionInvite? = nil
    
    /// True when currently advertising or establishing radio connections.
    public var isConnecting: Bool = false
    
    public var hasActiveSession: Bool {
        activeSession != nil
    }
    
    /// Safe 4-byte key fingerprint in hexadecimal format for UI diagnostics.
    public var keyFingerprint: String? {
        activeSession?.symmetricKeyData.prefix(4).map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// Serverless invite URL containing 256-bit symmetric key in URL fragment (#).
    public var inviteURL: URL? {
        activeSession?.inviteURL()
    }
    
    private static let activeSessionStorageKey = "com.teekum.activeSession"
    private static let localUserNameStorageKey = "com.teekum.localUserName"
    
    public init(activeSession: GroupSession? = nil) {
        let storedUser = UserDefaults.standard.string(forKey: Self.localUserNameStorageKey) ?? ""
        self.localUserName = storedUser
        
        if let activeSession {
            self.activeSession = activeSession
        } else {
            self.activeSession = Self.loadStoredSession()
        }
    }
    
    /// Enters the festival auto-mesh network using 1 to 3 uppercase initials.
    public func enterAutoMesh(initials: String) {
        let cleanInitials = initials.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleanInitials.count >= 1 && cleanInitials.count <= 3,
              cleanInitials.allSatisfy({ $0 >= "A" && $0 <= "Z" }) else {
            errorMessage = "Initials must be 1 to 3 uppercase letters (A–Z)."
            return
        }
        
        let session = GroupSession(localInitials: cleanInitials)
        self.activeSession = session
        self.localUserName = cleanInitials
        self.errorMessage = nil
        saveStoredSession(session)
        UserDefaults.standard.set(cleanInitials, forKey: Self.localUserNameStorageKey)
    }
    
    /// Creates a private group with a newly generated 256-bit key, custom name, and initials (1–3 letters).
    public func createGroup(name: String, localName: String) {
        let cleanInitials = InitialsCodec.sanitize(localName)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = trimmedName.isEmpty ? "Festival Group" : trimmedName
        
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        let keyData = Data(keyBytes)
        
        let session = GroupSession(
            sessionId: UInt16.random(in: 1...UInt16.max),
            sessionName: sessionName,
            symmetricKeyData: keyData,
            localInitials: cleanInitials,
            isHost: true
        )
        self.activeSession = session
        self.localUserName = cleanInitials
        self.errorMessage = nil
        saveStoredSession(session)
        UserDefaults.standard.set(cleanInitials, forKey: Self.localUserNameStorageKey)
    }
    
    /// Joins an existing group using decoded invite parameters and custom initials (1–3 letters).
    public func joinGroup(invite: GroupSessionInvite, localName: String) {
        let cleanInitials = InitialsCodec.sanitize(localName)
        let session = GroupSession(
            sessionId: invite.sessionId,
            sessionName: invite.sessionName,
            symmetricKeyData: invite.keyData,
            localInitials: cleanInitials,
            isHost: false
        )
        self.activeSession = session
        self.localUserName = cleanInitials
        self.errorMessage = nil
        saveStoredSession(session)
        UserDefaults.standard.set(cleanInitials, forKey: Self.localUserNameStorageKey)
    }
    
    /// Leaves the current group and triggers full ephemeral teardown.
    public func leaveGroup() {
        clearStoredSession()
        self.activeSession = nil
        self.members.removeAll()
        self.errorMessage = nil
        self.isConnecting = false
    }
    
    /// Directly sets and persists an already constructed active session.
    public func setActiveSession(_ session: GroupSession) {
        self.activeSession = session
        self.localUserName = session.localInitials
        self.errorMessage = nil
        saveStoredSession(session)
        UserDefaults.standard.set(session.localInitials, forKey: Self.localUserNameStorageKey)
    }
    
    /// Completely resets UI state.
    public func resetSessionState() {
        leaveGroup()
        newGroupName = ""
    }
    
    // MARK: - Local Persistence Helpers
    
    private static func loadStoredSession() -> GroupSession? {
        guard let data = UserDefaults.standard.data(forKey: activeSessionStorageKey) else { return nil }
        return try? JSONDecoder().decode(GroupSession.self, from: data)
    }
    
    private func saveStoredSession(_ session: GroupSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.activeSessionStorageKey)
        }
    }
    
    private func clearStoredSession() {
        UserDefaults.standard.removeObject(forKey: Self.activeSessionStorageKey)
    }
    
    /// Updates or inserts a peer member in the active session roster.
    public func updateMember(_ member: Member) {
        if let idx = members.firstIndex(where: { $0.id == member.id }) {
            members[idx] = member
        } else {
            members.append(member)
        }
    }
    
    /// Removes a member from the session roster.
    public func removeMember(id: String) {
        members.removeAll(where: { $0.id == id })
    }
    
    /// Clears any active error banner.
    public func clearError() {
        self.errorMessage = nil
    }
}
