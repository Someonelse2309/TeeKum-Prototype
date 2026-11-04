//
//  LiveActivityTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 28/10/26.
//

import Foundation
import CoreLocation

public final class LiveActivityTests: Sendable {
    
    // MARK: - Test Suite Runner
    
    @MainActor
    public static func runAllTests() async -> Bool {
        print("\n==================================================")
        print(">>> STARTING LIVE ACTIVITY & COMPANION TESTS <<<")
        print("==================================================")
        
        var allPassed = true
        let tests: [(String, @MainActor () async throws -> Void)] = [
            ("testAttributesInitialization", testAttributesInitialization),
            ("testContentStateCodableRoundtrip", testContentStateCodableRoundtrip),
            ("testSOSContentStateEncoding", testSOSContentStateEncoding),
            ("testRelayContentStateEncoding", testRelayContentStateEncoding),
            ("testLiveActivityManagerSafeLifecycle", testLiveActivityManagerSafeLifecycle),
            ("testDistanceFormattingCalculations", testDistanceFormattingCalculations)
        ]
        
        for (name, test) in tests {
            do {
                try await test()
                print("  [PASS] \(name)")
            } catch {
                print("  [FAIL] \(name): \(error)")
                allPassed = false
            }
        }
        
        print("==================================================")
        print(allPassed ? ">>> ALL LIVE ACTIVITY TESTS PASSED <<<" : ">>> SOME LIVE ACTIVITY TESTS FAILED <<<")
        print("==================================================\n")
        return allPassed
    }
    
    // MARK: - Individual Test Cases
    
    @MainActor
    public static func testAttributesInitialization() throws {
        let attributes = SessionActivityAttributes(
            sessionId: 0xABCD,
            sessionName: "Ultra Festival",
            userInitials: "NIC"
        )
        
        guard attributes.sessionId == 0xABCD else {
            throw TestError.assertionFailed("Session ID mismatch: expected 0xABCD, got \(attributes.sessionId)")
        }
        guard attributes.sessionName == "Ultra Festival" else {
            throw TestError.assertionFailed("Session name mismatch: \(attributes.sessionName)")
        }
        guard attributes.userInitials == "NIC" else {
            throw TestError.assertionFailed("User initials mismatch: \(attributes.userInitials)")
        }
    }
    
    @MainActor
    public static func testContentStateCodableRoundtrip() throws {
        let originalDate = Date(timeIntervalSince1970: 1730000000)
        let originalState = SessionActivityAttributes.ContentState(
            directPeerCount: 4,
            meetingPointName: "Sound Booth Stage 1",
            meetingPointDistanceMeters: 145.5,
            isSOSActive: false,
            sosSenderInitials: nil,
            lastUpdated: originalDate
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalState)
        
        let decoder = JSONDecoder()
        let decodedState = try decoder.decode(SessionActivityAttributes.ContentState.self, from: data)
        
        guard decodedState.directPeerCount == 4 else {
            throw TestError.assertionFailed("Peer count mismatch")
        }
        guard decodedState.meetingPointName == "Sound Booth Stage 1" else {
            throw TestError.assertionFailed("Meeting point name mismatch")
        }
        guard decodedState.meetingPointDistanceMeters == 145.5 else {
            throw TestError.assertionFailed("Distance mismatch")
        }
        guard !decodedState.isSOSActive else {
            throw TestError.assertionFailed("SOS should not be active")
        }
        guard decodedState.sosSenderInitials == nil else {
            throw TestError.assertionFailed("SOS sender should be nil")
        }
    }
    
    @MainActor
    public static func testSOSContentStateEncoding() throws {
        let sosState = SessionActivityAttributes.ContentState(
            directPeerCount: 2,
            meetingPointName: "First Aid Tent",
            meetingPointDistanceMeters: 80.0,
            isSOSActive: true,
            sosSenderInitials: "SAM",
            lastUpdated: Date()
        )
        
        let data = try JSONEncoder().encode(sosState)
        let decoded = try JSONDecoder().decode(SessionActivityAttributes.ContentState.self, from: data)
        
        guard decoded.isSOSActive else {
            throw TestError.assertionFailed("SOS must be active in decoded state")
        }
        guard decoded.sosSenderInitials == "SAM" else {
            throw TestError.assertionFailed("SOS sender must match 'SAM'")
        }
    }
    
    @MainActor
    public static func testRelayContentStateEncoding() throws {
        let state = SessionActivityAttributes.ContentState(
            directPeerCount: 3,
            meetingPointName: "Sound Stage",
            meetingPointDistanceMeters: 45.0,
            isSOSActive: false,
            sosSenderInitials: nil,
            lastUpdated: Date(),
            relayStatusText: "Active (Timed: 25m left)",
            relayModeText: "Timed 30m",
            timedRelayRemainingSeconds: 1500,
            isRelayActive: true
        )
        
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SessionActivityAttributes.ContentState.self, from: data)
        
        guard decoded.isRelayActive == true else {
            throw TestError.assertionFailed("isRelayActive mismatch")
        }
        guard decoded.relayStatusText == "Active (Timed: 25m left)" else {
            throw TestError.assertionFailed("relayStatusText mismatch")
        }
        guard decoded.timedRelayRemainingSeconds == 1500 else {
            throw TestError.assertionFailed("timedRelayRemainingSeconds mismatch")
        }
    }
    
    @MainActor
    public static func testLiveActivityManagerSafeLifecycle() async throws {
        let manager = LiveActivityManager.shared
        
        let dummyKey = Data(repeating: 0x55, count: 32)
        let session = GroupSession(
            sessionId: 0x4321,
            sessionName: "EDC Las Vegas",
            symmetricKeyData: dummyKey,
            localInitials: "NIC"
        )
        
        // Start activity (safely handles simulator/settings without throwing or crashing)
        await manager.startSessionActivity(session: session)
        
        // Update activity with telemetry
        let meetingPoint = MeetingPoint(
            id: 1,
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            proposerId: "NIC"
        )
        let currentCoord = CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4190)
        
        await manager.updateSessionActivity(
            peerCount: 3,
            meetingPoint: meetingPoint,
            currentLocation: currentCoord,
            isSOSActive: false,
            sosSenderInitials: nil
        )
        
        // End activity cleanly
        await manager.endSessionActivity()
    }
    
    @MainActor
    public static func testDistanceFormattingCalculations() throws {
        let coord1 = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let coord2 = CLLocation(latitude: 37.7759, longitude: -122.4194)
        let distance = coord1.distance(from: coord2)
        
        guard distance > 100 && distance < 120 else {
            throw TestError.assertionFailed("Calculated distance out of expected bounds: \(distance)m")
        }
    }
    
    // MARK: - Test Error
    
    private enum TestError: Error {
        case assertionFailed(String)
    }
}
