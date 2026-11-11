#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/teekum-chat-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
cat > "$test_dir/Runner.swift" <<'SWIFT'
import Foundation
@main struct Runner {
    static func main() async {
        let passed = await ChatMessagingEngineTests.runAllTests()
        if !passed { exit(1) }
    }
}
SWIFT
xcrun swiftc -parse-as-library -module-cache-path "$test_dir/cache" \
  'TeeKum Prototype/Core/Models/TeeKumConfiguration.swift' \
  'TeeKum Prototype/Core/Messaging/Models/PacketConstants.swift' \
  'TeeKum Prototype/Core/Messaging/Enums/PacketType.swift' \
  'TeeKum Prototype/Core/Messaging/Enums/PacketCodecError.swift' \
  'TeeKum Prototype/Core/Messaging/Models/CleartextEnvelope.swift' \
  'TeeKum Prototype/Core/Messaging/Models/RawWirePacket.swift' \
  'TeeKum Prototype/Core/Transport/CarryMessageStore.swift' \
  'TeeKum Prototype/Features/Chat/Services/ChatMessageEngine.swift' \
  'TeeKum Prototype/Core/Security/CryptoService.swift' \
  'TeeKum Prototype/Core/Security/CryptoServiceProtocol.swift' \
  'TeeKum Prototype/Core/Mesh/MeshProtocols.swift' \
  'TeeKum Prototype/Core/Mesh/MeshTimingConfiguration.swift' \
  'TeeKum Prototype/Core/Models/GroupSession.swift' \
  'TeeKum Prototype/Core/Messaging/InitialsCodec.swift' \
  'TeeKum Prototype/Core/Models/ChatMessage.swift' \
  'TeeKum Prototype/Core/Models/Enums/ChatDeliveryState.swift' \
  'TeeKum Prototype/Core/Models/Enums/RecipientDeliveryState.swift' \
  'TeeKum Prototype/Core/Models/Enums/ChatEngineError.swift' \
  'TeeKum Prototype/Core/Models/Enums/InboundChatOutcome.swift' \
  'TeeKum Prototype/Core/Messaging/Payloads/ChatMessagePayload.swift' \
  'TeeKum Prototype/Core/Messaging/Payloads/ACKPayload.swift' \
  'TeeKum Prototype/Core/Mesh/SeenPacketCache.swift' \
  'TeeKum Prototype/Core/Transport/PeerTransport.swift' \
  'TeeKum Prototype/Core/Messaging/Enums/ACKStatus.swift' \
  'TeeKum Prototype/Core/Models/Enums/MemberColor.swift' \
  'TeeKum Prototype/Tests/Integration/ChatMessagingEngineTests.swift' \
  'TeeKum Prototype/Core/Messaging/PriorityOutboxQueue.swift' \
  'TeeKum Prototype/Tests/Core/CarryMessageStoreTests.swift' \
  'TeeKum Prototype/Core/Messaging/Payloads/SOSPayload.swift' \
  'TeeKum Prototype/Core/Models/GroupSessionInvite.swift' \
  'TeeKum Prototype/Core/Mesh/ForwardingRateLimiter.swift' \
  'TeeKum Prototype/Core/Messaging/Enums/SOSType.swift' \
  'TeeKum Prototype/Shared/UI/Formatters.swift' \
  'TeeKum Prototype/Core/Models/LocationPin.swift' \
  "$test_dir/Runner.swift" -o "$test_dir/tests"
"$test_dir/tests"
