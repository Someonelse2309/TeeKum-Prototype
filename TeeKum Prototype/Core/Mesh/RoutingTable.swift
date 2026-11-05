//
//  RoutingTable.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation

/// Thread-safe Ad-hoc On-Demand Distance Vector (AODV) Routing & Reverse Path Engine.
///
/// Implements Subsystem 2 of Phase 2 Multi-Hop Mesh Architecture:
/// - Maintains active forward routes (`RouteEntry`) with 30s-60s TTL and sequence monotonicity.
/// - Maintains ephemeral reverse routes (`ReverseRouteEntry`) with 15s TTL for RREP and ACK return paths.
/// - Strictly bounds memory: 64 forward routes, 128 reverse routes (LRU / oldest-expiry eviction).
/// - Enforces hop limits: routes claiming hopCount > 8 are strictly rejected.
/// - Operates blindly for stranger relays: routes are indexed by destination ID or discovery sequence key.
/// - Uses injected `MeshClock` for 100% deterministic unit and multi-hop testing.
public actor RoutingTable: RoutingTableManaging {
    
    private let maxForwardRoutes: Int
    private let maxReverseRoutes: Int
    private let clock: MeshClock
    
    /// Map of destination member or session identifier -> forward route
    private var forwardRoutes: [String: RouteEntry] = [:]
    
    /// Map of discovery sequence or nonce key -> ephemeral reverse route
    private var reverseRoutes: [UInt32: ReverseRouteEntry] = [:]
    
    public init(
        maxForwardRoutes: Int = 64,
        maxReverseRoutes: Int = 128,
        clock: MeshClock = SystemMeshClock()
    ) {
        self.maxForwardRoutes = max(1, maxForwardRoutes)
        self.maxReverseRoutes = max(1, maxReverseRoutes)
        self.clock = clock
    }
    
    // MARK: - Key Generation Helper
    
    public static func routeKey(destinationId: String, sessionId: UInt32? = nil) -> String {
        if let sid = sessionId {
            return String(format: "%06X:%@", sid & 0x00FFFFFF, destinationId)
        }
        return destinationId
    }
    
    // MARK: - Forward Route Queries & Ingestion
    
    /// Looks up an active, unexpired route towards the given destination identifier,
    /// optionally scoped to a specific group session to prevent cross-group route leakage.
    public func findRoute(to destinationId: String, inSession sessionId: UInt32? = nil) async -> RouteEntry? {
        let key = RoutingTable.routeKey(destinationId: destinationId, sessionId: sessionId)
        let now = clock.now()
        
        if let entry = forwardRoutes[key] {
            if now >= entry.expiresAt {
                forwardRoutes.removeValue(forKey: key)
                return nil
            }
            return entry
        }
        
        // Fallback: if sessionId was specified but no session-scoped route was recorded,
        // check if a raw unscoped route exists (backward compatibility).
        if sessionId != nil, let entry = forwardRoutes[destinationId] {
            if now >= entry.expiresAt {
                forwardRoutes.removeValue(forKey: destinationId)
                return nil
            }
            return entry
        }
        
        return nil
    }
    
    /// Looks up an active, unexpired route towards the given destination identifier.
    public func findRoute(to destinationId: String) async -> RouteEntry? {
        await findRoute(to: destinationId, inSession: nil)
    }
    
    /// Inserts or updates a forward route entry, enforcing AODV sequence number monotonicity,
    /// cross-group scoping, and maximum hop limit bounds (capped at 8 hops).
    public func recordForwardRoute(
        destinationId: String,
        nextHop: String,
        hopCount: UInt8,
        cost: UInt8,
        sequenceNumber: UInt32,
        ttl: TimeInterval,
        sessionId: UInt32? = nil
    ) async {
        // Security constraint: enforce maximum hop limit (8 hops)
        guard hopCount <= PacketConstants.defaultHopLimit else {
            return
        }
        
        let now = clock.now()
        let expiresAt = now.addingTimeInterval(max(1.0, ttl))
        let key = RoutingTable.routeKey(destinationId: destinationId, sessionId: sessionId)
        
        // AODV Route Selection Rule:
        // 1. Prefer higher destination sequence number (fresher route)
        // 2. If sequence numbers are equal, prefer lower cost or lower hop count
        if let existing = forwardRoutes[key], existing.expiresAt > now {
            if sequenceNumber < existing.sequenceNumber {
                // Reject stale sequence number
                return
            } else if sequenceNumber == existing.sequenceNumber {
                if cost >= existing.routeCost && hopCount >= existing.hopCount {
                    // Equal or worse path metric: reject
                    return
                }
            }
        }
        
        // Bounded capacity eviction
        if forwardRoutes.count >= maxForwardRoutes && forwardRoutes[key] == nil {
            evictEarliestExpiringForwardRoute(now: now)
        }
        
        let entry = RouteEntry(
            destinationId: destinationId,
            nextHopPeerId: nextHop,
            hopCount: hopCount,
            routeCost: cost,
            sequenceNumber: sequenceNumber,
            expiresAt: expiresAt,
            sessionId: sessionId
        )
        forwardRoutes[key] = entry
    }
    
    public func recordForwardRoute(
        destinationId: String,
        nextHop: String,
        hopCount: UInt8,
        cost: UInt8,
        sequenceNumber: UInt32,
        ttl: TimeInterval
    ) async {
        await recordForwardRoute(
            destinationId: destinationId,
            nextHop: nextHop,
            hopCount: hopCount,
            cost: cost,
            sequenceNumber: sequenceNumber,
            ttl: ttl,
            sessionId: nil
        )
    }
    
    // MARK: - Reverse Route Ingestion & Consumption
    
    /// Records a reverse route entry during RREQ traversal.
    /// If an entry already exists for discoveryKey, updates only if new hopCount is lower (shorter path).
    public func recordReverseRoute(
        discoveryKey: UInt32,
        incomingPeerId: String,
        hopCount: UInt8,
        ttl: TimeInterval
    ) async {
        guard hopCount <= PacketConstants.defaultHopLimit else {
            return
        }
        
        let now = clock.now()
        let expiresAt = now.addingTimeInterval(max(1.0, ttl))
        
        if let existing = reverseRoutes[discoveryKey], existing.expiresAt > now {
            if hopCount >= existing.hopCount {
                // Already recorded a shorter or equal reverse path
                return
            }
        }
        
        // Bounded capacity eviction
        if reverseRoutes.count >= maxReverseRoutes && reverseRoutes[discoveryKey] == nil {
            evictEarliestExpiringReverseRoute(now: now)
        }
        
        let entry = ReverseRouteEntry(
            discoveryKey: discoveryKey,
            incomingPeerId: incomingPeerId,
            hopCount: hopCount,
            expiresAt: expiresAt
        )
        reverseRoutes[discoveryKey] = entry
    }
    
    /// Retrieves and consumes a reverse route for RREP / ACK forwarding.
    /// Once popped, the ephemeral association is removed to prevent stale replay.
    public func popReverseRoute(for discoveryKey: UInt32) async -> ReverseRouteEntry? {
        guard let entry = reverseRoutes[discoveryKey] else { return nil }
        reverseRoutes.removeValue(forKey: discoveryKey)
        let now = clock.now()
        guard entry.expiresAt > now else {
            return nil
        }
        return entry
    }
    
    // MARK: - Invalidation & Maintenance
    
    /// Invalidates all routes towards destinationId, or using destinationId as a next hop.
    public func invalidateRoute(towards destinationId: String, inSession sessionId: UInt32? = nil) async {
        let key = RoutingTable.routeKey(destinationId: destinationId, sessionId: sessionId)
        forwardRoutes.removeValue(forKey: key)
        forwardRoutes.removeValue(forKey: destinationId)
        
        // Also invalidate any routes whose next-hop is the disconnected neighbor
        var keysToInvalidate: [String] = []
        for (k, route) in forwardRoutes {
            if route.nextHopPeerId == destinationId {
                keysToInvalidate.append(k)
            }
        }
        for k in keysToInvalidate {
            forwardRoutes.removeValue(forKey: k)
        }
    }
    
    public func invalidateRoute(towards destinationId: String) async {
        await invalidateRoute(towards: destinationId, inSession: nil)
    }
    
    /// Invalidates all routes whose next-hop is the disconnected neighbor.
    public func invalidateRoutesUsingNextHop(_ nextHopPeerId: String) async {
        var keysToInvalidate: [String] = []
        for (key, route) in forwardRoutes {
            if route.nextHopPeerId == nextHopPeerId {
                keysToInvalidate.append(key)
            }
        }
        for key in keysToInvalidate {
            forwardRoutes.removeValue(forKey: key)
        }
    }
    
    /// Invalidates all forward routes belonging to a specific group session (e.g. on teardown or leave).
    public func invalidateRoutes(forSessionId sessionId: UInt32) async {
        let prefix = String(format: "%06X:", sessionId & 0x00FFFFFF)
        forwardRoutes = forwardRoutes.filter { key, route in
            if route.sessionId == sessionId { return false }
            if key.hasPrefix(prefix) { return false }
            return true
        }
    }
    
    /// Evicts expired route records from both forward and reverse tables.
    public func purgeExpiredRoutes() async {
        let now = clock.now()
        forwardRoutes = forwardRoutes.filter { $0.value.expiresAt > now }
        reverseRoutes = reverseRoutes.filter { $0.value.expiresAt > now }
    }
    
    // MARK: - Observability & Telemetry Queries
    
    /// Returns a snapshot of all active, unexpired forward routes.
    public func allForwardRoutes() async -> [RouteEntry] {
        let now = clock.now()
        return forwardRoutes.values.filter { $0.expiresAt > now }
    }
    
    /// Returns a snapshot of all active, unexpired reverse routes.
    public func allReverseRoutes() async -> [ReverseRouteEntry] {
        let now = clock.now()
        return reverseRoutes.values.filter { $0.expiresAt > now }
    }
    
    /// Current count of active forward routes.
    public var activeForwardRoutesCount: Int {
        let now = clock.now()
        return forwardRoutes.values.filter { $0.expiresAt > now }.count
    }
    
    /// Current count of active reverse routes.
    public var activeReverseRoutesCount: Int {
        let now = clock.now()
        return reverseRoutes.values.filter { $0.expiresAt > now }.count
    }
    
    /// Clears all routes for session reset.
    public func removeAll() async {
        forwardRoutes.removeAll()
        reverseRoutes.removeAll()
    }
    
    // MARK: - Private Eviction Helpers
    
    private func evictEarliestExpiringForwardRoute(now: Date) {
        // First purge expired
        forwardRoutes = forwardRoutes.filter { $0.value.expiresAt > now }
        if forwardRoutes.count < maxForwardRoutes { return }
        
        // If still full, evict earliest expiring entry
        if let earliestKey = forwardRoutes.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
            forwardRoutes.removeValue(forKey: earliestKey)
        }
    }
    
    private func evictEarliestExpiringReverseRoute(now: Date) {
        reverseRoutes = reverseRoutes.filter { $0.value.expiresAt > now }
        if reverseRoutes.count < maxReverseRoutes { return }
        
        if let earliestKey = reverseRoutes.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
            reverseRoutes.removeValue(forKey: earliestKey)
        }
    }
}
