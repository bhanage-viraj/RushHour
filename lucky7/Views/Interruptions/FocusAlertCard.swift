//
//  FocusAlertCard.swift
//  lucky7
//
//  Created by Andrian on 31/05/26.
//

import SwiftUI
struct FocusAlertCard: View {
    let title: String
    let message: String
    var buttonTitle: String = "GOT IT"
    var autoDismiss: Bool = false
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var leaving = false

    var body: some View {
        ZStack {
            // dim whatever's behind the card
            Color.black.opacity(appeared && !leaving ? 0.4 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            card
                .scaleEffect(appeared ? 1 : 0.9, anchor: .center)
                .opacity(appeared && !leaving ? 1 : 0)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: appeared)
        .onAppear {
            appeared = true
            AccessibilitySupport.announce("\(title). \(message)")
            guard autoDismiss else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { dismiss() }
        }
    }

    private func dismiss() {
        guard !leaving else { return }
        withAnimation(.easeOut(duration: 0.2)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
    }

    private var card: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.custom("SpecialGothicExpandedOne-Regular", size: 22))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 17))
                    .foregroundStyle(.black.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { dismiss() } label: {
                Text(buttonTitle)
                    .font(.custom("SpecialGothicExpandedOne-Regular", size: 14))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(.black))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(buttonTitle)
            .accessibilityHint("Dismisses this alert")
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .frame(maxWidth: 354)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.black, lineWidth: 2))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        FocusAlertCard(
            title: "One break at a time",
            message: "An app is already unlocked. You can unlock another app after returning to your focus session.",
            onDismiss: {}
        )
    }
}
