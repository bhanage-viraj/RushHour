//
//  NotificationPermission.swift
//  lucky7
//
//  Created by Andrian on 29/05/26.
//

import Foundation
import UserNotifications

@MainActor
enum NotificationPermission {
    static func requestIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // The shield → app return relies on a notification fallback, so the block
    // feature needs this granted. True when the user has DENIED it — iOS won't
    // re-show the prompt, so the app must nudge them to Settings.
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}

enum SessionNotifications {
    static let awayNudgeIds = ["rushhour.awaynudge.1", "rushhour.awaynudge.2"]

    static func scheduleAwayNudges() {
        let center = UNUserNotificationCenter.current()
        cancelAwayNudges()

        for (index, minutes) in [10, 20].enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Are you still there?"
            content.body = "Your focus session is paused — tap to jump back in."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(minutes * 60),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: awayNudgeIds[index],
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    static func cancelAwayNudges() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: awayNudgeIds)
        center.removeDeliveredNotifications(withIdentifiers: awayNudgeIds)
    }
}
