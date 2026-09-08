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
                onContinue: { path.append(2) },
                onGoNext: { path.append(2) }
            ) {
                mainContent
            }
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
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("Twelve tabs.")
                    .font(.custom("Special Gothic Expanded One", size: 28))
                Text("Six deadlines.")
                    .font(.custom("Special Gothic Expanded One", size: 28))
                Text("One you.")
                    .font(.custom("Special Gothic Expanded One", size: 28))
                    .padding(.bottom, 10)

                Text(
                    "Everything feels urgent but nothing feels finished. You're stuck in \(Text("Rush Hour").bold().italic())"
                )
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
            }
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Image("group206")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    OnBoarding1()
        .environmentObject(FocusViewModel())
}
