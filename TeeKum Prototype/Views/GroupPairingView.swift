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
    
    @State private var selectedTab: PairingTab = .create
    @State private var initialsInput: String = ""
    @State private var groupNameInput: String = "Festival Crew"
    @State private var createdSession: GroupSession?
    @FocusState private var isFieldFocused: Bool
    
    enum PairingTab: String, CaseIterable {
        case create = "Create Group"
        case join = "Scan to Join"
// MARK: Ini di hide dulu
//        case openMesh = "Open Mesh"
    }
    
    public init(sessionViewModel: GroupSessionViewModel) {
        self.sessionViewModel = sessionViewModel
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
                            // MARK: Ini di hide dulu
//                        case .openMesh:
//                            openMeshSection
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
            .onAppear {
                if !sessionViewModel.localUserName.isEmpty && initialsInput.isEmpty {
                    initialsInput = sessionViewModel.localUserName
                }
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
                        .stroke(isInitialsValid ? Color.green : Color(white: 0.25), lineWidth: 2)
                )
                .onChange(of: initialsInput) { _, newValue in
                    let filtered = newValue.uppercased().filter { $0 >= "A" && $0 <= "Z" }
                    if filtered.count > 3 {
                        initialsInput = String(filtered.prefix(3))
                    } else {
                        initialsInput = filtered
                    }
                }
            
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
        
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        let keyData = Data(keyBytes)
        
        let session = GroupSession(
            sessionId: UInt16.random(in: 1...UInt16.max),
            sessionName: trimmedGroup,
            symmetricKeyData: keyData,
            localInitials: clean,
            isHost: true
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
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedCode) else {
            sessionViewModel.errorMessage = "Scanned barcode is not a valid URL: \(trimmedCode)"
            return
        }
        
        guard let invite = GroupSession.parseInvite(from: url) else {
            sessionViewModel.errorMessage = "Invalid TeeKum QR code or mismatched session format."
            return
        }
        
        let clean = InitialsCodec.sanitize(cleanInitials)
        sessionViewModel.clearError()
        sessionViewModel.joinGroup(invite: invite, localName: clean)
    }
    
    // MARK: - Open Mesh Section (Instant Auto-Mesh)
    
    private var openMeshSection: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Festival Auto-Mesh")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                
                Text("Join the default festival mesh network immediately. All attendees using TeeKum on this channel can discover each other automatically without exchanging codes.")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            
            Button(action: handleEnterAutoMesh) {
                HStack(spacing: 10) {
                    Text("Join Festival Open Mesh")
                        .font(.headline.bold())
                    Image(systemName: "arrow.right")
                        .font(.headline.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isInitialsValid ? Color.green : Color.gray.opacity(0.3))
                .foregroundStyle(isInitialsValid ? Color.black : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!isInitialsValid)
            .padding(.horizontal)
        }
    }
    
    private func handleEnterAutoMesh() {
        guard isInitialsValid else { return }
        sessionViewModel.enterAutoMesh(initials: cleanInitials)
    }
}
