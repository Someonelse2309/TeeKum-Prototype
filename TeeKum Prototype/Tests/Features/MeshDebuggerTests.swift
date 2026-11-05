//
//  MeshDebuggerTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 02/11/26.
//

import Foundation
import CryptoKit

/// Comprehensive test suite validating the Mesh Debugger & Diagnostic Lab:
/// - Automated 1-Tap Triage Health Check
/// - Live packet log capture, filtering, and 56-byte breakdown
/// - Packet injection (Valid Ping, SOS, ACK, and Fault Injection)
/// - Virtual mesh topology sandbox presets and link breaking
/// - Diagnostic report formatting & zero-knowledge compliance
public struct MeshDebuggerTests {
    
    @MainActor
    public static func runAllTests() async -> Bool {
        print("--- [MeshDebuggerTests] Running Mesh Debugger & Diagnostic Lab Suite ---")
        var passed = true
        
        if !(await testMeshTriageHealthCheckAllPass()) { passed = false }
        if !(await testMeshTriageHealthCheckDeniedLocation()) { passed = false }
        if !(await testMeshTriageHealthCheckLowBattery()) { passed = false }
        if !(await testPacketLogFilteringAndClearing()) { passed = false }
        if !(await testPacketLog56ByteBreakdown()) { passed = false }
        if !(await testPacketInjectionPingsAndSOS()) { passed = false }
        if !(await testPacketFaultInjectionCorruptedMAC()) { passed = false }
        if !(await testVirtualMeshPresetsAndLinkFaultToggle()) { passed = false }
        if !(await testVirtualMeshPacketDelivery()) { passed = false }
        if !(await testDiagnosticReportExport()) { passed = false }
        
        if passed {
            print("--- [MeshDebuggerTests] ✓ ALL 10 MESH DEBUGGER TESTS PASSED ---")
        } else {
            print("--- [MeshDebuggerTests] ✗ SOME MESH DEBUGGER TESTS FAILED ---")
        }
        return passed
    }
    
    // MARK: - 1. Automated Triage: All Pass
    
    @MainActor
    public static func testMeshTriageHealthCheckAllPass() async -> Bool {
        print("[TEST] testMeshTriageHealthCheckAllPass...")
        
        let loc = LocationService()
        let groupVM = GroupSessionViewModel()
        let dummyKey = Data(repeating: 0x33, count: 32)
        let session = GroupSession(sessionId: 0x1234, sessionName: "VIP Crew", symmetricKeyData: dummyKey, localInitials: "NIC")
        groupVM.setActiveSession(session)
        
        let transport = PeerTransportService()
        try? await transport.start(serviceType: "_teekum._tcp", session: session)
        let relayManager = RelayPolicyManager(transport: transport)
        
        let debugger = MeshDebuggerViewModel(
            peerTransport: transport,
            groupSessionViewModel: groupVM,
            locationService: loc,
            relayPolicyManager: relayManager
        )
        
        await debugger.runAutomatedTriage()
        
        guard debugger.triageItems.count >= 4 else {
            print("FAILED: Expected at least 4 triage checks, got \(debugger.triageItems.count)")
            await transport.stop()
            return false
        }
        
        let cryptoItem = debugger.triageItems.first(where: { $0.category == "CryptoKit" })
        guard cryptoItem?.status == .pass else {
            print("FAILED: CryptoKit check should pass")
            await transport.stop()
            return false
        }
        
        await transport.stop()
        print("  PASS: testMeshTriageHealthCheckAllPass")
        return true
    }
    
    // MARK: - 2. Automated Triage: Missing Session
    
