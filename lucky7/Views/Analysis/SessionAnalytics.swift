//
//  SessionAnalytics.swift
//  lucky7
//

import SwiftUI
import SwiftData
import UIKit
import FamilyControls
import ManagedSettings

struct SessionAnalytics: View {
    var sessionId: UUID
    var videoFrames: [UIImage] = []
    var onClose: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var sessions: [Session]

    @StateObject private var distractionStat = DistractionStat()

    @State private var isShowingWrappedVideo = false
    /// Poster frame pulled from the saved wrapped video when no live capture
    /// frames are handed in (e.g. when opened from History).
    @State private var extractedThumbnail: UIImage?
    @State private var showDeleteConfirm = false
    @State private var fullscreenSnapshot: FullscreenSnapshot?
    @State private var isShowingShareComposer = false
    @State private var isEditingSession = false
    @State private var editedTitle = ""
    @State private var editedSummary = ""
    @State private var showEditError = false

    init(sessionId: UUID, videoFrames: [UIImage] = [], onClose: (() -> Void)? = nil) {
        self.sessionId = sessionId
        self.videoFrames = videoFrames
        self.onClose = onClose
        _sessions = Query(filter: #Predicate<Session> { $0.id == sessionId })
    }

    // MARK: - Derived data

    private var session: Session? { sessions.first }

    private var savedSnapshots: [UIImage] {
        // Only the first 3 are ever shown, so decode just those — decoding all
        // stored images on every render spikes memory and crashes past ~4 photos.
        (session?.snapshotImages ?? []).prefix(3).compactMap { UIImage(data: $0) }
    }

    /// The video thumbnail always uses captured frames from the session video —
    /// the live capture frames when available, otherwise a frame extracted from
    /// the saved wrapped video. Never the user's activity snapshots.
    private var thumbnailImage: UIImage? {
        videoFrames.first ?? extractedThumbnail
    }

    private var displayTitle: String {
        let t = session?.title ?? ""
        return t.isEmpty ? "Untitled session" : t
    }

    private var displaySummary: String {
        let s = session?.summary ?? ""
        return s.isEmpty ? "No description added for this session yet." : s
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        TimeFormatter.shortDuration(seconds)
    }

    private var durationBreakdown: (whole: Int, focus: Int, distracted: Int) {
        let whole = max(0, Int((session?.actualDuration ?? 0).rounded()))
        let distracted = min(
            whole,
            max(0, Int(distractionStat.totalDistractionDuration.rounded()))
        )
        let focus = max(0, Int((session?.focusDuration(distractedDuration: distractionStat.totalDistractionDuration) ?? 0).rounded()))
        return (whole, focus, distracted)
    }

    private var wholeSessionText: String {
        formatDuration(TimeInterval(durationBreakdown.whole))
    }

    private var focusDurationText: String {
        formatDuration(TimeInterval(durationBreakdown.focus))
    }

    private var distractedDurationText: String {
        formatDuration(TimeInterval(durationBreakdown.distracted))
    }

    private var dateText: String {
        guard let start = session?.startTime else { return "" }
        return start
            .formatted(.dateTime.day().month(.abbreviated).year())
            .uppercased()
    }

    private var distractionCountText: String {
        distractionStat.distractionCount == 0 ? "-" : "\(distractionStat.distractionCount)x"
    }

    private var shareableVideoURL: URL? {
        playableVideoURL
    }

    private var shareMetadata: WrapShareMetadata {
        WrapShareMetadata(
            title: displayTitle,
            duration: formatDuration(session?.focusDuration() ?? 0),
            date: dateText.capitalized
        )
    }

    private var sourceContainsMetadata: Bool {
        guard let shareableVideoURL else { return false }
        return WrapStorage.sessionMasterContainsMetadata(shareableVideoURL)
    }

    private var playableVideoURL: URL? {
        WrapStorage.resolveVideoURL(session?.wrappedVideoPath)
    }

    private func logVideoResolution() {
        guard let session else {
            RecordingDiagnostics.log("Analytics session missing id=\(sessionId)")
            return
        }
        let wrapped = WrapStorage.resolveVideoURL(session.wrappedVideoPath)
        let raw = WrapStorage.resolveVideoURL(session.rawClipPath)
        RecordingDiagnostics.log("Analytics session=\(sessionId) storedWrapped=\(session.wrappedVideoPath ?? "nil") resolvedWrapped=\(wrapped?.lastPathComponent ?? "nil") storedRaw=\(session.rawClipPath ?? "nil") resolvedRaw=\(raw?.lastPathComponent ?? "nil") playable=\(playableVideoURL?.lastPathComponent ?? "nil")")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    statsCard
                    detailCard
                    distractionsCard
                    deleteButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 50)
                .padding(.bottom, 38)
                .frame(maxWidth: 450)
                .frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    GeometryReader { geometry in
                        Image("AnalyticsPattern")
                            .resizable()
                            .frame(width: 786.807, height: 839.155)
                            .position(x: geometry.size.width / 2 + 0.4, y: 349.578)
                            .accessibilityHidden(true)
                    }
                }
            }
            .scrollClipDisabled()
            .background(Color("SessionDetailsBlue").ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: close) { Image(systemName: "chevron.left") }
                        .tint(.white)
                        .accessibilityLabel("Back to My Sessions")
                        .accessibilityInputLabels(["back", "close", "done"])
                }
                ToolbarItem(placement: .topBarTrailing) { shareButton }
            }
        }
        .preferredColorScheme(.dark)
        .overlay {
            if showDeleteConfirm { deleteConfirmation }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $isEditingSession) { editSessionForm }
        .hidesFloatingTabBar()
        .onAppear {
            if let session {
                distractionStat.fetchDistractions(for: session, context: context)
            } else {
                distractionStat.fetchDistractions(for: sessionId, context: context)
            }
            logVideoResolution()
        }
        .task(id: sessionId) {
            await loadThumbnailIfNeeded()
        }
        .fullScreenCover(isPresented: $isShowingWrappedVideo) {
            WrappedVideoScreen(kind: .session(sessionId), videoFrames: videoFrames)
        }
        .fullScreenCover(isPresented: $isShowingShareComposer) {
            if let sourceURL = shareableVideoURL {
                WrapShareComposer(
                    sourceURL: sourceURL,
                    metadata: shareMetadata,
                    sourceContainsMetadata: sourceContainsMetadata
                )
            }
        }
        .fullScreenCover(item: $fullscreenSnapshot) { item in
            SnapshotViewer(images: savedSnapshots, startIndex: item.id)
        }
    }

    // MARK: - Subviews
    private var shareButton: some View {
        Button {
            isShowingShareComposer = true
        } label: {
            shareIcon
        }
        .buttonStyle(.plain)
        .disabled(shareableVideoURL == nil)
    }

    private var shareIcon: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.system(size: 20))
            .foregroundColor(.white)
            .contentShape(Rectangle())
            .opacity(shareableVideoURL == nil ? 0.45 : 1)
            .accessibilityLabel("Share session wrap")
            .accessibilityHint(
                shareableVideoURL == nil
                    ? "The final wrap video is unavailable"
                    : "Opens template and sharing options for this session"
            )
            .accessibilityInputLabels(["share", "share session", "export"])
    }

    private var statsCard: some View {
        PatternBorderedCard(edges: [.top], cornerRadius: 24, stripHeight: 10) {
            VStack(spacing: 32) {
                Color.clear.frame(height: 88)
                VStack(spacing: 18) {
                    HStack(spacing: 18) {
                        StatView(title: "Whole Session", value: wholeSessionText)
                        StatView(title: "Focus Duration", value: focusDurationText)
                    }
                    HStack(spacing: 18) {
                        StatView(title: "Distraction Count", value: distractionCountText)
                        StatView(title: "Distracted Duration", value: distractedDurationText)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
        }
        .overlay(alignment: .top) { playPreview.offset(y: -88) }
    }

    private var playPreview: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let frame = thumbnailImage {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFill()
                        .foregroundColor(.gray.opacity(0.5))
                        .background(Color.white)
                }
            }
            .frame(width: 208, height: 208)
            .clipShape(Circle())
            .shadow(color: .black, radius: 0, y: 3)
            .overlay {
                Image("AnalyticsPreviewRing")
                    .resizable()
                    .frame(width: 214, height: 214)
                    .accessibilityHidden(true)
            }

            Button(action: {
                guard playableVideoURL != nil else { return }
                isShowingWrappedVideo = true
            }) {
                Image(systemName: "arrowtriangle.forward.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.black))
            }
            .disabled(playableVideoURL == nil)
            .opacity(playableVideoURL == nil ? 0.45 : 1)
            .accessibilityLabel("Play session wrap video")
            .accessibilityHint(playableVideoURL == nil ? "The wrap is still finishing" : "Opens the timelapse video for this session")
            .accessibilityInputLabels(["play", "play video", "watch wrap"])
        }
        .accessibilityElement(children: .contain)
    }

    private var detailCard: some View {
        PatternBorderedCard(edges: [], cornerRadius: 24) {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(displayTitle)
                            .font(.custom("Special Gothic Expanded One", size: 20))
                            .multilineTextAlignment(.center)
                        Button {
                            editedTitle = session?.title ?? ""
                            editedSummary = session?.summary ?? ""
                            isEditingSession = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 16, weight: .heavy))
                        }
                        .buttonStyle(.plain)
                        .disabled(session == nil)
                        .accessibilityLabel("Edit session details")
                    }
                    .foregroundColor(.black)

                    Text(displaySummary)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 13))
                        .foregroundColor(Color("SessionDetailsBlack80"))
                        .lineSpacing(2)
                }

                if savedSnapshots.isEmpty {
                    snapshotsEmptyLabel
                } else {
                    snapshotRow
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
        }
    }

    private var editSessionForm: some View {
        NavigationStack {
            Form {
                TextField("Session title", text: $editedTitle)
                    .onChange(of: editedTitle) { _, value in
                        if value.count > 30 { editedTitle = String(value.prefix(30)) }
                    }
                TextField("How did it go?", text: $editedSummary, axis: .vertical)
                    .lineLimit(3...8)
            }
            .navigationTitle("Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isEditingSession = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveEditedDetails)
                        .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session == nil)
                }
            }
            .alert("Could not save changes", isPresented: $showEditError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your original session details are safe. Please try again.")
            }
        }
    }

    private func saveEditedDetails() {
        guard let session else { return }
        let title = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let previousTitle = session.title
        let previousSummary = session.summary
        session.title = title
        session.summary = editedSummary
        do {
            try context.save()
            isEditingSession = false
        } catch {
            session.title = previousTitle
            session.summary = previousSummary
            showEditError = true
        }
    }

    private var distractionsCard: some View {
        PatternBorderedCard(edges: [.bottom], cornerRadius: 24, stripHeight: 10) {
            VStack(spacing: 24) {
                Text("YOUR DISTRACTIONS")
                    .font(.custom("Special Gothic Expanded One", size: 12))
                    .foregroundStyle(Color("SessionDetailsBlack"))

                if distractionStat.distractions.isEmpty {
                    Text("No distractions recorded for this session.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color("SessionDetailsBlack80"))
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 0) {
                        ForEach(distractionStat.distractions) { distraction in
                            distractionRow(distraction)
                            if distraction.id != distractionStat.distractions.last?.id {
                                Divider().overlay(Color.black.opacity(0.2))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
        }
    }

    private func distractionRow(_ distraction: Distraction) -> some View {
        let token = distraction.tokenData.flatMap { try? JSONDecoder().decode(ApplicationToken.self, from: $0) }
        let reason = distraction.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = session.map { distraction.duration(overlapping: $0) } ?? max(distraction.distractionDuration, 0)
        return HStack(alignment: .top, spacing: 16) {
            Group {
                if let token {
                    Label(token).labelStyle(.iconOnly)
                } else {
                    Image(systemName: "questionmark.app.dashed")
                        .foregroundStyle(.gray)
                }
            }
            .font(.system(size: 30))
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(distraction.resolvedAppName ?? "Blocked App")
                        .font(.custom("Special Gothic Expanded One", size: 14))
                    Spacer(minLength: 0)
                    Text(TimeFormatter.shortDuration(duration))
                        .font(.system(size: 10))
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(reason.isEmpty ? "No reason recorded." : reason)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.8))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.black)
        }
        .padding(.vertical, 12)
        .padding(.trailing, 8)
        .accessibilityElement(children: .combine)
    }

    // No photos → keep this compact so the card doesn't reserve empty space.
    private var snapshotsEmptyLabel: some View {
        Text("No activity snapshots added for this session.")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    // Show only the photos that exist — each keeps its third-of-the-row
    // size, left-aligned, with no grey placeholder filling empty slots.
    //
    // Kept OUT of `detailCard` on purpose: folded into that one chained
    // expression it pushed Swift's type-checker past its per-expression time
    // limit, which broke SwiftUI previews across the module ("unable to
    // type-check this expression in reasonable time"). Small views = fast solve.
    private var snapshotRow: some View {
        GeometryReader { geo in
            let tile = (geo.size.width - 24) / 3   // two 12pt gaps → same size as a full 3-up row
            HStack(spacing: 12) {
                ForEach(Array(savedSnapshots.enumerated()), id: \.offset) { index, image in
                    snapshotTile(image: image, index: index, width: tile)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 153)
        .padding(.horizontal, 10)
    }

    // A fixed-size clear box owns the layout, so a landscape photo
    // can never stretch the row — the image just fills it and crops.
    private func snapshotTile(image: UIImage, index: Int, width: CGFloat) -> some View {
        Color.clear
            .frame(width: width, height: 153)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Activity snapshot \(index + 1)")
            .accessibilityHint("Opens snapshot full screen")
            .accessibilityAddTraits(.isButton)
            .onTapGesture {
                fullscreenSnapshot = FullscreenSnapshot(id: index)
            }
    }

    private var deleteButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showDeleteConfirm = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                Text("DELETE")
                    .font(.custom("Special Gothic Expanded One", size: 14))
            }
            .foregroundStyle(Color("SessionDetailsRed"))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(.white, in: Capsule())
            .overlay(Capsule().stroke(Color("SessionDetailsRed"), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete session")
        .accessibilityHint("Permanently deletes this session and its video")
        .accessibilityInputLabels(["delete", "remove session"])
    }

    // MARK: - Delete confirmation modal

    private var deleteConfirmation: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { dismissDeleteConfirm() }

            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 8) {
                    Text("Delete this Session")
                        .font(.custom("Special Gothic Expanded One", size: 22))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: dismissDeleteConfirm) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close")
                }

                Text("You're about to permanently delete your session, including the timelapse and analytics.\nAre you sure?")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(UIColor.darkGray))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                HStack(spacing: 14) {
                    Button {
                        showDeleteConfirm = false
                        deleteSession()
                    } label: {
                        Text("DELETE")
                            .font(.custom("Special Gothic Expanded One", size: 15))
                            .foregroundColor(Color("ButtonRed"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 30).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color("ButtonRed"), lineWidth: 2))
                    }
                    .accessibilityLabel("Confirm delete")
                    .accessibilityInputLabels(["delete", "confirm delete"])

                    Button(action: dismissDeleteConfirm) {
                        Text("CANCEL")
                            .font(.custom("Special Gothic Expanded One", size: 15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 30).fill(Color.black))
                    }
                    .accessibilityLabel("Cancel delete")
                    .accessibilityInputLabels(["cancel", "keep session"])
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.black, lineWidth: 2))
            .padding(.horizontal, 12)
        }
        .zIndex(2)
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }

    private func dismissDeleteConfirm() {
        withAnimation(.easeInOut(duration: 0.2)) { showDeleteConfirm = false }
    }

    // MARK: - Actions

    private func close() {
        if let onClose {
            // The live flow tears down recording and opens My Sessions.
            onClose()
        } else {
            // Opened from History: pop back to My Sessions.
            NotificationCenter.default.post(name: .returnToMySessionsTab, object: nil)
            dismiss()
        }
    }

    private func deleteSession() {
        if let session = session {
            // Free the video files this session left in app storage.
            WrapStorage.delete(path: session.wrappedVideoPath)
            WrapStorage.delete(path: session.rawClipPath)
            // Remove the copy saved to the user's Photos library (iOS shows its own
            // confirmation). Older sessions saved before this won't have an id.
            if let assetId = session.photoAssetId {
                PhotoLibrarySaver.deleteAsset(withLocalId: assetId)
            }
            for distraction in distractionStat.distractions { context.delete(distraction) }
            distractionStat.distractions = []
            context.delete(session)
            try? context.save()
        }
        close()
    }

    /// Extracts a poster frame from the saved wrapped video when no live capture
    /// frames were passed in, so History still shows a real video frame (never a
    /// user snapshot). Decoding happens off the main thread.
    private func loadThumbnailIfNeeded() async {
        guard videoFrames.isEmpty, extractedThumbnail == nil,
              let url = shareableVideoURL else { return }

        let frame = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = SessionRecordingViewModel.extractPreviewFrames(from: url, count: 1).first
                continuation.resume(returning: image)
            }
        }
        extractedThumbnail = frame
    }
}

// MARK: - Reusable Stat View Component

struct StatView: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.black.opacity(0.7))
            Text(value)
                .font(.custom("Special Gothic Expanded One", size: 28))
                .foregroundColor(.black)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.replacingOccurrences(of: " ", with: " ").lowercased().capitalized)
        .accessibilityValue(value)
    }
}

// MARK: - Fullscreen Snapshot Viewer

/// Identifies which snapshot to open in the fullscreen viewer.
struct FullscreenSnapshot: Identifiable {
    let id: Int
}

/// Fullscreen, swipeable viewer for the saved activity snapshots.
struct SnapshotViewer: View {
    let images: [UIImage]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int

    init(images: [UIImage], startIndex: Int) {
        self.images = images
        self.startIndex = startIndex
        _selection = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
            .accessibilityLabel("Activity snapshot viewer")
            .accessibilityValue("Snapshot \(selection + 1) of \(images.count)")

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close")
                    .accessibilityHint("Returns to session analytics")
                }
                Spacer()
            }
            .padding(20)
        }
    }
}

#Preview {
    SessionAnalytics(sessionId: UUID(), videoFrames: [])
        .modelContainer(for: Session.self, inMemory: true)
}
