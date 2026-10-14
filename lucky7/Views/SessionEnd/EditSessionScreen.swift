//
//  EditSessionScreen.swift
//  lucky7
//

import SwiftUI
import SwiftData
import UIKit

/// Edits a saved session's title and description, using the same card as the
/// session-end form. No wrap re-export is needed: the stored master is text-free
/// and the title is only applied when sharing, so it picks up the new value.
struct EditSessionScreen: View {
    let session: Session
    var previewFrames: [UIImage] = []

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var sessionTitle: String
    @State private var sessionDescription: String

    init(session: Session, previewFrames: [UIImage] = []) {
        self.session = session
        self.previewFrames = previewFrames
        _sessionTitle = State(initialValue: session.title)
        _sessionDescription = State(initialValue: session.summary)
    }

    private var canSave: Bool {
        !sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                editCard
                saveButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background {
            Color("CanvasBlue")
                .overlay {
                    Image("PatternBackground")
                        .resizable()
                        .scaledToFill()
                        .offset(y: -30)
                }
                .clipped()
                .ignoresSafeArea()
                .accessibilityDecorative()
        }
        // Pushed from Session Analytics: the system back button leaves without saving.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)   // white glyphs on the blue backdrop
        .hidesFloatingTabBar()
    }

    // MARK: - Card

    private var editCard: some View {
        PatternBorderedCard {
            VStack(spacing: 22) {
                if !previewFrames.isEmpty {
                    SnapshotsView(images: previewFrames)
                }

                Text("Edit your session")
                    .font(.custom("Special Gothic Expanded One", size: 22))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)

                SessionTextFields(title: $sessionTitle, description: $sessionDescription)
            }
            .padding(.horizontal, 22)
            .padding(.top, 32)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Save button

    private var saveButton: some View {
        Button(action: save) {
            Text("SAVE")
                .font(.custom("Special Gothic Expanded One", size: 16))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .opacity(canSave ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.2), value: canSave)
        }
        .disabled(!canSave)
        .accessibilityLabel("Save changes")
        .accessibilityHint(canSave ? "Updates this session's title and description" : "Add a title to save")
        .accessibilityInputLabels(["save", "save changes", "done"])
    }

    private func save() {
        guard canSave else { return }
        session.title = sessionTitle
        session.summary = sessionDescription
        try? context.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        EditSessionScreen(
            session: Session(userId: UUID(), duration: 1500, title: "Deep work", summary: "Felt focused.")
        )
    }
    .modelContainer(for: Session.self, inMemory: true)
}
