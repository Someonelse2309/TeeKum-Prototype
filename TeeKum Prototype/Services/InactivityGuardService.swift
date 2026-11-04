//
//  InactivityGuardService.swift
//  TeeKum Prototype
//
//  Created by Nicho on 04/11/26.
//

import Foundation
import CoreMotion
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Operational state of the Inactivity Guard subsystem.
public enum InactivityGuardState: Equatable, Sendable {
    /// Guard is turned off by the user (opt-in default).
    case disabled
    /// Actively monitoring accelerometer motion & screen interaction.
    case monitoring(stillSince: Date)
    /// In the 30-second pre-alarm silent warning countdown before auto-SOS dispatch.
    case warning(remainingSeconds: Double)
    /// Warning countdown completed; automatic SOS has been dispatched.
    case triggered
}

/// Service governing the Inactivity Guard ("Man Down" Auto-SOS) feature.
///
/// Principles:
/// 1. Opt-In Protection: Disabled by default to prevent false alarms while resting or watching concerts.
/// 2. Hybrid Sensor Detection: Tracks accelerometer stillness (|magnitude - 1.0g| < threshold)
///    AND zero screen touch/unlock interactions.
/// 3. Pre-Alarm Warning: 30-second silent haptic & visual warning countdown (NO audible sirens).
/// 4. Effortless Cancellation: Picking up/moving the phone OR tapping "I'm OK" immediately cancels countdown.
/// 5. Auto-SOS Dispatch: Triggers emergency SOS with `SOSType.inactivity` upon countdown expiration.
@Observable
@MainActor
public final class InactivityGuardService {
    
    // MARK: - State Properties
    
    /// User master toggle for Inactivity Guard. Defaults to false (opt-in).
    public var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    
    /// Current operational state of the inactivity guard.
    public private(set) var state: InactivityGuardState = .disabled
    
    /// Seconds remaining in the pre-alarm warning countdown.
    public private(set) var countdownRemaining: Double = 0.0
    
    /// Timestamp when motion or screen interaction was last registered.
    public private(set) var lastActivityTimestamp: Date
    
    /// Callback invoked when the pre-alarm countdown expires and auto-SOS must be dispatched.
    public var onTriggerSOS: (@MainActor () -> Void)?
    
    /// Callback invoked when warning countdown starts (for local haptic feedback).
    public var onWarningStarted: (@MainActor () -> Void)?
    
    /// Callback invoked periodically during warning countdown (for haptic pulse).
    public var onWarningTick: (@MainActor (Double) -> Void)?
    
    /// Callback invoked when warning countdown is cancelled.
    public var onWarningCancelled: (@MainActor () -> Void)?
    
    // MARK: - Motion Hardware & Dependencies
    
    #if os(iOS) && canImport(CoreMotion)
    private let motionManager: CMMotionManager?
    private let motionQueue = OperationQueue()
    #endif
    
    private let dateProvider: @Sendable () -> Date
    private var monitorTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    
    // MARK: - Configuration Knobs
    
    public var stillnessThresholdSeconds: TimeInterval {
        TeeKumConfiguration.SOS.inactivityStillnessDuration
    }
    
    public var warningCountdownSeconds: TimeInterval {
        TeeKumConfiguration.SOS.inactivityWarningCountdown
    }
    
    public var motionThresholdG: Double {
        TeeKumConfiguration.SOS.inactivityMotionThreshold
    }
    
    public var isWarningActive: Bool {
        if case .warning = state { return true }
        return false
    }
    
    // MARK: - Initializer
    
    public init(
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.dateProvider = dateProvider
        self.lastActivityTimestamp = dateProvider()
        
        #if os(iOS) && canImport(CoreMotion)
        let manager = CMMotionManager()
        manager.accelerometerUpdateInterval = 0.5
        self.motionManager = manager
        #endif
    }
    
    // MARK: - Lifecycle Controls
    
    public func startMonitoring() {
        guard isEnabled else {
            state = .disabled
            return
        }
        
        cancelCountdown()
        lastActivityTimestamp = dateProvider()
        state = .monitoring(stillSince: lastActivityTimestamp)
        
        startHardwareAccelerometer()
        startMonitorLoop()
    }
    
    public func stopMonitoring() {
        cancelCountdown()
        cancelMonitorLoop()
        stopHardwareAccelerometer()
        state = .disabled
    }
    
    // MARK: - User & Motion Activity Registration
    
    /// Explicitly registers user activity (touch on screen, button press, typing, app resume).
    /// Resets the stillness duration.
    public func recordUserInteraction() {
        guard isEnabled else { return }
        lastActivityTimestamp = dateProvider()
        
        if case .warning = state {
            cancelWarning()
        } else if case .monitoring = state {
            state = .monitoring(stillSince: lastActivityTimestamp)
        }
    }
    
