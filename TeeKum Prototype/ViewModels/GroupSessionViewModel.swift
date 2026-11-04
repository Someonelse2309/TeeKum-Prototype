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
    
    /// User's chosen personal member color.
    public var localColor: MemberColor = .unset
    
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
    private static let localUserColorStorageKey = "com.teekum.localUserColorCode"
    
    public init(activeSession: GroupSession? = nil) {
        let storedUser = UserDefaults.standard.string(forKey: Self.localUserNameStorageKey) ?? ""
        self.localUserName = storedUser
        
        let storedColorCode = UInt8(UserDefaults.standard.integer(forKey: Self.localUserColorStorageKey))
        self.localColor = MemberColor(rawValue: storedColorCode) ?? .unset
        
        if let activeSession {
            self.activeSession = activeSession
        } else {
            self.activeSession = Self.loadStoredSession()
        }
    }
    
    /// Sets the local user's personal member color, updates active session, and persists preference.
    public func setLocalColor(_ color: MemberColor) {
        self.localColor = color
        UserDefaults.standard.set(Int(color.rawValue), forKey: Self.localUserColorStorageKey)
        if var session = activeSession {
            session.localColorCode = color.rawValue
            self.activeSession = session
            saveStoredSession(session)
        }
    }
    
    /// Enters the festival auto-mesh network using 1 to 3 uppercase initials.
    public func enterAutoMesh(initials: String, colorCode: UInt8? = nil) {
        let cleanInitials = initials.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard InitialsCodec.isValid(cleanInitials) else {
            errorMessage = "Initials must be 1 to 3 uppercase letters (A–Z)."
            return
        }
        
        let color = colorCode ?? localColor.rawValue
        let session = GroupSession(localInitials: cleanInitials, localColorCode: color)
        self.activeSession = session
        self.localUserName = cleanInitials
        self.errorMessage = nil
        saveStoredSession(session)
        UserDefaults.standard.set(cleanInitials, forKey: Self.localUserNameStorageKey)
    }
    
    /// Generates a new GroupSession with a cryptographic 256-bit key for staging/presentation without immediately activating it.
    public func createDraftSession(name: String, localName: String, colorCode: UInt8? = nil) -> GroupSession {
        let cleanInitials = InitialsCodec.sanitize(localName)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = trimmedName.isEmpty ? "Festival Group" : trimmedName
        
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        let keyData = Data(keyBytes)
        
        let color = colorCode ?? localColor.rawValue
        return GroupSession(
            sessionId: UInt16.random(in: 1...UInt16.max),
            sessionName: sessionName,
            symmetricKeyData: keyData,
            localInitials: cleanInitials,
            localColorCode: color,
            isHost: true
        )
    }
    
    /// Creates a private group with a newly generated 256-bit key, custom name, and initials (1–3 letters).
    public func createGroup(name: String, localName: String, colorCode: UInt8? = nil) {
        let session = createDraftSession(name: name, localName: localName, colorCode: colorCode)
        self.activeSession = session
        self.localUserName = session.localInitials
        self.errorMessage = nil
        saveStoredSession(session)
        UserDefaults.standard.set(session.localInitials, forKey: Self.localUserNameStorageKey)
    }
    
    /// Joins an existing group using decoded invite parameters and custom initials (1–3 letters).
    public func joinGroup(invite: GroupSessionInvite, localName: String, colorCode: UInt8? = nil) {
        let cleanInitials = InitialsCodec.sanitize(localName)
        let color = colorCode ?? localColor.rawValue
        let session = GroupSession(
            sessionId: invite.sessionId,
            sessionName: invite.sessionName,
            symmetricKeyData: invite.keyData,
            localInitials: cleanInitials,
            localColorCode: color,
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
        Task { @MainActor in
            await LiveActivityManager.shared.endSessionActivity()
        }
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
