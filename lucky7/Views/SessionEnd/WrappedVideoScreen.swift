//
//  WrappedVideoScreen.swift
//  lucky7
//

import SwiftUI
import SwiftData
import AVKit
import UniformTypeIdentifiers
import UIKit

struct WrappedVideoScreen: View {
    private static let portraitCardSize = CGSize(width: 362, height: 647)

    let kind: Kind
    var videoFrames: [UIImage] = []

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionRecording: SessionRecordingViewModel

    @Query private var sessions: [Session]
    @Query private var periodWraps: [PeriodWrap]
    @State private var player: AVPlayer?
    @State private var isPlaying = true
    @State private var sharePayload: VideoSharePayload?
    @State private var isShowingShareComposer = false
    @State private var mediaAspectRatio: CGFloat = 9.0 / 16.0
    @State private var isMigratingLegacyMaster = false

    init(kind: Kind, videoFrames: [UIImage] = []) {
        self.kind = kind
        self.videoFrames = videoFrames
        // Session wraps are backed by a `Session`; weekly/monthly by a `PeriodWrap`.
        let sessionId: UUID
        if case .session(let id) = kind { sessionId = id } else { sessionId = UUID() }
        _sessions = Query(filter: #Predicate<Session> { $0.id == sessionId })

        let key: String
        let kindStr: String
        switch kind {
        case .session:
            key = ""; kindStr = ""
        case .weekly(let k, _, _, _, _):
            key = k; kindStr = "weekly"
        case .monthly(let k, _, _, _, _):
            key = k; kindStr = "monthly"
        }
        _periodWraps = Query(filter: #Predicate<PeriodWrap> { $0.periodKey == key && $0.kind == kindStr })
    }

    // MARK: - Derived data

    private var session: Session? { sessions.first }
    private var periodWrap: PeriodWrap? { periodWraps.first }

    private var isWrapReady: Bool {
        videoURL != nil
    }

    /// The live flow's export is still rendering this wrap (nothing persisted yet).
    /// A session WITH a stored path but no resolvable file is gone for good — that
    /// gets the "unavailable" treatment instead of a spinner that never ends.
    private var isFinishingExport: Bool {
        sessionRecording.isExporting && session?.wrappedVideoPath == nil
    }

    private var displayTitle: String {
        switch kind {
        case .session:
            let t = session?.title ?? ""
            return t.isEmpty ? "Untitled session" : t
        case .weekly(_, _, let title, _, _), .monthly(_, _, let title, _, _):
            return title
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        TimeFormatter.shortDuration(seconds)
    }

    private var durationText: String {
        switch kind {
        case .session:
            return formatDuration(session?.actualDuration ?? 0)
        case .weekly(_, _, _, _, let duration), .monthly(_, _, _, _, let duration):
            return formatDuration(duration)
        }
    }

    private var dateText: String {
        switch kind {
        case .session:
            guard let start = session?.startTime else { return "" }
            return start
                .formatted(.dateTime.day().month(.abbreviated).year())
        case .weekly(_, _, _, let periodLabel, _), .monthly(_, _, _, let periodLabel, _):
            return periodLabel
        }
    }

    private var videoURL: URL? {
        switch kind {
        case .session:
            // The final wrapped session path is the only playable/shareable source.
            // rawClipPath is just an export source and must never be shown as a wrap.
            return WrapStorage.resolveVideoURL(session?.wrappedVideoPath)
        case .weekly, .monthly:
            return WrapStorage.resolveVideoURL(periodWrap?.videoPath)
        }
    }

    private var sourceContainsMetadata: Bool {
        guard case .session = kind, let videoURL else { return false }
        return WrapStorage.sessionMasterContainsMetadata(videoURL)
    }

    private var displayedMediaAspectRatio: CGFloat {
        mediaAspectRatio > 1
            ? mediaAspectRatio
            : Self.portraitCardSize.width / Self.portraitCardSize.height
    }

    private var shareableVideoURL: URL? {
        isMigratingLegacyMaster ? nil : videoURL
    }

    private var shareMetadata: WrapShareMetadata {
        WrapShareMetadata(title: displayTitle, duration: durationText, date: dateText)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.wrappedWatchBlue
                .ignoresSafeArea()

            Image("PatternBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .offset(y: -30)

            VStack(spacing: 0) {
                topBar
                    .frame(height: 48)

                if mediaAspectRatio <= 1 {
                    mediaCard
                        .padding(.horizontal, 20)
                        .padding(.top, 17)
                        .layoutPriority(1)

                    Spacer(minLength: 16)
                } else {
                    Spacer(minLength: 16)

                    mediaCard
                        .padding(.horizontal, 20)
                        .layoutPriority(1)

                    Spacer(minLength: 16)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .hidesFloatingTabBar()
        // Build the player as soon as a real video file URL exists, and rebuild if
        // the persisted path/live URL changes.
        .onAppear {
            syncPlayer()
        }
        .onChange(of: videoURL) { _, _ in syncPlayer() }
        .onChange(of: isWrapReady) { _, _ in syncPlayer() }
        .task(id: videoURL?.path) {
            guard let videoURL,
                  let size = await VideoOrientationHelper.presentationSize(for: videoURL),
                  size.height > 0 else {
                return
            }
            mediaAspectRatio = min(max(size.width / size.height, 0.5), 2.0)
        }
        .task(id: session?.wrappedVideoPath) {
            await migrateLegacySessionMasterIfNeeded()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
            guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            player?.seek(to: .zero)
            player?.play()
            isPlaying = true
        }
        .sheet(item: $sharePayload) { payload in
            VideoShareSheet(payload: payload)
        }
        .fullScreenCover(isPresented: $isShowingShareComposer, onDismiss: resumeAfterSharing) {
            if let sourceURL = shareableVideoURL {
                WrapShareComposer(
                    sourceURL: sourceURL,
                    metadata: shareMetadata,
                    sourceContainsMetadata: sourceContainsMetadata
                )
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
    }

    // MARK: - Player

    /// Builds (or rebuilds) the player once a wrap file exists.
    /// No-ops while we're still waiting, or if we're already playing this exact URL.
    private func syncPlayer() {
        guard let url = videoURL else {
            player?.pause()
            player = nil
            isPlaying = false
            return
        }
        if (player?.currentItem?.asset as? AVURLAsset)?.url == url { return }
        player = AVPlayer(url: url)
        player?.actionAtItemEnd = .none
        player?.play()
        isPlaying = true
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityInputLabels(["back", "go back"])

            Spacer()

            shareButton
        }
        .padding(.horizontal, 16)
    }

    private var shareButton: some View {
        Button {
            openShareFlow()
        } label: {
            shareIcon
        }
        .buttonStyle(.plain)
        .disabled(shareableVideoURL == nil)
    }

    private var shareIcon: some View {
        Group {
            if isMigratingLegacyMaster {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .semibold))
            }
        }
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .opacity(shareableVideoURL == nil && !isMigratingLegacyMaster ? 0.45 : 1)
            .accessibilityLabel(isMigratingLegacyMaster ? "Updating wrap" : "Share video")
            .accessibilityHint(
                isMigratingLegacyMaster ? "Preparing this older wrap for sharing"
                    : shareableVideoURL != nil ? "Opens sharing options for this wrap video"
                    : isFinishingExport ? "Video is still finishing"
                    : "Video unavailable"
            )
            .accessibilityInputLabels(["share", "share video", "export"])
    }

    private func shareVideo(_ url: URL) {
        sharePayload = VideoSharePayload(url: url, title: displayTitle)
    }

    private func openShareFlow() {
        guard let videoURL = shareableVideoURL else { return }
        switch kind {
        case .session:
            player?.pause()
            isPlaying = false
            isShowingShareComposer = true
        case .weekly, .monthly:
            shareVideo(videoURL)
        }
    }

    private func resumeAfterSharing() {
        guard isWrapReady else { return }
        player?.play()
        isPlaying = true
    }

    private var mediaCard: some View {
        // The clean master keeps the orientation used while recording.
        Color.clear
            .aspectRatio(displayedMediaAspectRatio, contentMode: .fit)
            .overlay {
                Group {
                    if let player {
                        VideoPlayer(player: player)
                    } else if let firstFrame = videoFrames.first {
                        Image(uiImage: firstFrame)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.gray.opacity(0.8)
                            .overlay(
                                Image(systemName: "person.crop.rectangle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.white.opacity(0.5))
                                    .padding(50)
                            )
                    }
                }
            }
            .overlay {
                // While the clean master is still rendering, keep a spinner over the poster
                // frame instead of playing the not-yet-final video. When no export is
                // running and the file is gone, say so — an endless spinner here used to
                // mask permanently lost videos.
                if case .session = kind, !isWrapReady {
                    ZStack {
                        Color.black.opacity(0.4)
                        if isFinishingExport {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(1.3)
                                Text("Finishing your wrap…")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "video.slash.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white.opacity(0.85))
                                Text("Video unavailable")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                Text("This wrap's video is no longer on this device.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Video unavailable")
                        }
                    }
                }
            }
            .overlay {
                if case .session = kind, isWrapReady, !sourceContainsMetadata {
                    WrapMetadataOverlay(template: .styled, metadata: shareMetadata)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.black)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.black, lineWidth: 2)
            }
            // Figma node 3:30 uses a 362 x 647 portrait card on its 402 pt canvas.
            // Landscape keeps the source aspect ratio until its dedicated design pass.
            .frame(
                maxWidth: mediaAspectRatio > 1 ? 680 : Self.portraitCardSize.width,
                maxHeight: mediaAspectRatio > 1 ? .infinity : Self.portraitCardSize.height
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Session wrap video")
            .accessibilityValue("\(displayTitle), \(durationText), \(dateText)")
            .accessibilityHint(isPlaying ? "Video is playing" : "Video is paused")
    }

    @MainActor
    private func migrateLegacySessionMasterIfNeeded() async {
        guard case .session = kind,
              let session,
              let legacyMasterURL = videoURL,
              WrapStorage.sessionMasterContainsMetadata(legacyMasterURL),
              !isMigratingLegacyMaster else {
            return
        }

        isMigratingLegacyMaster = true
        defer { isMigratingLegacyMaster = false }

        let rawSourceURL = WrapStorage.resolveVideoURL(session.rawClipPath)
        guard let cleanURL = await SessionWrapMigrationService.makeCleanMasterIfPossible(
            legacyMasterURL: legacyMasterURL,
            rawSourceURL: rawSourceURL,
            sessionDuration: session.actualDuration
        ) else {
            RecordingDiagnostics.log(
                "WrappedVideo legacy master retained session=\(session.id) "
                    + "master=\(legacyMasterURL.lastPathComponent)"
            )
            return
        }

        let previousPath = session.wrappedVideoPath
        session.wrappedVideoPath = cleanURL.lastPathComponent
        do {
            try context.save()
            RecordingDiagnostics.log(
                "WrappedVideo legacy master migrated session=\(session.id) "
                    + "from=\(legacyMasterURL.lastPathComponent) "
                    + "to=\(cleanURL.lastPathComponent)"
            )
        } catch {
            session.wrappedVideoPath = previousPath
            try? FileManager.default.removeItem(at: cleanURL)
            RecordingDiagnostics.log(
                "WrappedVideo legacy migration persist failed session=\(session.id) "
                    + "error=\(error.localizedDescription)"
            )
        }
    }

}

extension WrappedVideoScreen {
    /// The three sources a wrap can be built from. Only `.session` is backed by real
    /// data today; `.weekly` and `.monthly` carry display info but show a placeholder.
    enum Kind {
        case session(UUID)
        case weekly(periodKey: String, periodEnd: Date, title: String, periodLabel: String, duration: TimeInterval)
        case monthly(periodKey: String, periodEnd: Date, title: String, periodLabel: String, duration: TimeInterval)
    }

}

// MARK: - "Not ready yet" warning (EndSession-style bottom sheet)

struct WrapNotReadyModal: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.55))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.top, 2)

                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 8)

                Button(action: onDismiss) {
                    Text("GOT IT")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 22)
                .accessibilityLabel("Got it")
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 28)
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .accessibilityAddTraits(.isModal)
        }
    }
}

