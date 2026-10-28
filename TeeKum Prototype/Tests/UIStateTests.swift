//
//  UIStateTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation
import SwiftUI

/// Comprehensive test suite validating UI state contracts, ViewModel behavior,
/// freshness indicators, 3-second SOS hold logic, and honest delivery feedback.
public struct UIStateTests {
    
    @MainActor
    public static func runAllTests() async -> Bool {
        print("--- [UIStateTests] Running UI & ViewModel Test Suite ---")
        var passed = true
        
        if !(await testGroupPairingLifecycle()) { passed = false }
        if !(await testLocationFreshnessIndicators()) { passed = false }
        if !(await testStatusPickerState()) { passed = false }
        if !(await testLiveSharingToggle()) { passed = false }
        if !(await testSOSContinuousHoldAndCancellation()) { passed = false }
        if !(await testHonestDeliveryStateTransitions()) { passed = false }
        if !(await testFriendDistanceAndBearingCalculations()) { passed = false }
        if !(await testMeetingPointProposalAndAttendance()) { passed = false }
        if !(await testQRBarcodeScanningEdgeCases()) { passed = false }
        if !(await testSessionTeardownAndCleanUIReset()) { passed = false }
        if !(await testSOSMemberRosterAndEmergencyVisualState()) { passed = false }
        
        if passed {
            print("--- [UIStateTests] ✓ ALL 11 UI STATE TEST SUITES PASSED ---")
        } else {
            print("--- [UIStateTests] ✗ SOME UI STATE TESTS FAILED ---")
        }
        return passed
    }
    
    // MARK: - 1. Group Pairing Lifecycle
    
    @MainActor
    private static func testGroupPairingLifecycle() async -> Bool {
        print("[TEST] testGroupPairingLifecycle...")
        let vm = GroupSessionViewModel()
        vm.leaveGroup()
        
        // Initial state
        guard !vm.hasActiveSession else {
            print("FAILED: hasActiveSession should be false initially")
            return false
        }
        
        // Host creates group
        vm.createGroup(name: "EDC Crew", localName: "Nicho")
        guard let session = vm.activeSession else {
            print("FAILED: activeSession should not be nil after createGroup")
            return false
        }
        
        guard session.sessionName == "EDC Crew", session.localMemberName == "Nicho", session.isHost else {
            print("FAILED: session properties mismatch")
            return false
        }
        
        // Key fingerprint safety (never raw secret)
        guard let fingerprint = vm.keyFingerprint, fingerprint.count == 8 else {
            print("FAILED: keyFingerprint should be 8 hex characters")
            return false
        }
        
        // Invite URL generation & parsing
        guard let inviteURL = vm.inviteURL else {
            print("FAILED: inviteURL should be generated")
            return false
        }
        
        guard let parsedInvite = GroupSession.parseInvite(from: inviteURL) else {
            print("FAILED: parseInvite should parse inviteURL")
            return false
        }
        
        guard parsedInvite.sessionId == session.sessionId,
              parsedInvite.sessionName == "EDC Crew",
              parsedInvite.keyData == session.symmetricKeyData else {
            print("FAILED: parsed invite mismatch")
            return false
        }
        
        // Participant joins
        let participantVM = GroupSessionViewModel()
        participantVM.joinGroup(invite: parsedInvite, localName: "Alex")
        guard let participantSession = participantVM.activeSession else {
            print("FAILED: participant should have activeSession")
            return false
        }
        guard !participantSession.isHost, participantSession.localMemberName == "Alex" else {
            print("FAILED: participant properties mismatch")
            return false
        }
        
        // Teardown
        vm.leaveGroup()
        guard !vm.hasActiveSession, vm.members.isEmpty else {
            print("FAILED: leaveGroup should wipe session and members")
            return false
        }
        
        print("PASSED: testGroupPairingLifecycle")
        return true
    }
    
    // MARK: - 2. Location Freshness Indicators
    
