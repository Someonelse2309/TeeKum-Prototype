//
//  DiagnosticsView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI
import CoreLocation

/// On-Device Diagnostics Sheet (Debug HUD) displaying live radio telemetry,
/// connected peer metrics, location permissions, packet counts, and relevant errors.
public struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var sessionViewModel: GroupSessionViewModel
    var mapViewModel: MapViewModel?
    var sosViewModel: SOSViewModel?
    var relayPolicyManager: RelayPolicyManager?
    var peerTransport: PeerTransportService?
    
    @State private var isShowingMeshDebugger: Bool = false
    @State private var isRunningTests: Bool = false
    @State private var testResultSummary: String?
    @State private var isRunningUITests: Bool = false
    @State private var uiTestResultSummary: String?
    @State private var isRunningSOSTests: Bool = false
    @State private var sosTestResultSummary: String?
    @State private var isRunningRelayTests: Bool = false
    @State private var relayTestResultSummary: String?
    @State private var isRunningMeshFailureTests: Bool = false
    @State private var meshFailureTestSummary: String?
    @State private var isRunningDebuggerTests: Bool = false
    @State private var debuggerTestSummary: String?
    @State private var isRunningChatEngineTests: Bool = false
    @State private var chatEngineTestResultSummary: String?
    @State private var isRunningChatUITests: Bool = false
    @State private var chatUITestResultSummary: String?
    @State private var relayState: RelayPolicyState?
    @State private var relayTelemetry: RelayTelemetry?
    
    public init(
        sessionViewModel: GroupSessionViewModel,
        mapViewModel: MapViewModel? = nil,
        sosViewModel: SOSViewModel? = nil,
        relayPolicyManager: RelayPolicyManager? = nil,
        peerTransport: PeerTransportService? = nil
    ) {
        self.sessionViewModel = sessionViewModel
        self.mapViewModel = mapViewModel
        self.sosViewModel = sosViewModel
        self.relayPolicyManager = relayPolicyManager
        self.peerTransport = peerTransport
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                List {
                    // MARK: - 0. Full Mesh Debugger & Lab
                    Section {
                        Button {
                            isShowingMeshDebugger = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform.path.badge.gearshape")
                                    .font(.title2)
                                    .foregroundStyle(.yellow)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Open Mesh Debugger & Lab")
                                        .font(.headline.bold())
                                        .foregroundStyle(.white)
                                    Text("Interactive topology canvas, 56-byte wire packet inspector, packet injector, and virtual multi-node sandbox.")
                                        .font(.caption2)
                                        .foregroundStyle(.gray)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    // MARK: - 1. Active Session & Key Fingerprint
                    Section("Active Cryptographic Session") {
                        if let session = sessionViewModel.activeSession {
                            LabeledContent("Session Name", value: session.sessionName)
                            LabeledContent("Session ID", value: String(format: "0x%04X", session.sessionId))
                            LabeledContent("Local Initials", value: session.localInitials)
                            LabeledContent("Key Fingerprint") {
                                Text("0x\(session.symmetricKeyData.prefix(4).map { String(format: "%02hhx", $0) }.joined().uppercased())")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.green)
                            }
                        } else {
                            Text("No active session.")
                                .foregroundStyle(.gray)
                        }
                    }
                    
                    // MARK: - 2. Location Permissions & GPS Telemetry
                    Section("Location Permissions & Hardware State") {
                        if let locService = mapViewModel?.locationService {
                            LabeledContent("Authorization Status") {
                                Text(authorizationDescription(locService.authorizationStatus))
                                    .bold()
                                    .foregroundStyle(authorizationColor(locService.authorizationStatus))
                            }
                            
                            LabeledContent("GPS Availability") {
                                Text(locService.isGPSAvailable ? "Active Hardware Fix" : "Unavailable / Weak")
                                    .foregroundStyle(locService.isGPSAvailable ? .green : .red)
                            }
                            
                            if let acc = mapViewModel?.horizontalAccuracy {
                                LabeledContent("Horizontal Accuracy", value: String(format: "±%.1f meters", acc))
                            } else {
                                LabeledContent("Horizontal Accuracy", value: "No GPS fix")
                            }
                            
                            if let age = mapViewModel?.locationAge {
                                LabeledContent("Measurement Age") {
                                    Text(String(format: "%.1f s ago", age))
                                        .foregroundStyle((mapViewModel?.isLocationStale ?? false) ? .orange : .green)
                                }
                            }
                            
                            LabeledContent("Freshness State") {
                                Text((mapViewModel?.isLocationStale ?? false) ? "STALE FIX (>30s)" : "FRESH (<30s)")
                                    .bold()
                                    .foregroundStyle((mapViewModel?.isLocationStale ?? false) ? .orange : .green)
                            }
                            
                            LabeledContent("Motion State", value: locService.isStationary ? "Stationary (GPS Asleep via CoreMotion)" : "Moving (High Accuracy GPS)")
                            LabeledContent("Publishing Cadence", value: String(format: "%.1f s interval", locService.currentCadenceInterval))
                            LabeledContent("Battery Level", value: locService.currentBatteryLevel.formattedBatteryPercentage)
                            LabeledContent("Survival Mode (<20%)") {
                                Text(locService.isSurvivalModeActive ? "ACTIVE (Throttled)" : "Normal")
                                    .bold()
                                    .foregroundStyle(locService.isSurvivalModeActive ? .yellow : .green)
                            }
                        } else {
                            Text("Location service not attached.")
                                .foregroundStyle(.gray)
                        }
                    }
                    
                    // MARK: - 3. Peer Connectivity
                    Section("Peer Connectivity (\(sessionViewModel.members.count) Active)") {
                        if sessionViewModel.members.isEmpty {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundStyle(.gray)
                                Text("Searching for nearby peers over AWDL / Wi-Fi Direct...")
                                    .font(.footnote)
                                    .foregroundStyle(.gray)
                            }
                            .padding(.vertical, 4)
                        } else {
                            ForEach(sessionViewModel.members) { member in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Circle()
                                            .fill(member.color.swiftUIColor)
                                            .frame(width: 8, height: 8)
                                        Text(member.name).bold()
                                        
                                        if member.isEmergency {
                                            Text("SOS ACTIVE")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.red)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.red.opacity(0.2))
                                                .clipShape(Capsule())
                                        }
                                        
                                        Spacer()
                                        
                                        if let rssi = member.rssi {
                                            Text("\(rssi) dBm")
                                                .font(.caption.monospaced().bold())
                                                .foregroundStyle(rssi > -70 ? .green : .orange)
                                        }
                                    }
                                    
                                    HStack {
                                        Text(member.isDirectPeer ? "Direct 1-Hop Radio" : "Mesh Relay")
                                            .font(.caption2)
                                            .foregroundStyle(.gray)
                                        
                                        Text("•")
                                            .font(.caption2)
                                            .foregroundStyle(.gray)
                                        
                                        if let coord = member.coordinate {
                                            Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.green)
                                        } else {
                                            Text("Awaiting GPS Fix")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }
                                        
                                        Spacer()
                                        
                                        Text(member.isStale(threshold: 60) ? "Stale" : "Live")
                                            .font(.caption2.bold())
                                            .foregroundStyle(member.isStale(threshold: 60) ? .orange : .green)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    
                    // MARK: - 4. Radio Transport & Packet Counts
                    Section("Radio Telemetry & Packet Statistics") {
                        LabeledContent("Transport Mode", value: "Apple Network.framework P2P")
                        LabeledContent("Link Layer", value: "AWDL / Wi-Fi Direct & BLE")
                        LabeledContent("Bonjour Service", value: "_teekum._tcp")
                        LabeledContent("Wire Packet Size", value: "56 Bytes Fixed (Protocol v3)")
                        LabeledContent("Outer Envelope", value: "10 Bytes (Cleartext Routing)")
                        LabeledContent("Payload Cipher", value: "30 Bytes (ChaCha20-Poly1305)")
                        LabeledContent("Auth Tag (MAC)", value: "16 Bytes (Tamper Detection)")
                    }
                    
                    // MARK: - 5. System Health & Relevant Errors
                    Section("System Health & Error Diagnostics") {
                        if let error = sessionViewModel.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text("Session Error: \(error)")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        } else {
                            HStack {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(.green)
                                Text("No Session or Transport Errors")
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                            }
                        }
                        
                        LabeledContent("Replay Filter", value: "5-Minute LRU Cache Active")
                        LabeledContent("Zero-Knowledge Relay", value: "Enabled (Relays cannot read payloads)")
                    }
                    
                    // MARK: - 5B. Communal Relay & Battery Policy (Agent 5)
                    Section("Communal Relay & Battery Policy") {
                        if let state = relayState {
                            LabeledContent("Participation Mode", value: state.mode.rawValue)
                            LabeledContent("Relay Status") {
                                Text(state.statusDescription())
                                    .bold()
                                    .foregroundStyle(state.isRelayPermitted ? .green : .yellow)
                            }
                            LabeledContent("Hard 20% Cutoff") {
                                Text(state.batteryLevel < 0.20 || state.isLowPowerModeActive ? "ACTIVE (Throttled)" : "NORMAL (Permitted)")
                                    .bold()
                                    .foregroundStyle(state.batteryLevel < 0.20 || state.isLowPowerModeActive ? .yellow : .green)
                            }
                            if let expiry = state.timedExpiryDate {
                                let mins = max(0, Int(expiry.timeIntervalSince(Date())) / 60)
                                LabeledContent("30m Timed Session", value: "\(mins) min remaining")
                            }
                        } else {
                            Text("Relay policy manager not attached.")
                                .foregroundStyle(.gray)
                        }
                        
                        if let tele = relayTelemetry {
                            LabeledContent("Packets Relayed", value: "\(tele.totalPacketsForwarded)")
                            LabeledContent("SOS Forwarded", value: "\(tele.totalSOSForwarded)")
                            LabeledContent("Rate Limit Throttled (2 pkts/s)", value: "\(tele.packetsDroppedRateLimit)")
                            LabeledContent("Hop Limit Drops (Max 8)", value: "\(tele.packetsDroppedHopLimit)")
                            LabeledContent("Policy & Battery Drops", value: "\(tele.packetsDroppedPolicy)")
                            LabeledContent("Duplicates Suppressed", value: "\(tele.duplicatePacketsSuppressed)")
                        }
                    }
                    
                    // MARK: - 5C. Phase 2 Mesh Failure & Convergence Telemetry (Agent 6)
                    Section("Phase 2 Mesh Failure & Observability (Agent 6)") {
                        LabeledContent("Mesh Fault Simulator", value: "Multi-Node Deterministic Harness Active")
                        LabeledContent("Simulated Failure Models", value: "Loss, Latency, Duplication, Competing Routes")
                        LabeledContent("Forwarding Verification", value: "8-Hop Bounded Flooding & AODV Monotonicity")
                        LabeledContent("Queue Saturation Guard", value: "Urgent: 16 pkts | Relay: 32 pkts Ring Buffer")
                        LabeledContent("Rate Limit Policy", value: "Ordinary: 2 pkts/s | SOS Priority: 4 pkts/s")
                        LabeledContent("Zero-Knowledge Telemetry") {
                            Text("ACTIVE (0 GPS / 0 Keys)")
                                .bold()
                                .foregroundStyle(.green)
                        }
                    }
                    
                    // MARK: - 6. Emergency SOS & Multi-Hop Relay Diagnostics
                    Section("Emergency SOS & Multi-Hop Diagnostics") {
                        if let sos = sosViewModel {
                            let diag = sos.diagnostics
                            LabeledContent("Delivery State", value: sos.deliveryState.title)
                            LabeledContent("Ack Stage", value: diag.stage.rawValue)
                            LabeledContent("Route Choice", value: diag.routeChoice.description)
                            if let eventId = diag.eventId {
                                LabeledContent("Active Event ID", value: String(format: "0x%08X", eventId))
                            }
                            LabeledContent("Retries Attempted", value: "\(diag.retryCount) / \(sos.maxRetries)")
                            if let friend = diag.lastDeliveredFriendId {
                                LabeledContent("Friend Delivery Confirmed") {
                                    Text("\(friend) (\(diag.hopCount ?? 0) hops)")
                                        .bold()
                                        .foregroundStyle(.green)
                                }
                            }
                            if let relay = diag.lastRelayResponderId {
                                LabeledContent("Intermediary Relay Ack") {
                                    Text("\(relay) (\(sos.lastRelayHopCount ?? 0) hops)")
                                        .foregroundStyle(.yellow)
                                }
                            }
                            LabeledContent("Duplicates Suppressed", value: "\(sos.totalDuplicatesSuppressedCount)")
                            LabeledContent("Dispatched SOS Count", value: "\(sos.totalDispatchedSOSCount)")
                            LabeledContent("Received SOS Count", value: "\(sos.totalReceivedSOSCount)")
                            LabeledContent("Siren Audio Active") {
                                Text(sos.isSirenActive ? "ACTIVE (Audible)" : "Silent")
                                    .foregroundStyle(sos.isSirenActive ? .red : .gray)
                            }
                        } else {
                            Text("SOS ViewModel not attached.")
                                .foregroundStyle(.gray)
                        }
                    }
                    
                    // MARK: - 7. On-Device Verification
                    Section("On-Device Verification Suites") {
                        Button {
                            runLocationVerification()
                        } label: {
                            HStack {
                                Text("Run Location Verification Suite")
                                Spacer()
                                if isRunningTests {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRunningTests)
                        
                        if let summary = testResultSummary {
                            Text(summary)
                                .font(.caption.monospaced())
                                .foregroundStyle(summary.contains("PASSED") ? .green : .red)
                        }
                        
                        Button {
                            runUIVerification()
                        } label: {
                            HStack {
                                Text("Run UI State Verification Suite")
                                Spacer()
                                if isRunningUITests {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRunningUITests)
                        
                        if let uiSummary = uiTestResultSummary {
                            Text(uiSummary)
                                .font(.caption.monospaced())
                                .foregroundStyle(uiSummary.contains("PASSED") ? .green : .red)
                        }
                        
                        Button {
                            runSOSVerification()
                        } label: {
                            HStack {
                                Text("Run Multi-Hop SOS Verification Suite")
                                Spacer()
                                if isRunningSOSTests {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRunningSOSTests)
                        
                        if let sosSummary = sosTestResultSummary {
                            Text(sosSummary)
                                .font(.caption.monospaced())
                                .foregroundStyle(sosSummary.contains("PASSED") ? .green : .red)
                        }
                        
                        Button {
                            runRelayVerification()
                        } label: {
                            HStack {
                                Text("Run Relay & Battery Policy Suite (Agent 5)")
                                Spacer()
                                if isRunningRelayTests {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRunningRelayTests)
                        
                        if let relaySummary = relayTestResultSummary {
                            Text(relaySummary)
                                .font(.caption.monospaced())
                                .foregroundStyle(relaySummary.contains("PASSED") ? .green : .red)
                        }
                        
                        Button {
                            runMeshFailureVerification()
                        } label: {
                            HStack {
                                Text("Run Mesh Failure Suite (Agent 6)")
                                Spacer()
                                if isRunningMeshFailureTests {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRunningMeshFailureTests)
                        
                        if let meshSummary = meshFailureTestSummary {
                            Text(meshSummary)
                                .font(.caption.monospaced())
                                .foregroundStyle(meshSummary.contains("PASSED") ? .green : .red)
                        }
                        
                        Button {
                            runMeshDebuggerVerification()
                        } label: {
                            HStack {
                                Text("Run Mesh Debugger & Lab Suite")
                                Spacer()
                                if isRunningDebuggerTests {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRunningDebuggerTests)
                        
                        if let debuggerSummary = debuggerTestSummary {
                            Text(debuggerSummary)
                                .font(.caption.monospaced())
                                .foregroundStyle(debuggerSummary.contains("PASSED") ? .green : .red)
                        }
                        
                        Button {
                            runChatEngineVerification()
                        } label: {
                            HStack {
                                Text("Run Group Chat Messaging & Mesh Suite (Agent 2)")
                                Spacer()
                                if isRunningChatEngineTests {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRunningChatEngineTests)
                        
                        if let chatEngineSummary = chatEngineTestResultSummary {
                            Text(chatEngineSummary)
                                .font(.caption.monospaced())
                                .foregroundStyle(chatEngineSummary.contains("PASSED") ? .green : .red)
                        }
                        
                        Button {
                            runChatUIVerification()
                        } label: {
                            HStack {
                                Text("Run Group Chat UI & ViewModel Suite (Agent 3)")
                                Spacer()
                                if isRunningChatUITests {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRunningChatUITests)
                        
                        if let chatSummary = chatUITestResultSummary {
                            Text(chatSummary)
                                .font(.caption.monospaced())
                                .foregroundStyle(chatSummary.contains("PASSED") ? .green : .red)
                        }
                        
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .task {
                await loadRelayData()
            }
            .navigationTitle("Diagnostics HUD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .sheet(isPresented: $isShowingMeshDebugger) {
                MeshDebuggerView(
                    viewModel: MeshDebuggerViewModel(
                        peerTransport: peerTransport,
                        groupSessionViewModel: sessionViewModel,
                        locationService: mapViewModel?.locationService,
                        relayPolicyManager: relayPolicyManager
                    )
                )
            }
        }
    }
    
    private func authorizationDescription(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways:
            return "Authorized Always"
        case .authorizedWhenInUse:
            return "Authorized When In Use"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
        @unknown default:
            return "Unknown"
        }
    }
    
    private func authorizationColor(_ status: CLAuthorizationStatus) -> Color {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }
    
    private func runLocationVerification() {
        isRunningTests = true
        testResultSummary = "Running 15 tests..."
        
        Task {
            let passed = await LocationPublishingTests.runAllTests()
            await MainActor.run {
                isRunningTests = false
                testResultSummary = passed ? "✓ ALL 15 LOCATION TESTS PASSED" : "✗ SOME TESTS FAILED"
            }
        }
    }
    
    private func runUIVerification() {
        isRunningUITests = true
        uiTestResultSummary = "Running 13 UI tests..."
        
        Task {
            let passed = await UIStateTests.runAllTests()
            await MainActor.run {
                isRunningUITests = false
                uiTestResultSummary = passed ? "✓ ALL 13 UI STATE TESTS PASSED" : "✗ SOME UI TESTS FAILED"
            }
        }
    }
    
    private func runSOSVerification() {
        isRunningSOSTests = true
        sosTestResultSummary = "Running 22 multi-hop SOS tests..."
        
        Task {
            let p1 = await SOSEndToEndTests.runAllTests()
            let p2 = await MultiHopSOSTests.runAllTests()
            let passed = p1 && p2
            await MainActor.run {
                isRunningSOSTests = false
                sosTestResultSummary = passed ? "✓ ALL 22 SOS TESTS PASSED" : "✗ SOME SOS TESTS FAILED"
            }
        }
    }
    
    private func loadRelayData() async {
        guard let manager = relayPolicyManager else { return }
        self.relayState = await manager.currentState()
        self.relayTelemetry = await manager.snapshot()
    }
    
    private func runRelayVerification() {
        isRunningRelayTests = true
        relayTestResultSummary = "Running 12 relay & battery policy tests..."
        
        Task {
            let passed = await RelayPolicyTests.runAllTests()
            await MainActor.run {
                isRunningRelayTests = false
                relayTestResultSummary = passed ? "✓ ALL 12 RELAY POLICY TESTS PASSED" : "✗ SOME TESTS FAILED"
            }
            await loadRelayData()
        }
    }
    
    private func runMeshFailureVerification() {
        isRunningMeshFailureTests = true
        meshFailureTestSummary = "Running 12 mesh failure & convergence tests..."
        
        Task {
            let passed = await MeshFailureIntegrationTests.runAllTests()
            await MainActor.run {
                isRunningMeshFailureTests = false
                meshFailureTestSummary = passed ? "✓ ALL 12 MESH FAILURE TESTS PASSED" : "✗ SOME MESH FAILURE TESTS FAILED"
            }
            await loadRelayData()
        }
    }
    
    private func runMeshDebuggerVerification() {
        isRunningDebuggerTests = true
        debuggerTestSummary = "Running 10 mesh debugger tests..."
        
        Task {
            let passed = await MeshDebuggerTests.runAllTests()
            await MainActor.run {
                isRunningDebuggerTests = false
                debuggerTestSummary = passed ? "✓ ALL 10 MESH DEBUGGER TESTS PASSED" : "✗ SOME TESTS FAILED"
            }
        }
    }
    
    private func runChatEngineVerification() {
        isRunningChatEngineTests = true
        chatEngineTestResultSummary = "Running 16 Chat Engine tests..."
        
        Task {
            let passed = await ChatMessagingEngineTests.runAllTests()
            await MainActor.run {
                isRunningChatEngineTests = false
                chatEngineTestResultSummary = passed ? "✓ ALL 16 CHAT ENGINE TESTS PASSED" : "✗ SOME TESTS FAILED"
            }
        }
    }
    
    private func runChatUIVerification() {
        isRunningChatUITests = true
        chatUITestResultSummary = "Running 11 Chat UI tests..."
        
        Task {
            let passed = await ChatUITests.runAllTests()
            await MainActor.run {
                isRunningChatUITests = false
                chatUITestResultSummary = passed ? "✓ ALL 11 CHAT UI TESTS PASSED" : "✗ SOME TESTS FAILED"
            }
        }
    }
}
