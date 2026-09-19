//
//  AboutScreen.swift
//  lucky7
//

import SwiftUI

struct AboutScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)

                        Image("RushHourLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 170)
                            .accessibilityDecorative()

                        Text("Version 1.0")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.top, 18)

                        Text("Rush Hour is a focus companion that combines timed sessions, timelapse reviews, and app blocking to help you stay focused and build better habits.")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.top, 18)

                        Text("Copyright © 2026\nAll rights reserved.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.top, 22)

                        Spacer(minLength: 24)
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 36)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background {
            Color("CanvasBlue")
                .overlay {
                    Image("PatternBackground")
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    AboutScreen()
}