    @MainActor
    private static func testLocationFreshnessIndicators() async -> Bool {
        print("[TEST] testLocationFreshnessIndicators...")
        
        // Fresh member (< 60s)
        let freshMember = Member(
            id: 0x1234,
            name: "Sarah",
            lastSeen: Date().addingTimeInterval(-15), // 15s ago
            coordinate: CLLocationCoordinate2D(latitude: 33.68, longitude: -116.23)
        )
        guard !freshMember.isStale(threshold: 60) else {
            print("FAILED: freshMember should not be stale")
            return false
        }
        
        // Stale member (> 60s)
        let staleMember = Member(
            id: 0x5678,
            name: "Dave",
            lastSeen: Date().addingTimeInterval(-180), // 3 minutes ago
            coordinate: CLLocationCoordinate2D(latitude: 33.68, longitude: -116.23)
        )
        guard staleMember.isStale(threshold: 60) else {
            print("FAILED: staleMember should be marked stale")
            return false
        }
        
        // Custom threshold
        guard staleMember.isStale(threshold: 30) else {
            print("FAILED: staleMember should be marked stale with 30s threshold")
            return false
        }
        
        print("PASSED: testLocationFreshnessIndicators")
        return true
    }
    
    // MARK: - 3. Status Picker State
    
    @MainActor
    private static func testStatusPickerState() async -> Bool {
        print("[TEST] testStatusPickerState...")
        let mapVM = MapViewModel()
        
        guard mapVM.currentStatus.code == .available else {
            print("FAILED: default status should be .available")
            return false
        }
        
        // Update to drinks
        mapVM.updateUserStatus(UserStatus(code: .gettingDrinks))
        guard mapVM.currentStatus.code == .gettingDrinks else {
            print("FAILED: currentStatus should be .gettingDrinks")
            return false
        }
        
        // All enum cases must have valid title, emoji, and systemImage
        for code in StatusCode.allCases {
            guard !code.title.isEmpty, !code.emoji.isEmpty, !code.systemImage.isEmpty else {
                print("FAILED: missing display metadata for status \(code)")
                return false
            }
        }
        
        print("PASSED: testStatusPickerState")
        return true
    }
    
    // MARK: - 4. Live Sharing Toggle
    
    @MainActor
    private static func testLiveSharingToggle() async -> Bool {
        print("[TEST] testLiveSharingToggle...")
        let mapVM = MapViewModel(isLiveSharingEnabled: true)
        
        guard mapVM.isLiveSharingEnabled else {
            print("FAILED: should be enabled initially")
            return false
        }
        guard mapVM.statusPillMessage.contains("Live Sharing Active") else {
            print("FAILED: status pill message should indicate active")
            return false
        }
        
        // Toggle OFF
        mapVM.toggleLiveSharing()
        guard !mapVM.isLiveSharingEnabled else {
            print("FAILED: should be disabled after toggle")
            return false
        }
        guard mapVM.statusPillMessage.contains("Paused") else {
            print("FAILED: status pill should indicate paused")
            return false
        }
        
        // Toggle back ON
        mapVM.toggleLiveSharing()
        guard mapVM.isLiveSharingEnabled else {
            print("FAILED: should be re-enabled")
            return false
        }
        
        print("PASSED: testLiveSharingToggle")
        return true
    }
    
    // MARK: - 5. SOS Continuous 3-Second Hold & Cancellation
    
    @MainActor
    private static func testSOSContinuousHoldAndCancellation() async -> Bool {
        print("[TEST] testSOSContinuousHoldAndCancellation...")
        let sosVM = SOSViewModel()
        
        guard sosVM.deliveryState == .idle, sosVM.holdProgress == 0.0 else {
            print("FAILED: initial state should be idle with 0 progress")
            return false
        }
        
        // User starts pressing
        sosVM.handlePressBegan()
        guard case .countdown = sosVM.deliveryState else {
            print("FAILED: state should be .countdown after press begins")
            return false
        }
        
        // 1 second elapsed (33% progress)
        sosVM.updateProgress(elapsedSeconds: 1.0)
        guard abs(sosVM.holdProgress - (1.0 / 3.0)) < 0.01 else {
            print("FAILED: progress should be ~0.33")
            return false
        }
        
        // User releases early (< 3.0s) -> Must cancel immediately!
        sosVM.handlePressCancelled()
        guard sosVM.deliveryState == .idle, sosVM.holdProgress == 0.0 else {
            print("FAILED: early release must cancel and reset to idle")
            return false
        }
        
        // User presses again and completes 3.0s full hold
        sosVM.handlePressBegan()
        sosVM.updateProgress(elapsedSeconds: 1.5)
        sosVM.updateProgress(elapsedSeconds: 3.0)
        
        guard sosVM.deliveryState == .localSending, sosVM.holdProgress == 1.0 else {
            print("FAILED: 3.0s hold must trigger SOS and enter .localSending")
            return false
        }
        
        // Reset
        sosVM.reset()
        guard sosVM.deliveryState == .idle, sosVM.holdProgress == 0.0 else {
            print("FAILED: reset should return to idle")
            return false
        }
        
        print("PASSED: testSOSContinuousHoldAndCancellation")
        return true
    }
    