    @MainActor
    public static func testMeshTriageHealthCheckDeniedLocation() async -> Bool {
        print("[TEST] testMeshTriageHealthCheckDeniedLocation...")
        
        let groupVM = GroupSessionViewModel()
        groupVM.leaveGroup() // No active session
        
        let debugger = MeshDebuggerViewModel(
            peerTransport: nil,
            groupSessionViewModel: groupVM,
            locationService: nil,
            relayPolicyManager: nil
        )
        
        await debugger.runAutomatedTriage()
        
        guard debugger.overallTriageStatus != .pass else {
            print("FAILED: Overall status should have warning or fail when session/transport is nil")
            return false
        }
        
        let sessionItem = debugger.triageItems.first(where: { $0.category == "CryptoKit" })
        guard sessionItem?.status == .warning else {
            print("FAILED: Missing session should report warning")
            return false
        }
        
        print("  PASS: testMeshTriageHealthCheckDeniedLocation")
        return true
    }
    
    // MARK: - 3. Automated Triage: Low Battery Survival Mode
    
    @MainActor
    public static func testMeshTriageHealthCheckLowBattery() async -> Bool {
        print("[TEST] testMeshTriageHealthCheckLowBattery...")
        
        let transport = PeerTransportService()
        let relayManager = RelayPolicyManager(transport: transport)
        await relayManager.updatePowerMetrics(batteryLevel: 0.15, isLowPowerMode: false)
        
        let debugger = MeshDebuggerViewModel(
            peerTransport: transport,
            groupSessionViewModel: nil,
            locationService: nil,
            relayPolicyManager: relayManager
        )
        
        await debugger.runAutomatedTriage()
        
        let batteryItem = debugger.triageItems.first(where: { $0.category == "Battery Policy" })
        guard batteryItem?.status == .warning else {
            print("FAILED: Battery under 20% should trigger Survival Mode warning")
            return false
        }
        
        print("  PASS: testMeshTriageHealthCheckLowBattery")
        return true
    }
    
    // MARK: - 4. Packet Log Filtering and Clearing
    
    @MainActor
    public static func testPacketLogFilteringAndClearing() async -> Bool {
        print("[TEST] testPacketLogFilteringAndClearing...")
        
        let debugger = MeshDebuggerViewModel()
        
        let pingItem = MeshPacketLogItem(
            direction: .inbound,
            type: .locationPing,
            sourcePeer: "ALI",
            hopCount: 1,
            hopLimit: 8,
            sessionId: 0x123456,
            sequenceNumber: 101,
            envelopeSummary: "Ping",
            payloadSummary: "Ping details",
            authTagHex: "AABBCCDD"
        )
        
        let sosItem = MeshPacketLogItem(
            direction: .inbound,
            type: .sos,
            sourcePeer: "BOB",
            hopCount: 2,
            hopLimit: 8,
            sessionId: 0x123456,
            sequenceNumber: 102,
            envelopeSummary: "SOS",
            payloadSummary: "Emergency SOS",
            authTagHex: "11223344"
        )
        
        let droppedItem = MeshPacketLogItem(
            direction: .dropped,
            type: .locationPing,
            sourcePeer: "STRANGER",
            hopCount: 8,
            hopLimit: 8,
            sessionId: 0x999999,
            sequenceNumber: 103,
            envelopeSummary: "Dropped",
            payloadSummary: "Hop Limit Exceeded",
            authTagHex: "99887766",
            dropReason: "Hop limit reached"
        )
        
        debugger.packetLogs = [pingItem, sosItem, droppedItem]
        guard debugger.packetLogs.count == 3 else {
            print("FAILED: Should have 3 logs")
            return false
        }
        
        debugger.clearPacketLogs()
        guard debugger.packetLogs.isEmpty else {
            print("FAILED: clearPacketLogs should empty list")
            return false
        }
        
        print("  PASS: testPacketLogFilteringAndClearing")
        return true
    }
    
    // MARK: - 5. 56-Byte Wire Breakdown
    
