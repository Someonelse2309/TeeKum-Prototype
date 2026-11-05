//
//  NotificationService.swift
//  TeeKum Prototype
//
//  Created by Nicho on 03/11/26.
//

import SwiftUI
import UserNotifications
import Observation

/// Model representing a transient in-app floating banner toast.
public struct InAppToast: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let message: String
    public let systemImage: String
    public let accentColor: Color
    public let action: (@MainActor () -> Void)?
    
    public init(
        id: UUID = UUID(),
        title: String,
        message: String,
        systemImage: String = "bell.fill",
        accentColor: Color = Color(red: 0.0, green: 0.85, blue: 1.0),
        action: (@MainActor () -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.action = action
    }
    
    public static func == (lhs: InAppToast, rhs: InAppToast) -> Bool {
        lhs.id == rhs.id
    }
}

/// Centralized manager for in-app floating toast banners and system-level local notifications (`UserNotifications`).
@Observable
@MainActor
public final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    
    public static let shared = NotificationService()
    
    /// Current in-app floating toast to display (nil if none).
    public var activeToast: InAppToast? = nil
    
    /// Auto-dismissal task for in-app toasts.
    private var dismissTask: Task<Void, Never>?
    
    public override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    /// Requests system notification authorization from the user.
    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[NotificationService] Authorization error: \(error.localizedDescription)")
            } else {
                print("[NotificationService] Notification authorization granted: \(granted)")
            }
        }
    }
    
    // MARK: - Post Notifications
    
    /// Triggers an in-app toast and a system local notification for an incoming group chat message.
    public func notifyChatMessage(
        senderInitials: String,
        text: String,
        isSheetOpen: Bool,
        onTap: (@MainActor () -> Void)? = nil
    ) {
        // 1. In-app floating toast if sheet is closed
        if !isSheetOpen {
            showInAppToast(
                InAppToast(
                    title: senderInitials,
                    message: text,
                    systemImage: "bubble.left.and.bubble.right.fill",
                    accentColor: Color(red: 0.0, green: 0.85, blue: 1.0),
                    action: onTap
                )
            )
        }
        
        // 2. System Notification for background / lock screen
        postSystemNotification(
            title: "Chat: \(senderInitials)",
            body: text,
            categoryIdentifier: "CHAT_MESSAGE"
        )
    }
    
    /// Triggers an in-app toast and a system local notification for a new or updated meeting point.
    public func notifyMeetingPoint(
        proposerInitials: String,
        meetingPointName: String,
        actionName: String = "proposed",
        onTap: (@MainActor () -> Void)? = nil
    ) {
        let msg = "\(proposerInitials) \(actionName) \"\(meetingPointName)\""
        
        showInAppToast(
            InAppToast(
                title: "Meeting Point",
                message: msg,
                systemImage: "mappin.and.ellipse",
                accentColor: Color(red: 1.0, green: 0.84, blue: 0.04), // Neon Amber
                action: onTap
            )
        )
        
        postSystemNotification(
            title: "Meeting Point Update",
            body: msg,
            categoryIdentifier: "MEETING_UPDATE"
        )
    }
    
    // MARK: - Private Toast Presentation
    
    public func showInAppToast(_ toast: InAppToast) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            self.activeToast = toast
        }
        
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                if self.activeToast?.id == toast.id {
                    self.activeToast = nil
                }
            }
        }
    }
    
    public func dismissToast() {
        dismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            self.activeToast = nil
        }
    }
    
    // MARK: - Private System Notification Delivery
    
    private func postSystemNotification(title: String, body: String, categoryIdentifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationService] Failed to post notification: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Allow banners and sound even when app is active
        completionHandler([.banner, .sound])
    }
}
