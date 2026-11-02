//
//  MeshAgreementView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import SwiftUI

/// Offline Group Agreement Agreement Screen presented before creating or joining any group.
/// Mandates explicit user consent to participate as an offline relay node in the festival mesh,
/// adhering to Decision D5 and User Story 7.
public struct MeshAgreementView: View {
    public enum AgreementContext: Sendable {
        case create(groupName: String, initials: String)
        case join(groupName: String, initials: String)
        case autoMesh(initials: String)
        
        public var actionTitle: String {
            switch self {
            case .create(let name, _):
                return "Agree & Create \"\(name)\""
            case .join(let name, _):
                return "Agree & Join \"\(name)\""
            case .autoMesh:
                return "Agree & Create Private Group"
            }
        }
        
        public var contextSubtitle: String {
            switch self {
            case .create(let name, let initials):
                return "You are setting up \"\(name)\" as host with initials [\(initials)]."
            case .join(let name, let initials):
                return "You are connecting to \"\(name)\" with initials [\(initials)]."
            case .autoMesh(let initials):
                return "You are creating a private group with initials [\(initials)]."
            }
        }
    }
    
    public let context: AgreementContext
    public let onAgree: () -> Void
    public let onDecline: () -> Void
    
    public init(
        context: AgreementContext,
        onAgree: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        self.context = context
        self.onAgree = onAgree
        self.onDecline = onDecline
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 22) {
                        // Header Icon Badge
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.12))
                                .frame(width: 80, height: 80)
                            
                            Circle()
                                .stroke(Color.green.opacity(0.4), lineWidth: 2)
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(.system(size: 38))
                                .foregroundStyle(.green)
                        }
                        .padding(.top, 16)
                        
                        // Title & Subtitle
                        VStack(spacing: 8) {
                            Text("Offline Group Agreement")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            
                            Text("“Share location with trusted group members.”")
                                .font(.subheadline.italic())
                                .foregroundStyle(.green)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Target Group Context Box
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.badge.shield.checkmark.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Group Membership Requirement")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.gray)
                                    .textCase(.uppercase)
                                Text(context.contextSubtitle)
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color(white: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        
                        // 4 Pillars of the Mesh Compact
                        VStack(spacing: 14) {
                            compactItem(
                                icon: "point.3.connected.trianglepath.dotted",
                                iconColor: .green,
                                title: "Group Connections",
                                description: "Your phone connects directly to nearby phones and can forward authenticated packets within your private group. Stranger relaying is planned for Phase 2."
                            )
                            
                            compactItem(
                                icon: "lock.shield.fill",
                                iconColor: .cyan,
                                title: "Encrypted Group Data",
                                description: "Group members holding your invite key can read shared locations and status. Nearby outsiders can observe discovery and routing metadata, but cannot decrypt the packet payload."
                            )
                            
                            compactItem(
                                icon: "bolt.shield.fill",
                                iconColor: .yellow,
                                title: "Battery-Aware Sharing",
                                description: "Location updates slow down in Survival Mode. Turn Live Sharing off to pause normal location broadcasts; SOS can still send immediately."
                            )
                            
                            compactItem(
                                icon: "iphone.badge.play",
                                iconColor: .orange,
                                title: "Background Availability",
                                description: "iOS may suspend networking when your phone is locked or the app is inactive. A Live Activity does not guarantee background packet delivery. Keep the app open for active coordination."
                            )
                        }
                        .padding(.horizontal)
                        
                        // Action Buttons
                        VStack(spacing: 12) {
                            Button(action: onAgree) {
                                HStack(spacing: 8) {
                                    Text(context.actionTitle)
                                        .font(.headline.bold())
                                    Image(systemName: "arrow.right")
                                        .font(.headline.bold())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.green)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            
                            Button(action: onDecline) {
                                Text("Decline & Cancel")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.gray)
                                    .padding(.vertical, 8)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        onDecline()
                    }
                    .foregroundStyle(.gray)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func compactItem(icon: String, iconColor: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(14)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
