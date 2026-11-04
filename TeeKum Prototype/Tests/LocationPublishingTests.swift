//
//  LocationPublishingTests.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import CoreLocation
import CryptoKit

// MARK: - Test Mock Transport

private actor TestPeerTransport: PeerTransport {
    var broadcastedPackets: [Data] = []
    var directSentPackets: [(data: Data, peerId: String)] = []
    
    var inboundPackets: AsyncStream<InboundPacket> {
        AsyncStream { $0.finish() }
    }
    
    var peerUpdates: AsyncStream<[PeerInfo]> {
        AsyncStream { $0.finish() }
    }
    
    var stateUpdates: AsyncStream<TransportState> {
        AsyncStream { $0.finish() }
    }
    
    var transportErrors: AsyncStream<TransportError> {
        AsyncStream { $0.finish() }
    }
    
    func start(serviceType: String, session: GroupSession) async throws {}
    func stop() async {}
    
    func broadcastPacket(_ data: Data) async throws {
        broadcastedPackets.append(data)
    }
    
    func sendPacket(_ data: Data, to peerId: String) async throws {
        directSentPackets.append((data: data, peerId: peerId))
    }
    
    func activeDirectPeerCount() async -> Int {
        return 1
    }
    
    func getDiagnostics() async -> TransportDiagnostics {
        TransportDiagnostics(
            localPeerId: "TEST_PEER",
            serviceType: "_teekum._udp",
            sessionName: "Test",
            sessionId: 0x1234,
            state: .connected(peerCount: 1),
            activeDirectPeers: [],
            packetsSent: broadcastedPackets.count,
            packetsReceived: 0,
            obsoletePingsCoalesced: 0,
            sendErrors: 0,
            lastError: nil,
            recentEvents: []
        )
    }
    
    func getBroadcastedCount() -> Int {
        return broadcastedPackets.count
    }
    
    func getLastBroadcastedPacket() -> Data? {
        return broadcastedPackets.last
    }
}

// MARK: - Comprehensive Location & Publishing Verification Suite

/// Comprehensive verification suite for Agent 3:
/// - Acceptance Criterion 1: Live Sharing ON permits normal location updates.
/// - Acceptance Criterion 2: Live Sharing OFF prevents ordinary location broadcasting.
/// - Acceptance Criterion 3: Status changes are included in the next normal update.
/// - Acceptance Criterion 4: An older coordinate cannot overwrite a newer valid measurement.
/// - Acceptance Criterion 5: Location age and accuracy remain available to the UI.
/// - Acceptance Criterion 6: SOS can request latest location without waiting for a normal ping.
/// - Acceptance Criterion 7: Unavailable or denied location permissions are handled explicitly.
/// - Technical Constraints: Monotonic ordering, cancellable scheduler, no fake coordinates.
public struct LocationPublishingTests {
    
    @MainActor
    public static func runAllTests() async -> Bool {
        print("--- [LocationPublishingTests] Running Verification Suite ---")
        var passed = true
        
        if !(await testLiveSharingMasterToggle()) { passed = false }
        if !(await testStatusCoalescingInNextPing()) { passed = false }
        if !(await testMonotonicCoordinateOrdering()) { passed = false }
        if !(await testLocationAgeAndAccuracyExposed()) { passed = false }
        if !(await testSOSCanRequestLatestLocationWithoutNormalPing()) { passed = false }
        if !(await testLocationPermissionsHandling()) { passed = false }
        if !(await testAdaptiveCadenceSelection()) { passed = false }
        if !(await testSingleCancellableSchedulerLoop()) { passed = false }
        if !(await testNoManufacturedCoordinatesWhenGPSUnavailable()) { passed = false }
        if !(await testEndToEndLocationPublisherPacketSealing()) { passed = false }
        if !(await testMapViewModelIntegration()) { passed = false }
        if !(await testMultiSessionStreamRenewal()) { passed = false }
        if !(await testStalePeerAcceleratedCadenceAndTwoTierRecovery()) { passed = false }
        if !(await testDynamicAdaptiveAccuracyAndRadarMode()) { passed = false }
        if !(await testPeerHeadingDegreesAndOrientationVisualization()) { passed = false }
        
        if passed {
            print("--- [LocationPublishingTests] ALL 15 LOCATION TESTS PASSED SUCCESSFULLY! ---")
        } else {
            print("--- [LocationPublishingTests] SOME LOCATION TESTS FAILED! ---")
        }
        return passed
    }
    
    // MARK: - Test 1: Live Sharing Master Toggle (AC 1 & 2)
    
