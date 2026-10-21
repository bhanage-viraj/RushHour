//
//  ReasonFormView.swift
//  lucky7
//
//  Created by Andrian on 30/05/26.
//

import SwiftUI
import UIKit

struct ReasonFormView: View {
    let appName: String
    @State private var reason: String = ""
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var fieldFocused: Bool
    @State private var keyboardFrame = CGRect.null

    private let titleNavy = Color(red: 0x02/255.0, green: 0x2B/255.0, blue: 0x54/255.0)

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 402, geometry.size.height / 874)
            let drawerHeight = (fieldFocused ? 772 : 654) * scale
            let cardBottom = geometry.frame(in: .global).maxY - drawerHeight + 460 * scale
            let keyboardOverlap = fieldFocused ? max(0, cardBottom - keyboardFrame.minY) : 0

            ZStack(alignment: .bottom) {
                Color.black.opacity(0.8)
                    .onTapGesture { fieldFocused = false }
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Capsule()
                        .fill(.white.opacity(0.7))
                        .frame(width: 56 * scale, height: 6 * scale)
                        .padding(.top, 14 * scale)
                        .padding(.bottom, 20 * scale)
                        .onTapGesture { fieldFocused = false }
                        .accessibilityHidden(true)

                    reasonCard(scale: scale, keyboardOverlap: keyboardOverlap)
                        .frame(height: 420 * scale)
                        .padding(.bottom, 24 * scale)
                    buttons(scale: scale)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24 * scale)
                .frame(height: drawerHeight)
                .background {
                    LinearGradient(
                        colors: [Color(red: 0, green: 50 / 255, blue: 97 / 255),
                                 Color(red: 11 / 255, green: 31 / 255, blue: 50 / 255)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .overlay {
                        Image("ReasonSheetBg")
                            .resizable()
                            .frame(width: geometry.size.width, height: 645 * scale)
                    }
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 40 * scale,
                                                     topTrailingRadius: 40 * scale))
                    .shadow(color: .black.opacity(0.15), radius: 20 * scale, y: -19 * scale)
                }
                // Keep the artwork behind the drawer so only its top peeks out.
                .background(alignment: .top) {
                    Image("ReasonFormHeader")
                        .resizable()
                        .frame(width: (fieldFocused ? 213.645 : 271.852) * scale,
                               height: (fieldFocused ? 166.358 : 211.681) * scale)
                        .rotationEffect(.degrees(fieldFocused ? 5.21 : 0))
                        .offset(x: (fieldFocused ? 1.29 : 7.526) * scale,
                                y: (fieldFocused ? -90.006 : -140) * scale)
                        .accessibilityHidden(true)
                }
                .animation(.easeInOut(duration: 0.25), value: fieldFocused)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .null
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            if fieldFocused { fieldFocused = false } else { onCancel() }
        }
    }

    private func reasonCard(scale: CGFloat, keyboardOverlap: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 36 * scale)
            .fill(.white)
            .overlay(alignment: .topLeading) {
                Image("ReasonCardPattern")
                    .resizable()
                    .frame(width: 354 * scale, height: 313 * scale)
                    .offset(y: 107 * scale)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8 * scale) {
                    Text("Reason")
                        .font(.custom("Special Gothic Expanded One", size: 32 * scale))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(titleNavy)
                        .accessibilityAddTraits(.isHeader)

                    ZStack(alignment: .topLeading) {
                        if reason.isEmpty && !fieldFocused {
                            Text("I open this because....")
                                .font(.system(size: 24 * scale))
                                .foregroundStyle(.black.opacity(0.30))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        TextEditor(text: $reason)
                            .font(.system(size: 24 * scale))
                            .foregroundStyle(.black.opacity(0.7))
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, -5)
                            .padding(.top, -8)
                            .focused($fieldFocused)
                            .environment(\.colorScheme, .light)
                            .accessibilityLabel("Reason for opening \(appName)")
                            .accessibilityHint("Required before unlocking the app")
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") { fieldFocused = false }
                                }
                            }
                    }
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 24 * scale)
                .padding(.top, 32 * scale)
                .padding(.bottom, 32 * scale + keyboardOverlap)
            }
            .clipShape(RoundedRectangle(cornerRadius: 36 * scale))
            .overlay {
                RoundedRectangle(cornerRadius: 36 * scale).strokeBorder(.black, lineWidth: fieldFocused ? 2 : 1)
            }
    }

    private func buttons(scale: CGFloat) -> some View {
        // disabled until they type something
        let canSubmit = !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(spacing: 10 * scale) {
            Button {
                onSubmit(reason)
            } label: {
                pill(title: "SUBMIT & UNLOCK", bordered: false, scale: scale)
                    .opacity(canSubmit ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel("Submit and unlock \(appName)")
            .accessibilityHint("Unlocks the app for a short break")
            .accessibilityInputLabels(["submit", "unlock", "submit and unlock"])

            Button(action: onCancel) {
                pill(title: "CANCEL", bordered: true, scale: scale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
            .accessibilityHint("Returns to your focus session without unlocking")
            .accessibilityInputLabels(["cancel", "go back"])
        }
    }

    private func pill(title: String, bordered: Bool, scale: CGFloat) -> some View {
        Text(title)
            .font(.custom("Special Gothic Expanded One", size: 14 * scale))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: max(44, 56 * scale))
            .background(Capsule().fill(.white))
            .overlay {
                if bordered {
                    Capsule().strokeBorder(.black, lineWidth: 1)
                }
            }
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [Color(red: 0x00/255.0, green: 0x32/255.0, blue: 0x61/255.0),
                     Color(red: 0x0B/255.0, green: 0x1F/255.0, blue: 0x32/255.0)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        ReasonFormView(appName: "Instagram", onSubmit: { _ in }, onCancel: {})
    }
}
