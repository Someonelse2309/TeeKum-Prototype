#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/teekum-carry-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
cat > "$test_dir/main.swift" <<'SWIFT'
import Foundation
assert(CarryMessageStoreTests.runAllTests())
assert(BLEFrameCodecTests.runAllTests())
SWIFT
xcrun swiftc -module-cache-path "$test_dir/cache" \
  'TeeKum Prototype/Core/Models/TeeKumConfiguration.swift' \
  'TeeKum Prototype/Core/Messaging/Models/PacketConstants.swift' \
  'TeeKum Prototype/Core/Messaging/Enums/PacketType.swift' \
  'TeeKum Prototype/Core/Messaging/Enums/PacketCodecError.swift' \
  'TeeKum Prototype/Core/Messaging/Models/CleartextEnvelope.swift' \
  'TeeKum Prototype/Core/Messaging/Models/RawWirePacket.swift' \
  'TeeKum Prototype/Core/Transport/CarryMessageStore.swift' \
  'TeeKum Prototype/Tests/Core/CarryMessageStoreTests.swift' \
  'TeeKum Prototype/Core/Transport/BLEFrameCodec.swift' \
  'TeeKum Prototype/Tests/Core/BLEFrameCodecTests.swift' \
  "$test_dir/main.swift" -o "$test_dir/tests"
"$test_dir/tests"