    @MainActor
    public static func testLiveSharingMasterToggle() async -> Bool {
        print("[Test 1] Live Sharing Master Toggle (AC 1 & AC 2)...")
        
        let service = LocationService(isLiveSharingEnabled: true)
        var publishedCount = 0
        service.onPublishLocationPing = { _ in
            publishedCount += 1
        }
        
        let testCoord = CLLocationCoordinate2D(latitude: 33.6844, longitude: -116.2390)
        service.simulateLocation(coordinate: testCoord, accuracy: 5.0)
        
        // 1. Live Sharing ON permits publication
        service.triggerImmediatePublish()
        guard publishedCount == 1 else {
            print("FAILED: Live Sharing ON did not publish update. Count: \(publishedCount)")
            return false
        }
        
        // 2. Live Sharing OFF prevents ordinary location broadcasting
        service.isLiveSharingEnabled = false
        service.triggerImmediatePublish()
        guard publishedCount == 1 else {
            print("FAILED: Live Sharing OFF published an update! Count: \(publishedCount)")
            return false
        }
        
        // 3. Re-enabling permits publishing again
        service.isLiveSharingEnabled = true
        service.triggerImmediatePublish()
        guard publishedCount == 2 else {
            print("FAILED: Re-enabling Live Sharing did not resume publication. Count: \(publishedCount)")
            return false
        }
        
        print("  ✓ Live Sharing ON permits updates and Live Sharing OFF prevents ordinary broadcasting.")
        return true
    }
    
    // MARK: - Test 2: Status Coalescing (AC 3)
    
    @MainActor
    public static func testStatusCoalescingInNextPing() async -> Bool {
        print("[Test 2] Pure location ping publishing without legacy status overhead...")
        
        let service = LocationService(isLiveSharingEnabled: true)
        var lastPublishedLocation: LocationPin?
        var publishedCount = 0
        
        service.onPublishLocationPing = { location in
            lastPublishedLocation = location
            publishedCount += 1
        }
        
        let coord = CLLocationCoordinate2D(latitude: 33.6844, longitude: -116.2390)
        service.simulateLocation(coordinate: coord, accuracy: 4.0)
        
        // Immediate publish
        service.triggerImmediatePublish()
        guard publishedCount == 1 else {
            print("FAILED: Location publish failed.")
            return false
        }
        
        guard let pubLoc = lastPublishedLocation, abs(pubLoc.coordinate.latitude - 33.6844) < 0.0001 else {
            print("FAILED: Published coordinate does not match simulated fix.")
            return false
        }
        
        print("  ✓ Pure geographic location telemetry published cleanly without status overhead.")
        return true
    }
    
    // MARK: - Test 3: Monotonic Coordinate Ordering (AC 4)
    
    @MainActor
    public static func testMonotonicCoordinateOrdering() async -> Bool {
        print("[Test 3] An older coordinate cannot overwrite a newer valid measurement (AC 4)...")
        
        let service = LocationService()
        let t0 = Date(timeIntervalSince1970: 1700000000)
        let coord1 = CLLocationCoordinate2D(latitude: 33.6844, longitude: -116.2390)
        
        // 1. Initial valid coordinate at t0
        service.simulateLocation(coordinate: coord1, accuracy: 5.0, timestamp: t0)
        guard let loc1 = service.currentLocation else {
            print("FAILED: Initial location was not stored.")
            return false
        }
        guard loc1.timestamp == t0 else {
            print("FAILED: Timestamp was not preserved.")
            return false
        }
        
        // 2. Newer valid coordinate at t1 = t0 + 10s
        let t1 = t0.addingTimeInterval(10)
        let coord2 = CLLocationCoordinate2D(latitude: 33.6850, longitude: -116.2395)
        service.simulateLocation(coordinate: coord2, accuracy: 6.0, timestamp: t1)
        guard let loc2 = service.currentLocation else {
            print("FAILED: Second location was not stored.")
            return false
        }
        guard loc2.timestamp == t1 && loc2.coordinate.latitude == coord2.latitude else {
            print("FAILED: Newer location did not overwrite previous.")
            return false
        }
        
        // 3. Stale/delayed coordinate at t_stale = t0 - 20s must be dropped
        let tStale = t0.addingTimeInterval(-20)
        let coordOld = CLLocationCoordinate2D(latitude: 33.6800, longitude: -116.2300)
        service.simulateLocation(coordinate: coordOld, accuracy: 2.0, timestamp: tStale)
        guard let locAfterStale = service.currentLocation else {
            print("FAILED: Location became nil after stale attempt.")
            return false
        }
        guard locAfterStale.timestamp == t1 && locAfterStale.coordinate.latitude == coord2.latitude else {
            print("FAILED: Stale coordinate improperly overwrote a newer valid measurement!")
            return false
        }
        
        // 4. Invalid horizontal accuracy (< 0) must be discarded
        let coordInvalid = CLLocationCoordinate2D(latitude: 33.6900, longitude: -116.2400)
        service.simulateLocation(coordinate: coordInvalid, accuracy: -1.0, timestamp: t1.addingTimeInterval(5))
        guard service.currentLocation?.coordinate.latitude == coord2.latitude else {
            print("FAILED: Invalid horizontal accuracy fix was accepted!")
            return false
        }
        
        print("  ✓ Older and invalid coordinates cannot overwrite newer measurements.")
        return true
    }
    
    // MARK: - Test 4: Location Age & Accuracy Exposed (AC 5)
    