    // MARK: - 6. Honest Delivery State Transitions
    
    @MainActor
    private static func testHonestDeliveryStateTransitions() async -> Bool {
        print("[TEST] testHonestDeliveryStateTransitions...")
        let sosVM = SOSViewModel()
        
        sosVM.triggerSOS()
        guard sosVM.deliveryState == .localSending else {
            print("FAILED: should be .localSending")
            return false
        }
        
        // Intermediate relay hop ACK received
        // CRITICAL PRINCIPLE: Must NOT claim delivered to friend!
        sosVM.handleAckReceived(status: .relayedByMeshHop, responderId: 0x9999, hopCount: 2)
        guard case let .relayedAck(hops, responder) = sosVM.deliveryState, hops == 2, responder == 0x9999 else {
            print("FAILED: relay ack must not claim delivered to friend")
            return false
        }
        guard !sosVM.deliveryState.title.contains("Delivered to Friend") else {
            print("FAILED: relayedAck title must not claim friend delivery")
            return false
        }
        
        // Final destination friend ACK received
        sosVM.handleAckReceived(status: .deliveredToFriend, responderId: 0x1111, hopCount: 1)
        guard case let .deliveredToFriend(friendId, _) = sosVM.deliveryState, friendId == 0x1111 else {
            print("FAILED: friend delivery ack should be deliveredToFriend")
            return false
        }
        guard sosVM.deliveryState.title.contains("Delivered to Friend") else {
            print("FAILED: title should confirm delivery to friend")
            return false
        }
        
        print("PASSED: testHonestDeliveryStateTransitions")
        return true
    }
    
    // MARK: - 7. Friend Distance & Bearing Calculations
    
    @MainActor
    private static func testFriendDistanceAndBearingCalculations() async -> Bool {
        print("[TEST] testFriendDistanceAndBearingCalculations...")
        
        // Point A (Local user): 33.6800, -116.2300
        let userPin = LocationPin(
            coordinate: CLLocationCoordinate2D(latitude: 33.6800, longitude: -116.2300),
            horizontalAccuracy: 5.0
        )
        
        // Point B (Friend due North): 33.6810, -116.2300 (~111 meters North)
        let friend = Member(
            id: 0x2222,
            name: "Chloe",
            coordinate: CLLocationCoordinate2D(latitude: 33.6810, longitude: -116.2300)
        )
        
        let mapVM = MapViewModel()
        mapVM.userLocation = userPin
        
        let dist = mapVM.distance(to: friend)
        guard let dist, dist > 100 && dist < 125 else {
            print("FAILED: distance should be ~111m, got \(String(describing: dist))")
            return false
        }
        
        let bearing = mapVM.bearing(to: friend)
        guard let bearing, bearing >= 355 || bearing <= 5 else {
            print("FAILED: bearing due North should be ~0°, got \(String(describing: bearing))")
            return false
        }
        
        print("PASSED: testFriendDistanceAndBearingCalculations")
        return true
    }
    
    // MARK: - 8. Meeting Point Proposal & Attendance
    
