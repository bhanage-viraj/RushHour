//
//  SettingsScreen.swift
//  lucky7
//

import SwiftUI
#if os(iOS)
import FamilyControls
#endif

struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @EnvironmentObject private var focusController: FocusViewModel
    #endif

    @State private var showPicker = false
    @State private var isRequestingAuth = false
    @State private var authError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color("CanvasBlue").ignoresSafeArea()
                Image("PatternBackground")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .accessibilityDecorative()

                VStack(spacing: 0) {
                    header

                    settingsCard
                        .padding(.horizontal, 20)
                        .padding(.top, 28)

                    Spacer()
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            #if os(iOS)
            .familyActivityPicker(isPresented: $showPicker, selection: focusController.selectionBinding)
            .onChange(of: showPicker) { _, presented in
                if !presented { focusController.persistSelection() }   // save when the picker closes
            }
            #endif
            .alert(
                "Screen Time access needed",
                isPresented: .constant(authError != nil),
                presenting: authError
            ) { _ in
                Button("OK") { authError = nil }
            } message: { error in
                Text(error)
            }
        }
    }

    private var header: some View {
        ZStack {
            Text("Settings")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Back")
                .accessibilityInputLabels(["back", "close settings"])
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var settingsCard: some View {
        PatternBorderedCard(edges: [], cornerRadius: 16) {
            VStack(spacing: 0) {
                Button {
                    #if os(iOS)
                    Task { await openBlockedApps() }
                    #endif
                } label: {
                    row(icon: "lock.fill", title: "BLOCKED APPS")
                }
                .buttonStyle(.plain)
                .disabled(isRequestingAuth)
                .accessibilityLabel("Blocked apps")
                .accessibilityHint("Choose which apps to block during focus sessions")
                .accessibilityInputLabels(["blocked apps", "app blocking", "block apps"])

                Divider().padding(.horizontal, 16)

                NavigationLink {
                    AboutScreen()
                } label: {
                    row(icon: "info.circle", title: "ABOUT RUSH HOUR")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About Rush Hour")
                .accessibilityHint("App information and version")

                Divider().padding(.horizontal, 16)

                NavigationLink {
                    PrivacyPolicyScreen()
                } label: {
                    row(icon: "info.circle", title: "PRIVACY POLICY")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Privacy policy")
                .accessibilityHint("Read how Rush Hour handles your information")
            }
        }
    }

    private func row(icon: String, title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 26)

            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black.opacity(0.5))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }

    #if os(iOS)
    // Same flow the onboarding "pick apps to block" step uses.
    @MainActor
    private func openBlockedApps() async {
        if !ScreenTimeMonitorService.isAuthorized {
            isRequestingAuth = true
            defer { isRequestingAuth = false }
            do {
                try await ScreenTimeMonitorService.requestAuthorization()
            } catch {
                authError = error.localizedDescription
                return
            }
        }
        showPicker = true
    }
    #endif
}

#Preview {
    SettingsScreen()
        .environmentObject(FocusViewModel())
}
