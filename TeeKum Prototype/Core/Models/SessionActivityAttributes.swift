//
//  SessionActivityAttributes.swift
//  TeeKum Prototype
//
//  Created by Nicho on 28/10/26.
//

import Foundation
import ActivityKit

/// Attributes defining the TeeKum Active Session & Mesh Companion Live Activity.
///
/// Displayed across the iPhone Lock Screen and Dynamic Island during an active offline festival session.
public nonisolated struct SessionActivityAttributes: ActivityAttributes, Sendable {
    
    // MARK: - Dynamic State (Updated in real-time)
    
    public struct ContentState: Codable, Hashable, Sendable {
        /// Number of directly connected peer devices within AWDL/radio range.
        public var directPeerCount: Int
        
        /// Active meeting point label or landmark name (nil if none set).
        public var meetingPointName: String?
        
        /// Distance in meters to the active meeting point from user's current GPS fix.
        public var meetingPointDistanceMeters: Double?
        
        /// True if an emergency SOS alert is currently active in the group.
        public var isSOSActive: Bool
        
        /// Initials of the peer who triggered the emergency SOS alert (nil if normal).
        public var sosSenderInitials: String?
        
        /// Timestamp of the latest telemetry snapshot.
        public var lastUpdated: Date
        
        /// Current communal relay status text for Lock Screen & Dynamic Island display.
        public var relayStatusText: String?
        
        /// Mode descriptor ("Always", "30 Min", "Paused", "Off").
        public var relayModeText: String?
        
        /// Remaining seconds if timed relay is active.
        public var timedRelayRemainingSeconds: Int?
        
        /// True if communal relaying is permitted and active.
        public var isRelayActive: Bool
        
        public init(
            directPeerCount: Int = 0,
            meetingPointName: String? = nil,
            meetingPointDistanceMeters: Double? = nil,
            isSOSActive: Bool = false,
            sosSenderInitials: String? = nil,
            lastUpdated: Date = Date(),
            relayStatusText: String? = nil,
            relayModeText: String? = nil,
            timedRelayRemainingSeconds: Int? = nil,
            isRelayActive: Bool = false
        ) {
            self.directPeerCount = directPeerCount
            self.meetingPointName = meetingPointName
            self.meetingPointDistanceMeters = meetingPointDistanceMeters
            self.isSOSActive = isSOSActive
            self.sosSenderInitials = sosSenderInitials
            self.lastUpdated = lastUpdated
            self.relayStatusText = relayStatusText
            self.relayModeText = relayModeText
            self.timedRelayRemainingSeconds = timedRelayRemainingSeconds
            self.isRelayActive = isRelayActive
        }
    }
    
    // MARK: - Static Properties (Fixed for the session)
    
    /// Unique 16-bit session ID.
    public var sessionId: UInt16
    
    /// Human-readable festival session or group name.
    public var sessionName: String
    
    /// Local user's 1-to-3 letter initials.
    public var userInitials: String
    
    public init(sessionId: UInt16, sessionName: String, userInitials: String) {
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.userInitials = userInitials
    }
}

// MARK: - AppIntent for Live Activity Interactive Controls

import AppIntents

public struct EndSessionIntent: AppIntent {
    public static var title: LocalizedStringResource = "End Session"
    public static var description = IntentDescription("Ends the active TeeKum festival session and dismisses the Live Activity.")
    public static var isDiscoverable: Bool = false
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        UserDefaults.standard.removeObject(forKey: "com.teekum.activeGroupSession")
        for activity in Activity<SessionActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}

