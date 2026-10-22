//
//  loading.swift
//  lucky7
//

import SwiftUI
import Combine

struct Loading: View {
    @AppStorage("didShowAppBlockOnboarding") private var didShowOnboarding = false
    @EnvironmentObject private var pendingSiriSession: PendingSiriSession
    @State private var pulse = false
    @State private var showHome = false
    @State private var selectedTab = 0
    @StateObject private var tabBarVisibility = TabBarVisibility()
    @State private var pendingRecoverySession: PendingRecoverySession?
    @State private var recoveryCoverActive = SessionEndRecovery.pendingSessionID != nil

    private struct PendingRecoverySession: Identifiable {
        let id: UUID
    }

    init() {
        // Dark tab bar only — without forcing the whole app into dark mode.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(white: 0.10, alpha: 1.0)

        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(white: 1.0, alpha: 0.55)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(white: 1.0, alpha: 0.55)]
        item.selected.iconColor = .white
        item.selected.titleTextAttributes = [.foregroundColor: UIColor.white]

        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {

        if showHome {
            // jailbreak: gate the app behind the app-block onboarding the first launch
            if didShowOnboarding {
                ZStack(alignment: .bottom) {
                    // Both screens stay alive so each keeps its own navigation
                    // stack and scroll state; only the selected one is shown.
                    HomePage(isActiveTab: selectedTab == 0, isRecoveryPresented: recoveryCoverActive)
                        .opacity(selectedTab == 0 ? 1 : 0)
                        .allowsHitTesting(selectedTab == 0)
                        .zIndex(selectedTab == 0 ? 1 : 0)

                    MonitorScreen()
                        .opacity(selectedTab == 1 ? 1 : 0)
                        .allowsHitTesting(selectedTab == 1)
                        .zIndex(selectedTab == 1 ? 1 : 0)

                    if !tabBarVisibility.isHidden {
                        FloatingTabBar(selection: $selectedTab)
                            .padding(.bottom, 0)
                            .zIndex(2)
                            .transition(.opacity)
                    }
                }
                .environment(\.tabBarVisibility, tabBarVisibility)
                .onAppear {
                    UIApplication.shared.enableTapToDismissKeyboard()
                    loadPendingRecoveryIfNeeded()
                    if pendingSiriSession.hasPending {
                        selectedTab = 0
                    }
                }
                .onChange(of: pendingSiriSession.totalSeconds) { _, seconds in
                    // Siri start while already on Home — jump to the Rush Hour tab.
                    if seconds != nil {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 0 }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .returnToMySessionsTab)) { _ in
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 1 }
                }
                .fullScreenCover(item: $pendingRecoverySession, onDismiss: {
                    recoveryCoverActive = false
                    if pendingSiriSession.hasPending { selectedTab = 0 }
                }) { recovery in
                    SessionDetails(
                        sessionId: recovery.id,
                        onSave: {
                            SessionEndRecovery.clear(recovery.id)
                            pendingRecoverySession = nil
                            selectedTab = 1
                        },
                        onFlowComplete: {
                            SessionEndRecovery.clear(recovery.id)
                            pendingRecoverySession = nil
                            selectedTab = 1
                        }
                    )
                }
            } else {
//                AppBlockOnboardingScreen(onDone: {
//                    didShowOnboarding = true
//                })
                OnBoarding1(onComplete: {
                    didShowOnboarding = true
                })
            }
        } else {

            ZStack {

                Color.blue
                    .ignoresSafeArea()

                Image("load6")
                    .accessibilityDecorative()

                Image("load7")
                    .accessibilityDecorative()

                Image("load8")
                    .accessibilityDecorative()

                // Pulse Animation
                Image("Rushhourload")
                    .scaleEffect(pulse ? 1.08 : 0.92)
                    .opacity(pulse ? 1 : 0.75)
                    .animation(
                        .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true),
                        value: pulse
                    )
                    .accessibilityDecorative()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rush Hour")
            .accessibilityValue("Loading")
            .onAppear {

                // Start pulse animation
                pulse = true

                // Tap anywhere outside a text field to dismiss the keyboard.
                DispatchQueue.main.async {
                    UIApplication.shared.enableTapToDismissKeyboard()
                }

                // Siri / Shortcuts: skip the splash and go straight to Home so recording
                // can start without waiting on the 3s intro.
                if pendingSiriSession.hasPending {
                    showHome = true
                    selectedTab = 0
                    // Don't start behind onboarding — drop the request until setup is done.
                    if !didShowOnboarding {
                        pendingSiriSession.clear()
                    }
                    loadPendingRecoveryIfNeeded()
                    return
                }

                // Navigate after 3 sec
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeInOut) {
                        showHome = true
                    }
                    loadPendingRecoveryIfNeeded()
                }
            }
            .onChange(of: pendingSiriSession.totalSeconds) { _, seconds in
                // Intent fired while still on splash (or after splash timer started).
                guard seconds != nil, !showHome else { return }
                showHome = true
                selectedTab = 0
                if !didShowOnboarding {
                    pendingSiriSession.clear()
                }
            }
        }
    }

    private func loadPendingRecoveryIfNeeded() {
        guard didShowOnboarding, pendingRecoverySession == nil else { return }
        guard let id = SessionEndRecovery.pendingSessionID else { return }
        RecordingDiagnostics.log("Loading present pending recovery session=\(id)")
        recoveryCoverActive = true
        pendingRecoverySession = PendingRecoverySession(id: id)
    }
}

