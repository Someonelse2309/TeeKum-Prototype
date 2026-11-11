//
//  TeeKumConfiguration.swift
//  TeeKum Prototype
//
//  Created by Nicho on 04/11/26.
//

import Foundation

/// Centralized Master Configuration Repository for Google Antigravity / TeeKum Festival Mesh.
///
/// Every configurable knob, cadences, network thresholds, hop limits, battery cutoffs,
/// retry parameters, and UI timings are unified in this single file for rapid testing and field tuning.
nonisolated public enum TeeKumConfiguration {
    
    // MARK: - 1. Wire Protocol & Network Topology Parameters
    public enum Network {
        /// Strictly fixed 56-byte wire datagram format (invariant across all packet types).
        public static let wirePacketSize: Int = 56
        
        /// Size of cleartext envelope for routing inspection (10 bytes).
        public static let cleartextEnvelopeSize: Int = 10
        
        /// Size of encrypted ChaCha20 / Poly1305 payload (30 bytes).
        public static let encryptedPayloadSize: Int = 30
        
        /// Size of Poly1305 authentication tag (16 bytes).
        public static let authTagSize: Int = 16
        
        /// Size of cryptographic AEAD nonce (12 bytes).
        public static let nonceSize: Int = 12
        
        /// Protocol version (0x03 for Protocol Version 3).
        public static let protocolVersion: UInt8 = 0x03
        
        /// 4-byte domain separation tag used in AEAD nonce construction: 'T', 'K', 'M', '3'.
        public static let protocolDomainTag: [UInt8] = [0x54, 0x4B, 0x4D, 0x33]
        
        /// Hard architectural maximum allowable hop limit across the entire mesh (1...15).
        public static var maxHopLimit: UInt8 = 15
        
        /// Hop limit for standard periodic Location Ping packets (Type 0x01) (default: 8).
        public static var defaultHopLimit: UInt8 = 8
        
        /// Dedicated hop limit budget for Chat Messages (Type 0x07) and Delivery ACKs (Type 0x06).
        /// Tuneable independently to control text propagation radius and conserve festival airtime (default: 8).
        public static var chatHopLimit: UInt8 = 8
        
        /// Strict 1-hop limit for Ultra-Wideband token exchange packets (default: 1).
        public static var uwbHopLimit: UInt8 = 1
        
        /// High-reach hop limit for Group Rendezvous / Meeting Point updates (Type 0x03) (default: 15).
        public static var meetingPointHopLimit: UInt8 = 15
        
        /// Maximum-priority hop limit for Emergency SOS siren alerts (Type 0x02) (default: 15).
        public static var sosHopLimit: UInt8 = 15
    }
    
    // MARK: - 2. Broadcast Cadence & Mesh Timing Parameters
    public enum Timing {
        /// Location publishing interval when actively moving with strong nearby peers (default: 4.0s).
        public static var locationMovingInterval: TimeInterval = 4.0
        
        /// Location publishing interval when stationary with nearby peers (default: 20.0s).
        public static var locationStationaryInterval: TimeInterval = 20.0
        
        /// Accelerated publishing interval when links degrade or peers become distant (default: 2.0s).
        public static var distantPeerInterval: TimeInterval = 2.0
        
        /// Throttled publishing interval in Festival Survival Mode (<20% battery) (default: 60.0s).
        public static var survivalInterval: TimeInterval = 60.0
        
        /// RSSI threshold (dBm) below which a link is deemed weak/distant (default: -75 dBm).
        public static var distantRSSIThreshold: Int8 = -75
        
        /// GPS distance threshold (meters) beyond which a peer is treated as distant (default: 30.0m).
        public static var distantDistanceThresholdMeters: Double = 30.0
        
        /// Elapsed seconds of inactivity before a member is marked Stale (default: 30.0s).
        public static var stalePeerThreshold: TimeInterval = 30.0
        
        /// Elapsed seconds of inactivity before a member is marked Offline (default: 180.0s).
        public static var offlinePeerThreshold: TimeInterval = 180.0
        
        /// Direct neighbor heartbeat cadence (default: 2.0s).
        public static var neighborHeartbeatInterval: TimeInterval = 2.0
        
        /// Timeout to prune dead direct neighbor connections (default: 6.0s).
        public static var neighborPruneThreshold: TimeInterval = 6.0
        
        /// AODV routing table entry validity time-to-live (default: 30.0s).
        public static var routingTableTTL: TimeInterval = 30.0
        
        /// Minimum interval between route requests (RREQ) to prevent mesh flooding (default: 10.0s).
        public static var rreqRateLimitInterval: TimeInterval = 10.0
        
        /// Timeout waiting for Route Response (RREP) before retrying (default: 1.5s).
        public static var rreqRetryTimeout: TimeInterval = 1.5
        
        /// Maximum route discovery retries (default: 2).
        public static var rreqMaxRetries: Int = 2
        
        /// Ordinary relay budget in packets/second, read when a ForwardingRateLimiter is created.
        public static var ordinaryRelayRateLimit: Double = 8.0
        
        /// Burst token bucket capacity for ordinary packet relaying (default: 4.0).
        public static var ordinaryRelayBurstCapacity: Double = 4.0
        
        /// Urgent SOS packet forwarding rate (packets/second, default: 4.0).
        public static var urgentSOSRateLimit: Double = 4.0
        
        /// Maximum entries preserved in the LRU duplicate suppression cache (default: 1024).
        public static var seenPacketCacheCapacity: Int = 1024
        
        /// Priority outbox queue buffer capacity (default: 64 packets).
        public static var outboxQueueCapacity: Int = 64
        
        /// Maximum retry attempts for outbox transmissions (default: 2 retries = 3 total attempts).
        public static var outboxMaxRetries: Int = 2
        
        /// Initial backoff delay for outbox retries (default: 0.25s).
        public static var outboxBackoffInitialDelay: TimeInterval = 0.25
        
        /// Multiplier for exponential backoff between retries (default: 2.0).
        public static var outboxBackoffMultiplier: Double = 2.0
    }
    
    // MARK: - 3. Chat Messaging Parameters
    public enum Chat {
        /// Fast link retries fit inside the chat delivery ACK window; later custody is slower.
        public static var carryFastRetryInterval: TimeInterval = 2.0
        public static var carryFastAttemptLimit: Int = 3
        public static var carrySlowRetryInterval: TimeInterval = 30.0

        /// Maximum chat messages held strictly in ephemeral RAM (purged on exit) (default: 50).
        public static var maxHistory: Int = 50
        
        /// Anti-spam client-side cooldown interval between outgoing messages (default: 3.0s).
        public static var cooldownDuration: TimeInterval = 3.0
        
        /// ACK confirmation timeout window before marking a recipient as timed out (default: 15.0s).
        public static var deliveryTimeout: TimeInterval = 15.0
        
        /// Maximum automated retries for unacknowledged messages (default: 2 retries = 3 attempts).
        public static var maxRetries: Int = 2
        
        /// Initial backoff delay for chat message retries (default: 0.5s).
        public static var backoffInitialDelay: TimeInterval = 0.5
        
        /// Multiplier for exponential backoff on unacknowledged chat retries (default: 1.5).
        public static var backoffMultiplier: Double = 1.5
        
        /// Maximum UTF-8 byte boundary for chat text (strictly 20 bytes).
        public static let maxPayloadBytes: Int = 20
    }
    
    // MARK: - 4. Emergency SOS Parameters
    public enum SOS {
        /// Continuous press-and-hold duration required to trigger emergency alarm (default: 3.0s).
        public static var holdDuration: TimeInterval = 3.0
        
        /// Inactivity stillness duration before triggering pre-alarm warning countdown (default: 180.0s = 3 minutes).
        public static var inactivityStillnessDuration: TimeInterval = 180.0
        
        /// Pre-alarm silent haptic warning countdown duration before broadcasting auto-SOS (default: 30.0s).
        public static var inactivityWarningCountdown: TimeInterval = 30.0
        
        /// Acceleration variance threshold (in g) above which device is considered in physical motion (default: 0.15g).
        public static var inactivityMotionThreshold: Double = 0.15
    }
    
    // MARK: - 5. Group Rendezvous / Meeting Point Parameters
    public enum Rendezvous {
        /// Proximity radius in meters for automatic arrival detection (default: 25.0m).
        public static var defaultArrivalRadiusMeters: Double = 25.0
        
        /// Duration past scheduled meetup time before rendezvous auto-clears (default: 3600.0s = 1 hour).
        public static var autoExpirationSeconds: TimeInterval = 3600.0
        
        /// 1-tap quick preset offsets in minutes.
        public static let presetMinutes: [Int] = [0, 15, 30, 60]
    }
    
    // MARK: - 6. Battery & Survival Mode Parameters
    public enum Battery {
        /// Battery percentage threshold triggering Festival Survival Mode (default: 20%).
        public static var survivalThresholdPercent: UInt8 = 20
        
        /// Default duration for Lock Screen Timed Relay mode (default: 1800s = 30 minutes).
        public static var timedRelayDefaultDuration: TimeInterval = 1800.0
    }
    
    // MARK: - 7. Tactical Radar & Directional Navigation Parameters
    public enum Navigation {
        /// Outer polar boundary radius rendered on Tactical Radar (default: 60.0m).
        public static var tacticalRadarRangeMeters: Double = 60.0
        
        /// Proximity threshold where Tactical Radar transitions to Ultra-Wideband (default: 6.0m).
        public static var uwbTransitionDistanceMeters: Double = 6.0
        
        /// Maximum physical range of Apple Ultra-Wideband U1/U2 chips (default: 8.0m).
        public static var uwbMaxRangingDistanceMeters: Double = 8.0
        
        /// Inactivity timeout before an idle UWB session is torn down to preserve battery (default: 30.0s).
        public static var uwbSessionTimeoutSeconds: Double = 30.0
        
        /// Field of view angle for attendee heading vision cones on map (default: 50.0 degrees).
        public static var visionConeFOV: Double = 50.0
    }
}
