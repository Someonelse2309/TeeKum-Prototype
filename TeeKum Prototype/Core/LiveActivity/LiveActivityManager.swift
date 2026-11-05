//
//  LiveActivityManager.swift
//  TeeKum Prototype
//
//  Created by Nicho on 28/10/26.
//

import Foundation
import ActivityKit
import CoreLocation

/// Protocol governing Live Activity companion lifecycle and dynamic updates.
public protocol LiveActivityManaging: AnyObject, Sendable {
    func startSessionActivity(session: GroupSession) async
    func updateSessionActivity(
        peerCount: Int,
        meetingPoint: MeetingPoint?,
        currentLocation: CLLocationCoordinate2D?,
        isSOSActive: Bool,
        sosSenderInitials: String?,
        relayStatusText: String?,
        relayModeText: String?,
        timedRelayRemainingSeconds: Int?,
        isRelayActive: Bool
    ) async
    func endSessionActivity() async
}

extension LiveActivityManaging {
    public func updateSessionActivity(
        peerCount: Int,
        meetingPoint: MeetingPoint?,
        currentLocation: CLLocationCoordinate2D?,
        isSOSActive: Bool,
        sosSenderInitials: String?
    ) async {
        await updateSessionActivity(
            peerCount: peerCount,
            meetingPoint: meetingPoint,
            currentLocation: currentLocation,
            isSOSActive: isSOSActive,
            sosSenderInitials: sosSenderInitials,
            relayStatusText: nil,
            relayModeText: nil,
            timedRelayRemainingSeconds: nil,
            isRelayActive: false
        )
    }
}

/// Actor/MainActor service orchestrating ActivityKit Live Activity presentations across
/// Dynamic Island and the iPhone Lock Screen during active offline sessions.
@MainActor
public final class LiveActivityManager: LiveActivityManaging {
    
    // MARK: - Shared Singleton & Properties
    
    public static let shared = LiveActivityManager()
    
    /// Reference to the active ActivityKit instance (if running).
    private var currentActivity: Activity<SessionActivityAttributes>?
    
    public init() {}
    
    // MARK: - Lifecycle Management
    
    /// Starts a Live Activity for the given active festival group session.
    public func startSessionActivity(session: GroupSession) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivityManager] Live Activities are disabled in system settings.")
            return
        }
        
        // Terminate any leftover activity instance from a previous session
        await endSessionActivity()
        
        let attributes = SessionActivityAttributes(
            sessionId: session.sessionId,
            sessionName: session.sessionName,
            userInitials: session.localInitials
        )
        
        let initialState = SessionActivityAttributes.ContentState(
            directPeerCount: 0,
            meetingPointName: nil,
            meetingPointDistanceMeters: nil,
            isSOSActive: false,
            sosSenderInitials: nil,
            lastUpdated: Date()
        )
        
        let content = ActivityContent(state: initialState, staleDate: nil)
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            self.currentActivity = activity
            print("[LiveActivityManager] Started Live Activity: \(activity.id) for session \(session.sessionName)")
        } catch {
            print("[LiveActivityManager] Failed to start Live Activity: \(error)")
        }
    }
    
    /// Dynamically updates the running Live Activity with fresh telemetry.
    public func updateSessionActivity(
        peerCount: Int,
        meetingPoint: MeetingPoint?,
        currentLocation: CLLocationCoordinate2D?,
        isSOSActive: Bool,
        sosSenderInitials: String?,
        relayStatusText: String? = nil,
        relayModeText: String? = nil,
        timedRelayRemainingSeconds: Int? = nil,
        isRelayActive: Bool = false
    ) async {
        guard let activity = currentActivity else { return }
        
        var distance: Double? = nil
        if let meetingPoint = meetingPoint, let currentCoord = currentLocation {
            let userLoc = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude)
            let meetLoc = CLLocation(latitude: meetingPoint.coordinate.latitude, longitude: meetingPoint.coordinate.longitude)
            distance = userLoc.distance(from: meetLoc)
        }
        
        let updatedState = SessionActivityAttributes.ContentState(
            directPeerCount: peerCount,
            meetingPointName: meetingPoint?.name,
            meetingPointDistanceMeters: distance,
            isSOSActive: isSOSActive,
            sosSenderInitials: sosSenderInitials,
            lastUpdated: Date(),
            relayStatusText: relayStatusText,
            relayModeText: relayModeText,
            timedRelayRemainingSeconds: timedRelayRemainingSeconds,
            isRelayActive: isRelayActive
        )
        
        let content = ActivityContent(state: updatedState, staleDate: nil)
        
        Task {
            await activity.update(content)
        }
    }
    
    /// Cleanly dismisses all Live Activities and clears state.
    public func endSessionActivity() async {
        if let activity = currentActivity {
            let finalContent = ActivityContent(state: activity.content.state, staleDate: nil)
            await activity.end(finalContent, dismissalPolicy: .immediate)
            self.currentActivity = nil
            print("[LiveActivityManager] Dismissed current Live Activity: \(activity.id)")
        }
        
        // Terminate all system-tracked activities for this attribute type to prevent lingering/duplicates
        for activity in Activity<SessionActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
            print("[LiveActivityManager] Dismissed lingering Activity: \(activity.id)")
        }
    }
    
    /// Cleans up any orphaned activities if launched without an active group session.
    public func cleanupDanglingActivities() async {
        for activity in Activity<SessionActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.currentActivity = nil
    }
}