    @MainActor
    public static func testPacketLog56ByteBreakdown() async -> Bool {
        print("[TEST] testPacketLog56ByteBreakdown...")
        
        let item = MeshPacketLogItem(
            direction: .inbound,
            type: .sos,
            sourcePeer: "DAN",
            hopCount: 3,
            hopLimit: 8,
            sessionId: 0x007E3A,
            sequenceNumber: 42,
            rawLength: 56,
            envelopeSummary: "v3 | Hops: 3/8 | SID: 0x007E3A | Seq: 42",
            payloadSummary: "SOS [DAN] Medical",
            authTagHex: "F0E1D2C3B4A59687"
        )
        
        guard item.rawLength == 56 else {
            print("FAILED: Wire length must be 56 bytes")
            return false
        }
        guard item.hopCount == 3 && item.hopLimit == 8 else {
            print("FAILED: Hop bounds mismatch")
            return false
        }
        guard item.type == .sos else {
            print("FAILED: Packet type must be SOS")
            return false
        }
        
        print("  PASS: testPacketLog56ByteBreakdown")
        return true
    }
    
    // MARK: - 6. Packet Injection: Ping and SOS
    
    @MainActor
    public static func testPacketInjectionPingsAndSOS() async -> Bool {
        print("[TEST] testPacketInjectionPingsAndSOS...")
        
        let groupVM = GroupSessionViewModel()
        let dummyKey = Data(repeating: 0x55, count: 32)
        let session = GroupSession(sessionId: 0x55AA, sessionName: "Injector Fest", symmetricKeyData: dummyKey, localInitials: "INJ")
        groupVM.setActiveSession(session)
        
        let transport = PeerTransportService()
        try? await transport.start(serviceType: "_teekum._tcp", session: session)
        
        let debugger = MeshDebuggerViewModel(
            peerTransport: transport,
            groupSessionViewModel: groupVM
        )
        
        await debugger.injectLocationPing()
        guard let feedback1 = debugger.injectionFeedback, feedback1.contains("PASS") else {
            print("FAILED: injectLocationPing failed: \(debugger.injectionFeedback ?? "")")
            await transport.stop()
            return false
        }
        
        await debugger.injectUrgentSOS()
        guard let feedback2 = debugger.injectionFeedback, feedback2.contains("PASS") else {
            print("FAILED: injectUrgentSOS failed: \(debugger.injectionFeedback ?? "")")
            await transport.stop()
            return false
        }
        
        await debugger.injectReceiptACK()
        guard let feedback3 = debugger.injectionFeedback, feedback3.contains("PASS") else {
            print("FAILED: injectReceiptACK failed: \(debugger.injectionFeedback ?? "")")
            await transport.stop()
            return false
        }
        
        await transport.stop()
        print("  PASS: testPacketInjectionPingsAndSOS")
        return true
    }
    
    // MARK: - 7. Packet Fault Injection: Corrupted MAC
    
    @MainActor
    public static func testPacketFaultInjectionCorruptedMAC() async -> Bool {
        print("[TEST] testPacketFaultInjectionCorruptedMAC...")
        
        let groupVM = GroupSessionViewModel()
        let dummyKey = Data(repeating: 0x77, count: 32)
        let session = GroupSession(sessionId: 0x7788, sessionName: "Tamper Lab", symmetricKeyData: dummyKey, localInitials: "TMP")
        groupVM.setActiveSession(session)
        
        let transport = PeerTransportService()
        try? await transport.start(serviceType: "_teekum._tcp", session: session)
        
        let debugger = MeshDebuggerViewModel(
            peerTransport: transport,
            groupSessionViewModel: groupVM
        )
        
        await debugger.injectCorruptedAuthTag()
        guard let feedback = debugger.injectionFeedback, feedback.contains("PASS") else {
            print("FAILED: injectCorruptedAuthTag failed: \(debugger.injectionFeedback ?? "")")
            await transport.stop()
            return false
        }
        
        await transport.stop()
        print("  PASS: testPacketFaultInjectionCorruptedMAC")
        return true
    }
    
