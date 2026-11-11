import Foundation
import CoreBluetooth

/// Core Bluetooth delegates stay on the main queue; the transport actor owns routing.
@MainActor
final class BLEPeerLink: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private let serviceID = CBUUID(string: "A974CB10-7752-4F44-81A8-03047F278201")
    private let dataID = CBUUID(string: "A974CB11-7752-4F44-81A8-03047F278201")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheralManager!
    private var characteristic: CBMutableCharacteristic?
    private var remotes: [UUID: CBPeripheral] = [:]
    private var writable: [UUID: CBCharacteristic] = [:]
    private var subscribers: [UUID: CBCentral] = [:]
    private var buffers: [String: BLEFrameCodec] = [:]
    private var queues: [String: [Data]] = [:]
    private var writing: Set<UUID> = []
    private var active = false
    private let receive: @Sendable (Data, String) -> Void
    private let peersChanged: @Sendable ([String]) -> Void
    private let report: @Sendable (String) -> Void

    init(receive: @escaping @Sendable (Data, String) -> Void,
         peersChanged: @escaping @Sendable ([String]) -> Void,
         report: @escaping @Sendable (String) -> Void) {
        self.receive = receive
        self.peersChanged = peersChanged
        self.report = report
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        peripheral = CBPeripheralManager(delegate: self, queue: .main)
    }

    func start() {
        active = true
        scan()
        publish()
    }

    func stop() {
        active = false
        central.stopScan()
        peripheral.stopAdvertising()
        peripheral.removeAllServices()
        for remote in remotes.values { central.cancelPeripheralConnection(remote) }
        remotes.removeAll(); writable.removeAll(); subscribers.removeAll()
        queues.removeAll(); buffers.removeAll(); writing.removeAll()
        characteristic = nil
        updatePeers()
    }

    private func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return "powered on"
        case .poweredOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission denied"
        case .unsupported: return "unsupported"
        case .resetting: return "resetting"
        case .unknown: return "initializing"
        @unknown default: return "unknown"
        }
    }

    private func scan() {
        guard active, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [serviceID])
    }

    private func publish() {
        guard active, peripheral.state == .poweredOn, characteristic == nil else { return }
        let value = CBMutableCharacteristic(type: dataID, properties: [.write, .notify], value: nil, permissions: [.writeable])
        characteristic = value
        let service = CBMutableService(type: serviceID, primary: true)
        service.characteristics = [value]
        peripheral.add(service)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        report("BLE central: \(stateDescription(central.state))")
        if central.state != .poweredOn {
            remotes.removeAll(); writable.removeAll(); writing.removeAll()
            queues = queues.filter { !$0.key.hasPrefix("ble-p:") }
            buffers = buffers.filter { !$0.key.hasPrefix("ble-p:") }
            updatePeers()
        }
        scan()
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        report("BLE peripheral: \(stateDescription(peripheral.state))")
        if peripheral.state != .poweredOn {
            characteristic = nil
            subscribers.removeAll()
            queues = queues.filter { !$0.key.hasPrefix("ble-c:") }
            buffers = buffers.filter { !$0.key.hasPrefix("ble-c:") }
            updatePeers()
        }
        publish()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard active, error == nil else {
            if let error { report("BLE publish: \(error.localizedDescription)") }
            return
        }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceID]])
    }

    func centralManager(_ central: CBCentralManager, didDiscover remote: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard active, remotes[remote.identifier] == nil, remotes.count < 8 else { return }
        remotes[remote.identifier] = remote
        remote.delegate = self
        central.connect(remote)
    }

    func centralManager(_ central: CBCentralManager, didConnect remote: CBPeripheral) {
        guard active else { central.cancelPeripheralConnection(remote); return }
        remote.discoverServices([serviceID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect remote: CBPeripheral, error: Error?) {
        lost(remote)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral remote: CBPeripheral, error: Error?) {
        lost(remote)
    }

    private func lost(_ remote: CBPeripheral) {
        let id = "ble-p:\(remote.identifier)"
        remotes.removeValue(forKey: remote.identifier)
        writable.removeValue(forKey: remote.identifier)
        writing.remove(remote.identifier)
        queues.removeValue(forKey: id); buffers.removeValue(forKey: id)
        updatePeers()
        // Restart scanning so the same peripheral can be discovered after a disconnection.
        central.stopScan(); scan()
    }

    func peripheral(_ remote: CBPeripheral, didDiscoverServices error: Error?) {
        guard active, error == nil else { central.cancelPeripheralConnection(remote); return }
        for service in remote.services ?? [] where service.uuid == serviceID {
            remote.discoverCharacteristics([dataID], for: service)
        }
    }

    func peripheral(_ remote: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard active, error == nil, let value = service.characteristics?.first(where: { $0.uuid == dataID }) else {
            central.cancelPeripheralConnection(remote); return
        }
        writable[remote.identifier] = value
        remote.setNotifyValue(true, for: value)
    }

    func peripheral(_ remote: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard active, error == nil, characteristic.isNotifying else {
            central.cancelPeripheralConnection(remote); return
        }
        updatePeers()
    }

    func peripheral(_ remote: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard active, error == nil, let data = characteristic.value else { return }
        ingest(data, from: "ble-p:\(remote.identifier)")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard active, subscribers.count < 8 else { return }
        subscribers[central.identifier] = central
        updatePeers()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribers.removeValue(forKey: central.identifier)
        let id = "ble-c:\(central.identifier)"
        queues.removeValue(forKey: id); buffers.removeValue(forKey: id)
        updatePeers()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard active, request.characteristic.uuid == dataID, request.offset == 0,
                  let value = request.value, value.count >= 2, value.count <= 57,
                  subscribers[request.central.identifier] != nil else {
                peripheral.respond(to: request, withResult: .requestNotSupported); continue
            }
            ingest(value, from: "ble-c:\(request.central.identifier)")
            peripheral.respond(to: request, withResult: .success)
        }
    }

    private func ingest(_ fragment: Data, from peer: String) {
        if let frame = buffers[peer, default: BLEFrameCodec()].receive(fragment) {
            receive(frame, peer)
        }
    }

    /// Bound queues and fragment at the negotiated ATT limit; never interleave frames per link.
    func send(_ frame: Data, to target: String?) {
        guard active, frame.count == 56 else { return }
        let ids = target.map { [$0] } ?? peerIDs()
        for id in ids {
            guard (queues[id]?.count ?? 0) < 256 else { report("BLE queue full: \(id)"); continue }
            var limit = 20
            if id.hasPrefix("ble-p:"), let uuid = UUID(uuidString: String(id.dropFirst(6))), let remote = remotes[uuid] {
                limit = remote.maximumWriteValueLength(for: .withResponse)
            } else if id.hasPrefix("ble-c:"), let uuid = UUID(uuidString: String(id.dropFirst(6))), let subscriber = subscribers[uuid] {
                limit = subscriber.maximumUpdateValueLength
            } else { continue }
            let fragments = BLEFrameCodec.fragments(frame, maximumValueLength: limit)
            guard (queues[id]?.count ?? 0) + fragments.count <= 256 else {
                report("BLE queue full: \(id)"); continue
            }
            queues[id, default: []].append(contentsOf: fragments)
        }
        flush()
    }

    private func flush() {
        for (uuid, remote) in remotes {
            let id = "ble-p:\(uuid)"
            guard !writing.contains(uuid), let value = writable[uuid], value.isNotifying,
                  let fragment = queues[id]?.first else { continue }
            writing.insert(uuid)
            remote.writeValue(fragment, for: value, type: .withResponse)
        }
        guard let value = characteristic else { return }
        for (uuid, subscriber) in subscribers {
            let id = "ble-c:\(uuid)"
            while let fragment = queues[id]?.first {
                guard peripheral.updateValue(fragment, for: value, onSubscribedCentrals: [subscriber]) else { return }
                queues[id]?.removeFirst()
            }
        }
    }

    func peripheral(_ remote: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        writing.remove(remote.identifier)
        if let error {
            report("BLE write: \(error.localizedDescription)")
            central.cancelPeripheralConnection(remote)
            return
        }
        let id = "ble-p:\(remote.identifier)"
        if queues[id]?.isEmpty == false { queues[id]?.removeFirst() }
        flush()
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) { flush() }

    private func peerIDs() -> [String] {
        writable.filter { $0.value.isNotifying }.keys.map { "ble-p:\($0)" }
        + subscribers.keys.map { "ble-c:\($0)" }
    }

    private func updatePeers() { peersChanged(peerIDs()) }
}
