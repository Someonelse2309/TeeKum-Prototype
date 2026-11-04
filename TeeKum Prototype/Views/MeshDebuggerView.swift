//
//  MeshDebuggerView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 02/11/26.
//

import SwiftUI

/// Full-Screen Mesh Debugger & Diagnostic Lab.
///
/// Features:
/// 1. Dual-Mode Switcher: Live Radio Mode (AWDL / Bonjour) vs Virtual Simulation Mode (Multi-Node Sandbox).
/// 2. Automated 1-Tap Mesh Health Check & Diagnostic Triage Assistant.
/// 3. Interactive Topology Graph with live RSSI, link states, and interactive fault injection.
/// 4. Real-time 56-Byte Wire Packet Capture Stream & Breakdown Inspector.
/// 5. 1-Tap Packet Injector (Valid Pings, SOS, ACKs, and Corrupted / Malformed frames).
/// 6. Exportable Zero-Knowledge Diagnostic Markdown Report.
public struct MeshDebuggerView: View {
    @Environment(\.dismiss) private var dismiss
    @State public var viewModel: MeshDebuggerViewModel
    
    /// Optional closure if displayed as an embedded mode in MainMapView
    var onToggleToNormalMode: (() -> Void)? = nil
    
    @State private var isTriageCardExpanded: Bool = false
    @State private var selectedPacketForDetail: MeshPacketLogItem? = nil
    
