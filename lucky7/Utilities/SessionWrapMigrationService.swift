//
//  SessionWrapMigrationService.swift
//  lucky7
//

import AVFoundation
import Foundation

enum SessionWrapMigrationService {
    private static let minimumLongSessionSeconds: TimeInterval = 15 * 60
    private static let staleSliceMaximumSeconds: TimeInterval = 5

    /// Converts a legacy titled master into the clean master required by share templates.
    /// Returns nil when the durable source is missing or is an old short recap slice.
    static func makeCleanMasterIfPossible(
        legacyMasterURL: URL,
        rawSourceURL: URL?,
        sessionDuration: TimeInterval
    ) async -> URL? {
        guard WrapStorage.sessionMasterContainsMetadata(legacyMasterURL) else {
            return legacyMasterURL
        }
        guard let rawSourceURL,
              FileManager.default.fileExists(atPath: rawSourceURL.path) else {
            return nil
        }

        guard let sourceSeconds = await durationSeconds(for: rawSourceURL) else {
            return nil
        }
        guard sourceSeconds.isFinite, sourceSeconds > 0 else {
            return nil
        }
        let legacySeconds = await durationSeconds(for: legacyMasterURL)
        let sourceIsShorterThanExistingMaster = legacySeconds.map {
            sourceSeconds + 0.5 < $0
        } ?? false
        guard sessionDuration < minimumLongSessionSeconds
                || sourceSeconds > staleSliceMaximumSeconds,
              !sourceIsShorterThanExistingMaster else {
            RecordingDiagnostics.log(
                "SessionWrapMigration skipped short legacy source "
                    + "source=\(rawSourceURL.lastPathComponent) "
                    + "seconds=\(String(format: "%.2f", sourceSeconds)) "
                    + "legacySeconds=\(String(format: "%.2f", legacySeconds ?? 0))"
            )
            return nil
        }

        let frameCount = max(
            1,
            Int((sourceSeconds * AppConstants.wrappedOutputFPS).rounded())
        )
        return await withCheckedContinuation { continuation in
            ExportEngine.shared.generateWrappedVideo(
                rawVideoURL: rawSourceURL,
                capturedFrameCount: frameCount
            ) { cleanURL in
                continuation.resume(returning: cleanURL)
            }
        }
    }

    private static func durationSeconds(for url: URL) async -> TimeInterval? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else {
            return nil
        }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
