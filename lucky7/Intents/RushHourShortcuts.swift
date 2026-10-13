//
//  RushHourShortcuts.swift
//  lucky7
//
//  Donates Siri / Shortcuts phrases for starting a Rush Hour session.
//

import AppIntents

struct RushHourShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRushHourIntent(),
            phrases: [
                "Start \(.applicationName) for \(\.$duration)",
                "Begin \(.applicationName) for \(\.$duration)",
                "Start a \(.applicationName) session for \(\.$duration)",
                "Begin a \(.applicationName) session for \(\.$duration)"
            ],
            shortTitle: "Start Rush Hour",
            systemImageName: "record.circle"
        )
    }
}
