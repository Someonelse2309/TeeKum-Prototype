//
//  PriorityOutboxQueue.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

/// An item queued in the radio transmission outbox.
nonisolated public struct OutboxItem: Identifiable, Sendable {
    public let id: UUID
    public let packetData: Data
    public let packetType: PacketType
    public let destinationPeerId: String? // nil means broadcast to all direct peers
    public let createdAt: Date
    public var attemptCount: Int
    public let maxRetries: Int
    public let isUrgent: Bool
    
    public init(
        id: UUID = UUID(),
        packetData: Data,
        packetType: PacketType,
        destinationPeerId: String? = nil,
        createdAt: Date = Date(),
        attemptCount: Int = 0,
        maxRetries: Int = 2,
        isUrgent: Bool
    ) {
        self.id = id
        self.packetData = packetData
        self.packetType = packetType
        self.destinationPeerId = destinationPeerId
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.maxRetries = maxRetries
        self.isUrgent = isUrgent
    }
}

/// A dual-lane transmission queue that:
/// 1. Prioritizes urgent packets (SOS emergency sirens, delivery ACKs, meeting point changes).
/// 2. Coalesces normal periodic location pings so that newer GPS fixes immediately overwrite
///    older, unsent fixes, preventing radio saturation and obsolete coordinate flooding.
/// 3. Enforces bounded capacity limits to prevent out-of-memory under network congestion.
nonisolated public final class PriorityOutboxQueue: @unchecked Sendable {
    /// Bounded capacity for the high-priority urgent lane.
    public let maxUrgentCapacity: Int
    
    /// High-priority FIFO queue (SOS, ACK, Meeting updates).
    private var urgentLane: [OutboxItem] = []
    
    /// Normal lane keyed by destination peer ID (`nil` key represented as empty string for broadcast).
    /// Holds strictly the freshest single location ping per destination.
    private var normalCoalescedLane: [String: OutboxItem] = [:]
    
    /// Counter tracking obsolete location pings coalesced and discarded before transmission.
    public private(set) var obsoletePingsCoalesced: Int = 0
    
    public init(maxUrgentCapacity: Int = 50) {
        self.maxUrgentCapacity = maxUrgentCapacity
    }
    
    /// Total count of items currently waiting in the outbox.
    public var totalQueuedCount: Int {
        urgentLane.count + normalCoalescedLane.count
    }
    
    /// True when there are no items waiting to be sent.
    public var isEmpty: Bool {
        urgentLane.isEmpty && normalCoalescedLane.isEmpty
    }
    
    /// Current count of pending urgent packets.
    public var urgentCount: Int {
        urgentLane.count
    }
    
    /// Enqueues a packet for transmission.
    ///
    /// - Parameters:
    ///   - data: Exactly 66 bytes of binary wire data.
    ///   - destinationPeerId: Destination peer ID or nil for broadcast.
    /// - Returns: The created `OutboxItem`.
    /// - Throws: `TransportError.invalidPacketSize` or `TransportError.queueFull`.
    @discardableResult
    public func enqueue(data: Data, destinationPeerId: String? = nil) throws -> OutboxItem {
        guard data.count == PacketConstants.wirePacketSize else {
            throw TransportError.invalidPacketSize
        }
        
        let byte0 = data[data.startIndex]
        let typeRaw = byte0 & 0x0F
        guard let packetType = PacketType(rawValue: typeRaw) else {
            throw TransportError.sendFailed("Unrecognized packet type in Byte 0: \(typeRaw)")
        }
        
        let isUrgent = (packetType == .sos || packetType == .ack || packetType == .meetingUpdate)
        
        if isUrgent {
            guard urgentLane.count < maxUrgentCapacity else {
                throw TransportError.queueFull("Urgent outbox queue is full (\(urgentLane.count)/\(maxUrgentCapacity) items).")
            }
            
            let item = OutboxItem(
                packetData: data,
                packetType: packetType,
                destinationPeerId: destinationPeerId,
                attemptCount: 0,
                maxRetries: 2,
                isUrgent: true
            )
            urgentLane.append(item)
            return item
        } else {
            // Normal Location Ping lane: Coalesce per destination
            let destKey = destinationPeerId ?? ""
            if normalCoalescedLane[destKey] != nil {
                obsoletePingsCoalesced += 1
            }
            
            let item = OutboxItem(
                packetData: data,
                packetType: packetType,
                destinationPeerId: destinationPeerId,
                attemptCount: 0,
                maxRetries: 0, // Stale location pings are not retried on failure
                isUrgent: false
            )
            normalCoalescedLane[destKey] = item
            return item
        }
    }
    
    /// Pops the next highest-priority item for transmission.
    /// Urgent lane takes absolute precedence over normal location pings.
    public func dequeue() -> OutboxItem? {
        if !urgentLane.isEmpty {
            return urgentLane.removeFirst()
        }
        
        if let (key, item) = normalCoalescedLane.first {
            normalCoalescedLane.removeValue(forKey: key)
            return item
        }
        
        return nil
    }
    
    /// Re-queues an item that encountered a transient transmission failure, if retries remain.
    public func requeueForRetry(_ item: OutboxItem) -> Bool {
        guard urgentLane.count < maxUrgentCapacity, item.isUrgent, item.attemptCount < item.maxRetries else {
            return false
        }
        
        var retryItem = item
        retryItem.attemptCount += 1
        urgentLane.insert(retryItem, at: 0) // Preempt back to front of urgent lane
        return true
    }
    
    /// Clears all pending packets in the queue.
    public func clear() {
        urgentLane.removeAll()
        normalCoalescedLane.removeAll()
    }
}
