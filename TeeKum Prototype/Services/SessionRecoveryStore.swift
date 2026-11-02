import CryptoKit
import Foundation
import Security
import SwiftData

/// A single active-session snapshot. The context and its records stay on the main actor.
/// Explicit saves make recovery and teardown independent of SwiftData autosave timing.
@MainActor
final class SessionRecoveryStore {
    private let container: ModelContainer
    private let context: ModelContext
    private let keyAccount = "com.teekum.recovery.v1"
    private let memoryOnly: Bool
    private var testKey: SymmetricKey?
    private var loadedSession: GroupSession?
    private(set) var seenSOSEventIDs: Set<UInt32> = []

    init(memoryOnly: Bool = false) throws {
        self.memoryOnly = memoryOnly
        let configuration = ModelConfiguration(isStoredInMemoryOnly: memoryOnly, cloudKitDatabase: .none)
        container = try ModelContainer(for: SessionRecoveryRecord.self, configurations: configuration)
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func load(now: Date = .now) throws -> GroupSession? {
        var descriptor = FetchDescriptor<SessionRecoveryRecord>()
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return nil }
        guard let key = try recoveryKey(create: false) else {
            try purge()
            return nil
        }
        let box = try ChaChaPoly.SealedBox(combined: record.encryptedSnapshot)
        let bytes = try ChaChaPoly.open(box, using: key)
        let snapshot = try JSONDecoder().decode(StoredSessionSnapshot.self, from: bytes)
        let session = snapshot.session
        loadedSession = session
        seenSOSEventIDs = snapshot.seenSOSEventIDs
        guard now.timeIntervalSince(session.createdAt) >= 0,
              now.timeIntervalSince(session.createdAt) < 12 * 60 * 60 else {
            try purge()
            return nil
        }
        return session
    }

    func save(_ session: GroupSession) throws {
        guard let key = try recoveryKey(create: true) else { throw CryptoServiceError.keyNotFound }
        if loadedSession?.symmetricKeyData != session.symmetricKeyData { seenSOSEventIDs.removeAll() }
        loadedSession = session
        let bytes = try JSONEncoder().encode(StoredSessionSnapshot(session: session, seenSOSEventIDs: seenSOSEventIDs))
        let encrypted = try ChaChaPoly.seal(bytes, using: key).combined
        try context.delete(model: SessionRecoveryRecord.self)
        context.insert(SessionRecoveryRecord(encryptedSnapshot: encrypted))
        try context.save()
    }

    func recordSOSEvent(_ eventID: UInt32, session: GroupSession) throws {
        guard loadedSession == session else { return }
        seenSOSEventIDs.insert(eventID)
        try save(session)
    }

    func purge() throws {
        loadedSession = nil
        seenSOSEventIDs.removeAll()
        // Delete the decryption key first: old SQLite/WAL pages then contain unusable ciphertext.
        if memoryOnly {
            testKey = nil
        } else {
            let status = SecItemDelete(keyQuery() as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CryptoServiceError.keychainDeleteFailed(status)
            }
        }
        try context.delete(model: SessionRecoveryRecord.self)
        try context.save()
    }

    private func keyQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keyAccount,
         kSecAttrAccount as String: "active-session"]
    }

    private func recoveryKey(create: Bool) throws -> SymmetricKey? {
        if memoryOnly {
            if testKey == nil, create { testKey = SymmetricKey(size: .bits256) }
            return testKey
        }
        var query = keyQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let bytes = item as? Data, bytes.count == 32 {
            return SymmetricKey(data: bytes)
        }
        guard status == errSecItemNotFound else { throw CryptoServiceError.keychainLoadFailed(status) }
        guard create else { return nil }
        let key = SymmetricKey(size: .bits256)
        var insert = keyQuery()
        insert[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let saveStatus = SecItemAdd(insert as CFDictionary, nil)
        guard saveStatus == errSecSuccess else { throw CryptoServiceError.keychainSaveFailed(saveStatus) }
        return key
    }
}
