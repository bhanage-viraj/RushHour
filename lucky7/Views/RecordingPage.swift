//
//  RecordingPage.swift
//  lucky7
//

import SwiftUI
import SwiftData
import AVFoundation
import CoreImage
import UserNotifications
import Combine

// MARK: - Main View

struct RecordingPage: View {
    /// When true (entered from the home record button) the session begins as soon as
    /// the camera is ready, instead of waiting for the on-screen START button.
    var autoStart: Bool = false

    /// When true, RecordingPage is hosted *in place* inside HomePage rather than pushed.
    /// In that mode HomePage owns the one shared camera preview for the whole app (two
    /// `AVCaptureVideoPreviewLayer`s on a single session fight for the feed and one goes
    /// black), and morphs ITS camera into the focus circle — so this view draws no camera
    /// of its own. It ends the session via `onExit` instead of popping a navigation stack.
    var embedded: Bool = false

    /// Drives the expanded full-focus layout. A binding so an embedded host (HomePage) can
    /// morph its shared camera into the focus circle in lock-step with this view's chrome.
    @Binding var isExpanded: Bool

    var onExit: (() -> Void)? = nil

    @State private var hasStarted = false
    @State private var isStartingSession = false
    @State private var isPauseResumeTransitioning = false
    @State private var showEndConfirm = false
    @State private var showResumeReminder = false
    /// Set when the app is backgrounded mid-session, so only a real return to the app
    /// (not a Control Center / Notification Center pull-down) brings up the reminder.
    @State private var leftAppMidSession = false
    @State private var showFinishSessionFlow = false
    @State private var showCrashSession = false
    @State private var showNotifNudge = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionTimer: SessionTimerViewModel
    @EnvironmentObject private var sessionRecording: SessionRecordingViewModel

    #if os(iOS)
    @EnvironmentObject private var focusController: FocusViewModel
    #endif

    private let focusTransition = Animation.spring(response: 0.42, dampingFraction: 0.92, blendDuration: 0.08)

    /// Dim only while frames are actually being captured and nothing needs the
    /// user's attention — any modal, pause, or export restores full brightness.
    private var shouldDimScreen: Bool {
        hasStarted
            && sessionTimer.isRunning
            && !showEndConfirm
            && !showResumeReminder
            && !showFinishSessionFlow
            && !showCrashSession
            && !showNotifNudge
            && pendingPrompt == nil
            && unlock == nil
            && breakBlockedInfo == nil
            && !sessionRecording.isExporting
            && scenePhase == .active
    }

    /// The break flow's own prompts (reason form, unlock / one-break cards) take
    /// priority; the paused-session reminder waits behind them.
    private var isResumeReminderVisible: Bool {
        showResumeReminder
            && pendingPrompt == nil
            && unlock == nil
            && breakBlockedInfo == nil
    }

    // jailbreak: distraction prompt + in-app unlock card + records sheet
    @State private var pendingPrompt: PendingPrompt?
    @State private var unlock: UnlockInfo?
    @State private var breakBlockedInfo: BreakBlockedInfo?
    @State private var showBreakSaveError = false

    struct PendingPrompt: Identifiable {
        let id = UUID()
        let distraction: Distraction
        let tokenDataToClear: Data?
    }

    struct UnlockInfo: Identifiable {
        let id = UUID()
        var timeText: String = ""
    }

    // shown instead of the reason form when a break is already running — only one
    // app can be unlocked at a time, so a second "Break It" is rejected with a warning.
    struct BreakBlockedInfo: Identifiable {
        let id = UUID()
    }

