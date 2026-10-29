//
//  UIStateTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation
import SwiftUI
import CryptoKit

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
        if !(await testMeetingPointWireBroadcastWithHigherTTL()) { passed = false }
        if !(await testInitialsCodecAndAutoMeshEdgeCases()) { passed = false }
        if !(await testSessionTeardownAndCleanUIReset()) { passed = false }
        if !(await testSOSMemberRosterAndEmergencyVisualState()) { passed = false }
        
        if passed {
            print("--- [UIStateTests] ✓ ALL 12 UI STATE TEST SUITES PASSED ---")
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
        
        // Host creates group with 1 to 3-letter initials (e.g. "D" or "DNA")
        vm.createGroup(name: "EDC Crew", localName: "DNA")
        guard let session = vm.activeSession else {
            print("FAILED: activeSession should not be nil after createGroup")
            return false
        }
        
        guard session.sessionName == "EDC Crew", session.localInitials == "DNA", session.isHost else {
            print("FAILED: session properties mismatch")
            return false
        }
        
        // Key fingerprint safety (never raw secret)
        guard let fingerprint = vm.keyFingerprint, fingerprint.count == 8 else {
            print("FAILED: keyFingerprint should be 8 hex characters")
            return false
        }
        
        // Invite URL generation & QR barcode parsing
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
        
        // Pending invite agreement gating
        let participantVM = GroupSessionViewModel()
        participantVM.resetSessionState()
        participantVM.pendingInvite = parsedInvite
        guard participantVM.pendingInvite?.sessionId == parsedInvite.sessionId else {
            print("FAILED: pendingInvite not held prior to user agreement")
            return false
        }
        guard !participantVM.hasActiveSession else {
            print("FAILED: participant should not have active session before agreeing to compact")
            return false
        }
        
        // User accepts mesh agreement and joins host group with 2-letter initials (e.g. "AB")
        participantVM.joinGroup(invite: parsedInvite, localName: "AB")
        participantVM.pendingInvite = nil
        guard let participantSession = participantVM.activeSession else {
            print("FAILED: participant should have activeSession after agreement")
            return false
        }
        guard participantVM.pendingInvite == nil else {
            print("FAILED: pendingInvite should be cleared after join")
            return false
        }
        guard !participantSession.isHost, participantSession.localInitials == "AB" else {
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
            id: "SRH",
            name: "SRH",
            lastSeen: Date().addingTimeInterval(-15), // 15s ago
            coordinate: CLLocationCoordinate2D(latitude: 33.68, longitude: -116.23)
        )
        guard !freshMember.isStale(threshold: 60) else {
            print("FAILED: freshMember should not be stale")
            return false
        }
        
        // Stale member (> 60s)
        let staleMember = Member(
            id: "DVE",
            name: "DVE",
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
        sosVM.handleAckReceived(status: .relayedByMeshHop, responderId: "REL", hopCount: 2)
        guard case let .relayedAck(hops, responder) = sosVM.deliveryState, hops == 2, responder == "REL" else {
            print("FAILED: relay ack must not claim delivered to friend")
            return false
        }
        guard !sosVM.deliveryState.title.contains("Delivered to Friend") else {
            print("FAILED: relayedAck title must not claim friend delivery")
            return false
        }
        
        // Final destination friend ACK received
        sosVM.handleAckReceived(status: .deliveredToFriend, responderId: "ALX", hopCount: 1)
        guard case let .deliveredToFriend(friendId, _) = sosVM.deliveryState, friendId == "ALX" else {
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
            id: "CHL",
            name: "CHL",
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
            proposerId: "ALX"
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
        mpVM.respond(status: .cantMakeIt, memberId: "BOB")
        guard mpVM.activeMeetingPoint?.attendance["BOB"] == .cantMakeIt else {
            print("FAILED: member attendance not recorded")
            return false
        }
        
        // Single active rule: Cancel
        mpVM.cancelMeetingPoint()
        guard mpVM.activeMeetingPoint == nil, mpVM.localAttendanceStatus == nil else {
            print("FAILED: cancel should remove active meeting point")
            return false
        }
        
        // Map-dropped pin proposal with coordinate formatting
        let droppedCoord = CLLocationCoordinate2D(latitude: 33.6841, longitude: -116.2369)
        let defaultFormattedName = String(format: "Meeting Point (%.4f, %.4f)", droppedCoord.latitude, droppedCoord.longitude)
        mpVM.proposeMeetingPoint(
            name: defaultFormattedName,
            coordinate: droppedCoord,
            proposerId: "ALX"
        )
        guard let mapActive = mpVM.activeMeetingPoint, mapActive.name == defaultFormattedName else {
            print("FAILED: map-dropped meeting point name mismatch")
            return false
        }
        guard abs(mapActive.coordinate.latitude - 33.6841) < 0.0001,
              abs(mapActive.coordinate.longitude - (-116.2369)) < 0.0001 else {
            print("FAILED: map-dropped meeting point coordinate mismatch")
            return false
        }
        
        // Replace active meeting point directly (seamless overwrite)
        let replacedCoord = CLLocationCoordinate2D(latitude: 33.6822, longitude: -116.2355)
        mpVM.proposeMeetingPoint(
            name: "Main Stage Sound Booth",
            coordinate: replacedCoord,
            proposerId: "ALX",
            landmarkId: 1
        )
        guard let replacedActive = mpVM.activeMeetingPoint, replacedActive.name == "Main Stage Sound Booth" else {
            print("FAILED: active meeting point was not replaced cleanly")
            return false
        }
        guard replacedActive.landmarkId == 1 else {
            print("FAILED: landmarkId was not preserved on replaced point")
            return false
        }
        
        // Clean up
        mpVM.cancelMeetingPoint()
        
        // Premade Meeting Location Dropdown Verification
        guard PremadeMeetingLocation.defaultName == "Meeting Point" else {
            print("FAILED: PremadeMeetingLocation defaultName must be 'Meeting Point'")
            return false
        }
        guard PremadeMeetingLocation.allLocations.first == "Meeting Point" else {
            print("FAILED: PremadeMeetingLocation first option must be 'Meeting Point'")
            return false
        }
        guard PremadeMeetingLocation.allLocations.contains("Ferris Wheel"),
              PremadeMeetingLocation.allLocations.contains("Main Stage Sound Booth") else {
            print("FAILED: PremadeMeetingLocation missing key festival landmarks")
            return false
        }
        
        mpVM.proposeMeetingPoint(
            name: PremadeMeetingLocation.defaultName,
            coordinate: CLLocationCoordinate2D(latitude: 33.6820, longitude: -116.2350),
            proposerId: "ALX"
        )
        guard mpVM.activeMeetingPoint?.name == "Meeting Point" else {
            print("FAILED: default dropdown meeting point proposal failed")
            return false
        }
        mpVM.cancelMeetingPoint()
        
        print("PASSED: testMeetingPointProposalAndAttendance")
        return true
    }
    
    // MARK: - 9. Initials Codec & QR Barcode Scanning Edge Cases
    
    @MainActor
    private static func testInitialsCodecAndAutoMeshEdgeCases() async -> Bool {
        print("[TEST] testInitialsCodecAndAutoMeshEdgeCases...")
        
        // 1. Valid 1, 2, and 3-letter initials
        guard let b1 = InitialsCodec.encode("D"), InitialsCodec.decode(b1) == "D" else {
            print("FAILED: encode 1-letter 'D' failed")
            return false
        }
        guard let b2 = InitialsCodec.encode("AB"), InitialsCodec.decode(b2) == "AB" else {
            print("FAILED: encode 2-letter 'AB' failed")
            return false
        }
        guard let b3 = InitialsCodec.encode("DNA"), InitialsCodec.decode(b3) == "DNA" else {
            print("FAILED: encode 3-letter 'DNA' failed")
            return false
        }
        guard b1.count == 2 && b2.count == 2 && b3.count == 2 else {
            print("FAILED: encoded bytes must strictly be 2 bytes")
            return false
        }
        
        // 2. Sanitization: lowercase, whitespace, special characters, max 3
        guard InitialsCodec.sanitize("d") == "D" else { return false }
        guard InitialsCodec.sanitize("ab") == "AB" else { return false }
        guard InitialsCodec.sanitize(" d-n.a! ") == "DNA" else { return false }
        guard InitialsCodec.sanitize("Alex") == "ALE" else { return false }
        
        // 3. Boundary values
        guard let aBytes = InitialsCodec.encode("A"), InitialsCodec.decode(aBytes) == "A",
              let zzzBytes = InitialsCodec.encode("ZZZ"), InitialsCodec.decode(zzzBytes) == "ZZZ" else {
            print("FAILED: boundary codec failed")
            return false
        }
        
        // 4. Invalid input rejection
        guard InitialsCodec.encode("") == nil else { return false }
        guard InitialsCodec.encode("ABCD") == nil else { return false }
        guard InitialsCodec.encode("A1B") == nil else { return false }
        
        // 5. QR Barcode URL parsing edge cases
        let keyData = Data(repeating: 0x77, count: 32)
        let keyBase64 = keyData.base64EncodedString()
        let sid: UInt16 = 0x1234
        
        // Trimmed whitespace & fragment format
        let rawURLWithWhitespace = "  teekum://join#key=\(keyBase64)&sid=1234&name=Festival%20Crew \n"
        let trimmed = rawURLWithWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url1 = URL(string: trimmed), let invite1 = GroupSession.parseInvite(from: url1) else {
            print("FAILED: parseInvite should handle trimmed URL with whitespace")
            return false
        }
        guard invite1.sessionId == sid, invite1.keyData == keyData, invite1.sessionName == "Festival Crew" else {
            print("FAILED: invite1 properties mismatch")
            return false
        }
        
        // Uppercase scheme and host
        let uppercaseURL = URL(string: "TEEKUM://JOIN#key=\(keyBase64)&sid=1234&name=EDC")!
        guard let invite2 = GroupSession.parseInvite(from: uppercaseURL) else {
            print("FAILED: parseInvite should handle uppercase scheme and host")
            return false
        }
        guard invite2.sessionId == sid, invite2.keyData == keyData, invite2.sessionName == "EDC" else {
            print("FAILED: invite2 properties mismatch")
            return false
        }
        
        // Query format instead of fragment
        let queryURL = URL(string: "teekum://join?key=\(keyBase64)&sid=1234&name=Ultra")!
        guard let invite3 = GroupSession.parseInvite(from: queryURL) else {
            print("FAILED: parseInvite should handle query format")
            return false
        }
        guard invite3.sessionId == sid, invite3.keyData == keyData, invite3.sessionName == "Ultra" else {
            print("FAILED: invite3 properties mismatch")
            return false
        }
        
        // Invalid scheme rejection
        let invalidSchemeURL = URL(string: "https://join#key=\(keyBase64)&sid=1234&name=Fake")!
        guard GroupSession.parseInvite(from: invalidSchemeURL) == nil else {
            print("FAILED: parseInvite must reject non-teekum scheme")
            return false
        }
        
        // Short key rejection (< 32 bytes)
        let shortKeyBase64 = Data([0x01, 0x02]).base64EncodedString()
        let shortKeyURL = URL(string: "teekum://join#key=\(shortKeyBase64)&sid=1234&name=Fake")!
        guard GroupSession.parseInvite(from: shortKeyURL) == nil else {
            print("FAILED: parseInvite must reject keys that are not 32 bytes")
            return false
        }
        
        // 6. Regex invite link extraction from full copied share messages
        let fullShareMessage = "Join my offline concert group on TeeKum: Festival Crew teekum://join#key=EQMSefLnvHGgDn7OQxFTebz7KeeGr/Wr+FEC/3KJd1A=&sid=F390&name=Festival%20Crew"
        guard let extractedURL = GroupSession.extractInviteURL(from: fullShareMessage) else {
            print("FAILED: extractInviteURL failed on full share message")
            return false
        }
        guard extractedURL.absoluteString == "teekum://join#key=EQMSefLnvHGgDn7OQxFTebz7KeeGr/Wr+FEC/3KJd1A=&sid=F390&name=Festival%20Crew" else {
            print("FAILED: extractedURL mismatch: \(extractedURL.absoluteString)")
            return false
        }
        guard let inviteFromFullMessage = GroupSession.parseInvite(from: fullShareMessage) else {
            print("FAILED: parseInvite(from: String) failed on full share message")
            return false
        }
        guard inviteFromFullMessage.sessionId == 0xF390,
              inviteFromFullMessage.sessionName == "Festival Crew",
              inviteFromFullMessage.keyData.count == 32 else {
            print("FAILED: inviteFromFullMessage properties mismatch")
            return false
        }
        
        // Multiline with punctuation and quotes
        let multilineShare = "Hey everyone!\n\"Join my offline concert group on TeeKum: Hard Summer teekum://join#key=\(keyBase64)&sid=ABCD&name=Hard%20Summer.\"\nSee you at the stage!"
        guard let inviteFromMultiline = GroupSession.parseInvite(from: multilineShare) else {
            print("FAILED: parseInvite failed on multiline quoted message with trailing period")
            return false
        }
        guard inviteFromMultiline.sessionId == 0xABCD,
              inviteFromMultiline.sessionName == "Hard Summer",
              inviteFromMultiline.keyData == keyData else {
            print("FAILED: inviteFromMultiline properties mismatch")
            return false
        }
        
        // Invalid text without teekum link
        guard GroupSession.parseInvite(from: "Just some random text without links") == nil else {
            print("FAILED: parseInvite should return nil for random text")
            return false
        }
        
        print("PASSED: testInitialsCodecAndAutoMeshEdgeCases")
        return true
    }
    
    // MARK: - 10. Session Teardown & Clean UI Reset
    
    @MainActor
    private static func testSessionTeardownAndCleanUIReset() async -> Bool {
        print("[TEST] testSessionTeardownAndCleanUIReset...")
        let vm = GroupSessionViewModel()
        vm.leaveGroup()
        
        // 1. Enter auto-mesh and verify it persists across simulated relaunch
        vm.enterAutoMesh(initials: "MAY")
        guard let originalSession = vm.activeSession else {
            print("FAILED: Active session should exist")
            return false
        }
        
        let relaunchVM = GroupSessionViewModel()
        guard relaunchVM.hasActiveSession, let restored = relaunchVM.activeSession else {
            print("FAILED: Session should persist and restore on simulated relaunch")
            return false
        }
        guard restored.sessionId == originalSession.sessionId, restored.localInitials == "MAY" else {
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
            id: "ALX",
            name: "ALX",
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
            id: "ALX",
            name: "ALX",
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
    
    // MARK: - 12. Meeting Point Wire Broadcast with Higher TTL
    
    @MainActor
    private static func testMeetingPointWireBroadcastWithHigherTTL() async -> Bool {
        print("[TEST] testMeetingPointWireBroadcastWithHigherTTL...")
        
        let keyData = Data(repeating: 0x33, count: 32)
        let hostSession = GroupSession(
            sessionId: 0x55AA,
            sessionName: "Festival Mesh",
            symmetricKeyData: keyData,
            localInitials: "ALX",
            isHost: true
        )
        
        let hostTransport = MockMeetingTransport()
        let cryptoService = CryptoService()
        
        let hostVM = MeetingPointViewModel(
            sessionProvider: { hostSession },
            cryptoService: cryptoService,
            transport: hostTransport
        )
        
        // 1. Propose meeting point at Main Stage Sound Booth (Landmark ID 1)
        let coord = CLLocationCoordinate2D(latitude: 33.6822, longitude: -116.2355)
        hostVM.proposeMeetingPoint(
            name: "Main Stage Sound Booth",
            coordinate: coord,
            targetTime: Date(timeIntervalSince1970: 1729000000),
            proposerId: "ALX",
            landmarkId: 1
        )
        
        // Allow async broadcast Task to execute
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        let broadcastCount = await hostTransport.getBroadcastCount()
        guard broadcastCount == 1 else {
            print("FAILED: Meeting proposal should have broadcast 1 packet, got \(broadcastCount)")
            return false
        }
        
        guard let wireData = await hostTransport.getLastBroadcast() else {
            print("FAILED: Missing broadcast wire data")
            return false
        }
        
        // Strictly 56-byte wire layout
        guard wireData.count == PacketConstants.wirePacketSize else {
            print("FAILED: Wire packet size is \(wireData.count), expected \(PacketConstants.wirePacketSize)")
            return false
        }
        
        let wirePacket = try! RawWirePacket.fromWireData(wireData)
        
        // Verify type and Higher TTL
        guard wirePacket.envelope.type == .meetingUpdate else {
            print("FAILED: Envelope type must be .meetingUpdate, got \(wirePacket.envelope.type)")
            return false
        }
        
        guard wirePacket.envelope.hopLimit == PacketConstants.meetingPointHopLimit else {
            print("FAILED: Meeting packet must use higher TTL (\(PacketConstants.meetingPointHopLimit)), got \(wirePacket.envelope.hopLimit)")
            return false
        }
        
        guard wirePacket.envelope.hopLimit > PacketConstants.defaultHopLimit else {
            print("FAILED: Meeting point hopLimit (\(wirePacket.envelope.hopLimit)) must be strictly greater than default (\(PacketConstants.defaultHopLimit))")
            return false
        }
        
        guard wirePacket.envelope.sessionId == 0x55AA else {
            print("FAILED: Session ID mismatch: expected 0x55AA, got \(wirePacket.envelope.sessionId)")
            return false
        }
        
        // 2. Decrypt wire packet as remote peer
        let symmetricKey = SymmetricKey(data: keyData)
        let decryptedData = try! await cryptoService.open(
            ciphertext: wirePacket.ciphertext,
            envelope: wirePacket.envelope,
            authTag: wirePacket.authTag,
            using: symmetricKey
        )
        
        let update = try! MeetingUpdatePayload.deserialize(from: decryptedData)
        guard update.action == MeetingAction.propose else {
            print("FAILED: Decoded action must be .propose, got \(update.action)")
            return false
        }
        guard update.senderInitials == "ALX" else {
            print("FAILED: Sender initials mismatch, got \(update.senderInitials)")
            return false
        }
        guard update.landmarkId == 1 else {
            print("FAILED: Landmark ID mismatch, got \(String(describing: update.landmarkId))")
            return false
        }
        
        // 3. Remote peer receives proposal
        let peerSession = GroupSession(
            sessionId: 0x55AA,
            sessionName: "Festival Mesh",
            symmetricKeyData: keyData,
            localInitials: "BOB",
            isHost: false
        )
        let peerTransport = MockMeetingTransport()
        let peerVM = MeetingPointViewModel(
            sessionProvider: { peerSession },
            cryptoService: cryptoService,
            transport: peerTransport
        )
        
        peerVM.applyInboundUpdate(update)
        guard let peerActive = peerVM.activeMeetingPoint, peerActive.name == "Main Stage Sound Booth" else {
            print("FAILED: Peer VM active meeting point name should be resolved from landmark ID")
            return false
        }
        guard peerActive.proposerId == "ALX" else {
            print("FAILED: Proposer ID mismatch on peer VM")
            return false
        }
        guard peerVM.localAttendanceStatus == nil else {
            print("FAILED: Peer should not be auto-marked attending if not proposer")
            return false
        }
        
        // 4. Remote peer responds "I'll be there" (.attending)
        peerVM.respond(status: .attending, memberId: "BOB")
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        let peerBroadcastCount = await peerTransport.getBroadcastCount()
        guard peerBroadcastCount == 1 else {
            print("FAILED: Peer should have broadcast 1 acceptance packet, got \(peerBroadcastCount)")
            return false
        }
        
        guard let peerWireData = await peerTransport.getLastBroadcast() else {
            print("FAILED: Missing peer broadcast wire data")
            return false
        }
        let peerWirePacket = try! RawWirePacket.fromWireData(peerWireData)
        guard peerWirePacket.envelope.hopLimit == PacketConstants.meetingPointHopLimit else {
            print("FAILED: Peer response should also carry higher TTL, got \(peerWirePacket.envelope.hopLimit)")
            return false
        }
        
        let peerDecrypted = try! await cryptoService.open(
            ciphertext: peerWirePacket.ciphertext,
            envelope: peerWirePacket.envelope,
            authTag: peerWirePacket.authTag,
            using: symmetricKey
        )
        let peerUpdate = try! MeetingUpdatePayload.deserialize(from: peerDecrypted)
        guard peerUpdate.action == MeetingAction.accept, peerUpdate.senderInitials == "BOB" else {
            print("FAILED: Peer update should be .accept from BOB")
            return false
        }
        
        // Host receives BOB's attendance
        hostVM.applyInboundUpdate(peerUpdate)
        guard hostVM.activeMeetingPoint?.attendance["BOB"] == .attending else {
            print("FAILED: Host active meeting point should have BOB marked attending")
            return false
        }
        
        // 5. Host cancels meeting point
        hostVM.cancelMeetingPoint()
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        guard hostVM.activeMeetingPoint == nil else {
            print("FAILED: Host meeting point should be cleared after cancel")
            return false
        }
        guard await hostTransport.getBroadcastCount() == 2 else {
            print("FAILED: Host should have broadcast cancellation packet (2 total)")
            return false
        }
        
        let cancelWireData = await hostTransport.getLastBroadcast()!
        let cancelWirePacket = try! RawWirePacket.fromWireData(cancelWireData)
        let cancelDecrypted = try! await cryptoService.open(
            ciphertext: cancelWirePacket.ciphertext,
            envelope: cancelWirePacket.envelope,
            authTag: cancelWirePacket.authTag,
            using: symmetricKey
        )
        let cancelUpdate = try! MeetingUpdatePayload.deserialize(from: cancelDecrypted)
        guard cancelUpdate.action == MeetingAction.cancel else {
            print("FAILED: Action must be .cancel")
            return false
        }
        
        // Peer applies cancellation
        peerVM.applyInboundUpdate(cancelUpdate)
        guard peerVM.activeMeetingPoint == nil else {
            print("FAILED: Peer meeting point should be cleared upon receiving cancellation")
            return false
        }
        
        print("PASSED: testMeetingPointWireBroadcastWithHigherTTL")
        return true
    }
}

// MARK: - Mock Meeting Transport for UI & Meeting Testing

private actor MockMeetingTransport: PeerTransport {
    var broadcastedPackets: [Data] = []
    
    var inboundPackets: AsyncStream<InboundPacket> {
        AsyncStream { $0.finish() }
    }
    var peerUpdates: AsyncStream<[PeerInfo]> {
        AsyncStream { $0.finish() }
    }
    var stateUpdates: AsyncStream<TransportState> {
        AsyncStream { $0.finish() }
    }
    var transportErrors: AsyncStream<TransportError> {
        AsyncStream { $0.finish() }
    }
    
    func start(serviceType: String, session: GroupSession) async throws {}
    func stop() async {}
    func broadcastPacket(_ data: Data) async throws {
        broadcastedPackets.append(data)
    }
    func sendPacket(_ data: Data, to peerId: String) async throws {}
    func activeDirectPeerCount() async -> Int { 1 }
    func getDiagnostics() async -> TransportDiagnostics {
        TransportDiagnostics(
            localPeerId: "TEST",
            serviceType: "_teekum._tcp",
            sessionName: "Test",
            sessionId: 0x1234,
            state: .connected(peerCount: 1),
            activeDirectPeers: [],
            packetsSent: broadcastedPackets.count,
            packetsReceived: 0,
            obsoletePingsCoalesced: 0,
            sendErrors: 0,
            lastError: nil,
            recentEvents: []
        )
    }
    
    func getLastBroadcast() -> Data? {
        broadcastedPackets.last
    }
    
    func getBroadcastCount() -> Int {
        broadcastedPackets.count
    }
}
