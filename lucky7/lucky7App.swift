//
//  lucky7App.swift
//  lucky7
//
//  Created by Viraj Bhanage on 20/05/26.
//

import SwiftUI
import SwiftData
import UserNotifications
import ManagedSettings

@main
struct lucky7App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var focusController = FocusViewModel()
    @StateObject private var sessionTimer = SessionTimerViewModel()
    @StateObject private var sessionRecording = SessionRecordingViewModel()

    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: Session.self, Distraction.self, PeriodWrap.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Loading()
                .environmentObject(focusController)
                .environmentObject(sessionTimer)
                .environmentObject(sessionRecording)
                // No notification prompt on launch — it used to fire here and
                // landed on top of the first onboarding screen, asking before
                // the user knew what it was for. `RecordingPage` requests it at
                // the point it's actually needed (starting a session) instead.
                .task {
                    // Roll completed weeks/months into recap videos and prune old slices.
                    await WrapRollupService.rollUpIfNeeded(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}

extension Notification.Name {
    /// Posted when the shield-return notification is received/tapped, so the active screen
    /// re-checks for a pending break even if scenePhase is already .active.
    static let shieldReturnTapped = Notification.Name("rushhour.shieldReturnTapped")

    /// Posted when a screen wants the root TabView to jump back to the Home (Rush Hour) tab,
    /// e.g. closing Session Analytics opened from History.
    static let returnToHomeTab = Notification.Name("rushhour.returnToHomeTab")
}

// Registers as the notification delegate so the shield-return notification is an actual return
// path: it shows even in the foreground, and receiving/tapping it drives the pending-break check.
// Without this, tapping the fallback notification did nothing meaningful — the whole reason the
// shield buttons "didn't redirect."
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        RecordingDiagnostics.log("App launched diagnostics=\(RecordingDiagnostics.logURL.path)")
        SessionNotifications.cancelAwayNudges()
        return true
    }

    // Closing the app ends the session — lift the shield. Best-effort: iOS doesn't reliably call
    // this on a swipe-kill, so FocusViewModel.init()'s cold-launch clear is the backstop.
    func applicationWillTerminate(_ application: UIApplication) {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("rushhour.focus")).clearAllSettings()
        SharedJailbreakStore.endSession()
        SessionNotifications.cancelAwayNudges()
    }

    // Foreground delivery — show the banner AND drive the return.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // App is already in the foreground — drive the return silently; no stray banner.
        NotificationCenter.default.post(name: .shieldReturnTapped, object: nil)
        completionHandler([])
    }

    // Tap — bring the user back and drive the return.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(name: .shieldReturnTapped, object: nil)
        completionHandler()
    }
}