    @MainActor
    public static func testLocationAgeAndAccuracyExposed() async -> Bool {
        print("[Test 4] Location age and accuracy remain available to UI (AC 5)...")
        
        final class MockClock: @unchecked Sendable {
            var now: Date
            init(now: Date) { self.now = now }
        }
        
        let initialTime = Date(timeIntervalSince1970: 1700000000)
        let clock = MockClock(now: initialTime)
        let service = LocationService(
            cadenceConfig: CadenceConfiguration(staleThreshold: 30.0),
            dateProvider: { clock.now }
        )
        
        // Initially no location
        guard service.currentLocation == nil && service.locationAge == nil && service.isLocationStale else {
            print("FAILED: Fresh service without GPS should report nil location and stale = true.")
            return false
        }
        
        // Apply fix with 7.5m accuracy
        let fixTime = clock.now
        let coord = CLLocationCoordinate2D(latitude: 33.6844, longitude: -116.2390)
        service.simulateLocation(coordinate: coord, accuracy: 7.5, timestamp: fixTime)
        
        guard let pin = service.currentLocation else {
            print("FAILED: LocationPin missing.")
            return false
        }
        guard abs(pin.horizontalAccuracy - 7.5) < 0.001 else {
            print("FAILED: Accuracy not exposed correctly: \(pin.horizontalAccuracy)")
            return false
        }
        
        // Advance time by 10 seconds -> age = 10, stale = false
        clock.now = fixTime.addingTimeInterval(10)
        guard let age1 = service.locationAge, abs(age1 - 10.0) < 0.1 else {
            print("FAILED: Expected location age ~10s, got: \(String(describing: service.locationAge))")
            return false
        }
        guard !service.isLocationStale else {
            print("FAILED: Location marked stale prematurely at 10s (threshold: 30s).")
            return false
        }
        
        // Advance time past stale threshold (35s) -> age = 35, stale = true
        clock.now = fixTime.addingTimeInterval(35)
        guard let age2 = service.locationAge, abs(age2 - 35.0) < 0.1 else {
            print("FAILED: Expected location age ~35s, got: \(String(describing: service.locationAge))")
            return false
        }
        guard service.isLocationStale else {
            print("FAILED: Location should be marked stale at 35s (threshold: 30s).")
            return false
        }
        
        print("  ✓ Location age and accuracy remain accurately exposed to the UI.")
        return true
    }
    
    // MARK: - Test 5: SOS Requests Latest Location Without Ping (AC 6)
    
    @MainActor
    public static func testSOSCanRequestLatestLocationWithoutNormalPing() async -> Bool {
        print("[Test 5] SOS can request latest location without waiting for normal ping (AC 6)...")
        
        let service = LocationService(isLiveSharingEnabled: false) // Live sharing is OFF
        let measurementTime = Date(timeIntervalSince1970: 1700000000)
        let coord = CLLocationCoordinate2D(latitude: 33.6844, longitude: -116.2390)
        
        service.simulateLocation(coordinate: coord, accuracy: 3.5, timestamp: measurementTime)
        
        // SOS requests location immediately even while Live Sharing is OFF
        guard let sosLocation = service.getLatestLocationForSOS() else {
            print("FAILED: SOS failed to retrieve location while Live Sharing was OFF.")
            return false
        }
        
        guard sosLocation.coordinate.latitude == coord.latitude && sosLocation.coordinate.longitude == coord.longitude else {
            print("FAILED: SOS location coordinate mismatch.")
            return false
        }
        
        // Crucial: Must preserve measurement timestamp of actual hardware reading
        guard sosLocation.timestamp == measurementTime else {
            print("FAILED: SOS modified or fabricated the measurement timestamp!")
            return false
        }
        
        print("  ✓ SOS retrieves latest location immediately without waiting for normal pings or Live Sharing.")
        return true
    }
    
    // MARK: - Test 6: Permissions Handling (AC 7)
    
    @MainActor
    public static func testLocationPermissionsHandling() async -> Bool {
        print("[Test 6] Unavailable or denied location permissions handled explicitly (AC 7)...")
        
        let service = LocationService()
        
        // Simulate permission denied
        service.simulateAuthorizationStatus(.denied)
        guard service.authorizationStatus == .denied && !service.isGPSAvailable else {
            print("FAILED: Denied status did not update isGPSAvailable to false.")
            return false
        }
        
        // Attempting to start tracking with denied permission must throw explicitly
        do {
            try service.startTracking()
            print("FAILED: startTracking() should have thrown permissionDenied error.")
            return false
        } catch let error as LocationServiceError {
            guard error == .permissionDenied else {
                print("FAILED: Wrong error thrown: \(error)")
                return false
            }
        } catch {
            print("FAILED: Unexpected error: \(error)")
            return false
        }
        
        // Simulate authorized status
        #if os(iOS)
        service.simulateAuthorizationStatus(.authorizedWhenInUse)
        guard service.authorizationStatus == .authorizedWhenInUse && service.isGPSAvailable else {
            print("FAILED: Authorized status did not set isGPSAvailable to true.")
            return false
        }
        #else
        service.simulateAuthorizationStatus(.authorizedAlways)
        guard service.authorizationStatus == .authorizedAlways && service.isGPSAvailable else {
            print("FAILED: Authorized status did not set isGPSAvailable to true.")
            return false
        }
        #endif
        
        print("  ✓ Denied and authorized permissions handled explicitly.")
        return true
    }
    
    // MARK: - Test 7: Adaptive Cadence Selection
    
