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
    
    @State private var isRunningTests: Bool = false
    @State private var testResultSummary: String?
    @State private var isRunningUITests: Bool = false
    @State private var uiTestResultSummary: String?
    
    public init(sessionViewModel: GroupSessionViewModel, mapViewModel: MapViewModel? = nil) {
        self.sessionViewModel = sessionViewModel
        self.mapViewModel = mapViewModel
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                List {
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
                            LabeledContent("Battery Level", value: String(format: "%.0f%%", locService.currentBatteryLevel * 100))
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
                                        Text(member.status.code.emoji)
                                        Text(member.name).bold()
                                        
                                        if member.status.code.isEmergency {
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
                        LabeledContent("Wire Packet Size", value: "56 Bytes Fixed (Protocol v2)")
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
                    
                    // MARK: - 6. On-Device Verification
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
                    }
                }
                .scrollContentBackground(.hidden)
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
        testResultSummary = "Running 11 tests..."
        
        Task {
            let passed = await LocationPublishingTests.runAllTests()
            await MainActor.run {
                isRunningTests = false
                testResultSummary = passed ? "✓ ALL 11 LOCATION TESTS PASSED" : "✗ SOME TESTS FAILED"
            }
        }
    }
    
    private func runUIVerification() {
        isRunningUITests = true
        uiTestResultSummary = "Running 8 UI tests..."
        
        Task {
            let passed = await UIStateTests.runAllTests()
            await MainActor.run {
                isRunningUITests = false
                uiTestResultSummary = passed ? "✓ ALL 8 UI STATE TESTS PASSED" : "✗ SOME UI TESTS FAILED"
            }
        }
    }
}
