//
//  SOSDiagnostics.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

/// Instantaneous diagnostic snapshot of an in-flight or completed SOS event.
public struct SOSDiagnostics: Equatable, Sendable {
    public let eventId: UInt32?
    public let hopCount: UInt8?
    public let retryCount: Int
    public let routeChoice: RouteChoice
    public let stage: AcknowledgementStage
    public let lastDeliveredFriendId: String?
    public let lastRelayResponderId: String?
    public let timestamp: Date
    
    public init(
        eventId: UInt32? = nil,
        hopCount: UInt8? = nil,
        retryCount: Int = 0,
        routeChoice: RouteChoice = .none,
        stage: AcknowledgementStage = .idle,
        lastDeliveredFriendId: String? = nil,
        lastRelayResponderId: String? = nil,
        timestamp: Date = Date()
    ) {
        self.eventId = eventId
        self.hopCount = hopCount
        self.retryCount = retryCount
        self.routeChoice = routeChoice
        self.stage = stage
        self.lastDeliveredFriendId = lastDeliveredFriendId
        self.lastRelayResponderId = lastRelayResponderId
        self.timestamp = timestamp
    }
}
