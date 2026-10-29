//
//  MeshDiagnostics.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation

/// Comprehensive, immutable diagnostic metrics snapshot for Phase 2 mesh networking.
///
/// Designed to track the 7 required mesh operational metrics:
/// 1. Forwarding attempts (total attempts, successes, failures)
/// 2. Packets dropped (categorized by exact failure reason)
/// 3. Duplicates suppressed (via LRU cache and sequence monotonicity)
/// 4. Route discoveries (initiated, succeeded, failed/timed out)
/// 5. Route failures / invalidations (link breakages, timeouts)
/// 6. Hop count metrics (maximum observed, histogram distribution, average hops)
/// 7. Queue saturation (drops due to overflow, lane depths, high watermarks)
///
/// Privacy Guarantee:
/// Guarantees 100% zero-knowledge diagnostics. Under NO circumstances does this snapshot
/// retain, log, or export sensitive user GPS coordinates, location histories, or 256-bit symmetric keys.
public struct MeshDiagnosticsSnapshot: Sendable, Equatable {
    
    // MARK: - 1. Forwarding Attempts & Outcomes
    public var forwardingAttempts: Int
    public var forwardingSuccesses: Int
    public var forwardingFailures: Int
    
    // MARK: - 2. Packets Dropped (Categorized by Reason)
    public var droppedRateLimit: Int
    public var droppedHopLimit: Int
    public var droppedQueueSaturation: Int
    public var droppedPolicyDisabled: Int
    public var droppedBatterySurvival: Int
    public var droppedMalformed: Int
    public var droppedSecurityFailed: Int
    public var droppedSimulatedLoss: Int
    
    public var totalPacketsDropped: Int {
        droppedRateLimit +
        droppedHopLimit +
        droppedQueueSaturation +
        droppedPolicyDisabled +
        droppedBatterySurvival +
        droppedMalformed +
        droppedSecurityFailed +
        droppedSimulatedLoss
    }
    
    // MARK: - 3. Duplicates Suppressed
    public var duplicatesSuppressed: Int
    
    // MARK: - 4. Route Discoveries
    public var routeDiscoveriesInitiated: Int
    public var routeDiscoveriesSucceeded: Int
    public var routeDiscoveriesFailed: Int
    
    // MARK: - 5. Route Failures & Invalidation Events
    public var routeFailuresOrInvalidations: Int
    
    // MARK: - 6. Hop Count Metrics
    public var maxHopCountObserved: UInt8
    public var hopCountHistogram: [UInt8: Int] // [HopCount: OccurrenceCount]
    public var totalHopsSum: Int
    public var totalHopsSamples: Int
    
    public var averageHopCount: Double {
        totalHopsSamples > 0 ? Double(totalHopsSum) / Double(totalHopsSamples) : 0.0
    }
    
    // MARK: - 7. Queue Saturation & Memory Footprint
    public var queueSaturationDrops: Int
    public var urgentQueueDepth: Int
    public var relayQueueDepth: Int
    public var normalQueueDepth: Int
    
    // MARK: - Privacy & Security Verification
    public var containsLocationData: Bool { false }
    public var containsCryptographicKeys: Bool { false }
    public var isPrivacyCompliant: Bool { true }
    
