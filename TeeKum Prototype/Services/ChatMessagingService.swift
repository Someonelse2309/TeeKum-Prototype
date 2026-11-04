//
//  ChatMessagingService.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import Foundation

/// Approved messaging service protocol governing the group chat engine.
///
/// Keeps all messaging business logic (cryptographic sealing, multi-hop radio dispatch,
/// FIFO outbox priority, ACK tracking, retries, stranger relaying, and ephemeral storage)
/// strictly inside the service layer, keeping ViewModels purely focused on presentation state.
public protocol ChatMessagingService: Actor {
    /// Accepts, validates, encodes, encrypts, and broadcasts a 20-byte chat message.
    @discardableResult
    func sendMessage(text: String, targetRecipients: [String]?) async throws -> ChatMessage
    
    /// Returns active ephemeral in-memory message history (max 50 messages).
    func activeMessages() async -> [ChatMessage]
    
    /// Asynchronous stream yielding updated or newly delivered messages for UI observation.
    nonisolated var messageUpdates: AsyncStream<ChatMessage> { get }
    
    /// Direct callback hook for reactive message updates.
    func setOnMessageUpdated(_ handler: (@Sendable (ChatMessage) -> Void)?) async
    
    /// Clears all ephemeral chat history and in-flight tracking on group session teardown.
    func clearHistory() async
    
    /// Hardware power state.
    var currentBatteryLevel: Float { get async }
    var isLowPowerMode: Bool { get async }
    var isSurvivalMode: Bool { get async }
    
    /// Active timing configuration parameters.
    var timingConfig: MeshTimingConfiguration { get async }
    
    /// Updates hardware power metrics.
    func setBatteryLevel(_ level: Float, isLowPowerMode: Bool) async
}

// Conform ChatMessageEngine to ChatMessagingService
extension ChatMessageEngine: ChatMessagingService {}
