//
//  MeshTimingConfiguration.swift
//  TeeKum Prototype
//
//  Created by Nicho on 02/11/26.
//

import Foundation

/// Centralized, easily adjustable timing, cadence, and retry configuration
/// for TeeKum multi-hop mesh networking and peer broadcasting.
///
/// Easily tune these variables in code to optimize broadcasting intervals,
/// link degradation thresholds, and distant relay retry policies.
nonisolated public struct MeshTimingConfiguration: Equatable, Sendable {
    
    // MARK: - 1. Broadcast Cadence Timings (Seconds)
    
    /// Publishing interval when one or more peers are distant or signal is weak (recommended: 2.0s).
    /// Speeds up broadcasting from 20s down to 2s to maintain relay responsiveness across distant links.
    public var distantPeerInterval: TimeInterval
    
    /// Publishing interval while user is actively moving with nearby peers (recommended: 4.0s).
    public var movingInterval: TimeInterval
    
    /// Publishing interval while stationary with strong nearby peers (recommended: 20.0s).
    public var stationaryInterval: TimeInterval
    
    /// Throttled publishing interval in survival mode (<20% battery) to conserve power (recommended: 60.0s).
    public var survivalInterval: TimeInterval
    
    // MARK: - 2. Distant Link & Weak Signal Thresholds
    
    /// RSSI threshold (dBm) below which a peer link is classified as distant or weak (recommended: -75 dBm).
    /// Links with RSSI <= this threshold trigger the `distantPeerInterval`.
    public var distantRSSIThreshold: Int8
    
    /// GPS distance threshold (meters) beyond which a peer is classified as distant (recommended: 30.0m).
    /// Peers farther than this distance trigger the `distantPeerInterval`.
    public var distantDistanceThresholdMeters: Double
    
    // MARK: - 3. Distant Link Retry & Priority Policies
    
    /// Maximum transmission retries for relay packets or packets sent over distant/degraded links (recommended: 2).
    public var distantLinkMaxRetries: Int
    
    /// Backoff delay (seconds) between successive retries over distant or lossy links (recommended: 0.5s).
    public var distantLinkRetryDelay: TimeInterval
    
    // MARK: - 4. Rate Limiter Budgets & Token Buckets
    
    /// Maximum ordinary relay forwarding rate (packets per second, recommended: 2.0).
    public var ordinaryRelayRateLimit: Double
    
    /// Burst capacity for ordinary relay token bucket (recommended: 4.0).
    public var ordinaryRelayBurstCapacity: Double
    
    /// Maximum urgent SOS forwarding rate (packets per second, recommended: 4.0).
    public var urgentSOSRateLimit: Double
    
    // MARK: - 5. Group Chat Engine Timings
    
    /// Enforced client-side cooldown between outgoing user chat messages (recommended: 3.0s).
    public var chatUserCooldown: TimeInterval
    
    /// Maximum radio transmission retries for chat messages (recommended: 2 retries, 3 total attempts).
    public var chatMaxRetries: Int
    
    /// Initial retry backoff delay for chat messages (recommended: 0.5s).
    public var chatRetryBackoff: TimeInterval
    
    /// Multi-peer delivery ACK confirmation timeout window (recommended: 15.0s).
    public var chatAckTimeout: TimeInterval
    
    /// Maximum randomized jitter delay before transmitting ACKs to avoid collisions (recommended: 0.35s).
    public var chatAckJitterMax: TimeInterval
    
    // MARK: - 5. Stale Peer Accelerated Cadence & Two-Tier Probe Timings
    
    /// Elapsed duration (seconds) since last contact after which a group member is classified as stale (recommended: 30.0s).
    /// Upon crossing this threshold, Stage 1 accelerated probing begins at `staleRecoveryInterval`.
    public var stalePeerThreshold: TimeInterval
    
    /// Accelerated publishing interval (seconds) while probing for stale peers (recommended: 2.0s).
    /// Drives high-cadence local pings across the mesh to refresh link state and wake sleeping relays.
    public var staleRecoveryInterval: TimeInterval
    
    /// Additional elapsed time (seconds) of continuous staleness before initiating Stage 2 on-demand AODV route discovery (recommended: 15.0s).
    /// Total elapsed time since last seen = `stalePeerThreshold + staleRouteReqDelay` (30s + 15s = 45s).
    public var staleRouteReqDelay: TimeInterval
    
    /// Maximum duration (seconds) to sustain accelerated probing for an unresponsive stale peer (recommended: 60.0s).
    /// If the peer remains missing beyond `stalePeerThreshold + staleRecoveryTimeout` (30s + 60s = 90s),
    /// the probe window expires and publishing cadence backs off to conserve battery.
    public var staleRecoveryTimeout: TimeInterval
    
    // MARK: - 6. One-to-Many Multi-Peer Staggering & Response Burst
    
    /// Spacing delay (seconds) between sequential AODV route requests when multiple group members are stale (recommended: 2.5s).
    /// Prevents radio flooding and adheres to the 2 pkts/sec token bucket rate limiter in one-to-many topologies.
    public var staleRouteReqStaggerInterval: TimeInterval
    
    /// Number of rapid location pings published by a stale peer upon receiving a ROUTE_REQ probe (recommended: 3).
    /// Ensures fresh coordinates punch through intermediate relays to reach all group members.
    public var staleResponseBurstCount: Int
    
    /// Cadence interval (seconds) between each ping in the stale response burst (recommended: 2.0s).
    public var staleResponseBurstInterval: TimeInterval
    
    // MARK: - Initialization & Shared Default
    
    public init(
        distantPeerInterval: TimeInterval = TeeKumConfiguration.Timing.distantPeerInterval,
        movingInterval: TimeInterval = TeeKumConfiguration.Timing.locationMovingInterval,
        stationaryInterval: TimeInterval = TeeKumConfiguration.Timing.locationStationaryInterval,
        survivalInterval: TimeInterval = TeeKumConfiguration.Timing.survivalInterval,
        distantRSSIThreshold: Int8 = TeeKumConfiguration.Timing.distantRSSIThreshold,
        distantDistanceThresholdMeters: Double = TeeKumConfiguration.Timing.distantDistanceThresholdMeters,
        distantLinkMaxRetries: Int = 2,
        distantLinkRetryDelay: TimeInterval = 0.5,
        ordinaryRelayRateLimit: Double = TeeKumConfiguration.Timing.ordinaryRelayRateLimit,
        ordinaryRelayBurstCapacity: Double = TeeKumConfiguration.Timing.ordinaryRelayBurstCapacity,
        urgentSOSRateLimit: Double = TeeKumConfiguration.Timing.urgentSOSRateLimit,
        chatUserCooldown: TimeInterval = TeeKumConfiguration.Chat.cooldownDuration,
        chatMaxRetries: Int = TeeKumConfiguration.Chat.maxRetries,
        chatRetryBackoff: TimeInterval = TeeKumConfiguration.Chat.backoffInitialDelay,
        chatAckTimeout: TimeInterval = TeeKumConfiguration.Chat.deliveryTimeout,
        chatAckJitterMax: TimeInterval = 0.35,
        stalePeerThreshold: TimeInterval = TeeKumConfiguration.Timing.stalePeerThreshold,
        staleRecoveryInterval: TimeInterval = 2.0,
        staleRouteReqDelay: TimeInterval = 15.0,
        staleRecoveryTimeout: TimeInterval = 60.0,
        staleRouteReqStaggerInterval: TimeInterval = 2.5,
        staleResponseBurstCount: Int = 3,
        staleResponseBurstInterval: TimeInterval = 2.0
    ) {
        self.distantPeerInterval = distantPeerInterval
        self.movingInterval = movingInterval
        self.stationaryInterval = stationaryInterval
        self.survivalInterval = survivalInterval
        self.distantRSSIThreshold = distantRSSIThreshold
        self.distantDistanceThresholdMeters = distantDistanceThresholdMeters
        self.distantLinkMaxRetries = distantLinkMaxRetries
        self.distantLinkRetryDelay = distantLinkRetryDelay
        self.ordinaryRelayRateLimit = ordinaryRelayRateLimit
        self.ordinaryRelayBurstCapacity = ordinaryRelayBurstCapacity
        self.urgentSOSRateLimit = urgentSOSRateLimit
        self.chatUserCooldown = chatUserCooldown
        self.chatMaxRetries = chatMaxRetries
        self.chatRetryBackoff = chatRetryBackoff
        self.chatAckTimeout = chatAckTimeout
        self.chatAckJitterMax = chatAckJitterMax
        self.stalePeerThreshold = stalePeerThreshold
        self.staleRecoveryInterval = staleRecoveryInterval
        self.staleRouteReqDelay = staleRouteReqDelay
        self.staleRecoveryTimeout = staleRecoveryTimeout
        self.staleRouteReqStaggerInterval = staleRouteReqStaggerInterval
        self.staleResponseBurstCount = staleResponseBurstCount
        self.staleResponseBurstInterval = staleResponseBurstInterval
    }
    
    /// Global shared timing configuration. Modify this instance to tune network timing app-wide.
    public static var `default` = MeshTimingConfiguration()
}