    @MainActor
    private static func testMeetingPointProposalAndAttendance() async -> Bool {
        print("[TEST] testMeetingPointProposalAndAttendance...")
        let mpVM = MeetingPointViewModel()
        
        guard mpVM.activeMeetingPoint == nil else {
            print("FAILED: should have no active meeting point initially")
            return false
        }
        
        mpVM.proposeMeetingPoint(
            name: "Stage 2 Sound Booth",
            coordinate: CLLocationCoordinate2D(latitude: 33.6820, longitude: -116.2350),
            proposerId: 0xAAAA
        )
        
        guard let active = mpVM.activeMeetingPoint, active.name == "Stage 2 Sound Booth" else {
            print("FAILED: active meeting point should be set")
            return false
        }
        guard mpVM.localAttendanceStatus == .attending else {
            print("FAILED: proposer should be marked attending")
            return false
        }
        
        // Member responds
        mpVM.respond(status: .cantMakeIt, memberId: 0xBBBB)
        guard mpVM.activeMeetingPoint?.attendance[0xBBBB] == .cantMakeIt else {
            print("FAILED: member attendance not recorded")
            return false
        }
        
        // Single active rule: Cancel
        mpVM.cancelMeetingPoint()
        guard mpVM.activeMeetingPoint == nil, mpVM.localAttendanceStatus == nil else {
            print("FAILED: cancel should remove active meeting point")
            return false
        }
        
        print("PASSED: testMeetingPointProposalAndAttendance")
        return true
    }
    
    // MARK: - 9. QR Barcode Scanning & URL Edge Cases
    
    @MainActor
    private static func testQRBarcodeScanningEdgeCases() async -> Bool {
        print("[TEST] testQRBarcodeScanningEdgeCases...")
        let keyData = Data(repeating: 0x77, count: 32)
        let keyBase64 = keyData.base64EncodedString()
        let sid: UInt32 = 0x12345678
        
        // 1. Whitespace & newline trailing
        let rawURLWithWhitespace = "  teekum://join#key=\(keyBase64)&sid=12345678&name=Festival%20Crew \n"
        let trimmed = rawURLWithWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url1 = URL(string: trimmed), let invite1 = GroupSession.parseInvite(from: url1) else {
            print("FAILED: parseInvite should handle trimmed URL with whitespace")
            return false
        }
        guard invite1.sessionId == sid, invite1.keyData == keyData, invite1.sessionName == "Festival Crew" else {
            print("FAILED: invite1 properties mismatch")
            return false
        }
        
        // 2. Uppercase scheme and host
        let uppercaseURL = URL(string: "TEEKUM://JOIN#key=\(keyBase64)&sid=12345678&name=EDC")!
        guard let invite2 = GroupSession.parseInvite(from: uppercaseURL) else {
            print("FAILED: parseInvite should handle uppercase scheme and host")
            return false
        }
        guard invite2.sessionId == sid, invite2.keyData == keyData, invite2.sessionName == "EDC" else {
            print("FAILED: invite2 properties mismatch")
            return false
        }
        
        // 3. Query string format instead of fragment
        let queryURL = URL(string: "teekum://join?key=\(keyBase64)&sid=12345678&name=Ultra")!
        guard let invite3 = GroupSession.parseInvite(from: queryURL) else {
            print("FAILED: parseInvite should handle query format")
            return false
        }
        guard invite3.sessionId == sid, invite3.keyData == keyData, invite3.sessionName == "Ultra" else {
            print("FAILED: invite3 properties mismatch")
            return false
        }
        
        // 4. Invalid scheme or host
        let invalidSchemeURL = URL(string: "https://join#key=\(keyBase64)&sid=12345678&name=Fake")!
        guard GroupSession.parseInvite(from: invalidSchemeURL) == nil else {
            print("FAILED: parseInvite must reject non-teekum scheme")
            return false
        }
        
        // 5. Short key (less than 32 bytes)
        let shortKeyBase64 = Data([0x01, 0x02]).base64EncodedString()
        let shortKeyURL = URL(string: "teekum://join#key=\(shortKeyBase64)&sid=12345678&name=Fake")!
        guard GroupSession.parseInvite(from: shortKeyURL) == nil else {
            print("FAILED: parseInvite must reject keys that are not 32 bytes")
            return false
        }
        
        print("PASSED: testQRBarcodeScanningEdgeCases")
        return true
    }
    