    var body: some View {

        ZStack {

            // Session background. Standalone only; when embedded,
            // HomePage draws the session background beneath its shared camera.
            if !embedded {
                RecordingBackground(isExpanded: isExpanded, isPaused: hasStarted && !sessionTimer.isRunning)
                    .animation(focusTransition, value: isExpanded)
            }

            // Camera preview — STANDALONE ONLY. Morphs between full-screen fill and the
            // focus circle. When embedded, HomePage owns the single shared preview layer
            // and morphs it into the circle itself, so we draw no camera here.
            if !embedded {
                GeometryReader { geo in
                    let layout = RecordingLayout(size: geo.size, isExpanded: isExpanded,
                                                 isPaused: hasStarted && !sessionTimer.isRunning)
                    let camera = layout.camera

                    ZStack {
                        CameraPreview(session: sessionRecording.captureSession)
                            .frame(width: camera.width, height: camera.height)
                            .overlay {
                                if !isExpanded {
                                    RecordingCameraShading(isPaused: hasStarted && !sessionTimer.isRunning)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: isExpanded ? camera.width / 2 : 30 * layout.scale))
                            .shadow(color: isExpanded ? .black : .clear, radius: 0, y: 4 * layout.scale)
                            .overlay {
                                if !isExpanded {
                                    RoundedRectangle(cornerRadius: 30 * layout.scale)
                                        .strokeBorder(.black, lineWidth: 2 * layout.scale)
                                }
                            }
                            .position(x: camera.midX, y: camera.midY)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Camera preview")
                            .accessibilityHint("Live timelapse camera feed")
                            .accessibilityValue(
                                AccessibilitySupport.cameraPreviewValue(
                                    isRecording: sessionRecording.isRecording,
                                    isPaused: hasStarted && !sessionTimer.isRunning,
                                    frameCount: sessionRecording.capturedFrameCount,
                                    remainingHours: sessionTimer.hours,
                                    remainingMinutes: sessionTimer.minutes,
                                    remainingSeconds: sessionTimer.seconds
                                )
                            )
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    .animation(focusTransition, value: isExpanded)
                }
                .ignoresSafeArea()
            }

            RecordingControls(
                hours: sessionTimer.hours,
                minutes: sessionTimer.minutes,
                seconds: sessionTimer.seconds,
                hasStarted: hasStarted,
                isRunning: sessionTimer.isRunning,
                isExpanded: isExpanded,
                isTransitioning: isPauseResumeTransitioning,
                onEnd: { withAnimation(.easeInOut(duration: 0.2)) { showEndConfirm = true } },
                onPauseResume: togglePauseResume,
                onToggleExpanded: { withAnimation(focusTransition) { isExpanded.toggle() } }
            )
            .animation(focusTransition, value: isExpanded)

            if sessionRecording.isExporting {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .accessibilityDecorative()
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                    Text("Saving your video...")
                        .font(.custom("Special Gothic Expanded One", size: 16))
                        .foregroundColor(.white)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Saving your video")
                .accessibilityAddTraits(.updatesFrequently)
            }

            if sessionRecording.permissionDenied {
                VStack(spacing: 12) {
                    Text("Camera access is required to record your timelapse.")
                        .font(.system(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.7))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Camera access required")
                .accessibilityValue("Camera access is required to record your timelapse. Enable camera in Settings.")
            }

            if showEndConfirm {
                EndSessionConfirm(
                    onEnd: {
                        showEndConfirm = false
                        endSessionEarly()
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) { showEndConfirm = false }
                    }
                )
                .transition(.opacity)
                .zIndex(20)
                .accessibilityAddTraits(.isModal)
            }

            // Always mounted so it can run its own slide and emoji animations both ways.
            ResumeSessionReminder(
                isPresented: isResumeReminderVisible,
                onContinue: continueFromReminder,
                onEnd: {
                    showResumeReminder = false
                    endSessionEarly()
                },
                onDismiss: { showResumeReminder = false }
            )
            .zIndex(20)
        }
        // The embedded camera belongs to HomePage, so include the transparent gaps
        // between our controls in hit testing as well as the controls themselves.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityAnnounce(when: sessionRecording.isExporting, message: "Saving your video")
        .accessibilityAnnounce(when: isResumeReminderVisible, message: "Session paused. Continue recording or end your session.")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in ScreenDimmer.touch() }
                .onEnded { _ in ScreenDimmer.touch() }
        )
        .onChange(of: shouldDimScreen) { _, dim in
            ScreenDimmer.setActive(dim)
        }
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)   // recording is a full-screen mode — keep the tab bar on the home page only
        #endif
        // jailbreak: in-app "App Unlocked" card that shrinks up into the Dynamic Island,
        // plus the "one break at a time" warning — both styled after the figma cards.
        .overlay {
            #if os(iOS)
            if let u = unlock {
                FocusAlertCard(
                    title: "App Unlocked",
                    message: "The selected app is now available for \(u.timeText)",
                    autoDismiss: true,
                    onDismiss: { unlock = nil }
                )
                .id(u.id)
            } else if let b = breakBlockedInfo {
                FocusAlertCard(
                    title: "One break at a time",
                    message: "An app is already unlocked. You can unlock another app after returning to your focus session.",
                    onDismiss: { breakBlockedInfo = nil }
                )
                .id(b.id)
            }
            #endif
        }
        .onAppear {
            recLog("onAppear embedded=\(embedded) autoStart=\(autoStart) cameraReady=\(sessionRecording.cameraReady) hasStarted=\(hasStarted)")
            if !embedded { sessionRecording.prepareCamera() }
            if autoStart { beginSession() }   // camera may already be ready (prepared on Home)
            ScreenDimmer.setActive(shouldDimScreen)   // re-arm if we return mid-session
            checkPendingEvents()
            // The shield return relies on a tappable notification. Request it HERE (a stable
            // screen) — the splash-time request gets cancelled before the user can respond,
            // leaving the app unregistered (not even listed in Settings → Notifications). Then
            // nudge to Settings if it's been denied.
            Task {
                await NotificationPermission.requestIfNeeded()
                if await NotificationPermission.isDenied() { showNotifNudge = true }
            }
        }
        .onChange(of: sessionRecording.cameraReady) { _, ready in
            recLog("cameraReady changed ready=\(ready) autoStart=\(autoStart) hasStarted=\(hasStarted)")
            if autoStart, ready { beginSession() }   // start once the camera finishes warming up
        }
        .onReceive(NotificationCenter.default.publisher(for: .shieldReturnTapped).receive(on: DispatchQueue.main)) { _ in
            checkPendingEvents()   // shield-return notification received/tapped → surface the prompt
        }
        .alert("Turn on notifications", isPresented: $showNotifNudge) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("Rush Hour sends a quick notification to bring you back here when you tap “Break It” or “Back to Session” on the block screen. Tap that notification to return — without notifications on, it can fail.")
        }
        .onDisappear {
            ScreenDimmer.release()   // never leave the user's screen dim outside the session
            if !sessionRecording.isExporting, !sessionRecording.isRecording {
                ScreenWakeLock.release()
            }
            // Embedded: HomePage owns the shared camera and keeps it running for the home
            // preview, so don't tear it down here.
            if !embedded, !sessionRecording.isExporting {
                sessionRecording.stopCamera()
            }
            #if os(iOS)
            // Leaving the session screen (swipe-back / pop) ends the session — stop the timer
            // AND lift the shield. The normal end flow already does both; this covers the
            // swipe-back path that otherwise left the timer ticking + every app blocked.
            if hasStarted {
                sessionTimer.pause()
                focusController.release()
            }
            SessionNotifications.cancelAwayNudges()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            recLog("scenePhase=\(phase) hasStarted=\(hasStarted) timerRunning=\(sessionTimer.isRunning) recording=\(sessionRecording.isRecording) exporting=\(sessionRecording.isExporting)")
            switch phase {
            case .active:
                if hasStarted, sessionTimer.isRunning {
                    sessionRecording.recoverCameraAfterInterruption()
                } else if hasStarted {
                    recLog("scenePhase active skipped camera recovery because session is paused")
                }
                if sessionRecording.isRecording || sessionRecording.isExporting {
                    ScreenWakeLock.setActive(true)
                }
                checkPendingEvents()   // jailbreak: pick up a break taken on the shield
                if leftAppMidSession {
                    leftAppMidSession = false
                    presentResumeReminderIfNeeded()   // after checkPendingEvents, so a break prompt wins
                }
                UNUserNotificationCenter.current().removeDeliveredNotifications(
                    withIdentifiers: ["rushhour.shieldreturn", "rushhour.shieldreason"]
                )
                SessionNotifications.cancelAwayNudges()   // they're back — drop the "still there?" pings
                // notifications ARE the return path now — re-nudge if they got denied mid-session
                Task { if await NotificationPermission.isDenied() { showNotifNudge = true } }
            case .background:
                isPauseResumeTransitioning = false
                let wasRunning = sessionTimer.isRunning
                let shouldNudgeAway = hasStarted && sessionRecording.isRecording && wasRunning
                // left the app → pause the session instead of letting it silently freeze and
                // auto-resume; the button flips to RESUME so you pick back up deliberately
                if hasStarted {
                    leftAppMidSession = true
                    if wasRunning {
                        pauseLiveSession(reason: "background")
                    } else {
                        recLog("scenePhase background left while already paused")
                    }
                    // The capture writer can't survive suspension — finalize the current
                    // segment now (running OR already paused, incl. the Screen-Time redirect)
                    // so footage isn't lost; a fresh segment opens on resume.
                    sessionRecording.prepareForBackground()
                }
                #if os(iOS)
                // away from a paused session (and not on a break) → ping them to come back
                if shouldNudgeAway && focusController.activeBreaks.isEmpty {
                    SessionNotifications.scheduleAwayNudges()
                } else if !shouldNudgeAway {
                    SessionNotifications.cancelAwayNudges()
                }
                #endif
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: sessionTimer.showFinishSession) { _, show in
            if show {
                sessionTimer.showFinishSession = false
                finalizeRecording {
                    showFinishSessionFlow = true
                }
                SessionNotifications.cancelAwayNudges()
                #if os(iOS)
                focusController.release()   // timer hit 00:00 — lift the shield + tear down the break Live Activity now, not after the recap
                #endif
            }
        }
        .onChange(of: sessionTimer.requestReturnToHome) { _, shouldReturn in
            guard shouldReturn else { return }
            sessionTimer.requestReturnToHome = false
            exitToHomeFromSessionFlow()
        }

        .fullScreenCover(isPresented: $showFinishSessionFlow) {
            FinishSessionScreen(onFlowComplete: completeSessionFlow)
        }
        .fullScreenCover(isPresented: $showCrashSession) {
            CrashSessionScreen(onFlowComplete: completeSessionFlow)
        }
        // jailbreak: reason sheet over the recording when a break was taken on the shield
        .sheet(item: $pendingPrompt) { prompt in
            ReasonFormView(
                appName: prompt.distraction.appOpened.isEmpty ? "this app" : prompt.distraction.appOpened,
                onSubmit: { takeBreak($0, for: prompt) },
                onCancel: { cancelBreak(for: prompt) }
            )
            .onAppear(perform: cancelShieldFallbackNotifications)
            .alert("Could not save your reason", isPresented: $showBreakSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The app is still blocked. Please try submitting your reason again.")
            }
            .presentationDetents([.large])
            .presentationCornerRadius(40)
            .presentationDragIndicator(.visible)
            .presentationBackground {
                LinearGradient(
                    colors: [Color(red: 0x00/255.0, green: 0x32/255.0, blue: 0x61/255.0),
                             Color(red: 0x0B/255.0, green: 0x1F/255.0, blue: 0x32/255.0)],
                    startPoint: .top, endPoint: .bottom
                )
                .overlay {
                    Image("ReasonSheetBg")
                        .resizable()
                        .scaledToFill()
                        .blendMode(.overlay)
                }
            }
            // sheet stays put until they actually submit or cancel — no swipe-away
            .interactiveDismissDisabled()
        }
    }

    private func takeBreak(_ reason: String, for prompt: PendingPrompt) {
        guard pendingPrompt?.id == prompt.id, !prompt.distraction.reasonSubmitted else { return }
        guard saveBreakReason(reason, for: prompt.distraction) else { return }
        #if os(iOS)
        checkPendingEvents()   // consume repeat shield requests while this prompt still owns the break
        focusController.grantBreak(for: prompt.distraction)
        let secs = Int(FocusViewModel.breakDuration)
        unlock = UnlockInfo(timeText: String(format: "%d:%02d", secs / 60, secs % 60))
        #endif
        try? modelContext.save()
        pendingPrompt = nil
        showResumeReminder = false   // they chose a break, so staying paused is deliberate
    }

    private func saveBreakReason(_ reason: String, for distraction: Distraction) -> Bool {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return false }
        distraction.reason = reason
        distraction.reasonSubmitted = true
        do {
            try modelContext.save()
        } catch {
            distraction.reasonSubmitted = false
            showBreakSaveError = true
            return false
        }
        return true
    }

    private func cancelBreak(for prompt: PendingPrompt) {
        guard pendingPrompt?.id == prompt.id, !prompt.distraction.reasonSubmitted else { return }
        pendingPrompt = nil

        #if os(iOS)
        if focusController.activeBreaks.contains(where: { $0.id == prompt.distraction.id }) {
            focusController.endBreakEarly(for: prompt.distraction)
        }
        #endif

        modelContext.delete(prompt.distraction)
        try? modelContext.save()
    }

    // jailbreak: a break was taken on the shield → record it and prompt for a reason
    private func checkPendingEvents() {
        #if os(iOS)
        guard focusController.isEngaged, breakBlockedInfo == nil, unlock == nil else { return }
        guard let pair = SharedJailbreakStore.nextUnhandledBreak() else { return }
        if pendingPrompt != nil {
            SharedJailbreakStore.markBreakHandled(pair.action.occurredAt)
            return
        }

        // one break at a time: if an app is already unlocked, reject this new break —
        // keep the active break running, warn the user, and skip the reason form.
        if focusController.activeBreaks.contains(where: { focusController.remainingSeconds(for: $0) > 0 }) {
            breakBlockedInfo = BreakBlockedInfo()
            SharedJailbreakStore.markBreakHandled(pair.action.occurredAt)   // consume so it won't re-prompt
            return
        }

        let tokenData = pair.action.tokenData ?? pair.config?.tokenData
        let displayName = pair.config?.displayName
            ?? pair.action.displayName
            ?? SharedJailbreakStore.lastShieldedAppName()
            ?? ""
        let bundleId = pair.config?.bundleId
            ?? pair.action.bundleId
            ?? SharedJailbreakStore.lastShieldedBundleId()

        let distraction = Distraction(
            sessionId: sessionTimer.sessionId,
            appOpened: displayName,
            startTime: pair.config?.occurredAt ?? pair.action.occurredAt,
            tokenData: tokenData,
            appBundleId: bundleId,
            appDisplayName: displayName.isEmpty ? nil : displayName,
            sourceKind: "shieldAction",
            actionTaken: "break"
        )
        modelContext.insert(distraction)
        try? modelContext.save()

        // resolve the real app name now, while foregrounded on the reason screen, so it's ready
        // before the Live Activity starts (otherwise the async lookup is cut off when you leave)
        focusController.prefetchDisplayName(for: distraction)

        SharedJailbreakStore.markBreakHandled(pair.action.occurredAt)
        pendingPrompt = PendingPrompt(
            distraction: distraction,
            tokenDataToClear: tokenData
        )
        #endif
    }

    // .openParentalControlsApp is the primary shield→app return; the shield also queued
    // a delayed notification as a fallback. We're back in the app now, so drop it.
    private func cancelShieldFallbackNotifications() {
        // The reason sheet is visible, so the delayed return fallback is no longer needed.
        let ids = ["rushhour.shieldreturn", "rushhour.shieldreason"]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    // stamp endTime on any break still open this session, so the distracted time is recorded
    private func closeOpenDistractions() {
        let sid = sessionTimer.sessionId
        let descriptor = FetchDescriptor<Distraction>(
            predicate: #Predicate { $0.sessionId == sid }
        )
        if let all = try? modelContext.fetch(descriptor) {
            for d in all where d.endTime == nil { d.endTime = .now }
            try? modelContext.save()
        }
    }

    private func completeSessionFlow() {
        exitToHomeFromSessionFlow()
        NotificationCenter.default.post(name: .returnToMySessionsTab, object: nil)
    }

    private func exitToHomeFromSessionFlow() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showFinishSessionFlow = false
            showCrashSession = false
            isExpanded = false
            sessionTimer.showFinishSession = false
        }
        hasStarted = false
        isStartingSession = false
        isPauseResumeTransitioning = false
        showResumeReminder = false
        leftAppMidSession = false
        sessionTimer.pause()
        SessionNotifications.cancelAwayNudges()
        // Embedded: keep the shared camera running so it flows straight back into the
        // home preview as the frame shrinks; standalone: tear it down.
        if !embedded { sessionRecording.stopCamera() }
        sessionRecording.resetForNewSession()
        #if os(iOS)
        closeOpenDistractions()
        focusController.release()   // jailbreak: unblock everything when the session ends
        #endif
        if let onExit { onExit() } else { dismiss() }
    }

    // Begins the focus session: starts the timelapse capture, the countdown, and
    // (on iOS) the app shield. Used by both the on-screen START button and the
    // auto-start path when arriving from the home record button.
    private func beginSession() {
        recLog("beginSession requested hasStarted=\(hasStarted) starting=\(isStartingSession) cameraReady=\(sessionRecording.cameraReady)")
        guard !hasStarted, !isStartingSession, sessionRecording.cameraReady else { return }
        isStartingSession = true
        sessionRecording.startRecording(
            plannedSessionSeconds: TimeInterval(sessionTimer.configuredTotalSeconds)
        ) { started in
            recLog("beginSession startRecording callback started=\(started)")
            isStartingSession = false
            guard started else {
                SessionNotifications.cancelAwayNudges()
                return
            }

            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                hasStarted = true
                sessionTimer.start()
                #if os(iOS)
                focusController.engage()   // jailbreak: apply the shield
                #endif
            }
        }
    }

    // Center control: pause a running session or resume a paused one.
    private func togglePauseResume() {
        recLog("togglePauseResume hasStarted=\(hasStarted) timerRunning=\(sessionTimer.isRunning) recording=\(sessionRecording.isRecording) transitioning=\(isPauseResumeTransitioning)")
        guard hasStarted else { beginSession(); return }
        guard !isPauseResumeTransitioning, sessionRecording.isRecording else { return }
        isPauseResumeTransitioning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isPauseResumeTransitioning = false
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if sessionTimer.isRunning {
                pauseLiveSession(reason: "manual")
            } else {
                resumeLiveSession(reason: "manual")
            }
        }
    }

    private func pauseLiveSession(reason: String) {
        recLog("pauseLiveSession reason=\(reason) timerRunning=\(sessionTimer.isRunning) capturePaused=\(sessionRecording.isCapturePaused)")
        guard hasStarted else { return }
        let wasRunning = sessionTimer.isRunning
        if wasRunning {
            sessionTimer.pause()
        }
        if wasRunning || !sessionRecording.isCapturePaused {
            sessionRecording.pauseRecording(reason: reason)
        }
    }

    private func resumeLiveSession(reason: String) {
        recLog("resumeLiveSession reason=\(reason) recording=\(sessionRecording.isRecording) capturePaused=\(sessionRecording.isCapturePaused)")
        guard hasStarted, sessionRecording.isRecording else { return }
        sessionTimer.start()
        sessionRecording.resumeRecording(reason: reason)
        #if os(iOS)
        focusController.resume()
        #endif
    }

    // Back in the app with the session still paused → remind them to continue or end it.
    private func presentResumeReminderIfNeeded() {
        guard hasStarted,
              sessionRecording.isRecording,
              !sessionTimer.isRunning,
              !sessionRecording.isExporting,
              !showFinishSessionFlow,
              !showCrashSession else { return }
        recLog("presentResumeReminder")
        withAnimation(.easeInOut(duration: 0.2)) {
            showEndConfirm = false   // the reminder offers END as well
            showResumeReminder = true
        }
    }

    private func continueFromReminder() {
        showResumeReminder = false
        guard !sessionTimer.isRunning else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            resumeLiveSession(reason: "return reminder")
        }
    }

    private func endSessionEarly() {
        recLog("endSessionEarly")
        SessionNotifications.cancelAwayNudges()
        sessionTimer.end()
        #if os(iOS)
        focusController.release()   // lift the shield the moment they end, not after the recap
        #endif
        finalizeRecording {
            showCrashSession = true
        }
    }

    private func finalizeRecording(completion: @escaping () -> Void = {}) {
        recLog("finalizeRecording hasStarted=\(hasStarted) elapsed=\(sessionTimer.elapsedSeconds) recording=\(sessionRecording.isRecording)")
        guard hasStarted else {
            completion()
            return
        }
        let wallClock = TimeInterval(sessionTimer.elapsedSeconds)
        sessionRecording.stopRecordingAndExport(wallClockSeconds: wallClock, completion: completion)
    }

    private func recLog(_ message: String) {
        RecordingDiagnostics.log("RecordingPage \(message)")
    }
}


