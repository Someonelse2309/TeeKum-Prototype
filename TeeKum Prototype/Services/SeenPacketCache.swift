//
//  SeenPacketCache.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation

/// Thread-safe in-memory Bounded LRU Duplicate Packet Suppression Cache.
///
/// Implements Architectural Decision 2 & 7:
/// - Max capacity: 1,024 entries (~7.1 KB RAM footprint)
/// - Sliding retention TTL: 300 seconds (5 minutes)
/// - Deterministic eviction: Oldest / least-recently-seen packet key evicted on overflow
/// - Injected `MeshClock` dependency for 100% deterministic unit testing
/// - Keyed by canonical 7-byte `PacketKey` (excluding mutating hop metadata)
public actor SeenPacketCache {
    
    public struct CacheEntry: Sendable {
        public let key: PacketKey
        public let arrivalTime: Date
        public var lastAccessed: Date
    }
    
    private let capacity: Int
    private let ttl: TimeInterval
    private let clock: MeshClock
    
    /// Map of canonical packet key -> entry
    private var entries: [PacketKey: CacheEntry] = [:]
    
    /// Ordered list of keys maintaining LRU order (most recently accessed at the end)
    private var lruOrder: [PacketKey] = []
    
    public init(
        capacity: Int = 1024,
        ttl: TimeInterval = 300.0,
        clock: MeshClock = SystemMeshClock()
    ) {
        self.capacity = max(1, capacity)
        self.ttl = max(1.0, ttl)
        self.clock = clock
    }
    
    /// Current number of unexpired entries in the cache.
    public var count: Int {
        entries.count
    }
    
    /// Checks whether the packet key is present and unexpired.
    /// Does NOT mutate the cache or record the key.
    public func contains(_ key: PacketKey, now: Date? = nil) -> Bool {
        let currentTime = now ?? clock.now()
        guard let entry = entries[key] else { return false }
        if currentTime.timeIntervalSince(entry.arrivalTime) >= ttl {
            return false
        }
        return true
    }
    
    /// Inserts or touches a packet key in the cache.
    public func insert(_ key: PacketKey, now: Date? = nil) {
        let currentTime = now ?? clock.now()
        _ = recordKey(key, now: currentTime)
    }
    
    /// Atomically checks if a packet key is a duplicate, and if not, records it.
    ///
    /// - Returns: `true` if the packet was already present and fresh (duplicate to drop).
    ///            `false` if the packet was not seen before (fresh packet to process).
    public func isDuplicateAndRecord(_ key: PacketKey, now: Date? = nil) -> Bool {
        let currentTime = now ?? clock.now()
        
        // Fast lookup
        if let existing = entries[key] {
            if currentTime.timeIntervalSince(existing.arrivalTime) < ttl {
                // Fresh duplicate! Update LRU order
                touchLRU(key, now: currentTime)
                return true
            } else {
                // Expired entry found: treat as fresh arrival
                removeEntry(key)
            }
        }
        
        // Evict expired entries if approaching capacity
        if entries.count >= capacity {
            purgeExpiredEntries(currentTime: currentTime)
        }
        
        // If still at capacity, evict least recently accessed entry (head of lruOrder)
        while entries.count >= capacity, !lruOrder.isEmpty {
            let oldest = lruOrder.removeFirst()
            entries.removeValue(forKey: oldest)
        }
        
        // Insert new entry
        let newEntry = CacheEntry(key: key, arrivalTime: currentTime, lastAccessed: currentTime)
        entries[key] = newEntry
        lruOrder.append(key)
        return false
    }
    
    /// Manually purges all expired entries beyond the 5-minute TTL window.
    public func purgeExpired(now: Date? = nil) {
        let currentTime = now ?? clock.now()
        purgeExpiredEntries(currentTime: currentTime)
    }
    
    /// Wipes all cached packet keys (e.g. on group teardown).
    public func removeAll() {
        entries.removeAll()
        lruOrder.removeAll()
    }
    
    // MARK: - Private Helpers
    
    private func recordKey(_ key: PacketKey, now: Date) -> Bool {
        if let existing = entries[key] {
            if now.timeIntervalSince(existing.arrivalTime) < ttl {
                touchLRU(key, now: now)
                return true
            } else {
                removeEntry(key)
            }
        }
        
        if entries.count >= capacity {
            purgeExpiredEntries(currentTime: now)
        }
        
        while entries.count >= capacity, !lruOrder.isEmpty {
            let oldest = lruOrder.removeFirst()
            entries.removeValue(forKey: oldest)
        }
        
        let newEntry = CacheEntry(key: key, arrivalTime: now, lastAccessed: now)
        entries[key] = newEntry
        lruOrder.append(key)
        return false
    }
    
    private func touchLRU(_ key: PacketKey, now: Date) {
        if var entry = entries[key] {
            entry.lastAccessed = now
            entries[key] = entry
        }
        if let idx = lruOrder.firstIndex(of: key) {
            lruOrder.remove(at: idx)
            lruOrder.append(key)
        }
    }
    
    private func removeEntry(_ key: PacketKey) {
        entries.removeValue(forKey: key)
        if let idx = lruOrder.firstIndex(of: key) {
            lruOrder.remove(at: idx)
        }
    }
    
    private func purgeExpiredEntries(currentTime: Date) {
        let cutoff = currentTime.addingTimeInterval(-ttl)
        var toRemove: Set<PacketKey> = []
        for (key, entry) in entries {
            if entry.arrivalTime < cutoff {
                toRemove.insert(key)
            }
        }
        for key in toRemove {
            removeEntry(key)
        }
    }
}
