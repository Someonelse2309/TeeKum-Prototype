//
//  MeshAgreementView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 29/10/26.
//

import SwiftUI

/// Communal Mesh Compact Agreement Screen presented before creating or joining any group.
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
                return "Agree & Join Open Mesh"
            }
        }
        
        public var contextSubtitle: String {
            switch self {
            case .create(let name, let initials):
                return "You are setting up \"\(name)\" as host with initials [\(initials)]."
            case .join(let name, let initials):
                return "You are connecting to \"\(name)\" with initials [\(initials)]."
            case .autoMesh(let initials):
                return "You are connecting to the festival open channel with initials [\(initials)]."
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
                            Text("Communal Mesh Compact")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            
                            Text("“Relay for others while others relay for you.”")
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
                                title: "All-in Community Mesh Relay",
                                description: "Your phone acts as an offline hop node for your group and nearby attendees, bouncing encrypted signals across crowd dead zones without cell towers or internet."
                            )
                            
                            compactItem(
                                icon: "lock.shield.fill",
                                iconColor: .cyan,
                                title: "100% Zero-Knowledge Privacy",
                                description: "Every packet is end-to-end encrypted with ChaCha20-Poly1305. Relay nodes only see 4-byte network routing headers—nobody can see your location, status, or identity."
                            )
                            
                            compactItem(
                                icon: "bolt.shield.fill",
                                iconColor: .yellow,
                                title: "20% Battery Survival Guarantee",
                                description: "Relaying is rate-limited to ≤2 pkts/sec. To protect your phone for emergencies, mesh relaying automatically shuts off if battery drops to 20% or in Low Power Mode."
                            )
                            
                            compactItem(
                                icon: "iphone.badge.play",
                                iconColor: .orange,
                                title: "Pocket Background Execution",
                                description: "TeeKum stays alive in your pocket via Apple's official location status indicator and Live Activity companion, ensuring you stay tethered with screen locked."
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
