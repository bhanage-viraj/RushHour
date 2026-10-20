// Utilities/SessionDeletion.swift

import Foundation
import SwiftData

/// Permanently removes a session: its break log, the session row itself, its video
/// files, and the copy saved to Photos.
enum SessionDeletion {
    /// The database delete is saved first; media is only removed once that succeeds.
    /// On failure the context is rolled back and the error is rethrown, so the session
    /// and all of its media are left untouched.
    @MainActor
    static func delete(_ session: Session, context: ModelContext) throws {
        let sessionId = session.id
        let wrappedPath = session.wrappedVideoPath
        let rawPath = session.rawClipPath
        let photoAssetId = session.photoAssetId

        do {
            let breaks = FetchDescriptor<Distraction>(predicate: #Predicate { $0.sessionId == sessionId })
            for distraction in try context.fetch(breaks) {
                context.delete(distraction)
            }
            context.delete(session)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        // Free the video files this session left in app storage.
        WrapStorage.delete(path: wrappedPath)
        WrapStorage.delete(path: rawPath)
        // Remove the copy saved to the user's Photos library (iOS shows its own
        // confirmation). Older sessions saved before this won't have an id.
        if let photoAssetId {
            PhotoLibrarySaver.deleteAsset(withLocalId: photoAssetId)
        }
    }
}
