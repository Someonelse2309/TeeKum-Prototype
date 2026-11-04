//
//  SOSButtonView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI

/// Pure MVVM View providing the prominent 3-second continuous hold emergency SOS trigger
/// with visible circular progress ring, early release cancellation, and honest delivery feedback.
public struct SOSButtonView: View {
    @Bindable var sosViewModel: SOSViewModel
    
    @State private var isPressing: Bool = false
    @State private var pressTask: Task<Void, Never>?
    
    public init(sosViewModel: SOSViewModel) {
        self.sosViewModel = sosViewModel
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Inactivity Pre-Alarm Warning Banner
            if sosViewModel.inactivityGuard.isWarningActive {
                inactivityWarningBanner
            }
            
            // Delivery Feedback State Banner
            if sosViewModel.deliveryState != .idle {
                deliveryStateBanner
            }
            
            // SOS Trigger Button
            HStack(spacing: 12) {
                ZStack {
                    // Background Progress Track
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 4)
                        .frame(width: 44, height: 44)
                    
                    // Animated Continuous Hold Progress Ring
                    Circle()
                        .trim(from: 0.0, to: CGFloat(sosViewModel.holdProgress))
                        .stroke(
                            Color.white,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44, height: 44)
                        .animation(.linear(duration: 0.05), value: sosViewModel.holdProgress)
                    
                    Image(systemName: sosViewModel.deliveryState.systemImage)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(buttonTitle)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    
                    Text(buttonSubtitle)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                
                Spacer()
                
                if case .idle = sosViewModel.deliveryState {
                    Menu {
                        ForEach(SOSType.allCases, id: \.self) { type in
                            Button {
                                sosViewModel.currentEmergencyType = type
                            } label: {
                                HStack {
                                    Text(type.title)
                                    if sosViewModel.currentEmergencyType == type {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(categoryBadgeText)
                                .font(.caption2.bold())
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                    }
                } else {
                    Button("Reset") {
                        sosViewModel.reset()
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(buttonBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: isPressing ? Color.red.opacity(0.5) : Color.clear, radius: 10)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressing && (sosViewModel.deliveryState == .idle || sosViewModel.deliveryState == .searchingPeers) {
                            startContinuousPress()
                        }
                    }
                    .onEnded { _ in
                        cancelContinuousPress()
                    }
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Emergency SOS button")
            .accessibilityValue(sosViewModel.deliveryState.title)
            .accessibilityHint("Touch and hold continuously for 3 seconds to broadcast emergency SOS. Release early to cancel.")
            
            // Inactivity Guard Opt-In Toggle
            if case .idle = sosViewModel.deliveryState {
                inactivityGuardToggleRow
            }
        }
    }
    
    // MARK: - Inactivity Warning Banner (Pre-Alarm Countdown)
    
    private var inactivityWarningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.fall")
                .font(.title2.bold())
                .foregroundStyle(.yellow)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("INACTIVITY DETECTED")
                    .font(.caption.bold())
                    .foregroundStyle(.yellow)
                
                Text(String(format: "Auto-SOS in %.0fs • Move phone or tap", sosViewModel.inactivityGuard.countdownRemaining))
                    .font(.caption2)
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            Button("I'M OK") {
                sosViewModel.inactivityGuard.cancelWarning()
            }
            .font(.caption.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.green)
            .clipShape(Capsule())
            .foregroundStyle(.black)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 0.25, green: 0.12, blue: 0.0))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.yellow, lineWidth: 1.5)
        )
        .shadow(color: Color.yellow.opacity(0.4), radius: 8)
    }
    
    // MARK: - Inactivity Guard Toggle Row
    
    private var inactivityGuardToggleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.walk.motion")
                .font(.subheadline)
                .foregroundStyle(sosViewModel.isInactivityGuardEnabled ? .green : .gray)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Inactivity Guard (Man Down)")
                    .font(.caption.bold())
                    .foregroundStyle(sosViewModel.isInactivityGuardEnabled ? .white : .gray)
                
