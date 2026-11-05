//
//  RouteChoice.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

/// Categorization of route choice taken when dispatching or relaying an emergency SOS event.
public enum RouteChoice: Equatable, Sendable, CustomStringConvertible {
    case directPeer(peerId: String)
    case knownRoute(nextHop: String, hopCount: UInt8)
    case boundedFlooding(neighborCount: Int)
    case none
    
    public var description: String {
        switch self {
        case let .directPeer(id):
            return "Direct Peer (\(id))"
        case let .knownRoute(nextHop, hopCount):
            return "Known Route via \(nextHop) (\(hopCount) \(hopCount == 1 ? "hop" : "hops"))"
        case let .boundedFlooding(count):
            return "Bounded Flooding (\(count) \(count == 1 ? "neighbor" : "neighbors"))"
        case .none:
            return "None (No Reachable Peers)"
        }
    }
}
