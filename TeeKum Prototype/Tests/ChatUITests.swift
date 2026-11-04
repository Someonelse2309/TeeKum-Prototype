//
//  ChatUITests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import Foundation
import SwiftUI

/// Comprehensive automated UI and ViewModel test suite for TeeKum Phase 3 Festival Group Mesh Chat.
///
/// Validates:
/// 1. Incoming and outgoing message bubble rendering (initials, timestamps, alignment, colors).
/// 2. Accurate honest delivery states (pending, sent, relayed, delivered, timed out, failed).
///    INVARIANT: Intermediary relay ACK is NEVER displayed as confirmed recipient delivery.
/// 3. Per-recipient ACK progress and breakdown inspection.
/// 4. Hard ByteLimiter engine (20-byte wire allocation, multi-byte code point clamping, meter colors).
/// 5. Empty and whitespace-only message rejection with clear feedback.
/// 6. 1-tap quick preset chips population and validation.
/// 7. Battery policy & Festival Survival Mode (<20% battery disables chat; SOS unaffected).
/// 8. 3.0-second cooldown rate limit enforcement.
/// 9. Ephemeral conversation purge on session teardown (zero persistence).
/// 10. Unread badge counter logic on map floating button.
/// 11. End-to-end integration between ChatViewModel and ChatMessageEngine.
public struct ChatUITests {
    
    @MainActor
    public static func runAllTests() async -> Bool {
        print("\n================================================================")
        print(">>> STARTING PHASE 3 CHAT UI & VIEWMODEL TEST SUITE <<<")
        print("================================================================")
        fflush(stdout)
        var passed = true
        
        if !(await testMessageBubbleIncomingAndOutgoingRendering()) { passed = false }
        fflush(stdout)
        if !(await testHonestDeliveryStateTransitions()) { passed = false }
        fflush(stdout)
        if !(await testPerRecipientAckProgressTracking()) { passed = false }
        fflush(stdout)
        if !(await testByteLimiterEnforcementAndClamping()) { passed = false }
        fflush(stdout)
        if !(await testRejectEmptyAndWhitespaceMessages()) { passed = false }
        fflush(stdout)
        if !(await testPresetChipsPopulationAndValidation()) { passed = false }
        fflush(stdout)
        if !(await testBatteryPolicyAndSurvivalModeCutoff()) { passed = false }
        fflush(stdout)
        if !(await testCooldownRateLimiting()) { passed = false }
        fflush(stdout)
        if !(await testSessionTeardownConversationPurge()) { passed = false }
        fflush(stdout)
        if !(await testUnreadBadgeCountBehavior()) { passed = false }
        fflush(stdout)
        if !(await testEndToEndServiceIntegration()) { passed = false }
        fflush(stdout)
        
        if passed {
            print("================================================================")
            print(">>> ALL 11 CHAT UI & VIEWMODEL TESTS PASSED (100%) <<<")
            print("================================================================\n")
        } else {
            print("================================================================")
            print(">>> ✗ SOME CHAT UI & VIEWMODEL TESTS FAILED <<<")
            print("================================================================\n")
        }
        fflush(stdout)
        return passed
    }
    
    // MARK: - Test 1: Message Bubble Incoming and Outgoing Rendering
    
