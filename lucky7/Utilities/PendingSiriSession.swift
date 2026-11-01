//
//  PendingSiriSession.swift
//  lucky7
//
//  Holds a Siri / Shortcuts "start session" request until Home can consume it
//  and jump straight into recording.
//

import Combine
import Foundation

@MainActor
final class PendingSiriSession: ObservableObject {
    static let shared = PendingSiriSession()

    /// Planned session length in whole seconds, once queued by StartRushHourIntent.
    @Published private(set) var totalSeconds: Int?

    private init() {}

    /// Queue a duration for the next Home auto-start. Clamps to the app minimum.
    func queue(totalSeconds: Int) {
        let clamped = max(totalSeconds, Int(AppConstants.minimumPlannedSessionSeconds))
        self.totalSeconds = clamped
    }

    /// Whether a Siri start is waiting to be applied.
    var hasPending: Bool { totalSeconds != nil }

    /// Take and clear the pending duration, if any.
    func consume() -> Int? {
        defer { totalSeconds = nil }
        return totalSeconds
    }

    /// Drop a pending request without starting (e.g. already recording, onboarding).
    func clear() {
        totalSeconds = nil
    }
}