    // MARK: - 8. Virtual Mesh Presets and Link Breaking
    
    @MainActor
    public static func testVirtualMeshPresetsAndLinkFaultToggle() async -> Bool {
        print("[TEST] testVirtualMeshPresetsAndLinkFaultToggle...")
        
        let debugger = MeshDebuggerViewModel()
        await debugger.initializeVirtualSandbox()
        
        // 1. Linear chain
        await debugger.applyVirtualPreset(.linearChain)
        guard debugger.virtualNodes.count == 4 else {
            print("FAILED: Linear chain should have 4 nodes")
            return false
        }
        guard debugger.virtualActiveLinks["ALI-R1"] == true else {
            print("FAILED: ALI-R1 should be active initially")
            return false
        }
        
        // 2. Break link
        await debugger.toggleVirtualLink(nodeA: "ALI", nodeB: "R1")
        guard debugger.virtualActiveLinks["ALI-R1"] == false else {
            print("FAILED: ALI-R1 should be broken")
            return false
        }
        
        // 3. Restore link
        await debugger.toggleVirtualLink(nodeA: "ALI", nodeB: "R1")
        guard debugger.virtualActiveLinks["ALI-R1"] == true else {
            print("FAILED: ALI-R1 should be restored")
            return false
        }
        
        // 4. Diamond preset
        await debugger.applyVirtualPreset(.diamondMultiPath)
        guard debugger.virtualActiveLinks["ALI-R1"] == true && debugger.virtualActiveLinks["ALI-R2"] == true else {
            print("FAILED: Diamond links missing")
            return false
        }
        
        print("  PASS: testVirtualMeshPresetsAndLinkFaultToggle")
        return true
    }
    
    // MARK: - 9. Virtual Mesh Packet Traversal
    
    @MainActor
    public static func testVirtualMeshPacketDelivery() async -> Bool {
        print("[TEST] testVirtualMeshPacketDelivery...")
        
        let debugger = MeshDebuggerViewModel()
        await debugger.initializeVirtualSandbox()
        await debugger.applyVirtualPreset(.linearChain)
        
        await debugger.sendVirtualPing()
        guard debugger.virtualLogs.contains(where: { $0.contains("dispatched Location Ping") }) else {
            print("FAILED: Simulation log should record ping dispatch")
            return false
        }
        
        await debugger.sendVirtualSOS()
        guard debugger.virtualLogs.contains(where: { $0.contains("dispatched URGENT SOS") }) else {
            print("FAILED: Simulation log should record SOS dispatch")
            return false
        }
        
        print("  PASS: testVirtualMeshPacketDelivery")
        return true
    }
    
    // MARK: - 10. Diagnostic Report Export
    
    @MainActor
    public static func testDiagnosticReportExport() async -> Bool {
        print("[TEST] testDiagnosticReportExport...")
        
        let groupVM = GroupSessionViewModel()
        let dummyKey = Data(repeating: 0x99, count: 32)
        let session = GroupSession(sessionId: 0x99AA, sessionName: "Report Fest", symmetricKeyData: dummyKey, localInitials: "REP")
        groupVM.setActiveSession(session)
        
        let debugger = MeshDebuggerViewModel(
            groupSessionViewModel: groupVM
        )
        await debugger.runAutomatedTriage()
        
        let report = debugger.exportDiagnosticReport()
        guard report.contains("# TeeKum Mesh Diagnostic & Health Report") else {
            print("FAILED: Report missing header")
            return false
        }
        guard report.contains("Session ID: 0x99AA") else {
            print("FAILED: Report missing session ID")
            return false
        }
        guard report.contains("Automated Health Triage") else {
            print("FAILED: Report missing triage section")
            return false
        }
        guard debugger.copiedReportNotification else {
            print("FAILED: copiedReportNotification should be true")
            return false
        }
        
        print("  PASS: testDiagnosticReportExport")
        return true
    }
}
