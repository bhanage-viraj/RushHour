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
    var onSkip: (() -> Void)?
    var onBack: (() -> Void)?
    var onGoPrevious: (() -> Void)?
    var onGoNext: (() -> Void)?
    @ViewBuilder private var content: () -> Content

    init(
        step: Int,
        buttonText: String? = nil,
        isDisabled: Bool? = false,
        onContinue: @escaping () -> Void = {},
        onSkip: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        onGoPrevious: (() -> Void)? = nil,
        onGoNext: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.step = step
        self.buttonText = buttonText
        self.isDisabled = isDisabled
        self.onContinue = onContinue
        self.onSkip = onSkip
        self.onBack = onBack
        self.onGoPrevious = onGoPrevious
        self.onGoNext = onGoNext
        self.content = content
    }
    
    @State private var animated = false
    @State private var maskWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private func animate() {
        maskWidth = 0
        withAnimation(.easeInOut(duration: 1.3)) {
            maskWidth = containerWidth
        }
    }
    
    @State private var visible = false
    
    var body: some View {
        GeometryReader { geometry in
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

                VStack(spacing: 0) {
                    progressHeader
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                    Spacer(minLength: 20)

                    Image("OnboardingContainer")
                        .resizable()
                        .scaledToFit()
                        .accessibilityDecorative()
                        .overlay {
                            content()
                                .padding(.horizontal, 28)
                                .padding(.top, 36)
                                .padding(.bottom, 28)
                        }
                        .padding(.horizontal, 20)

                    Spacer(minLength: 20)

                    VStack(spacing: 12) {
                        if let onSkip {
                            Button(action: onSkip) {
                                Text("Skip for now")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.black.opacity(0.55))
                            }
                            .accessibilityLabel("Skip for now")
                            .accessibilityHint("Continue without blocking apps")
                        }

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
                        .accessibilityHint("Step \(step) of 3")
                        .accessibilityInputLabels(["continue", "next"])
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }

                HStack(spacing: 0) {
                    sideTapZone(action: onGoPrevious)
                        .frame(width: sideTapWidth(for: geometry.size.width))
                        .accessibilityHidden(true)

                    Spacer()
                        .allowsHitTesting(false)

                    sideTapZone(action: onGoNext)
                        .frame(width: sideTapWidth(for: geometry.size.width))
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var progressHeader: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityInputLabels(["back", "previous"])
            }

            ZStack{
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { index in
                        Capsule()
                            .fill(Color.white.opacity(index <= step-1 ? 1 : 0.35))
                            .frame(height: 5)
                            .frame(maxWidth: .infinity)
                            .task {
                                try? await Task.sleep(for: .seconds(1.5))
                                withAnimation {
                                            visible = true
                                        }
                            }
                            
                    }
                }
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? Color.white : Color.clear)
                            .frame(height: 5)
                            .frame(maxWidth: .infinity)
                            .mask(alignment: .leading) {
                                Rectangle()
                                    .frame(width: maskWidth)
                            }
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            containerWidth = 120
                                            animate()
                                        }
                                }
                            )
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Onboarding progress")
            .accessibilityValue("Step \(step) of 3")
        }
    }

    private func sideTapZone(action: (() -> Void)?) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                action?()
            }
            .allowsHitTesting(action != nil)
    }

    private func sideTapWidth(for totalWidth: CGFloat) -> CGFloat {
        max(44, (totalWidth - 40) * 0.12)
    }
}

extension OnboardingScreenTemplate where Content == EmptyView {
    init(
        step: Int,
        buttonText: String? = nil,
        isDisabled: Bool? = false,
        onContinue: @escaping () -> Void = {},
        onSkip: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        onGoPrevious: (() -> Void)? = nil,
        onGoNext: (() -> Void)? = nil
    ) {
        self.init(
            step: step,
            buttonText: buttonText,
            isDisabled: isDisabled,
            onContinue: onContinue,
            onSkip: onSkip,
            onBack: onBack,
            onGoPrevious: onGoPrevious,
            onGoNext: onGoNext,
            content: { EmptyView() }
        )
    }
}

#Preview("Flow") {
    OnBoarding1()
}

#Preview("Step 1") {
    OnboardingScreenTemplate(step: 1, onGoNext: {})
}

#Preview("Step 2") {
    OnboardingScreenTemplate(step: 2, onBack: {}, onGoPrevious: {}, onGoNext: {})
}

#Preview("Step 3") {
    OnboardingScreenTemplate(step: 3, onBack: {}, onGoPrevious: {})
}
