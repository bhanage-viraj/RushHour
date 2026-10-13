//
//  DeviceActivityMonitorExtension.swift
//  RushHourJailBreakMonitor
//
//  Created by Andrian on 01/06/26.
//

import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let appGroupId = "group.bhanageviraj.RushHour"

    private func containerFile(_ name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(name)
    }

    private func loadSelection() -> FamilyActivitySelection? {
        guard let url = containerFile("monitor_selection.json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("rushhour.focus"))
        CFPreferencesAppSynchronize(appGroupId as CFString)   // dodge the stale cfprefs cache
        let sessionActive = UserDefaults(suiteName: appGroupId)?.bool(forKey: "sessionActive") ?? false
        guard sessionActive else {
            store.clearAllSettings()
            return
        }
        // if selection can't be read, leave the existing shield as-is instead of unblocking
        guard let selection = loadSelection() else { return }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }
}
