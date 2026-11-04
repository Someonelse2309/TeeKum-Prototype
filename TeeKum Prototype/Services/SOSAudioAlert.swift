//
//  SOSAudioAlert.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
#if canImport(AudioToolbox)
import AudioToolbox
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Authoritative contract for audio and haptic alert feedback when emergency SOS is triggered or received.
public protocol SOSAudioAlerting: Sendable {
    /// Plays the emergency alert tone / siren and triggers strong haptic vibration.
    func triggerEmergencyAlertFeedback()
    
    /// Stops any ongoing audio alert or siren loop.
    func stopEmergencyAlertFeedback()
}

/// Native implementation using standard Apple system audio and feedback generators.
///
/// iOS Platform Realities:
/// 1. Hardware Silent / Mute Switch: Standard system alerts (`AudioServicesPlayAlertSound`)
///    respect the physical silent switch and Action button mute mode. When muted, only
///    the haptic vibration fires. Bypassing the mute switch requires `AVAudioSessionCategoryPlayback`
///    with the `audio` UIBackgroundModes entitlement, which iOS restricts for background apps.
/// 2. Focus Modes / Do Not Disturb: Only apps with Apple's special-entitlement
///    "Critical Alerts" (`UNAuthorizationOptions.criticalAlert`) can break through DND.
///    In this direct offline POC, alerts sound when the app is active and foregrounded.
public final class DefaultSOSAudioAlerter: SOSAudioAlerting, @unchecked Sendable {
    
    public init() {}
    
    public func triggerEmergencyAlertFeedback() {
        #if os(iOS) && canImport(AudioToolbox)
        // System Sound 1005: High-priority SMS alert / warning chime
        AudioServicesPlayAlertSound(SystemSoundID(1005))
        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        #endif
        
        #if os(iOS) && canImport(UIKit)
        Task { @MainActor in
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
        }
        #endif
    }
    
    public func stopEmergencyAlertFeedback() {
        // Discrete system sound does not require manual stop, but hooks into active siren loops if expanded.
    }
}

