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
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 402,
                            (geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom) / 874)
            VStack(spacing: 8 * scale) {
                titleCard(scale: scale)
                pickerCard

                VStack(spacing: 14 * scale) {
                    Text(footerText)
                        .font(.system(size: 16 * scale))
                        .foregroundStyle(.white)
                    continueButton
                        .frame(height: 56 * scale)
                }
                .padding(.top, 12 * scale)
                .padding(.bottom, 13 * scale)
            }
            .padding(.horizontal, 24 * scale)
        }
        .background { OnboardingBackground() }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    // MARK: - Chrome

    private func titleCard(scale: CGFloat) -> some View {
        PatternBorderedCard(edges: [.top], cornerRadius: 24 * scale, stripHeight: 9.861 * scale) {
            VStack(spacing: 8 * scale) {
                Text("Select \(Self.minimumSelections) Apps\nthat distract you")
                    .font(.custom("Special Gothic Expanded One", size: 24 * scale))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 64 * scale)

                Text("You can change it later in settings")
                    .font(.system(size: 15 * scale))
                    .foregroundStyle(Color(white: 38 / 255).opacity(0.8))
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 20 * scale)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 23 * scale)
            .padding(.top, 50 * scale)
            .padding(.bottom, 38 * scale)
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
            .environment(\.colorScheme, .light)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.black, lineWidth: 2)
            )
            .accessibilityLabel("App and category picker")
        #else
        // FamilyControls is iOS-only; keep the layout compiling elsewhere.
        RoundedRectangle(cornerRadius: 24)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.black, lineWidth: 2)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    private var continueButton: some View {
        Button(action: finishOnboarding) {
            Text("CONTINUE")
                .font(.custom("Special Gothic Expanded One", size: 14))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 52 / 255), in: Capsule())
                .opacity(hasEnoughSelected ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!hasEnoughSelected)
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
