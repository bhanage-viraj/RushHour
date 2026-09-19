//
//  ReasonFormView.swift
//  lucky7
//
//  Created by Andrian on 30/05/26.
//

import SwiftUI

struct ReasonFormView: View {
    let appName: String
    @State private var reason: String = ""
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var fieldFocused: Bool

    private let titleNavy = Color(red: 0x02/255.0, green: 0x2B/255.0, blue: 0x54/255.0)

    var body: some View {
        VStack(spacing: 16) {
            reasonCard
                .frame(maxHeight: .infinity)
            buttons
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reasonCard: some View {
        RoundedRectangle(cornerRadius: 36)
            .fill(.white)
            .overlay {
                Image("Vector16")
                    .resizable()
                    .scaledToFill()
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reason")
                        .font(.custom("SpecialGothicExpandedOne-Regular", size: 32))
                        .foregroundStyle(titleNavy)

                    ZStack(alignment: .topLeading) {
                        if reason.isEmpty {
                            Text("I open this because….")
                                .font(.system(size: 22))
                                .foregroundStyle(.black.opacity(0.30))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)  
                        }
                        TextEditor(text: $reason)
                            .font(.system(size: 22))
                            .foregroundStyle(.black)
                            .scrollContentBackground(.hidden)
                            .focused($fieldFocused)
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
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
            .clipShape(RoundedRectangle(cornerRadius: 36))
            .overlay {
                RoundedRectangle(cornerRadius: 36).strokeBorder(.black, lineWidth: 1.5)
            }
    }

    private var buttons: some View {
        // disabled until they type something
        let canSubmit = !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(spacing: 10) {
            Button {
                onSubmit(reason)
            } label: {
                pill(title: "SUBMIT & UNLOCK", bordered: false)
                    .opacity(canSubmit ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel("Submit and unlock \(appName)")
            .accessibilityHint("Unlocks the app for a short break")
            .accessibilityInputLabels(["submit", "unlock", "submit and unlock"])

            Button(action: onCancel) {
                pill(title: "CANCEL", bordered: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
            .accessibilityHint("Returns to your focus session without unlocking")
            .accessibilityInputLabels(["cancel", "go back"])
        }
    }

    private func pill(title: String, bordered: Bool) -> some View {
        Text(title)
            .font(.custom("SpecialGothicExpandedOne-Regular", size: 14))
            .tracking(0.5)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Capsule().fill(.white))
            .overlay {
                if bordered {
                    Capsule().strokeBorder(.black, lineWidth: 1.5)
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