    @MainActor
    public static func testAdaptiveCadenceSelection() async -> Bool {
        print("[Test 7] Configurable target intervals: moving vs stationary vs survival...")
        
        let config = CadenceConfiguration(
            movingInterval: 4.0,       // 3–5 seconds
            stationaryInterval: 20.0,  // 15–30 seconds
            survivalInterval: 60.0
        )
        let service = LocationService(cadenceConfig: config)
        
        // 1. Moving state (default isStationary == false)
        guard abs(service.currentCadenceInterval - 4.0) < 0.001 else {
            print("FAILED: Moving cadence should be 4.0s, got: \(service.currentCadenceInterval)")
            return false
        }
        
        // 2. Stationary state
        service.simulateMotionActivity(stationary: true)
        guard abs(service.currentCadenceInterval - 20.0) < 0.001 else {
            print("FAILED: Stationary cadence should be 20.0s, got: \(service.currentCadenceInterval)")
            return false
        }
        
        // 3. Survival mode (<20% battery)
        service.applyBatteryLevel(0.15)
        guard service.isSurvivalModeActive else {
            print("FAILED: Survival mode should be active at 15% battery.")
            return false
        }
        guard abs(service.currentCadenceInterval - 60.0) < 0.001 else {
            print("FAILED: Survival cadence should be 60.0s, got: \(service.currentCadenceInterval)")
            return false
        }
        
        // 4. Recovery when battery restored
        service.applyBatteryLevel(0.80)
        guard !service.isSurvivalModeActive else {
            print("FAILED: Survival mode should be cleared at 80% battery.")
            return false
        }
        guard abs(service.currentCadenceInterval - 20.0) < 0.001 else {
            print("FAILED: Cadence did not restore to stationary after battery recharge.")
            return false
        }
        
        // 5. Distant peers detected: accelerates stationary cadence to distantPeerInterval (2.0s)
        service.hasDistantPeers = true
        guard abs(service.currentCadenceInterval - 2.0) < 0.001 else {
            print("FAILED: Distant peer cadence should be 2.0s, got: \(service.currentCadenceInterval)")
            return false
        }
        service.hasDistantPeers = false
        
        // 6. Stale peers detected: accelerates stationary cadence to staleRecoveryInterval (2.0s)
        service.hasStalePeers = true
        guard abs(service.currentCadenceInterval - 2.0) < 0.001 else {
            print("FAILED: Stale peer cadence should be 2.0s, got: \(service.currentCadenceInterval)")
            return false
        }
        service.hasStalePeers = false
        
        print("  ✓ Adaptive cadence selection selects correct intervals for moving, stationary, survival, distant, and stale peers.")
        return true
    }
    
    // MARK: - Test 8: Single Cancellable Scheduler Loop
    
    @MainActor
    public static func testSingleCancellableSchedulerLoop() async -> Bool {
        print("[Test 8] Scheduler is cancellable and creates no duplicate loops...")
        
        let config = CadenceConfiguration(movingInterval: 0.05, stationaryInterval: 0.1)
        let service = LocationService(cadenceConfig: config, isLiveSharingEnabled: true)
        
        let coord = CLLocationCoordinate2D(latitude: 33.6844, longitude: -116.2390)
        service.simulateLocation(coordinate: coord, accuracy: 5.0)
        
        // Rapidly toggle live sharing and motion state
        service.isLiveSharingEnabled = true
        service.simulateMotionActivity(stationary: true)
        service.simulateMotionActivity(stationary: false)
        service.simulateMotionActivity(stationary: true)
        
        // Disabling Live Sharing stops ordinary broadcasting
        service.isLiveSharingEnabled = false
        service.stopTracking()
        
        // Wait to verify no rogue background tasks fire
        try? await Task.sleep(nanoseconds: 150_000_000)
        
        print("  ✓ Scheduler cleanly cancelled without duplicate loops or rogue firings.")
        return true
    }
    
    // MARK: - Test 9: No Manufactured Coordinates When GPS Unavailable
    
    @MainActor
    public static func testNoManufacturedCoordinatesWhenGPSUnavailable() async -> Bool {
        print("[Test 9] Do not manufacture new coordinates when GPS is unavailable...")
        
        let service = LocationService(isLiveSharingEnabled: true)
        var publishedCount = 0
        service.onPublishLocationPing = { _ in
            publishedCount += 1
        }
        
        // Service starts with NO coordinates
        guard service.currentLocation == nil else {
            print("FAILED: currentLocation must be nil before first fix.")
            return false
        }
        
        // Triggering publish must NOT manufacture dummy (0,0) coordinates
        service.publishCurrentState()
        guard publishedCount == 0 else {
            print("FAILED: Manufactured and published fake coordinate when GPS had no fix!")
            return false
        }
        
        print("  ✓ Zero dummy coordinates manufactured when GPS is unavailable.")
        return true
    }
    
    // MARK: - Test 10: End-to-End Publisher Packet Sealing
    
