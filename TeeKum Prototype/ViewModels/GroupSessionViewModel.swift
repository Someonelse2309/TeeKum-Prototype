//
//  GroupSessionViewModel.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import Observation

/// Pure MVVM ViewModel managing group session lifecycle, serverless QR/Link pairing,
/// and roster of active peers.
@Observable
@MainActor
public final class GroupSessionViewModel {
    /// Active group session, or nil if user is in unpaired onboarding state.
    public var activeSession: GroupSession?
    
    /// List of members participating in the active session.
    public var members: [Member] = []
    
    /// User's chosen display name for group pairing.
    public var localUserName: String = ""
    
    /// Name for newly created group sessions.
    public var newGroupName: String = ""
    
    /// State banner / error message displayed in UI.
    public var errorMessage: String?
    
    /// True when currently advertising or establishing radio connections.
    public var isConnecting: Bool = false
    
    public var hasActiveSession: Bool {
        activeSession != nil
    }
    
    /// Serverless universal invite URL packing session metadata and key into the URL fragment.
    public var inviteURL: URL? {
        activeSession?.inviteURL()
    }
    
    /// Safe 4-byte key fingerprint in hexadecimal format for UI display without exposing full secret.
    public var keyFingerprint: String? {
        activeSession?.symmetricKeyData.prefix(4).map { String(format: "%02hhx", $0) }.joined()
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
    
    /// Creates a new serverless group session with a cryptographically secure 256-bit key.
    public func createGroup(name: String, localName: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = localName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedUser.isEmpty else {
            errorMessage = "Group and user names cannot be empty."
            return
        }
        
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        let keyData = Data(keyBytes)
        
        let session = GroupSession(
            sessionName: trimmedName,
            symmetricKeyData: keyData,
            localMemberName: trimmedUser,
            isHost: true
        )
        self.activeSession = session
        self.localUserName = trimmedUser
        self.errorMessage = nil
        saveStoredSession(session)
        UserDefaults.standard.set(trimmedUser, forKey: Self.localUserNameStorageKey)
    }
    
    /// Joins an existing group session using decoded invite details (from QR or URL link).
    public func joinGroup(invite: GroupSessionInvite, localName: String) {
        let trimmedUser = localName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty else {
            errorMessage = "Please enter your name to join."
            return
        }
        
        let session = GroupSession(
            sessionId: invite.sessionId,
            sessionName: invite.sessionName,
            symmetricKeyData: invite.keyData,
            localMemberName: trimmedUser,
            isHost: false
        )
        self.activeSession = session
        self.localUserName = trimmedUser
        self.errorMessage = nil
        saveStoredSession(session)
        UserDefaults.standard.set(trimmedUser, forKey: Self.localUserNameStorageKey)
    }
    
    /// Leaves the current group and triggers full ephemeral teardown.
    public func leaveGroup() {
        clearStoredSession()
        self.activeSession = nil
        self.members.removeAll()
        self.errorMessage = nil
        self.isConnecting = false
    }
    
    /// Directly sets and persists an already constructed active session (e.g. host QR creation).
    public func setActiveSession(_ session: GroupSession) {
        self.activeSession = session
        self.localUserName = session.localMemberName
        self.errorMessage = nil
        saveStoredSession(session)
        UserDefaults.standard.set(session.localMemberName, forKey: Self.localUserNameStorageKey)
    }
    
    /// Completely resets UI state and all drafted sessions for starting fresh.
    public func resetSessionState() {
        leaveGroup()
        self.newGroupName = ""
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
    public func removeMember(id: UInt32) {
        members.removeAll(where: { $0.id == id })
    }
    
    /// Clears any active error banner.
    public func clearError() {
        self.errorMessage = nil
    }
}