// MARK: - End Session confirmation

struct EndSessionConfirm: View {
    let onEnd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        SessionConfirmSheet(
            title: "End Session",
            message: "Ending now will stop recording\nand end your session early",
            confirmTitle: "END",
            confirmAccessibilityLabel: "End session now",
            confirmHint: "Stops recording and ends your session early",
            confirmInputLabels: ["end", "confirm end", "stop session"],
            cancelHint: "Continues your current session",
            closeHint: "Cancels ending the session",
            onConfirm: onEnd,
            onCancel: onCancel
        )
    }
}

// MARK: - Resume reminder

/// Bottom sheet shown when the user comes back to the app and the session is still
/// paused, so they don't forget to resume. It stays mounted and slides itself in and
/// out with `isPresented`; the emoji pop up from behind its top edge once it lands.
/// Swiping it down or tapping outside keeps the session paused.
struct ResumeSessionReminder: View {
    let isPresented: Bool
    let onContinue: () -> Void
    let onEnd: () -> Void
    let onDismiss: () -> Void

    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.35, dampingFraction: 0.85)))
    private var dragOffset: CGFloat = 0
    @State private var sheetHeight: CGFloat = 400
    @State private var emojisRaised = false

    private let sheetShape = UnevenRoundedRectangle(
        topLeadingRadius: 36,
        topTrailingRadius: 36,
        style: .continuous
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                // The design has no dim, but a tap outside the sheet still dismisses it.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)
            }

            sheet
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
                // Hidden = pushed below the screen, far enough to take the emoji with it.
                .offset(y: isPresented ? dragOffset : sheetHeight + 200)
                .animation(.spring(response: 0.45, dampingFraction: 0.88), value: isPresented)
                .gesture(dismissDrag)
                .allowsHitTesting(isPresented)
                .accessibilityHidden(!isPresented)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear { emojisRaised = isPresented }
        .onChange(of: isPresented) { _, presented in emojisRaised = presented }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.6))
                .frame(width: 54, height: 5)
                .padding(.top, 14)
                .accessibilityHidden(true)

            Text("Continue session?")
                .font(.custom("Special Gothic Expanded One", size: 22))
                .foregroundStyle(.white)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 12) {
                endButton
                continueButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            sheetShape
                .fill(Color("CanvasBlue"))
                .overlay(alignment: .top) {
                    Image("PatternBackgroundSmall")
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(sheetShape)
                .ignoresSafeArea(edges: .bottom)
        }
        // Behind the sheet, so its top edge tucks away the bottom of the emoji.
        .background(alignment: .top) {
            emojiRow
                .alignmentGuide(.top) { $0[.bottom] - 22 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
    }

    // ✍️ 👩‍💻 👀 peeking over the sheet. While hidden they sit below its top edge, then
    // spring up one after another as it lands.
    private var emojiRow: some View {
        ZStack(alignment: .bottom) {
            peeking(
                Text("👩‍💻")
                    .font(.system(size: 104))
                    .offset(y: -6),
                delay: 0.28
            )

            peeking(
                Text("✍️")
                    .font(.system(size: 66))
                    .scaleEffect(x: -1, y: 1)   // mirrored so the pen points away from the laptop
                    .rotationEffect(.degrees(-35))
                    .offset(x: -84, y: -14),
                delay: 0.22
            )

            peeking(
                Text("👀")
                    .font(.system(size: 92))
                    .offset(x: 86),
                delay: 0.34
            )
        }
        .accessibilityHidden(true)
    }

    private func peeking(_ emoji: some View, delay: Double) -> some View {
        emoji
            .offset(y: emojisRaised ? 0 : 120)
            .animation(
                emojisRaised
                    ? .spring(response: 0.5, dampingFraction: 0.6).delay(delay)
                    : .easeIn(duration: 0.15),
                value: emojisRaised
            )
    }

    private var dismissDrag: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                state = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 80 || value.predictedEndTranslation.height > 220 {
                    onDismiss()
                }
            }
    }

    private var endButton: some View {
        Button(action: onEnd) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .frame(width: 13, height: 13)
                Text("END")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.custom("Special Gothic Expanded One", size: 14))
            .foregroundStyle(Color("ButtonRed"))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(Color("ButtonRed"), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End session")
        .accessibilityHint("Stops recording and ends your session early")
        .accessibilityInputLabels(["end", "end session", "stop session"])
    }

    private var continueButton: some View {
        Button(action: onContinue) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("CONTINUE")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.custom("Special Gothic Expanded One", size: 14))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color(white: 0.17), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue session")
        .accessibilityHint("Resumes the timer and timelapse recording")
        .accessibilityInputLabels(["continue", "resume", "resume session", "keep going"])
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.setSession(session)
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.setSession(session)
    }
}


