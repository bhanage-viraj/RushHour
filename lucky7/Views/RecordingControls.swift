import SwiftUI

/// Camera and controls share the same canvas so the embedded preview stays aligned.
struct RecordingLayout {
    let size: CGSize
    let isExpanded: Bool
    let isPaused: Bool

    var scale: CGFloat { min(size.width / 402, size.height / 874) }
    var origin: CGPoint {
        CGPoint(x: (size.width - 402 * scale) / 2, y: (size.height - 874 * scale) / 2)
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    func rect(_ rect: CGRect) -> CGRect {
        CGRect(x: origin.x + rect.minX * scale, y: origin.y + rect.minY * scale,
               width: rect.width * scale, height: rect.height * scale)
    }

    var camera: CGRect {
        rect(isExpanded
             ? CGRect(x: 119, y: 189, width: 164, height: 164)
             : CGRect(x: 10, y: 62, width: 382, height: 789))
    }

    var timer: CGRect {
        rect(isExpanded
             ? CGRect(x: 27, y: isPaused ? 389.5 : 387, width: 348, height: 132)
             : CGRect(x: 105, y: 78, width: 192, height: 72))
    }

    var badgeCenter: CGPoint { point(201, isExpanded ? 84.5 : 169.5) }
    var controlsCenter: CGPoint { point(201, isExpanded ? (isPaused ? 784 : 799) : 793) }
}

struct RecordingControls: View {
    let hours: Int
    let minutes: Int
    let seconds: Int
    let hasStarted: Bool
    let isRunning: Bool
    let isExpanded: Bool
    let isTransitioning: Bool
    let onEnd: () -> Void
    let onPauseResume: () -> Void
    let onToggleExpanded: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let layout = RecordingLayout(size: geometry.size, isExpanded: isExpanded,
                                         isPaused: hasStarted && !isRunning)
            ZStack {
                RecordingTrafficTimer(hours: hours, minutes: minutes, seconds: seconds,
                                      width: layout.timer.width)
                    .position(x: layout.timer.midX, y: layout.timer.midY)

                if hasStarted && !isRunning {
                    Text("PAUSED")
                        .font(.system(size: 11 * layout.scale, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 8 * layout.scale)
                        .padding(.vertical, 4 * layout.scale)
                        .background(Color(red: 1, green: 56 / 255, blue: 60 / 255), in: Capsule())
                        .position(layout.badgeCenter)
                        .accessibilityLabel("Recording paused")
                }

                if isExpanded {
                    Text("Tips:\nDon’t forget to take a break to drink")
                        .font(.system(size: 14 * layout.scale))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 264 * layout.scale)
                        .position(layout.point(204, 649.2))
                }

                controls(scale: layout.scale)
                    .frame(width: 340 * layout.scale, height: 80 * layout.scale)
                    .position(layout.controlsCenter)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }

