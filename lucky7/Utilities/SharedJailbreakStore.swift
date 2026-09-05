//
//  SharedJailbreakStore.swift
//  lucky7
//
//  Created by Andrian on 31/05/26.
//

import Foundation

struct PendingJailbreakEvent: Identifiable {
    let id: String
    let displayName: String?
    let bundleId: String?
    let tokenData: Data?
    let occurredAt: Date
    let sourceKind: String
    let actionTaken: String?
}

// each writer gets its own file so the app and the extensions don't clobber each other
enum SharedJailbreakStore {
    static let appGroupId = "group.com.andrianangg.Traffic-Man"

    static func fileURL(_ name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(name)
    }

    static var configFileURL: URL? { fileURL("config_events.json") }
    static var actionFileURL: URL? { fileURL("action_events.json") }
    static var sessionFileURL: URL? { fileURL("session.json") }
    static var openCountFileURL: URL? { fileURL("open_count.json") }

    static func loadArray(_ url: URL?) -> [[String: Any]] {
        guard let url, let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr
    }

    static func parse(_ dict: [String: Any]) -> PendingJailbreakEvent? {
        guard let id = dict["id"] as? String,
              let occurredAtSeconds = dict["occurredAt"] as? TimeInterval,
              let sourceKind = dict["sourceKind"] as? String
        else { return nil }
        let displayName = (dict["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let bundleId = (dict["bundleId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let tokenData = Data(base64Encoded: dict["tokenData"] as? String ?? "")
        return PendingJailbreakEvent(
            id: id,
            displayName: displayName,
            bundleId: bundleId,
            tokenData: tokenData,
            occurredAt: Date(timeIntervalSince1970: occurredAtSeconds),
            sourceKind: sourceKind,
            actionTaken: dict["actionTaken"] as? String
        )
    }

    // last break we already prompted for, so we don't re-prompt it
    static var lastPromptedBreakAt: TimeInterval {
        get { UserDefaults.standard.double(forKey: "lastPromptedBreakAt") }
        set { UserDefaults.standard.set(newValue, forKey: "lastPromptedBreakAt") }
    }

    static func nextUnhandledBreak() -> (action: PendingJailbreakEvent, config: PendingJailbreakEvent?)? {
        let handledUntil = lastPromptedBreakAt
        let actions = loadArray(actionFileURL).compactMap { parse($0) }
        let configs = loadArray(configFileURL).compactMap { parse($0) }.sorted { $0.occurredAt > $1.occurredAt }

        guard let breakAction = actions
            .filter({ $0.actionTaken == "break" && $0.occurredAt.timeIntervalSince1970 > handledUntil })
            .sorted(by: { $0.occurredAt > $1.occurredAt })
            .first
        else { return nil }

        let matchingConfig = configs.first(where: { cfg in
            guard let c = cfg.tokenData, let b = breakAction.tokenData else { return false }
            return c == b
        }) ?? configs.first

        return (breakAction, matchingConfig)
    }

    static func markBreakHandled(_ occurredAt: Date) {
        lastPromptedBreakAt = occurredAt.timeIntervalSince1970
    }

    static func removeAll() {
        [configFileURL, actionFileURL, sessionFileURL, openCountFileURL, configSharedURL].forEach { url in
            if let url { try? FileManager.default.removeItem(at: url) }
        }
    }

    static var configSharedURL: URL? { fileURL("config_shared.json") }

    // sync before reading, otherwise we get stale cached values
    private static func sharedDefaults() -> UserDefaults? {
        CFPreferencesAppSynchronize(appGroupId as CFString)
        return UserDefaults(suiteName: appGroupId)
    }

    static func configTick() -> Int {
        sharedDefaults()?.integer(forKey: "configTick") ?? 0
    }

    // [app name: times opened this session]
    static func openCounts() -> [String: Int] {
        (sharedDefaults()?.dictionary(forKey: "openCountsByApp") as? [String: Int]) ?? [:]
    }

    // most-recently-shielded app, used to label a break and route back
    static func lastShieldedAppName() -> String? {
        sharedDefaults()?.string(forKey: "lastShieldedAppName")
    }

    static func lastShieldedBundleId() -> String? {
        sharedDefaults()?.string(forKey: "lastShieldedBundleId")
    }

    static func openCount() -> Int {
        openCounts().values.reduce(0, +)
    }

    static func startSession() {
        removeAll()
        lastPromptedBreakAt = 0
        if let defaults = UserDefaults(suiteName: appGroupId) {
            defaults.removeObject(forKey: "openCountsByApp")
            defaults.removeObject(forKey: "lastOpenByApp")
            defaults.removeObject(forKey: "lastShieldedAppName")
            defaults.removeObject(forKey: "lastShieldedBundleId")
            defaults.removeObject(forKey: "configTick")
            // stamp session start so the config ext resets its own count
            defaults.set(Date().timeIntervalSince1970, forKey: "sessionStartedAt")
            defaults.set(true, forKey: "sessionActive")
            CFPreferencesAppSynchronize(appGroupId as CFString)
        }
        let session: [String: Any] = ["startedAt": Date().timeIntervalSince1970]
        if let url = sessionFileURL, let data = try? JSONSerialization.data(withJSONObject: session) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // mark the session over so the monitor ext stops re-blocking
    static func endSession() {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        defaults.set(false, forKey: "sessionActive")
        CFPreferencesAppSynchronize(appGroupId as CFString)
        if let url = sessionFileURL { try? FileManager.default.removeItem(at: url) }
    }
}
