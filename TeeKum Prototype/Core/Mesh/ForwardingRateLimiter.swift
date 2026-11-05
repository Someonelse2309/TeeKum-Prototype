//
//  ForwardingRateLimiter.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation

/// Token bucket forwarding rate limiter enforcing Decision 7 limits:
/// - Ordinary relay traffic: 2 packets / sec (capacity 4 tokens, refill 2.0/s)
/// - Urgent SOS priority traffic: max 4 packets / sec (capacity 8 tokens, refill 4.0/s)
///
/// Supports an injected `MeshClock` for deterministic automated unit testing.
public actor ForwardingRateLimiter: ForwardingBudgetManaging {
    private let clock: MeshClock
    
    // Ordinary traffic token bucket
    private let ordinaryCapacity: Double
    private let ordinaryRefillRate: Double // tokens per second
    private var ordinaryTokens: Double
    private var lastOrdinaryRefill: Date
    
    // SOS priority token bucket
    private let sosCapacity: Double
    private let sosRefillRate: Double // tokens per second
    private var sosTokens: Double
    private var lastSOSRefill: Date
    
    public init(
        clock: MeshClock = SystemMeshClock(),
        ordinaryCapacity: Double = 4.0,
        ordinaryRefillRate: Double = 2.0,
        sosCapacity: Double = 8.0,
        sosRefillRate: Double = 4.0
    ) {
        self.clock = clock
        self.ordinaryCapacity = ordinaryCapacity
        self.ordinaryRefillRate = ordinaryRefillRate
        self.sosCapacity = sosCapacity
        self.sosRefillRate = sosRefillRate
        
        let now = clock.now()
        self.ordinaryTokens = ordinaryCapacity
        self.lastOrdinaryRefill = now
        self.sosTokens = sosCapacity
        self.lastSOSRefill = now
    }
    
    /// Refills ordinary token bucket based on elapsed time.
    private func refillOrdinary(now: Date) {
        let elapsed = max(0.0, now.timeIntervalSince(lastOrdinaryRefill))
        if elapsed > 0 {
            let refilled = elapsed * ordinaryRefillRate
            ordinaryTokens = min(ordinaryCapacity, ordinaryTokens + refilled)
            lastOrdinaryRefill = now
        }
    }
    
    /// Refills SOS token bucket based on elapsed time.
    private func refillSOS(now: Date) {
        let elapsed = max(0.0, now.timeIntervalSince(lastSOSRefill))
        if elapsed > 0 {
            let refilled = elapsed * sosRefillRate
            sosTokens = min(sosCapacity, sosTokens + refilled)
            lastSOSRefill = now
        }
    }
    
    /// Attempts to consume 1 token for forwarding ordinary relay traffic.
    /// Returns true if permitted, false if rate limit exceeded.
    public func consumeOrdinaryToken() async -> Bool {
        let now = clock.now()
        refillOrdinary(now: now)
        
        if ordinaryTokens >= 1.0 {
            ordinaryTokens -= 1.0
            return true
        } else {
            return false
        }
    }
    
    /// Attempts to consume 1 token for forwarding urgent SOS priority traffic.
    /// Returns true if permitted, false if SOS limit exceeded.
    public func consumeSOSToken() async -> Bool {
        let now = clock.now()
        refillSOS(now: now)
        
        if sosTokens >= 1.0 {
            sosTokens -= 1.0
            return true
        } else {
            return false
        }
    }
    
    /// Current available ordinary token reserve.
    public func availableTokens() async -> Double {
        let now = clock.now()
        refillOrdinary(now: now)
        return ordinaryTokens
    }
    
    /// Current available SOS token reserve.
    public func availableSOSTokens() async -> Double {
        let now = clock.now()
        refillSOS(now: now)
        return sosTokens
    }
    
    /// Manually resets token reserves to full capacity.
    public func reset() {
        let now = clock.now()
        ordinaryTokens = ordinaryCapacity
        lastOrdinaryRefill = now
        sosTokens = sosCapacity
        lastSOSRefill = now
    }
}