struct VideoSharePayload: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

struct ImageSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
    let title: String
    var isTransparentSticker = false
}

struct VideoShareSheet: UIViewControllerRepresentable {
    let payload: VideoSharePayload
    var onComplete: (Error?) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let item = VideoShareItemSource(payload: payload)
        let controller = UIActivityViewController(
            activityItems: [item],
            applicationActivities: [InstagramStoryActivity()]
        )
        controller.excludedActivityTypes = [.addToReadingList, .assignToContact, .markupAsPDF, .print]
        controller.completionWithItemsHandler = { _, _, _, error in
            DispatchQueue.main.async {
                onComplete(error)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ImageShareSheet: UIViewControllerRepresentable {
    let payload: ImageSharePayload
    var onComplete: (Error?) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let item = ImageShareItemSource(payload: payload)
        let controller = UIActivityViewController(
            activityItems: [item],
            applicationActivities: [InstagramStoryActivity()]
        )
        controller.excludedActivityTypes = [.addToReadingList, .assignToContact, .markupAsPDF, .print]
        controller.completionWithItemsHandler = { _, _, _, error in
            DispatchQueue.main.async {
                onComplete(error)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class VideoShareItemSource: NSObject, UIActivityItemSource {
    let payload: VideoSharePayload

    init(payload: VideoSharePayload) {
        self.payload = payload
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        payload.url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        payload.url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        payload.title
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.mpeg4Movie.identifier
    }
}

private final class ImageShareItemSource: NSObject, UIActivityItemSource {
    let payload: ImageSharePayload

    init(payload: ImageSharePayload) {
        self.payload = payload
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        payload.image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        payload.image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        payload.title
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.png.identifier
    }
}

@MainActor
private final class InstagramStoryActivity: UIActivity {
    private enum StoryItem {
        case image(UIImage, isSticker: Bool)
        case video(URL)
    }

    private var item: StoryItem?

    override class var activityCategory: UIActivity.Category {
        .share
    }

    override var activityType: UIActivity.ActivityType? {
        UIActivity.ActivityType("com.andrianangg.lucky7.instagramStory")
    }

    override var activityTitle: String? {
        "Instagram Story"
    }

    override var activityImage: UIImage? {
        UIImage(systemName: "camera.fill")
    }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        guard InstagramStorySharer.isConfigured,
              InstagramStorySharer.canOpenStories else {
            return false
        }
        return activityItems.contains { shareableItem(from: $0) != nil }
    }

    override func prepare(withActivityItems activityItems: [Any]) {
        item = activityItems.compactMap { shareableItem(from: $0) }.first
    }

    override func perform() {
        let didShare: Bool
        switch item {
        case .image(let image, let isSticker):
            didShare = isSticker
                ? InstagramStorySharer.shareStickerImage(image)
                : InstagramStorySharer.shareImage(image)
        case .video(let url):
            didShare = InstagramStorySharer.shareVideo(url: url)
        case nil:
            didShare = false
        }

        activityDidFinish(didShare)
    }

    private func shareableItem(from item: Any) -> StoryItem? {
        if let image = item as? UIImage {
            return image.pngData() == nil ? nil : .image(image, isSticker: false)
        }

        if let url = item as? URL {
            return FileManager.default.fileExists(atPath: url.path) ? .video(url) : nil
        }

        if let source = item as? VideoShareItemSource {
            return FileManager.default.fileExists(atPath: source.payload.url.path)
                ? .video(source.payload.url)
                : nil
        }

        if let source = item as? ImageShareItemSource {
            return source.payload.image.pngData() == nil
                ? nil
                : .image(
                    source.payload.image,
                    isSticker: source.payload.isTransparentSticker
                )
        }

        return nil
    }
}

@MainActor
enum InstagramStorySharer {
    enum Availability: Equatable {
        case ready
        case missingAppID
        case instagramUnavailable
    }

    private static let appIDKey = "FacebookAppID"

    static var isConfigured: Bool {
        facebookAppID != nil
    }

    static var availability: Availability {
        guard isConfigured else { return .missingAppID }
        return canOpenStories ? .ready : .instagramUnavailable
    }

    static var canOpenStories: Bool {
        guard let storiesURL = URL(string: "instagram-stories://share") else { return false }
        return UIApplication.shared.canOpenURL(storiesURL)
    }

    static func shareVideo(url: URL) -> Bool {
        guard let videoData = try? Data(contentsOf: url) else {
            return false
        }

        return openStories(with: [
            "com.instagram.sharedSticker.backgroundVideo": videoData,
            "com.instagram.sharedSticker.backgroundTopColor": "#3A8DFF",
            "com.instagram.sharedSticker.backgroundBottomColor": "#3A8DFF"
        ])
    }

    static func shareImage(_ image: UIImage) -> Bool {
        guard let imageData = image.pngData() else {
            return false
        }

        return openStories(with: [
            "com.instagram.sharedSticker.backgroundImage": imageData,
            "com.instagram.sharedSticker.backgroundTopColor": "#3A8DFF",
            "com.instagram.sharedSticker.backgroundBottomColor": "#3A8DFF"
        ])
    }

    static func shareStickerImage(_ image: UIImage) -> Bool {
        guard let imageData = image.pngData() else {
            return false
        }

        return openStories(with: [
            "com.instagram.sharedSticker.stickerImage": imageData,
            "com.instagram.sharedSticker.backgroundTopColor": "#0060BE",
            "com.instagram.sharedSticker.backgroundBottomColor": "#0060BE"
        ])
    }

    private static func openStories(with item: [String: Any]) -> Bool {
        guard let facebookAppID,
              var components = URLComponents(string: "instagram-stories://share"),
              canOpenStories else {
            return false
        }

        components.queryItems = [
            URLQueryItem(name: "source_application", value: facebookAppID)
        ]
        guard let storiesURL = components.url else { return false }

        UIPasteboard.general.setItems(
            [item],
            options: [.expirationDate: Date().addingTimeInterval(5 * 60)]
        )
        UIApplication.shared.open(storiesURL)
        return true
    }

    private static var facebookAppID: String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: appIDKey) as? String else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.allSatisfy(\.isNumber) else {
            return nil
        }
        return value
    }
}

#Preview {
    WrappedVideoScreen(kind: .session(UUID()), videoFrames: [])
        .environmentObject(SessionRecordingViewModel())
        .modelContainer(for: [Session.self, PeriodWrap.self], inMemory: true)
}