                Text("Auto-SOS if immobile for 3m (30s silent warning)")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { sosViewModel.isInactivityGuardEnabled },
                set: { sosViewModel.isInactivityGuardEnabled = $0 }
            ))
            .labelsHidden()
            .tint(.green)
            .scaleEffect(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Banner
    
    private var deliveryStateBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: bannerIcon)
                .font(.footnote)
                .foregroundStyle(bannerColor)
            
            Text(sosViewModel.deliveryState.title)
                .font(.caption.bold())
                .foregroundStyle(.white)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(bannerColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(bannerColor.opacity(0.4), lineWidth: 1)
        )
    }
    
    // MARK: - Press Engine
    
    private func startContinuousPress() {
        isPressing = true
        sosViewModel.handlePressBegan()
        
        let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
        impactGenerator.impactOccurred()
        
        pressTask?.cancel()
        pressTask = Task { @MainActor in
            let startDate = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms tick
                guard !Task.isCancelled, isPressing else { break }
                
                let elapsed = Date().timeIntervalSince(startDate)
                sosViewModel.updateProgress(elapsedSeconds: elapsed)
                
                if elapsed >= sosViewModel.holdThresholdSeconds {
                    // Trigger completed
                    isPressing = false
                    let notificationGenerator = UINotificationFeedbackGenerator()
                    notificationGenerator.notificationOccurred(.error)
                    break
                }
            }
        }
    }
    
    private func cancelContinuousPress() {
        guard isPressing else { return }
        isPressing = false
        pressTask?.cancel()
        pressTask = nil
        
        sosViewModel.handlePressCancelled()
        
        let cancelGenerator = UIImpactFeedbackGenerator(style: .light)
        cancelGenerator.impactOccurred()
    }
    
    // MARK: - Helpers
    
    private var categoryBadgeText: String {
        switch sosViewModel.currentEmergencyType {
        case .general:
            return "3s"
        case .medical:
            return "Med"
        case .separated:
            return "Lost"
        case .security:
            return "Sec"
        case .inactivity:
            return "Immobile"
        }
    }
    
    private var buttonTitle: String {
        switch sosViewModel.deliveryState {
        case .idle:
            return "EMERGENCY SOS"
        case let .countdown(remaining):
            return String(format: "HOLD FOR SOS (%.1fs)", remaining)
        case .localSending:
            return "BROADCASTING SOS..."
        case .relayedAck:
            return "SOS RELAY ACKNOWLEDGED"
        case .deliveredToFriend:
            return "SOS DELIVERED TO FRIEND"
        case .searchingPeers:
            return "SEARCHING PEERS..."
        case .failed:
            return "SOS WARNING"
        }
    }
    
    private var buttonSubtitle: String {
        switch sosViewModel.deliveryState {
        case .idle:
            return "Press & hold 3s • Release early to cancel"
        case .countdown:
            return "Keep holding button..."
        case .localSending:
            return "Transmitting urgent packet over radio"
        case let .relayedAck(hops, _):
            return "Relayed by \(hops) mesh \(hops == 1 ? "hop" : "hops") (not yet friend)"
        case .deliveredToFriend:
            return "Confirmed received on friend device"
        case .searchingPeers:
            return "Retrying peer broadcast"
        case let .failed(reason):
            return reason
        }
    }
    
    private var buttonBackgroundColor: Color {
        switch sosViewModel.deliveryState {
        case .idle:
            return isPressing ? Color.red : Color(red: 0.75, green: 0.1, blue: 0.1)
        case .countdown:
            return Color.red
        case .localSending:
            return Color.orange
        case .relayedAck:
            return Color.purple
        case .deliveredToFriend:
            return Color.green
        case .searchingPeers:
            return Color.blue
        case .failed:
            return Color.red
        }
    }
    
    private var bannerColor: Color {
        switch sosViewModel.deliveryState {
        case .idle:
            return .gray
        case .countdown:
            return .red
        case .localSending:
            return .orange
        case .relayedAck:
            return .purple
        case .deliveredToFriend:
            return .green
        case .searchingPeers:
            return .blue
        case .failed:
            return .red
        }
    }
    
    private var bannerIcon: String {
        sosViewModel.deliveryState.systemImage
    }
}
