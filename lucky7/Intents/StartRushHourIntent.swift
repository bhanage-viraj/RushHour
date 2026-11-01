//
//  StartRushHourIntent.swift
//  lucky7
//
//  App Intent: open Rush Hour and start a focus session for a given duration.
//

import AppIntents
import Foundation

struct StartRushHourIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Rush Hour"
    static var description = IntentDescription("Start a Rush Hour focus session for a set duration.")

    /// Bring the app to the foreground so the camera session can begin.
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Duration", requestValueDialog: "For how long?")
    var duration: RushHourDurationOption

    static var parameterSummary: some ParameterSummary {
        Summary("Start Rush Hour for \(\.$duration)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let totalSeconds = max(
            duration.totalSeconds,
            Int(AppConstants.minimumPlannedSessionSeconds)
        )
        PendingSiriSession.shared.queue(totalSeconds: totalSeconds)

        let label = RushHourDurationOption.caseDisplayRepresentations[duration]?.title
            ?? LocalizedStringResource(stringLiteral: "\(totalSeconds) seconds")
        return .result(dialog: IntentDialog("Starting Rush Hour for \(label)."))
    }
}
