//
//  SessionDetails.swift
//  lucky7
//
//  Created by Kadek Belvanatha Gargita Satwikananda on 27/05/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct SessionDetails: View {
    var sessionId: UUID
    var videoFrames: [UIImage] = []
    var onSave: (() -> Void)? = nil
    var onFlowComplete: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var sessionRecording: SessionRecordingViewModel
    @Query private var sessions: [Session]

    @State private var sessionTitle = ""
    @State private var sessionDescription = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var uploadedSnapshots: [UIImage] = []
    @State private var showImageSourceDialog = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var isSaving = false
    @State private var showDiscardConfirm = false
    @State private var didDiscard = false
    @State private var hasLoadedDraft = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var backgroundWrapTask: Task<Void, Never>?

    // Drives the darker "active" outline on whichever field is in use.
    @FocusState private var focusedField: Field?
    private enum Field { case title, description }

    private let maxSnapshots = 6
    private let maxTitleLength = 30
    private let staleRollupSliceMaxSeconds: TimeInterval = 5

    // filtering only 3 frames for snapshots
    private var displayFrame: [UIImage] {
        let sourceFrames = videoFrames.isEmpty ? sessionRecording.previewFrames : videoFrames
        guard !sourceFrames.isEmpty else { return [] }

        if sourceFrames.count <= 3 {
            return sourceFrames
        }

        let firstFrame = sourceFrames.first!
        let middleFrame = sourceFrames[sourceFrames.count / 2]
        let lastFrame = sourceFrames.last!

        return [firstFrame, middleFrame, lastFrame]
    }

    /// The snapshots field counts as "active" while its picker / camera / dialog is open.
    private var snapshotFieldActive: Bool {
        showImageSourceDialog || showCamera || showLibrary
    }

    private var canSave: Bool {
        !sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addSnapshot(_ image: UIImage) {
        guard uploadedSnapshots.count < maxSnapshots else { return }
        uploadedSnapshots.append(downscaled(image))
    }

    /// Shrinks large photos so storing/decoding several of them doesn't spike memory.
    private func downscaled(_ image: UIImage, maxDimension: CGFloat = 1080) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension else { return image }
        let scale = maxDimension / longestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    var body: some View {
        NavigationStack {
            detailsContent
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showDiscardConfirm = true }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(isSaving)
                        .tint(.white)
                        .accessibilityLabel("Back")
                        .accessibilityHint("Asks before discarding this session")
                    }
                }
        }
        .overlay {
            Color.black.opacity(showDiscardConfirm ? 0.3 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.2), value: showDiscardConfirm)
        .sheet(isPresented: $showDiscardConfirm) {
            ScrollView(showsIndicators: false) {
                discardConfirmation
            }
            .scrollBounceBehavior(.basedOnSize)
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(250)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
            .presentationBackground(.white)
        }
        .interactiveDismissDisabled()
    }

    private var detailsContent: some View {
        ZStack {
            Color("SessionDetailsBlue")
                .overlay {
                    Image("SessionDetailsPattern")
                        .resizable()
                        .frame(width: 786.807, height: 786.807)
                        .accessibilityDecorative()
                }
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    sessionCard
                        .disabled(isSaving)
                        .opacity(isSaving ? 0.6 : 1)
                        .animation(.easeInOut(duration: 0.2), value: isSaving)
                    saveButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 1)
                .padding(.bottom, 40)
                .frame(maxWidth: 450)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(showDiscardConfirm)
        .onAppear {
            loadSessionDraft()
            restoreRecoverableVideoState()
            scheduleBackgroundWrapExport()
        }
        .onDisappear {
            backgroundWrapTask?.cancel()
        }
        .alert("Could not save session", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }

    // MARK: - Card

    private var sessionCard: some View {
        PatternBorderedCard(cornerRadius: 24, stripHeight: 10) {
            VStack(spacing: 24) {
                VStack(spacing: 20) {
                    SnapshotsView(images: displayFrame)
                        .scaleEffect(0.941)
                        .frame(height: 92)

                    Text("How was your session?")
                        .font(.custom("Special Gothic Expanded One", size: 22))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 28)
                }

                VStack(spacing: 16) {
                    LabeledField(title: "TITLE", isRequired: true) {
                        TextField("", text: $sessionTitle)
                            .font(.system(size: 15))
                            .foregroundColor(.black)
                            .tint(Color("SessionDetailsBlack80"))
                            .fixedPlaceholder("Give your session a title", isEmpty: sessionTitle.isEmpty, font: .system(size: 15))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                            .focused($focusedField, equals: .title)
                            .formFieldStyle(isActive: focusedField == .title)
                            .accessibilityLabel("Session title")
                            .accessibilityHint("Up to \(maxTitleLength) characters")
                            .onChange(of: sessionTitle) { _, newValue in
                                if newValue.count > maxTitleLength {
                                    sessionTitle = String(newValue.prefix(maxTitleLength))
                                }
                            }
                    }

                    LabeledField(title: "HOW DID IT GO?") {
                        TextField(
                            "",
                            text: $sessionDescription,
                            axis: .vertical
                        )
                        .lineLimit(2...8)
                        .font(.system(size: 15))
                        .foregroundColor(.black)
                        .tint(Color("SessionDetailsBlack80"))
                        .fixedPlaceholder("How do you feel during and after the session?", isEmpty: sessionDescription.isEmpty, font: .system(size: 15), alignment: .topLeading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                        .focused($focusedField, equals: .description)
                        .formFieldStyle(isActive: focusedField == .description)
                        .accessibilityLabel("Session description")
                        .accessibilityHint("How you felt during and after the session")
                    }

                    LabeledField(title: "ACTIVITIES SNAPSHOTS") {
                        snapshotsField
                    }
                }
            }
            .padding(.horizontal, 23)
            .padding(.vertical, 48)
            .frame(minHeight: 594)
        }
    }

    // MARK: - Snapshots field

    @ViewBuilder
    private var snapshotsField: some View {
        Group {
            if uploadedSnapshots.isEmpty {
                Button {
                    showImageSourceDialog = true
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 22))
                            .foregroundColor(.black)

                        Text("Add Photos/Video")
                            .font(.system(size: 13, weight: .bold))
                            .frame(minHeight: 18)
                            .foregroundColor(Color("SessionDetailsBlack"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .frame(minHeight: 104)
                }
                .formFieldStyle(isActive: snapshotFieldActive)
                .accessibilityLabel("Add activity snapshots")
                .accessibilityHint("Take a photo or choose from your library")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(uploadedSnapshots.enumerated()), id: \.offset) { index, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        uploadedSnapshots.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 20))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black)
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove snapshot \(index + 1)")
                                }
                        }

                        if uploadedSnapshots.count < maxSnapshots {
                            Button {
                                showImageSourceDialog = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.black)
                                    .frame(width: 80, height: 80)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.black.opacity(0.06))
                                    )
                            }
                            .accessibilityLabel("Add another snapshot")
                        }
                    }
                    .padding(12)
                }
                .formFieldStyle(isActive: snapshotFieldActive)
            }
        }
        .confirmationDialog("Add a snapshot", isPresented: $showImageSourceDialog, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") { showCamera = true }
            }
            Button("Choose from Library") { showLibrary = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showLibrary,
            selection: $pickerItems,
            maxSelectionCount: max(1, maxSnapshots - uploadedSnapshots.count),
            matching: .images
        )
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                addSnapshot(image)
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var newImages: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        newImages.append(img)
                    }
                }
                await MainActor.run {
                    for img in newImages { addSnapshot(img) }
                    pickerItems = []
                }
            }
        }
    }

    // MARK: - Discard confirmation

    private var discardConfirmation: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Discard Session?")
                    .font(.custom("Special Gothic Expanded One", size: 22))
                Text("Your recorded session and analytics will be deleted permanently if you discard this session without saving.")
                    .font(.system(size: 17))
            }
            .foregroundStyle(Color.black.opacity(0.8))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(action: discardSession) {
                    Text("DISCARD")
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(Color("SessionDetailsRed"))
                        .background(.white, in: Capsule())
                        .overlay(Capsule().stroke(Color("SessionDetailsRed"), lineWidth: 1))
                }
                .accessibilityLabel("Discard session permanently")

                Button(action: dismissDiscardConfirm) {
                    Text("CANCEL")
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(Color("SessionDetailsBlack"), in: Capsule())
                }
            }
            .font(.custom("Special Gothic Expanded One", size: 14))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 32)
        .padding(.bottom, 20)
        .frame(maxWidth: 450)
        .overlay(alignment: .topTrailing) {
            Button(action: dismissDiscardConfirm) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color("SessionDetailsBlack80"))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 5)
            .padding(.trailing, 7)
            .accessibilityLabel("Keep session")
        }
    }

    private func dismissDiscardConfirm() {
        withAnimation(.easeInOut(duration: 0.2)) { showDiscardConfirm = false }
    }

    private func discardSession() {
        guard !isSaving, !didDiscard else { return }
        let id = sessionId
        do {
            var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let session = try context.fetch(descriptor).first
            let distractions = try context.fetch(FetchDescriptor<Distraction>(predicate: #Predicate { $0.sessionId == id }))
            let wrappedPath = session?.wrappedVideoPath
            let rawPath = session?.rawClipPath
            for distraction in distractions { context.delete(distraction) }
            if let session { context.delete(session) }
            try context.save()

            didDiscard = true
            backgroundWrapTask?.cancel()
            focusedField = nil
            sessionRecording.discardCurrentSession()
            WrapStorage.delete(path: wrappedPath)
            WrapStorage.delete(path: rawPath)
            SessionEndRecovery.clear(sessionId)
            if let onFlowComplete { onFlowComplete() } else { dismiss() }
        } catch {
            context.rollback()
            dismissDiscardConfirm()
            saveErrorMessage = "Could not discard your session. Please try again."
            showSaveError = true
        }
    }

    // MARK: - Save button

    private var saveButton: some View {
        Button(action: saveSession) {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                Text(isSaving ? "FINISHING WRAP..." : "SAVE")
                    .font(.custom("Special Gothic Expanded One", size: 14))
            }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(Color("SessionDetailsBlack"))
                .clipShape(Capsule())
                .opacity(isSaveActionable ? 1 : 0.5)
                .animation(.easeInOut(duration: 0.2), value: isSaveActionable)
        }
        .disabled(!canSave || isSaving)
        .accessibilityLabel(isSaving ? "Finishing session wrap" : "Save session")
        .accessibilityHint(accessibilitySaveHint)
        .accessibilityInputLabels(["save", "save session", "export"])
        .accessibilityAddTraits(isSaving ? .updatesFrequently : [])
    }

    /// True only when tapping does something — drives the dimmed disabled look.
    private var isSaveActionable: Bool { canSave && !isSaving }

    private var accessibilitySaveHint: String {
        if isSaving {
            return "Please wait while Rush Hour generates and saves your wrap"
        }
        return canSave ? "Saves your session details and exports the session video" : "Add a title to save"
    }

    private var exportTitle: String {
        let trimmed = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled session" : trimmed
    }

    private var currentSessionDuration: TimeInterval {
        sessions.first(where: { $0.id == sessionId })?.actualDuration ?? 0
    }

    private func scheduleBackgroundWrapExport() {
        guard !isSaving else { return }
        backgroundWrapTask?.cancel()
        let duration = currentSessionDuration
        backgroundWrapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            sessionRecording.reexportWithTitle(
                exportTitle,
                durationSeconds: duration,
                saveToPhotos: false
            ) { finalURL in
                guard let finalURL, FileManager.default.fileExists(atPath: finalURL.path) else { return }
                persistFinalWrap(finalURL, reason: "background export")
            }
        }
    }

    private func saveSession() {
        guard canSave, !isSaving else { return }

        backgroundWrapTask?.cancel()
        isSaving = true
        var sessionDuration: TimeInterval = 0
        let snapshotsToExport = uploadedSnapshots
        if let session = sessions.first(where: { $0.id == sessionId }) {
            session.title = sessionTitle
            session.summary = sessionDescription
            if let rawName = sessionRecording.rawClipURL?.lastPathComponent {
                session.rawClipPath = rawName
            }
            sessionDuration = session.actualDuration
            try? context.save()
            RecordingDiagnostics.log("SessionDetails saved text session=\(sessionId) raw=\(session.rawClipPath ?? "nil") wrapped=\(session.wrappedVideoPath ?? "nil")")
        }

        // The durable result is text-free; title and duration are applied only when sharing.
        sessionRecording.reexportWithTitle(
            exportTitle,
            durationSeconds: sessionDuration,
            saveToPhotos: false
        ) { finalURL in
            guard let finalURL, FileManager.default.fileExists(atPath: finalURL.path) else {
                isSaving = false
                saveErrorMessage = sessionRecording.lastError
                    ?? "Rush Hour is still generating your wrap. Keep the app open while it retries."
                showSaveError = true
                return
            }
            persistFinalWrap(finalURL, reason: "save final callback", snapshots: snapshotsToExport)

            Task {
                for image in snapshotsToExport {
                    try? await PhotoLibrarySaver.saveImage(image)
                }

                await MainActor.run {
                    isSaving = false
                    SessionEndRecovery.clear(sessionId)
                    onSave?()
                }
            }
        }
    }

    private func restoreRecoverableVideoState() {
        guard let session = sessions.first(where: { $0.id == sessionId }) else {
            RecordingDiagnostics.log("SessionDetails restore skipped missing session=\(sessionId)")
            return
        }

        let wrapped = WrapStorage.resolveVideoURL(session.wrappedVideoPath)
        let raw = WrapStorage.resolveVideoURL(session.rawClipPath)
        RecordingDiagnostics.log("SessionDetails restore session=\(sessionId) storedWrapped=\(session.wrappedVideoPath ?? "nil") resolvedWrapped=\(wrapped?.lastPathComponent ?? "nil") storedRaw=\(session.rawClipPath ?? "nil") resolvedRaw=\(raw?.lastPathComponent ?? "nil")")
        sessionRecording.restoreExportContext(
            rawURL: exportableRawSource(for: session, rawURL: raw, wrappedURL: wrapped),
            finalURL: wrapped
        )
    }

    private func loadSessionDraft() {
        guard !hasLoadedDraft, let session = sessions.first(where: { $0.id == sessionId }) else { return }
        hasLoadedDraft = true
        if sessionTitle.isEmpty {
            sessionTitle = session.title
        }
        if sessionDescription.isEmpty {
            sessionDescription = session.summary
        }
        if uploadedSnapshots.isEmpty {
            uploadedSnapshots = session.snapshotImages.compactMap { UIImage(data: $0) }
        }
    }

    private func persistFinalWrap(_ finalURL: URL, reason: String) {
        persistFinalWrap(finalURL, reason: reason, snapshots: nil)
    }

    private func persistFinalWrap(_ finalURL: URL, reason: String, snapshots: [UIImage]?) {
        guard !didDiscard, let session = sessions.first(where: { $0.id == sessionId }) else { return }
        session.wrappedVideoPath = finalURL.lastPathComponent
        if let rawName = sessionRecording.rawClipURL?.lastPathComponent {
            session.rawClipPath = rawName
        }
        if let snapshots {
            session.snapshotImages = snapshots.compactMap {
                $0.jpegData(compressionQuality: 0.8)
            }
        }
        try? context.save()
        RecordingDiagnostics.log("SessionDetails persist final reason=\(reason) session=\(sessionId) final=\(finalURL.lastPathComponent) raw=\(session.rawClipPath ?? "nil")")
    }

    private func exportableRawSource(for session: Session, rawURL: URL?, wrappedURL: URL?) -> URL? {
        guard let rawURL else { return nil }
        guard wrappedURL == nil else { return rawURL }

        let rawSeconds = Double(SessionRecordingViewModel.estimatedFrameCount(from: rawURL)) / AppConstants.wrappedOutputFPS
        if session.focusDuration() >= 15 * 60, rawSeconds <= staleRollupSliceMaxSeconds {
            RecordingDiagnostics.log("SessionDetails restore skipped short raw source session=\(sessionId) raw=\(rawURL.lastPathComponent) seconds=\(String(format: "%.2f", rawSeconds))")
            return nil
        }
        return rawURL
    }
}

