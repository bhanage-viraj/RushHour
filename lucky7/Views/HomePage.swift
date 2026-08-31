import SwiftUI
import AVFoundation

// MARK: - Home Page
//
// New home screen: a live camera "card" with the traffic-light duration picker.
// The record button is gray until a duration is set, then turns red — tapping it
// does NOT push a new screen. Instead the *same* camera frame enlarges to fill the
// screen and the home controls cross-fade into the recording controls in place.

struct HomePage: View {

    /// Whether the Home tab is the one currently on screen. The tab bar keeps both
    /// tabs alive (opacity-swapped), so `onAppear`/`onDisappear` alone can't tell when
    /// Home is hidden — this drives the camera lifecycle so the live preview only runs
    /// while Home is actually visible.
    var isActiveTab: Bool = true

    @EnvironmentObject private var sessionTimer: SessionTimerViewModel
    @EnvironmentObject private var sessionRecording: SessionRecordingViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var hours = 0
    @State private var minutes = 0
    @State private var seconds = 0

    // One-time home coachmarks — hidden permanently after the first interaction.
    @AppStorage("homeTipDurationSeen") private var tipDurationSeen = false
    @AppStorage("homeTipStartSeen") private var tipStartSeen = false

    @State private var showSettings = false

    /// false = home card; true = full-screen session. Drives the enlarge transition.
    @State private var sessionActive = false

    /// true once the session is pushed into full-focus mode — morphs the one shared camera
    /// from the session card down into the focus circle. Shared with the embedded RecordingPage.
    @State private var isFocusExpanded = false
    // Safe-area insets, read once, so the camera card lines up under the header / above
    // the tab bar while the camera itself ignores the safe area (to animate to full screen).
    @State private var safeTop: CGFloat = 47
    @State private var safeBottom: CGFloat = 34

    private let transition = Animation.spring(response: 0.5, dampingFraction: 0.86)
    private let focusTransition = Animation.spring(response: 0.42, dampingFraction: 0.92, blendDuration: 0.08)

    private var isReadyToRecord: Bool {
        hours > 0 || minutes > 0 || seconds > 0
    }

    private var showSetupTip: Bool { !isReadyToRecord && !tipDurationSeen }
    private var showStartTip: Bool { isReadyToRecord && !tipStartSeen }

