//
//  RadarView.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI
import CoreLocation

/// Complete reusable tactical radar display view.
/// Shows all peers in the group positioned by relative bearing and distance,
/// supports selection of an individual target, and clamps distant peers (> 60m)
/// to the outer boundary with directional edge indicators.
public struct RadarView: View {
    public let members: [Member]
    public let userLocation: LocationPin?
    public let currentHeading: CLLocationDirection?
    @Binding public var selectedMember: Member?
    public let theme: RadarTheme
    public let userColor: Color?
    
    public init(
        members: [Member],
        userLocation: LocationPin?,
        currentHeading: CLLocationDirection?,
        selectedMember: Binding<Member?>,
        theme: RadarTheme = .standard,
        userColor: Color? = nil
    ) {
        self.members = members
        self.userLocation = userLocation
        self.currentHeading = currentHeading
        self._selectedMember = selectedMember
        self.theme = theme
        self.userColor = userColor
    }
    
    public var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            // Leave margin for blips and clamped arrow markers at the edge
            let maxAvailable = min(geo.size.width, geo.size.height)
            let radius = max(60, (maxAvailable - (theme.blipSize + 24)) / 2)
            
            ZStack {
                // MARK: - Tap Background to Clear Selection
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMember = nil
                        }
                    }
                
                // MARK: - Radar Grid & Rings
                RadarGridBackground(radius: radius, theme: theme)
                    .position(center)
                
                // MARK: - Directional Guide Line to Selected Target
                if let target = selectedMember,
                   let pos = computeBlipPosition(for: target, center: center, radius: radius) {
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: pos.point)
                    }
                    .stroke(
                        theme.guideLineColor,
                        style: StrokeStyle(lineWidth: theme.guideLineWidth, dash: [6, 4])
                    )
                    .shadow(color: theme.guideLineColor.opacity(0.8), radius: 4)
                }
                
                // MARK: - Center User Marker
                RadarCenterMarker(theme: theme, userColor: userColor)
                    .position(center)
                
                // MARK: - Peer Blips
                ForEach(members) { member in
                    if let pos = computeBlipPosition(for: member, center: center, radius: radius) {
                        RadarBlipView(
                            member: member,
                            distance: pos.distance,
                            relativeBearing: pos.relativeBearing,
                            isClamped: pos.isClamped,
                            isSelected: selectedMember?.id == member.id,
                            theme: theme,
                            onTap: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    if selectedMember?.id == member.id {
                                        selectedMember = nil
                                    } else {
                                        selectedMember = member
                                    }
                                }
                            }
                        )
                        .position(pos.point)
                    }
                }
            }
        }
        .drawingGroup() // Metal hardware acceleration for smooth 60fps heading rotation
    }
    
    // MARK: - Projection Math
    
    public struct BlipPosition {
        public let point: CGPoint
        public let distance: CLLocationDistance
        public let relativeBearing: Double
        public let isClamped: Bool
    }
    
    private func computeBlipPosition(
        for member: Member,
        center: CGPoint,
        radius: CGFloat
    ) -> BlipPosition? {
        guard let userLoc = userLocation, let targetCoord = member.coordinate else {
            return nil
        }
        
        let dist = userLoc.distance(to: targetCoord)
        let absoluteBearing = userLoc.bearing(to: targetCoord)
        let heading = currentHeading ?? 0.0
        
        // Forward-Up (Heading-Up) Relative Angle
        let relativeAngle = (absoluteBearing - heading + 360.0).truncatingRemainder(dividingBy: 360.0)
        let isClamped = dist > theme.maxDisplayRange
        let displayDistance = min(dist, theme.maxDisplayRange)
        
        // Polar to Cartesian conversion
        // 0° is North (Up) -> dx = sin(rad), dy = -cos(rad)
        let rad = relativeAngle * .pi / 180.0
        let radialFraction = CGFloat(displayDistance / theme.maxDisplayRange)
        let blipRadius = radius * radialFraction
        
        let dx = sin(rad) * blipRadius
        let dy = -cos(rad) * blipRadius
        
        let point = CGPoint(x: center.x + dx, y: center.y + dy)
        
        return BlipPosition(
            point: point,
            distance: dist,
            relativeBearing: relativeAngle,
            isClamped: isClamped
        )
    }
}
