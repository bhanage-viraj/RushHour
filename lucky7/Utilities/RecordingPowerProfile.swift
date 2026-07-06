import AVFoundation
import Foundation

struct RecordingPowerProfile {
    struct Applied {
        let requestedFPS: Double
        let appliedFPS: Double
        let minSupportedFPS: Double
        let maxSupportedFPS: Double
        let formatChanged: Bool
        let width: Int32
        let height: Int32
    }

    let plannedSessionSeconds: TimeInterval
    let captureIntervalSeconds: TimeInterval
    let requestedFPS: Double

    static func recording(plannedSessionSeconds: TimeInterval) -> RecordingPowerProfile {
        let planned = max(plannedSessionSeconds, AppConstants.minimumPlannedSessionSeconds)
        let interval = AppConstants.captureIntervalSeconds(plannedSessionSeconds: planned)
        let naturalFPS = ceil((1 / interval) * 2)
        let fps = min(
            max(naturalFPS, AppConstants.minimumRecordingCameraFPS),
            AppConstants.maximumRecordingCameraFPS
        )
        return RecordingPowerProfile(
            plannedSessionSeconds: planned,
            captureIntervalSeconds: interval,
            requestedFPS: fps
        )
    }

    static var preview: RecordingPowerProfile {
        RecordingPowerProfile(
            plannedSessionSeconds: 0,
            captureIntervalSeconds: 0,
            requestedFPS: 30
        )
    }

    func apply(to device: AVCaptureDevice) throws -> Applied {
        try device.lockForConfiguration()
        let originalFormat = device.activeFormat
        let selectedFormat = Self.preferredFormat(on: device, requestedFPS: requestedFPS)
        let formatChanged = selectedFormat !== originalFormat
        if formatChanged {
            device.activeFormat = selectedFormat
        }

        let ranges = selectedFormat.videoSupportedFrameRateRanges
        let minSupported = ranges.map(\.minFrameRate).min() ?? 1
        let maxSupported = ranges.map(\.maxFrameRate).max() ?? 30
        let appliedFPS = min(max(requestedFPS, minSupported), maxSupported)
        let frameDuration = CMTime(seconds: 1 / appliedFPS, preferredTimescale: 600)

        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
        device.unlockForConfiguration()
        let dimensions = Self.dimensions(of: selectedFormat)

        return Applied(
            requestedFPS: requestedFPS,
            appliedFPS: appliedFPS,
            minSupportedFPS: minSupported,
            maxSupportedFPS: maxSupported,
            formatChanged: formatChanged,
            width: dimensions.width,
            height: dimensions.height
        )
    }

    private static func preferredFormat(
        on device: AVCaptureDevice,
        requestedFPS: Double
    ) -> AVCaptureDevice.Format {
        let activeFormat = device.activeFormat
        guard !supports(format: activeFormat, fps: requestedFPS) else {
            return activeFormat
        }

        // Preserve capture resolution for this pass: only switch to a low-FPS format
        // when the device offers one at the current dimensions.
        let activeDimensions = dimensions(of: activeFormat)
        let candidates = device.formats.filter { format in
            let formatDimensions = dimensions(of: format)
            return formatDimensions.width == activeDimensions.width
                && formatDimensions.height == activeDimensions.height
                && supports(format: format, fps: requestedFPS)
        }

        return candidates.sorted { lhs, rhs in
            let lhsMin = lhs.videoSupportedFrameRateRanges.map(\.minFrameRate).min() ?? 30
            let rhsMin = rhs.videoSupportedFrameRateRanges.map(\.minFrameRate).min() ?? 30
            if lhsMin != rhsMin { return lhsMin < rhsMin }

            let lhsMax = lhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
            let rhsMax = rhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
            return lhsMax > rhsMax
        }.first ?? activeFormat
    }

    private static func supports(format: AVCaptureDevice.Format, fps: Double) -> Bool {
        format.videoSupportedFrameRateRanges.contains { range in
            range.minFrameRate <= fps + 0.001 && fps <= range.maxFrameRate + 0.001
        }
    }

    private static func dimensions(of format: AVCaptureDevice.Format) -> CMVideoDimensions {
        CMVideoFormatDescriptionGetDimensions(format.formatDescription)
    }
}