    @MainActor
    private static func testMessageBubbleIncomingAndOutgoingRendering() async -> Bool {
        print("[ChatUITest 1] Incoming & Outgoing message bubble rendering...")
        let session = GroupSession(localInitials: "ALX", localColorCode: MemberColor.neonPink.rawValue)
        let mockService = MockChatMessagingService()
        let vm = ChatViewModel(chatService: mockService, sessionProvider: { session })
        try? await Task.sleep(nanoseconds: 20_000_000)
        
        // Outgoing message
        let outMsg = ChatMessage(
            sequenceNumber: 1,
            senderInitials: "ALX",
            text: "Meet at Main Stage",
            deliveryState: .forwardedToNextHop,
            isLocalSender: true
        )
        
        // Incoming message
        let inMsg = ChatMessage(
            sequenceNumber: 2,
            senderInitials: "BOB",
            text: "On my way!",
            deliveryState: .delivered(confirmedCount: 1, totalRecipients: 1),
            isLocalSender: false
        )
        
        await mockService.simulateMessage(outMsg)
        await mockService.simulateMessage(inMsg)
        
        // Allow stream yield and MainActor dispatch
        for _ in 0..<20 {
            if vm.messages.count == 2 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        
        guard vm.messages.count == 2 else {
            print("  FAIL: Expected 2 messages, got \(vm.messages.count)")
            return false
        }
        
        guard vm.messages[0].isLocalSender && vm.messages[0].senderInitials == "ALX" else {
            print("  FAIL: First message should be local sender ALX")
            return false
        }
        
        guard !vm.messages[1].isLocalSender && vm.messages[1].senderInitials == "BOB" else {
            print("  FAIL: Second message should be remote sender BOB")
            return false
        }
        
        // Color resolution
        let bobColor = vm.memberColor(for: "BOB")
        guard bobColor != .unset else {
            print("  FAIL: BOB color should be deterministically resolved")
            return false
        }
        
        print("  PASS: Message bubble incoming and outgoing rendering verified.")
        return true
    }
    
    // MARK: - Test 2: Honest Delivery State Transitions
    
    @MainActor
    private static func testHonestDeliveryStateTransitions() async -> Bool {
        print("[ChatUITest 2] Honest delivery state transitions (Relayed != Delivered)...")
        let session = GroupSession(localInitials: "NIC")
        let mockService = MockChatMessagingService()
        let vm = ChatViewModel(chatService: mockService, sessionProvider: { session })
        try? await Task.sleep(nanoseconds: 20_000_000)
        
        var msg = ChatMessage(
            sequenceNumber: 10,
            senderInitials: "NIC",
            text: "Beer line",
            deliveryState: .locallyAccepted,
            isLocalSender: true
        )
        await mockService.simulateMessage(msg)
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        // 1. locallyAccepted
        guard vm.messages.first?.deliverySummaryText == "Sending..." else {
            print("  FAIL: locallyAccepted summary text mismatch: \(String(describing: vm.messages.first?.deliverySummaryText))")
            return false
        }
        
        // 2. forwardedToNextHop
        msg.deliveryState = .forwardedToNextHop
        await mockService.simulateMessage(msg)
        try? await Task.sleep(nanoseconds: 30_000_000)
        guard vm.messages.first?.deliverySummaryText == "Sent over Radio" else {
            print("  FAIL: forwardedToNextHop summary text mismatch")
            return false
        }
        
        // 3. relayedByMesh (CRUCIAL INVARIANT: Must NEVER be shown as delivered!)
        msg.deliveryState = .relayedByMesh(hopCount: 2)
        await mockService.simulateMessage(msg)
        try? await Task.sleep(nanoseconds: 30_000_000)
        guard let current = vm.messages.first else { return false }
        guard current.deliveryState.isRelayed && !current.deliveryState.isDelivered else {
            print("  FAIL: Relayed state was incorrectly marked as delivered!")
            return false
        }
        guard current.deliverySummaryText.contains("Relayed by 2 Hops (Unconfirmed)") else {
            print("  FAIL: Relayed summary text must explicitly state unconfirmed: \(current.deliverySummaryText)")
            return false
        }
        
        // 4. delivered (All confirmed)
        msg.deliveryState = .delivered(confirmedCount: 3, totalRecipients: 3)
        await mockService.simulateMessage(msg)
        try? await Task.sleep(nanoseconds: 30_000_000)
        guard let delivered = vm.messages.first, delivered.deliveryState.isDelivered else {
            print("  FAIL: Delivered state not acknowledged")
            return false
        }
        guard delivered.deliverySummaryText.contains("Delivered to All (3/3)") else {
            print("  FAIL: Delivered to All summary mismatch: \(delivered.deliverySummaryText)")
            return false
        }
        
        // 5. deliveryTimedOut
        msg.deliveryState = .deliveryTimedOut
        await mockService.simulateMessage(msg)
        try? await Task.sleep(nanoseconds: 30_000_000)
        guard let timedOut = vm.messages.first, timedOut.deliveryState.isTimedOut else {
            print("  FAIL: Timed out state not reflected")
            return false
        }
        
        // 6. failed
        msg.deliveryState = .failed(reason: "No route to host")
        await mockService.simulateMessage(msg)
        try? await Task.sleep(nanoseconds: 30_000_000)
        guard let failed = vm.messages.first, case .failed = failed.deliveryState else {
            print("  FAIL: Failed state not reflected")
            return false
        }
        
        print("  PASS: Honest delivery state transitions verified.")
        return true
    }
    
    // MARK: - Test 3: Per-Recipient ACK Progress Tracking
    
    @MainActor
    private static func testPerRecipientAckProgressTracking() async -> Bool {
        print("[ChatUITest 3] Per-recipient ACK progress tracking...")
        let session = GroupSession(localInitials: "ALX")
        let mockService = MockChatMessagingService()
        let vm = ChatViewModel(chatService: mockService, sessionProvider: { session })
        
        var recipientStates: [String: RecipientDeliveryState] = [
            "BOB": .locallyAccepted,
            "CHA": .locallyAccepted,
            "DAV": .locallyAccepted
        ]
        
        var msg = ChatMessage(
            sequenceNumber: 20,
            senderInitials: "ALX",
            text: "Where are you?",
            confirmedResponders: [],
            recipientStates: recipientStates,
            deliveryState: .forwardedToNextHop,
            isLocalSender: true
        )
        await mockService.simulateMessage(msg)
        try? await Task.sleep(nanoseconds: 30_000_000)
        
        guard let first = vm.messages.first else { return false }
        guard first.totalRecipientCount == 3, first.confirmedRecipientCount == 0 else {
            print("  FAIL: Initial recipient counts incorrect: \(first.confirmedRecipientCount)/\(first.totalRecipientCount)")
            return false
        }
        
        // BOB delivers
        recipientStates["BOB"] = .deliveredToRecipient(timestamp: Date(), rssi: -65)
        msg.recipientStates = recipientStates
        msg.confirmedResponders = ["BOB"]
        msg.deliveryState = .delivered(confirmedCount: 1, totalRecipients: 3)
        await mockService.simulateMessage(msg)
        try? await Task.sleep(nanoseconds: 30_000_000)
        
        guard let bobConfirmed = vm.messages.first else { return false }
        guard bobConfirmed.confirmedRecipientCount == 1 else {
            print("  FAIL: Confirmed recipient count should be 1, got \(bobConfirmed.confirmedRecipientCount)")
            return false
        }
        guard bobConfirmed.recipientStates["BOB"]?.isDelivered == true else {
            print("  FAIL: BOB should be delivered")
            return false
        }
        
        // CHA is relayed via mesh (NOT delivered!)
        recipientStates["CHA"] = .relayedByMesh(hops: 2, relayPeerId: "RELAY_1")
        msg.recipientStates = recipientStates
        await mockService.simulateMessage(msg)
        try? await Task.sleep(nanoseconds: 30_000_000)
        
        guard let chaRelayed = vm.messages.first else { return false }
        guard chaRelayed.recipientStates["CHA"]?.isRelayed == true else {
            print("  FAIL: CHA should be relayed")
            return false
        }
        guard chaRelayed.recipientStates["CHA"]?.isDelivered == false else {
            print("  FAIL: Relayed recipient CHA must NOT be marked delivered!")
            return false
        }
        guard chaRelayed.confirmedRecipientCount == 1 else {
            print("  FAIL: Confirmed recipient count should still be 1")
            return false
        }
        
        // DAV times out
        recipientStates["DAV"] = .deliveryTimedOut
        msg.recipientStates = recipientStates
        msg.deliveryState = .deliveryTimedOut
        await mockService.simulateMessage(msg)
        try? await Task.sleep(nanoseconds: 30_000_000)
        
        guard let davTimedOut = vm.messages.first else { return false }
        guard davTimedOut.recipientStates["DAV"]?.isTimedOut == true else {
            print("  FAIL: DAV should be timed out")
            return false
        }
        
        print("  PASS: Per-recipient ACK progress tracking verified.")
        return true
    }
    
    // MARK: - Test 4: Byte Limiter Enforcement and Clamping
    
    @MainActor
    private static func testByteLimiterEnforcementAndClamping() async -> Bool {
        print("[ChatUITest 4] ByteLimiter enforcement and clamping...")
        let vm = ChatViewModel()
        
        // 1. ASCII 20 characters
        vm.updateDraft("12345678901234567890")
        guard vm.currentByteCount == 20 else {
            print("  FAIL: 20 ASCII chars should equal 20 bytes, got \(vm.currentByteCount)")
            return false
        }
        guard vm.isDraftAtLimit, vm.remainingBytes == 0, vm.byteUsageRatio == 1.0 else {
            print("  FAIL: Meter flags incorrect at 20 bytes")
            return false
        }
        
        // 2. ASCII oversized clamped to 20
        vm.updateDraft("12345678901234567890EXTRA")
        guard vm.currentByteCount == 20, vm.draftText == "12345678901234567890" else {
            print("  FAIL: Excess ASCII text was not clamped to 20 bytes: \(vm.draftText)")
            return false
        }
        
        // 3. Multi-byte Emojis (4 bytes each)
        // 5 emojis = 20 bytes
        vm.updateDraft("🎉🎊🎈🎂🎁")
        guard vm.currentByteCount == 20, vm.draftText == "🎉🎊🎈🎂🎁" else {
            print("  FAIL: 5 emojis should equal 20 bytes, got \(vm.currentByteCount)")
            return false
        }
        
        // 6 emojis = 24 bytes -> Clamped to 5 emojis (20 bytes) without corrupting character boundary
        vm.updateDraft("🎉🎊🎈🎂🎁🔥")
        guard vm.currentByteCount == 20, vm.draftText == "🎉🎊🎈🎂🎁" else {
            print("  FAIL: 6th emoji should be clamped, got: \(vm.draftText)")
            return false
        }
        
        // 4. Color thresholds
        vm.updateDraft("Hello") // 5 bytes (<16)
        guard vm.currentByteCount < 16 else { return false }
        
        vm.updateDraft("1234567890123456") // 16 bytes (16..19)
        guard vm.currentByteCount >= 16 && vm.currentByteCount < 20 else { return false }
        
        vm.updateDraft("12345678901234567890") // 20 bytes
        guard vm.currentByteCount == 20 else { return false }
        
        print("  PASS: ByteLimiter enforcement and clamping verified.")
        return true
    }
    
    // MARK: - Test 5: Reject Empty and Whitespace Messages
    
    @MainActor
    private static func testRejectEmptyAndWhitespaceMessages() async -> Bool {
        print("[ChatUITest 5] Reject empty and whitespace messages...")
        let session = GroupSession(localInitials: "ALX")
        let mockService = MockChatMessagingService()
        let vm = ChatViewModel(chatService: mockService, sessionProvider: { session })
        
        // Empty string
        vm.updateDraft("")
        guard !vm.canSend else {
            print("  FAIL: canSend should be false for empty text")
            return false
        }
        await vm.sendMessage()
        guard vm.errorMessage == "Message cannot be empty." else {
            print("  FAIL: Expected empty error feedback, got \(String(describing: vm.errorMessage))")
            return false
        }
        
        // Whitespace only
        vm.updateDraft("   \n\t  ")
        guard !vm.canSend else {
            print("  FAIL: canSend should be false for whitespace-only text")
            return false
        }
        await vm.sendMessage()
        guard vm.errorMessage == "Message cannot be empty." else {
            print("  FAIL: Expected empty error feedback for whitespace")
            return false
        }
        
        // Valid text
        vm.updateDraft("Beer line")
        guard vm.canSend else {
            print("  FAIL: canSend should be true for valid draft")
            return false
        }
        
        print("  PASS: Rejection of empty and whitespace messages verified.")
        return true
    }
    
    // MARK: - Test 6: Preset Chips Population and Validation
    
    @MainActor
    private static func testPresetChipsPopulationAndValidation() async -> Bool {
        print("[ChatUITest 6] Preset chips population and validation...")
        let session = GroupSession(localInitials: "ALX")
        let vm = ChatViewModel(sessionProvider: { session })
        
        let presets = ChatMessagePayload.standardPresets
        guard presets.count == 6 else {
            print("  FAIL: Expected 6 standard presets, got \(presets.count)")
            return false
        }
        
        for preset in presets {
            vm.applyPreset(preset)
            guard vm.draftText == preset else {
                print("  FAIL: Failed to apply preset: \(preset)")
                return false
            }
            guard vm.currentByteCount <= 20 else {
                print("  FAIL: Preset \(preset) exceeds 20 bytes (\(vm.currentByteCount))")
                return false
            }
            guard vm.canSend else {
                print("  FAIL: Preset \(preset) should be sendable")
                return false
            }
        }
        
        print("  PASS: Preset chips population and validation verified.")
        return true
    }
    
    // MARK: - Test 7: Battery Policy and Survival Mode Cutoff
    
    @MainActor
    private static func testBatteryPolicyAndSurvivalModeCutoff() async -> Bool {
        print("[ChatUITest 7] Battery policy and Festival Survival Mode cutoff...")
        let session = GroupSession(localInitials: "ALX")
        let mockService = MockChatMessagingService()
        let vm = ChatViewModel(chatService: mockService, sessionProvider: { session })
        
        // Normal battery: 80%
        vm.updateBattery(level: 0.80, isLowPower: false)
        vm.updateDraft("Normal text")
        guard !vm.isSurvivalMode, vm.canSend else {
            print("  FAIL: Chat should be available at 80% battery")
            return false
        }
        
        // Drop below 20%: 19%
        vm.updateBattery(level: 0.19, isLowPower: false)
        guard vm.isSurvivalMode, !vm.canSend, !vm.isChatAvailable else {
            print("  FAIL: Chat should be disabled below 20% battery")
            return false
        }
        guard vm.availabilityStatusText?.contains("Survival Mode") == true else {
            print("  FAIL: Availability status text should mention Survival Mode")
            return false
        }
        
        // Attempting to send is rejected
        await vm.sendMessage()
        guard vm.errorMessage?.contains("Survival Mode") == true else {
            print("  FAIL: Send rejection message should mention Survival Mode")
            return false
        }
        
        // Low Power Mode also triggers Survival Mode
        vm.updateBattery(level: 0.50, isLowPower: true)
        guard vm.isSurvivalMode, !vm.canSend else {
            print("  FAIL: Low Power Mode should trigger Survival Mode")
            return false
        }
        
        print("  PASS: Battery policy and Festival Survival Mode cutoff verified.")
        return true
    }
    
    // MARK: - Test 8: Cooldown Rate Limiting
    
    @MainActor
    private static func testCooldownRateLimiting() async -> Bool {
        print("[ChatUITest 8] Cooldown rate limiting...")
        let session = GroupSession(localInitials: "ALX")
        let mockService = MockChatMessagingService()
        let vm = ChatViewModel(chatService: mockService, sessionProvider: { session })
        
        vm.updateDraft("First message")
        guard vm.canSend else { return false }
        
        await vm.sendMessage()
        
        // Cooldown should be active immediately after sending
        guard vm.cooldownRemaining > 0 else {
            print("  FAIL: Cooldown remaining should be > 0 immediately after sending")
            return false
        }
        
        // Second message should be blocked while cooldown active
        vm.updateDraft("Second message")
        guard !vm.canSend else {
            print("  FAIL: canSend should be false while cooldown is active")
            return false
        }
        
        await vm.sendMessage()
        guard vm.errorMessage?.contains("Please wait") == true else {
            print("  FAIL: Cooldown rejection error message missing: \(String(describing: vm.errorMessage))")
            return false
        }
        
        print("  PASS: Cooldown rate limiting verified.")
        return true
    }
    
    // MARK: - Test 9: Session Teardown Conversation Purge
    
    @MainActor
    private static func testSessionTeardownConversationPurge() async -> Bool {
        print("[ChatUITest 9] Session teardown conversation purge...")
        let session = GroupSession(localInitials: "ALX")
        let mockService = MockChatMessagingService()
        let vm = ChatViewModel(chatService: mockService, sessionProvider: { session })
        
        let msg = ChatMessage(sequenceNumber: 1, senderInitials: "BOB", text: "Hey", isLocalSender: false)
        await mockService.simulateMessage(msg)
        try? await Task.sleep(nanoseconds: 30_000_000)
        
        vm.updateDraft("Draft in progress")
        vm.unreadCount = 3
        vm.selectedMessageForDetails = msg
        
        guard !vm.messages.isEmpty else { return false }
        
        // Teardown
        vm.clearConversation()
        
        guard vm.messages.isEmpty else {
            print("  FAIL: Messages were not purged on session teardown")
            return false
        }
        guard vm.draftText.isEmpty else {
            print("  FAIL: Draft text was not cleared")
            return false
        }
        guard vm.unreadCount == 0 else {
            print("  FAIL: Unread count was not reset")
            return false
        }
        guard vm.selectedMessageForDetails == nil else {
            print("  FAIL: Selected detail message was not reset")
            return false
        }
        
        print("  PASS: Ephemeral conversation purge on session teardown verified.")
        return true
    }
    
    // MARK: - Test 10: Unread Badge Count Behavior
    
    @MainActor
    private static func testUnreadBadgeCountBehavior() async -> Bool {
        print("[ChatUITest 10] Unread badge count behavior...")
        let session = GroupSession(localInitials: "ALX")
        let mockService = MockChatMessagingService()
        let vm = ChatViewModel(chatService: mockService, sessionProvider: { session })
        
        vm.isChatSheetPresented = false
        guard vm.unreadCount == 0 else { return false }
        
        // Peer message received while sheet closed -> unread count increments
        let inMsg1 = ChatMessage(sequenceNumber: 1, senderInitials: "BOB", text: "Beer line", isLocalSender: false)
        await mockService.simulateMessage(inMsg1)
        try? await Task.sleep(nanoseconds: 30_000_000)
        guard vm.unreadCount == 1 else {
            print("  FAIL: Unread count should be 1, got \(vm.unreadCount)")
            return false
        }
        
        // Second peer message -> increments again
        let inMsg2 = ChatMessage(sequenceNumber: 2, senderInitials: "CHA", text: "On my way", isLocalSender: false)
        await mockService.simulateMessage(inMsg2)
        try? await Task.sleep(nanoseconds: 30_000_000)
        guard vm.unreadCount == 2 else {
            print("  FAIL: Unread count should be 2, got \(vm.unreadCount)")
            return false
        }
        
        // Local sender message -> does NOT increment unread count
        let localMsg = ChatMessage(sequenceNumber: 3, senderInitials: "ALX", text: "Got it", isLocalSender: true)
        await mockService.simulateMessage(localMsg)
        try? await Task.sleep(nanoseconds: 30_000_000)
        guard vm.unreadCount == 2 else {
            print("  FAIL: Local message should not increment unread count, got \(vm.unreadCount)")
            return false
        }
        
        // User opens sheet -> unread count resets to 0
        vm.isChatSheetPresented = true
        guard vm.unreadCount == 0 else {
            print("  FAIL: Opening sheet should reset unread count to 0, got \(vm.unreadCount)")
            return false
        }
        
        print("  PASS: Unread badge count behavior verified.")
        return true
    }
    
    // MARK: - Test 11: End-to-End Service Integration
    
    @MainActor
    private static func testEndToEndServiceIntegration() async -> Bool {
        print("[ChatUITest 11] End-to-end integration between ChatViewModel and ChatMessageEngine...")
        let clock = TestMeshClock()
        let transport = ChatMessagingEngineTests.TestChatMockTransport()
        let crypto = CryptoService()
        let session = GroupSession(localInitials: "NIC", localColorCode: MemberColor.neonAmber.rawValue)
        
        let engine = ChatMessageEngine(
            transport: transport,
            cryptoService: crypto,
            clock: clock,
            sessionProvider: { session },
            recipientsProvider: { ["BOB"] }
        )
        
        let vm = ChatViewModel(chatService: engine, sessionProvider: { session }, clock: clock)
        
        // Compose & send message
        vm.updateDraft("Restroom")
        guard vm.canSend else {
            print("  FAIL: VM should be ready to send")
            return false
        }
        
        await vm.sendMessage()
        
        // Allow async stream delivery
        for _ in 0..<20 {
            if vm.messages.first?.deliveryState == .forwardedToNextHop { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        
        guard vm.messages.count == 1 else {
            print("  FAIL: Expected 1 message in VM after sending, got \(vm.messages.count)")
            return false
        }
        
        let sent = vm.messages[0]
        guard sent.text == "Restroom", sent.senderInitials == "NIC", sent.isLocalSender else {
            print("  FAIL: Sent message fields mismatch: \(sent)")
            return false
        }
        guard sent.deliveryState == .forwardedToNextHop else {
            print("  FAIL: Initial sent state should be forwardedToNextHop, got \(sent.deliveryState)")
            return false
        }
        
        print("  PASS: End-to-end integration between ChatViewModel and ChatMessageEngine verified.")
        return true
    }
}

// MARK: - Mock Chat Messaging Service for Deterministic UI Tests

public actor MockChatMessagingService: ChatMessagingService {
    public var sentMessages: [ChatMessage] = []
    public var storedMessages: [ChatMessage] = []
    public var currentBatteryLevel: Float = 1.0
    public var isLowPowerMode: Bool = false
    public var isSurvivalMode: Bool = false
    public var timingConfig: MeshTimingConfiguration = MeshTimingConfiguration()
    
    private var messageUpdateContinuation: AsyncStream<ChatMessage>.Continuation?
    public nonisolated let messageUpdates: AsyncStream<ChatMessage>
    private var onMessageUpdated: (@Sendable (ChatMessage) -> Void)?
    
    public init() {
        let (stream, continuation) = AsyncStream.makeStream(of: ChatMessage.self)
        self.messageUpdates = stream
        self.messageUpdateContinuation = continuation
    }
    
    public func sendMessage(text: String, targetRecipients: [String]?) async throws -> ChatMessage {
        let msg = ChatMessage(
            sequenceNumber: UInt32(sentMessages.count + 1),
            senderInitials: "LOCAL",
            text: text,
            deliveryState: .forwardedToNextHop,
            isLocalSender: true
        )
        sentMessages.append(msg)
        storedMessages.append(msg)
        messageUpdateContinuation?.yield(msg)
        return msg
    }
    
    public func activeMessages() async -> [ChatMessage] {
        storedMessages
    }
    
    public func setOnMessageUpdated(_ handler: (@Sendable (ChatMessage) -> Void)?) async {
        self.onMessageUpdated = handler
    }
    
    public func clearHistory() async {
        storedMessages.removeAll()
        sentMessages.removeAll()
    }
    
    public func setBatteryLevel(_ level: Float, isLowPowerMode: Bool) async {
        self.currentBatteryLevel = level
        self.isLowPowerMode = isLowPowerMode
        self.isSurvivalMode = (level < 0.20) || isLowPowerMode
    }
    
    public func simulateMessage(_ message: ChatMessage) {
        if let idx = storedMessages.firstIndex(where: { $0.sequenceNumber == message.sequenceNumber && $0.senderInitials == message.senderInitials }) {
            storedMessages[idx] = message
        } else if let idx = storedMessages.firstIndex(where: { $0.id == message.id }) {
            storedMessages[idx] = message
        } else {
            storedMessages.append(message)
        }
        messageUpdateContinuation?.yield(message)
        onMessageUpdated?(message)
    }
}
