//
//  TimelapseManager.swift
//  lucky7
//
//  Spreads up to 1800 frames evenly across the planned session.
//  Stops early → fewer frames → shorter video (e.g. half session → 900 frames → 15s @ 60fps).
//
//  Segmented across app-background: an AVAssetWriter can't survive the app being suspended
//  (iOS reclaims the VideoToolbox encoder and the writer goes terminal .failed). So every time
//  we background we finalize the current writer to its own file and open a fresh one on resume,
//  then stitch the segments back into one raw clip at finish. A session that never backgrounds
//  is a single segment and returns that file directly — unchanged from the old single-writer path.
//

import AVFoundation
import UIKit

struct TimelapseStopResult {
    let url: URL?
    let frameCount: Int
}

final class TimelapseManager: NSObject {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.lucky7.timelapse.session")
    private let writerQueue = DispatchQueue(label: "com.lucky7.timelapse.writer")

    private var videoOutput: AVCaptureVideoDataOutput?
    private var assetWriter: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private lazy var sampleBufferDelegate = TimelapseSampleBufferDelegate { [weak self] sampleBuffer in
        self?.appendFrame(from: sampleBuffer)
    }

    private var cameraFrameIndex = 0
    /// Frames captured across the WHOLE session (all segments). Drives capture cadence + duration.
    private var framesCaptured = 0
    /// Frames in the CURRENT segment only. Drives per-segment presentation time (restarts at 0
    /// every segment, because each segment's writer does startSession(atSourceTime: .zero)).
    private var segmentFrameIndex = 0
    /// Finalized segment files (each with >= 1 written frame), in capture order.
    private var segmentURLs: [URL] = []
    /// Set when the live writer was torn down (background / writer-failure) and the next frame
    /// should open a fresh segment. NOT the same as `assetWriter == nil`, which is also the idle
    /// state after reset/finish — we must not spawn a segment in those cases.
    private var needsNewSegment = false
    /// True from the moment finishRecording commits to stopping — blocks opening new segments.
    private var isStopping = false
    /// True while a background segment finalize (finishWriting) is still flushing. finishRecording
    /// waits this out so it never double-finalizes the same writer.
    private var finalizingInFlight = false
    /// Bumped by resetWriterState. A background finalize captures it before finishWriting; if it
    /// no longer matches when the (async, off-queue) completion lands, the session was reset / a
    /// new one started underneath it, so the late segment is discarded instead of corrupting state.
    private var finalizeGeneration = 0
    private var plannedSessionSeconds: TimeInterval = 3600
    private var captureIntervalSeconds: TimeInterval = 2
    private var isRecording = false
    private var capturePaused = false
    private var isWriterReady = false
    private var hasWrittenFrame = false
    private var recordingStartWallSeconds: Double?
    private var totalPausedSeconds: Double = 0
    private var pauseBeganWallSeconds: Double?
    private var configuredPosition: AVCaptureDevice.Position = .front
    private var recordingOrientation: UIInterfaceOrientation = .portrait
    private var sampleBuffersReceived = 0
    private var loggedNotRecordingDrop = false
    private var loggedPausedDrop = false
    private var loggedMissingWriterDrop = false
    private var pendingStartCompletion: ((Bool) -> Void)?
    private var captureCommandGeneration = 0
    private var activePowerProfile: RecordingPowerProfile?
    /// Keeps the app alive long enough to flush finishWriting when we background mid-recording.
    /// Touched only on the main thread.
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    private(set) var outputURL: URL?
    private(set) var lastCapturedFrameCount = 0
    /// Frames captured in the current or most recent recording session.
    var currentFrameCount: Int { framesCaptured }

    var captureSession: AVCaptureSession { session }

    // MARK: - Setup

