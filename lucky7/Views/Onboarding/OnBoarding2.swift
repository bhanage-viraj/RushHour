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
        ) { scale in
            mainContent(scale: scale)
        }
        .navigationBarBackButtonHidden()
    }

    private func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    private func mainContent(scale: CGFloat) -> some View {
        VStack(spacing: 24 * scale) {
            VStack(spacing: 16 * scale) {
                OnboardingTitle(text: "Set a time.\nStart a Session", scale: scale)

                Text("Turn intentions into action.\nStay focused, review your recordings,\nand celebrate every step forward.")
                    .font(.system(size: 17 * scale))
                    .foregroundStyle(Color(white: 38 / 255).opacity(0.8))
                    .lineSpacing(2 * scale)
                    .frame(height: 66 * scale)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            photo(scale: scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func photo(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            LoopingVideoPlayer(assetName: "OnboardingVideoSample")
                .frame(width: 226.033 * scale, height: 333.81 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 25.806 * scale))
                .shadow(color: .black, radius: 0, x: 0, y: 2.994 * scale)
                .overlay {
                    RoundedRectangle(cornerRadius: 25.806 * scale)
                        .strokeBorder(.black, lineWidth: 0.748 * scale)
                }
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        Text("Morning Session Rush!")
                            .font(.custom("Special Gothic Expanded One", size: 7.37 * scale))
                            .frame(height: 9.58 * scale)
                        Text("3h 20m")
                            .font(.custom("Special Gothic Expanded One", size: 26.32 * scale))
                            .frame(height: 34.22 * scale)
                            .padding(.top, 2 * scale)
                        Text("26 MAY 2026")
                            .font(.system(size: 6.317 * scale, weight: .bold))
                            .tracking(0.6317 * scale)
                            .opacity(0.7)
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 20.96 * scale)
                }
                .position(x: 142.2865 * scale, y: 185.905 * scale)

            Image("OnboardingTrafficLight")
                .resizable()
                .frame(width: 193.543 * scale, height: 81.223 * scale)
                .position(x: 189.57 * scale, y: 352.611 * scale)
        }
        .frame(width: 306 * scale, height: 405 * scale)
        .accessibilityHidden(true)
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
