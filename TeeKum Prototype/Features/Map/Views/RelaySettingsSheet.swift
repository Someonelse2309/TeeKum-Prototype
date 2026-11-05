//
//  RelaySettingsSheet.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import SwiftUI

/// Communal Mesh Relay Settings and Battery Policy Control Sheet.
///
/// Gives the user explicit, deliberate control over stranger relaying:
/// - Select between Always Active, Timed (30 Minutes), and Disabled (Off).
/// - Prominently stop relaying and promptly drain queued work.
/// - Live Festival Survival Mode & hardware battery indicator.
/// - Aggregated resource telemetry counters without retaining sensitive location history.
public struct RelaySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let relayPolicyManager: RelayPolicyManager
    let currentBatteryLevel: Float
    let isLowPowerMode: Bool
    
    @State private var policyState: RelayPolicyState = RelayPolicyState(mode: .disabled)
    @State private var telemetry: RelayTelemetry = RelayTelemetry()
    @State private var selectedMode: RelayParticipationMode = .disabled
    
    public init(
        relayPolicyManager: RelayPolicyManager,
        currentBatteryLevel: Float = 1.0,
        isLowPowerMode: Bool = false
    ) {
        self.relayPolicyManager = relayPolicyManager
        self.currentBatteryLevel = currentBatteryLevel
        self.isLowPowerMode = isLowPowerMode
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Status Card Banner
                        statusHeaderCard
                        
                        // Participation Mode Picker
                        modePickerCard
                        
                        // Stop Relaying Action
                        if policyState.mode != .disabled {
                            stopRelayingButton
                        }
                        
                        // Battery & Survival Mode Guard Card
                        batteryGuardCard
                        
                        // Live Resource Telemetry
                        resourceTelemetryCard
                        
                        // Privacy & Battery Guarantees
                        privacyGuaranteesCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Communal Relay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.bold())
                    .foregroundStyle(.green)
                }
            }
            .task {
                while !Task.isCancelled {
                    await refreshState()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Status Header Card
    
    private var statusHeaderCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusIndicatorColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Circle()
                    .stroke(statusIndicatorColor.opacity(0.5), lineWidth: 2)
                    .frame(width: 52, height: 52)
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title2)
                    .foregroundStyle(statusIndicatorColor)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(policyState.statusDescription())
                    .font(.headline.bold())
                    .foregroundStyle(statusIndicatorColor)
                
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            
            Spacer()
        }
        .padding(14)
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(statusIndicatorColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Participation Mode Selector
    
    private var modePickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RELAY PARTICIPATION MODE")
                .font(.caption2.bold())
                .foregroundStyle(.gray)
                .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
                modeOptionRow(
                    mode: .communalRelayActive,
                    title: "Always Active",
                    subtitle: "Relay for nearby festival attendees while battery is ≥20%.",
                    icon: "bolt.fill",
                    color: .green
                )
                
                Divider().background(Color(white: 0.2))
                
                modeOptionRow(
                    mode: .timed30Minutes,
                    title: "Timed (30 Minutes)",
                    subtitle: "Relay for 30 minutes, then automatically pause to preserve power.",
                    icon: "timer",
                    color: .cyan
                )
                
                Divider().background(Color(white: 0.2))
                
                modeOptionRow(
                    mode: .disabled,
                    title: "Disabled (Off)",
                    subtitle: "Never forward stranger packets. Relies on friends and direct links.",
                    icon: "slash.circle",
                    color: .gray
                )
            }
            .padding(14)
            .background(Color(white: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    private func modeOptionRow(
        mode: RelayParticipationMode,
        title: String,
        subtitle: String,
        icon: String,
        color: Color
    ) -> some View {
        Button {
            Task {
                await relayPolicyManager.setParticipationMode(mode)
                await refreshState()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        
                        if policyState.mode == mode {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        }
                    }
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Stop Relaying Promptly Button
    
    private var stopRelayingButton: some View {
        Button {
            Task {
                await relayPolicyManager.stopRelaying()
                await refreshState()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "stop.circle.fill")
                    .font(.headline.bold())
                Text("Stop Relaying & Drain Queued Work")
                    .font(.subheadline.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.red.opacity(0.18))
            .foregroundStyle(.red)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.4), lineWidth: 1)
            )
        }
        .accessibilityLabel("Stop communal relaying")
        .accessibilityHint("Immediately cancels relaying and drains any queued stranger packets.")
    }
    
    // MARK: - Battery & Survival Mode Guard Card
    
    private var batteryGuardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BATTERY & SURVIVAL MODE GUARD")
                .font(.caption2.bold())
                .foregroundStyle(.gray)
                .padding(.horizontal, 4)
            
            VStack(spacing: 10) {
                HStack {
                    Label("Current Battery", systemImage: "battery.100")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(currentBatteryLevel.formattedBatteryPercentage)
                        .font(.subheadline.bold().monospaced())
                        .foregroundStyle(currentBatteryLevel < 0.20 ? .red : .green)
                }
                
                HStack {
                    Label("Low Power Mode", systemImage: "bolt.badge.automatic")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(isLowPowerMode ? "ACTIVE" : "OFF")
                        .font(.subheadline.bold().monospaced())
                        .foregroundStyle(isLowPowerMode ? .yellow : .gray)
                }
                
                HStack {
                    Label("Festival Survival Mode (<20%)", systemImage: "shield.lefthalf.filled")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(policyState.batteryLevel < 0.20 || policyState.isLowPowerModeActive ? "ACTIVE (Throttled)" : "NORMAL")
                        .font(.subheadline.bold().monospaced())
                        .foregroundStyle(policyState.batteryLevel < 0.20 || policyState.isLowPowerModeActive ? .yellow : .green)
                }
            }
            .padding(14)
            .background(Color(white: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    // MARK: - Resource Telemetry Card
    
    private var resourceTelemetryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RELAY RESOURCE BUDGETS & COUNTERS")
                .font(.caption2.bold())
                .foregroundStyle(.gray)
                .padding(.horizontal, 4)
            
            VStack(spacing: 10) {
                telemetryRow(title: "Packets Relayed", value: "\(telemetry.totalPacketsForwarded)")
                telemetryRow(title: "Emergency SOS Forwarded", value: "\(telemetry.totalSOSForwarded)")
                telemetryRow(title: "Rate Limit Throttled (2 pkts/s)", value: "\(telemetry.packetsDroppedRateLimit)")
                telemetryRow(title: "Hop Limit Drops (Max 8)", value: "\(telemetry.packetsDroppedHopLimit)")
                telemetryRow(title: "Duplicates Suppressed (5m LRU)", value: "\(telemetry.duplicatePacketsSuppressed)")
                telemetryRow(title: "Policy & Battery Drops", value: "\(telemetry.packetsDroppedPolicy)")
                
                Divider().background(Color(white: 0.2))
                
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Strictly aggregated counters. Zero location history is retained.")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                .padding(.top, 2)
            }
            .padding(14)
            .background(Color(white: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    private func telemetryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.subheadline.bold().monospaced())
                .foregroundStyle(.cyan)
        }
    }
    
    // MARK: - Privacy & Battery Guarantees Card
    
    private var privacyGuaranteesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THE COMMUNAL MESH COMPACT")
                .font(.caption2.bold())
                .foregroundStyle(.gray)
                .padding(.horizontal, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                bulletPoint(icon: "lock.shield", text: "Zero-Knowledge Encryption: Relays see only 4-byte headers; payloads remain opaque.")
                bulletPoint(icon: "speedometer", text: "2 Retransmissions/Second: Rate-limited ordinary forwarding prevents channel saturation.")
                bulletPoint(icon: "bolt.slash.fill", text: "Hard 20% Cutoff: Stranger forwarding automatically stops at 20% to save battery.")
                bulletPoint(icon: "location.viewfinder", text: "Pocket Background: Runs while locked via Apple's official location indicator.")
            }
            .padding(14)
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    private func bulletPoint(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.green)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }
    
    // MARK: - State Helpers
    
    private func refreshState() async {
        self.policyState = await relayPolicyManager.currentState()
        self.telemetry = await relayPolicyManager.snapshot()
        self.selectedMode = policyState.mode
    }
    
    private var statusIndicatorColor: Color {
        if policyState.isRelayPermitted {
            return Color(red: 0.1, green: 0.9, blue: 0.4) // Green
        } else if policyState.batteryLevel < 0.20 || policyState.isLowPowerModeActive {
            return .yellow
        } else {
            return .gray
        }
    }
    
    private var statusSubtitle: String {
        if policyState.isRelayPermitted {
            if let expiry = policyState.timedExpiryDate {
                let mins = max(1, Int(expiry.timeIntervalSince(Date())) / 60)
                return "Active relaying for community (\(mins) minutes remaining)"
            } else {
                return "Active communal relaying enabled"
            }
        } else if policyState.batteryLevel < 0.20 {
            return "Stranger relaying paused to preserve battery (<20%)"
        } else if policyState.isLowPowerModeActive {
            return "Stranger relaying paused due to Low Power Mode"
        } else if policyState.mode == .timed30Minutes {
            return "30-minute timed relay session expired"
        } else {
            return "Communal relaying is disabled by user"
        }
    }
}
