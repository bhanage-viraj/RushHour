//
//  WrapShareViewModel.swift
//  lucky7
//

import Combine
import Foundation
import MessageUI
import UniformTypeIdentifiers
import UIKit

@MainActor
final class WrapShareViewModel: ObservableObject {
    @Published var selectedTemplate: WrapTemplate = .styled
    @Published private(set) var posterImage: UIImage?
    @Published private(set) var aspectRatio: CGFloat = 9.0 / 16.0
    @Published private(set) var isWorking = false
    @Published private(set) var workingLabel = ""
    @Published var videoSharePayload: VideoSharePayload?
    @Published var imageSharePayload: ImageSharePayload?
    @Published var messageSharePayload: MessageSharePayload?
    @Published var errorMessage: String?
    @Published private(set) var resultMessage: String?

    let sourceURL: URL
    let metadata: WrapShareMetadata
    let sourceContainsMetadata: Bool

    private let exportEngine: ExportEngine
    private var styledVideoURL: URL?
    private var instagramStoryVideoURL: URL?
    private var instagramStorySourceURL: URL?
    private var transparentImage: UIImage?
    private var didPrepare = false

    init(
        sourceURL: URL,
        metadata: WrapShareMetadata,
        sourceContainsMetadata: Bool = false,
        initialTemplate: WrapTemplate = .styled,
        exportEngine: ExportEngine? = nil
    ) {
        self.sourceURL = sourceURL
        self.metadata = metadata
        self.sourceContainsMetadata = sourceContainsMetadata
        self.selectedTemplate = sourceContainsMetadata && initialTemplate == .clean
            ? .styled
            : initialTemplate
        self.exportEngine = exportEngine ?? .shared
    }

    var canShareToInstagram: Bool {
        InstagramStorySharer.availability == .ready
    }

    var canCopySelected: Bool {
        selectedTemplate.isTransparent
    }

    var availableTemplates: [WrapTemplate] {
        sourceContainsMetadata ? [.styled, .transparent] : WrapTemplate.allCases
    }

