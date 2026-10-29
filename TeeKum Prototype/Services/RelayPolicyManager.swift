//
//  RelayPolicyManager.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import Foundation

/// Actor-isolated communal relay participation and battery policy manager.
///
/// Implements Subsystem 4 (`RelayPolicyManaging`) and Subsystem 6 (`RelayDiagnosticsProviding`):
/// - Enforces explicit user opt-in for stranger relaying.
/// - Persists user preference via `UserDefaults` with support for timed 30-minute sessions.
/// - Enforces Festival Survival Mode (<20% battery or Low Power Mode) with immediate shutdown of stranger forwarding.
/// - Drains and purges queued stranger packets promptly upon relay termination.
/// - Integrates with `MeshTransport` and `PriorityOutboxQueue` to enforce resource budgets at the service layer.
/// - Tracks strictly aggregated resource telemetry with ZERO sensitive location coordinates or tracking history.
/// - Fully testable via injected `MeshClock`.
public actor RelayPolicyManager: RelayPolicyManaging, RelayDiagnosticsProviding {
    
    // MARK: - Dependencies
    
    private let clock: MeshClock
    private let userDefaults: UserDefaults
    private let storageKeyPrefix: String
    private weak var transport: MeshTransport?
    private let outbox: PriorityOutboxQueue?
    
    // MARK: - State Properties
    
    private var mode: RelayParticipationMode
    private var timedExpiryDate: Date?
    private var batteryLevel: Float
    private var isLowPowerModeActive: Bool
    
    // MARK: - Telemetry Counters (Anonymous, zero location retention)
    
    private var totalPacketsForwarded: Int = 0
    private var totalSOSForwarded: Int = 0
    private var packetsDroppedRateLimit: Int = 0
    private var packetsDroppedHopLimit: Int = 0
    private var duplicatePacketsSuppressed: Int = 0
    private var packetsDroppedPolicy: Int = 0
    private var packetsDroppedBattery: Int = 0
    private var packetsDroppedQueueSaturation: Int = 0
    private var packetsDroppedMalformed: Int = 0
    private var packetsDroppedSecurity: Int = 0
    private var packetsDroppedSimulatedLoss: Int = 0
    
    // MARK: - Reactive State Stream
    
    private var stateContinuation: AsyncStream<RelayPolicyState>.Continuation?
    public nonisolated let stateUpdates: AsyncStream<RelayPolicyState>
    
    // MARK: - Storage Keys
    
    private var modeStorageKey: String { "\(storageKeyPrefix).participationMode" }
    private var expiryStorageKey: String { "\(storageKeyPrefix).timedExpiryDate" }
    
    // MARK: - Initialization
    
    public init(
        clock: MeshClock = SystemMeshClock(),
        userDefaults: UserDefaults = .standard,
        storageKeyPrefix: String = "com.teekum.relay",
        transport: MeshTransport? = nil,
        outbox: PriorityOutboxQueue? = nil,
        initialBatteryLevel: Float = 1.0,
        initialLowPowerMode: Bool = false,
        defaultMode: RelayParticipationMode? = nil
    ) {
        self.clock = clock
        self.userDefaults = userDefaults
        self.storageKeyPrefix = storageKeyPrefix
        self.transport = transport
        self.outbox = outbox
        self.batteryLevel = initialBatteryLevel
        self.isLowPowerModeActive = initialLowPowerMode
        
        var continuation: AsyncStream<RelayPolicyState>.Continuation?
        self.stateUpdates = AsyncStream { continuation = $0 }
        self.stateContinuation = continuation
        
        // Restore persisted mode or use provided default / fallback to disabled
        if let defaultMode = defaultMode {
            self.mode = defaultMode
            self.timedExpiryDate = nil
        } else if let savedRaw = userDefaults.string(forKey: "\(storageKeyPrefix).participationMode"),
                  let savedMode = RelayParticipationMode(rawValue: savedRaw) {
            self.mode = savedMode
            if savedMode == .timed30Minutes {
                let expiryEpoch = userDefaults.double(forKey: "\(storageKeyPrefix).timedExpiryDate")
                if expiryEpoch > 0 {
                    let expiry = Date(timeIntervalSince1970: expiryEpoch)
                    if clock.now() < expiry {
                        self.timedExpiryDate = expiry
                    } else {
                        // Already expired while app was closed -> pause relaying
                        self.timedExpiryDate = expiry
                    }
                } else {
                    self.timedExpiryDate = nil
                }
            } else {
                self.timedExpiryDate = nil
            }
        } else {
            // Default at first launch: disabled until user explicitly opts in / accepts compact
            self.mode = .disabled
            self.timedExpiryDate = nil
        }
    }
    
    // MARK: - Subsystem 4: Policy Management
    
    /// Returns the current effective relay policy state.
    public func currentState() -> RelayPolicyState {
        RelayPolicyState(
            mode: mode,
            batteryLevel: batteryLevel,
            isLowPowerModeActive: isLowPowerModeActive,
            timedExpiryDate: timedExpiryDate
        )
    }
    
    /// Updates the user's chosen participation mode and persists to disk.
    public func setParticipationMode(_ newMode: RelayParticipationMode) async {
        let now = clock.now()
        self.mode = newMode
        
        switch newMode {
        case .communalRelayActive:
            self.timedExpiryDate = nil
            userDefaults.removeObject(forKey: expiryStorageKey)
            
            // Check if battery permits
            if batteryLevel >= 0.20 && !isLowPowerModeActive {
                await transport?.setRelayParticipation(enabled: true)
            } else {
                await transport?.setRelayParticipation(enabled: false)
                outbox?.clearRelayQueue()
            }
            
        case .timed30Minutes:
            let expiry = now.addingTimeInterval(1800) // 30 minutes
            self.timedExpiryDate = expiry
            userDefaults.set(expiry.timeIntervalSince1970, forKey: expiryStorageKey)
            
            if batteryLevel >= 0.20 && !isLowPowerModeActive {
                await transport?.setRelayParticipation(enabled: true)
            } else {
                await transport?.setRelayParticipation(enabled: false)
                outbox?.clearRelayQueue()
            }
            
        case .disabled:
            self.timedExpiryDate = nil
            userDefaults.removeObject(forKey: expiryStorageKey)
            
            // Stop relaying immediately and drain queue
            await stopRelayingInternal()
        }
        
        userDefaults.set(newMode.rawValue, forKey: modeStorageKey)
        emitStateUpdate()
    }
    
    /// Sets a timed relay session for an explicit duration (seconds).
    public func setTimedParticipation(durationSeconds: TimeInterval = 1800) async {
        let now = clock.now()
        self.mode = .timed30Minutes
        let expiry = now.addingTimeInterval(durationSeconds)
        self.timedExpiryDate = expiry
        
        userDefaults.set(RelayParticipationMode.timed30Minutes.rawValue, forKey: modeStorageKey)
        userDefaults.set(expiry.timeIntervalSince1970, forKey: expiryStorageKey)
        
        if batteryLevel >= 0.20 && !isLowPowerModeActive && durationSeconds > 0 {
            await transport?.setRelayParticipation(enabled: true)
        } else {
            await transport?.setRelayParticipation(enabled: false)
            outbox?.clearRelayQueue()
        }
        
        emitStateUpdate()
    }
    
    /// Promptly halts stranger relaying, sets mode to disabled, and purges all queued relay packets.
    public func stopRelaying() async {
        self.mode = .disabled
        self.timedExpiryDate = nil
        userDefaults.set(RelayParticipationMode.disabled.rawValue, forKey: modeStorageKey)
        userDefaults.removeObject(forKey: expiryStorageKey)
        
        await stopRelayingInternal()
        emitStateUpdate()
    }
    
    private func stopRelayingInternal() async {
        // 1. Clear outbox relay queue ring buffer
        outbox?.clearRelayQueue()
        
        // 2. Notify radio transport to drop relay forwarding
        await transport?.setRelayParticipation(enabled: false)
    }
    
    /// Updates hardware power metrics from UIDevice / ProcessInfo.
    public func updatePowerMetrics(batteryLevel: Float, isLowPowerMode: Bool) async {
        let clamped = min(1.0, max(0.0, batteryLevel))
        self.batteryLevel = clamped
        self.isLowPowerModeActive = isLowPowerMode
        
        let now = clock.now()
        let isPermitted = currentState().isPermitted(at: now)
        
        if !isPermitted {
            // Hard cutoff: purge queued stranger packets and disable transport relay
            outbox?.clearRelayQueue()
            await transport?.setRelayParticipation(enabled: false)
        } else if mode != .disabled {
            // Restore relaying if battery recovered above threshold and not expired
            await transport?.setRelayParticipation(enabled: true)
        }
        
        emitStateUpdate()
    }
    
    /// Evaluates whether forwarding a packet of the given type is currently permitted.
    public func canRelay(packetType: PacketType) async -> Bool {
        let now = clock.now()
        return currentState().isPermitted(at: now)
    }
    
    // MARK: - Subsystem 6: Relay Diagnostics & Resource Telemetry
    
    /// Records a successful packet forwarding event.
    public func recordForwardEvent(type: PacketType) {
        totalPacketsForwarded += 1
        if type == .sos {
            totalSOSForwarded += 1
        }
    }
    
    /// Records a dropped packet event with specific reason.
    public func recordDropEvent(reason: DropReason) {
        switch reason {
        case .rateLimitExceeded:
            packetsDroppedRateLimit += 1
        case .hopLimitExceeded:
            packetsDroppedHopLimit += 1
        case .duplicate:
            duplicatePacketsSuppressed += 1
        case .batteryThrottled:
            packetsDroppedBattery += 1
            packetsDroppedPolicy += 1
        case .policyDisabled:
            packetsDroppedPolicy += 1
        case .queueSaturation:
            packetsDroppedQueueSaturation += 1
        case .malformed:
            packetsDroppedMalformed += 1
        case .securityVerificationFailed:
            packetsDroppedSecurity += 1
        case .simulatedLoss:
            packetsDroppedSimulatedLoss += 1
        }
    }
    
    /// Captures a live snapshot of relay telemetry (zero location retention).
    public func snapshot() async -> RelayTelemetry {
        let now = clock.now()
        let state = currentState()
        let isSurvival = (state.batteryLevel < 0.20) || state.isLowPowerModeActive
        let activeNeighbors = await transport?.activeNeighbors().count ?? 0
        
        return RelayTelemetry(
            totalPacketsForwarded: totalPacketsForwarded,
            totalSOSForwarded: totalSOSForwarded,
            packetsDroppedRateLimit: packetsDroppedRateLimit,
            packetsDroppedHopLimit: packetsDroppedHopLimit,
            duplicatePacketsSuppressed: duplicatePacketsSuppressed,
            packetsDroppedPolicy: packetsDroppedPolicy,
            packetsDroppedBattery: packetsDroppedBattery,
            activeRoutesCount: 0,
            activeNeighborsCount: activeNeighbors,
            currentForwardingRatePerSec: 0.0,
            isFestivalSurvivalActive: isSurvival
        )
    }
    
    /// Resets all diagnostic counters (for testing and session resets).
    public func resetCounters() {
        totalPacketsForwarded = 0
        totalSOSForwarded = 0
        packetsDroppedRateLimit = 0
        packetsDroppedHopLimit = 0
        duplicatePacketsSuppressed = 0
        packetsDroppedPolicy = 0
        packetsDroppedBattery = 0
        packetsDroppedQueueSaturation = 0
        packetsDroppedMalformed = 0
        packetsDroppedSecurity = 0
        packetsDroppedSimulatedLoss = 0
    }
    
    // MARK: - Private Helpers
    
    private func emitStateUpdate() {
        let state = currentState()
        stateContinuation?.yield(state)
    }
}