// MARK: - Camera Capture

/// Wraps `UIImagePickerController` so a snapshot can be taken straight from the camera.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Reusable Custom Components

/// White card with a rounded-rectangle clip mask and the `BlackWhitePattern`
/// checkerboard strip pinned to the chosen edges (ticket-style border).
struct PatternBorderedCard<Content: View>: View {
    var edges: Set<VerticalEdge>
    var cornerRadius: CGFloat
    var stripHeight: CGFloat
    let content: Content

    init(
        edges: Set<VerticalEdge> = [.top, .bottom],
        cornerRadius: CGFloat = 28,
        stripHeight: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.edges = edges
        self.cornerRadius = cornerRadius
        self.stripHeight = stripHeight
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .overlay(alignment: .top) {
                if edges.contains(.top) {
                    Image("BlackWhitePattern")
                        .resizable()
                        .frame(height: stripHeight)
                }
            }
            .overlay(alignment: .bottom) {
                if edges.contains(.bottom) {
                    Image("BlackWhitePattern")
                        .resizable()
                        .frame(height: stripHeight)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.black, lineWidth: 2)
            )
    }
}

/// A left-aligned uppercase label sitting above a form control.
struct LabeledField<Content: View>: View {
    let title: String
    var isRequired: Bool
    let content: Content

