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
            onContinue: continueTapped,
            onBack: { if !path.isEmpty { path.removeLast() } }
        ) { scale in
            mainContent(scale: scale)
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

    private func mainContent(scale: CGFloat) -> some View {
        VStack(spacing: 24 * scale) {
            VStack(spacing: 16 * scale) {
                OnboardingTitle(text: "Lock Out Your\nDistractions", scale: scale)

                Text("We'll remind you to stay focused\nwhen it matters most.")
                    .font(.system(size: 17 * scale))
                    .foregroundStyle(Color(white: 38 / 255).opacity(0.8))
                    .lineSpacing(2 * scale)
                    .frame(height: 44 * scale)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                Image(.blockedAppsMainScreen)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 277.47 * scale, height: 318.56 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 26.188 * scale))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26.188 * scale)
                            .strokeBorder(.black, lineWidth: 0.671 * scale)
                    }
                    .shadow(color: .black, radius: 0, x: 0, y: 2.686 * scale)
                    .offset(x: -0.65 * scale)

                Image(systemName: "lock.fill")
                    .resizable()
                    .font(.system(size: 27.342 * scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 18.8 * scale, height: 26.7 * scale)
                    .rotationEffect(.degrees(9.1))
                    .offset(y: -0.48 * scale)
                    .frame(width: 79.24 * scale, height: 79.13 * scale)
                    .background {
                        Canvas { context, size in
                            let dot = context.resolve(Image("OnboardingLockDot"))
                            let diameter = 9 * 0.06564462184906006 * scale
                            // Figma expresses the pattern gap relative to the dot size.
                            let spacing = diameter * (1 + 0.97)
                            let columns = Int(ceil(size.width / spacing / 2))
                            let rows = Int(ceil(size.height / spacing / 2))
                            for row in -rows...rows {
                                for column in -columns...columns {
                                    context.draw(dot, in: CGRect(
                                        x: size.width / 2 + CGFloat(column) * spacing - diameter / 2,
                                        y: size.height / 2 + CGFloat(row) * spacing - diameter / 2,
                                        width: diameter, height: diameter
                                    ))
                                }
                            }
                        }
                        .opacity(0.2)
                        .background(Color(red: 25 / 255, green: 135 / 255, blue: 237 / 255))
                        .clipShape(Circle())
                    }
                    .overlay { Circle().strokeBorder(.black, lineWidth: 0.525 * scale) }
                    .compositingGroup()
                    .shadow(color: .black, radius: 0, x: 0, y: 2.293 * scale)
                    .position(x: 262.77 * scale, y: 296.18 * scale)
            }
            .frame(width: 302 * scale, height: 348 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
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
