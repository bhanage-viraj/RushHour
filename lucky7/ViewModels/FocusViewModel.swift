//
//  FocusViewModel.swift
//  lucky7
//
//  Created by Andrian on 31/05/26.
//

import Foundation
import Combine
#if os(iOS)
import FamilyControls
import ManagedSettings
import UserNotifications
import DeviceActivity
import ActivityKit
import SwiftUI
import UIKit

@MainActor
final class FocusViewModel: ObservableObject {
    @Published var selection = FamilyActivitySelection()
    @Published private(set) var isEngaged = false
    @Published private(set) var isRunning = false   // false = paused, e.g. on a distraction
    @Published private(set) var activeBreaks: [Distraction] = []
    @Published private(set) var now: Date = .now

    static let breakDuration: TimeInterval = 15 * 60
    static let appGroupId = "group.com.andrianangg.Traffic-Man"
    static let selectionDefaultsKey = "savedFamilyActivitySelection"

    private let store = ManagedSettingsStore(named: .rushHourFocus)
    private var tickTimer: Timer?

    init() {
        loadSelection()
        // cold launch: any shield still applied is stale, lift it
        store.clearAllSettings()
        SharedJailbreakStore.endSession()
        endBreakActivity()
    }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    var selectionSummary: String {
        let appCount = selection.applicationTokens.count
        let categoryCount = selection.categoryTokens.count
        let domainCount = selection.webDomainTokens.count
        var parts: [String] = []
        if appCount > 0 { parts.append("\(appCount) app\(appCount == 1 ? "" : "s")") }
        if categoryCount > 0 { parts.append("\(categoryCount) categor\(categoryCount == 1 ? "y" : "ies")") }
        if domainCount > 0 { parts.append("\(domainCount) site\(domainCount == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: ", ")
    }

    var selectionBinding: Binding<FamilyActivitySelection> {
        Binding(
            get: { self.selection },
            set: { self.selection = $0 }
        )
    }

    private let breakActivity = DeviceActivityName("rushhour.break")

    func engage() {
        guard hasSelection else { return }
        SharedJailbreakStore.startSession()
        saveSelectionForMonitor()
        applyShield()
        isEngaged = true
        isRunning = true
        startTicking()
    }

    func pause() {
        isRunning = false
    }

    // back from a distraction: reblock everything and resume
    func resume() {
        for distraction in activeBreaks {
            if distraction.endTime == nil { distraction.endTime = .now }
            distraction.breakGrantedUntil = nil
            cancelBreakNotification(for: distraction)
        }
        activeBreaks.removeAll()
        applyShield()
        stopBreakMonitor()
        endBreakActivity()
        isRunning = true
    }

    func release() {
        store.clearAllSettings()
        SharedJailbreakStore.endSession()
        isEngaged = false
        isRunning = false
        for distraction in activeBreaks {
            if distraction.endTime == nil { distraction.endTime = .now }
            distraction.breakGrantedUntil = nil
            cancelBreakNotification(for: distraction)
        }
        activeBreaks.removeAll()
        stopBreakMonitor()
        endBreakActivity()
        stopTicking()
    }

    func grantBreak(for distraction: Distraction) {
        // only one app unlocked at a time, re-block any other active break
        let others = activeBreaks.filter { $0.id != distraction.id }
        for other in others {
            other.breakGrantedUntil = nil
            if other.endTime == nil { other.endTime = .now }
            cancelBreakNotification(for: other)
        }
        activeBreaks.removeAll { $0.id != distraction.id }

        let until = Date().addingTimeInterval(Self.breakDuration)
        distraction.breakGrantedUntil = until
        if !activeBreaks.contains(where: { $0.id == distraction.id }) {
            activeBreaks.append(distraction)
        }
        applyShield()
        scheduleBreakNotification(for: distraction)
        startBreakMonitor()
        let appName = distraction.appDisplayName ?? distraction.appOpened
        startBreakActivity(appName: appName, until: until)
        // resolve the real name and backfill once we have it
        if (distraction.appDisplayName ?? "").isEmpty {
            Task { @MainActor in
                guard let name = await resolveDisplayName(for: distraction), !name.isEmpty else { return }
                distraction.appDisplayName = name
                startBreakActivity(appName: name, until: until)
            }
        }
        isRunning = false   // auto-pause while distracted
    }

    func endBreakEarly(for distraction: Distraction) {
        if distraction.endTime == nil { distraction.endTime = .now }
        distraction.breakGrantedUntil = nil
        activeBreaks.removeAll { $0.id == distraction.id }
        applyShield()
        cancelBreakNotification(for: distraction)
        stopBreakMonitor()
        if activeBreaks.isEmpty { endBreakActivity() }
    }

    // schedules the 15-min interval, monitor ext reblocks when it ends
    private func startBreakMonitor() {
        saveSelectionForMonitor()
        let now = Date()
        let end = now.addingTimeInterval(Self.breakDuration)
        let cal = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.hour, .minute, .second], from: now),
            intervalEnd: cal.dateComponents([.hour, .minute, .second], from: end),
            repeats: false
        )
        try? DeviceActivityCenter().startMonitoring(breakActivity, during: schedule)
    }

    private func stopBreakMonitor() {
        DeviceActivityCenter().stopMonitoring([breakActivity])
    }

    private func saveSelectionForMonitor() {
        guard let url = SharedJailbreakStore.fileURL("monitor_selection.json"),
              let data = try? JSONEncoder().encode(selection) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Live Activity

    private var liveActivity: Activity<BreakActivityAttributes>?

    private func startBreakActivity(appName: String, until endsAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let name = appName.isEmpty ? "Blocked App" : appName
        let state = BreakActivityAttributes.ContentState(
            startedAt: Date(),
            endsAt: endsAt,
            statusText: "\(name) unlocked"
        )
        // if the island is already up, update it instead of starting a second
        if let activity = liveActivity {
            Task { await activity.update(ActivityContent(state: state, staleDate: endsAt)) }
            return
        }
        do {
            liveActivity = try Activity.request(
                attributes: BreakActivityAttributes(appName: name),
                content: ActivityContent(state: state, staleDate: endsAt),
                pushType: nil
            )
        } catch {
        }
    }

    private func endBreakActivity() {
        let current = liveActivity
        liveActivity = nil
        // keep the app alive long enough to actually tear the Live Activity down
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "endBreakActivity")
        Task {
            await current?.end(nil, dismissalPolicy: .immediate)
            for activity in Activity<BreakActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            UIApplication.shared.endBackgroundTask(bgTask)
        }
    }

    // resolve the real app name up front while we're still foregrounded
    func prefetchDisplayName(for distraction: Distraction) {
        guard (distraction.appDisplayName ?? "").isEmpty else { return }
        Task { @MainActor in
            if let name = await resolveDisplayName(for: distraction), !name.isEmpty {
                distraction.appDisplayName = name
            }
        }
    }

    private func resolveDisplayName(for distraction: Distraction) async -> String? {
        guard let data = distraction.tokenData,
              let token = try? JSONDecoder().decode(ApplicationToken.self, from: data),
              let apps = try? await FamilyActivityData.shared.installedApplications,
              let match = apps.first(where: { $0.token == token })
        else { return nil }
        return match.localizedDisplayName
    }

    func remainingSeconds(for distraction: Distraction) -> TimeInterval {
        guard let until = distraction.breakGrantedUntil else { return 0 }
        return max(0, until.timeIntervalSince(now))
    }

    func persistSelection() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupId) else { return }
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: Self.selectionDefaultsKey)
        }
    }

    func loadSelection() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupId),
              let data = defaults.data(forKey: Self.selectionDefaultsKey),
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }
        selection = decoded
    }

    private func applyShield() {
        let brokenTokens = Set(activeBreaks.compactMap { decodeToken($0.tokenData) })
        let hasCategoryBreak = activeBreaks.contains { decodeToken($0.tokenData) == nil }

        let effective = selection.applicationTokens.subtracting(brokenTokens)
        store.shield.applications = effective.isEmpty ? nil : effective
        store.shield.applicationCategories = (selection.categoryTokens.isEmpty || hasCategoryBreak)
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
    }

    private func decodeToken(_ data: Data?) -> ApplicationToken? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(ApplicationToken.self, from: data)
    }

    private func startTicking() {
        stopTicking()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        // only do work while a break is active, otherwise we re-render for nothing
        guard !activeBreaks.isEmpty else { return }
        now = .now
        let expired = activeBreaks.filter { d in
            guard let until = d.breakGrantedUntil else { return true }
            return until <= now
        }
        guard !expired.isEmpty else { return }
        for d in expired {
            if d.endTime == nil { d.endTime = d.breakGrantedUntil ?? now }
            d.breakGrantedUntil = nil
        }
        activeBreaks.removeAll { d in expired.contains(where: { $0.id == d.id }) }
        applyShield()
        if activeBreaks.isEmpty { endBreakActivity() }
    }

    private func scheduleBreakNotification(for distraction: Distraction) {
        let content = UNMutableNotificationContent()
        let appName = distraction.appDisplayName ?? distraction.appOpened
        content.title = appName.isEmpty ? "Break ended" : "\(appName) is locked again"
        content.body = "Your 15-minute break is over."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.breakDuration, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationId(for: distraction),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelBreakNotification(for distraction: Distraction) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationId(for: distraction)])
    }

    private func notificationId(for distraction: Distraction) -> String {
        "break.\(distraction.id.uuidString)"
    }
}

extension ManagedSettingsStore.Name {
    static let rushHourFocus = Self("rushhour.focus")
}
#endif
