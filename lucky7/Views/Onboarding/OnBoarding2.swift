//
//  OnBoarding2.swift
//  lucky7
//

import SwiftUI
import AVFoundation
import UIKit

struct OnBoarding2: View {
    @Binding var path: [Int]

    var body: some View {
        OnboardingScreenTemplate(
            step: 2,
            onContinue: { path.append(3) },
            onBack: goBack
        ) {
            mainContent
        }
        .navigationBarBackButtonHidden()
    }

    private func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    private var mainContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Set a time.\nStart a Session")
                    .font(.custom("Special Gothic Expanded One", size: 28))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Turn intentions into action.\nStay focused, review your recordings,\nand celebrate every step forward.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.black.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            photo
                .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity)
    }

    private var photo: some View {
        LoopingVideoPlayer(assetName: "OnboardingVideoSample")
            .frame(width: 220, height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.black.opacity(1), radius: 0, x: 0, y: 3)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.black, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                VStack(spacing: 2) {
                    Text("Morning Session Rush!")
                        .font(.system(size: 12, weight: .bold))
                    Text("3h 20m")
                        .font(.system(size: 34, weight: .heavy))
                    Text("26 MAY 2026")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(2)
                }
                .foregroundColor(.white)
                .padding(.top, 20)
            }
            .offset(x: -14, y: 8)
            .overlay(alignment: .bottomTrailing) {
                Image("OnboardingTrafficLight")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 96)
                    .offset(x: 30, y: 70)
                    .padding(12)
            }
    }
}

private struct LoopingVideoPlayer: UIViewRepresentable {
    let assetName: String

    func makeUIView(context: Context) -> LoopingPlayerView {
        LoopingPlayerView(assetName: assetName)
    }

    func updateUIView(_ uiView: LoopingPlayerView, context: Context) {}
}

private final class LoopingPlayerView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?

    init(assetName: String) {
        super.init(frame: .zero)

        guard let dataAsset = NSDataAsset(name: assetName) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(assetName).mp4")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? dataAsset.data.write(to: url)
        }

        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: url))

        playerLayer.player = queuePlayer
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
        queuePlayer.play()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

#Preview {
    NavigationStack {
        OnBoarding2(path: .constant([2]))
    }
}
