//
//  PhotoLibrarySaver.swift
//  lucky7
//

import Photos
import UIKit

enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Photo library access was denied. Enable it in Settings to save your wrap."
            case .failed(let message):
                return message
            }
        }
    }

    static func requestAddPermissionIfNeeded() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    /// Saves the video and returns the new asset's Photos local identifier, so the
    /// session can delete exactly this copy from the library later.
    @discardableResult
    static func saveVideo(at url: URL) async throws -> String? {
        guard await requestAddPermissionIfNeeded() else {
            throw SaveError.denied
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, Error>) in
            var localId: String?
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                localId = request?.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: SaveError.failed(error.localizedDescription))
                } else if success {
                    continuation.resume(returning: localId)
                } else {
                    continuation.resume(throwing: SaveError.failed("Could not save video to Photos."))
                }
            }
        }
    }

    /// Saves a single image as PNG data so transparent share overlays retain their alpha channel.
    static func saveImage(_ image: UIImage) async throws {
        guard await requestAddPermissionIfNeeded() else {
            throw SaveError.denied
        }
        guard let pngData = image.pngData() else {
            throw SaveError.failed("Could not prepare photo for saving.")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "RushHourWrap-\(UUID().uuidString).png"
                request.addResource(with: .photo, data: pngData, options: options)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: SaveError.failed(error.localizedDescription))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SaveError.failed("Could not save photo to Photos."))
                }
            }
        }
    }

    /// Removes a previously-saved wrap from the Photos library. iOS shows its own
    /// deletion confirmation. No-ops if the id is missing or the asset is already gone.
    static func deleteAsset(withLocalId id: String) {
        Task {
            // Deleting needs read-write access (add-only can't fetch the asset to delete).
            // iOS still shows its own deletion confirmation for app-created assets.
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else { return }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            guard assets.firstObject != nil else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            } completionHandler: { _, _ in }
        }
    }
}
