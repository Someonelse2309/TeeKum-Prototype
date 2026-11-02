//
//  TeeKumApp.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import SwiftUI
import CoreLocation
import CryptoKit

@main
struct TeeKumApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var connections = SessionConnectionModel()
    private var sessionViewModel: GroupSessionViewModel { connections.sessionViewModel }
    private var locationService: LocationService { connections.locationService }
    private var mapViewModel: MapViewModel { connections.mapViewModel }
    private var sosViewModel: SOSViewModel { connections.sosViewModel }
    private var meetingPointViewModel: MeetingPointViewModel { connections.meetingPointViewModel }

    var body: some Scene {
        WindowGroup {
            Group {
                if sessionViewModel.hasActiveSession, let session = sessionViewModel.activeSession {
                    MainMapView(
                        mapViewModel: mapViewModel,
                        sessionViewModel: sessionViewModel,
                        sosViewModel: sosViewModel,
                        meetingPointViewModel: meetingPointViewModel
                    )
                    .task(id: session.createdAt) {
                        await connections.runSessionLifecycle(session: session)
                    }
                } else {
                    GroupPairingView(sessionViewModel: sessionViewModel)
                        .task {
                            await connections.stopActiveSession()
                        }
                }
            }
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, newPhase in
                sessionViewModel.expireSessionIfNeeded()
                if newPhase == .active && sessionViewModel.hasActiveSession {
                    locationService.publishCurrentState()
                }
            }
            .onChange(of: locationService.isSurvivalModeActive) { _, isSurvival in
                if isSurvival {
                    Task {
                        await LiveActivityManager.shared.endSessionActivity()
                    }
                }
            }
            .onChange(of: meetingPointViewModel.activeMeetingPoint) { _, _ in
                Task {
                    await connections.updateLiveActivityTelemetry()
                }
            }
            .onChange(of: sosViewModel.activeIncomingAlert) { _, _ in
                Task {
                    await connections.updateLiveActivityTelemetry()
                }
            }
            .onChange(of: sosViewModel.deliveryState) { _, _ in
                Task {
                    await connections.updateLiveActivityTelemetry()
                }
            }
            .onOpenURL { url in
                connections.handleIncomingURL(url)
            }
            .task {
                if ProcessInfo.processInfo.arguments.contains("-runAllTests") {
                    print(">>> RUNNING ALL AUTOMATED TESTS <<<")
                    fflush(stdout)
                    let results = [
                        PacketCodecTests.runAllTests(),
                        PeerTransportTests.runAllTests(),
                        await CryptoSecurityTests.runAllTests(),
                        await LocationPublishingTests.runAllTests(),
                        await UIStateTests.runAllTests(),
                        await SOSEndToEndTests.runAllTests(),
                        await LiveActivityTests.runAllTests(),
                        await Phase1RegressionTests.runAllTests()
                    ]
                    print(results.allSatisfy { $0 } ? ">>> ALL AUTOMATED TESTS PASSED <<<" : ">>> AUTOMATED TESTS FAILED <<<")
                    print(">>> ALL AUTOMATED TEST RUNS FINISHED <<<")
                    fflush(stdout)
                } else {
                    if ProcessInfo.processInfo.arguments.contains("-runUITests") {
                        _ = await UIStateTests.runAllTests()
                        fflush(stdout)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-runSOSTests") {
                        _ = await SOSEndToEndTests.runAllTests()
                        fflush(stdout)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-simulateSession") {
                        let dummyKey = Data(repeating: 0x55, count: 32)
                        let session = GroupSession(
                            sessionId: 0x4321,
                            sessionName: "Festival Crew",
                            symmetricKeyData: dummyKey,
                            localInitials: "NIC"
                        )
                        sessionViewModel.setActiveSession(session)
                    }
                }
            }
        }
    }
    
}
