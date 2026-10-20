//
//  SessionConfirmSheet.swift
//  lucky7
//

import SwiftUI

/// Bottom confirmation card over a dimmed backdrop: a red-outlined destructive
/// action next to a black CANCEL. Used by "End Session"; generic so other
/// destructive confirmations can share the same look.
struct SessionConfirmSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    let confirmAccessibilityLabel: String
    let confirmHint: String
    let confirmInputLabels: [String]
    let cancelHint: String
    let closeHint: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 38, height: 5)
                    .padding(.top, 10)

                HStack {
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.55))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .accessibilityHint(closeHint)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)

                Text(title)
                    .font(.custom("Special Gothic Expanded One", size: 22))
                    .foregroundStyle(.black)
                    .padding(.top, 2)

                Text(message)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                HStack(spacing: 14) {
                    Button(action: onConfirm) {
                        Text(confirmTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .overlay(Capsule().stroke(Color.red, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(confirmAccessibilityLabel)
                    .accessibilityHint(confirmHint)
                    .accessibilityInputLabels(confirmInputLabels)

                    Button(action: onCancel) {
                        Text("CANCEL")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                    .accessibilityHint(cancelHint)
                    .accessibilityInputLabels(["cancel", "keep going", "go back"])
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 22)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}