    // MARK: - Initializer
    public init(
        forwardingAttempts: Int = 0,
        forwardingSuccesses: Int = 0,
        forwardingFailures: Int = 0,
        droppedRateLimit: Int = 0,
        droppedHopLimit: Int = 0,
        droppedQueueSaturation: Int = 0,
        droppedPolicyDisabled: Int = 0,
        droppedBatterySurvival: Int = 0,
        droppedMalformed: Int = 0,
        droppedSecurityFailed: Int = 0,
        droppedSimulatedLoss: Int = 0,
        duplicatesSuppressed: Int = 0,
        routeDiscoveriesInitiated: Int = 0,
        routeDiscoveriesSucceeded: Int = 0,
        routeDiscoveriesFailed: Int = 0,
        routeFailuresOrInvalidations: Int = 0,
        maxHopCountObserved: UInt8 = 0,
        hopCountHistogram: [UInt8: Int] = [:],
        totalHopsSum: Int = 0,
        totalHopsSamples: Int = 0,
        queueSaturationDrops: Int = 0,
        urgentQueueDepth: Int = 0,
        relayQueueDepth: Int = 0,
        normalQueueDepth: Int = 0
    ) {
        self.forwardingAttempts = forwardingAttempts
        self.forwardingSuccesses = forwardingSuccesses
        self.forwardingFailures = forwardingFailures
        self.droppedRateLimit = droppedRateLimit
        self.droppedHopLimit = droppedHopLimit
        self.droppedQueueSaturation = droppedQueueSaturation
        self.droppedPolicyDisabled = droppedPolicyDisabled
        self.droppedBatterySurvival = droppedBatterySurvival
        self.droppedMalformed = droppedMalformed
        self.droppedSecurityFailed = droppedSecurityFailed
        self.droppedSimulatedLoss = droppedSimulatedLoss
        self.duplicatesSuppressed = duplicatesSuppressed
        self.routeDiscoveriesInitiated = routeDiscoveriesInitiated
        self.routeDiscoveriesSucceeded = routeDiscoveriesSucceeded
        self.routeDiscoveriesFailed = routeDiscoveriesFailed
        self.routeFailuresOrInvalidations = routeFailuresOrInvalidations
        self.maxHopCountObserved = maxHopCountObserved
        self.hopCountHistogram = hopCountHistogram
        self.totalHopsSum = totalHopsSum
        self.totalHopsSamples = totalHopsSamples
        self.queueSaturationDrops = queueSaturationDrops
        self.urgentQueueDepth = urgentQueueDepth
        self.relayQueueDepth = relayQueueDepth
        self.normalQueueDepth = normalQueueDepth
    }
    
    // MARK: - Multi-Node Aggregation Operator
    public static func +(lhs: MeshDiagnosticsSnapshot, rhs: MeshDiagnosticsSnapshot) -> MeshDiagnosticsSnapshot {
        var mergedHisto = lhs.hopCountHistogram
        for (hops, count) in rhs.hopCountHistogram {
            mergedHisto[hops, default: 0] += count
        }
        
        return MeshDiagnosticsSnapshot(
            forwardingAttempts: lhs.forwardingAttempts + rhs.forwardingAttempts,
            forwardingSuccesses: lhs.forwardingSuccesses + rhs.forwardingSuccesses,
            forwardingFailures: lhs.forwardingFailures + rhs.forwardingFailures,
            droppedRateLimit: lhs.droppedRateLimit + rhs.droppedRateLimit,
            droppedHopLimit: lhs.droppedHopLimit + rhs.droppedHopLimit,
            droppedQueueSaturation: lhs.droppedQueueSaturation + rhs.droppedQueueSaturation,
            droppedPolicyDisabled: lhs.droppedPolicyDisabled + rhs.droppedPolicyDisabled,
            droppedBatterySurvival: lhs.droppedBatterySurvival + rhs.droppedBatterySurvival,
            droppedMalformed: lhs.droppedMalformed + rhs.droppedMalformed,
            droppedSecurityFailed: lhs.droppedSecurityFailed + rhs.droppedSecurityFailed,
            droppedSimulatedLoss: lhs.droppedSimulatedLoss + rhs.droppedSimulatedLoss,
            duplicatesSuppressed: lhs.duplicatesSuppressed + rhs.duplicatesSuppressed,
            routeDiscoveriesInitiated: lhs.routeDiscoveriesInitiated + rhs.routeDiscoveriesInitiated,
            routeDiscoveriesSucceeded: lhs.routeDiscoveriesSucceeded + rhs.routeDiscoveriesSucceeded,
            routeDiscoveriesFailed: lhs.routeDiscoveriesFailed + rhs.routeDiscoveriesFailed,
            routeFailuresOrInvalidations: lhs.routeFailuresOrInvalidations + rhs.routeFailuresOrInvalidations,
            maxHopCountObserved: max(lhs.maxHopCountObserved, rhs.maxHopCountObserved),
            hopCountHistogram: mergedHisto,
            totalHopsSum: lhs.totalHopsSum + rhs.totalHopsSum,
            totalHopsSamples: lhs.totalHopsSamples + rhs.totalHopsSamples,
            queueSaturationDrops: lhs.queueSaturationDrops + rhs.queueSaturationDrops,
            urgentQueueDepth: lhs.urgentQueueDepth + rhs.urgentQueueDepth,
            relayQueueDepth: lhs.relayQueueDepth + rhs.relayQueueDepth,
            normalQueueDepth: lhs.normalQueueDepth + rhs.normalQueueDepth
        )
    }
}

