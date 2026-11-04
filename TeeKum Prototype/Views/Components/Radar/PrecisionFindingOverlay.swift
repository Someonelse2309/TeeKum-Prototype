//
//  PrecisionFindingOverlay.swift
//  TeeKum Prototype
//
//  Created by Nicho on 04/11/26.
//

import SwiftUI
import simd

/// Full AirTag-style Precision Finding guidance overlay.
/// Renders a dynamic 3D directional arrow, pulsating concentric sonar rings,
/// live centimeter distance readout, and directional coaching guidance.
public struct PrecisionFindingOverlay: View {
    public let targetMember: Member
    public let distanceMeters: Float?
    public let direction: simd_float3?
    public let horizontalAngle: Float?
    public let simulatedAngle: Float?
    public let rangingState: UWBRangingState
    public let isSimulated: Bool
    public let onStop: () -> Void
    
    @State private var sonarPulse: CGFloat = 1.0
    
    public init(
        targetMember: Member,
        distanceMeters: Float?,
        direction: simd_float3?,
        horizontalAngle: Float?,
        simulatedAngle: Float? = nil,
        rangingState: UWBRangingState,
        isSimulated: Bool = false,
        onStop: @escaping () -> Void
    ) {
        self.targetMember = targetMember
        self.distanceMeters = distanceMeters
        self.direction = direction
        self.horizontalAngle = horizontalAngle
        self.simulatedAngle = simulatedAngle
        self.rangingState = rangingState
        self.isSimulated = isSimulated
        self.onStop = onStop
    }
    
    // MARK: - Computed Guidance Values
    
    public var hasDirection: Bool {
        direction != nil || horizontalAngle != nil || simulatedAngle != nil
    }
    
    private var primaryColor: Color {
        guard let d = distanceMeters else { return .cyan }
        if d < 1.5 {
            return Color(red: 1.0, green: 0.84, blue: 0.0) // Trophy Gold
        } else if d < 3.0 {
            return Color(red: 0.0, green: 0.95, blue: 0.55) // Emerald Green
        } else {
            return Color(red: 0.0, green: 0.85, blue: 1.0) // Neon Cyan
        }
    }
    
    private var rotationAngle: Angle {
        if let dir = direction {
            // Priority 1: Real Apple U1/U2 3D Direction vector (x: right, -z: forward)
            let rad = atan2(Double(dir.x), -Double(dir.z))
            return Angle(radians: rad)
        } else if let h = horizontalAngle {
            // Priority 2: Real Apple U1/U2 Azimuthal Horizontal Angle (radians)
            return Angle(radians: Double(h))
        } else if let sim = simulatedAngle {
            // Priority 3: Live Sensor-Assisted GPS + Magnetic Compass Heading Fallback
            return Angle(radians: Double(sim))
        }
        return .zero
    }
    
    private var coachingText: String {
        switch rangingState {
        case .requestingToken:
            return "Connecting with \(targetMember.name) over Ultra-Wideband..."
        case .outOfRange:
            return "Signal obstructed • Move iPhone around"
        case .failed(let msg):
            return msg
        case .active, .idle, .unsupported:
            guard let d = distanceMeters else {
                return "Move iPhone around to locate"
            }
            if d < 0.8 {
                return "Here! Within arm's reach 🎉"
            }
            
            let deg = rotationAngle.degrees
            if abs(deg) <= 15 {
                return "Directly ahead • Walk forward"
            } else if deg > 15 && deg <= 60 {
                return "Turn slightly right"
            } else if deg > 60 && deg <= 120 {
                return "Turn right"
            } else if deg < -15 && deg >= -60 {
                return "Turn slightly left"
            } else if deg < -60 && deg >= -120 {
                return "Turn left"
            } else {
                return "Turn around"
            }
        }
    }
    
    public var body: some View {
        ZStack {
            // Background subtle gradient
            RadialGradient(
                gradient: Gradient(colors: [primaryColor.opacity(0.18), Color.black]),
                center: .center,
                startRadius: 20,
                endRadius: 260
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Top status bar
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(primaryColor)
                        .symbolEffect(.pulse, options: .repeating)
                    
                    Text((direction != nil || horizontalAngle != nil) ? "ULTRA-WIDEBAND PRECISION FINDING" : "SENSOR-ASSISTED PRECISION FINDING")
                        .font(.caption2.bold().monospaced())
                        .foregroundStyle(primaryColor)
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // MARK: - Center AirTag Directional Radar
                ZStack {
                    // Concentric expanding sonar rings
                    ForEach(0..<3) { ring in
                        Circle()
                            .stroke(primaryColor.opacity(0.2 - Double(ring) * 0.05), lineWidth: 1.5)
                            .frame(width: CGFloat(140 + ring * 65), height: CGFloat(140 + ring * 65))
                            .scaleEffect(sonarPulse)
                            .animation(
                                .easeInOut(duration: 1.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(ring) * 0.25),
                                value: sonarPulse
                            )
                    }
                    
                    // Center directional pointer / Arrival indicator
                    if let d = distanceMeters, d < 0.8 {
                        // Close proximity (<0.8m): AirTag green arrival circle
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.0, green: 0.95, blue: 0.55).opacity(0.25))
                                .frame(width: 130, height: 130)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 80, weight: .bold))
                                .foregroundStyle(Color(red: 0.0, green: 0.95, blue: 0.55))
                                .shadow(color: Color(red: 0.0, green: 0.95, blue: 0.55).opacity(0.8), radius: 18)
                        }
                        .transition(.scale.combined(with: .opacity))
                    } else if hasDirection {
                        // Navigational Arrow pointing directly at target friend
                        VStack {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 84, weight: .black))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [primaryColor, primaryColor.opacity(0.65)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: primaryColor.opacity(0.7), radius: 18)
                                .rotationEffect(rotationAngle)
                                .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.75), value: rotationAngle)
                        }
                    } else {
                        // Searching / Locating pulse
                        Circle()
                            .fill(primaryColor.opacity(0.2))
                            .frame(width: 90, height: 90)
                            .overlay(
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundStyle(primaryColor)
                                    .symbolEffect(.variableColor.iterative, options: .repeating)
                            )
                    }
                }
                .frame(height: 280)
                
                // MARK: - Distance & Coaching Banner
                VStack(spacing: 8) {
                    if let d = distanceMeters {
                        if d < 1.0 {
                            Text("\(Int(d * 100)) cm")
                                .font(.system(size: 56, weight: .black, design: .rounded))
                                .foregroundStyle(primaryColor)
                                .contentTransition(.numericText())
                        } else {
                            Text(String(format: "%.1f m", d))
                                .font(.system(size: 56, weight: .black, design: .rounded))
                                .foregroundStyle(primaryColor)
                                .contentTransition(.numericText())
                        }
                    } else {
                        Text("Finding...")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.gray)
                    }
                    
                    Text(coachingText)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                Spacer()
                
                // MARK: - Bottom Actions & Friend Card
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Text(targetMember.initials)
                            .font(.headline.bold())
                            .padding(10)
                            .background(primaryColor)
                            .foregroundStyle(.black)
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(targetMember.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            Text((direction != nil || horizontalAngle != nil) ? "Apple U1/U2 Centimeter Link Active" : "Sensor-Assisted Navigation (Live Compass + GPS)")
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)
                    
                    Button {
                        onStop()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                            Text("STOP PRECISION FINDING")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.15))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            sonarPulse = 1.08
        }
    }
}
