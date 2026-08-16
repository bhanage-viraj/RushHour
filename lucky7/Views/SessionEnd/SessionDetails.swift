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
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var backgroundWrapTask: Task<Void, Never>?

    // Drives the darker "active" outline on whichever field is in use.
    @FocusState private var focusedField: Field?
    private enum Field { case title, description }

    private let maxSnapshots = 6
    private let maxTitleLength = 30
    private let staleRollupSliceMaxSeconds: TimeInterval = 5

    /// Dark navy fill for the SAVE button (matches the design mock-up).
    private let saveButtonColor = Color(red: 30 / 255, green: 58 / 255, blue: 95 / 255)
    private let disabledSaveButtonColor = Color(red: 155 / 255, green: 164 / 255, blue: 174 / 255)

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
        ZStack {
            Color("CanvasBlue")
                .ignoresSafeArea()

            Image("PatternBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .offset(y: -30)
                .accessibilityDecorative()

            ScrollView {
                VStack(spacing: 24) {
                    sessionCard
                        .disabled(isSaving)
                    saveButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            loadSessionDraft()
            restoreRecoverableVideoState()
            scheduleBackgroundWrapExport()
        }
        .onDisappear {
            backgroundWrapTask?.cancel()
        }
        .alert("Could not create wrap", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }

    // MARK: - Card

    private var sessionCard: some View {
        PatternBorderedCard {
            VStack(spacing: 22) {
                SnapshotsView(images: displayFrame)

                Text("How was your session?")
                    .font(.custom("Special Gothic Expanded One", size: 22))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)

                LabeledField(title: "TITLE", isRequired: true) {
                    TextField("", text: $sessionTitle)
                        .font(.system(size: 15))
                        .foregroundColor(.black)
                        .fixedPlaceholder("Give your session a title", isEmpty: sessionTitle.isEmpty, font: .system(size: 15))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .lineLimit(3...8)
                    .font(.system(size: 15))
                    .foregroundColor(.black)
                    .fixedPlaceholder("How do you feel during and after the session?", isEmpty: sessionDescription.isEmpty, font: .system(size: 15), alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .focused($focusedField, equals: .description)
                    .formFieldStyle(isActive: focusedField == .description)
                    .accessibilityLabel("Session description")
                    .accessibilityHint("How you felt during and after the session")
                }

                LabeledField(title: "ACTIVITIES SNAPSHOTS") {
                    snapshotsField
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 32)
            .padding(.bottom, 30)
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
                            .font(.system(size: 30))
                            .foregroundColor(.black)

                        Text("Add Photos/Video")
                            .font(.custom("Special Gothic Expanded One", size: 14))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
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
                    .font(.custom("Special Gothic Expanded One", size: 16))
            }
                .foregroundColor(.white.opacity(canSave || isSaving ? 1 : 0.72))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(saveButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 30))
        }
        .disabled(!canSave || isSaving)
        .accessibilityLabel(isSaving ? "Finishing session wrap" : "Save session")
        .accessibilityHint(accessibilitySaveHint)
        .accessibilityInputLabels(["save", "save session", "export"])
        .accessibilityAddTraits(isSaving ? .updatesFrequently : [])
    }

    private var saveButtonBackground: Color {
        if isSaving {
            return saveButtonColor
        }
        return canSave ? saveButtonColor : disabledSaveButtonColor
    }

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
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
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
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
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
        if session.actualDuration >= 15 * 60, rawSeconds <= staleRollupSliceMaxSeconds {
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
    let content: Content

    init(
        edges: Set<VerticalEdge> = [.top, .bottom],
        cornerRadius: CGFloat = 28,
        @ViewBuilder content: () -> Content
    ) {
        self.edges = edges
        self.cornerRadius = cornerRadius
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
                        .frame(height: 12)
                }
            }
            .overlay(alignment: .bottom) {
                if edges.contains(.bottom) {
                    Image("BlackWhitePattern")
                        .resizable()
                        .frame(height: 12)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                Text(title)
                if isRequired {
                    Text("*")
                        .accessibilityLabel("required")
                }
            }
            .font(.custom("Special Gothic Expanded One", size: 11))
            .foregroundColor(.black)
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
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(isActive ? 0.9 : 0.35), lineWidth: isActive ? 2 : 1.5)
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
                .foregroundColor(Color(white: 0.45))
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
