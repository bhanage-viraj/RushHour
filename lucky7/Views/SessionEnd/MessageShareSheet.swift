//
//  MessageShareSheet.swift
//  lucky7
//

import MessageUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MessageSharePayload: Identifiable {
    enum Content {
        case video(URL)
        case image(UIImage)
    }

    let id = UUID()
    let content: Content
    let title: String
}

struct MessageShareSheet: UIViewControllerRepresentable {
    let payload: MessageSharePayload
    var onComplete: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.body = payload.title

        switch payload.content {
        case .video(let url):
            _ = controller.addAttachmentURL(
                url,
                withAlternateFilename: "Rush Hour Wrap.mp4"
            )

        case .image(let image):
            if let data = image.pngData() {
                _ = controller.addAttachmentData(
                    data,
                    typeIdentifier: UTType.png.identifier,
                    filename: "Rush Hour Wrap.png"
                )
            }
        }

        return controller
    }

    func updateUIViewController(
        _ uiViewController: MFMessageComposeViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onComplete: () -> Void

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onComplete()
        }
    }
}