    var body: some View {
        ZStack {
            // 1a. Home background — fades out during a session.
            if !sessionActive {
                BackgroundPatternView(isTimerSet: isReadyToRecord)
                    .transition(.opacity)
            }

            // 1b. Session background (matches FullFocusScreen) — fades in around the frame.
            if sessionActive {
                RecordingBackground()
                    .transition(.opacity)
            }

            // 2. The single, persistent camera — ONE preview layer for the whole app so it
            //    never fights another layer for the feed. Its frame animates across three
            //    states: home card → full session card → focus circle.
            GeometryReader { geo in
                let circleSize: CGFloat = 164
                let isCircle = sessionActive && isFocusExpanded
                let homeScale = HomeDesign.scale(in: geo.size)
                let homeOrigin = HomeDesign.origin(in: geo.size, scale: homeScale)

                // Card insets (home vs in-session), measured from the screen edges. Active
                // frame: top sits 6pt below the countdown housing; bottom 6pt below pause.
                let activeTopInset = safeTop + 60
                let activeBottomInset = safeBottom + 28
                let activeHInset: CGFloat = 12

                let activeCardW = max(geo.size.width - activeHInset * 2, 0)
                let activeCardH = max(geo.size.height - activeTopInset - activeBottomInset, 0)
                let homeCardW = HomeDesign.camera.width * homeScale
                let homeCardH = HomeDesign.camera.height * homeScale

                let cardW = sessionActive ? activeCardW : homeCardW
                let cardH = sessionActive ? activeCardH : homeCardH
                let homeCenter = HomeDesign.center(of: HomeDesign.camera, origin: homeOrigin, scale: homeScale)

                let camW = isCircle ? circleSize : cardW
                let camH = isCircle ? circleSize : cardH
                let centerX = isCircle || sessionActive ? geo.size.width / 2 : homeCenter.x
                let centerY = isCircle ? safeTop + 168 : (sessionActive ? activeTopInset + activeCardH / 2 : homeCenter.y)
                let corner: CGFloat = isCircle ? circleSize / 2 : 30

                ZStack(alignment: .top) {
                    Color.black

                    CameraPreview(session: sessionRecording.captureSession)
                        .frame(width: camW, height: camH)

                    if isReadyToRecord && !sessionActive && !isCircle {
                        GeometryReader { _ in
                            Image("HomeReadyGlow")
                                .resizable()
                                // The Figma source is a transparent SVG: keep its individual
                                // red, yellow, and green alpha gradients intact over the preview.
                                .renderingMode(.original)
                                .frame(
                                    width: HomeDesign.readyGlowSize.width * homeScale,
                                    height: HomeDesign.readyGlowSize.height * homeScale
                                )
                                .position(
                                    x: HomeDesign.readyGlowCenter.x * homeScale,
                                    y: HomeDesign.readyGlowCenter.y * homeScale
                                )
                        }
                            .frame(width: camW, height: camH)
                            .clipped()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: camW, height: camH)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay {
                        if !isCircle {
                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                                .strokeBorder(Color.black, lineWidth: sessionActive ? 3 : 2)
                        }
                    }
                    .position(x: centerX, y: centerY)
                    .animation(focusTransition, value: isFocusExpanded)
                    .animation(transition, value: sessionActive)
            }
            .ignoresSafeArea()

            // 3. Home controls (header + duration picker + record + flip) — fade out.
            if !sessionActive {
                HomeControls(
                    hours: $hours,
                    minutes: $minutes,
                    seconds: $seconds,
                    isReadyToRecord: isReadyToRecord,
                    cameraReady: sessionRecording.cameraReady,
                    showSetupTip: showSetupTip,
                    showStartTip: showStartTip,
                    onInteraction: { sessionRecording.noteHomePreviewInteraction() },
                    onSettings: { showSettings = true },
                    onFlip: { sessionRecording.switchCamera() },
                    onRecord: startSession
                )
                .transition(.opacity)
            }

            // 4. Recording controls, hosted in place over the now-full-screen camera.
            if sessionActive {
                RecordingPage(
                    autoStart: true,
                    embedded: true,
                    isExpanded: $isFocusExpanded,
                    onExit: {
                        isFocusExpanded = false   // reset focus state when the session ends
                        endSession()
                    }
                )
                .hidesFloatingTabBar()
                .transition(.opacity)
            }
        }
        .background(safeAreaReader)
        .onAppear {
            if isActiveTab { sessionRecording.noteHomePreviewInteraction() }
        }
        .onDisappear { sessionRecording.stopHomePreview() }
        .onChange(of: isActiveTab) { _, active in
            if active { sessionRecording.noteHomePreviewInteraction() }
            else { sessionRecording.stopHomePreview() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Mid-session the camera is already live — only warm it up for the idle
                // home preview, never underneath a recording.
                if isActiveTab && !sessionActive { sessionRecording.noteHomePreviewInteraction() }
            case .background, .inactive:
                sessionRecording.stopHomePreview()
            @unknown default:
                break
            }
        }
        .onChange(of: sessionActive) { _, active in
            if !active { sessionRecording.noteHomePreviewInteraction() }   // session ended → resume home preview
            AccessibilitySupport.announce(active ? "Focus session started" : "Returned to home")
        }
        .onChange(of: isReadyToRecord) { _, ready in
            if ready { tipDurationSeen = true }   // first duration set → drop the setup tip for good
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsScreen()
        }
    }

    private var safeAreaReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    safeTop = proxy.safeAreaInsets.top
                    safeBottom = proxy.safeAreaInsets.bottom
                }
        }
        .ignoresSafeArea()
    }

    private func startSession() {
        guard isReadyToRecord, sessionRecording.cameraReady else { return }
        sessionRecording.noteHomePreviewInteraction()
        tipStartSeen = true   // first session start → drop the "start" tip for good
        sessionTimer.configure(hours: hours, minutes: minutes, seconds: seconds)
        withAnimation(transition) { sessionActive = true }
    }

    private func endSession() {
        withAnimation(transition) { sessionActive = false }
    }
}

