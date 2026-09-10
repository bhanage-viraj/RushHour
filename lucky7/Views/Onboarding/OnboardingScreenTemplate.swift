//
//  OnboardingScreenTemplate.swift
//  lucky7
//

import SwiftUI

struct OnboardingScreenTemplate<Content: View>: View {
    let step: Int
    let buttonText: String?
    var isDisabled: Bool?
    var onContinue: () -> Void
    var onBack: (() -> Void)?
    @ViewBuilder private var content: () -> Content

    init(
        step: Int,
        buttonText: String? = nil,
        isDisabled: Bool? = false,
        onContinue: @escaping () -> Void = {},
        onBack: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.step = step
        self.buttonText = buttonText
        self.isDisabled = isDisabled
        self.onContinue = onContinue
        self.onBack = onBack
        self.content = content
    }
    
    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressHeader(step: step, onBack: onBack)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            ScrollView {
                content()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
                    .padding(.top, 36)
                    .padding(.bottom, 28)
                    .background {
                        // The content determines the card height, even when it
                        // is taller than the iPhone compatibility window.
                        Image("OnboardingContainer")
                            .resizable(capInsets: EdgeInsets(top: 32, leading: 32, bottom: 32, trailing: 32))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)


            Button(action: onContinue) {
                Text(buttonText ?? "CONTINUE")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Capsule().fill(Color.black))
            }
            .disabled(isDisabled ?? false)
            .opacity(isDisabled ?? false ? 0.5 : 1)
            .accessibilityLabel(buttonText ?? "Continue")
            .accessibilityHint("Step \(step) of \(OnboardingProgressHeader.totalSteps)")
            .accessibilityInputLabels(["continue", "next"])
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .background(Color("CanvasBlue").ignoresSafeArea(edges: .bottom))
        }
        .background {
            Color("CanvasBlue")
                .overlay(alignment: .bottom) {
                    Image("PatternBackground")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 250)
                        .clipped()
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
    }


}

/// Shared by the explanation screens and the final app-selection step.
struct OnboardingProgressHeader: View {
    static let totalSteps = 4
    let step: Int
    var onBack: (() -> Void)?
    @State private var animated = false

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityInputLabels(["back", "previous"])
            }

            HStack(spacing: 8) {
                ForEach(1...Self.totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .overlay {
                            Capsule()
                                .fill(.white)
                                .scaleEffect(x: index < step || (index == step && animated) ? 1 : 0,
                                             y: 1, anchor: .leading)
                        }
                        .frame(height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Onboarding progress")
            .accessibilityValue("Step \(step) of \(Self.totalSteps)")
            .onAppear {
                withAnimation(.easeInOut(duration: 1.3)) { animated = true }
            }
        }
    }
}

extension OnboardingScreenTemplate where Content == EmptyView {
    init(
        step: Int,
        buttonText: String? = nil,
        isDisabled: Bool? = false,
        onContinue: @escaping () -> Void = {},
        onBack: (() -> Void)? = nil
    ) {
        self.init(
            step: step,
            buttonText: buttonText,
            isDisabled: isDisabled,
            onContinue: onContinue,
            onBack: onBack,
            content: { EmptyView() }
        )
    }
}

#Preview("Flow") {
    OnBoarding1()
}

#Preview("Step 1") {
    OnboardingScreenTemplate(step: 1)
}

#Preview("Step 2") {
    OnboardingScreenTemplate(step: 2, onBack: {})
}

#Preview("Step 3") {
    OnboardingScreenTemplate(step: 3)
}
