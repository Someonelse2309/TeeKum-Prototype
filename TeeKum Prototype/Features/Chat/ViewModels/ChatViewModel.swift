//
//  ChatViewModel.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI
import Observation
import Foundation

/// Pure MVVM ViewModel governing the TeeKum Festival Group Mesh Chat interface.
///
/// Implements Master Specification & UI Architecture Guarantees:
/// 1. Pure MVVM with `@Observable @MainActor`: Reactive UI bindings, zero extraneous coordinators.
/// 2. Separation of Concerns: Keeps ALL messaging business logic (cryptography, outbox priority,
///    multi-hop relaying, ACK dispatch, and retries) strictly in `ChatMessagingService`.
/// 3. Byte Limiter Engine: Strictly enforces maximum 20 UTF-8 encoded bytes (`ChatMessagePayload.maxTextBytes`),
///    clamping multi-byte code point boundaries and driving the dynamic visual byte meter.
/// 4. Honest Delivery State: Clearly distinguishes intermediary mesh relays from actual recipient delivery.
/// 5. Multi-Peer ACK Progress: Tracks and exposes per-recipient delivery details.
/// 6. Festival Survival Mode: Automatically disables sending when battery < 20% or Low Power Mode is active.
/// 7. Ephemeral In-Memory History: Wipes conversation upon group session exit (zero disk writes).
@Observable
@MainActor
public final class ChatViewModel {
    
    // MARK: - Dependencies
    
    public var chatService: (any ChatMessagingService)?
    public var sessionProvider: (@Sendable () -> GroupSession?)?
    public var membersProvider: (@MainActor () -> [Member])?
    public var clock: MeshClock
    
    // MARK: - Presentation State
    
    /// Bounded in-memory list of chat messages for the active session (up to 50 latest).
    public var messages: [ChatMessage] = []
    
    /// Current draft text in composition bar (clamped to max 20 UTF-8 bytes).
    public var draftText: String = ""
    
    /// Number of unread incoming messages received while chat sheet was closed.
    public var unreadCount: Int = 0
    
    /// Whether the chat bottom sheet is currently presented.
    public var isChatSheetPresented: Bool = false {
        didSet {
            if isChatSheetPresented {
                unreadCount = 0
            }
        }
    }
    
    /// True while message transmission is actively in flight.
    public var isSending: Bool = false
    
    /// Feedback / error banner text.
    public var errorMessage: String? = nil
    
    /// Cooldown countdown in seconds (enforces 3.0s between outgoing messages).
    public var cooldownRemaining: Double = 0.0
    
    /// Selected message for per-recipient delivery detail inspection.
    public var selectedMessageForDetails: ChatMessage? = nil
    
    /// Hardware battery percentage (0.0 to 1.0).
    public var currentBatteryLevel: Float = 1.0
    
    /// Hardware Low Power Mode status.
    public var isLowPowerMode: Bool = false
    
    /// True when battery < 20% or Low Power Mode is active (Festival Survival Mode).
    public var isSurvivalMode: Bool = false
    
    // MARK: - Internal Tasks
    
    private var streamObservationTask: Task<Void, Never>?
    private var cooldownTimerTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init(
        chatService: (any ChatMessagingService)? = nil,
        sessionProvider: (@Sendable () -> GroupSession?)? = nil,
        membersProvider: (@MainActor () -> [Member])? = nil,
        clock: MeshClock = SystemMeshClock()
    ) {
        self.chatService = chatService
        self.sessionProvider = sessionProvider
        self.membersProvider = membersProvider
        self.clock = clock
        
        if let service = chatService {
            startListening(to: service)
        }
    }
    
    // MARK: - Configuration & Lifecycle
    
    /// Configures or updates runtime dependencies for an active group session.
    public func configure(
        chatService: any ChatMessagingService,
        sessionProvider: @escaping @Sendable () -> GroupSession?,
        membersProvider: (@MainActor () -> [Member])? = nil
    ) {
        self.chatService = chatService
        self.sessionProvider = sessionProvider
        self.membersProvider = membersProvider
        startListening(to: chatService)
        
        Task {
            let initial = await chatService.activeMessages()
            self.messages = initial
            let battery = await chatService.currentBatteryLevel
            let lowPower = await chatService.isLowPowerMode
            self.updateBattery(level: battery, isLowPower: lowPower)
        }
    }
    
