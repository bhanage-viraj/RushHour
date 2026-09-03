//
//  RecordingPage.swift
//  lucky7
//

import SwiftUI
import SwiftData
import AVFoundation
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
            && !showFinishSessionFlow
            && !showCrashSession
            && !showNotifNudge
            && pendingPrompt == nil
            && unlock == nil
            && breakBlockedInfo == nil
            && !sessionRecording.isExporting
            && scenePhase == .active
    }

    // jailbreak: distraction prompt + in-app unlock card + records sheet
    @State private var pendingPrompt: PendingPrompt?
    @State private var unlock: UnlockInfo?
    @State private var breakBlockedInfo: BreakBlockedInfo?

    struct PendingPrompt: Identifiable {
        let id = UUID()
        let distraction: Distraction
        let actionOccurredAt: Date
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

            // Expanded background — full-focus mode. Standalone only; when embedded,
            // HomePage draws the session background beneath its shared camera.
            if !embedded {
                RecordingBackground()
                    .opacity(isExpanded ? 1 : 0)
                    .animation(focusTransition, value: isExpanded)
            }

            // Camera preview — STANDALONE ONLY. Morphs between full-screen fill and the
            // focus circle. When embedded, HomePage owns the single shared preview layer
            // and morphs it into the circle itself, so we draw no camera here.
            if !embedded {
                GeometryReader { geo in
                    let circleSize: CGFloat = 164
                    let cameraW: CGFloat = isExpanded ? circleSize : geo.size.width
                    let cameraH: CGFloat = isExpanded ? circleSize : geo.size.height
                    let camCenterY: CGFloat = isExpanded
                        ? geo.safeAreaInsets.top + 168
                        : geo.size.height / 2

                    ZStack {
                        // Drop-shadow behind the camera circle (expanded only)
                        Circle()
                            .fill(Color.black)
                            .frame(width: circleSize, height: circleSize)
                            .position(x: geo.size.width / 2, y: camCenterY + 10)
                            .opacity(isExpanded ? 1 : 0)

                        CameraPreview(session: sessionRecording.captureSession)
                            .frame(width: cameraW, height: cameraH)
                            .clipShape(RoundedRectangle(cornerRadius: isExpanded ? circleSize / 2 : 0))
                            .position(x: geo.size.width / 2, y: camCenterY)
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

            VStack {
                // COUNTDOWN — live remaining time in the traffic housing, with a soft
                // rainbow glow BEHIND it (peeking out just below) while paused.
                ZStack {
                    if hasStarted && !sessionTimer.isRunning {
                        Image("RainbowEffect")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 240, height: 46)
                            .blur(radius: 14)
                            .opacity(0.85)
                            .offset(y: 28)
                            .allowsHitTesting(false)
                            .accessibilityDecorative()
                            .transition(.opacity)
                    }

                    RecordingTrafficTimer(
                        hours: sessionTimer.hours,
                        minutes: sessionTimer.minutes,
                        seconds: sessionTimer.seconds
                    )
                }
                .padding(.top, 8)

                Spacer()

                // CONTROL BAR — stop · pause/resume · expand
                HStack {
                    // STOP — ask before ending the session early
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showEndConfirm = true } }) {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 60, height: 60)
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.red)
                                    .frame(width: 22, height: 22)
                            }
                    }
                    .accessibilityLabel("End session")
                    .accessibilityHint("Stops recording and ends your focus session early")
                    .accessibilityInputLabels(["stop", "end session", "stop recording", "end timelapse"])

                    Spacer()

                    // PAUSE / RESUME
                    Button(action: togglePauseResume) {
                        Circle()
                            .fill(.white)
                            .frame(width: 82, height: 82)
                            .overlay {
                                Image(systemName: sessionTimer.isRunning ? "pause.fill" : "play.fill")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(.black)
                            }
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    }
                    .accessibilityLabel(sessionTimer.isRunning ? "Pause session" : "Resume session")
                    .accessibilityHint(sessionTimer.isRunning ? "Pauses the timer and timelapse recording" : "Resumes the timer and timelapse recording")
                    .accessibilityInputLabels(sessionTimer.isRunning
                        ? ["pause", "pause session", "pause recording"]
                        : ["resume", "play", "resume session", "continue recording"])
                    .disabled(isPauseResumeTransitioning)
                    .opacity(isPauseResumeTransitioning ? 0.65 : 1)

                    Spacer()

                    // EXPAND — fullscreen focus view
                    // EXPAND — full-focus view (same camera, different chrome)
                    Button(action: { withAnimation(focusTransition) { isExpanded = true } }) {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 60, height: 60)
                            .overlay {
                                Image(systemName: "arrow.down.right.and.arrow.up.left")
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                    }
                    .accessibilityLabel("Enter full focus mode")
                    .accessibilityHint("Shows a larger timer with fewer distractions")
                    .accessibilityInputLabels(["expand", "full focus", "focus mode", "fullscreen"])
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 24)
            }
            .opacity(isExpanded ? 0 : 1)
            .scaleEffect(isExpanded ? 0.98 : 1)
            .blur(radius: isExpanded ? 5 : 0)
            .animation(focusTransition, value: isExpanded)
            .allowsHitTesting(!isExpanded)

            // ── Expanded (full-focus) overlay ─────────────────
            expandedSessionOverlay
                .opacity(isExpanded ? 1 : 0)
                .scaleEffect(isExpanded ? 1 : 1.02)
                .blur(radius: isExpanded ? 0 : 5)
                .animation(focusTransition, value: isExpanded)
                .allowsHitTesting(isExpanded)

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

            VStack {
                if hasStarted {
                    HStack(spacing: 7) {
                        if sessionTimer.isRunning {
                            Circle()
                                .fill(.white)
                                .frame(width: 8, height: 8)
                            Text("Recording")
                        } else {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Paused")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(sessionTimer.isRunning ? Color.red : Color(white: 0.26), in: Capsule())
                    .animation(.easeInOut(duration: 0.2), value: sessionTimer.isRunning)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(sessionTimer.isRunning ? "Recording in progress" : "Recording paused")
                    .accessibilityValue(
                        "\(sessionRecording.capturedFrameCount) frames captured. \(AccessibilitySupport.spokenCountdown(hours: sessionTimer.hours, minutes: sessionTimer.minutes, seconds: sessionTimer.seconds))"
                    )
                    .accessibilityAddTraits(.updatesFrequently)
                }

                Spacer()
            }
            .padding(.top, 132)   // floating recording/paused indicator below the housing
            .opacity(isExpanded ? 0 : 1)
            .scaleEffect(isExpanded ? 0.98 : 1)
            .blur(radius: isExpanded ? 5 : 0)
            .animation(focusTransition, value: isExpanded)

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
        }
        // The embedded camera belongs to HomePage, so include the transparent gaps
        // between our controls in hit testing as well as the controls themselves.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityAnnounce(when: sessionRecording.isExporting, message: "Saving your video")
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
        .onReceive(NotificationCenter.default.publisher(for: .shieldReturnTapped)) { _ in
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
                cancelShieldFallbackNotifications()   // clear delivered shield notifications
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
            FinishSessionScreen(onFlowComplete: exitToHomeFromSessionFlow)
        }
        .fullScreenCover(isPresented: $showCrashSession) {
            CrashSessionScreen(onFlowComplete: exitToHomeFromSessionFlow)
        }
        // jailbreak: reason sheet over the recording when a break was taken on the shield
        .sheet(item: $pendingPrompt) { prompt in
            ReasonFormView(
                appName: prompt.distraction.appOpened.isEmpty ? "this app" : prompt.distraction.appOpened,
                onSubmit: { takeBreak($0, for: prompt) },
                onCancel: { cancelBreak(for: prompt) }
            )
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

    // MARK: - Expanded (full-focus) overlay

    @ViewBuilder
    private var expandedSessionOverlay: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 24)

            // Paused badge (top-left)
            HStack {
                Text("PAUSED")
                    .foregroundStyle(.white)
                    .font(.system(size: 14))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(.canvasRed))
                    )
                    .opacity(sessionTimer.isRunning ? 0 : 1)
                    .accessibilityHidden(sessionTimer.isRunning)
                    .accessibilityLabel("Paused")
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 12)

            Color.clear.frame(height: 40)

            // Space for the camera circle (rendered in the camera layer)
            Color.clear.frame(height: 164)

            // Traffic-light timer
            ZStack(alignment: .center) {
                if !sessionTimer.isRunning {
                    Image(.redYellowGreen)
                        .frame(height: 136)
                        .accessibilityDecorative()
                }

                Image(.trafficLight)
                    .accessibilityDecorative()

                HStack {
                    Text("\(sessionTimer.hours)")
                        .font(.custom("Special Gothic Expanded One", size: 34))
                        .frame(width: 104, height: 102)

                    Text(String(format: "%02d", sessionTimer.minutes))
                        .font(.custom("Special Gothic Expanded One", size: 34))
                        .frame(width: 104, height: 102)

                    Text(String(format: "%02d", sessionTimer.seconds))
                        .font(.custom("Special Gothic Expanded One", size: 34))
                        .frame(width: 110, height: 102)
                        .clipped()
                }
                .foregroundStyle(.white)
                .frame(height: 136)
                .zIndex(2.0)
                .offset(y: -8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time remaining")
            .accessibilityValue(AccessibilitySupport.spokenCountdown(
                hours: sessionTimer.hours,
                minutes: sessionTimer.minutes,
                seconds: sessionTimer.seconds
            ))
            .accessibilityAddTraits(.updatesFrequently)
            .padding(.top, 36)

            Spacer()

            VStack(alignment: .center) {
                Text("Tips:")
                Text("Don't forget to take break")
            }
            .opacity(0.5)
            .foregroundStyle(.white)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tip: Don't forget to take a break")

            Spacer()

            // Bottom control bar — same actions as minimized, different style
            HStack {
                // STOP
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { showEndConfirm = true }
                }) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.75))
                            .frame(width: 56, height: 56)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.red)
                            .frame(width: 20, height: 20)
                    }
                }
                .accessibilityLabel("End session")
                .accessibilityHint("Stops recording and ends your focus session early")
                .accessibilityInputLabels(["stop", "end session", "stop recording"])

                Spacer()

                // PAUSE / RESUME (uses the unified togglePauseResume)
                Button(action: togglePauseResume) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.75))
                            .frame(width: 100, height: 100)
                        Image(systemName: sessionTimer.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.black)
                    }
                }
                .accessibilityLabel(sessionTimer.isRunning ? "Pause session" : "Resume session")
                .accessibilityInputLabels(sessionTimer.isRunning ? ["pause"] : ["resume", "play"])
                .disabled(isPauseResumeTransitioning)
                .opacity(isPauseResumeTransitioning ? 0.65 : 1)

                Spacer()

                // MINIMIZE — shrink back to the recording page layout
                Button(action: {
                    withAnimation(focusTransition) {
                        isExpanded = false
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.75))
                            .frame(width: 56, height: 56)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 18))
                            .foregroundStyle(.black)
                    }
                }
                .accessibilityLabel("Exit full focus mode")
                .accessibilityHint("Returns to the standard recording layout")
                .accessibilityInputLabels(["minimize", "exit focus", "collapse"])
            }
            .padding(.horizontal, 24)

            Color.clear.frame(height: 16)
        }
    }

    private func takeBreak(_ reason: String, for prompt: PendingPrompt) {
        prompt.distraction.reason = reason
        prompt.distraction.reasonSubmitted = true
        #if os(iOS)
        focusController.grantBreak(for: prompt.distraction)
        let secs = Int(FocusViewModel.breakDuration)
        unlock = UnlockInfo(timeText: String(format: "%d:%02d", secs / 60, secs % 60))
        #endif
        try? modelContext.save()
        pendingPrompt = nil
    }

    private func cancelBreak(for prompt: PendingPrompt) {
        if pendingPrompt?.id == prompt.id {
            pendingPrompt = nil
        }

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
        guard breakBlockedInfo == nil, unlock == nil else { return }
        guard let pair = SharedJailbreakStore.nextUnhandledBreak() else { return }
        if let pendingPrompt, pair.action.occurredAt <= pendingPrompt.actionOccurredAt {
            return
        }

        // one break at a time: if an app is already unlocked, reject this new break —
        // keep the active break running, warn the user, and skip the reason form.
        if focusController.activeBreaks.contains(where: { focusController.remainingSeconds(for: $0) > 0 }) {
            breakBlockedInfo = BreakBlockedInfo()
            SharedJailbreakStore.markBreakHandled(pair.action.occurredAt)   // consume so it won't re-prompt
            return
        }

        if let stalePrompt = pendingPrompt,
           !stalePrompt.distraction.reasonSubmitted,
           stalePrompt.distraction.breakGrantedUntil == nil {
            modelContext.delete(stalePrompt.distraction)
            pendingPrompt = nil
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
            actionOccurredAt: pair.action.occurredAt,
            tokenDataToClear: tokenData
        )
        #endif
    }

    // .openParentalControlsApp is the primary shield→app return; the shield also queued
    // a delayed notification as a fallback. We're back in the app now, so drop it.
    private func cancelShieldFallbackNotifications() {
        // Only clear DELIVERED ones — leave any pending request to fire, since pending means the
        // app hasn't genuinely returned yet (don't kill the safety net on a transient .active).
        let ids = ["rushhour.shieldreturn", "rushhour.shieldreason"]
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
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

    private func endSessionEarly() {
        recLog("endSessionEarly")
        SessionNotifications.cancelAwayNudges()
        sessionTimer.pause()
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


// MARK: - Countdown housing
//
// Compact, label-less version of the home traffic housing: three split shell
// layers in a dark rounded bar, showing the live remaining time.

private struct RecordingTrafficTimer: View {
    let hours: Int
    let minutes: Int
    let seconds: Int

    private let panelSize: CGFloat = 74

    var body: some View {
        HStack(spacing: 8) {
            panel(text: "\(hours)")
            panel(text: String(format: "%02d", minutes))
            panel(text: String(format: "%02d", seconds))
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(white: 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue(AccessibilitySupport.spokenCountdown(hours: hours, minutes: minutes, seconds: seconds))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func panel(text: String) -> some View {
        let lensDiameter = panelSize * 0.68
        let lensArtDiameter = panelSize * (87.27 / 99.36)
        let shellShadowHeight = panelSize * (26.69 / 99.36)
        let shellShadowWidth = panelSize * (99.41 / 99.36)
        let lensTop = (panelSize - lensArtDiameter) / 2
        let wheelTop = (panelSize - lensDiameter) / 2

        return ZStack(alignment: .top) {
            Image("TrafficShellShadow")
                .resizable()
                .frame(width: shellShadowWidth, height: shellShadowHeight)
                .offset(y: panelSize)

            Image("TrafficShellBg")
                .resizable()
                .frame(width: panelSize, height: panelSize)

            Image("TrafficShell")
                .resizable()
                .frame(width: lensArtDiameter, height: lensArtDiameter)
                .offset(y: lensTop)

            Text(text)
                .font(.custom("Special Gothic Expanded One", size: panelSize * 0.4))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: lensDiameter, height: lensDiameter)
                .clipShape(Circle())
                .offset(y: wheelTop)
        }
        .frame(width: panelSize, height: panelSize)
    }
}

// MARK: - End Session confirmation

struct EndSessionConfirm: View {
    let onEnd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 38, height: 5)
                    .padding(.top, 10)

                HStack {
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.55))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .accessibilityHint("Cancels ending the session")
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)

                Text("End Session")
                    .font(.custom("Special Gothic Expanded One", size: 22))
                    .foregroundStyle(.black)
                    .padding(.top, 2)

                Text("Ending now will stop recording\nand end your session early")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                HStack(spacing: 14) {
                    Button(action: onEnd) {
                        Text("END")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .overlay(Capsule().stroke(Color.red, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("End session now")
                    .accessibilityHint("Stops recording and ends your session early")
                    .accessibilityInputLabels(["end", "confirm end", "stop session"])

                    Button(action: onCancel) {
                        Text("CANCEL")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                    .accessibilityHint("Continues your current session")
                    .accessibilityInputLabels(["cancel", "keep going", "go back"])
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 22)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
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

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        if let connection = previewLayer.connection {
            // Preview follows the app interface; recording orientation is handled by the writer.
            // Run it asynchronously on the main actor.
            Task { @MainActor in
                await VideoOrientationHelper.applyToPreviewConnection(connection)
            }
        }
    }
}


#Preview {
    RecordingPage(isExpanded: .constant(false))
        .environmentObject(SessionTimerViewModel())
        .environmentObject(SessionRecordingViewModel())
        .environmentObject(FocusViewModel())
        .modelContainer(for: [Session.self, Distraction.self], inMemory: true)
}