    // MARK: - 10. Session Teardown & Clean UI Reset
    
    @MainActor
    private static func testSessionTeardownAndCleanUIReset() async -> Bool {
        print("[TEST] testSessionTeardownAndCleanUIReset...")
        let vm = GroupSessionViewModel()
        vm.leaveGroup()
        
        // 1. Create a session and verify it persists across simulated relaunch
        vm.createGroup(name: "Tomorrowland", localName: "Maya")
        guard let originalSession = vm.activeSession else {
            print("FAILED: Active session should exist")
            return false
        }
        
        let relaunchVM = GroupSessionViewModel()
        guard relaunchVM.hasActiveSession, let restored = relaunchVM.activeSession else {
            print("FAILED: Session should persist and restore on simulated relaunch")
            return false
        }
        guard restored.sessionId == originalSession.sessionId, restored.sessionName == "Tomorrowland" else {
            print("FAILED: Restored session properties mismatch")
            return false
        }
        
        // 2. Perform leaveGroup and verify clean purge
        relaunchVM.leaveGroup()
        guard !relaunchVM.hasActiveSession, relaunchVM.members.isEmpty else {
            print("FAILED: Active session and members should be cleared after leaveGroup")
            return false
        }
        
        // Verify disk storage is wiped
        let cleanSlateVM = GroupSessionViewModel()
        guard !cleanSlateVM.hasActiveSession else {
            print("FAILED: Session should not restore after leaveGroup")
            return false
        }
        
        // 3. Test resetSessionState
        cleanSlateVM.newGroupName = "Draft Group"
        cleanSlateVM.resetSessionState()
        guard cleanSlateVM.newGroupName.isEmpty, !cleanSlateVM.hasActiveSession else {
            print("FAILED: resetSessionState did not clear drafted state")
            return false
        }
        
        print("PASSED: testSessionTeardownAndCleanUIReset")
        return true
    }
    
    // MARK: - 11. SOS Member Roster & Emergency Visual State
    
    @MainActor
    private static func testSOSMemberRosterAndEmergencyVisualState() async -> Bool {
        print("[TEST] testSOSMemberRosterAndEmergencyVisualState...")
        let sessionVM = GroupSessionViewModel()
        sessionVM.leaveGroup()
        
        let initialMember = Member(
            id: 0x00010001,
            name: "Alice",
            coordinate: CLLocationCoordinate2D(latitude: 33.6800, longitude: -116.2300),
            status: UserStatus(code: .available),
            isDirectPeer: true
        )
        sessionVM.updateMember(initialMember)
        
        guard let m1 = sessionVM.members.first, !m1.status.code.isEmergency else {
            print("FAILED: Member should initially have non-emergency status")
            return false
        }
        
        // Simulate inbound SOS update from local relay (hopCount = 1, so isDirectPeer = false)
        let emergencyCoord = CLLocationCoordinate2D(latitude: 33.6850, longitude: -116.2350)
        let updatedEmergencyMember = Member(
            id: 0x00010001,
            name: "Alice",
            lastSeen: Date(),
            coordinate: emergencyCoord,
            horizontalAccuracy: 5.0,
            status: UserStatus(code: .sos),
            batteryLevel: 0.85,
            isDirectPeer: false // Relayed via mesh
        )
        sessionVM.updateMember(updatedEmergencyMember)
        
        guard let m2 = sessionVM.members.first else {
            print("FAILED: Member should exist in roster")
            return false
        }
        
        guard m2.status.code == .sos, m2.status.code.isEmergency else {
            print("FAILED: Member status must be .sos and isEmergency must be true")
            return false
        }
        guard !m2.isDirectPeer else {
            print("FAILED: Relayed emergency member must have isDirectPeer = false (Mesh Relay)")
            return false
        }
        guard m2.coordinate?.latitude == 33.6850, m2.coordinate?.longitude == -116.2350 else {
            print("FAILED: Emergency coordinates not updated in roster")
            return false
        }
        
        print("PASSED: testSOSMemberRosterAndEmergencyVisualState")
        return true
    }
}
