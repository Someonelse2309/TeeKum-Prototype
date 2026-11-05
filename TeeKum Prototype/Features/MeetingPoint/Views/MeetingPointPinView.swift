//
//  MeetingPointPinView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 04/11/26.
//

import SwiftUI

/// Renders a single active meeting point rendezvous pin annotation on MapKit.
public struct MeetingPointPinView: View {
    public let meetingPoint: MeetingPoint
    
    public init(meetingPoint: MeetingPoint) {
        self.meetingPoint = meetingPoint
    }
    
    public var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.20))
                    .frame(width: 42, height: 42)
                Circle()
                    .stroke(Color(red: 0.0, green: 0.85, blue: 1.0), lineWidth: 2)
                    .frame(width: 42, height: 42)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
            }
            .shadow(color: Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.55), radius: 6)
            
            VStack(spacing: 1) {
                Text(meetingPoint.title)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(meetingPoint.timeDescription)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.85))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.4), lineWidth: 1)
            )
        }
    }
}
