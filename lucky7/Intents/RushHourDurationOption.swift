//
//  RushHourDurationOption.swift
//  lucky7
//
//  Duration choices for Siri / App Shortcuts. App Shortcut phrases only allow
//  AppEnum / AppEntity parameters, so free-form Measurement isn't usable there.
//

import AppIntents
import Foundation

enum RushHourDurationOption: String, AppEnum, CaseIterable {
    case minutes15
    case minutes25
    case minutes30
    case minutes45
    case hour1
    case hours2
    case hours3
    case hours4

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Duration")

    static var caseDisplayRepresentations: [RushHourDurationOption: DisplayRepresentation] = [
        .minutes15: "15 minutes",
        .minutes25: "25 minutes",
        .minutes30: "30 minutes",
        .minutes45: "45 minutes",
        .hour1: "1 hour",
        .hours2: "2 hours",
        .hours3: "3 hours",
        .hours4: "4 hours"
    ]

    var totalSeconds: Int {
        switch self {
        case .minutes15: return 15 * 60
        case .minutes25: return 25 * 60
        case .minutes30: return 30 * 60
        case .minutes45: return 45 * 60
        case .hour1: return 60 * 60
        case .hours2: return 2 * 60 * 60
        case .hours3: return 3 * 60 * 60
        case .hours4: return 4 * 60 * 60
        }
    }
}
