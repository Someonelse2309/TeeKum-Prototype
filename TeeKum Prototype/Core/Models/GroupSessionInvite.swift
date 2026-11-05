//
//  GroupSessionInvite.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

/// Decoded details from a serverless share link or QR barcode invite.
public struct GroupSessionInvite: Equatable, Sendable {
    public let sessionId: UInt16
    public let sessionName: String
    public let keyData: Data
    
    public init(sessionId: UInt16, sessionName: String, keyData: Data) {
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.keyData = keyData
    }
}