    init(title: String, isRequired: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.isRequired = isRequired
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .frame(minHeight: 13)
                .foregroundColor(Color("SessionDetailsBlack80"))
                .accessibilityLabel(isRequired ? "\(title), required" : title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// White rounded-rectangle field with a dark outline. The outline darkens and
    /// thickens while the field is active (focused, or its picker is open).
    func formFieldStyle(isActive: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color("SessionDetailsBlack80"), lineWidth: isActive ? 2 : 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    /// Overlays a fixed-grey placeholder while `isEmpty` is true. The system placeholder
    /// turns light in dark mode and vanishes on our white fields, so we draw our own with
    /// a non-adaptive colour that stays legible in both light and dark mode.
    func fixedPlaceholder(_ text: String, isEmpty: Bool, font: Font, alignment: Alignment = .leading) -> some View {
        overlay(alignment: alignment) {
            Text(text)
                .font(font)
                .foregroundColor(Color("SessionDetailsBlack80").opacity(0.6))
                .allowsHitTesting(false)
                .opacity(isEmpty ? 1 : 0)
        }
    }
}

struct SnapshotsView: View {
    var images: [UIImage]

    var body: some View {
        ZStack {
            if images.count > 1 {
                Image(uiImage: images[1])
                    .resizable()
                    .scaledToFill()
                    .frame(width: 61, height: 81)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black, radius: 0, x: 0, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 1))
                    .rotationEffect(.degrees(-11))
                    .offset(x: -34, y: 5)
            }

            if images.count > 2 {
                Image(uiImage: images[2])
                    .resizable()
                    .scaledToFill()
                    .frame(width: 61, height: 81)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black, radius: 0, x: 0, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 1))
                    .rotationEffect(.degrees(11))
                    .offset(x: 34, y: 5)
            }

            if images.count > 0 {
                Image(uiImage: images[0])
                    .resizable()
                    .scaledToFill()
                    .frame(width: 68, height: 91)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black, radius: 0, x: 0, y: 5)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 1))
                    .zIndex(1)
            }
        }
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session video preview frames")
        .accessibilityValue("\(images.count) preview frames")
    }
}

struct CardInput<Content: View>: View {
    let title: String
    var backgroundColor: Color
    let content: Content

    init(title: String, backgroundColor: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.backgroundColor = backgroundColor
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            backgroundColor
                .cornerRadius(20)
                .shadow(color: .black, radius: 0, x: 0, y: 4)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.black, lineWidth: 1))
                .padding(.top, 12)

            content
                .padding(.top, 12)

            Text(title)
                .font(.custom("Special Gothic Expanded One", size: 10))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black)
                .clipShape(Capsule())
                .offset(y: -2)
        }
    }
}

#Preview {
    let dummyFrames = ["dummySnapshot1", "dummySnapshot2", "dummySnapshot3"]
        .compactMap { UIImage(named: $0) }

    return SessionDetails(sessionId: UUID(), videoFrames: dummyFrames)
        .environmentObject(SessionRecordingViewModel())
        .modelContainer(for: Session.self, inMemory: true)
}
