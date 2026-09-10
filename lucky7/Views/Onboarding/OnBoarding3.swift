//
//  OnBoarding3.swift
//  lucky7
//

import SwiftUI
import FamilyControls

/// Step 3 — explain WHY Screen Time is needed, then ask for it.
///
/// This order is deliberate (the old flow was rejected by App Review): the
/// screen only explains and offers CONTINUE. Tapping CONTINUE is what raises
/// the system "Rush Hour Would Like to Access Screen Time" prompt. Only once
/// the user approves do we move to `OnBoarding4`, where they pick apps.
/// No picker and no permission request happen behind the user's back here.
struct OnBoarding3: View {
    @Binding var path: [Int]

    @State private var isRequestingAuth = false
    @State private var authError: String?

    var body: some View {
        OnboardingScreenTemplate(
            step: 3,
            isDisabled: isRequestingAuth,
            onContinue: continueTapped
        ) {
            mainContent
        }
        .navigationBarBackButtonHidden()
        .alert(
            "Screen Time access needed",
            isPresented: Binding(
                get: { authError != nil },
                set: { if !$0 { authError = nil } }
            ),
            presenting: authError
        ) { _ in
            Button("Open Settings") {
                openSettings()
                authError = nil
            }
            Button("Not now", role: .cancel) { authError = nil }
        } message: { error in
            Text(error)
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("Lock Out Your Distractions")
                    .font(.custom("Special Gothic Expanded One", size: 32))
                Color.clear
                    .frame(height: 16)
                Text("Screen Time access lets Rush Hour block the apps you choose during focus sessions.")
                    .font(.system(size: 17))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Image(.blockedAppsMainScreen)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: .infinity, alignment: .center)
                .layoutPriority(1)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func advance() {
        path.append(4)
    }

    #if os(iOS)
    private func continueTapped() {
        Task { await requestScreenTimeThenAdvance() }
    }

    @MainActor
    private func requestScreenTimeThenAdvance() async {
        // Already approved (user stepped back then forward again) → just move on;
        // iOS would not show its prompt a second time anyway.
        guard !ScreenTimeMonitorService.isAuthorized else {
            advance()
            return
        }

        isRequestingAuth = true
        defer { isRequestingAuth = false }

        do {
            try await ScreenTimeMonitorService.requestAuthorization()
            advance()
        } catch {
            // App blocking requires authorization. Explain the failure and
            // offer Settings without automatically opening another prompt.
            authError = error.localizedDescription
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    #else
    private func continueTapped() { advance() }
    private func openSettings() {}
    #endif
}

#Preview {
    NavigationStack {
        OnBoarding3(path: .constant([2, 3]))
    }
    .environmentObject(FocusViewModel())
}