// MARK: - Floating tab bar

/// Custom pill-shaped tab bar that floats above the content. The selected tab is a
/// filled black circle; unselected tabs show a bare icon. Icons are placeholders —
/// swap them as needed.
struct FloatingTabBar: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            tabButton(index: 0, systemImage: "timer")
            tabButton(index: 1, systemImage: "calendar.badge.clock")
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.5)))
                .overlay(Capsule().strokeBorder(Color.black, lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 1.3)
        }
    }

    private func tabButton(index: Int, systemImage: String) -> some View {
        let titles = ["Home", "Sessions"]
        let isSelected = selection == index
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selection = index }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(selection == index ? .white : .black)
                .frame(width: 64, height: 48)
                .background(
                    Capsule().fill(selection == index ? Color(red: 9 / 255, green: 9 / 255, blue: 9 / 255) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(titles[index])
        .accessibilityHint(isSelected ? "Selected tab" : "Switch to \(titles[index]) tab")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityInputLabels([titles[index].lowercased(), index == 0 ? "home" : "sessions", "tab"])
    }
}

// MARK: - Floating tab bar visibility

/// Tracks how many on-screen views want the floating tab bar hidden. A counter
/// (not a Bool) keeps push/pop transitions flicker-free when a new screen
/// appears before the previous one disappears.
final class TabBarVisibility: ObservableObject {
    @Published private var hideCount = 0
    var isHidden: Bool { hideCount > 0 }
    func push() { hideCount += 1 }
    func pop() { hideCount = max(0, hideCount - 1) }
}

private struct TabBarVisibilityKey: EnvironmentKey {
    static let defaultValue = TabBarVisibility()
}

extension EnvironmentValues {
    var tabBarVisibility: TabBarVisibility {
        get { self[TabBarVisibilityKey.self] }
        set { self[TabBarVisibilityKey.self] = newValue }
    }
}

extension View {
    /// Hides the floating tab bar while this view is on screen. Apply to pushed
    /// detail screens so the bar only shows on Home / Monitor (and Search).
    func hidesFloatingTabBar() -> some View {
        modifier(HidesFloatingTabBar())
    }
}

private struct HidesFloatingTabBar: ViewModifier {
    @Environment(\.tabBarVisibility) private var visibility
    func body(content: Content) -> some View {
        content
            .onAppear { withAnimation(.easeInOut(duration: 0.2)) { visibility.push() } }
            .onDisappear { withAnimation(.easeInOut(duration: 0.2)) { visibility.pop() } }
    }
}

#Preview {
    Loading()
        .environmentObject(FocusViewModel())
        .environmentObject(SessionTimerViewModel())
        .environmentObject(SessionRecordingViewModel())
        .environmentObject(PendingSiriSession.shared)
}