private enum HomeDesign {
    static let size = CGSize(width: 402, height: 874)
    static let backgroundPattern = CGSize(width: 963.912, height: 963.912)
    static let backgroundPatternCenter = CGPoint(x: 203, y: 440)
    static let camera = CGRect(x: 10, y: 107, width: 382, height: 657)
    static let settings = CGRect(x: 16, y: 57, width: 40, height: 40)
    static let logo = CGRect(x: 130.103, y: 55, width: 148.536, height: 44.134)
    static let timer = CGRect(x: 26.96, y: 123, width: 348.079, height: 146)
    static let setupTip = CGRect(x: 129, y: 281, width: 144, height: 29)
    static let startTip = CGRect(x: 99.5, y: 620, width: 203, height: 29)
    static let recordCenter = CGPoint(x: 201, y: 703)
    static let flip = CGRect(x: 326, y: 683, width: 40, height: 40)
    static let readyGlowSize = CGSize(width: 759.182, height: 479.275)
    // This is the glow's center in the camera card's coordinate space. It must
    // not include the camera card's page-level x origin.
    static let readyGlowCenter = CGPoint(x: 203.932, y: 98)

    static func scale(in size: CGSize) -> CGFloat {
        min(size.width / Self.size.width, size.height / Self.size.height)
    }

    static func origin(in size: CGSize, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: (size.width - Self.size.width * scale) / 2,
            y: (size.height - Self.size.height * scale) / 2
        )
    }

    static func center(of rect: CGRect, origin: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: origin.x + rect.midX * scale,
            y: origin.y + rect.midY * scale
        )
    }

    static func point(_ point: CGPoint, origin: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: origin.x + point.x * scale,
            y: origin.y + point.y * scale
        )
    }
}

// MARK: - Background

struct BackgroundPatternView: View {
    let isTimerSet: Bool