    public init(
        viewModel: MeshDebuggerViewModel,
        onToggleToNormalMode: (() -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onToggleToNormalMode = onToggleToNormalMode
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // MARK: - Header Controls & Dual-Mode Picker
                    topControlBar
                    
                    // MARK: - Automated Health Triage Banner
                    triageBanner
                    
                    // MARK: - Tab Bar
                    tabSelectionBar
                    
                    // MARK: - Active Tab Content
                    switch viewModel.selectedTab {
                    case .topology:
                        topologyTabContent
                    case .packets:
                        packetsTabContent
                    case .injector:
                        injectorTabContent
                    case .virtualSandbox:
                        virtualSandboxTabContent
                    }
                }
            }
            .task {
                await viewModel.startObserving()
            }
            .onDisappear {
                viewModel.stopObserving()
            }
            .sheet(item: $selectedPacketForDetail) { packet in
                PacketDetailSheet(packet: packet)
            }
            .overlay(alignment: .bottom) {
                if viewModel.copiedReportNotification {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Diagnostic Report Copied to Clipboard!")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.9))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.green.opacity(0.6), lineWidth: 1))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Top Control Bar
    
    private var topControlBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Return to Normal Map mode toggle if embedded
                if let onToggle = onToggleToNormalMode {
                    Button {
                        onToggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "map.fill")
                            Text("Normal Map")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.2))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }
                }
                
                Text("Mesh Lab")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                
                Spacer()
                
                // Re-run Triage Button
                Button {
                    Task {
                        await viewModel.runAutomatedTriage()
                        await viewModel.refreshLiveNeighbors()
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption.bold())
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                
                // Export Report Button
                Button {
                    _ = viewModel.exportDiagnosticReport()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.bold())
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                
                // Dismiss sheet button
                Button {
                    if let onToggle = onToggleToNormalMode {
                        onToggle()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .foregroundStyle(.gray)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            
            // Mode Segmented Picker
            Picker("Mode", selection: $viewModel.mode) {
                ForEach(DebuggerMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }
        .padding(.bottom, 6)
        .background(Color(white: 0.08))
    }
    
    // MARK: - Automated Health Triage Banner
    
    private var triageBanner: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isTriageCardExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.overallTriageStatus.icon)
                        .foregroundStyle(viewModel.overallTriageStatus.color)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Mesh Triage: \(viewModel.triageSummaryMessage)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        
                        Text(isTriageCardExpanded ? "Tap to collapse" : "Tap for diagnostic health checklist")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isTriageCardExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(viewModel.overallTriageStatus.color.opacity(0.12))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(viewModel.overallTriageStatus.color.opacity(0.3)),
                    alignment: .bottom
                )
            }
            .buttonStyle(.plain)
            
            if isTriageCardExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.triageItems) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.status.icon)
                                .font(.caption2)
                                .foregroundStyle(item.status.color)
                                .padding(.top, 2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("[\(item.category)]")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.gray)
                                    Text(item.title)
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                                
                                Text(item.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                
                                if let remediation = item.remediation {
                                    Text("Fix: \(remediation)")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .padding(.top, 1)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(12)
                .background(Color(white: 0.12))
            }
        }
    }
    
    // MARK: - Tab Selection Bar
    
    private var tabSelectionBar: some View {
        HStack(spacing: 4) {
            ForEach(DebuggerTab.allCases, id: \.self) { tab in
                Button {
                    viewModel.selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.caption.bold())
                            .foregroundStyle(viewModel.selectedTab == tab ? .green : .gray)
                        
                        Rectangle()
                            .fill(viewModel.selectedTab == tab ? Color.green : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }
        }
        .background(Color(white: 0.05))
    }
    
    // MARK: - Tab 1: Topology Graph View
    
    private var topologyTabContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.mode == .liveRadio {
                    liveRadioTopologySection
                } else {
                    virtualSandboxTopologySection
                }
            }
            .padding()
        }
    }
    
    private var liveRadioTopologySection: some View {
        VStack(spacing: 16) {
            // Live Status Card
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Physical Radio Mesh")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text("Bonjour Service: _teekum._tcp (AWDL & BLE)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.gray)
                }
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(viewModel.livePeerCount) Direct Peers")
                        .font(.subheadline.bold())
                        .foregroundStyle(viewModel.livePeerCount > 0 ? .green : .orange)
                    Text("Radio: \(viewModel.transportState != .stopped ? "Active" : "Idle")")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
            .padding()
            .background(Color(white: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Visual Node Graph Canvas
            VStack(spacing: 12) {
                Text("DIRECT 1-HOP RADIO LINKS")
                    .font(.caption.bold())
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if viewModel.liveNeighbors.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.largeTitle)
                            .foregroundStyle(.gray)
                        Text("No direct physical neighbors connected.")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        Text("Place another iPhone running TeeKum nearby with Wi-Fi & Bluetooth ON to establish an AWDL link.")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(Color(white: 0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ForEach(viewModel.liveNeighbors) { neighbor in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(neighbor.isGroupMember ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                                    .frame(width: 44, height: 44)
                                
                                Text(neighbor.id.prefix(3))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(neighbor.isGroupMember ? .green : .blue)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(neighbor.displayName ?? neighbor.id)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                    
                                    Text(neighbor.isGroupMember ? "Group Member" : "Stranger Relay")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(neighbor.isGroupMember ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                                        .foregroundStyle(neighbor.isGroupMember ? .green : .blue)
                                        .clipShape(Capsule())
                                }
                                
                                Text("Link: \(neighbor.state == .connected ? "Connected" : "Degraded") • Last seen \(Date().timeIntervalSince(neighbor.lastSeen), specifier: "%.0f")s ago")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }
                            
                            Spacer()
                            
                            if let rssi = neighbor.rssi {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(rssi) dBm")
                                        .font(.caption.monospaced().bold())
                                        .foregroundStyle(rssi > -70 ? .green : (rssi > -85 ? .orange : .red))
                                    
                                    Text(rssi > -70 ? "Strong" : (rssi > -85 ? "Moderate" : "Weak"))
                                        .font(.caption2)
                                        .foregroundStyle(.gray)
                                }
                            }
                        }
                        .padding()
                        .background(Color(white: 0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
    
    private var virtualSandboxTopologySection: some View {
        VStack(spacing: 16) {
            // Preset Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("VIRTUAL TOPOLOGY PRESET")
                    .font(.caption.bold())
                    .foregroundStyle(.gray)
                
                Picker("Preset", selection: $viewModel.virtualPreset) {
                    ForEach(VirtualTopologyPreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: viewModel.virtualPreset) { _, newPreset in
                    Task {
                        await viewModel.applyVirtualPreset(newPreset)
                    }
                }
                
                Text(viewModel.virtualPreset.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Visual Pipeline of Nodes
            VStack(alignment: .leading, spacing: 12) {
                Text("VIRTUAL NODES & LINK CONTROL")
                    .font(.caption.bold())
                    .foregroundStyle(.gray)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.virtualNodes, id: \.self) { node in
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(node == "ALI" || node == "BOB" ? Color.green.opacity(0.2) : Color.cyan.opacity(0.2))
                                        .frame(width: 50, height: 50)
                                    
                                    Text(node)
                                        .font(.caption.bold())
                                        .foregroundStyle(node == "ALI" || node == "BOB" ? .green : .cyan)
                                }
                                
                                Text(node == "ALI" ? "Sender" : (node == "BOB" ? "Dest" : "Relay"))
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Interactive Link Breaker Controls
                VStack(spacing: 8) {
                    Text("Tap to Toggle Link Status (Simulate Hardware Loss / Cut):")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    ForEach(Array(viewModel.virtualActiveLinks.keys.sorted()), id: \.self) { key in
                        let isUp = viewModel.virtualActiveLinks[key] ?? true
                        let parts = key.split(separator: "-").map { String($0) }
                        if parts.count == 2 {
                            Button {
                                Task {
                                    await viewModel.toggleVirtualLink(nodeA: parts[0], nodeB: parts[1])
                                }
                            } label: {
                                HStack {
                                    Text("\(parts[0]) <-> \(parts[1])")
                                        .font(.caption.monospaced().bold())
                                    Spacer()
                                    Text(isUp ? "LINK ACTIVE (Connected)" : "BROKEN (Disconnected)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(isUp ? .green : .red)
                                }
                                .padding(10)
                                .background(isUp ? Color.green.opacity(0.1) : Color.red.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                
                // Simulation Trigger Buttons
                HStack(spacing: 12) {
                    Button {
                        Task {
                            await viewModel.sendVirtualPing()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "location.fill")
                            Text("Send Virtual Ping")
                        }
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Button {
                        Task {
                            await viewModel.sendVirtualSOS()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Send Virtual SOS")
                        }
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.top, 8)
                
                // Simulation Logs
                if !viewModel.virtualLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SIMULATION EVENT LOG")
                            .font(.caption2.bold())
                            .foregroundStyle(.gray)
                        
                        ForEach(viewModel.virtualLogs.suffix(6), id: \.self) { log in
                            Text("• \(log)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Tab 2: Packet Stream & Inspector View
    
    private var packetsTabContent: some View {
        VStack(spacing: 0) {
            // Filter Pills & Clear Button
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(PacketLogFilter.allCases, id: \.self) { filter in
                            Button {
                                viewModel.packetFilter = filter
                            } label: {
                                Text(filter.rawValue)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(viewModel.packetFilter == filter ? Color.green : Color(white: 0.15))
                                    .foregroundStyle(viewModel.packetFilter == filter ? .black : .white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                
                Button {
                    viewModel.clearPacketLogs()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .padding(6)
                        .background(Color(white: 0.15))
                        .foregroundStyle(.gray)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(white: 0.08))
            
            // Packet List
            let filtered = filteredPackets
            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 40))
                        .foregroundStyle(.gray)
                    Text("No wire packets captured yet.")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                    Text("Transmit a ping or SOS using the Injector tab, or connect another iPhone nearby.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filtered) { packet in
                        Button {
                            selectedPacketForDetail = packet
                        } label: {
                            packetRowView(for: packet)
                        }
                        .listRowBackground(Color(white: 0.06))
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private var filteredPackets: [MeshPacketLogItem] {
        viewModel.packetLogs.filter { item in
            switch viewModel.packetFilter {
            case .all: return true
            case .sos: return item.type == .sos
            case .ping: return item.type == .locationPing
            case .ack: return item.type == .ack
            case .routing: return item.type == .routeReq || item.type == .routeResp
            case .dropped: return item.direction == .dropped || item.dropReason != nil
            }
        }
    }
    
    private func packetRowView(for packet: MeshPacketLogItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: packet.direction.icon)
                    .foregroundStyle(packet.direction.color)
                
                Text(packet.type.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(packet.type == .sos ? .red : .white)
                
                Text("[\(packet.direction.rawValue)]")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                
                Spacer()
                
                Text("\(packet.hopCount)/\(packet.hopLimit) hops")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                
                Text(packet.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.gray)
            }
            
            Text(packet.payloadSummary)
                .font(.caption2.monospaced())
                .foregroundStyle(packet.isDecrypted ? .white : .secondary)
                .lineLimit(2)
            
            HStack {
                Text("From: \(packet.sourcePeer)")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                
                Text("Seq: \(packet.sequenceNumber)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.gray)
                
                if let drop = packet.dropReason {
                    Spacer()
                    Text("DROPPED: \(drop)")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Tab 3: Packet Injector View
    
    private var injectorTabContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Feedback Banner
                if let feedback = viewModel.injectionFeedback {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: feedback.contains("PASS") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(feedback.contains("PASS") ? .green : .red)
                        Text(feedback)
                            .font(.caption.monospaced())
                            .foregroundStyle(.white)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(feedback.contains("PASS") ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                // Section 1: Standard Valid Packets
                VStack(alignment: .leading, spacing: 12) {
                    Text("STANDARD PROTOCOL FRAMES (56 BYTES)")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)
                    
                    Button {
                        Task { await viewModel.injectLocationPing() }
                    } label: {
                        HStack {
                            Image(systemName: "location.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Inject Location Ping (Type 0x01)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text("Normal 30-byte payload + 10-byte cleartext envelope + 16-byte Poly1305 MAC.")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }
                            Spacer()
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(.blue)
                        }
                        .padding()
                        .background(Color(white: 0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button {
                        Task { await viewModel.injectUrgentSOS() }
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Inject Urgent Emergency SOS (Type 0x02)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text("Dispatches to priority outbox lane with max queue priority.")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }
                            Spacer()
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(.red)
                        }
                        .padding()
                        .background(Color.red.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button {
                        Task { await viewModel.injectReceiptACK() }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Inject Receipt ACK (Type 0x06)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text("Simulates friend confirmation acknowledging delivered sequence number.")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }
                            Spacer()
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(.green)
                        }
                        .padding()
                        .background(Color(white: 0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                
                // Section 2: Fault & Security Injection
                VStack(alignment: .leading, spacing: 12) {
                    Text("SECURITY & FAULT INJECTION (VERIFY DROP LOGIC)")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)
                    
                    Button {
                        Task { await viewModel.injectCorruptedAuthTag() }
                    } label: {
                        HStack {
                            Image(systemName: "lock.slash.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tamper Test: Corrupted MAC Auth Tag")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text("Mutates Poly1305 tag byte. Verifies receiver drops frame cryptographically.")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button {
                        Task { await viewModel.injectExceededHopCount() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.title3)
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Boundary Test: Exceeded Hop Limit (9/8)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text("Injects hopCount > hopLimit. Verifies relay terminates forwarding loop.")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button {
                        Task { await viewModel.injectRogueSessionId() }
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.title3)
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Stranger Test: Rogue Session ID (0xBADF00)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text("Injects stranger packet. Verifies zero-knowledge communal blind relay.")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.purple.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Tab 4: Virtual Sandbox View
    
    private var virtualSandboxTabContent: some View {
        virtualSandboxTopologySection
            .padding()
    }
}

// MARK: - 56-Byte Wire Packet Detail Sheet

private struct PacketDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let packet: MeshPacketLogItem
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header Summary
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: packet.direction.icon)
                                    .foregroundStyle(packet.direction.color)
                                Text("\(packet.type.displayName) (\(packet.direction.rawValue))")
                                    .font(.headline.bold())
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("56 Bytes Fixed")
                                    .font(.caption.monospaced().bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            }
                            
                            Text("Captured at \(packet.timestamp.formatted())")
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                        .padding()
                        .background(Color(white: 0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        // Byte Section 1: Cleartext Envelope (10 Bytes)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. CLEARTEXT ENVELOPE (BYTES 0..9)")
                                .font(.caption.bold())
                                .foregroundStyle(.cyan)
                            
                            VStack(spacing: 6) {
                                row(label: "Byte 0 (Version & Type)", value: "Version: \(packet.envelopeSummary.prefix(4)) | Type: \(packet.type.rawValue)")
                                row(label: "Byte 1 (Hop Limit)", value: "\(packet.hopLimit) hops budget")
                                row(label: "Byte 2 (Hop Count)", value: "\(packet.hopCount) traversal hops")
                                row(label: "Bytes 3..5 (Session ID)", value: "0x\(String(format: "%06X", packet.sessionId))")
                                row(label: "Bytes 6..9 (Sequence Number)", value: "\(packet.sequenceNumber)")
                            }
                            .padding()
                            .background(Color(white: 0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        
                        // Byte Section 2: Ciphertext Payload (30 Bytes)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("2. ENCRYPTED PAYLOAD (BYTES 10..39)")
                                .font(.caption.bold())
                                .foregroundStyle(.yellow)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                row(label: "Payload Size", value: "30 Bytes (Fixed)")
                                row(label: "Decryption Status", value: packet.isDecrypted ? "Decrypted (Session Key Match)" : "Zero-Knowledge Ciphertext (Opaque)")
                                
                                Divider().background(Color.gray)
                                
                                Text("Decoded Contents:")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.gray)
                                
                                Text(packet.payloadSummary)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(packet.isDecrypted ? .white : .secondary)
                            }
                            .padding()
                            .background(Color(white: 0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        
                        // Byte Section 3: Auth Tag (16 Bytes)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("3. POLY1305 / AES-GCM MAC TAG (BYTES 40..55)")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                row(label: "MAC Size", value: "16 Bytes (128-bit)")
                                Text("Hex Tag: \(packet.authTagHex.isEmpty ? "Calculated on Transmission" : packet.authTagHex)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.green)
                            }
                            .padding()
                            .background(Color(white: 0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("56-Byte Wire Breakdown")
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
    
    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.gray)
            Spacer()
            Text(value)
                .font(.caption2.monospaced().bold())
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Extension Helper

extension PacketType {
    var displayName: String {
        switch self {
        case .locationPing: return "Location Ping"
        case .sos: return "Emergency SOS"
        case .meetingUpdate: return "Meeting Update"
        case .routeReq: return "Route Request"
        case .routeResp: return "Route Response"
        case .ack: return "Delivery ACK"
        case .chatMessage: return "Group Chat"
        case .uwbTokenExchange: return "UWB Precision Token"
        }
    }
}
