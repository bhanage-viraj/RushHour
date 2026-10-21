//
//  SessionConfirmSheet.swift
//  lucky7
//

import SwiftUI

/// Bottom confirmation card over a dimmed backdrop: a red-outlined destructive
/// action next to a black CANCEL. Shared by End Session and Discard Session.
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
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)

            VStack(spacing: 24) {
                Capsule()
                    .fill(Color("SessionDetailsBlack80").opacity(0.4))
                    .frame(width: 48, height: 5)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.custom("Special Gothic Expanded One", size: 22))
                        .frame(minHeight: 28)

                    Text(message)
                        .font(.system(size: 17, weight: .regular))
                        .lineSpacing(2)
                        .frame(minHeight: 44)
                }
                .foregroundStyle(Color.black.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button(action: onConfirm) {
                        Text(confirmTitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(Color("SessionDetailsRed"))
                            .background(.white, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color("SessionDetailsRed"), lineWidth: 1))
                    }
                    .accessibilityLabel(confirmAccessibilityLabel)
                    .accessibilityHint(confirmHint)
                    .accessibilityInputLabels(confirmInputLabels)

                    Button(action: onCancel) {
                        Text("CANCEL")
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(.white)
                            .background(Color("SessionDetailsBlack"), in: Capsule())
                    }
                    .accessibilityLabel("Cancel")
                    .accessibilityHint(cancelHint)
                    .accessibilityInputLabels(["cancel", "keep going", "go back"])
                }
                .font(.custom("Special Gothic Expanded One", size: 14))
                .multilineTextAlignment(.center)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 450)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.black, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color("SessionDetailsBlack80"))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .padding(.trailing, 6)
                .accessibilityLabel("Close")
                .accessibilityHint(closeHint)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onCancel)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
