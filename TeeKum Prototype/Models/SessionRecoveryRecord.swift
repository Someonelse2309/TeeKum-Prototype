import Foundation
import SwiftData

/// Contains authenticated ciphertext only. Group keys and coordinates are never stored in plaintext.
@Model
final class SessionRecoveryRecord {
    var encryptedSnapshot: Data

    init(encryptedSnapshot: Data) {
        self.encryptedSnapshot = encryptedSnapshot
    }
}
