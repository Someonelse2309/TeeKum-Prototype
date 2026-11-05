//
//  AppRootView.swift
//  TeeKum Prototype
//
//  Created by Fantasix Team.
//

import SwiftUI

/// Plain root view that presents either GroupPairingView or MainMapView based on session state.
struct AppRootView: View {
    @Bindable var sessionViewModel: GroupSessionViewModel
    var mapViewModel: MapViewModel
    var sosViewModel: SOSViewModel
    var meetingPointViewModel: MeetingPointViewModel
    var chatViewModel: ChatViewModel
    var relayPolicyManager: RelayPolicyManager
    var peerTransport: PeerTransportService
    
    var onSessionStart: (GroupSession) async -> Void
    var onSessionEnd: () async -> Void
    
    var body: some View {
        Group {
            if sessionViewModel.hasActiveSession, let session = sessionViewModel.activeSession {
                MainMapView(
                    mapViewModel: mapViewModel,
                    sessionViewModel: sessionViewModel,
                    sosViewModel: sosViewModel,
                    meetingPointViewModel: meetingPointViewModel,
                    chatViewModel: chatViewModel,
                    relayPolicyManager: relayPolicyManager,
                    peerTransport: peerTransport
                )
                .task(id: session.sessionId) {
                    await onSessionStart(session)
                }
            } else {
                GroupPairingView(
                    sessionViewModel: sessionViewModel,
                    relayPolicyManager: relayPolicyManager,
                    peerTransport: peerTransport
                )
                .task {
                    await onSessionEnd()
                }
            }
        }
    }
}
