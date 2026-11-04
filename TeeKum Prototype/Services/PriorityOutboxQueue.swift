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
    public let isRelay: Bool
    
    public nonisolated init(
        id: UUID = UUID(),
        packetData: Data,
        packetType: PacketType,
        destinationPeerId: String? = nil,
        createdAt: Date = Date(),
        attemptCount: Int = 0,
        maxRetries: Int = 2,
        isUrgent: Bool,
        isRelay: Bool = false
    ) {
        self.id = id
        self.packetData = packetData
        self.packetType = packetType
        self.destinationPeerId = destinationPeerId
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.maxRetries = maxRetries
        self.isUrgent = isUrgent
        self.isRelay = isRelay
    }
}

/// A prioritized multi-lane transmission queue that:
/// 1. Prioritizes urgent packets (SOS emergency sirens, delivery ACKs, meeting point changes).
/// 2. Coalesces normal periodic location pings so that newer GPS fixes immediately overwrite
///    older, unsent fixes, preventing radio saturation and obsolete coordinate flooding.
/// 3. Manages a bounded ring buffer FIFO lane for stranger mesh relay packets (Decision 7: 32 pkts max).
/// 4. Enforces bounded capacity limits to prevent out-of-memory under network congestion.
nonisolated public final class PriorityOutboxQueue: @unchecked Sendable {
    /// Bounded capacity for the high-priority urgent lane (Decision 7: 16 packets).
    public let maxUrgentCapacity: Int
    
    /// Bounded capacity for stranger blind relaying (Decision 7: 32 packets ring buffer).
    public let maxRelayCapacity: Int
    
    /// Bounded capacity for local group chat FIFO lane (Decision D17: 16 packets).
    public let maxChatCapacity: Int
    
    /// High-priority FIFO queue (SOS, ACK, Meeting updates).
    private var urgentLane: [OutboxItem] = []
    
    /// Dedicated local group chat FIFO queue (Decision D17: 20-character chat messages).
    private var localChatLane: [OutboxItem] = []
    
    /// Normal lane keyed by destination peer ID (`nil` key represented as empty string for broadcast).
    /// Holds strictly the freshest single location ping per destination.
    private var normalCoalescedLane: [String: OutboxItem] = [:]
    
    /// Stranger relay ring buffer queue (Decision 7: 32 packets, drop-head on overflow).
    private var strangerRelayLane: [OutboxItem] = []
    
    /// Counter tracking obsolete location pings coalesced and discarded before transmission.
    public private(set) var obsoletePingsCoalesced: Int = 0
    
    /// Counter tracking stranger relay packets dropped due to ring buffer overflow.
    public private(set) var relayPacketsDroppedOverflow: Int = 0
    
    /// Counter tracking urgent packets dropped due to urgent lane capacity overflow.
    public private(set) var urgentPacketsDroppedOverflow: Int = 0
    
    /// Counter tracking local chat packets dropped due to chat lane capacity overflow.
    public private(set) var chatPacketsDroppedOverflow: Int = 0
    
    /// Total packets dropped across all lanes due to queue saturation.
    public var totalQueueSaturationDrops: Int {
        relayPacketsDroppedOverflow + urgentPacketsDroppedOverflow + chatPacketsDroppedOverflow
    }
    
    public init(maxUrgentCapacity: Int = 16, maxRelayCapacity: Int = 32, maxChatCapacity: Int = 16) {
        self.maxUrgentCapacity = maxUrgentCapacity
        self.maxRelayCapacity = maxRelayCapacity
        self.maxChatCapacity = maxChatCapacity
    }
    
    /// Total count of items currently waiting in the outbox across all lanes.
    public var totalQueuedCount: Int {
        urgentLane.count + localChatLane.count + normalCoalescedLane.count + strangerRelayLane.count
    }
    
    /// True when there are no items waiting to be sent across any lane.
    public var isEmpty: Bool {
        urgentLane.isEmpty && localChatLane.isEmpty && normalCoalescedLane.isEmpty && strangerRelayLane.isEmpty
    }
    
    /// Current count of pending urgent packets.
    public var urgentCount: Int {
        urgentLane.count
    }
    
    /// Current count of pending local chat packets.
    public var chatCount: Int {
        localChatLane.count
    }
    
    /// Current count of pending stranger relay packets.
    public var relayCount: Int {
        strangerRelayLane.count
    }
    
    /// Snapshot of current queue depth across all lanes.
    public var queueDepth: QueueDepth {
        QueueDepth(
            urgentCount: urgentLane.count,
            normalCount: normalCoalescedLane.count,
            relayCount: strangerRelayLane.count,
            chatCount: localChatLane.count
        )
    }
    
    /// Enqueues a packet for transmission.
    ///
    /// - Parameters:
    ///   - data: Exactly 56 bytes of binary wire data.
    ///   - destinationPeerId: Destination peer ID or nil for broadcast.
    ///   - isRelay: True if forwarding a stranger's opaque packet on the communal mesh.
    /// - Returns: The created `OutboxItem`.
    /// - Throws: `TransportError.invalidPacketSize` or `TransportError.queueFull`.
    @discardableResult
    public func enqueue(
        data: Data,
        destinationPeerId: String? = nil,
        isRelay: Bool = false
    ) throws -> OutboxItem {
        guard data.count == PacketConstants.wirePacketSize else {
            throw TransportError.invalidPacketSize
        }
        
        let byte0 = data[data.startIndex]
        let typeRaw = byte0 & 0x0F
        guard let packetType = PacketType(rawValue: typeRaw) else {
            throw TransportError.sendFailed("Unrecognized packet type in Byte 0: \(typeRaw)")
        }
        
        if isRelay {
            // Communal Stranger Relay Lane (Ring buffer FIFO: 32 max)
            if strangerRelayLane.count >= maxRelayCapacity {
                // Drop oldest unforwarded packet (drop-head)
                strangerRelayLane.removeFirst()
                relayPacketsDroppedOverflow += 1
            }
            
            let item = OutboxItem(
                packetData: data,
                packetType: packetType,
                destinationPeerId: destinationPeerId,
                attemptCount: 0,
                maxRetries: MeshTimingConfiguration.default.distantLinkMaxRetries,
                isUrgent: false,
                isRelay: true
            )
            strangerRelayLane.append(item)
            return item
        }
        
        let isUrgent = (packetType == .sos || packetType == .ack || packetType == .meetingUpdate || packetType == .uwbTokenExchange)
        
        if isUrgent {
            guard urgentLane.count < maxUrgentCapacity else {
                urgentPacketsDroppedOverflow += 1
                throw TransportError.queueFull("Urgent outbox queue is full (\(urgentLane.count)/\(maxUrgentCapacity) items).")
            }
            
            let item = OutboxItem(
                packetData: data,
                packetType: packetType,
                destinationPeerId: destinationPeerId,
                attemptCount: 0,
                maxRetries: 2,
                isUrgent: true,
                isRelay: false
            )
            urgentLane.append(item)
            return item
        } else if packetType == .chatMessage {
            // Tier 3: Local Group Chat FIFO Lane (Cap: 16)
            guard localChatLane.count < maxChatCapacity else {
                chatPacketsDroppedOverflow += 1
                throw TransportError.queueFull("Chat outbox queue is full (\(localChatLane.count)/\(maxChatCapacity) items).")
            }
            
            let item = OutboxItem(
                packetData: data,
                packetType: packetType,
                destinationPeerId: destinationPeerId,
                attemptCount: 0,
                maxRetries: MeshTimingConfiguration.default.chatMaxRetries,
                isUrgent: false,
                isRelay: false
            )
            localChatLane.append(item)
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
                isUrgent: false,
                isRelay: false
            )
            normalCoalescedLane[destKey] = item
            return item
        }
    }
    
    /// Pops the next highest-priority item for transmission.
    /// Priority order:
    /// 1. Urgent lane (SOS, ACK, Meeting updates).
    /// 2. Local chat lane (local user chat messages FIFO, max 16).
    /// 3. Stranger relay lane (communal mesh packets forwarded for other devices).
    /// 4. Normal coalesced lane (local routine location pings).
    public func dequeue() -> OutboxItem? {
        if !urgentLane.isEmpty {
            return urgentLane.removeFirst()
        }
        
        if !localChatLane.isEmpty {
            return localChatLane.removeFirst()
        }
        
        if !strangerRelayLane.isEmpty {
            return strangerRelayLane.removeFirst()
        }
        
        if let (key, item) = normalCoalescedLane.first {
            normalCoalescedLane.removeValue(forKey: key)
            return item
        }
        
        return nil
    }
    
    /// Re-queues an item that encountered a transient transmission failure, if retries remain.
    public func requeueForRetry(_ item: OutboxItem) -> Bool {
        guard item.attemptCount < item.maxRetries else {
            return false
        }
        
        var retryItem = item
        retryItem.attemptCount += 1
        
        if item.isUrgent {
            urgentLane.insert(retryItem, at: 0) // Preempt back to front of urgent lane
            return true
        } else if item.packetType == .chatMessage {
            localChatLane.insert(retryItem, at: 0) // Preempt back to front of local chat lane
            return true
        } else if item.isRelay {
            strangerRelayLane.insert(retryItem, at: 0) // Preempt back to front of stranger relay lane
            return true
        } else {
            let destKey = item.destinationPeerId ?? ""
            normalCoalescedLane[destKey] = retryItem
            return true
        }
    }
    
    /// Clears only pending stranger relay packets (e.g. when relay participation is disabled).
    public func clearRelayQueue() {
        strangerRelayLane.removeAll()
    }
    
    /// Clears all pending packets across all lanes.
    public func clear() {
        urgentLane.removeAll()
        localChatLane.removeAll()
        normalCoalescedLane.removeAll()
        strangerRelayLane.removeAll()
    }
}
