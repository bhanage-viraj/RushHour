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
    @ViewBuilder private var content: (CGFloat) -> Content

    init(
        step: Int,
        buttonText: String? = nil,
        isDisabled: Bool? = false,
        onContinue: @escaping () -> Void = {},
        onBack: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (CGFloat) -> Content
    ) {
        self.step = step
        self.buttonText = buttonText
        self.isDisabled = isDisabled
        self.onContinue = onContinue
        self.onBack = onBack
        self.content = content
    }
    
    var body: some View {
        GeometryReader { geometry in
            let fullHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let scale = min(geometry.size.width / 402, fullHeight / 874)

            VStack(spacing: 0) {
                OnboardingProgressHeader(step: step, onBack: onBack, scale: scale)
                    .frame(height: 32 * scale)
                    .padding(.bottom, (step == 1 ? 10 : 13) * scale)

                PatternBorderedCard(edges: [.top], cornerRadius: 24 * scale, stripHeight: 10 * scale) {
                    content(scale)
                        .padding(.horizontal, 23 * scale)
                        .padding(.top, 48 * scale)
                        .padding(.bottom, (step == 3 ? 24 : step == 2 ? 33 : 48) * scale)
                        .frame(height: 660 * scale)
                }

                Button(action: onContinue) {
                    Text(buttonText ?? "CONTINUE")
                        .font(.custom("Special Gothic Expanded One", size: 14 * scale))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(44, 56 * scale))
                        .background(Color(white: 52 / 255), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isDisabled ?? false)
                .opacity(isDisabled ?? false ? 0.5 : 1)
                .accessibilityLabel(buttonText ?? "Continue")
                .accessibilityHint("Step \(step) of \(OnboardingProgressHeader.totalSteps)")
                .accessibilityInputLabels(["continue", "next"])
                .padding(.top, 14 * scale)
            }
            .padding(.horizontal, 24 * scale)
            .padding(.top, 61 * scale - geometry.safeAreaInsets.top)
        }
        .background { OnboardingBackground() }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
    }
}

struct OnboardingTitle: View {
    let text: String
    let scale: CGFloat

    var body: some View {
        // The font's default line height is taller than Figma's 34-point title lines.
        VStack(spacing: 0) {
            ForEach(text.components(separatedBy: "\n"), id: \.self) { line in
                Text(line)
                    .frame(height: 34 * scale)
            }
        }
        .font(.custom("Special Gothic Expanded One", size: 28 * scale))
        .foregroundStyle(.black)
    }
}

struct OnboardingBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 402, geometry.size.height / 874)
            Color(red: 0, green: 96 / 255, blue: 190 / 255)
                .overlay(alignment: .bottom) {
                    Image("AppSelectionPattern")
                        .resizable()
                        .frame(width: 1276 * scale, height: 1054 * scale)
                        .offset(x: 2 * scale)
                        .frame(width: geometry.size.width, height: 463 * scale, alignment: .top)
                        .clipped()
                }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct OnboardingProgressHeader: View {
    static let totalSteps = 3
    let step: Int
    var onBack: (() -> Void)?
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 8 * scale) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16 * scale, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 32 * scale, height: 32 * scale)
                .accessibilityLabel("Back")
                .accessibilityInputLabels(["back", "previous"])
            }

            HStack(spacing: 8 * scale) {
                ForEach(1...Self.totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(index <= step ? 1 : 0.3))
                        .frame(height: 4 * scale)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Onboarding progress")
            .accessibilityValue("Step \(step) of \(Self.totalSteps)")
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
            content: { _ in EmptyView() }
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
