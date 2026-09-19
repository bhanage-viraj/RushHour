//
//  VideoOrientationHelper.swift
//  lucky7
//

import AVFoundation
import UIKit

enum VideoOrientationHelper {
    static func presentationSize(for url: URL) async -> CGSize? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }
        return try? await presentationSize(for: track)
    }

    static func presentationSize(for track: AVAssetTrack) async throws -> CGSize {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
    }

    /// Preview policy is portrait for both cameras, independent of recording orientation.
    /// Changing only values that differ avoids reconfiguring the preview on every layout.
    static func configurePortraitPreview(_ connection: AVCaptureConnection, mirrored: Bool) {
        if connection.isVideoOrientationSupported, connection.videoOrientation != .portrait {
            connection.videoOrientation = .portrait
        }
        if connection.automaticallyAdjustsVideoMirroring {
            connection.automaticallyAdjustsVideoMirroring = false
        }
        if connection.isVideoMirroringSupported, connection.isVideoMirrored != mirrored {
            connection.isVideoMirrored = mirrored
        }
    }

    /// Rotate sensor pixels first, normalize the bounds, then mirror horizontally in
    /// presentation coordinates. The coordinator supplies the camera-specific angle.
    static func writerTransform(
        bufferWidth: Int,
        bufferHeight: Int,
        rotationAngle: CGFloat,
        mirrored: Bool
    ) -> CGAffineTransform {
        let rotation = CGAffineTransform(rotationAngle: rotationAngle * .pi / 180)
        let bounds = CGRect(x: 0, y: 0, width: bufferWidth, height: bufferHeight).applying(rotation)
        let normalized = rotation.concatenating(
            CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
        )
        guard mirrored else { return normalized }
        return normalized.concatenating(
            CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: bounds.width, ty: 0)
        )
    }
}

extension Notification.Name {
    static let cameraConfigurationDidChange = Notification.Name("rushhour.cameraConfigurationDidChange")
}