// MARK: - Preview UIView

class PreviewView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    private var connectionObservation: NSKeyValueObservation?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var lastOrientationLog: String?
    private static let blurContext = CIContext(options: [.useSoftwareRenderer: false])

    private var switchCover: UIView?
    private var switchCovered = false
    private var switchCoverGeneration = 0
    private var switchCoverStarted = Date()

    func setSession(_ session: AVCaptureSession) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        updateOrientation()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        connectionObservation = previewLayer.observe(\.connection, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            if Thread.isMainThread {
                self.updateOrientation()
            } else {
                DispatchQueue.main.async { [weak self] in self?.updateOrientation() }
            }
        }
        for name in [AVCaptureSession.didStartRunningNotification,
                     AVCaptureSession.interruptionEndedNotification,
                     UIApplication.didBecomeActiveNotification,
                     .cameraSwitchWillBegin,
                     .cameraConfigurationDidChange] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(cameraConnectionChanged(_:)), name: name, object: nil
            )
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        switchCover?.removeFromSuperview()
    }

    @objc private func cameraConnectionChanged(_ notification: Notification) {
        // Session notifications can arrive on its background queue. Resolve the current
        // connection on the main thread, rather than retaining a replaced connection.
        // The switch cover has to run synchronously: deferring it lets the new camera
        // draw a landscape frame before the snapshot is up.
        if Thread.isMainThread {
            handleCameraConnectionChange(notification)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.handleCameraConnectionChange(notification)
            }
        }
    }

    private func handleCameraConnectionChange(_ notification: Notification) {
        if notification.name != UIApplication.didBecomeActiveNotification {
            guard let session = notification.object as? AVCaptureSession,
                  session === previewLayer.session else { return }
        }
        if notification.name == .cameraSwitchWillBegin {
            coverForCameraSwitch()
            return
        }
        updateOrientation()
        if notification.name == .cameraConfigurationDidChange {
            revealAfterCameraSwitch()
        }
    }

    func updateOrientation() {
        guard window != nil,
              let port = previewLayer.connection?.inputPorts.first(where: { $0.mediaType == .video }),
              let input = port.input as? AVCaptureDeviceInput else { return }
        let device = input.device
        if rotationCoordinator?.device !== device {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotationCoordinator = coordinator
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
                if Thread.isMainThread {
                    self?.updateOrientation()
                } else {
                    DispatchQueue.main.async { [weak self] in self?.updateOrientation() }
                }
            }
        }
        guard let coordinator = rotationCoordinator else { return }
        let angle = VideoOrientationHelper.uprightPreviewAngle(from: coordinator)
        applyPreviewRotation(angle, mirrored: device.position == .front)
    }

    private func applyPreviewRotation(_ angle: CGFloat, mirrored: Bool) {
        guard let connection = previewLayer.connection else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        VideoOrientationHelper.configurePortraitPreview(connection, rotationAngle: angle, mirrored: mirrored)
        CATransaction.commit()
        let state = "preview camera angle=\(connection.videoRotationAngle) mirrored=\(connection.isVideoMirrored)"
        if state != lastOrientationLog {
            RecordingDiagnostics.log(state)
            lastOrientationLog = state
        }
    }

    private func coverForCameraSwitch() {
        switchCoverGeneration += 1
        switchCovered = true
        switchCoverStarted = Date()
        let generation = switchCoverGeneration
        switchCover?.removeFromSuperview()
        switchCover = nil

        // Freeze the current upright frame before the session swaps cameras.
        // The live preview rotates sideways for a moment; hiding it keeps that
        // turn out of the blur.
        let still = blurredSwitchImage()
        guard let host = superview, bounds.width > 1, bounds.height > 1 else { return }
        let cover = UIImageView(image: still)
        cover.frame = host.convert(bounds, from: self)
        cover.clipsToBounds = true
        cover.contentMode = .scaleAspectFill
        cover.isUserInteractionEnabled = false
        if still == nil {
            let frost = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
            frost.frame = cover.bounds
            frost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            frost.isUserInteractionEnabled = false
            cover.addSubview(frost)
        }
        host.addSubview(cover)
        switchCover = cover

        guard still != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.opacity = 0
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.switchCovered, self.switchCoverGeneration == generation else { return }
            self.revealAfterCameraSwitch()
        }
    }

    private func blurredSwitchImage() -> UIImage? {
        guard let session = previewLayer.session,
              let cgImage = PreviewFrameStore.shared.image(for: session) else { return nil }
        let angle = previewLayer.connection?.videoRotationAngle ?? 0
        let mirrored = previewLayer.connection?.isVideoMirrored ?? false
        var image = CIImage(cgImage: cgImage)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.midX, y: -image.extent.midY))
        if abs(angle) > 0.5 {
            image = image.transformed(by: CGAffineTransform(rotationAngle: -angle * .pi / 180))
        }
        if mirrored {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
        let blurred = image
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 14)
            .cropped(to: image.extent)
        guard let output = Self.blurContext.createCGImage(blurred, from: image.extent) else { return nil }
        return UIImage(cgImage: output)
    }

    private func revealAfterCameraSwitch() {
        guard switchCovered else { return }
        switchCovered = false
        let generation = switchCoverGeneration
        updateOrientation()
        let elapsed = Date().timeIntervalSince(switchCoverStarted)
        let hold = max(0.12, 0.55 - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self, self.switchCoverGeneration == generation else { return }
            self.updateOrientation()
            let cover = self.switchCover
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.previewLayer.opacity = 1
            CATransaction.commit()
            UIView.animate(
                withDuration: 0.4,
                delay: 0,
                options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]
            ) {
                cover?.alpha = 0
            } completion: { _ in
                guard self.switchCoverGeneration == generation else { return }
                cover?.removeFromSuperview()
                if let cover, self.switchCover === cover {
                    self.switchCover = nil
                }
                self.previewLayer.opacity = 1
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateOrientation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        if let switchCover, let host = switchCover.superview {
            switchCover.frame = host.convert(bounds, from: self)
        }
        updateOrientation()
    }
}


#Preview {
    RecordingPage(isExpanded: .constant(false))
        .environmentObject(SessionTimerViewModel())
        .environmentObject(SessionRecordingViewModel())
        .environmentObject(FocusViewModel())
        .modelContainer(for: [Session.self, Distraction.self], inMemory: true)
}
