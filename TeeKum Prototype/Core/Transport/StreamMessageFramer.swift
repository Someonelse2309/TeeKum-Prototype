//
//  StreamMessageFramer.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation

/// Manages chunk buffering, frame delimitation, and stream resynchronization for stream-based
/// peer-to-peer connections (such as TCP over AWDL / Wi-Fi Direct).
///
/// Because stream transports do not guarantee packet boundaries, a single read may deliver:
/// 1. A partial 56-byte packet (e.g. 20 bytes).
/// 2. Multiple coalesced packets (e.g. 112 bytes for 2 packets).
/// 3. Split packets (e.g. 70 bytes = 1 full packet + 14 bytes of the next).
///
/// `StreamMessageFramer` buffers incomplete chunks, extracts complete 56-byte packets,
/// scans forward across corrupted bytes to recover synchronization, and prevents memory exhaustion.
public final class StreamMessageFramer: @unchecked Sendable {
    /// Internal byte buffer accumulating stream data.
    private var buffer = Data()
    
    /// Maximum allowed buffer capacity before triggering an overflow error to prevent unbounded memory growth.
    public let maxBufferSize: Int
    
    /// Creates a new framer instance with a bounded buffer limit.
    public init(maxBufferSize: Int = 65536) {
        self.maxBufferSize = maxBufferSize
    }
    
    /// Current number of unconsumed bytes awaiting more stream data.
    public var unconsumedByteCount: Int {
        buffer.count
    }
    
    /// Ingests a raw byte chunk from a stream read, buffers partial packets, and returns
    /// all extracted, valid 56-byte binary wire frames.
    ///
    /// - Parameter chunk: The newly received bytes from `NWConnection.receive`.
    /// - Returns: An array of complete 56-byte packet data buffers ready for protocol decoding.
    /// - Throws: `TransportError` if the buffer overflows or encounters unrecoverable corruption.
    public func processIncomingChunk(_ chunk: Data) throws -> [Data] {
        guard !chunk.isEmpty else { return [] }
        
        buffer.append(chunk)
        
        guard buffer.count <= maxBufferSize else {
            buffer.removeAll()
            throw TransportError.listenerFailed("Stream buffer overflow: exceeded max buffer size of \(maxBufferSize) bytes.")
        }
        
        var frames: [Data] = []
        
        while buffer.count >= PacketConstants.wirePacketSize {
            let startIndex = buffer.startIndex
            let byte0 = buffer[startIndex]
            let version = (byte0 >> 4) & 0x0F
            let typeRaw = byte0 & 0x0F
            
            // Check if Byte 0 contains valid protocol version (0x01) and recognized PacketType (0x01...0x06)
            if version == PacketConstants.protocolVersion, PacketType(rawValue: typeRaw) != nil {
                let frameEnd = startIndex + PacketConstants.wirePacketSize
                let frameData = buffer.subdata(in: startIndex..<frameEnd)
                frames.append(frameData)
                buffer.removeSubrange(startIndex..<frameEnd)
            } else {
                // Stream misalignment detected: discard the leading byte to seek the next valid packet header
                buffer.removeFirst(1)
            }
        }
        
        return frames
    }
    
    /// Clears the accumulation buffer (e.g. upon socket reset or disconnect).
    public func reset() {
        buffer.removeAll()
    }
}
