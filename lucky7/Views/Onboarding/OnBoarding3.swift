//
//  OnBoarding3.swift
//  lucky7
//

import SwiftUI
import FamilyControls

struct OnBoarding3: View {
    @Binding var path: [Int]
    var onComplete: () -> Void = {}
    
    #if os(iOS)
    @EnvironmentObject private var focusController: FocusViewModel
    #endif
    
    @State private var showPicker = false
    @State private var isRequestingAuth = false
    @State private var authError: String?
    
    let onDone: () -> Void
    
    var body: some View {
        OnboardingScreenTemplate(
            step: 3,
            onContinue: finishOnboarding,
            onSkip: finishOnboarding,
            onBack: goBack,
            onGoPrevious: goBack
        ) {
            mainContent
        }
        .navigationBarBackButtonHidden()
        #if os(iOS)
        .familyActivityPicker(isPresented: $showPicker, selection: focusController.selectionBinding)
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
    
    private func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("Lock Out Your Distractions")
                    .font(.custom("Special Gothic Expanded One", size: 32))
                Color.clear
                    .frame(height: 16)
                Text("Select the apps that distracts. We'll remind you to stay focused when it matters most.")
                    .font(.system(size: 17))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            
            Image(.blockedAppsMainScreen)
                .resizable()
                .scaledToFit()
                .frame(height: 280)
                .layoutPriority(1)
                .padding()
            
            pickerCard
            
            Text("Optional — you can set this up later in settings")
                .font(.system(size: 13))
                .foregroundStyle(.black.opacity(0.5))
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    @ViewBuilder
    private var pickerCard: some View {
        #if os(iOS)
        Button {
            Task { await presentPicker() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: focusController.hasSelection ? "lock.shield.fill" : "lock.shield")
                    .font(.title3)
                    .foregroundStyle(Color(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(focusController.hasSelection ? "Apps locked" : "Pick apps to block")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(focusController.hasSelection ? focusController.selectionSummary : "Tap to choose")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                Spacer()
                if isRequestingAuth {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }
            .padding(16)
            .background(.black, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(isRequestingAuth)
        #endif
    }
    
    private func finishOnboarding() {
        #if os(iOS)
        if focusController.hasSelection {
            focusController.persistSelection()
        }
        #endif
        onDone()
    }
    
    #if os(iOS)
    @MainActor
    private func presentPicker() async {
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
    NavigationStack {
        OnBoarding3(path: .constant([2, 3]), onDone: {})
    }
    .environmentObject(FocusViewModel())
}
