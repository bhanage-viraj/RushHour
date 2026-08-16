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

    static func currentInterfaceOrientation() async -> UIInterfaceOrientation {
        // Always access UIApplication/UIScene on the main actor.
        return await MainActor.run { () -> UIInterfaceOrientation in
            interfaceOrientationFromApplication()
        }
    }

    static func currentInterfaceOrientationSync() -> UIInterfaceOrientation {
        if Thread.isMainThread {
            return interfaceOrientationFromApplication()
        }
        return DispatchQueue.main.sync {
            interfaceOrientationFromApplication()
        }
    }

    static func currentRecordingOrientationSync() -> UIInterfaceOrientation {
        if Thread.isMainThread {
            return physicalRecordingOrientation()
                ?? recordingOrientation(from: interfaceOrientationFromApplication())
        }
        return DispatchQueue.main.sync {
            physicalRecordingOrientation()
                ?? recordingOrientation(from: interfaceOrientationFromApplication())
        }
    }

    private static func interfaceOrientationFromApplication() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes
        let windowScenes = scenes.compactMap { $0 as? UIWindowScene }
        let active = windowScenes.first { $0.activationState == .foregroundActive }
        guard let scene = active ?? windowScenes.first else { return .portrait }
        if #available(iOS 26.0, *) {
            return scene.effectiveGeometry.interfaceOrientation
        }
        return scene.interfaceOrientation
    }

    private static func physicalRecordingOrientation() -> UIInterfaceOrientation? {
        switch UIDevice.current.orientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return isPhoneInterfaceIdiom() ? .portrait : .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return nil
        }
    }

    static func recordingOrientation(from orientation: UIInterfaceOrientation) -> UIInterfaceOrientation {
        guard orientation != .unknown else { return .portrait }

        // iPhone does not advertise portrait-upside-down in Info.plist. If UIKit briefly reports
        // that stale orientation at the first camera frame, encoding it would make the raw clip
        // and final wrap upside down on affected devices.
        if isPhoneInterfaceIdiom(), orientation == .portraitUpsideDown {
            return .portrait
        }

        return orientation
    }

    static func orientationName(_ orientation: UIInterfaceOrientation) -> String {
        switch orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .unknown: return "unknown"
        @unknown default: return "unknown(\(orientation.rawValue))"
        }
    }

    private static func isPhoneInterfaceIdiom() -> Bool {
        if Thread.isMainThread {
            return UIDevice.current.userInterfaceIdiom == .phone
        }
        return DispatchQueue.main.sync {
            UIDevice.current.userInterfaceIdiom == .phone
        }
    }

    /// Keeps the camera preview aligned with the app interface. On iPhone the interface is
    /// portrait-only, while the recording writer separately follows physical device orientation.
    static func applyToPreviewConnection(_ connection: AVCaptureConnection) async {
        let rawOrientation = await currentInterfaceOrientation()
        let orientation = recordingOrientation(from: rawOrientation)
        // Use `videoOrientation` instead of rotation angles.
        // This avoids inverted mappings across iOS versions/devices.
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = captureVideoOrientation(from: orientation)
        }
    }

    static func rotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        // This mapping matches what users expect visually:
        // holding phone upright (portrait) should produce an upright preview/video.
        case .portrait: return 270
        case .portraitUpsideDown: return 90
        case .landscapeLeft: return 0
        case .landscapeRight: return 180
        default: return 270
        }
    }

    static func captureVideoOrientation(from orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portrait
        }
    }

    /// Rotate/mirror sensor buffers so saved video is upright in the current interface orientation.
    static func writerTransform(
        bufferWidth: Int,
        bufferHeight: Int,
        cameraPosition: AVCaptureDevice.Position
    ) async -> CGAffineTransform {
        let rawOrientation = await currentInterfaceOrientation()
        let orientation = recordingOrientation(from: rawOrientation)
        return writerTransform(
            bufferWidth: bufferWidth,
            bufferHeight: bufferHeight,
            cameraPosition: cameraPosition,
            orientation: orientation
        )
    }

    static func writerTransform(
        bufferWidth: Int,
        bufferHeight: Int,
        cameraPosition: AVCaptureDevice.Position,
        orientation: UIInterfaceOrientation
    ) -> CGAffineTransform {
        let width = CGFloat(bufferWidth)
        let height = CGFloat(bufferHeight)
        let isLandscapeBuffer = bufferWidth > bufferHeight

        switch orientation {
        case .portrait:
            if isLandscapeBuffer {
                return portraitUpFromLandscapeBuffer(
                    width: width,
                    height: height,
                    cameraPosition: cameraPosition
                )
            }
            if cameraPosition == .front {
                return CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -width, y: 0)
            }
            return .identity

        case .portraitUpsideDown:
            if isLandscapeBuffer {
                return portraitDownFromLandscapeBuffer(
                    width: width,
                    height: height,
                    cameraPosition: cameraPosition
                )
            }
            if cameraPosition == .front {
                return CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -width, y: 0)
                    .rotated(by: .pi)
            }
            return CGAffineTransform(rotationAngle: .pi)

        case .landscapeLeft:
            if cameraPosition == .front {
                return CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -width, y: 0)
            }
            return .identity

        case .landscapeRight:
            if isLandscapeBuffer {
                return CGAffineTransform(rotationAngle: .pi)
            }
            return CGAffineTransform(rotationAngle: .pi)

        default:
            return portraitUpFromLandscapeBuffer(
                width: width,
                height: height,
                cameraPosition: cameraPosition
            )
        }
    }

    // MARK: - Portrait from landscape sensor buffer (typical iPhone)

    private static func portraitUpFromLandscapeBuffer(
        width: CGFloat,
        height: CGFloat,
        cameraPosition: AVCaptureDevice.Position
    ) -> CGAffineTransform {
        // Standard portrait fix for landscape sensor buffers:
        // rotate +90° then translate up by -width.
        let base = CGAffineTransform(rotationAngle: .pi / 2)
            .translatedBy(x: 0, y: -width)

        if cameraPosition == .front {
            // Mirror for selfie camera after rotation.
            return base
                .scaledBy(x: -1, y: 1)
                .translatedBy(x: -height, y: 0)
        }

        return base
    }

    private static func portraitDownFromLandscapeBuffer(
        width: CGFloat,
        height: CGFloat,
        cameraPosition: AVCaptureDevice.Position
    ) -> CGAffineTransform {
        // Upside-down portrait: rotate -90° then translate left by -height.
        let base = CGAffineTransform(rotationAngle: -.pi / 2)
            .translatedBy(x: -height, y: 0)

        if cameraPosition == .front {
            return base
                .scaledBy(x: -1, y: 1)
                .translatedBy(x: -width, y: 0)
        }

        return base
    }
}
