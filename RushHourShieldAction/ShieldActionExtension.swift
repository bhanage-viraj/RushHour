//
//  ShieldActionExtension.swift
//  RushHourShieldAction
//
//  Created by Andrian on 01/06/26.
//

import Foundation
import ManagedSettings
import UserNotifications
import os

private let actionLog = OSLog(subsystem: "com.andrianangg.Traffic-Man.RushHourShieldAction", category: "ShieldAction")

class ShieldActionExtension: ShieldActionDelegate {
    override init() {
        super.init()
        os_log("RUSHHOUR_ACTION_INIT — ShieldActionExtension initialized", log: actionLog, type: .default)
    }

    private let appGroupId = "group.com.andrianangg.Traffic-Man"

    private func containerFile(_ name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(name)
    }

    private func loadEvents() -> [[String: Any]] {
        guard let url = containerFile("action_events.json"),
              let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr
    }

    private func saveEvents(_ events: [[String: Any]]) {
        guard let url = containerFile("action_events.json"),
              let data = try? JSONSerialization.data(withJSONObject: events)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    // App handler — we have the real ApplicationToken (drives the "<App> unlocked" card via Label(token)).
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        let tokenData = try? JSONEncoder().encode(application)
        handleAction(action, tokenData: tokenData, completionHandler: completionHandler)
    }

    // Category handler — fires when the user blocked a whole CATEGORY (the common case here). No app token,
    // but the SAME return logic must run or the buttons do nothing. The app falls back to the shielded-app
    // name the config extension stashed (lastShieldedAppName) for the card/prompt.
    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(action, tokenData: nil, completionHandler: completionHandler)
    }

    // Web-domain handler — same: run the return logic, no token.
    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(action, tokenData: nil, completionHandler: completionHandler)
    }

    // Shared return logic for app / category / web-domain shields.
    // Schedule the return notification durably (addAndWait blocks until the daemon accepts it),
    // THEN deliver the response synchronously on this call stack.
    private func handleAction(_ action: ShieldAction, tokenData: Data?, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            recordAction(tokenData: tokenData, action: "back")
            scheduleReturnNotification()
            respond(completionHandler)
        case .secondaryButtonPressed:
            recordAction(tokenData: tokenData, action: "break")
            scheduleReasonPromptNotification()
            respond(completionHandler)
        @unknown default:
            completionHandler(.close)
        }
    }

    // Notifications are the reliable return path; close the shield after scheduling.
    private func respond(_ completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    private func recordAction(tokenData: Data?, action: String) {
        var events = loadEvents()
        let event: [String: Any] = [
            "id": UUID().uuidString,
            "tokenData": (tokenData ?? Data()).base64EncodedString(),
            "occurredAt": Date().timeIntervalSince1970,
            "sourceKind": "shieldAction",
            "actionTaken": action
        ]
        events.append(event)
        saveEvents(events)
    }

    private func scheduleReasonPromptNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Tap to record your reason"
        content.body = "Come back to Rush Hour to log why you opened that app."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["type": "jailbreakReason"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: "rushhour.shieldreason", content: content, trigger: trigger)
        addAndWait(request)
    }

    private func scheduleReturnNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Back to Rush Hour"
        content.body = "Tap to return to your focus session."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["type": "jailbreakReturn"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: "rushhour.shieldreturn", content: content, trigger: trigger)
        addAndWait(request)
    }

    // Block until the notification is actually persisted, so this short-lived extension isn't
    // torn down mid-schedule. The 1s timeout is a safety net; the add normally completes in ms.
    private func addAndWait(_ request: UNNotificationRequest) {
        let group = DispatchGroup()
        group.enter()
        UNUserNotificationCenter.current().add(request) { _ in group.leave() }
        _ = group.wait(timeout: .now() + 1.0)
    }
}