    /// Starts background observation of the service's asynchronous message update stream and direct callback.
    public func startListening(to service: any ChatMessagingService) {
        Task { [weak self] in
            await service.setOnMessageUpdated { [weak self] updatedMessage in
                Task { @MainActor in
                    self?.handleIncomingMessageUpdate(updatedMessage)
                }
            }
        }
        
        streamObservationTask?.cancel()
        streamObservationTask = Task { [weak self] in
            for await updatedMessage in service.messageUpdates {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.handleIncomingMessageUpdate(updatedMessage)
                }
            }
        }
    }
    
    /// Reacts to an updated or newly delivered message from the service.
    private func handleIncomingMessageUpdate(_ updatedMessage: ChatMessage) {
        if let index = messages.firstIndex(where: { $0.sequenceNumber == updatedMessage.sequenceNumber && $0.senderInitials == updatedMessage.senderInitials }) {
            if updatedMessage.deliveryState.priorityRank >= messages[index].deliveryState.priorityRank {
                messages[index] = updatedMessage
            } else {
                var merged = messages[index]
                merged.confirmedResponders.formUnion(updatedMessage.confirmedResponders)
                messages[index] = merged
            }
        } else if let index = messages.firstIndex(where: { $0.id == updatedMessage.id }) {
            if updatedMessage.deliveryState.priorityRank >= messages[index].deliveryState.priorityRank {
                messages[index] = updatedMessage
            }
        } else {
            messages.append(updatedMessage)
            if messages.count > 50 {
                messages.removeFirst(messages.count - 50)
            }
            // Increment unread count for peer messages if sheet is closed
            if !updatedMessage.isLocalSender && !isChatSheetPresented {
                unreadCount += 1
            }
        }
        
        // Update detail inspector if this message is actively selected
        if selectedMessageForDetails?.id == updatedMessage.id {
            selectedMessageForDetails = updatedMessage
        }
    }
    
    // MARK: - Session & Conversation Teardown
    
    /// Clears the displayed conversation, draft, and in-flight tracking on group session teardown.
    public func clearConversation() {
        messages.removeAll()
        draftText = ""
        unreadCount = 0
        errorMessage = nil
        cooldownRemaining = 0.0
        selectedMessageForDetails = nil
        cooldownTimerTask?.cancel()
        cooldownTimerTask = nil
        
        Task {
            await chatService?.clearHistory()
        }
    }
    
    // MARK: - Battery & Power Updates
    
    /// Updates hardware power metrics and enforces Festival Survival Mode policy.
    public func updateBattery(level: Float, isLowPower: Bool) {
        self.currentBatteryLevel = level
        self.isLowPowerMode = isLowPower
        self.isSurvivalMode = (level < 0.20) || isLowPower
        
        Task {
            await chatService?.setBatteryLevel(level, isLowPowerMode: isLowPower)
        }
    }
    
    // MARK: - ByteLimiter Engine (20-Byte Wire Allocation)
    
    public static let maxBytes: Int = ChatMessagePayload.maxTextBytes
    
    /// Current number of UTF-8 encoded bytes in draft.
    public var currentByteCount: Int {
        draftText.utf8.count
    }
    
    /// Number of remaining bytes before hitting the 20-byte wire limit.
    public var remainingBytes: Int {
        max(0, Self.maxBytes - currentByteCount)
    }
    
    /// Normalized byte consumption ratio (0.0 to 1.0).
    public var byteUsageRatio: Double {
        min(1.0, Double(currentByteCount) / Double(Self.maxBytes))
    }
    
    /// True when draft has reached the maximum 20-byte allocation.
    public var isDraftAtLimit: Bool {
        currentByteCount >= Self.maxBytes
    }
    
    /// Dynamic color for visual byte meter.
    public var byteMeterColor: Color {
        if currentByteCount < 16 {
            return Color(red: 0.0, green: 0.85, blue: 1.0) // Neon Cyan
        } else if currentByteCount < 20 {
            return Color(red: 1.0, green: 0.84, blue: 0.04) // Neon Amber
        } else {
            return Color(red: 1.0, green: 0.18, blue: 0.45) // Neon Red
        }
    }
    
    /// Intercepts input, clamps to largest valid UTF-8 boundary <= 20 bytes, and updates draft.
    public func updateDraft(_ input: String) {
        let clamped = ChatMessagePayload.clampTo20Bytes(input)
        if input.utf8.count > Self.maxBytes {
            errorMessage = "Capped at 20 bytes for mesh radio transmission."
        } else {
            errorMessage = nil
        }
        self.draftText = clamped
    }
    
    /// Populates draft with one of the approved quick preset chips.
    public func applyPreset(_ preset: String) {
        updateDraft(preset)
    }
    
    // MARK: - Validation & Readiness
    
    public var hasActiveSession: Bool {
        sessionProvider?() != nil
    }
    
    public var localInitials: String {
        sessionProvider?()?.localInitials ?? ""
    }
    
    public var localColor: MemberColor {
        MemberColor(rawValue: sessionProvider?()?.localColorCode ?? 0) ?? .unset
    }
    
    public var isChatAvailable: Bool {
        hasActiveSession && !isSurvivalMode
    }
    
    /// Validation check determining if send button should be enabled.
    public var canSend: Bool {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && currentByteCount <= Self.maxBytes
            && !isSending
            && cooldownRemaining <= 0
            && !isSurvivalMode
            && hasActiveSession
    }
    
    /// User-facing status string explaining why sending is currently disabled.
    public var availabilityStatusText: String? {
        if !hasActiveSession {
            return "Join or create a group to chat."
        }
        if isSurvivalMode {
            return "Chat disabled in Survival Mode (<20% battery). Emergency SOS remains active."
        }
        if cooldownRemaining > 0 {
            return String(format: "Cooldown: %.1fs", cooldownRemaining)
        }
        return nil
    }
    
    // MARK: - Message Composition & Dispatch
    
    /// Validates, sends message via `ChatMessagingService`, and starts the 3.0s cooldown.
    public func sendMessage() async {
        guard hasActiveSession else {
            errorMessage = "Cannot send message without an active group."
            return
        }
        guard !isSurvivalMode else {
            errorMessage = "Chat is disabled in Survival Mode (<20% battery). Emergency SOS remains active."
            return
        }
        guard cooldownRemaining <= 0 else {
            errorMessage = String(format: "Please wait %.1f seconds before sending another message.", cooldownRemaining)
            return
        }
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Message cannot be empty."
            return
        }
        guard currentByteCount <= Self.maxBytes else {
            errorMessage = "Message exceeds 20-byte wire limit."
            return
        }
        guard let service = chatService else {
            errorMessage = "Chat service unavailable."
            return
        }
        
        isSending = true
        errorMessage = nil
        let textToSend = draftText
        
        do {
            let sentMessage = try await service.sendMessage(text: textToSend, targetRecipients: nil)
            self.draftText = ""
            self.isSending = false
            self.errorMessage = nil
            
            // Upsert in local array immediately
            handleIncomingMessageUpdate(sentMessage)
            
            // Start 3.0s cooldown timer
            let cooldownDuration = await service.timingConfig.chatUserCooldown
            startCooldown(duration: cooldownDuration)
            
        } catch {
            self.isSending = false
            self.errorMessage = error.localizedDescription
        }
    }
    
    /// Initiates the cooldown countdown timer.
    private func startCooldown(duration: Double) {
        cooldownRemaining = duration
        cooldownTimerTask?.cancel()
        cooldownTimerTask = Task { [weak self] in
            let step: TimeInterval = 0.1
            while let current = self?.cooldownRemaining, current > 0 {
                try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    if let self = self {
                        self.cooldownRemaining = max(0.0, self.cooldownRemaining - step)
                    }
                }
            }
        }
    }
    
    // MARK: - Color Resolution Helper
    
    /// Resolves the vibrant festival color associated with any group member initials.
    public func memberColor(for initials: String) -> MemberColor {
        let cleanInitials = InitialsCodec.sanitize(initials)
        if cleanInitials == localInitials {
            return localColor != .unset ? localColor : MemberColor.deterministicColor(for: cleanInitials)
        }
        if let members = membersProvider?() {
            if let match = members.first(where: { $0.id == cleanInitials }) {
                return match.color
            }
        }
        return MemberColor.deterministicColor(for: cleanInitials)
    }
}
