import Foundation

/// Bounded ciphertext custody for the active session. Owned by PeerTransportService.
/// shortcut: custody is in memory; persist encrypted entries if process-restart delivery is required.
nonisolated struct CarryMessageStore {
    static let retention: TimeInterval = 600
    private let capacity: Int
    private let retention: TimeInterval
    private struct Entry {
        let data: Data
        let expiresAt: Date
        let isForeign: Bool
        var sources: Set<String> = []
        struct Attempt {
            var count: Int
            var lastSentAt: Date
        }
        var attempts: [String: Attempt] = [:]
    }
    private var entries: [Data: Entry] = [:]
    private var order: [Data] = []

    init(capacity: Int = 256, retention: TimeInterval = Self.retention) {
        self.capacity = max(1, capacity)
        self.retention = max(1, retention)
    }

    mutating func remember(_ data: Data, isForeign: Bool, excludingPeerId: String? = nil, now: Date = Date()) {
        purge(now: now)
        guard let packet = try? RawWirePacket.fromWireData(data),
              packet.envelope.type == .chatMessage || packet.envelope.type == .ack else { return }
        let key = identity(data)
        // Retries and loops must not extend custody or reset the hop budget.
        if entries[key] != nil {
            if let excludingPeerId { entries[key]?.sources.insert(excludingPeerId) }
            return
        }
        while order.count >= capacity {
            entries.removeValue(forKey: order.removeFirst())
        }
        entries[key] = Entry(data: data, expiresAt: now.addingTimeInterval(retention), isForeign: isForeign,
            sources: Set(excludingPeerId.map { [$0] } ?? []))
        order.append(key)
    }

    /// ACKs precede chat; each peer gets bounded fast attempts, then slow carry retries.
    mutating func nextTransmission(to peers: [String], now: Date = Date()) -> (data: Data, peer: String, isForeign: Bool)? {
        purge(now: now)
        var candidate: (data: Data, peer: String, isForeign: Bool)?
        var oldest = Date.distantFuture
        var bestPriority = Int.max
        for key in order {
            guard let entry = entries[key] else { continue }
            let priority = (entry.data[entry.data.startIndex] & 0x0F) == PacketType.ack.rawValue ? 0 : 1
            for peer in peers where !entry.sources.contains(peer) {
                let attempt = entry.attempts[peer]
                let last = attempt?.lastSentAt ?? .distantPast
                let delay = (attempt?.count ?? 0) < TeeKumConfiguration.Chat.carryFastAttemptLimit
                    ? TeeKumConfiguration.Chat.carryFastRetryInterval : TeeKumConfiguration.Chat.carrySlowRetryInterval
                if now.timeIntervalSince(last) >= delay,
                   priority < bestPriority || (priority == bestPriority && last < oldest) {
                    bestPriority = priority
                    oldest = last
                    candidate = (entry.data, peer, entry.isForeign)
                }
            }
        }
        return candidate
    }

    mutating func markAttempt(_ data: Data, to peer: String, now: Date = Date()) {
        let key = identity(data)
        let count = entries[key]?.attempts[peer]?.count ?? 0
        entries[key]?.attempts[peer] = Entry.Attempt(count: count + 1, lastSentAt: now)
    }

    mutating func disconnected(_ peer: String) {
        for key in order { entries[key]?.attempts.removeValue(forKey: peer) }
    }

    mutating func removeForeign() {
        entries = entries.filter { !$0.value.isForeign }
        order.removeAll { entries[$0] == nil }
    }

    mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
    }

    private mutating func purge(now: Date) {
        entries = entries.filter { $0.value.expiresAt > now }
        order.removeAll { entries[$0] == nil }
    }

    private func identity(_ data: Data) -> Data {
        var key = data
        if key.count > 2 { key[key.startIndex + 2] = 0 }
        return key
    }
}