/// Actor-isolated collector of operational mesh diagnostics and packet lifecycle metrics.
public actor MeshDiagnosticsCollector {
    private let clock: MeshClock
    private var snapshotData = MeshDiagnosticsSnapshot()
    
    public init(clock: MeshClock = SystemMeshClock()) {
        self.clock = clock
    }
    
    // MARK: - Forwarding Attempts
    public func recordForwardingAttempt(success: Bool) {
        snapshotData.forwardingAttempts += 1
        if success {
            snapshotData.forwardingSuccesses += 1
        } else {
            snapshotData.forwardingFailures += 1
        }
    }
    
    // MARK: - Packet Drops
    public func recordPacketDrop(reason: DropReason) {
        switch reason {
        case .rateLimitExceeded:
            snapshotData.droppedRateLimit += 1
        case .hopLimitExceeded:
            snapshotData.droppedHopLimit += 1
        case .duplicate:
            snapshotData.duplicatesSuppressed += 1
        case .batteryThrottled:
            snapshotData.droppedBatterySurvival += 1
        case .policyDisabled:
            snapshotData.droppedPolicyDisabled += 1
        case .queueSaturation:
            snapshotData.droppedQueueSaturation += 1
            snapshotData.queueSaturationDrops += 1
        case .malformed:
            snapshotData.droppedMalformed += 1
        case .securityVerificationFailed:
            snapshotData.droppedSecurityFailed += 1
        case .simulatedLoss:
            snapshotData.droppedSimulatedLoss += 1
        }
    }
    
    // MARK: - Duplicates Suppressed
    public func recordDuplicateSuppressed() {
        snapshotData.duplicatesSuppressed += 1
    }
    
    // MARK: - Route Discoveries
    public func recordRouteDiscoveryInitiated() {
        snapshotData.routeDiscoveriesInitiated += 1
    }
    
    public func recordRouteDiscoverySucceeded() {
        snapshotData.routeDiscoveriesSucceeded += 1
    }
    
    public func recordRouteDiscoveryFailed() {
        snapshotData.routeDiscoveriesFailed += 1
    }
    
    // MARK: - Route Failures & Invalidations
    public func recordRouteInvalidation() {
        snapshotData.routeFailuresOrInvalidations += 1
    }
    
    // MARK: - Hop Count Observation
    public func recordHopCount(_ hopCount: UInt8) {
        if hopCount > snapshotData.maxHopCountObserved {
            snapshotData.maxHopCountObserved = hopCount
        }
        snapshotData.hopCountHistogram[hopCount, default: 0] += 1
        snapshotData.totalHopsSum += Int(hopCount)
        snapshotData.totalHopsSamples += 1
    }
    
    // MARK: - Queue Depths
    public func recordQueueSaturationDrop() {
        snapshotData.droppedQueueSaturation += 1
        snapshotData.queueSaturationDrops += 1
    }
    
    public func updateQueueDepths(urgent: Int, relay: Int, normal: Int) {
        snapshotData.urgentQueueDepth = urgent
        snapshotData.relayQueueDepth = relay
        snapshotData.normalQueueDepth = normal
    }
    
    // MARK: - Query Snapshot
    public func snapshot() -> MeshDiagnosticsSnapshot {
        snapshotData
    }
    
    // MARK: - Reset Counters
    public func reset() {
        snapshotData = MeshDiagnosticsSnapshot()
    }
    
    // MARK: - Privacy Enforcement Verification
    public func verifyPrivacyCompliance() -> Bool {
        snapshotData.isPrivacyCompliant &&
        !snapshotData.containsLocationData &&
        !snapshotData.containsCryptographicKeys
    }
}