    /// Called when accelerometer detects significant physical motion.
    public func recordPhysicalMotion() {
        guard isEnabled else { return }
        lastActivityTimestamp = dateProvider()
        
        if case .warning = state {
            cancelWarning()
        } else if case .monitoring = state {
            state = .monitoring(stillSince: lastActivityTimestamp)
        }
    }
    
    /// User taps "I'm OK" button on screen or notification to dismiss the warning countdown.
    public func cancelWarning() {
        guard case .warning = state else { return }
        cancelCountdown()
        lastActivityTimestamp = dateProvider()
        state = .monitoring(stillSince: lastActivityTimestamp)
        onWarningCancelled?()
    }
    
    // MARK: - Hardware Accelerometer Integration
    
    private func startHardwareAccelerometer() {
        #if os(iOS) && canImport(CoreMotion)
        guard let motionManager, motionManager.isAccelerometerAvailable else { return }
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, _ in
            guard let data else { return }
            let x = data.acceleration.x
            let y = data.acceleration.y
            let z = data.acceleration.z
            
            // Vector magnitude in g: sqrt(x^2 + y^2 + z^2)
            let magnitude = sqrt(x*x + y*y + z*z)
            let deviation = abs(magnitude - 1.0)
            
            Task { @MainActor [weak self] in
                guard let self else { return }
                if deviation >= self.motionThresholdG {
                    self.recordPhysicalMotion()
                }
            }
        }
        #endif
    }
    
    private func stopHardwareAccelerometer() {
        #if os(iOS) && canImport(CoreMotion)
        motionManager?.stopAccelerometerUpdates()
        #endif
    }
    
    // MARK: - Background Monitoring Loop
    
    private func startMonitorLoop() {
        cancelMonitorLoop()
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s tick
                guard let self, !Task.isCancelled else { break }
                self.evaluateStillness()
            }
        }
    }
    
    private func cancelMonitorLoop() {
        monitorTask?.cancel()
        monitorTask = nil
    }
    
    /// Evaluates current stillness duration and starts countdown if threshold met.
    public func evaluateStillness() {
        guard isEnabled else { return }
        guard case .monitoring = state else { return }
        
        let now = dateProvider()
        let elapsed = now.timeIntervalSince(lastActivityTimestamp)
        
        if elapsed >= stillnessThresholdSeconds {
            startWarningCountdown()
        }
    }
    
    // MARK: - Pre-Alarm Warning Countdown
    
    private func startWarningCountdown() {
        let duration = warningCountdownSeconds
        self.countdownRemaining = duration
        self.state = .warning(remainingSeconds: duration)
        
        onWarningStarted?()
        triggerHapticWarning()
        
        cancelCountdown()
        countdownTask = Task { @MainActor [weak self] in
            var remaining = duration
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s tick
                guard let self, !Task.isCancelled else { break }
                
                remaining = max(0.0, remaining - 0.5)
                self.countdownRemaining = remaining
                self.state = .warning(remainingSeconds: remaining)
                
                // Periodic haptic feedback (every ~2 seconds), NO audible sound
                if Int(remaining * 2) % 4 == 0 {
                    self.triggerHapticWarning()
                }
                self.onWarningTick?(remaining)
            }
            
            guard let self, !Task.isCancelled, remaining <= 0 else { return }
            self.executeAutoSOS()
        }
    }
    
    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownRemaining = 0.0
    }
    
    private func triggerHapticWarning() {
        #if canImport(UIKit)
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.warning)
        #endif
    }
    
    private func executeAutoSOS() {
        state = .triggered
        cancelCountdown()
        onTriggerSOS?()
    }
    
    // MARK: - Testing & Simulation Hooks
    
    /// Simulates advancing stillness time by `seconds` and ticks evaluation.
    public func simulateStillness(seconds: TimeInterval) {
        guard isEnabled else { return }
        lastActivityTimestamp = dateProvider().addingTimeInterval(-seconds)
        evaluateStillness()
    }
    
    /// Directly sets the state to warning for UI and integration testing.
    public func simulateWarningState(remainingSeconds: Double) {
        self.countdownRemaining = remainingSeconds
        self.state = .warning(remainingSeconds: remainingSeconds)
    }
    
    /// Resets the inactivity guard back to idle/monitoring.
    public func reset() {
        cancelCountdown()
        lastActivityTimestamp = dateProvider()
        if isEnabled {
            state = .monitoring(stillSince: lastActivityTimestamp)
        } else {
            state = .disabled
        }
    }
}
