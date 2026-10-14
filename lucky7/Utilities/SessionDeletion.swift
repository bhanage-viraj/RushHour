// Utilities/SessionDeletion.swift

import Foundation
import SwiftData

/// Permanently removes a session: its video files, the copy saved to Photos,
/// its break log, and the session row itself.
enum SessionDeletion {
    @MainActor
    static func delete(_ session: Session, context: ModelContext) {
        // Free the video files this session left in app storage.
        WrapStorage.delete(path: session.wrappedVideoPath)
        WrapStorage.delete(path: session.rawClipPath)
        // Remove the copy saved to the user's Photos library (iOS shows its own
        // confirmation). Older sessions saved before this won't have an id.
        if let assetId = session.photoAssetId {
            PhotoLibrarySaver.deleteAsset(withLocalId: assetId)
        }

        let sessionId = session.id
        let breaks = FetchDescriptor<Distraction>(predicate: #Predicate { $0.sessionId == sessionId })
        for distraction in (try? context.fetch(breaks)) ?? [] {
            context.delete(distraction)
        }

        context.delete(session)
        try? context.save()
    }
}
