//
//  ScreenDimmer.swift
//  lucky7
//

import UIKit

/// Drops the hardware screen brightness while a recording session runs so long
/// sessions don't drain the battery, then restores the user's own level.
/// Unlike a dark overlay, lowering `UIScreen.brightness` turns the backlight
/// down for real — that's what actually saves power.
@MainActor
enum ScreenDimmer {
    /// Low enough to save battery, high enough that the timer stays readable.
    static let dimmedBrightness: CGFloat = 0.1

    /// Grace period after arming / the last touch before the screen dims,
    /// so the user can read the screen and reach the controls first.
    static let idleSecondsBeforeDim: TimeInterval = 5

    private(set) static var isActive = false
    private static var isDimmed = false
    private static var userBrightness: CGFloat = 0.5
    private static var pendingDim: Task<Void, Never>?
    private static var fadeTask: Task<Void, Never>?

    /// Arms the dimmer while recording runs; disarming restores the user's brightness.
    static func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        pendingDim?.cancel()
        if active {
            scheduleDim()
        } else {
            undim()
        }
    }

    /// Call on any touch: brings brightness back and restarts the idle countdown.
    static func touch() {
        guard isActive else { return }
        undim()
        scheduleDim()
    }

    /// Always call when tearing down a session so the screen never stays dim.
    static func release() {
        setActive(false)
    }

    private static func scheduleDim() {
        pendingDim?.cancel()
        pendingDim = Task {
            try? await Task.sleep(nanoseconds: UInt64(idleSecondsBeforeDim * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dim()
        }
    }

    private static func dim() {
        guard isActive, !isDimmed, let screen else { return }
        userBrightness = screen.brightness
        isDimmed = true
        fade(to: min(dimmedBrightness, userBrightness), on: screen)
    }

    private static func undim() {
        guard isDimmed, let screen else { return }
        isDimmed = false
        fade(to: userBrightness, on: screen)
    }

    /// `UIScreen.brightness` has no animation API — step it over ~0.3 s so the
    /// change reads as a fade rather than a glitch.
    private static func fade(to target: CGFloat, on screen: UIScreen) {
        fadeTask?.cancel()
        fadeTask = Task {
            let start = screen.brightness
            let steps = 12
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: 25_000_000)
                guard !Task.isCancelled else { return }
                let progress = CGFloat(step) / CGFloat(steps)
                screen.brightness = start + (target - start) * progress
            }
        }
    }

    /// Brightness must be set on the screen of the foreground scene.
    private static var screen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }
}