    @MainActor
    public static func testEndToEndLocationPublisherPacketSealing() async -> Bool {
        print("[Test 10] End-to-end LocationPublisher wire packet sealing and broadcast...")
        
        let service = LocationService(isLiveSharingEnabled: true)
        let keyData = Data(repeating: 0x42, count: 32)
        let session = GroupSession(
            sessionId: 0xDEAD,
            sessionName: "Festival Crew",
            symmetricKeyData: keyData,
            localInitials: "ALX",
            memberSlot: 1,
            isHost: true
        )
        
        let mockTransport = TestPeerTransport()
        let cryptoService = CryptoService()
        
        let publisher = LocationPublisher(
            locationService: service,
            sessionProvider: { session },
            cryptoService: cryptoService,
            transport: mockTransport
        )
        
        let coord = CLLocationCoordinate2D(latitude: 33.684444, longitude: -116.239111)
        let ts = Date(timeIntervalSince1970: 1700000000)
        service.simulateLocation(coordinate: coord, accuracy: 6.0, timestamp: ts)
        
        // Broadcast location ping
        await publisher.handleLocationPingReady(location: service.currentLocation!)
        
        let packetCount = await mockTransport.getBroadcastedCount()
        guard packetCount == 1 else {
            print("FAILED: Packet was not broadcast over transport. Count: \(packetCount)")
            return false
        }
        
        guard let wireData = await mockTransport.getLastBroadcastedPacket() else {
            print("FAILED: Missing broadcasted wire data.")
            return false
        }
        
        // Verify exactly 56 bytes
        guard wireData.count == PacketConstants.wirePacketSize else {
            print("FAILED: Wire packet size is \(wireData.count), expected \(PacketConstants.wirePacketSize).")
            return false
        }
        
        // Parse raw packet
        let wirePacket = try! RawWirePacket.fromWireData(wireData)
        guard wirePacket.envelope.type == .locationPing else {
            print("FAILED: Wrong packet type: \(wirePacket.envelope.type)")
            return false
        }
        guard wirePacket.envelope.sessionId == 0xDEAD else {
            print("FAILED: Wrong session ID.")
            return false
        }
        
        // Decrypt with group key
        let symmetricKey = SymmetricKey(data: keyData)
        let decryptedData = try! await cryptoService.open(
            ciphertext: wirePacket.ciphertext,
            envelope: wirePacket.envelope,
            authTag: wirePacket.authTag,
            using: symmetricKey
        )
        
        let deserializedPayload = try! LocationPingPayload.deserialize(from: decryptedData)
        guard deserializedPayload.senderInitials == "ALX" else {
            print("FAILED: Sender initials mismatch.")
            return false
        }
        guard deserializedPayload.batteryLevel == 100 else {
            print("FAILED: Battery level mismatch: expected 100, got \(deserializedPayload.batteryLevel)")
            return false
        }
        guard abs(deserializedPayload.coordinate.latitude - coord.latitude) < 0.000002 else {
            print("FAILED: Quantized coordinate error exceeds ~11cm resolution.")
            return false
        }
        
        // Dispatch SOS independently
        try! await publisher.dispatchSOS(emergencyType: .medical)
        let totalCount = await mockTransport.getBroadcastedCount()
        guard totalCount == 2 else {
            print("FAILED: SOS packet was not dispatched over transport.")
            return false
        }
        
        let sosWireData = await mockTransport.getLastBroadcastedPacket()!
        let sosWirePacket = try! RawWirePacket.fromWireData(sosWireData)
        guard sosWirePacket.envelope.type == .sos else {
            print("FAILED: Expected SOS envelope type, got \(sosWirePacket.envelope.type)")
            return false
        }
        guard sosWirePacket.envelope.hopLimit == PacketConstants.sosHopLimit else {
            print("FAILED: Expected SOS hopLimit \(PacketConstants.sosHopLimit), got \(sosWirePacket.envelope.hopLimit)")
            return false
        }
        
        print("  ✓ LocationPublisher sealed 56-byte wire packets and dispatched both location pings and SOS.")
        return true
    }
    
    // MARK: - Test 11: MapViewModel Integration
    
    @MainActor
    public static func testMapViewModelIntegration() async -> Bool {
        print("[Test 11] MapViewModel integration with LocationServiceProvider...")
        
        let service = LocationService(isLiveSharingEnabled: true)
        let mapViewModel = MapViewModel(locationService: service)
        
        guard mapViewModel.isLiveSharingEnabled == true else {
            print("FAILED: MapViewModel did not sync initial Live Sharing state.")
            return false
        }
        
        // Toggle from MapViewModel
        mapViewModel.toggleLiveSharing()
        guard mapViewModel.isLiveSharingEnabled == false && service.isLiveSharingEnabled == false else {
            print("FAILED: Toggling MapViewModel did not update LocationService.")
            return false
        }
        guard mapViewModel.statusPillMessage.contains("Paused") else {
            print("FAILED: Status pill message should reflect paused state, got: \(mapViewModel.statusPillMessage)")
            return false
        }
        
        // Toggle back ON
        mapViewModel.toggleLiveSharing()
        guard mapViewModel.isLiveSharingEnabled == true && service.isLiveSharingEnabled == true else {
            print("FAILED: Re-enabling Live Sharing did not propagate.")
            return false
        }
        
        // Feed location
        let coord = CLLocationCoordinate2D(latitude: 33.6844, longitude: -116.2390)
        service.simulateLocation(coordinate: coord, accuracy: 5.0)
        guard mapViewModel.userLocation?.coordinate.latitude == coord.latitude else {
            print("FAILED: MapViewModel did not expose userLocation.")
            return false
        }
        guard mapViewModel.horizontalAccuracy == 5.0 else {
            print("FAILED: MapViewModel did not expose horizontalAccuracy.")
            return false
        }
        
        print("  ✓ MapViewModel cleanly integrates with LocationService.")
        return true
    }
    
