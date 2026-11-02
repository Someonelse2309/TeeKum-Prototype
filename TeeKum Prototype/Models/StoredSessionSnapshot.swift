import Foundation

nonisolated struct StoredSessionSnapshot: Codable {
    let session: GroupSession
    let seenSOSEventIDs: Set<UInt32>
}
