//
//  AppConstants.swift
//  lucky7
//

import CoreGraphics
import Foundation

enum AppConstants {
    /// Source timelapse timing stays at 60 fps so 1,800 captured frames remain 30 seconds.
    nonisolated static let wrappedOutputFPS: Double = 60

    /// Gallery/share exports render at 30 fps while preserving the source duration.
    static let finalRenderFPS: Double = 30

    /// Target H.264 bitrate for the final 1080x1920 wrap. 4 Mbps keeps 30 second
    /// gallery files around 15 MB instead of the ~80 MB Highest Quality exports.
    static let finalVideoAverageBitRate: Int = 4_000_000

    static let finalRenderSize = CGSize(width: 1080, height: 1920)
    static let landscapeFinalRenderSize = CGSize(width: 1920, height: 1080)

    /// Frames in a full-length session (30 sec × 60 fps).
    static let maxFramesForFullSession: Int = 1800

    /// Max video length when the user completes the entire planned session.
    static let maxWrappedDurationSeconds: TimeInterval = 30

    /// Instagram's direct Stories handoff accepts background videos up to 20 seconds.
    /// Story-only derivatives compress the full wrap into this duration.
    static let instagramStoryMaximumDurationSeconds: TimeInterval = 20

    /// Camera ~30 fps — used only for logging / estimates.
    static let cameraFramesPerSecond: Double = 30

    /// Keep the live recording preview smooth without returning to full 30 fps cost.
    /// The timelapse sampler still writes only the needed frames.
    static let minimumRecordingCameraFPS: Double = 20
    static let maximumRecordingCameraFPS: Double = 25

    /// Minimum planned session length used for sampling math.
    static let minimumPlannedSessionSeconds: TimeInterval = 60

    /// Wall-clock seconds between captures when the full planned session runs: planned ÷ 1800.
    static func captureIntervalSeconds(plannedSessionSeconds: TimeInterval) -> TimeInterval {
        let planned = max(plannedSessionSeconds, minimumPlannedSessionSeconds)
        return planned / Double(maxFramesForFullSession)
    }

    /// Final video length from captured frame count.
    static func wrappedDurationSeconds(frameCount: Int) -> TimeInterval {
        guard frameCount > 0 else { return 0 }
        return Double(frameCount) / wrappedOutputFPS
    }

    /// Target frames if the user stops after `elapsed` of a `planned` session.
    static func targetFrameCount(elapsedSeconds: TimeInterval, plannedSeconds: TimeInterval) -> Int {
        let planned = max(plannedSeconds, minimumPlannedSessionSeconds)
        let elapsed = max(elapsedSeconds, 0)
        let ratio = min(elapsed / planned, 1)
        return max(1, Int((Double(maxFramesForFullSession) * ratio).rounded()))
    }
}