    var body: some View {
        GeometryReader { geo in
            let scale = HomeDesign.scale(in: geo.size)
            let origin = HomeDesign.origin(in: geo.size, scale: scale)
            let patternCenter = HomeDesign.point(
                HomeDesign.backgroundPatternCenter,
                origin: origin,
                scale: scale
            )

            ZStack {
                Color(
                    red: isTimerSet ? 0 / 255 : 24 / 255,
                    green: isTimerSet ? 96 / 255 : 128 / 255,
                    blue: isTimerSet ? 190 / 255 : 229 / 255
                )

                Image("group45")
                    .resizable()
                    .frame(
                        width: HomeDesign.backgroundPattern.width * scale,
                        height: HomeDesign.backgroundPattern.height * scale
                    )
                    .position(patternCenter)
                    .allowsHitTesting(false)
            }
            .clipped()
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Session background (matches FullFocusScreen)

struct RecordingBackground: View {
    var body: some View {
        ZStack {
            Color("CanvasDarkGrey")
                .ignoresSafeArea()

            Image("PatternBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .offset(x: -20, y: 2)

            VStack {
                Spacer()
                Image("bottomBlur")
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityDecorative()
    }
}

// MARK: - Header

private struct HomeHeader: View {
    let onSettings: () -> Void

    var body: some View {
        ZStack {
            Image("Hrushhour")
                .resizable()
                .scaledToFit()
                .frame(width: 149, height: 45)

            HStack {
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Settings")
                .accessibilityHint("Opens app settings")
                .accessibilityInputLabels(["settings", "open settings", "gear"])
                Spacer()
            }
            .padding(.horizontal, 22)
        }
        .frame(height: 45)
    }
}

// MARK: - Home Controls
private struct HomeControls: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int
    let isReadyToRecord: Bool
    let cameraReady: Bool
    let showSetupTip: Bool
    let showStartTip: Bool
    let onInteraction: () -> Void
    let onSettings: () -> Void
    let onFlip: () -> Void
    let onRecord: () -> Void

    var body: some View {
        GeometryReader { geo in
            let scale = HomeDesign.scale(in: geo.size)
            let origin = HomeDesign.origin(in: geo.size, scale: scale)
            let recordCenter = HomeDesign.point(HomeDesign.recordCenter, origin: origin, scale: scale)

            ZStack {
                Button(action: {
                    onInteraction()
                    onSettings()
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18.732 * scale, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: HomeDesign.settings.width * scale, height: HomeDesign.settings.height * scale)
                }
                .buttonStyle(.plain)
                .position(HomeDesign.center(of: HomeDesign.settings, origin: origin, scale: scale))

                Image("Hrushhour")
                    .resizable()
                    .scaledToFit()
                    .frame(width: HomeDesign.logo.width * scale, height: HomeDesign.logo.height * scale)
                    .position(HomeDesign.center(of: HomeDesign.logo, origin: origin, scale: scale))

                HomeTrafficTimer(
                    hours: $hours,
                    minutes: $minutes,
                    seconds: $seconds,
                    timerWidth: HomeDesign.timer.width * scale
                )
                .position(HomeDesign.center(of: HomeDesign.timer, origin: origin, scale: scale))

                if showSetupTip {
                    HomePillTooltip(
                        text: "Set up focus duration",
                        width: HomeDesign.setupTip.width,
                        height: HomeDesign.setupTip.height,
                        direction: .up,
                        scale: scale
                    )
                    .position(HomeDesign.center(of: HomeDesign.setupTip, origin: origin, scale: scale))
                }

                if showStartTip {
                    HomePillTooltip(
                        text: "Start session when you're ready",
                        width: HomeDesign.startTip.width,
                        height: HomeDesign.startTip.height,
                        direction: .down,
                        scale: scale
                    )
                    .position(HomeDesign.center(of: HomeDesign.startTip, origin: origin, scale: scale))
                }

                RecordButton(isReady: isReadyToRecord, scale: scale) {
                    onInteraction()
                    onRecord()
                }
                    .disabled(!isReadyToRecord || !cameraReady)
                    .position(recordCenter)

                FlipCameraButton(scale: scale) {
                    onInteraction()
                    onFlip()
                }
                    .position(HomeDesign.center(of: HomeDesign.flip, origin: origin, scale: scale))
            }
        }
        .ignoresSafeArea()
        .simultaneousGesture(TapGesture().onEnded(onInteraction))
    }
}

// MARK: - Record / Flip buttons

private struct RecordButton: View {
    let isReady: Bool
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 80 * scale, height: 80 * scale)
                Circle()
                    .fill(isReady ? Color("ButtonRed") : Color(white: 0.6))
                    .frame(width: 68 * scale, height: 68 * scale)
                Image(systemName: "play.fill")
                    .font(.system(size: 30 * scale, weight: .bold))
                    .foregroundStyle(isReady ? Color.white : Color.white.opacity(0.42))
                    .offset(x: 1 * scale)
            }
            .animation(.easeInOut(duration: 0.2), value: isReady)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isReady ? "Start focus session" : "Start focus session, unavailable")
        .accessibilityHint(isReady ? "Begins timelapse recording and focus timer" : "Set a focus duration first")
        .accessibilityInputLabels(["record", "start", "start session", "start recording", "start timelapse"])
        .accessibilityAddTraits(.isButton)
    }
}

private struct FlipCameraButton: View {
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 16 * scale, weight: .heavy))
                .foregroundStyle(Color(red: 52 / 255, green: 52 / 255, blue: 52 / 255))
                .frame(width: 40 * scale, height: 40 * scale)
                .background(Color.white.opacity(0.75), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch camera")
        .accessibilityHint("Switches between front and back camera")
        .accessibilityInputLabels(["flip camera", "switch camera", "front camera", "back camera"])
    }
}

