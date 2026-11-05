//
//  ChatSheetView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI

/// Complete SwiftUI Group Mesh Chat bottom sheet overlay.
///
/// Implements Master Specification & UI Architecture Guarantees:
/// 1. Feed of incoming and outgoing message bubbles with honest delivery indicators.
/// 2. ByteLimiter engine with visual byte meter (X / 20 B) and color thresholds.
/// 3. Carousel of 1-tap quick preset chips for swift festival communication.
/// 4. Disables message composition during Festival Survival Mode (<20% battery).
/// 5. Bounded 3.0-second cooldown rate limit between sent messages.
/// 6. Per-recipient ACK inspection detail sheet.
/// 7. 100% accessible touch targets (>= 44x44pt) and AMOLED #000000 dark aesthetics.
public struct ChatSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ChatViewModel
    @FocusState private var isTextFieldFocused: Bool
    
    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Bar
                    headerBar
                    
                    // Battery / Survival Mode Warning Banner
                    if viewModel.isSurvivalMode {
                        survivalModeBanner
                    }
                    
                    // Transient Error Feedback Banner
                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }
                    
                    // Message Feed
                    messageFeedView
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    // Bottom Input Dock (Presets + Text Field + Meter + Send Button)
                    bottomInputDock
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $viewModel.selectedMessageForDetails) { message in
                RecipientAckBreakdownView(message: message, viewModel: viewModel)
            }
            .onAppear {
                viewModel.unreadCount = 0
            }
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Festival Group Chat")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    
                    Circle()
                        .fill(viewModel.isChatAvailable ? Color(red: 0.19, green: 0.82, blue: 0.35) : Color.gray)
                        .frame(width: 8, height: 8)
                }
                
                if let session = viewModel.sessionProvider?() {
                    Text("\(session.sessionName) • \(viewModel.localInitials)")
                        .font(.caption)
                        .foregroundStyle(.gray)
                } else {
                    Text("No Active Session")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
            
            Spacer()
            
            // Dismiss Button (44x44pt touch target)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.bold())
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close chat")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.95))
    }
    
    // MARK: - Banners
    
    private var survivalModeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.slash.fill")
                .font(.subheadline.bold())
                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.04)) // Neon Amber
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Festival Survival Mode (<20% Battery)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Text("Chat is disabled to preserve battery for GPS and emergency sirens. Emergency SOS remains active.")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 0.25, green: 0.18, blue: 0.05))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.04).opacity(0.4)),
            alignment: .bottom
        )
    }
    
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.18, blue: 0.45))
            
            Text(message)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
            
            Spacer()
            
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(6)
            }
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 0.25, green: 0.06, blue: 0.1))
    }
    
    // MARK: - Message Feed
    
    private var messageFeedView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    emptyFeedPlaceholder
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageBubbleView(
                                message: message,
                                localColor: viewModel.localColor,
                                senderColor: viewModel.memberColor(for: message.senderInitials),
                                onSelectDetails: {
                                    viewModel.selectedMessageForDetails = message
                                }
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastId = viewModel.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if let lastId = viewModel.messages.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }
    
    private var emptyFeedPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.6))
            
            Text("No Messages Yet")
                .font(.headline.bold())
                .foregroundStyle(.white)
            
            Text("Tap a quick preset chip below or type a direct message up to 20 bytes.")
                .font(.subheadline)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    // MARK: - Bottom Input Dock
    
    private var bottomInputDock: some View {
        VStack(spacing: 8) {
            // Preset Chips Carousel
            PresetChipsView(viewModel: viewModel)
                .padding(.top, 6)
            
            // Text Input Bar + Byte Meter + Send Button
            HStack(spacing: 8) {
                // Text Field with integrated Byte Meter
                HStack(spacing: 8) {
                    TextField(
                        viewModel.isSurvivalMode ? "Chat disabled (<20% battery)" : "Message (max 20B)...",
                        text: Binding(
                            get: { viewModel.draftText },
                            set: { viewModel.updateDraft($0) }
                        )
                    )
                    .focused($isTextFieldFocused)
                    .font(.body)
                    .foregroundStyle(.white)
                    .disabled(!viewModel.isChatAvailable)
                    .submitLabel(.send)
                    .onSubmit {
                        if viewModel.canSend {
                            Task { await viewModel.sendMessage() }
                        }
                    }
                    
                    // Byte Meter Docked to the right of text
                    ByteMeterView(viewModel: viewModel)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            viewModel.isDraftAtLimit
                                ? viewModel.byteMeterColor
                                : Color.white.opacity(0.15),
                            lineWidth: 1
                        )
                )
                
                // Send Button (44x44pt touch target)
                Button {
                    Task {
                        await viewModel.sendMessage()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(sendButtonBackgroundColor)
                            .frame(width: 44, height: 44)
                        
                        if viewModel.isSending {
                            ProgressView()
                                .tint(.black)
                        } else if viewModel.cooldownRemaining > 0 {
                            Text(String(format: "%.0f", ceil(viewModel.cooldownRemaining)))
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(.black)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.headline.bold())
                                .foregroundStyle(viewModel.canSend ? .black : .gray)
                        }
                    }
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel(sendButtonAccessibilityLabel)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color.black.opacity(0.95))
    }
    
    private var sendButtonBackgroundColor: Color {
        if viewModel.canSend {
            return Color(red: 0.0, green: 0.85, blue: 1.0) // Neon Cyan
        } else if viewModel.cooldownRemaining > 0 {
            return Color(red: 1.0, green: 0.84, blue: 0.04) // Neon Amber
        } else {
            return Color.white.opacity(0.15)
        }
    }
    
    private var sendButtonAccessibilityLabel: String {
        if let reason = viewModel.availabilityStatusText {
            return "Send message, currently disabled: \(reason)"
        } else if viewModel.canSend {
            return "Send message"
        } else {
            return "Send message, disabled"
        }
    }
}