    func prepare() async {
        guard !didPrepare else { return }
        didPrepare = true

        if let size = await VideoOrientationHelper.presentationSize(for: sourceURL), size.height > 0 {
            aspectRatio = min(max(size.width / size.height, 0.5), 2.0)
        }

        let previewSourceURL = sourceURL
        posterImage = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = SessionRecordingViewModel.extractPreviewFrames(
                    from: previewSourceURL,
                    count: 1
                ).first
                continuation.resume(returning: image)
            }
        }
    }

    func saveSelected() {
        perform(.save)
    }

    func shareSelected() {
        perform(.systemShare)
    }

    func shareSelectedToInstagramMessages() {
        // The system sheet is the supported attachment hand-off for Instagram DMs.
        // It can also offer another destination when Instagram is not installed.
        perform(.systemShare)
    }

    func shareSelectedToWhatsApp() {
        // WhatsApp does not offer a stable public video-attachment URL scheme. Let iOS
        // hand the selected media to the installed share extensions instead.
        perform(.systemShare)
    }

    func shareSelectedToMessages() {
        guard MFMessageComposeViewController.canSendText() else {
            errorMessage = "Messages is not available on this device."
            return
        }
        guard MFMessageComposeViewController.canSendAttachments() else {
            errorMessage = "Messages cannot attach this wrap on this device."
            return
        }
        let attachmentType = selectedTemplate.isTransparent
            ? UTType.png.identifier
            : UTType.mpeg4Movie.identifier
        guard MFMessageComposeViewController.isSupportedAttachmentUTI(attachmentType) else {
            errorMessage = "Messages does not support this wrap format on this device."
            return
        }
        perform(.messages)
    }

    func shareSelectedToInstagramStory() {
        switch InstagramStorySharer.availability {
        case .ready:
            perform(.instagramStory)

        case .missingAppID:
            errorMessage = "Instagram Stories is not configured in this build."

        case .instagramUnavailable:
            errorMessage = "Install Instagram to share this wrap to Stories."
        }
    }

    func copySelected() {
        guard canCopySelected else { return }
        perform(.copy)
    }

    func completeSystemShare(error: Error?) {
        videoSharePayload = nil
        imageSharePayload = nil
        if let error {
            errorMessage = error.localizedDescription
        }
    }

    func completeMessageShare() {
        messageSharePayload = nil
    }

    func clearResultMessage() {
        resultMessage = nil
    }

    func cleanup() {
        if let styledVideoURL, styledVideoURL != sourceURL {
            try? FileManager.default.removeItem(at: styledVideoURL)
        }
        if let instagramStoryVideoURL,
           instagramStoryVideoURL != sourceURL,
           instagramStoryVideoURL != styledVideoURL {
            try? FileManager.default.removeItem(at: instagramStoryVideoURL)
        }
        styledVideoURL = nil
        instagramStoryVideoURL = nil
        instagramStorySourceURL = nil
        transparentImage = nil
        videoSharePayload = nil
        imageSharePayload = nil
        messageSharePayload = nil
    }

    private enum Destination {
        case save
        case systemShare
        case messages
        case instagramStory
        case copy

        var workingLabel: String {
            switch self {
            case .save:
                return "Preparing to save..."
            case .systemShare, .messages, .instagramStory:
                return "Preparing to share..."
            case .copy:
                return "Preparing image..."
            }
        }
    }

    private enum PreparedOutput {
        case video(URL)
        case image(UIImage)
    }

    private func perform(_ destination: Destination) {
        guard !isWorking else { return }
        isWorking = true
        workingLabel = destination.workingLabel
        errorMessage = nil
        resultMessage = nil
        let template = selectedTemplate

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let output = await self.output(for: template) else {
                self.isWorking = false
                self.errorMessage = "Rush Hour could not prepare this share. Please try again."
                return
            }

            switch destination {
            case .save:
                self.workingLabel = "Saving to Photos..."
                await self.save(output)

            case .systemShare:
                switch output {
                case .video(let url):
                    self.videoSharePayload = VideoSharePayload(
                        url: url,
                        title: self.metadata.title
                    )
                case .image(let image):
                    self.imageSharePayload = ImageSharePayload(
                        image: image,
                        title: self.metadata.title,
                        isTransparentSticker: true
                    )
                }

            case .messages:
                switch output {
                case .video(let url):
                    self.messageSharePayload = MessageSharePayload(
                        content: .video(url),
                        title: self.metadata.title
                    )
                case .image(let image):
                    self.messageSharePayload = MessageSharePayload(
                        content: .image(image),
                        title: self.metadata.title
                    )
                }

            case .instagramStory:
                let didOpen: Bool
                switch output {
                case .video(let url):
                    guard let storyURL = await self.instagramStoryOutput(for: url) else {
                        self.errorMessage = "Rush Hour could not prepare this video for Instagram Stories."
                        self.isWorking = false
                        return
                    }
                    didOpen = InstagramStorySharer.shareVideo(url: storyURL)
                case .image(let image):
                    didOpen = InstagramStorySharer.shareStickerImage(image)
                }
                if !didOpen {
                    self.errorMessage = "Rush Hour could not open Instagram Stories."
                }

            case .copy:
                guard case .image(let image) = output,
                      let data = image.pngData() else {
                    self.errorMessage = "Rush Hour could not copy this image."
                    self.isWorking = false
                    return
                }
                UIPasteboard.general.setData(data, forPasteboardType: UTType.png.identifier)
                self.resultMessage = "Copied to Clipboard"
            }

            self.isWorking = false
        }
    }

    private func instagramStoryOutput(for url: URL) async -> URL? {
        if instagramStorySourceURL == url,
           let instagramStoryVideoURL,
           FileManager.default.fileExists(atPath: instagramStoryVideoURL.path) {
            return instagramStoryVideoURL
        }

        if let previousURL = instagramStoryVideoURL,
           previousURL != sourceURL,
           previousURL != styledVideoURL {
            try? FileManager.default.removeItem(at: previousURL)
        }

        guard let outputURL = await exportEngine.generateInstagramStoryVideo(
            sourceVideoURL: url
        ) else {
            return nil
        }
        instagramStorySourceURL = url
        instagramStoryVideoURL = outputURL
        return outputURL
    }

    private func output(for template: WrapTemplate) async -> PreparedOutput? {
        switch template {
        case .clean:
            return .video(sourceURL)

        case .styled:
            // Legacy `wrapped_*` masters already contain this exact metadata treatment.
            // Reusing that file avoids drawing a second title/duration/date layer.
            if sourceContainsMetadata {
                return .video(sourceURL)
            }

            if let styledVideoURL,
               FileManager.default.fileExists(atPath: styledVideoURL.path) {
                return .video(styledVideoURL)
            }

            guard let output = await exportEngine.generateShareVideo(
                sourceVideoURL: sourceURL,
                overlay: exportOverlay,
                template: .styled
            ) else {
                return nil
            }
            styledVideoURL = output
            return .video(output)

        case .transparent:
            if let transparentImage {
                return .image(transparentImage)
            }
            guard let image = await exportEngine.generateTransparentShareImage(
                sourceVideoURL: sourceURL,
                overlay: exportOverlay
            ) else {
                return nil
            }
            transparentImage = image
            return .image(image)
        }
    }

    private var exportOverlay: ExportEngine.WrappedVideoOverlay {
        ExportEngine.WrappedVideoOverlay(
            header: metadata.title,
            duration: metadata.duration,
            subtitle: metadata.date
        )
    }

    private func save(_ output: PreparedOutput) async {
        do {
            switch output {
            case .video(let url):
                _ = try await PhotoLibrarySaver.saveVideo(at: url)
            case .image(let image):
                try await PhotoLibrarySaver.saveImage(image)
            }
            resultMessage = "Saved to Photos"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