    private func controls(scale: CGFloat) -> some View {
        HStack {
            Button(action: onEnd) {
                Image(systemName: "square.fill")
                    .font(.system(size: 16 * scale, weight: .heavy))
                    .foregroundStyle(Color(red: 1, green: 56 / 255, blue: 60 / 255))
                    .frame(width: max(44, 48 * scale), height: max(44, 48 * scale))
                    .background(.white.opacity(0.75), in: Circle())
            }
            .accessibilityLabel("End session")
            .accessibilityHint("Stops recording and ends your focus session early")
            .accessibilityInputLabels(["stop", "end session", "stop recording"])

            Spacer()

            Button(action: onPauseResume) {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 32 * scale, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 80 * scale, height: 80 * scale)
                    .background(.white.opacity(0.75), in: Circle())
            }
            .accessibilityLabel(isRunning ? "Pause session" : "Resume session")
            .accessibilityHint(isRunning ? "Pauses the timer and timelapse recording" : "Resumes the timer and timelapse recording")
            .accessibilityInputLabels(isRunning ? ["pause", "pause session", "pause recording"] : ["resume", "play", "resume session", "continue recording"])
            .disabled(isTransitioning)
            .opacity(isTransitioning ? 0.65 : 1)

            Spacer()

            Button(action: onToggleExpanded) {
                Image(systemName: isExpanded
                      ? "arrow.down.backward.and.arrow.up.forward"
                      : "arrow.up.right.and.arrow.down.left")
                    .font(.system(size: 16 * scale, weight: .heavy))
                    .foregroundStyle(Color(white: 38 / 255).opacity(0.8))
                    .frame(width: max(44, 48 * scale), height: max(44, 48 * scale))
                    .background(.white.opacity(0.75), in: Circle())
            }
            .accessibilityLabel(isExpanded ? "Exit full focus mode" : "Enter full focus mode")
            .accessibilityHint(isExpanded ? "Returns to the standard recording layout" : "Shows a larger timer with fewer distractions")
            .accessibilityInputLabels(isExpanded ? ["minimize", "exit focus", "collapse"] : ["expand", "full focus", "focus mode", "fullscreen"])
        }
        .buttonStyle(.plain)
    }
}

struct RecordingTrafficTimer: View {
    let hours: Int
    let minutes: Int
    let seconds: Int
    let width: CGFloat

    var body: some View {
        let scale = width / 348
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12.934 * scale)
                .fill(LinearGradient(colors: [Color(white: 28 / 255), .black],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: width, height: 132 * scale)

            HStack(spacing: 10.796 * scale) {
                panel(hours, scale: scale)
                panel(minutes, scale: scale)
                panel(seconds, scale: scale)
            }
            .offset(x: 14.034 * scale, y: 18.51 * scale)

            Image("RecordingTimerTopMask")
                .resizable()
                .frame(width: 348.699 * scale, height: 52.118 * scale)
                .offset(x: -1.12 * scale, y: 0.3 * scale)

            ForEach([119.0, 229.0], id: \.self) { x in
                Text(":")
                    .font(.custom("Special Gothic Expanded One", size: 20 * scale))
                    .foregroundStyle(.white)
                    .position(x: x * scale, y: (68.5 - 1.96) * scale)
            }
        }
        .frame(width: width, height: 132 * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue(AccessibilitySupport.spokenCountdown(hours: hours, minutes: minutes, seconds: seconds))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func panel(_ value: Int, scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 17.347 * scale)
                .fill(LinearGradient(colors: [Color(white: 63 / 255), Color(white: 32 / 255)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 17.347 * scale)
                        .stroke(Color(white: 61 / 255), lineWidth: 1.334 * scale)
                }
                .frame(width: 99.358 * scale, height: 99.358 * scale)

            Text("\(value)")
                .font(.custom("Special Gothic Expanded One", size: 36 * scale))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 92 * scale, height: 94 * scale)
                .background(.black, in: RoundedRectangle(cornerRadius: 13 * scale))
                .offset(x: 2.67 * scale, y: 1.65 * scale)
        }
        .frame(width: 99.358 * scale, height: 99.358 * scale)
        .overlay(alignment: .topLeading) {
            Image("RecordingTimerSlotShadow")
                .resizable()
                .frame(width: 116.227 * scale, height: 43.503 * scale)
                .offset(x: -8.41 * scale, y: 84.81 * scale)
        }
    }
}

/// Clipped by the camera's existing rounded frame, including its blurred edges.
struct RecordingCameraShading: View {
    let isPaused: Bool

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 382
            ZStack {
                if isPaused {
                    Image("RecordingPausedGlow")
                        .resizable()
                        .frame(width: 759.182 * scale, height: 479.275 * scale)
                        .position(x: (191 + 12.93) * scale, y: 98 * scale)
                }
                Image("RecordingTopShade")
                    .resizable()
                    .frame(width: 739 * scale, height: 353 * scale)
                    .position(x: 200.5 * scale, y: -0.5 * scale)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
