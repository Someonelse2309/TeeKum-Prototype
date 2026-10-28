//
//  GroupPairingView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI

/// Pure MVVM View for serverless group formation, QR code generation/display,
/// and native AVFoundation camera QR scanning.
public struct GroupPairingView: View {
    @Bindable var sessionViewModel: GroupSessionViewModel
    
    @State private var selectedTab: PairingTab = .create
    @State private var groupNameInput: String = "Coachella Crew"
    @State private var userNameInput: String = ""
    @State private var createdSession: GroupSession?
    @State private var isShowingScannerSheet: Bool = false
    
    enum PairingTab: String, CaseIterable {
        case create = "Create Group"
        case join = "Scan to Join"
    }
    
    public init(sessionViewModel: GroupSessionViewModel) {
        self.sessionViewModel = sessionViewModel
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerView
                        
                        // Tab Picker
                        Picker("Pairing Mode", selection: $selectedTab) {
                            ForEach(PairingTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
                        // Content based on tab
                        if selectedTab == .create {
                            createGroupSection
                        } else {
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
                if sessionViewModel.activeSession == nil {
                    createdSession = nil
                    sessionViewModel.errorMessage = nil
                }
                if !sessionViewModel.localUserName.isEmpty && userNameInput.isEmpty {
                    userNameInput = sessionViewModel.localUserName
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.green)
                .padding(.top, 10)
            
            Text("TeeKum")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            
            Text("Offline Concert-Finding Mesh")
                .font(.subheadline)
                .foregroundStyle(.gray)
        }
    }
    
    // MARK: - Create Group Section
    
    private var createGroupSection: some View {
        VStack(spacing: 20) {
            if let session = createdSession {
                // Generated QR Code Display
                VStack(spacing: 16) {
                    QRCodeView(
                        url: session.inviteURL(),
                        title: session.sessionName,
                        subtitle: "Display this QR code to friends on-site. They scan with their camera to join instantly with zero reception.",
                        keyFingerprint: session.symmetricKeyData.prefix(4).map { String(format: "%02hhx", $0) }.joined()
                    )
                    .padding(.horizontal)
                    
                    Button {
                        // Commit active session and navigate to map
                        sessionViewModel.setActiveSession(session)
                        createdSession = nil
                    } label: {
                        HStack {
                            Text("Enter Festival Map")
                                .font(.headline.bold())
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)
                    .accessibilityLabel("Enter festival map")
                    .accessibilityHint("Proceeds to the main offline map with this active group session.")
                    
                    Button("Cancel & Reset Group") {
                        createdSession = nil
                        sessionViewModel.resetSessionState()
                    }
                    .font(.footnote)
                    .foregroundStyle(.red)
                }
            } else {
                // Group Setup Form
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your Nickname")
                            .font(.caption.bold())
                            .foregroundStyle(.gray)
                        
                        TextField("e.g. Alex", text: $userNameInput)
                            .padding()
                            .background(Color(white: 0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Group / Festival Name")
                            .font(.caption.bold())
                            .foregroundStyle(.gray)
                        
                        TextField("e.g. Coachella Crew", text: $groupNameInput)
                            .padding()
                            .background(Color(white: 0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                    }
                    
                    Button(action: handleCreateAndDisplayQR) {
                        Label("Generate Group QR Code", systemImage: "qrcode")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canCreateGroup ? Color.green : Color.gray.opacity(0.3))
                            .foregroundStyle(canCreateGroup ? Color.black : Color.gray)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canCreateGroup)
                    .padding(.top, 8)
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var canCreateGroup: Bool {
        !userNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !groupNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func handleCreateAndDisplayQR() {
        let trimmedUser = userNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGroup = groupNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty, !trimmedGroup.isEmpty else { return }
        
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        let keyData = Data(keyBytes)
        
        let session = GroupSession(
            sessionName: trimmedGroup,
            symmetricKeyData: keyData,
            localMemberName: trimmedUser,
            isHost: true
        )
        self.createdSession = session
        sessionViewModel.clearError()
    }
    
    // MARK: - Scan to Join Section
    
    private var scanToJoinSection: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your Nickname")
                    .font(.caption.bold())
                    .foregroundStyle(.gray)
                
                TextField("Enter your name to join", text: $userNameInput)
                    .padding()
                    .background(Color(white: 0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal)
            
            if userNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 44))
                        .foregroundStyle(.gray)
                    Text("Please enter your nickname above to enable camera scanning.")
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
                // Embedded Native Scanner View
                VStack(spacing: 12) {
                    QRScannerView(onCodeScanned: handleScannedCode)
                        .frame(height: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(white: 0.2), lineWidth: 1)
                        )
                    
                    Text("Scan the host's QR code on-site without internet.")
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
            sessionViewModel.errorMessage = "Invalid TeeKum QR code or mismatched key version."
            return
        }
        
        let trimmedUser = userNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUser = !trimmedUser.isEmpty ? trimmedUser : (!sessionViewModel.localUserName.isEmpty ? sessionViewModel.localUserName : "Friend")
        
        sessionViewModel.localUserName = resolvedUser
        sessionViewModel.clearError()
        sessionViewModel.joinGroup(invite: invite, localName: resolvedUser)
    }
}
