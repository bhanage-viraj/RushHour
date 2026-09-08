//
//  OnBoarding4.swift
//  lucky7
//

import SwiftUI
#if os(iOS)
import FamilyControls
#endif

/// Step 4 — pick the distracting apps.
///
/// Reached only after the user approved Screen Time in `OnBoarding3`, because
/// `FamilyActivityPicker` shows nothing without that authorization.
///
/// Deliberately does NOT use `OnboardingScreenTemplate`:
/// - no progress bar and no back button — this is the commit point, the user
///   already granted Screen Time and there is nothing to go back to
/// - the title and the picker live in two SEPARATE cards, so the picker gets
///   the whole remaining height instead of sharing one padded container
/// - the picker sits flush inside its card (no padding) so more rows fit
///
/// CONTINUE stays disabled until `minimumSelections` things are picked.
struct OnBoarding4: View {
    let onDone: () -> Void

    /// Apps, categories and web domains each count as one pick.
    static let minimumSelections = 3

    #if os(iOS)
    @EnvironmentObject private var focusController: FocusViewModel
    #endif

    var body: some View {
        ZStack {
            background

            VStack(spacing: 12) {
                titleCard
                pickerCard

                Text(footerText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 4)

                continueButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Chrome

    private var background: some View {
        ZStack {
            Color("CanvasBlue")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                Image("PatternBackground")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .offset(y: 400)
            }
            .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }

    private var titleCard: some View {
        PatternBorderedCard(edges: [.top], cornerRadius: 28) {
            VStack(spacing: 6) {
                Text("Select \(Self.minimumSelections) Apps\nthat distract you")
                    .font(.custom("Special Gothic Expanded One", size: 26))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)

                Text("You can change it later in settings")
                    .font(.system(size: 15))
                    .foregroundStyle(.black.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 22)
        }
    }

    /// The system picker, flush inside its own card — no inner padding, so the
    /// rows use the full width and one extra row fits on screen.
    @ViewBuilder
    private var pickerCard: some View {
        #if os(iOS)
        // Bound straight to the @Published property, not FocusViewModel's
        // hand-rolled `selectionBinding` — a fresh Binding(get:set:) is built on
        // every render, and the picker can end up writing into a stale one.
        FamilyActivityPicker(selection: $focusController.selection)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.black, lineWidth: 2)
            )
            .accessibilityLabel("App and category picker")
        #else
        // FamilyControls is iOS-only; keep the layout compiling elsewhere.
        RoundedRectangle(cornerRadius: 28)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.black, lineWidth: 2)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    private var continueButton: some View {
        Button(action: finishOnboarding) {
            Text("CONTINUE")
                .font(.system(size: 16, weight: .heavy))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Capsule().fill(Color.black))
        }
        .disabled(!hasEnoughSelected)
        .opacity(hasEnoughSelected ? 1 : 0.5)
        .accessibilityLabel("Continue")
        .accessibilityHint(
            hasEnoughSelected
                ? "Finishes setup"
                : "Select at least \(Self.minimumSelections) apps first"
        )
        .accessibilityInputLabels(["continue", "next"])
    }

    // MARK: - Selection gate

    private var selectedCount: Int {
        #if os(iOS)
        focusController.selectedCount
        #else
        0
        #endif
    }

    private var hasEnoughSelected: Bool {
        selectedCount >= Self.minimumSelections
    }

    private var footerText: String {
        "\(selectedCount) App\(selectedCount == 1 ? "" : "s") Selected"
    }

    private func finishOnboarding() {
        guard hasEnoughSelected else { return }
        #if os(iOS)
        focusController.persistSelection()
        #endif
        onDone()
    }
}

#Preview {
    NavigationStack {
        OnBoarding4(onDone: {})
    }
    .environmentObject(FocusViewModel())
}
