import Foundation
import Combine

@MainActor
final class SessionTimerViewModel: ObservableObject {
    @Published var hours: Int = 2
    @Published var minutes: Int = 30
    @Published var seconds: Int = 0
    @Published var isRunning: Bool = false
    @Published var showFinishSession: Bool = false
    @Published var requestReturnToHome: Bool = false

    // One id per focus session, minted in configure() (called when a session is set up).
    // Distractions are saved under it AND the Session row is created with it, so the analytics
    // screens — which match distractions by Session.id — actually find them.
    private(set) var sessionId = UUID()

    private var timer: Timer?
    private var totalSeconds: Int = 2 * 3600 + 30 * 60
    private(set) var configuredTotalSeconds: Int = 2 * 3600 + 30 * 60

    var elapsedSeconds: Int {
        let remaining = (hours * 3600) + (minutes * 60) + seconds
        return max(configuredTotalSeconds - remaining, 0)
    }

    func configure(hours: Int, minutes: Int, seconds: Int = 0) {
        pause()
        showFinishSession = false
        sessionId = UUID()   // fresh id for this session

        let clampedHours = min(max(hours, 0), 23)
        let clampedMinutes = min(max(minutes, 0), 59)
        let clampedSeconds = min(max(seconds, 0), 59)

        self.hours = clampedHours
        self.minutes = clampedMinutes
        self.seconds = clampedSeconds
        totalSeconds = (clampedHours * 3600) + (clampedMinutes * 60) + clampedSeconds
        configuredTotalSeconds = totalSeconds
    }

    func returnToHome() {
        pause()
        showFinishSession = false
        requestReturnToHome = true
    }

    func start() {
        guard totalSeconds > 0, timer == nil else { return }

        showFinishSession = false
        isRunning = true
        let newTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func reset(hours: Int = 2, minutes: Int = 30) {
        configure(hours: hours, minutes: minutes)
    }

    private func tick() {
        guard totalSeconds > 0 else {
            finish()
            return
        }

        totalSeconds -= 1

        if totalSeconds <= 0 {
            finish()
        } else {
            updateDisplay()
        }
    }

    private func updateDisplay() {
        hours = totalSeconds / 3600
        minutes = (totalSeconds % 3600) / 60
        seconds = totalSeconds % 60
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        updateDisplay()
        showFinishSession = true
    }
}