// MARK: - Tooltip

private struct HomePillTooltip: View {
    enum Direction {
        case up
        case down
    }

    let text: String
    let width: CGFloat
    let height: CGFloat
    let direction: Direction
    let scale: CGFloat

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255).opacity(0.8))

            Text(text)
                .font(.system(size: 12 * scale, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Image("HomeTooltipPointer")
                .resizable()
                .frame(width: 10 * scale, height: 6 * scale)
                .rotationEffect(direction == .up ? .degrees(180) : .zero)
                .offset(
                    y: direction == .up
                        ? -(height / 2 + 3) * scale
                        : (height / 2 + 3) * scale
                )
        }
        .frame(width: width * scale, height: height * scale)
    }
}

// MARK: - Traffic-light duration picker

private struct HomeTrafficTimer: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int
    let timerWidth: CGFloat

    private enum Layout {
        static let size = CGSize(width: 348.079, height: 146)
        static let slotOrigin = CGPoint(x: 14.034, y: 18.014)
        static let slotSize = CGSize(width: 99.358, height: 99.358)
        static let slotSpacing: CGFloat = 10.796
        static let dialOrigin = CGPoint(x: 4.005, y: 2.986)
        static let dialSize = CGSize(width: 92, height: 94)
        static let slotCornerRadius: CGFloat = 17.347
        static let dialCornerRadius: CGFloat = 13
        static let slotShadowOrigin = CGPoint(x: -8.41, y: 84.81)
        static let slotShadowSize = CGSize(width: 116.227, height: 43.503)
        static let topMaskOrigin = CGPoint(x: -1.08, y: -0.2)
        static let topMaskSize = CGSize(width: 348.699, height: 52.118)
        static let labels = [
            (text: "HOURS", center: CGPoint(x: 63.01, y: 130.26)),
            (text: "MINUTES", center: CGPoint(x: 172.93, y: 130.26)),
            (text: "SECONDS", center: CGPoint(x: 284.19, y: 130.26))
        ]
        static let colonCenters = [CGPoint(x: 119.04, y: 68), CGPoint(x: 229.04, y: 68)]
    }

    private var timerHeight: CGFloat { timerWidth * HomeDesign.timer.height / HomeDesign.timer.width }

    var body: some View {
        let scale = timerWidth / Layout.size.width
        let slotSize = CGSize(
            width: Layout.slotSize.width * scale,
            height: Layout.slotSize.height * scale
        )
        let slotGroupWidth = slotSize.width * 3 + Layout.slotSpacing * scale * 2

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12.934 * scale, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: timerWidth, height: timerHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            HStack(spacing: Layout.slotSpacing * scale) {
                dial($hours, range: 0...23, unit: .hour, scale: scale)
                dial($minutes, range: 0...59, unit: .minute, scale: scale)
                dial($seconds, range: 0...59, unit: .second, scale: scale)
            }
            .frame(width: slotGroupWidth, height: slotSize.height, alignment: .topLeading)
            .offset(x: Layout.slotOrigin.x * scale, y: Layout.slotOrigin.y * scale)

            Image("HomeTrafficTimerTopMask")
                .resizable()
                .frame(
                    width: Layout.topMaskSize.width * scale,
                    height: Layout.topMaskSize.height * scale
                )
                .offset(
                    x: Layout.topMaskOrigin.x * scale,
                    y: Layout.topMaskOrigin.y * scale
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            ForEach(Array(Layout.labels.enumerated()), id: \.offset) { _, label in
                Text(label.text)
                    .font(.system(size: 9.669 * scale, weight: .regular))
                    .tracking(1.064 * scale)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: label.center.x * scale, y: label.center.y * scale)
                    .accessibilityHidden(true)
            }

            ForEach(Array(Layout.colonCenters.enumerated()), id: \.offset) { _, center in
                Text(":")
                    .font(.custom("Special Gothic Expanded One", size: 20 * scale))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .position(x: center.x * scale, y: center.y * scale)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: timerWidth, height: timerHeight)
    }

    private func dial(
        _ value: Binding<Int>,
        range: ClosedRange<Int>,
        unit: AccessibilitySupport.TimeUnit,
        scale: CGFloat
    ) -> some View {
        let slotSize = CGSize(
            width: Layout.slotSize.width * scale,
            height: Layout.slotSize.height * scale
        )
        let dialSize = CGSize(
            width: Layout.dialSize.width * scale,
            height: Layout.dialSize.height * scale
        )

        return ZStack(alignment: .topLeading) {
            Image("HomeTrafficTimerSlotShadow")
                .resizable()
                .frame(
                    width: Layout.slotShadowSize.width * scale,
                    height: Layout.slotShadowSize.height * scale
                )
                .offset(
                    x: Layout.slotShadowOrigin.x * scale,
                    y: Layout.slotShadowOrigin.y * scale
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            RoundedRectangle(cornerRadius: Layout.slotCornerRadius * scale, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 63 / 255, green: 63 / 255, blue: 63 / 255),
                            Color(red: 32 / 255, green: 32 / 255, blue: 32 / 255)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.slotCornerRadius * scale, style: .continuous)
                        .stroke(Color(red: 61 / 255, green: 61 / 255, blue: 61 / 255), lineWidth: 1.334 * scale)
                }
                .frame(width: slotSize.width, height: slotSize.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            RoundedRectangle(cornerRadius: Layout.dialCornerRadius * scale, style: .continuous)
                .fill(.black)
                .frame(width: dialSize.width, height: dialSize.height)
                .offset(x: Layout.dialOrigin.x * scale, y: Layout.dialOrigin.y * scale)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            HomeTimeDial(selected: value, range: range, size: dialSize, unit: unit)
                .frame(width: dialSize.width, height: dialSize.height)
                .offset(
                    x: Layout.dialOrigin.x * scale,
                    y: Layout.dialOrigin.y * scale
                )
        }
        .frame(width: slotSize.width, height: slotSize.height)
    }
}

