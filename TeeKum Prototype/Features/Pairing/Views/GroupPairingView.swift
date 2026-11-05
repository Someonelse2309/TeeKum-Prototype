//
//  GroupPairingView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI

/// Comprehensive Group Pairing & Formation View:
/// - Supports 1 to 3-letter initials (e.g. "D", "AB", "DNA")
/// - Create Group: Generates serverless 256-bit key & QR barcode for friends to scan on-site
/// - Scan to Join: Native camera QR barcode scanner to join a host's private group
/// - Open Mesh: 1-tap auto-mesh connecting to all nearby peers on default festival channel
public struct GroupPairingView: View {
    @Bindable var sessionViewModel: GroupSessionViewModel
    var relayPolicyManager: RelayPolicyManager?
    var peerTransport: PeerTransportService?
    
    @State private var selectedTab: PairingTab = .create
    @State private var initialsInput: String = ""
    @State private var selectedColor: MemberColor = .skyBlue
    @State private var groupNameInput: String = "Festival Crew"
    @State private var createdSession: GroupSession?
    @State private var pendingAgreement: PendingAgreementAction? = nil
    @State private var isShowingMeshDebugger: Bool = false
    @FocusState private var isFieldFocused: Bool
    
    public init(
        sessionViewModel: GroupSessionViewModel,
        relayPolicyManager: RelayPolicyManager? = nil,
        peerTransport: PeerTransportService? = nil
    ) {
        self.sessionViewModel = sessionViewModel
        self.relayPolicyManager = relayPolicyManager
        self.peerTransport = peerTransport
    }
    
    enum PendingAgreementAction: Identifiable {
        case create(name: String, initials: String)
        case join(invite: GroupSessionInvite, initials: String)
        case autoMesh(initials: String)
        
        var id: String {
            switch self {
            case .create(let name, let initials):
                return "create-\(name)-\(initials)"
            case .join(let invite, let initials):
                return "join-\(invite.sessionId)-\(initials)"
            case .autoMesh(let initials):
                return "automesh-\(initials)"
            }
        }
        
        var context: MeshAgreementView.AgreementContext {
            switch self {
            case .create(let name, let initials):
                return .create(groupName: name, initials: initials)
            case .join(let invite, let initials):
                return .join(groupName: invite.sessionName, initials: initials)
            case .autoMesh(let initials):
                return .autoMesh(initials: initials)
            }
        }
    }
    
    enum PairingTab: String, CaseIterable {
        case create = "Create Group"
        case join = "Scan to Join"
    }
    
    private var cleanInitials: String {
        initialsInput
            .uppercased()
            .filter { $0 >= "A" && $0 <= "Z" }
    }
    
    private var isInitialsValid: Bool {
        cleanInitials.count >= 1 && cleanInitials.count <= 3
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerView
                        
                        // User Initials Input Card (Required across all modes)
                        initialsCard
                        
                        // Tab Selector
                        Picker("Mode", selection: $selectedTab) {
                            ForEach(PairingTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
                        // Tab Content
                        switch selectedTab {
                        case .create:
                            createGroupSection
                        case .join:
                            scanToJoinSection
                        }
                        
                        // Error message banner
                        if let error = sessionViewModel.errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding()
                            .background(Color.red.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("TeeKum Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingMeshDebugger = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform.path.badge.gearshape")
                            Text("Mesh Lab")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(.yellow)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if createdSession != nil {
                        Button("Reset") {
                            createdSession = nil
                            sessionViewModel.resetSessionState()
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)
                    }
                }
            }
            .sheet(isPresented: $isShowingMeshDebugger) {
                MeshDebuggerView(
                    viewModel: MeshDebuggerViewModel(
                        peerTransport: peerTransport,
                        groupSessionViewModel: sessionViewModel,
                        relayPolicyManager: relayPolicyManager
                    )
                )
            }
            .onAppear {
                if !sessionViewModel.localUserName.isEmpty && initialsInput.isEmpty {
                    initialsInput = sessionViewModel.localUserName
                }
                if sessionViewModel.localColor != .unset {
                    selectedColor = sessionViewModel.localColor
                } else if !initialsInput.isEmpty {
                    selectedColor = MemberColor.deterministicColor(for: initialsInput)
                }
            }
            .sheet(item: $pendingAgreement) { action in
                MeshAgreementView(
                    context: action.context,
                    onAgree: {
                        // Persist user opt-in to Communal Mesh Compact (Agent 5)
                        UserDefaults.standard.set(RelayParticipationMode.communalRelayActive.rawValue, forKey: "com.teekum.relay.participationMode")
                        if let manager = relayPolicyManager {
                            Task {
                                await manager.setParticipationMode(.communalRelayActive)
                            }
                        }
                        switch action {
                        case .create(let name, let initials):
                            executeCreateGroup(name: name, initials: initials)
                        case .join(let invite, let initials):
                            sessionViewModel.joinGroup(invite: invite, localName: initials, colorCode: selectedColor.rawValue)
                            sessionViewModel.pendingInvite = nil
                        case .autoMesh(let initials):
                            sessionViewModel.enterAutoMesh(initials: initials, colorCode: selectedColor.rawValue)
                        }
                        pendingAgreement = nil
                    },
                    onDecline: {
                        UserDefaults.standard.set(RelayParticipationMode.disabled.rawValue, forKey: "com.teekum.relay.participationMode")
                        if let manager = relayPolicyManager {
                            Task {
                                await manager.stopRelaying()
                            }
                        }
                        if case .join = action {
                            sessionViewModel.pendingInvite = nil
                        }
                        pendingAgreement = nil
                    }
                )
            }
            .onChange(of: sessionViewModel.pendingInvite) { _, newInvite in
                guard let invite = newInvite else { return }
                let initials = isInitialsValid ? cleanInitials : (sessionViewModel.localUserName.isEmpty ? "ME" : sessionViewModel.localUserName)
                pendingAgreement = .join(invite: invite, initials: initials)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.green)
                .padding(.top, 10)
            
            Text("TeeKum")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            
            Text("Offline Peer-to-Peer Festival Mesh")
                .font(.subheadline)
                .foregroundStyle(.gray)
        }
    }
    
