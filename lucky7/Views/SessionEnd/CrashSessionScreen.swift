// Views/SessionEnd/CrashSessionScreen.swift

import SwiftUI
import SwiftData

private enum SessionEndStep {
    case celebration
    case details
    case analytics
}

struct CrashSessionScreen: View {
    var onFlowComplete: () -> Void

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var sessionTimer: SessionTimerViewModel
    @EnvironmentObject private var sessionRecording: SessionRecordingViewModel

    private var videoFrames: [UIImage] { sessionRecording.previewFrames }
    private let stepAnimation = Animation.spring(response: 0.44, dampingFraction: 0.9, blendDuration: 0.08)
    private var stepTransition: AnyTransition {
        .opacity
    }

    @State private var appeared = false
    @State private var shake = false
    @State private var step: SessionEndStep = .celebration
    @State private var sessionId: UUID?
    @State private var hasCompletedFlow = false
    @State private var previewWaitTimedOut = false

    private var canAdvanceToDetails: Bool {
        !videoFrames.isEmpty || previewWaitTimedOut
    }

    var body: some View {
        ZStack {
            switch step {
            case .celebration:
                celebrationView
                    .transition(stepTransition)
                    .overlay(alignment: .bottom) {
                        if sessionRecording.savedToPhotos {
                            Text("Saved to Photos")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.8))
                                .clipShape(Capsule())
                                .padding(.bottom, 48)
                        }
                    }
            case .details:
                if let sessionId {
                    SessionDetails(
                        sessionId: sessionId,
                        videoFrames: videoFrames,
                        onSave: {
                            withAnimation(stepAnimation) {
                                step = .analytics
                            }
                        },
                        onFlowComplete: completeFlow
                    )
                    .transition(stepTransition)
                }
            case .analytics:
                if let sessionId {
                    SessionAnalytics(
                        sessionId: sessionId,
                        videoFrames: videoFrames,
                        onClose: completeFlow
                    )
                    .transition(stepTransition)
                }
            }
        }
        .animation(stepAnimation, value: step)
        .onAppear {
            appeared = true
            shake = true
            createSessionIfNeeded()
            startPreviewFallbackTimer()
            AccessibilitySupport.announce("Session ended early")
        }
        .onChange(of: sessionRecording.finalVideoURL) { _, url in
            persistWrappedVideoPath(url)
        }
        .onChange(of: sessionRecording.rawClipURL) { _, url in
            persistRawClipPath(url)
        }
        .onChange(of: sessionRecording.photoAssetId) { _, id in
            persistPhotoAssetId(id)
        }
        .onChange(of: sessionRecording.previewFrames.count) { _, count in
            if count > 0 {
                RecordingDiagnostics.log("CrashSession preview ready count=\(count)")
            }
        }
    }

    private func persistPhotoAssetId(_ id: String?) {
        guard let sessionId, let id else { return }
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionId })
        descriptor.fetchLimit = 1
        if let session = try? context.fetch(descriptor).first {
            session.photoAssetId = id
            try? context.save()
        }
    }

    private func persistWrappedVideoPath(_ url: URL?) {
        // Filename only — see FinishSessionScreen; absolute paths break on app update.
        guard let sessionId, let name = url?.lastPathComponent else { return }
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionId })
        descriptor.fetchLimit = 1
        if let session = try? context.fetch(descriptor).first {
            session.wrappedVideoPath = name
            try? context.save()
            RecordingDiagnostics.log("CrashSession persist wrapped session=\(sessionId) path=\(name)")
        }
    }

    private func persistRawClipPath(_ url: URL?) {
        guard let sessionId, let name = url?.lastPathComponent else { return }
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionId })
        descriptor.fetchLimit = 1
        if let session = try? context.fetch(descriptor).first {
            session.rawClipPath = name
            try? context.save()
            RecordingDiagnostics.log("CrashSession persist raw session=\(sessionId) path=\(name)")
        }
    }

    private var celebrationView: some View {
        ZStack {
            LinearGradient(
                    colors: [Color(hex: "003261"), Color(hex: "0B1F32")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

            Image("PatternBackgroundSmall")
                .ignoresSafeArea()
                .accessibilityDecorative()

            VStack {
                Spacer()

                ZStack {
                    Text("🤕")
                        .font(.system(size: 112))
                        .offset(x: 68, y: -32)
                        .rotationEffect(.degrees(appeared ? 9 : 30))
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 1.4)
                        .animation(.spring(response: 0.5, dampingFraction: 0.4).delay(0.2), value: appeared)
                        .accessibilityDecorative()

                    Image(.titleEndSession)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : -20)
                        .blur(radius: appeared ? 0 : 6)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.05), value: appeared)
                        .accessibilityDecorative()
                }
                .offset(x: shake ? -8 : 0)
                .animation(
                    .interpolatingSpring(stiffness: 600, damping: 8)
                    .repeatCount(4, autoreverses: true)
                    .delay(0.1),
                    value: shake
                )

                Text("Oh no, looks like you got distracted this session. Take a moment, reset, and try again.")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .frame(width: 240)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.easeOut(duration: 0.6).delay(0.4), value: appeared)

                Color.clear
                    .frame(height: 2)

                Image(systemName: "car.side.rear.and.collision.and.car.side.front")
                    .font(.system(size: 40))
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.4)
                    .animation(.spring(response: 0.5, dampingFraction: 0.4).delay(0.6), value: appeared)
                    .accessibilityDecorative()

                Spacer()

                Button(action: advanceToDetails) {
                    Text(canAdvanceToDetails ? "Tap to go to the next screen" : "Preparing preview...")
                        .font(.system(size: 14))
                        .opacity(appeared ? 0.8 : 0)
                        .animation(.easeIn(duration: 0.5).delay(0.9), value: appeared)
                }
                .disabled(!canAdvanceToDetails)
                .buttonStyle(.plain)
                .accessibilityLabel("Continue to session details")
                .accessibilityHint("Opens the screen to title and save your session")
                .accessibilityInputLabels(["continue", "next", "session details"])
            }
            .foregroundStyle(.white)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: advanceToDetails)
        .accessibilityAddTraits(.isButton)
    }

    private func advanceToDetails() {
        guard sessionId != nil, step == .celebration else { return }
        guard canAdvanceToDetails else {
            RecordingDiagnostics.log("CrashSession blocked details: preview not ready")
            return
        }
        showDetails(reason: videoFrames.isEmpty ? "preview timeout" : "preview ready")
    }

    private func startPreviewFallbackTimer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard videoFrames.isEmpty, step == .celebration else { return }
            previewWaitTimedOut = true
            RecordingDiagnostics.log("CrashSession preview wait timed out")
        }
    }

    private func showDetails(reason: String) {
        guard sessionId != nil, step == .celebration else { return }
        RecordingDiagnostics.log("CrashSession show details reason=\(reason) previewFrames=\(videoFrames.count)")
        withAnimation(stepAnimation) {
            step = .details
        }
    }

    private func createSessionIfNeeded() {
        guard sessionId == nil else { return }
        let id = sessionTimer.sessionId   // SAME id the distractions were saved under, so analytics matches
        let duration = TimeInterval(sessionTimer.elapsedSeconds)
        let endTime = sessionTimer.endedAt ?? Date()
        let session = Session(
            id: id,
            userId: UUID(),
            duration: TimeInterval(sessionTimer.configuredTotalSeconds),
            startTime: sessionTimer.startedAt ?? endTime.addingTimeInterval(-duration),
            endTime: endTime,
            wrappedVideoPath: sessionRecording.finalVideoURL?.lastPathComponent,
            rawClipPath: sessionRecording.rawClipURL?.lastPathComponent
        )
        context.insert(session)
        sessionId = id
        SessionEndRecovery.markPending(id)
        RecordingDiagnostics.log("CrashSession create session=\(id) wrapped=\(session.wrappedVideoPath ?? "nil") raw=\(session.rawClipPath ?? "nil")")
    }

    private func completeFlow() {
        guard !hasCompletedFlow else { return }
        hasCompletedFlow = true
        SessionEndRecovery.clear(sessionId)
        onFlowComplete()
    }
}

#Preview {
    CrashSessionScreen(onFlowComplete: {})
        .environmentObject(SessionTimerViewModel())
        .environmentObject(SessionRecordingViewModel())
        .modelContainer(for: Session.self, inMemory: true)
}

// MARK: - Extension Color

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
