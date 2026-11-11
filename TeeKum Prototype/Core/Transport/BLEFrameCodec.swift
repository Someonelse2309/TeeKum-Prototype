import Foundation

/// Offset-prefixed fragments preserve the existing 56-byte encrypted wire format.
nonisolated struct BLEFrameCodec {
    private var buffer: Data?

    static func fragments(_ frame: Data, maximumValueLength: Int) -> [Data] {
        guard frame.count == 56, maximumValueLength >= 2 else { return [] }
        let size = min(56, maximumValueLength - 1)
        return stride(from: 0, to: 56, by: size).map { offset in
            Data([UInt8(offset)]) + frame.subdata(in: offset..<min(56, offset + size))
        }
    }

    mutating func receive(_ fragment: Data) -> Data? {
        guard let offset = fragment.first else { buffer = nil; return nil }
        if offset == 0 { buffer = Data() }
        guard var next = buffer, next.count == Int(offset), fragment.count > 1,
              next.count + fragment.count - 1 <= 56 else { buffer = nil; return nil }
        next.append(fragment.dropFirst())
        if next.count == 56 { buffer = nil; return next }
        buffer = next
        return nil
    }
}