    func requestPermissionAndConfigure(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            log("camera permission authorized")
            // Already configured? Just make sure it's running. prepareCamera() fires on
            // every return to foreground — rebuilding here would glitch an in-flight
            // recording and snap a back-camera pick back to the front camera.
            sessionQueue.async {
                if self.session.inputs.isEmpty {
                    self.log("configuring camera: no existing input")
                    self.configureSession(position: .front, completion: completion)
                } else {
                    if !self.session.isRunning { self.session.startRunning() }
                    self.log("camera already configured inputs=\(self.session.inputs.count) outputs=\(self.session.outputs.count) running=\(self.session.isRunning)")
                    DispatchQueue.main.async { completion(true) }
                }
            }
        case .notDetermined:
            log("camera permission not determined; requesting")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                self.log("camera permission request result granted=\(granted)")
                if granted {
                    self.configureSession(position: .front, completion: completion)
                } else {
                    DispatchQueue.main.async { completion(false) }
                }
            }
        default:
            log("camera permission denied/restricted status=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue)")
            DispatchQueue.main.async { completion(false) }
        }
    }

    func switchCamera() {
        sessionQueue.async {
            let next: AVCaptureDevice.Position = self.currentPosition() == .front ? .back : .front
            self.configureSession(position: next, completion: nil)
        }
    }

    func startRunning() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            self.log("camera startRunning running=\(self.session.isRunning)")
        }
    }

    func restartRunning() {
        sessionQueue.async {
            self.log("camera restart requested runningBefore=\(self.session.isRunning)")
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.session.startRunning()
            self.log("camera restart finished running=\(self.session.isRunning)")
        }
    }

    func stopRunning() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            self.log("camera stopRunning")
        }
    }

    // MARK: - Recording

    func pauseCapture() {
        writerQueue.async {
            self.captureCommandGeneration += 1
            self.pauseCaptureOnWriterQueue()
        }
    }

    func resumeCapture() {
        writerQueue.async {
            self.captureCommandGeneration += 1
            let generation = self.captureCommandGeneration
            self.sessionQueue.async {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                self.log("camera ensured for resume running=\(self.session.isRunning) generation=\(generation)")
                self.writerQueue.async {
                    guard generation == self.captureCommandGeneration else {
                        self.log("capture resume ignored: stale generation=\(generation) current=\(self.captureCommandGeneration)")
                        return
                    }
                    self.resumeCaptureOnWriterQueue()
                }
            }
        }
    }

    /// Called from scenePhase .background whenever a session is live (running OR already paused).
    /// The writer can't survive suspension, so finalize the current segment NOW — atomically with
    /// pausing — and arrange for a fresh segment on the next resume.
    func prepareForBackground() {
        writerQueue.async {
            self.captureCommandGeneration += 1
            self.capturePaused = true
            if self.pauseBeganWallSeconds == nil {
                self.pauseBeganWallSeconds = self.currentWallElapsedSeconds()
            }
            guard self.isRecording else { return }
            self.finalizeCurrentSegmentForBackground()
        }
    }

    private func pauseCaptureOnWriterQueue() {
        capturePaused = true
        log("capture paused framesCaptured=\(framesCaptured) samples=\(sampleBuffersReceived)")
        if pauseBeganWallSeconds == nil {
            pauseBeganWallSeconds = currentWallElapsedSeconds()
        }
    }

    private func resumeCaptureOnWriterQueue() {
        guard isRecording else {
            log("capture resume ignored: not recording")
            return
        }
        let wasPaused = capturePaused || pauseBeganWallSeconds != nil
        guard wasPaused else {
            log("capture resume ignored: already active framesCaptured=\(framesCaptured) samples=\(sampleBuffersReceived)")
            return
        }

        if let began = pauseBeganWallSeconds {
            let end = currentWallElapsedSeconds()
            totalPausedSeconds += max(0, end - began)
            pauseBeganWallSeconds = nil
        }
        capturePaused = false
        loggedPausedDrop = false
        log("capture resumed framesCaptured=\(framesCaptured) samples=\(sampleBuffersReceived) needsNewSegment=\(needsNewSegment)")
    }

    func resetCapturePause() {
        writerQueue.async {
            self.captureCommandGeneration += 1
            self.capturePaused = false
            self.pauseBeganWallSeconds = nil
            self.log("capture pause reset")
        }
    }

    func startRecording(plannedSessionSeconds: TimeInterval, completion: ((Bool) -> Void)? = nil) {
        writerQueue.async {
            self.resetWriterState()
            self.recordingOrientation = VideoOrientationHelper.currentRecordingOrientationSync()
            self.plannedSessionSeconds = max(plannedSessionSeconds, AppConstants.minimumPlannedSessionSeconds)
            self.captureIntervalSeconds = AppConstants.captureIntervalSeconds(plannedSessionSeconds: self.plannedSessionSeconds)
            let powerProfile = RecordingPowerProfile.recording(plannedSessionSeconds: self.plannedSessionSeconds)
            self.setPowerProfile(powerProfile, reason: "startRecording")

            print(
                String(
                    format: "TimelapseManager: planned %.0fs → capture every %.2fs targetCameraFPS=%.0f (up to %d frames = %.0fs video)",
                    self.plannedSessionSeconds,
                    self.captureIntervalSeconds,
                    powerProfile.requestedFPS,
                    AppConstants.maxFramesForFullSession,
                    AppConstants.maxWrappedDurationSeconds
                )
            )

            self.outputURL = Self.makeOutputURL(suffix: "raw")
            guard self.outputURL != nil else {
                self.log("startRecording failed: output URL nil")
                DispatchQueue.main.async { completion?(false) }
                return
            }

            do {
                let writer = try AVAssetWriter(outputURL: self.outputURL!, fileType: .mp4)
                self.assetWriter = writer
                self.isRecording = true
                self.pendingStartCompletion = completion
                self.startRunning()
                self.log(
                    "startRecording ok raw=\(self.outputURL!.lastPathComponent) "
                        + "interval=\(String(format: "%.3f", self.captureIntervalSeconds)) "
                        + "orientation=\(VideoOrientationHelper.orientationName(self.recordingOrientation))"
                )
                self.writerQueue.asyncAfter(deadline: .now() + .seconds(4)) {
                    guard self.isRecording, self.framesCaptured == 0, self.pendingStartCompletion != nil else { return }
                    self.log("startRecording failed first-frame timeout samples=\(self.sampleBuffersReceived) writerReady=\(self.isWriterReady)")
                    if let url = self.outputURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                    self.isRecording = false
                    self.finishStartCompletion(false)
                    self.resetWriterState()
                }
            } catch {
                self.log("startRecording failed writer error=\(error.localizedDescription)")
                self.isRecording = false
                DispatchQueue.main.async { completion?(false) }
            }
        }
    }

    func stopRecording(completion: @escaping (TimelapseStopResult) -> Void) {
        let waitUntil = DispatchTime.now() + .milliseconds(1200)
        let finalizeDeadline = DispatchTime.now() + .seconds(5)
        writerQueue.async {
            self.finishRecording(waitUntil: waitUntil, finalizeDeadline: finalizeDeadline, completion: completion)
        }
    }

    private func finishRecording(
        waitUntil: DispatchTime,
        finalizeDeadline: DispatchTime,
        completion: @escaping (TimelapseStopResult) -> Void
    ) {
        guard self.isRecording else {
            self.finishStartCompletion(false)
            DispatchQueue.main.async {
                completion(TimelapseStopResult(url: nil, frameCount: 0))
            }
            return
        }

        // A background segment finalize might still be flushing — let it land (so its frames
        // make it into segmentURLs) before we read the segment list / finalize the live writer.
        if self.finalizingInFlight, DispatchTime.now().uptimeNanoseconds < finalizeDeadline.uptimeNanoseconds {
            self.writerQueue.asyncAfter(deadline: .now() + .milliseconds(150)) {
                self.finishRecording(waitUntil: waitUntil, finalizeDeadline: finalizeDeadline, completion: completion)
            }
            return
        }

        var liveSegmentHasFrames = self.isWriterReady && self.segmentFrameIndex > 0
        var hasAnyFootage = !self.segmentURLs.isEmpty || liveSegmentHasFrames

        if !hasAnyFootage, self.capturePaused {
            self.endPauseAccountingForStop()
            liveSegmentHasFrames = self.isWriterReady && self.segmentFrameIndex > 0
            hasAnyFootage = !self.segmentURLs.isEmpty || liveSegmentHasFrames
        }

        if !hasAnyFootage,
           DispatchTime.now().uptimeNanoseconds < waitUntil.uptimeNanoseconds {
            self.log("stop waiting for first usable frame samples=\(self.sampleBuffersReceived) writerReady=\(self.isWriterReady) segFrames=\(self.segmentFrameIndex) segments=\(self.segmentURLs.count)")
            self.startRunning()
            self.writerQueue.asyncAfter(deadline: .now() + .milliseconds(150)) {
                self.finishRecording(waitUntil: waitUntil, finalizeDeadline: finalizeDeadline, completion: completion)
            }
            return
        }

        self.isRecording = false
        self.isStopping = true

        // Finalize the live segment if it captured anything, then deliver. The finishWriting
        // completion runs off our queue, so re-hop to writerQueue before touching shared state.
        if liveSegmentHasFrames, let writer = self.assetWriter, let input = self.writerInput, let url = self.outputURL {
            let segFrames = self.segmentFrameIndex
            self.assetWriter = nil
            self.writerInput = nil
            self.pixelBufferAdaptor = nil
            self.isWriterReady = false
            self.segmentFrameIndex = 0
            input.markAsFinished()
            writer.finishWriting {
                let ok = writer.status == .completed
                self.writerQueue.async {
                    if ok {
                        self.segmentURLs.append(url)
                    } else {
                        try? FileManager.default.removeItem(at: url)
                        self.framesCaptured = max(0, self.framesCaptured - segFrames)
                        self.log("stop live segment finalize failed status=\(writer.status.rawValue) error=\(writer.error?.localizedDescription ?? "unknown")")
                    }
                    self.log("stop finalized live segment ok=\(ok) frames=\(segFrames)")
                    self.deliverFinalResult(completion: completion)
                }
            }
        } else {
            // No frames in the live segment — drop any empty writer and ship the earlier segments.
            self.discardCurrentSegment()
            self.deliverFinalResult(completion: completion)
        }
    }

    /// Builds the final raw clip from whatever segments we captured and hands it back on main.
    /// Always runs on writerQueue.
    private func deliverFinalResult(completion: @escaping (TimelapseStopResult) -> Void) {
        let segments = self.segmentURLs
        let captured = self.framesCaptured

        guard !segments.isEmpty else {
            self.log("stop failed: no segments captured samples=\(self.sampleBuffersReceived)")
            self.finishStartCompletion(false)
            self.resetWriterState()
            DispatchQueue.main.async {
                completion(TimelapseStopResult(url: nil, frameCount: 0))
            }
            return
        }

        if segments.count == 1 {
            let url = segments[0]
            let exists = FileManager.default.fileExists(atPath: url.path)
            self.lastCapturedFrameCount = captured
            self.segmentURLs = []   // hand ownership to the caller; don't let reset delete it
            self.log("stop finished single segment frames=\(captured) url=\(url.lastPathComponent) exists=\(exists)")
            self.resetWriterState()
            DispatchQueue.main.async {
                completion(TimelapseStopResult(url: url, frameCount: captured))
            }
            return
        }

        // 2+ segments → stitch them back into one continuous raw clip. Keep the app alive for
        // the export in case the user has wandered off to the recap screen.
        self.log("stop stitching segments=\(segments.count) frames=\(captured)")
        self.beginBackgroundTaskIfNeeded()
        Task {
            var stitched: (url: URL, durationSeconds: Double)?
            for attempt in 1...3 {
                stitched = await ExportEngine.shared.concatenateRawSegments(segments)
                if stitched != nil { break }
                self.log("stitch retry attempt=\(attempt) segments=\(segments.count)")
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            self.writerQueue.async {
                self.endBackgroundTask()
                if let stitched {
                    // Frame count from the stitched duration so the downstream scaleTimeRange stays a no-op.
                    let count = max(1, Int((stitched.durationSeconds * AppConstants.wrappedOutputFPS).rounded()))
                    for url in segments { try? FileManager.default.removeItem(at: url) }
                    self.lastCapturedFrameCount = count
                    self.segmentURLs = []
                    self.log("stitch ok segments=\(segments.count) frames=\(count) url=\(stitched.url.lastPathComponent)")
                    self.resetWriterState()
                    DispatchQueue.main.async {
                        completion(TimelapseStopResult(url: stitched.url, frameCount: count))
                    }
                } else {
                    self.log("stitch FAILED; no fallback raw source will be used")
                    self.resetWriterState()
                    DispatchQueue.main.async {
                        completion(TimelapseStopResult(url: nil, frameCount: 0))
                    }
                }
            }
        }
    }

    // MARK: - Private

    private func configureSession(position: AVCaptureDevice.Position, completion: ((Bool) -> Void)?) {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                self.log("configure failed position=\(position.rawValue)")
                DispatchQueue.main.async { completion?(false) }
                return
            }

            self.session.addInput(input)
            self.configuredPosition = position

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self.sampleBufferDelegate, queue: self.writerQueue)

            guard self.session.canAddOutput(output) else {
                self.session.commitConfiguration()
                self.log("configure failed: cannot add output")
                DispatchQueue.main.async { completion?(false) }
                return
            }

            self.session.addOutput(output)
            self.videoOutput = output

            // Keep sample buffers in sensor orientation; AVAssetWriterInput.transform
            // sets the correct portrait/landscape metadata on the saved file.
            if let connection = output.connection(with: .video) {
                let angle: CGFloat = 0
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }

            self.session.commitConfiguration()

            if !self.session.isRunning {
                self.session.startRunning()
            }

            self.log("configure success position=\(position.rawValue) inputs=\(self.session.inputs.count) outputs=\(self.session.outputs.count) running=\(self.session.isRunning)")
            self.applyActivePowerProfile(reason: "configureSession")
            DispatchQueue.main.async { completion?(true) }
        }
    }

    private func setPowerProfile(_ profile: RecordingPowerProfile, reason: String) {
        sessionQueue.async {
            self.activePowerProfile = profile
            self.applyActivePowerProfile(reason: reason)
        }
    }

    private func restorePreviewPowerProfile(reason: String) {
        sessionQueue.async {
            self.activePowerProfile = nil
            self.applyPowerProfile(.preview, reason: reason)
        }
    }

    private func applyActivePowerProfile(reason: String) {
        guard let activePowerProfile else { return }
        applyPowerProfile(activePowerProfile, reason: reason)
    }

    private func applyPowerProfile(_ profile: RecordingPowerProfile, reason: String) {
        guard let input = session.inputs.first as? AVCaptureDeviceInput else {
            log("powerProfile skipped reason=\(reason) noInput")
            return
        }

        do {
            let applied = try profile.apply(to: input.device)
            log(
                String(
                    format: "powerProfile reason=%@ planned=%.0fs interval=%.2fs requestedFPS=%.0f appliedFPS=%.2f supported=%.2f...%.2f formatChanged=%@ dimensions=%dx%d",
                    reason,
                    profile.plannedSessionSeconds,
                    profile.captureIntervalSeconds,
                    applied.requestedFPS,
                    applied.appliedFPS,
                    applied.minSupportedFPS,
                    applied.maxSupportedFPS,
                    applied.formatChanged ? "yes" : "no",
                    applied.width,
                    applied.height
                )
            )
        } catch {
            log("powerProfile failed reason=\(reason) error=\(error.localizedDescription)")
        }
    }

    private func currentPosition() -> AVCaptureDevice.Position {
        guard let input = session.inputs.first as? AVCaptureDeviceInput else { return .front }
        return input.device.position
    }

    private func resetWriterState() {
        assetWriter = nil
        writerInput = nil
        pixelBufferAdaptor = nil
        isWriterReady = false
        hasWrittenFrame = false
        cameraFrameIndex = 0
        framesCaptured = 0
        segmentFrameIndex = 0
        // Delete any segment files that weren't handed off to a caller (abandoned recording).
        for url in segmentURLs { try? FileManager.default.removeItem(at: url) }
        segmentURLs = []
        needsNewSegment = false
        isStopping = false
        finalizingInFlight = false
        // Invalidate any background finalize still in flight so its late completion no-ops.
        finalizeGeneration += 1
        sampleBuffersReceived = 0
        loggedNotRecordingDrop = false
        loggedPausedDrop = false
        loggedMissingWriterDrop = false
        recordingStartWallSeconds = nil
        totalPausedSeconds = 0
        pauseBeganWallSeconds = nil
        pendingStartCompletion = nil
        captureCommandGeneration = 0
        restorePreviewPowerProfile(reason: "resetWriterState")
    }

    private static func makeOutputURL(suffix: String) -> URL? {
        let name = "timelapse_\(suffix)_\(UUID().uuidString).mp4"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    /// Opens a fresh writer for the next segment (after a background or a writer failure).
    /// The input + startSession are added lazily on the first real frame in setupWriterIfNeeded.
    private func beginNewSegment() -> Bool {
        guard let url = Self.makeOutputURL(suffix: "raw") else {
            log("new segment failed: output URL nil")
            return false
        }
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            assetWriter = writer
            outputURL = url
            writerInput = nil
            pixelBufferAdaptor = nil
            isWriterReady = false
            segmentFrameIndex = 0
            loggedPausedDrop = false
            loggedMissingWriterDrop = false
            log("new segment opened url=\(url.lastPathComponent) totalFrames=\(framesCaptured)")
            return true
        } catch {
            log("new segment failed error=\(error.localizedDescription)")
            return false
        }
    }

    /// Throws away the current (unusable / empty) writer and its file without counting its frames.
    private func discardCurrentSegment() {
        guard let writer = assetWriter else { return }
        if writer.status == .writing {
            writer.cancelWriting()
        }
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        framesCaptured = max(0, framesCaptured - segmentFrameIndex)
        segmentFrameIndex = 0
        assetWriter = nil
        writerInput = nil
        pixelBufferAdaptor = nil
        isWriterReady = false
    }

    /// Atomically (on writerQueue) tears down the live writer ahead of suspension. Non-empty
    /// segments are finished to disk; empty ones are dropped. Either way the next resume opens
    /// a fresh segment.
    private func finalizeCurrentSegmentForBackground() {
        guard let writer = assetWriter else {
            needsNewSegment = true
            return
        }

        if isWriterReady, let input = writerInput, segmentFrameIndex > 0 {
            let url = outputURL
            let segFrames = segmentFrameIndex
            assetWriter = nil
            writerInput = nil
            pixelBufferAdaptor = nil
            isWriterReady = false
            segmentFrameIndex = 0
            needsNewSegment = true
            finalizingInFlight = true
            let gen = finalizeGeneration
            beginBackgroundTaskIfNeeded()
            input.markAsFinished()
            writer.finishWriting {
                let ok = writer.status == .completed
                self.writerQueue.async {
                    // The session may have been reset / a new one started while this flush was in
                    // the air (e.g. End tapped past the finalize deadline). If so this segment is
                    // orphaned — drop its file and don't touch the now-foreign live state.
                    guard gen == self.finalizeGeneration else {
                        if let url { try? FileManager.default.removeItem(at: url) }
                        self.endBackgroundTask()
                        self.log("background segment finalize stale gen=\(gen) current=\(self.finalizeGeneration); discarded \(url?.lastPathComponent ?? "nil")")
                        return
                    }
                    if ok, let url {
                        self.segmentURLs.append(url)
                        self.log("background segment finalized frames=\(segFrames) url=\(url.lastPathComponent)")
                    } else {
                        if let url { try? FileManager.default.removeItem(at: url) }
                        self.framesCaptured = max(0, self.framesCaptured - segFrames)
                        self.log("background segment finalize failed status=\(writer.status.rawValue) error=\(writer.error?.localizedDescription ?? "unknown")")
                    }
                    self.finalizingInFlight = false
                    self.endBackgroundTask()
                }
            }
        } else {
            // Writer never produced a frame this segment — nothing worth keeping.
            discardCurrentSegment()
            needsNewSegment = true
            log("background discarded empty segment framesCaptured=\(framesCaptured)")
        }
    }

    private func currentWallElapsedSeconds(now: Double = ProcessInfo.processInfo.systemUptime) -> Double {
        guard let start = recordingStartWallSeconds else { return 0 }
        return max(0, now - start - totalPausedSeconds)
    }

    private func shouldCaptureFrame(wallElapsed: Double) -> Bool {
        guard framesCaptured < AppConstants.maxFramesForFullSession else { return false }
        if framesCaptured == 0 { return true }
        let nextCaptureAt = Double(framesCaptured) * captureIntervalSeconds
        return wallElapsed + 0.001 >= nextCaptureAt
    }

    private func endPauseAccountingForStop() {
        if let began = pauseBeganWallSeconds {
            let end = currentWallElapsedSeconds()
            totalPausedSeconds += max(0, end - began)
            pauseBeganWallSeconds = nil
        }
        capturePaused = false
        log("stop unpaused capture to flush final frame framesCaptured=\(framesCaptured) samples=\(sampleBuffersReceived)")
    }

    private func outputPresentationTime(forFrameIndex index: Int) -> CMTime {
        CMTime(value: CMTimeValue(index), timescale: CMTimeScale(AppConstants.wrappedOutputFPS))
    }

    private func setupWriterIfNeeded(from sampleBuffer: CMSampleBuffer) -> Bool {
        guard let writer = assetWriter, writer.status == .unknown else {
            return isWriterReady
        }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            log("setupWriter failed: no formatDescription")
            return false
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        guard width > 0, height > 0 else {
            log("setupWriter failed: invalid dimensions \(width)x\(height)")
            return false
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        input.transform = VideoOrientationHelper.writerTransform(
            bufferWidth: width,
            bufferHeight: height,
            cameraPosition: configuredPosition,
            orientation: recordingOrientation
        )

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        guard writer.canAdd(input) else {
            log("setupWriter failed: writer cannot add input")
            return false
        }

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        writerInput = input
        pixelBufferAdaptor = adaptor
        isWriterReady = true
        // Set ONCE for the whole session — new segments reuse the same wall-clock origin so the
        // capture cadence stays continuous across backgrounds.
        if recordingStartWallSeconds == nil {
            recordingStartWallSeconds = ProcessInfo.processInfo.systemUptime
        }
        log("setupWriter ok dimensions=\(width)x\(height) camera=\(configuredPosition.rawValue) orientationApplied=\(VideoOrientationHelper.orientationName(recordingOrientation))")
        return true
    }

    private func appendFrame(from sampleBuffer: CMSampleBuffer) {
        sampleBuffersReceived += 1
        if sampleBuffersReceived <= 3 {
            log("sample received #\(sampleBuffersReceived) isRecording=\(isRecording) paused=\(capturePaused) writerNil=\(assetWriter == nil)")
        }

        guard isRecording else {
            if !loggedNotRecordingDrop {
                loggedNotRecordingDrop = true
                log("sample dropped: not recording")
            }
            return
        }
        guard !capturePaused else {
            if !loggedPausedDrop {
                loggedPausedDrop = true
                log("sample dropped: paused")
            }
            return
        }

        // After a background (or writer failure) the live writer is gone — open the next segment
        // on the first frame that flows once we're un-paused. Gated on needsNewSegment, never on a
        // bare nil writer, so a stray frame after finish/reset can't spawn a phantom segment.
        if assetWriter == nil {
            guard needsNewSegment, !isStopping else {
                if !loggedMissingWriterDrop {
                    loggedMissingWriterDrop = true
                    log("sample dropped: no active segment")
                }
                return
            }
            guard beginNewSegment() else { return }
            needsNewSegment = false
        }

        guard let writer = assetWriter else { return }

        // Writer died mid-foreground (media-services reset / encoder loss): roll over to a fresh
        // segment instead of silently dropping every remaining frame.
        guard writer.status != .failed else {
            log("writer failed mid-segment error=\(writer.error?.localizedDescription ?? "unknown") — rolling to new segment frames=\(segmentFrameIndex)")
            discardCurrentSegment()
            needsNewSegment = true
            return
        }

        cameraFrameIndex += 1
        if !isWriterReady {
            guard setupWriterIfNeeded(from: sampleBuffer) else { return }
        }

        guard writer.status == .writing,
              let input = writerInput,
              input.isReadyForMoreMediaData,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let wallElapsed = currentWallElapsedSeconds()
        guard shouldCaptureFrame(wallElapsed: wallElapsed) else { return }

        let presentationTime = outputPresentationTime(forFrameIndex: segmentFrameIndex)

        guard pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: presentationTime) == true else {
            log("append failed segFrame=\(segmentFrameIndex) total=\(framesCaptured) writerStatus=\(writer.status.rawValue) inputReady=\(input.isReadyForMoreMediaData)")
            return
        }

        segmentFrameIndex += 1
        framesCaptured += 1
        hasWrittenFrame = true
        if framesCaptured == 1 {
            finishStartCompletion(true)
        }
        if framesCaptured <= 3 || framesCaptured == 10 || framesCaptured % 60 == 0 {
            log("frame appended total=\(framesCaptured) segFrame=\(segmentFrameIndex) samples=\(sampleBuffersReceived)")
        }
    }

    private func finishStartCompletion(_ started: Bool) {
        guard let completion = pendingStartCompletion else { return }
        pendingStartCompletion = nil
        DispatchQueue.main.async {
            completion(started)
        }
    }

    // MARK: - Background task (keeps finishWriting alive across suspension)

    private func beginBackgroundTaskIfNeeded() {
        DispatchQueue.main.async {
            guard self.backgroundTaskId == .invalid else { return }
            self.backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "com.lucky7.timelapse.finalize") {
                self.endBackgroundTaskOnMain()
            }
        }
    }

    private func endBackgroundTask() {
        DispatchQueue.main.async {
            self.endBackgroundTaskOnMain()
        }
    }

    private func endBackgroundTaskOnMain() {
        guard backgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
    }

    private func log(_ message: String) {
        RecordingDiagnostics.log("Timelapse \(message)")
    }
}

private final class TimelapseSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated(unsafe) private let onSampleBuffer: (CMSampleBuffer) -> Void

    init(onSampleBuffer: @escaping (CMSampleBuffer) -> Void) {
        self.onSampleBuffer = onSampleBuffer
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onSampleBuffer(sampleBuffer)
    }
}