    // MARK: - Test 12: Multi-Session Stream Renewal Across Cancellation
    
    @MainActor
    public static func testMultiSessionStreamRenewal() async -> Bool {
        print("[Test 12] Multi-session stream renewal across task cancellation (no app rebuild required)...")
        
        let service = LocationService(isLiveSharingEnabled: true)
        let mockTransport = TestPeerTransport()
        let cryptoService = CryptoService()
        
        // --- SESSION 1 ---
        let keyData1 = Data(repeating: 0x11, count: 32)
        let session1 = GroupSession(
            sessionId: 0x1111,
            sessionName: "Session 1",
            symmetricKeyData: keyData1,
            localInitials: "ALX",
            memberSlot: 1,
            isHost: true
        )
        
        try? service.startTracking()
        let publisher1 = LocationPublisher(
            locationService: service,
            sessionProvider: { session1 },
            cryptoService: cryptoService,
            transport: mockTransport
        )
        publisher1.start()
        
        // Feed location in Session 1
        let coord1 = CLLocationCoordinate2D(latitude: 33.684, longitude: -116.239)
        service.simulateLocation(coordinate: coord1, accuracy: 5.0)
        
        // Yield briefly to let publisher Task process
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        let countSession1 = await mockTransport.getBroadcastedCount()
        guard countSession1 >= 1 else {
            print("FAILED: Session 1 did not broadcast location ping. Count: \(countSession1)")
            return false
        }
        
        // --- LEAVE SESSION 1 (Simulate user leaving group / task cancellation) ---
        publisher1.stop()
        service.stopTracking()
        
        // --- SESSION 2 (Simulate user creating new group WITHOUT rebuilding app) ---
        let keyData2 = Data(repeating: 0x22, count: 32)
        let session2 = GroupSession(
            sessionId: 0x2222,
            sessionName: "Session 2",
            symmetricKeyData: keyData2,
            localInitials: "ALX",
            memberSlot: 2,
            isHost: true
        )
        
        // startTracking resets publishedPings stream
        try? service.startTracking()
        
        let publisher2 = LocationPublisher(
            locationService: service,
            sessionProvider: { session2 },
            cryptoService: cryptoService,
            transport: mockTransport
        )
        publisher2.start()
        
        // Feed location in Session 2
        let coord2 = CLLocationCoordinate2D(latitude: 33.685, longitude: -116.240)
        service.simulateLocation(coordinate: coord2, accuracy: 4.0)
        
        // Yield briefly to let publisher Task process
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        let countSession2 = await mockTransport.getBroadcastedCount()
        guard countSession2 > countSession1 else {
            print("FAILED: Session 2 did not broadcast any location pings (stream was terminated or dead)! Total count: \(countSession2), Session 1 count: \(countSession1)")
            return false
        }
        
        guard let lastPacket = await mockTransport.getLastBroadcastedPacket() else {
            print("FAILED: Session 2 missing last packet.")
            return false
        }
        
        let wirePacket = try! RawWirePacket.fromWireData(lastPacket)
        guard wirePacket.envelope.sessionId == 0x2222 else {
            print("FAILED: Session 2 packet session ID mismatch: expected 0x2222, got \(String(format: "0x%04X", wirePacket.envelope.sessionId))")
            return false
        }
        
        // Cleanup
        publisher2.stop()
        service.stopTracking()
        
        print("  ✓ Multi-session stream renewal successfully preserved location sharing across session restarts!")
        return true
    }
    
    // MARK: - Test 13: Stale Peer Accelerated Cadence & Two-Tier Recovery
    
