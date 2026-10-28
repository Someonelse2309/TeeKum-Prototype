//
//  MeetingPointViewModel.swift
//  TeeKum Prototype
//
//  Created by Nicho on 27/10/26.
//

import Foundation
import Observation
import CoreLocation

/// Pure MVVM ViewModel governing the Single Active Meeting Point and 1-tap attendance synchronization.
@Observable
@MainActor
public final class MeetingPointViewModel {
    /// Strictly ONE active meeting point per group at any given time.
    public var activeMeetingPoint: MeetingPoint?
    
    /// User attendance response to the current active proposal.
    public var localAttendanceStatus: AttendanceStatus?
    
    public init(activeMeetingPoint: MeetingPoint? = nil) {
        self.activeMeetingPoint = activeMeetingPoint
    }
    
    /// Proposes a new rendezvous point (replaces any previous active meeting point).
    public func proposeMeetingPoint(
        name: String,
        coordinate: CLLocationCoordinate2D,
        targetTime: Date? = nil,
        proposerId: UInt32,
        landmarkId: UInt32? = nil
    ) {
        let point = MeetingPoint(
            name: name,
            coordinate: coordinate,
            targetTime: targetTime,
            proposerId: proposerId,
            landmarkId: landmarkId,
            attendance: [proposerId: .attending]
        )
        self.activeMeetingPoint = point
        self.localAttendanceStatus = .attending
    }
    
    /// Responds with 1-tap confirmation.
    public func respond(status: AttendanceStatus, memberId: UInt32) {
        guard var point = activeMeetingPoint else { return }
        point.attendance[memberId] = status
        self.activeMeetingPoint = point
        self.localAttendanceStatus = status
    }
    
    /// Cancels the current meeting point.
    public func cancelMeetingPoint() {
        self.activeMeetingPoint = nil
        self.localAttendanceStatus = nil
    }
}
