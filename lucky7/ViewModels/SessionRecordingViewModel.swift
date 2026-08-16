//
//  SessionRecordingViewModel.swift
//  lucky7
//

import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class SessionRecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isExporting = false
    @Published var finalVideoURL: URL?
    /// Durable full source clip for final wrap generation and retry. This is not a
    /// playable fallback; session playback must use `finalVideoURL`.
    @Published var rawClipURL: URL?
    @Published var previewFrames: [UIImage] = []
    @Published var cameraReady = false
    @Published var permissionDenied = false
    @Published var savedToPhotos = false
    /// Photos-library local id for the saved wrap, persisted on the Session so deleting
    /// the session can also remove the copy from the user's library.
    @Published var photoAssetId: String?
    @Published var lastError: String?
    @Published var statusMessage: String?
    @Published private(set) var isCapturePaused = false

    private let timelapseManager = TimelapseManager()
    private let exportEngine = ExportEngine.shared
    private var plannedSessionSeconds: TimeInterval = 0
    private var recordedWallClockSeconds: TimeInterval = 0
    private var didCaptureThisSession = false
    private var stopCompletions: [() -> Void] = []
    private var isStoppingRecording = false
    private var pendingTitleExport: PendingTitleExport?
    private var activeTitleExportTitle: String?
    private var activeTitleExportCompletions: [(URL?) -> Void] = []
    private var activeTitleExportShouldSaveToPhotos = false
    private var completedTitleExportTitle: String?
    private var completedTitleExportSavedToPhotos = false
    private var titleExportRetryTask: Task<Void, Never>?
    // Kept for final-export recovery and recap generation. Share styling never reads raw.
    private var retainedRawURL: URL?
    private var lastExportFrameCount: Int = 0
    private static let homePreviewIdleNanoseconds: UInt64 = 45 * 1_000_000_000
    private var homePreviewIdleTask: Task<Void, Never>?

    private struct PendingTitleExport {
        let title: String
        let durationSeconds: TimeInterval
        let saveToPhotos: Bool
        let completions: [(URL?) -> Void]
    }

    var captureSession: AVCaptureSession {
        timelapseManager.captureSession
    }

    var capturedFrameCount: Int {
        timelapseManager.currentFrameCount
    }

    func prepareCamera() {
        log("prepareCamera")
        timelapseManager.requestPermissionAndConfigure { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.cameraReady = granted
                self.permissionDenied = !granted
                self.log("prepareCamera result granted=\(granted)")
                if granted {
                    self.timelapseManager.startRunning()
                    self.statusMessage = nil
                } else {
                    self.lastError = "Camera access is required to record."
                }
            }
        }
    }

    func switchCamera() {
        timelapseManager.switchCamera()
    }

    func stopCamera() {
        timelapseManager.stopRunning()
    }

    func ensureCameraRunning() {
        timelapseManager.startRunning()
    }

    func noteHomePreviewInteraction() {
        guard !isRecording, !isExporting else { return }
        log("homePreview interaction cameraReady=\(cameraReady)")
        if cameraReady {
            timelapseManager.startRunning()
        } else {
            prepareCamera()
        }
        scheduleHomePreviewIdleStop()
    }

    func stopHomePreview() {
        cancelHomePreviewIdleStop()
        guard !isRecording, !isExporting else { return }
        log("homePreview stop")
        timelapseManager.stopRunning()
    }

    private func scheduleHomePreviewIdleStop() {
        homePreviewIdleTask?.cancel()
        homePreviewIdleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.homePreviewIdleNanoseconds)
            guard !Task.isCancelled else { return }
            self?.stopHomePreviewAfterIdle()
        }
    }

    private func cancelHomePreviewIdleStop() {
        homePreviewIdleTask?.cancel()
        homePreviewIdleTask = nil
    }

    private func stopHomePreviewAfterIdle() {
        guard !isRecording, !isExporting else { return }
        log("homePreview idle stop")
        timelapseManager.stopRunning()
    }

    func startRecording(plannedSessionSeconds: TimeInterval, completion: ((Bool) -> Void)? = nil) {
        log("startRecording requested cameraReady=\(cameraReady) isRecording=\(isRecording) planned=\(plannedSessionSeconds)")
        guard cameraReady else {
            lastError = "Camera is not ready yet."
            log("startRecording blocked: camera not ready")
            completion?(false)
            return
        }
        guard !isRecording else {
            log("startRecording ignored: already recording")
            completion?(true)
            return
        }

        finalVideoURL = nil
        rawClipURL = nil
        previewFrames = []
        lastError = nil
        savedToPhotos = false
        photoAssetId = nil
        statusMessage = "Recording…"
        self.plannedSessionSeconds = max(plannedSessionSeconds, 60)
        recordedWallClockSeconds = 0
        cancelHomePreviewIdleStop()

        timelapseManager.startRecording(plannedSessionSeconds: self.plannedSessionSeconds) { [weak self] started in
            Task { @MainActor in
                guard let self else { return }
                if started {
                    self.isRecording = true
                    self.isCapturePaused = false
                    self.didCaptureThisSession = true
                    self.log("startRecording succeeded")
                    ScreenWakeLock.setActive(true)
                    AccessibilitySupport.announce("Recording started")
                } else {
                    self.isCapturePaused = false
                    self.lastError = "Could not start recording. Keep the camera preview open and try again."
                    self.statusMessage = nil
                    self.log("startRecording failed from timelapse")
                }
                completion?(started)
            }
        }
    }

    func pauseRecording(reason: String = "manual") {
        log("pauseRecording reason=\(reason) isRecording=\(isRecording) paused=\(isCapturePaused)")
        guard isRecording else { return }
        guard !isCapturePaused else { return }
        isCapturePaused = true
        timelapseManager.pauseCapture()
        timelapseManager.stopRunning()
        statusMessage = "Recording paused"
        AccessibilitySupport.announce("Recording paused")
    }

    func resumeRecording(reason: String = "manual") {
        log("resumeRecording reason=\(reason) isRecording=\(isRecording) paused=\(isCapturePaused)")
        guard isRecording else { return }
        guard isCapturePaused else {
            timelapseManager.startRunning()
            return
        }
        isCapturePaused = false
        timelapseManager.resumeCapture()
        statusMessage = "Recording…"
        AccessibilitySupport.announce("Recording resumed")
    }

    func recoverCameraAfterInterruption() {
        log("recoverCameraAfterInterruption isRecording=\(isRecording) paused=\(isCapturePaused)")
        guard isRecording, !isCapturePaused else { return }
        timelapseManager.startRunning()
    }

    /// The recording writer can't survive the app being suspended, so finalize the current
    /// segment before we background. Safe to call whether the session is running or paused.
    func prepareForBackground() {
        guard isRecording else { return }
        log("prepareForBackground paused=\(isCapturePaused)")
        timelapseManager.prepareForBackground()
    }

    func stopRecordingAndExport(
        wallClockSeconds: TimeInterval? = nil,
        completion: @escaping () -> Void
    ) {
        if let wallClockSeconds {
            recordedWallClockSeconds = wallClockSeconds
        }
        log("stopRecordingAndExport requested wall=\(recordedWallClockSeconds) isRecording=\(isRecording) didCapture=\(didCaptureThisSession) stopping=\(isStoppingRecording)")

        stopCompletions.append(completion)

        if isStoppingRecording {
            log("stopRecordingAndExport queued while stopping")
            return
        }

        guard isRecording || didCaptureThisSession else {
            log("stopRecordingAndExport no-op: no active capture")
            finishStopCompletions()
            return
        }

        isRecording = false
        isCapturePaused = false
        isStoppingRecording = true
        ScreenWakeLock.setActive(true)
        statusMessage = "Preparing your session…"
        AccessibilitySupport.announce("Recording stopped. Preparing your session")

        timelapseManager.stopRecording { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isStoppingRecording = false
                let rawExists = result.url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                self.log("stopRecording result url=\(result.url?.lastPathComponent ?? "nil") exists=\(rawExists) frames=\(result.frameCount)")

                guard let rawURL = result.url, result.frameCount > 0 else {
                    let pending = self.pendingTitleExport
                    self.pendingTitleExport = nil
                    self.isExporting = false
                    self.activeTitleExportTitle = nil
                    self.activeTitleExportCompletions.removeAll()
                    self.activeTitleExportShouldSaveToPhotos = false
                    self.didCaptureThisSession = false
                    self.lastError = "No video was captured. Record for a few seconds on a real device, then end the session."
                    self.statusMessage = nil
                    pending?.completions.forEach { $0(nil) }
                    self.finishStopCompletions()
                    return
                }

                self.lastExportFrameCount = result.frameCount
                self.previewFrames = Self.extractPreviewFrames(from: rawURL, count: 3)
                let durableRawURL = Self.copyRawClipToDurableStorage(rawURL)
                let sourceURL = durableRawURL ?? rawURL
                self.retainedRawURL = sourceURL
                self.rawClipURL = sourceURL
                self.log("raw source prepared previewFrames=\(self.previewFrames.count) source=\(self.rawClipURL?.lastPathComponent ?? "nil")")
                self.didCaptureThisSession = false
                self.statusMessage = "Ready to save"
                let pending = self.pendingTitleExport
                self.pendingTitleExport = nil
                self.finishStopCompletions()
                if let pending {
                    self.startTitleExport(
                        pending.title,
                        durationSeconds: pending.durationSeconds,
                        saveToPhotos: pending.saveToPhotos,
                        completions: pending.completions
                    )
                } else {
                    self.prepareTitledExport("Untitled session", durationSeconds: self.recordedWallClockSeconds)
                }
            }
        }
    }

    private func finishStopCompletions() {
        let completions = stopCompletions
        stopCompletions.removeAll()
        ScreenWakeLock.release()
        completions.forEach { $0() }
    }

    private static func copyRawClipToDurableStorage(_ rawURL: URL) -> URL? {
        let sourceURL = WrapStorage.newSessionSourceURL()
        do {
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try FileManager.default.removeItem(at: sourceURL)
            }
            try FileManager.default.copyItem(at: rawURL, to: sourceURL)
            RecordingDiagnostics.log("SessionRecording raw source copied from=\(rawURL.lastPathComponent) to=\(sourceURL.lastPathComponent)")
            return sourceURL
        } catch {
            RecordingDiagnostics.log("SessionRecording raw source copy failed error=\(error.localizedDescription)")
            return nil
        }
    }

    func resetForNewSession() {
        log("resetForNewSession final=\(finalVideoURL?.lastPathComponent ?? "nil") raw=\(rawClipURL?.lastPathComponent ?? "nil")")
        ScreenWakeLock.release()
        isRecording = false
        isCapturePaused = false
        isExporting = false
        titleExportRetryTask?.cancel()
        titleExportRetryTask = nil
        cancelHomePreviewIdleStop()
        let persistedRawURL = rawClipURL
        finalVideoURL = nil
        rawClipURL = nil
        if let raw = retainedRawURL {
            if persistedRawURL == raw {
                log("resetForNewSession kept persisted raw=\(raw.lastPathComponent)")
            } else {
                try? FileManager.default.removeItem(at: raw)
            }
            retainedRawURL = nil
        }
        lastExportFrameCount = 0
        previewFrames = []
        lastError = nil
        savedToPhotos = false
        photoAssetId = nil
        statusMessage = nil
        plannedSessionSeconds = 0
        recordedWallClockSeconds = 0
        didCaptureThisSession = false
        pendingTitleExport = nil
        activeTitleExportTitle = nil
        activeTitleExportCompletions.removeAll()
        activeTitleExportShouldSaveToPhotos = false
        completedTitleExportTitle = nil
        completedTitleExportSavedToPhotos = false
        stopCompletions.removeAll()
        timelapseManager.resetCapturePause()
    }

    func restoreExportContext(rawURL: URL?, finalURL: URL?) {
        guard !isRecording, !isStoppingRecording else {
            log("restoreExportContext skipped while recording")
            return
        }

        if let rawURL, FileManager.default.fileExists(atPath: rawURL.path) {
            retainedRawURL = rawURL
            rawClipURL = rawURL
            lastExportFrameCount = Self.estimatedFrameCount(from: rawURL)
            if previewFrames.isEmpty {
                previewFrames = Self.extractPreviewFrames(from: rawURL, count: 3)
            }
            log("restoreExportContext raw=\(rawURL.lastPathComponent) frames=\(lastExportFrameCount) previews=\(previewFrames.count)")
        }

        if let finalURL, FileManager.default.fileExists(atPath: finalURL.path) {
            finalVideoURL = finalURL
            if previewFrames.isEmpty {
                previewFrames = Self.extractPreviewFrames(from: finalURL, count: 3)
            }
            log("restoreExportContext final=\(finalURL.lastPathComponent) previews=\(previewFrames.count)")
        }
    }

    var wrappedDurationSeconds: TimeInterval {
        if let url = finalVideoURL {
            let asset = AVURLAsset(url: url)
            return CMTimeGetSeconds(asset.duration)
        }
        return AppConstants.wrappedDurationSeconds(frameCount: timelapseManager.lastCapturedFrameCount)
    }


    private func saveToPhotosIfPossible(videoURL: URL) async {
        do {
            photoAssetId = try await PhotoLibrarySaver.saveVideo(at: videoURL)
            savedToPhotos = true
            statusMessage = "Saved to Photos"
            AccessibilitySupport.announce("Saved to Photos")
            log("saved wrap to Photos asset=\(photoAssetId ?? "nil")")
        } catch {
            log("Photos save failed error=\(error.localizedDescription)")
            // Video is still available in-app via finalVideoURL and Share.
            lastError = error.localizedDescription
        }
    }

    nonisolated static func extractPreviewFrames(from url: URL, count: Int) -> [UIImage] {
        guard count > 0 else { return [] }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let durationSeconds = CMTimeGetSeconds(asset.duration)
        let totalSeconds = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : 1
        var images: [UIImage] = []
        let primaryTimes = previewFrameTimes(totalSeconds: totalSeconds, count: count)
        let fallbackTimes = previewFrameFallbackTimes(totalSeconds: totalSeconds)
        var attemptedTimes: [Double] = []

        for seconds in primaryTimes + fallbackTimes {
            guard images.count < count else { break }
            let clampedSeconds = min(max(seconds, 0), totalSeconds)
            guard !attemptedTimes.contains(where: { abs($0 - clampedSeconds) < 0.01 }) else { continue }
            attemptedTimes.append(clampedSeconds)

            let time = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                images.append(UIImage(cgImage: cgImage))
            }
        }

        guard !images.isEmpty else { return [] }

        let extractedCount = images.count
        while images.count < count {
            images.append(images[images.count % extractedCount])
        }

        return Array(images.prefix(count))
    }

    nonisolated static func estimatedFrameCount(from url: URL) -> Int {
        let asset = AVURLAsset(url: url)
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else { return 1 }
        return max(1, Int((durationSeconds * AppConstants.wrappedOutputFPS).rounded()))
    }

    nonisolated private static func previewFrameTimes(totalSeconds: Double, count: Int) -> [Double] {
        guard count > 1 else { return [0] }
        guard count > 2 else {
            return [0, Double.random(in: (totalSeconds * 0.55)...(totalSeconds * 0.95))]
        }

        let middle = Double.random(in: (totalSeconds * 0.33)...(totalSeconds * 0.66))
        let late = Double.random(in: (totalSeconds * 0.70)...(totalSeconds * 0.95))
        return [0, middle, late]
    }

    nonisolated private static func previewFrameFallbackTimes(totalSeconds: Double) -> [Double] {
        let safeStart = min(max(totalSeconds * 0.02, 0.03), max(totalSeconds * 0.25, 0.03))
        return [
            0,
            safeStart,
            totalSeconds * 0.10,
            totalSeconds * 0.25,
            totalSeconds * 0.40,
            totalSeconds * 0.55,
            totalSeconds * 0.70,
            totalSeconds * 0.85,
            totalSeconds * 0.95
        ]
    }

    /// Ensures the clean, durable master exists. The title is retained in this legacy API
    /// signature for recovery compatibility; text is applied only by the share composer.
    func prepareTitledExport(_ title: String, durationSeconds: TimeInterval = 0) {
        reexportWithTitle(title, durationSeconds: durationSeconds, saveToPhotos: false)
    }

    /// Ensures the clean session master exists. Explicit gallery saves happen after the user
    /// chooses a share template, so this defaults to app storage only.
    func reexportWithTitle(
        _ title: String,
        durationSeconds: TimeInterval = 0,
        saveToPhotos: Bool = false,
        completion: ((URL?) -> Void)? = nil
    ) {
        let exportTitle = normalizedTitle(title)
        log("reexportWithTitle title=\(exportTitle) duration=\(durationSeconds) saveToPhotos=\(saveToPhotos) isExporting=\(isExporting) retainedRaw=\(retainedRawURL?.lastPathComponent ?? "nil") frameCount=\(lastExportFrameCount)")

        if let finalVideoURL,
           FileManager.default.fileExists(atPath: finalVideoURL.path) {
            finishCachedTitleExport(
                finalVideoURL,
                saveToPhotos: saveToPhotos,
                completion: completion
            )
            return
        }

        guard !isExporting else {
            if pendingTitleExport != nil {
                queuePendingTitleExport(
                    title: exportTitle,
                    durationSeconds: durationSeconds,
                    saveToPhotos: saveToPhotos,
                    completion: completion
                )
            } else {
                if let completion {
                    activeTitleExportCompletions.append(completion)
                }
                if saveToPhotos {
                    activeTitleExportShouldSaveToPhotos = true
                }
            }
            return
        }

        guard exportSourceURL() != nil, lastExportFrameCount > 0 else {
            if isStoppingRecording {
                isExporting = true
                activeTitleExportTitle = exportTitle
                activeTitleExportCompletions = completion.map { [$0] } ?? []
                activeTitleExportShouldSaveToPhotos = saveToPhotos
                statusMessage = "Generating your Wrap…"
                ScreenWakeLock.setActive(true)
                pendingTitleExport = PendingTitleExport(
                    title: exportTitle,
                    durationSeconds: durationSeconds,
                    saveToPhotos: saveToPhotos,
                    completions: completion.map { [$0] } ?? []
                )
            } else {
                log("reexportWithTitle no retained raw; returning cached final=\(finalVideoURL?.lastPathComponent ?? "nil")")
                completion?(finalVideoURL)
            }
            return
        }

        startTitleExport(
            exportTitle,
            durationSeconds: durationSeconds,
            saveToPhotos: saveToPhotos,
            completions: completion.map { [$0] } ?? []
        )
    }

    private func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled session" : trimmed
    }

    private func queuePendingTitleExport(
        title: String,
        durationSeconds: TimeInterval,
        saveToPhotos: Bool,
        completion: ((URL?) -> Void)?
    ) {
        let newCompletions = completion.map { [$0] } ?? []
        if let existingPending = pendingTitleExport {
            pendingTitleExport = PendingTitleExport(
                title: title,
                durationSeconds: durationSeconds,
                saveToPhotos: existingPending.saveToPhotos || saveToPhotos,
                completions: existingPending.completions + newCompletions
            )
        } else {
            pendingTitleExport = PendingTitleExport(
                title: title,
                durationSeconds: durationSeconds,
                saveToPhotos: saveToPhotos,
                completions: newCompletions
            )
        }
    }

    private func finishCachedTitleExport(
        _ url: URL,
        saveToPhotos: Bool,
        completion: ((URL?) -> Void)?
    ) {
        guard saveToPhotos, !completedTitleExportSavedToPhotos else {
            completion?(url)
            return
        }

        isExporting = true
        statusMessage = "Saving your Wrap…"
        ScreenWakeLock.setActive(true)
        Task { @MainActor in
            await saveToPhotosIfPossible(videoURL: url)
            completedTitleExportSavedToPhotos = savedToPhotos
            isExporting = false
            statusMessage = nil
            ScreenWakeLock.release()
            completion?(url)
        }
    }

    private func startTitleExport(
        _ title: String,
        durationSeconds: TimeInterval,
        saveToPhotos: Bool,
        completions: [(URL?) -> Void]
    ) {
        guard let raw = exportSourceURL(), lastExportFrameCount > 0 else {
            log("startTitleExport missing raw/frameCount final=\(finalVideoURL?.lastPathComponent ?? "nil") raw=\(rawClipURL?.lastPathComponent ?? "nil") retained=\(retainedRawURL?.lastPathComponent ?? "nil")")
            lastError = finalVideoURL == nil ? "Could not generate wrap because the source video is missing." : lastError
            activeTitleExportTitle = nil
            activeTitleExportCompletions.removeAll()
            activeTitleExportShouldSaveToPhotos = false
            isExporting = false
            statusMessage = nil
            ScreenWakeLock.release()
            completions.forEach { $0(finalVideoURL) }
            return
        }

        isExporting = true
        activeTitleExportTitle = title
        activeTitleExportCompletions = completions
        activeTitleExportShouldSaveToPhotos = saveToPhotos
        lastError = nil
        statusMessage = "Generating your Wrap…"
        ScreenWakeLock.setActive(true)
        log("finalExport start raw=\(raw.lastPathComponent) frames=\(lastExportFrameCount)")
        exportEngine.generateWrappedVideo(
            rawVideoURL: raw,
            capturedFrameCount: lastExportFrameCount
        ) { [weak self] finalURL in
            Task { @MainActor in
                guard let self else { return }
                let finishedTitle = self.activeTitleExportTitle ?? title
                let callbacks = self.activeTitleExportCompletions
                let shouldSaveToPhotos = self.activeTitleExportShouldSaveToPhotos
                if let finalURL {
                    self.titleExportRetryTask?.cancel()
                    self.titleExportRetryTask = nil
                    self.activeTitleExportTitle = nil
                    self.activeTitleExportCompletions.removeAll()
                    self.activeTitleExportShouldSaveToPhotos = false
                    self.isExporting = false
                    self.statusMessage = nil
                    self.lastError = nil
                    let exists = FileManager.default.fileExists(atPath: finalURL.path)
                    self.log("finalExport success final=\(finalURL.lastPathComponent) exists=\(exists)")
                    // A recovery retry can replace an earlier master; remove the old file.
                    if let old = self.finalVideoURL, old != finalURL {
                        try? FileManager.default.removeItem(at: old)
                    }
                    self.finalVideoURL = finalURL
                    if self.previewFrames.isEmpty {
                        self.previewFrames = Self.extractPreviewFrames(from: finalURL, count: 3)
                    }
                    self.completedTitleExportTitle = finishedTitle
                    self.completedTitleExportSavedToPhotos = false
                    if shouldSaveToPhotos {
                        await self.saveToPhotosIfPossible(videoURL: finalURL)
                        self.completedTitleExportSavedToPhotos = self.savedToPhotos
                    }
                    ScreenWakeLock.release()
                    callbacks.forEach { $0(finalURL) }
                } else {
                    self.lastError = "Could not stitch session video."
                    self.statusMessage = "Generating your Wrap…"
                    self.isExporting = true
                    self.log("finalExport failed final=nil; retrying")
                    self.scheduleTitleExportRetry(
                        title: finishedTitle,
                        durationSeconds: durationSeconds,
                        saveToPhotos: shouldSaveToPhotos
                    )
                    return
                }

                let pending = self.pendingTitleExport
                self.pendingTitleExport = nil
                if let pending {
                    if let finalVideoURL = self.finalVideoURL {
                        self.finishCachedTitleExport(
                            finalVideoURL,
                            saveToPhotos: pending.saveToPhotos,
                            completion: { url in
                                pending.completions.forEach { $0(url) }
                            }
                        )
                    } else {
                        self.startTitleExport(
                            pending.title,
                            durationSeconds: pending.durationSeconds,
                            saveToPhotos: pending.saveToPhotos,
                            completions: pending.completions
                        )
                    }
                }
            }
        }
    }

    private func scheduleTitleExportRetry(
        title: String,
        durationSeconds: TimeInterval,
        saveToPhotos: Bool
    ) {
        titleExportRetryTask?.cancel()
        titleExportRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.titleExportRetryTask = nil
                if let pending = self.pendingTitleExport {
                    let activeCompletions = self.activeTitleExportCompletions
                    let shouldSave = saveToPhotos || self.activeTitleExportShouldSaveToPhotos || pending.saveToPhotos
                    self.pendingTitleExport = nil
                    self.startTitleExport(
                        pending.title,
                        durationSeconds: pending.durationSeconds,
                        saveToPhotos: shouldSave,
                        completions: activeCompletions + pending.completions
                    )
                } else {
                    self.startTitleExport(
                        self.activeTitleExportTitle ?? title,
                        durationSeconds: durationSeconds,
                        saveToPhotos: saveToPhotos || self.activeTitleExportShouldSaveToPhotos,
                        completions: self.activeTitleExportCompletions
                    )
                }
            }
        }
    }

    private func exportSourceURL() -> URL? {
        if let retainedRawURL, FileManager.default.fileExists(atPath: retainedRawURL.path) {
            return retainedRawURL
        }
        if let rawClipURL, FileManager.default.fileExists(atPath: rawClipURL.path) {
            retainedRawURL = rawClipURL
            if lastExportFrameCount <= 0 {
                lastExportFrameCount = Self.estimatedFrameCount(from: rawClipURL)
            }
            log("exportSource raw=\(rawClipURL.lastPathComponent) frames=\(lastExportFrameCount)")
            return rawClipURL
        }
        if let retainedRawURL {
            log("exportSource missing retained path=\(retainedRawURL.lastPathComponent)")
        }
        if let rawClipURL {
            log("exportSource missing raw path=\(rawClipURL.lastPathComponent)")
        }
        return nil
    }

    private func log(_ message: String) {
        RecordingDiagnostics.log("SessionRecording \(message)")
    }
}