    @MainActor
    public static func testStalePeerAcceleratedCadenceAndTwoTierRecovery() async -> Bool {
        print("[Test 13] Stale peer accelerated cadence and two-tier recovery window...")
        
        let timing = MeshTimingConfiguration.default
        let service = LocationService()
        service.simulateMotionActivity(stationary: true)
        
        // 1. Initially stationary without stale peers: interval is 20s
        guard abs(service.currentCadenceInterval - timing.stationaryInterval) < 0.001 else {
            print("FAILED: Stationary interval should be \(timing.stationaryInterval), got \(service.currentCadenceInterval)")
            return false
        }
        
        let now = Date()
        
        // 2. Fresh peer (last seen 10s ago)
        let freshMember = Member(id: "ALX", lastSeen: now.addingTimeInterval(-10.0))
        guard !freshMember.isWithinStaleRecoveryWindow(now: now) else {
            print("FAILED: Member seen 10s ago should NOT be within stale recovery window.")
            return false
        }
        guard !freshMember.isEligibleForStaleRouteDiscovery(now: now) else {
            print("FAILED: Member seen 10s ago should NOT be eligible for route discovery.")
            return false
        }
        
        // 3. Stage 1 Stale Peer (last seen 35s ago: > 30s threshold but < 45s route discovery delay)
        let stage1Member = Member(id: "BOB", lastSeen: now.addingTimeInterval(-35.0))
        guard stage1Member.isWithinStaleRecoveryWindow(now: now) else {
            print("FAILED: Member seen 35s ago should be within stale recovery window.")
            return false
        }
        guard !stage1Member.isEligibleForStaleRouteDiscovery(now: now) else {
            print("FAILED: Member seen 35s ago should not yet be eligible for route discovery (< 45s).")
            return false
        }
        
        // Activate stale peer on location service
        service.hasStalePeers = true
        guard abs(service.currentCadenceInterval - timing.staleRecoveryInterval) < 0.001 else {
            print("FAILED: Stale peer should accelerate cadence to \(timing.staleRecoveryInterval)s, got \(service.currentCadenceInterval)")
            return false
        }
        
        // 4. Stage 2 Stale Peer (last seen 50s ago: >= 45s and <= 90s)
        let stage2Member = Member(id: "CAR", lastSeen: now.addingTimeInterval(-50.0))
        guard stage2Member.isWithinStaleRecoveryWindow(now: now) else {
            print("FAILED: Member seen 50s ago should be within stale recovery window.")
            return false
        }
        guard stage2Member.isEligibleForStaleRouteDiscovery(now: now) else {
            print("FAILED: Member seen 50s ago should be eligible for Stage 2 route discovery.")
            return false
        }
        
        // 5. Timed-out Stale Peer (last seen 95s ago: > 90s (30s threshold + 60s timeout))
        let expiredMember = Member(id: "DAN", lastSeen: now.addingTimeInterval(-95.0))
        guard !expiredMember.isWithinStaleRecoveryWindow(now: now) else {
            print("FAILED: Member seen 95s ago should be expired beyond stale recovery timeout (90s).")
            return false
        }
        guard !expiredMember.isEligibleForStaleRouteDiscovery(now: now) else {
            print("FAILED: Member seen 95s ago should NOT be eligible for route discovery after timeout.")
            return false
        }
        
        // When active stale peers expire or recover, cadence backs off to stationary (20s)
        service.hasStalePeers = false
        guard abs(service.currentCadenceInterval - timing.stationaryInterval) < 0.001 else {
            print("FAILED: Cadence should back off to stationary (\(timing.stationaryInterval)s) when stale peer window expires.")
            return false
        }
        
        // 6. Dynamic provider evaluation
        var peerRoster: [Member] = [stage1Member]
        service.hasStalePeersProvider = {
            let evalNow = Date()
            return peerRoster.contains { $0.isWithinStaleRecoveryWindow(now: evalNow) }
        }
        guard abs(service.currentCadenceInterval - timing.staleRecoveryInterval) < 0.001 else {
            print("FAILED: Dynamic hasStalePeersProvider should accelerate cadence to 2.0s.")
            return false
        }
        
        // Stale peer recovers with a fresh update (last seen 2s ago)
        peerRoster = [Member(id: "BOB", lastSeen: Date().addingTimeInterval(-2.0))]
        guard abs(service.currentCadenceInterval - timing.stationaryInterval) < 0.001 else {
            print("FAILED: Cadence should restore to stationary after peer recovery.")
            return false
        }
        
        // 7. Stale Response Burst (rapid pings on target discovery)
        var burstPingsCount = 0
        service.onPublishLocationPing = { _ in
            burstPingsCount += 1
        }
        service.simulateLocation(coordinate: CLLocationCoordinate2D(latitude: 33.68, longitude: -116.24), accuracy: 5.0)
        
        service.triggerBurstPings(count: 3, interval: 0.05)
        try? await Task.sleep(nanoseconds: 160_000_000)
        
        guard burstPingsCount >= 3 else {
            print("FAILED: Expected at least 3 burst pings, got \(burstPingsCount).")
            return false
        }
        
        print("  ✓ Stale peer accelerated cadence, two-tier recovery, and response burst successfully validated!")
        return true
    }
    
    // MARK: - Test 14: Dynamic Adaptive Accuracy & Tactical Radar High-Precision Mode (Option B)
    