// MARK: - Single number dial


private struct HomeTimeDial: View {
    @Binding var selected: Int
    let range: ClosedRange<Int>
    let size: CGSize
    let unit: AccessibilitySupport.TimeUnit

    @State private var scrollID: Int?

    private var values: [Int] { Array(range) }

    private func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    var body: some View {
        let row = size.height / 2
        let centerPadding = max((size.height - row) / 2, 0)

        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(values, id: \.self) { number in
                    let isSelected = number == selected
                    Text("\(number)")
                        .font(.custom("Special Gothic Expanded One", size: 36 * size.width / 92))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.4))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: true, vertical: true)
                        .animation(.smooth(duration: 0.15), value: selected)
                        .frame(width: size.width, height: row)
                        .id(number)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, centerPadding)
        }
        .frame(width: size.width, height: size.height)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollID, anchor: .center)
        .scrollClipDisabled()
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 13 * size.width / 92, style: .continuous))
        .onAppear { if scrollID == nil { scrollID = clamped(selected) } }
        .onChange(of: scrollID) { _, new in
            guard let new else { return }
            let value = clamped(new)
            if value != selected { selected = value }
        }
        .onChange(of: selected) { _, new in
            let value = clamped(new)
            if value != new {
                selected = value
            } else if scrollID != value {
                scrollID = value
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .timeDialAccessibility(selected: $selected, range: range, unit: unit)
    }
}

#Preview {
    HomePage()
        .environmentObject(SessionTimerViewModel())
        .environmentObject(SessionRecordingViewModel())
}
