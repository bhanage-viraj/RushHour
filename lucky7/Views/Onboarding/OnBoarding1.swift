//
//  OnBoarding1.swift
//  lucky7
//
//  Created by Viraj Bhanage on 04/06/26.
//

import SwiftUI

struct OnBoarding1: View {
    var onComplete: () -> Void = {}

    @State private var path: [Int] = []

    var body: some View {
        NavigationStack(path: $path) {
            OnboardingScreenTemplate(
                step: 1,
                onContinue: { path.append(2) }
            ) { scale in
                mainContent(scale: scale)
            }
            .task { await NotificationPermission.requestIfNeeded() }
            .navigationDestination(for: Int.self) { step in
                switch step {
                case 2:
                    OnBoarding2(path: $path)
                case 3:
                    OnBoarding3(path: $path)
                case 4:
                    OnBoarding4(onDone: onComplete)
                default:
                    EmptyView()
                }
            }
        }
    }
    
    private func mainContent(scale: CGFloat) -> some View {
        VStack(spacing: 24 * scale) {
            VStack(spacing: 16 * scale) {
                OnboardingTitle(text: "Twelve tabs.\nSix deadlines.\nOne you.", scale: scale)

                Text("Everything feels urgent\nbut nothing feels finished.\nYou're stuck in \(Text("Rush Hour").bold().italic())")
                    .font(.system(size: 17 * scale))
                    .foregroundStyle(Color(white: 38 / 255).opacity(0.8))
                    .lineSpacing(2 * scale)
                    .frame(height: 66 * scale)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Image("group206")
                .resizable()
                .frame(width: 303 * scale, height: 345 * scale)
                .offset(x: 3.45 * scale, y: 18.25 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

}

#Preview {
    OnBoarding1()
        .environmentObject(FocusViewModel())
}
