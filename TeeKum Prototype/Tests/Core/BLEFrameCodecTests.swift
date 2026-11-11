import Foundation

nonisolated enum BLEFrameCodecTests {
    static func runAllTests() -> Bool {
        let frame = Data(0..<56)
        for mtu in [2, 20, 56, 57, 185, 512] {
            let chunks = BLEFrameCodec.fragments(frame, maximumValueLength: mtu)
            var receiver = BLEFrameCodec()
            var results: [Data] = []
            for chunk in chunks {
                assert(chunk.count <= mtu)
                if let result = receiver.receive(chunk) { results.append(result) }
            }
            assert(results == [frame])
        }
        assert(BLEFrameCodec.fragments(frame, maximumValueLength: 1).isEmpty)
        assert(BLEFrameCodec.fragments(Data(), maximumValueLength: 20).isEmpty)
        let chunks = BLEFrameCodec.fragments(frame, maximumValueLength: 20)
        var receiver = BLEFrameCodec()
        assert(receiver.receive(chunks[1]) == nil)
        assert(receiver.receive(chunks[0]) == nil)
        assert(receiver.receive(chunks[2]) == nil) // Missing middle must discard partial data.
        assert(receiver.receive(Data(repeating: 0, count: 58)) == nil)
        var results: [Data] = []
        for chunk in chunks + chunks {
            if let result = receiver.receive(chunk) { results.append(result) }
        }
        assert(results == [frame, frame])
        print("BLEFrameCodecTests passed: MTU boundaries, missing fragments, malformed input, consecutive frames")
        return true
    }
}