    // MARK: - Initials Input Card
    
    private var initialsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("YOUR INITIALS (1 TO 3 LETTERS)")
                    .font(.caption.bold())
                    .foregroundStyle(.gray)
                    .tracking(1.2)
                Spacer()
                Text("\(cleanInitials.count)/3")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isInitialsValid ? .green : .gray)
            }
            
            TextField("DNA", text: $initialsInput)
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .focused($isFieldFocused)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isInitialsValid ? selectedColor.swiftUIColor : Color(white: 0.25), lineWidth: 2)
                        .shadow(color: isInitialsValid ? selectedColor.swiftUIColor.opacity(0.4) : Color.clear, radius: 6)
                )
                .onChange(of: initialsInput) { _, newValue in
                    let filtered = newValue.uppercased().filter { $0 >= "A" && $0 <= "Z" }
                    if filtered.count > 3 {
                        initialsInput = String(filtered.prefix(3))
                    } else {
                        initialsInput = filtered
                    }
                    if sessionViewModel.localColor == .unset && !filtered.isEmpty {
                        selectedColor = MemberColor.deterministicColor(for: filtered)
                    }
                }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("YOUR COLOR")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)
                        .tracking(1.2)
                    Spacer()
                    Text(selectedColor.name)
                        .font(.caption.bold())
                        .foregroundStyle(selectedColor.swiftUIColor)
                }
                ColorPickerPaletteView(selectedColor: $selectedColor) { newColor in
                    sessionViewModel.setLocalColor(newColor)
                }
            }
            .padding(.top, 4)
            
            Text("Your initials will be visible to nearby friends on radars and maps without cell service.")
                .font(.caption2)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }
    
    // MARK: - Create Group Section (QR Generator)
    
    private var createGroupSection: some View {
        VStack(spacing: 20) {
            if let session = createdSession {
                // Display Generated QR Code for friends to scan
                VStack(spacing: 16) {
                    QRCodeView(
                        url: session.inviteURL(),
                        title: session.sessionName,
                        subtitle: "Have friends scan this barcode with TeeKum to join your private group with zero cell reception.",
                        keyFingerprint: session.symmetricKeyData.prefix(4).map { String(format: "%02hhx", $0) }.joined()
                    )
                    
                    Button(action: {
                        sessionViewModel.setActiveSession(session)
                    }) {
                        HStack(spacing: 8) {
                            Text("Enter Group Map")
                                .font(.headline.bold())
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal)
            } else {
                // Form to create group
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Group Name")
                            .font(.caption.bold())
                            .foregroundStyle(.gray)
                        
                        TextField("e.g. Coachella Crew", text: $groupNameInput)
                            .padding()
                            .background(Color(white: 0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                    }
                    
                    Button(action: handleCreateGroup) {
                        HStack(spacing: 8) {
                            Image(systemName: "qrcode")
                            Text("Create Group & Generate QR")
                                .font(.headline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canCreateGroup ? Color.green : Color.gray.opacity(0.3))
                        .foregroundStyle(canCreateGroup ? Color.black : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canCreateGroup)
                    .padding(.top, 6)
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var canCreateGroup: Bool {
        isInitialsValid && !groupNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func handleCreateGroup() {
        let clean = InitialsCodec.sanitize(cleanInitials)
        let trimmedGroup = groupNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !trimmedGroup.isEmpty else { return }
        
        // Present Agreement Page before creating group
        pendingAgreement = .create(name: trimmedGroup, initials: clean)
    }
    
    private func executeCreateGroup(name: String, initials: String) {
        let session = sessionViewModel.createDraftSession(
            name: name,
            localName: initials,
            colorCode: selectedColor.rawValue
        )
        self.createdSession = session
        sessionViewModel.clearError()
    }
    
    // MARK: - Scan to Join Section (QR Scanner)
    
    private var scanToJoinSection: some View {
        VStack(spacing: 16) {
            if !isInitialsValid {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 44))
                        .foregroundStyle(.gray)
                    Text("Please enter your 1 to 3-letter initials above to enable camera scanning.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(white: 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    QRScannerView(onCodeScanned: handleScannedCode)
                        .frame(height: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(white: 0.2), lineWidth: 1)
                        )
                    
                    Text("Scan the host's group QR code on-site without internet.")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func handleScannedCode(_ code: String) {
        guard let invite = GroupSession.parseInvite(from: code) else {
            sessionViewModel.errorMessage = "Invalid TeeKum invite link or mismatched session format."
            return
        }
        
        let clean = InitialsCodec.sanitize(cleanInitials)
        sessionViewModel.clearError()
        // Present Agreement Page before joining group
        pendingAgreement = .join(invite: invite, initials: clean)
    }
}