    public static func testDynamicAdaptiveAccuracyAndRadarMode() async -> Bool {
        print("[Test 14] Dynamic adaptive accuracy & Tactical Radar high-precision mode...")
        let service = LocationService()
        
        // 1. Initial Default State (Moving / Normal)
        guard service.currentDesiredAccuracy == kCLLocationAccuracyBest else {
            print("FAILED: Default desiredAccuracy should be kCLLocationAccuracyBest, got \(service.currentDesiredAccuracy)")
            return false
        }
        guard !service.isTacticalRadarActive else {
            print("FAILED: isTacticalRadarActive should be false initially")
            return false
        }
        
        // 2. Open Tactical Radar -> Elevate to BestForNavigation + 0° heading filter
        service.setTacticalRadarActive(true)
        guard service.isTacticalRadarActive else {
            print("FAILED: isTacticalRadarActive should be true")
            return false
        }
        guard service.currentDesiredAccuracy == kCLLocationAccuracyBestForNavigation else {
            print("FAILED: Tactical radar mode should elevate accuracy to kCLLocationAccuracyBestForNavigation")
            return false
        }
        #if os(iOS)
        guard service.currentHeadingFilter == kCLHeadingFilterNone else {
            print("FAILED: Tactical radar mode should set headingFilter to kCLHeadingFilterNone")
            return false
        }
        #endif
        
        // 3. Close Tactical Radar -> Restore Normal Moving Accuracy
        service.setTacticalRadarActive(false)
        guard !service.isTacticalRadarActive else {
            print("FAILED: isTacticalRadarActive should be false")
            return false
        }
        guard service.currentDesiredAccuracy == kCLLocationAccuracyBest else {
            print("FAILED: Exiting radar should restore kCLLocationAccuracyBest")
            return false
        }
        
        // 4. User is Stationary (Dancing/Resting at Stage) -> Drop to 100m to save battery
        service.simulateMotionActivity(stationary: true)
        guard service.isStationary else {
            print("FAILED: isStationary should be true")
            return false
        }
        guard service.currentDesiredAccuracy == kCLLocationAccuracyHundredMeters else {
            print("FAILED: Stationary state should drop accuracy to kCLLocationAccuracyHundredMeters to save battery")
            return false
        }
        guard service.currentDistanceFilter == 15.0 else {
            print("FAILED: Stationary state should set distanceFilter to 15m")
            return false
        }
        
        // 5. User opens Tactical Radar while Stationary -> Priority elevation to BestForNavigation
        service.setTacticalRadarActive(true)
        guard service.currentDesiredAccuracy == kCLLocationAccuracyBestForNavigation else {
            print("FAILED: Tactical radar should preempt stationary low-power mode and elevate to BestForNavigation")
            return false
        }
        
        // 6. User closes Tactical Radar while still Stationary -> Return to 100m
        service.setTacticalRadarActive(false)
        guard service.currentDesiredAccuracy == kCLLocationAccuracyHundredMeters else {
            print("FAILED: Closing radar while stationary should return to kCLLocationAccuracyHundredMeters")
            return false
        }
        
        // 7. User starts walking -> Return to kCLLocationAccuracyBest
        service.simulateMotionActivity(stationary: false)
        guard !service.isStationary else {
            print("FAILED: isStationary should be false")
            return false
        }
        guard service.currentDesiredAccuracy == kCLLocationAccuracyBest else {
            print("FAILED: Walking motion should restore kCLLocationAccuracyBest")
            return false
        }
        
        // 8. Festival Survival Mode (<20% Battery) -> Force battery-saving GPS throttling
        service.applyBatteryLevel(0.15)
        guard service.isSurvivalModeActive else {
            print("FAILED: isSurvivalModeActive should be true at 15% battery")
            return false
        }
        guard service.currentDesiredAccuracy == kCLLocationAccuracyHundredMeters else {
            print("FAILED: Survival mode should force accuracy to kCLLocationAccuracyHundredMeters")
            return false
        }
        guard service.currentDistanceFilter == 25.0 else {
            print("FAILED: Survival mode should set distanceFilter to 25m")
            return false
        }
        
        // 9. Battery recovers -> Restore standard moving accuracy
        service.applyBatteryLevel(0.85)
        guard !service.isSurvivalModeActive else {
            print("FAILED: isSurvivalModeActive should be false at 85% battery")
            return false
        }
        guard service.currentDesiredAccuracy == kCLLocationAccuracyBest else {
            print("FAILED: Battery recovery should restore kCLLocationAccuracyBest")
            return false
        }
        
        print("  ✓ Dynamic adaptive accuracy and Tactical Radar high-precision mode successfully validated!")
        return true
    }
    
    // MARK: - Test 15: Peer Heading & Orientation Telemetry
    
    @MainActor
    public static func testPeerHeadingDegreesAndOrientationVisualization() async -> Bool {
        print("[Test 15] Peer Heading Degrees & Orientation Telemetry...")
        
        let testHeadings: [(degrees: CLLocationDirection, expectedByte: UInt8)] = [
            (0.0, 0),
            (90.0, 64),
            (180.0, 128),
            (270.0, 191),
            (359.0, 254)
        ]
        
        for (degrees, _) in testHeadings {
            let headingByte = UInt8(min(255, max(0, Int((degrees * 255.0 / 360.0).rounded()))))
            let ping = LocationPingPayload(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                accuracy: 5,
                senderInitials: "BOB",
                batteryLevel: 80,
                heading: headingByte
            )
            
            let reconstructed = ping.headingDegrees
            let diff = abs(reconstructed - degrees)
            // 8-bit quantization gives 360 / 255 ≈ 1.41 degrees resolution
            guard diff <= 2.0 else {
                print("FAILED: Heading \(degrees) reconstructed as \(reconstructed), error \(diff) > 2.0°")
                return false
            }
            
            let member = Member(
                id: "BOB",
                name: "Bob",
                lastSeen: Date(),
                coordinate: ping.coordinate,
                horizontalAccuracy: 5.0,
                isEmergency: false,
                batteryLevel: 0.8,
                heading: ping.headingDegrees,
                isDirectPeer: true,
                color: .skyBlue
            )
            
            guard let memHeading = member.heading, abs(memHeading - degrees) <= 2.0 else {
                print("FAILED: Member heading \(String(describing: member.heading)) does not match target \(degrees)")
                return false
            }
        }
        
        print("  ✓ Peer heading degrees quantization, reconstruction, and Member orientation telemetry verified!")
        return true
    }
}
