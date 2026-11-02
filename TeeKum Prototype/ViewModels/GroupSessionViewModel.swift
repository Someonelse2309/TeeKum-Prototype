//
//  GroupSessionViewModel.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import Observation
import CryptoKit

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
        activeSession.map { SHA256.hash(data: $0.symmetricKeyData).prefix(4).map { String(format: "%02hhx", $0) }.joined() }
    }
    
    /// Serverless invite URL containing 256-bit symmetric key in URL fragment (#).
    public var inviteURL: URL? {
        activeSession?.inviteURL()
    }
    
    @ObservationIgnored private var recoveryStore: SessionRecoveryStore?

    public init(activeSession: GroupSession? = nil, inMemoryStorage: Bool = false) {
        // Old snapshots included plaintext group keys. Never restore or migrate those secrets.
        UserDefaults.standard.removeObject(forKey: "com.teekum.activeSession")
        UserDefaults.standard.removeObject(forKey: "com.teekum.localUserName")
        do {
            let testing = ProcessInfo.processInfo.arguments.contains("-runAllTests")
            let store = try SessionRecoveryStore(memoryOnly: inMemoryStorage || testing)
            recoveryStore = store
            self.activeSession = try activeSession ?? store.load()
            localUserName = self.activeSession?.localInitials ?? ""
        } catch {
            self.activeSession = activeSession
            errorMessage = "Session recovery is unavailable. Create or join a group again."
        }
    }

    init(recoveryStore: SessionRecoveryStore) {
        self.recoveryStore = recoveryStore
        do {
            activeSession = try recoveryStore.load()
            localUserName = activeSession?.localInitials ?? ""
        } catch { errorMessage = "Session recovery is unavailable." }
    }

    var recoveredSOSEventIDs: Set<UInt32> { recoveryStore?.seenSOSEventIDs ?? [] }

    func recordSOSEvent(_ eventID: UInt32) {
        guard let activeSession else { return }
        do { try recoveryStore?.recordSOSEvent(eventID, session: activeSession) }
        catch { errorMessage = "SOS received, but replay protection could not be saved." }
    }

    public func expireSessionIfNeeded(now: Date = .now) {
        if let activeSession, now.timeIntervalSince(activeSession.createdAt) >= 12 * 3600 {
            leaveGroup()
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
    }
    
    /// Creates a private group with a newly generated 256-bit key, custom name, and initials (1–3 letters).
    public func createGroup(name: String, localName: String) {
        let cleanInitials = InitialsCodec.sanitize(localName)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = trimmedName.isEmpty ? "Festival Group" : trimmedName
        
        let keyData = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }

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
    }
    
    /// Leaves the current group and triggers full ephemeral teardown.
    public func leaveGroup() {
        self.errorMessage = nil
        guard clearStoredSession() else { return }
        self.pendingInvite = nil
        self.activeSession = nil
        self.members.removeAll()
        self.isConnecting = false
    }
    
    /// Directly sets and persists an already constructed active session.
    public func setActiveSession(_ session: GroupSession) {
        self.activeSession = session
        self.localUserName = session.localInitials
        self.errorMessage = nil
        saveStoredSession(session)
    }
    
    /// Completely resets UI state.
    public func resetSessionState() {
        leaveGroup()
        newGroupName = ""
    }
    
    // MARK: - Local Persistence Helpers
    
    private func saveStoredSession(_ session: GroupSession) {
        do {
            guard let recoveryStore else { throw CryptoServiceError.keyNotFound }
            try recoveryStore.save(session)
        } catch {
            errorMessage = "Group is active, but secure recovery could not be saved."
        }
    }

    private func clearStoredSession() -> Bool {
        do { try recoveryStore?.purge(); return true }
        catch {
            errorMessage = "Secure session cleanup failed. Please try leaving again."
            return false
        }
    }

    /// Updates or inserts a peer member in the active session roster.
    public func updateMember(_ member: Member) {
        if let idx = members.firstIndex(where: { $0.id == member.id }) {
            // A delayed packet must not move a friend back to an older GPS fix.
            guard member.lastSeen >= members[idx].lastSeen else { return }
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
