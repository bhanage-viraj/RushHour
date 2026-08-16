//
//  ExportEngine.swift
//  lucky7
//
//  Raw timelapse is already timed at 60 fps (frame N → t = N/60).
//  Export re-encodes to a clean MP4 with duration = frameCount / 60.
//

import AVFoundation
import CoreImage
import UIKit

final class ExportEngine {
    static let shared = ExportEngine()

    private init() {}

    func generateWrappedVideo(
        rawVideoURL: URL,
        capturedFrameCount: Int,
        sessionWallClockSeconds: TimeInterval? = nil,
        plannedSessionSeconds: TimeInterval? = nil,
        completion: @escaping (URL?) -> Void
    ) {
        let frameCount = max(capturedFrameCount, 0)
        let outputSeconds = AppConstants.wrappedDurationSeconds(frameCount: frameCount)

        guard frameCount > 0, outputSeconds > 0 else {
            completion(nil)
            return
        }

        let asset = AVURLAsset(url: rawVideoURL)

        Task {
            do {
                let sourceDuration = try await asset.load(.duration)
                let rawSeconds = max(CMTimeGetSeconds(sourceDuration), 0.1)
                let targetDuration = CMTime(seconds: outputSeconds, preferredTimescale: 600)

                if let wall = sessionWallClockSeconds, let planned = plannedSessionSeconds {
                    print(
                        String(
                            format: "ExportEngine: %.0fs of %.0fs planned → %d frames → %.2fs @ %.0ffps",
                            wall,
                            planned,
                            frameCount,
                            outputSeconds,
                            AppConstants.wrappedOutputFPS
                        )
                    )
                } else {
                    print(
                        String(
                            format: "ExportEngine: %d frames → %.2fs @ %.0ffps",
                            frameCount,
                            outputSeconds,
                            AppConstants.wrappedOutputFPS
                        )
                    )
                }

                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                    await MainActor.run { completion(nil) }
                    return
                }

                let composition = AVMutableComposition()
                guard let compositionTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    await MainActor.run { completion(nil) }
                    return
                }

                try compositionTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: sourceDuration),
                    of: videoTrack,
                    at: .zero
                )

                if abs(rawSeconds - outputSeconds) > 0.05 {
                    compositionTrack.scaleTimeRange(
                        CMTimeRange(start: .zero, duration: sourceDuration),
                        toDuration: targetDuration
                    )
                }

                let outputURL = WrapStorage.newFinalURL()

                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }

                let renderSize = try await sessionRenderSize(for: videoTrack)
                let videoComposition = try await makeVideoComposition(
                    for: composition,
                    sourceVideoTrack: videoTrack,
                    renderSize: renderSize,
                    scaling: .fill
                )

                let ok = await exportCompressed(
                    composition: composition,
                    videoComposition: videoComposition,
                    to: outputURL,
                    bitRate: AppConstants.finalVideoAverageBitRate
                )

                await MainActor.run {
                    if ok {
                        let megabytes = Self.fileSizeMegabytes(outputURL)
                        print(String(format: "ExportEngine: final wrap ok %.2f MB", megabytes))
                        completion(outputURL)
                    } else {
                        completion(nil)
                    }
                }
            } catch {
                print("ExportEngine: \(error.localizedDescription)")
                await MainActor.run { completion(nil) }
            }
        }
    }

    /// Burns the selected share template onto the clean session master. The result lives
    /// in temporary storage and must never replace `Session.wrappedVideoPath`.
    func generateShareVideo(
        sourceVideoURL: URL,
        overlay: WrappedVideoOverlay,
        template: WrapTemplate
    ) async -> URL? {
        guard template.hasVideoOverlay else { return sourceVideoURL }

        let asset = AVURLAsset(url: sourceVideoURL)
        do {
            let duration = try await asset.load(.duration)
            guard CMTimeGetSeconds(duration) > 0,
                  let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }

            let composition = AVMutableComposition()
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                return nil
            }

            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: videoTrack,
                at: .zero
            )
            compositionTrack.preferredTransform = try await videoTrack.load(.preferredTransform)

            let renderSize = try await VideoOrientationHelper.presentationSize(for: videoTrack)
            guard let overlayImage = makeOverlayImage(
                renderSize: renderSize,
                overlay: overlay,
                template: template
            ) else {
                return nil
            }
            let overlayCIImage = CIImage(cgImage: overlayImage)
            let videoComposition = AVMutableVideoComposition(
                asset: composition,
                applyingCIFiltersWithHandler: { request in
                    let sourceImage = request.sourceImage.clampedToExtent()
                    let outputImage = overlayCIImage.composited(over: sourceImage)
                        .cropped(to: request.sourceImage.extent)
                    request.finish(with: outputImage, context: nil)
                }
            )
            let outputURL = WrapStorage.temporaryShareURL()
            let ok = await exportCompressed(
                composition: composition,
                videoComposition: videoComposition,
                to: outputURL,
                bitRate: AppConstants.finalVideoAverageBitRate
            )

            if ok {
                print("ExportEngine: share template=\(template.rawValue) output=\(outputURL.lastPathComponent)")
                return outputURL
            }
            return nil
        } catch {
            print("ExportEngine.generateShareVideo: \(error.localizedDescription)")
            return nil
        }
    }

    /// Produces a Story-compatible derivative without changing the clean session master.
    /// Longer wraps are time-scaled so the complete timelapse remains present.
    func generateInstagramStoryVideo(sourceVideoURL: URL) async -> URL? {
        let asset = AVURLAsset(url: sourceVideoURL)
        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            guard durationSeconds.isFinite,
                  durationSeconds > 0,
                  let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }

            let maximumDuration = AppConstants.instagramStoryMaximumDurationSeconds
            guard durationSeconds > maximumDuration else {
                return sourceVideoURL
            }

            let composition = AVMutableComposition()
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                return nil
            }

            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: videoTrack,
                at: .zero
            )
            compositionTrack.scaleTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                toDuration: CMTime(seconds: maximumDuration, preferredTimescale: 600)
            )

            let renderSize = try await sessionRenderSize(for: videoTrack)
            let videoComposition = try await makeVideoComposition(
                for: composition,
                sourceVideoTrack: videoTrack,
                renderSize: renderSize,
                scaling: .fill
            )
            let outputURL = WrapStorage.temporaryShareURL()
            let ok = await exportCompressed(
                composition: composition,
                videoComposition: videoComposition,
                to: outputURL,
                bitRate: AppConstants.finalVideoAverageBitRate
            )
            return ok ? outputURL : nil
        } catch {
            print("ExportEngine.generateInstagramStoryVideo: \(error.localizedDescription)")
            return nil
        }
    }

    /// Produces the Figma "Transparent" share option as a PNG with alpha. It is a
    /// temporary share artifact and never replaces the clean session master.
    func generateTransparentShareImage(
        sourceVideoURL: URL,
        overlay: WrappedVideoOverlay
    ) async -> UIImage? {
        let asset = AVURLAsset(url: sourceVideoURL)
        do {
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }
            let renderSize = try await VideoOrientationHelper.presentationSize(for: videoTrack)
            guard let image = makeOverlayImage(
                renderSize: renderSize,
                overlay: overlay,
                template: .transparent
            ) else {
                return nil
            }
            return UIImage(cgImage: image)
        } catch {
            print("ExportEngine.generateTransparentShareImage: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Raw segment stitching (background-interrupted recordings)

    /// Concatenates the per-segment raw clips a recording produced when it was interrupted by
    /// app-background into ONE continuous raw clip, preserving the camera orientation. Passthrough
    /// (no re-encode) since every segment came from the same capture config. Returns the stitched
    /// URL + its measured duration so the caller can recompute a matching frame count.
    func concatenateRawSegments(_ urls: [URL]) async -> (url: URL, durationSeconds: Double)? {
        guard !urls.isEmpty else { return nil }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }

        var cursor = CMTime.zero
        var preferredTransform: CGAffineTransform?
        for url in urls {
            let asset = AVURLAsset(url: url)
            do {
                guard let src = try await asset.loadTracks(withMediaType: .video).first else { continue }
                let dur = try await asset.load(.duration)
                guard CMTimeGetSeconds(dur) > 0 else { continue }
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: src, at: cursor)
                cursor = CMTimeAdd(cursor, dur)
                if preferredTransform == nil {
                    preferredTransform = try? await src.load(.preferredTransform)
                }
            } catch {
                print("ExportEngine.concatenateRawSegments insert: \(error.localizedDescription)")
                continue
            }
        }
        guard cursor > .zero else { return nil }
        if let preferredTransform { track.preferredTransform = preferredTransform }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timelapse_stitched_\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            return nil
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await session.export()

        guard session.status == .completed else {
            print("ExportEngine.concatenateRawSegments export failed: \(session.error?.localizedDescription ?? "unknown")")
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        let stitchedSeconds = (try? await AVURLAsset(url: outputURL).load(.duration))
            .map { CMTimeGetSeconds($0) } ?? CMTimeGetSeconds(cursor)
        return (outputURL, stitchedSeconds)
    }

    // MARK: - Period recaps (weekly / monthly)

    /// Produces a short, TEXT-FREE, portrait-normalised (1080×1920) slice of a raw
    /// timelapse for weekly/monthly recaps.
    func generateCleanSlice(rawVideoURL: URL, sliceSeconds: Double, outputURL: URL) async -> Bool {
        let asset = AVURLAsset(url: rawVideoURL)
        do {
            let duration = try await asset.load(.duration)
            let totalSeconds = CMTimeGetSeconds(duration)
            guard totalSeconds > 0 else { return false }

            let slice = min(sliceSeconds, totalSeconds)
            let startSeconds = max(0, (totalSeconds - slice) / 2)   // centered
            let timeRange = CMTimeRange(
                start: CMTime(seconds: startSeconds, preferredTimescale: 600),
                duration: CMTime(seconds: slice, preferredTimescale: 600)
            )

            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { return false }

            let composition = AVMutableComposition()
            guard let compTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { return false }
            try compTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

            let videoComposition = try await makeVideoComposition(
                for: composition,
                sourceVideoTrack: videoTrack,
                renderSize: AppConstants.finalRenderSize,
                scaling: .portraitRecap
            )

            return await exportCompressed(
                composition: composition,
                videoComposition: videoComposition,
                to: outputURL,
                bitRate: AppConstants.finalVideoAverageBitRate
            )
        } catch {
            print("ExportEngine.generateCleanSlice: \(error.localizedDescription)")
            return false
        }
    }

    /// Concatenates the temporary portrait-normalized per-session slices into one
    /// video and burns a single period-level overlay (total focus time / period label /
    /// footer). Each clip is trimmed so the whole recap never exceeds `maxDurationSeconds`.
    func generatePeriodWrap(
        clipURLs: [URL],
        overlay: WrappedVideoOverlay,
        maxDurationSeconds: Double,
        outputURL: URL
    ) async -> Bool {
        guard !clipURLs.isEmpty else { return false }
        let renderSize = AppConstants.finalRenderSize
        // Share the budget evenly so every session is represented within the cap.
        let perClipSeconds = maxDurationSeconds / Double(clipURLs.count)

        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return false }

        var cursor = CMTime.zero
        do {
            for url in clipURLs {
                let asset = AVURLAsset(url: url)
                guard let track = try await asset.loadTracks(withMediaType: .video).first else { continue }
                let dur = CMTimeGetSeconds(try await asset.load(.duration))
                let take = min(dur, perClipSeconds)
                guard take > 0 else { continue }
                let range = CMTimeRange(start: .zero, duration: CMTime(seconds: take, preferredTimescale: 600))
                try compTrack.insertTimeRange(range, of: track, at: cursor)
                cursor = CMTimeAdd(cursor, range.duration)
            }
        } catch {
            print("ExportEngine.generatePeriodWrap insert: \(error.localizedDescription)")
            return false
        }
        guard cursor > .zero else { return false }

        guard let overlayImage = makeOverlayImage(
            renderSize: renderSize,
            overlay: overlay,
            template: .styled
        ) else {
            return false
        }
        let overlayCIImage = CIImage(cgImage: overlayImage)
        let videoComposition = AVMutableVideoComposition(
            asset: composition,
            applyingCIFiltersWithHandler: { request in
                let sourceImage = request.sourceImage.clampedToExtent()
                let outputImage = overlayCIImage.composited(over: sourceImage)
                    .cropped(to: request.sourceImage.extent)
                request.finish(with: outputImage, context: nil)
            }
        )

        return await exportCompressed(
            composition: composition,
            videoComposition: videoComposition,
            to: outputURL,
            bitRate: AppConstants.finalVideoAverageBitRate
        )
    }

    private func exportCompressed(
        composition: AVComposition,
        videoComposition: AVMutableVideoComposition,
        to outputURL: URL,
        bitRate: Int
    ) async -> Bool {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        guard let videoTrack = composition.tracks(withMediaType: .video).first else {
            print("ExportEngine.exportCompressed failed: missing video track")
            return false
        }

        do {
            let reader = try AVAssetReader(asset: composition)
            let readerOutput = AVAssetReaderVideoCompositionOutput(
                videoTracks: [videoTrack],
                videoSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                ]
            )
            readerOutput.videoComposition = videoComposition
            readerOutput.alwaysCopiesSampleData = false

            guard reader.canAdd(readerOutput) else {
                print("ExportEngine.exportCompressed failed: reader cannot add output")
                return false
            }
            reader.add(readerOutput)

            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            let renderSize = videoComposition.renderSize
            let writerInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: Int(renderSize.width),
                    AVVideoHeightKey: Int(renderSize.height),
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: bitRate,
                        AVVideoExpectedSourceFrameRateKey: Int(AppConstants.finalRenderFPS),
                        AVVideoMaxKeyFrameIntervalKey: Int(AppConstants.finalRenderFPS * 2),
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                    ]
                ]
            )
            writerInput.expectsMediaDataInRealTime = false

            guard writer.canAdd(writerInput) else {
                print("ExportEngine.exportCompressed failed: writer cannot add input")
                return false
            }
            writer.add(writerInput)

            guard reader.startReading() else {
                print("ExportEngine.exportCompressed reader failed: \(reader.error?.localizedDescription ?? "unknown")")
                return false
            }
            guard writer.startWriting() else {
                reader.cancelReading()
                print("ExportEngine.exportCompressed writer failed: \(writer.error?.localizedDescription ?? "unknown")")
                return false
            }
            writer.startSession(atSourceTime: .zero)

            let success: Bool = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let queue = DispatchQueue(label: "com.lucky7.export.compressed")
                var didFinish = false

                func finish(_ ok: Bool) {
                    guard !didFinish else { return }
                    didFinish = true

                    if !ok {
                        reader.cancelReading()
                        writer.cancelWriting()
                        continuation.resume(returning: false)
                        return
                    }

                    writerInput.markAsFinished()
                    writer.finishWriting {
                        let completed = writer.status == .completed && reader.status == .completed
                        if !completed {
                            print("ExportEngine.exportCompressed failed reader=\(reader.status.rawValue) writer=\(writer.status.rawValue) readerError=\(reader.error?.localizedDescription ?? "nil") writerError=\(writer.error?.localizedDescription ?? "nil")")
                        }
                        continuation.resume(returning: completed)
                    }
                }

                writerInput.requestMediaDataWhenReady(on: queue) {
                    while writerInput.isReadyForMoreMediaData {
                        var reachedEnd = false
                        var appendFailed = false

                        autoreleasepool {
                            guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                                reachedEnd = true
                                return
                            }

                            appendFailed = !writerInput.append(sampleBuffer)
                        }

                        if reachedEnd {
                            finish(reader.status == .completed)
                            return
                        }

                        if appendFailed {
                            print("ExportEngine.exportCompressed append failed: \(writer.error?.localizedDescription ?? "unknown")")
                            finish(false)
                            return
                        }
                    }
                }
            }

            if success {
                print(
                    String(
                        format: "ExportEngine.exportCompressed ok %.0fx%.0f %.0ffps %.1fMbps %.2fMB",
                        renderSize.width,
                        renderSize.height,
                        AppConstants.finalRenderFPS,
                        Double(bitRate) / 1_000_000,
                        Self.fileSizeMegabytes(outputURL)
                    )
                )
            } else {
                try? FileManager.default.removeItem(at: outputURL)
            }

            return success
        } catch {
            print("ExportEngine.exportCompressed error: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: outputURL)
            return false
        }
    }

    private static func fileSizeMegabytes(_ url: URL) -> Double {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .doubleValue ?? 0
        return bytes / 1_000_000
    }

    // MARK: - Session output + overlay

    struct WrappedVideoOverlay {
        /// Top line — the session title, the week's date range, or "<Month> Rewind".
        let header: String
        /// Large hero line — total focus duration, e.g. "3h 20m".
        let duration: String
        /// Small line under the duration — the date for session wraps. Empty hides it,
        /// so weekly/monthly wraps show only header + duration.
        let subtitle: String
    }

    private enum VideoScaling {
        case fill
        case portraitRecap
    }

    private func sessionRenderSize(for track: AVAssetTrack) async throws -> CGSize {
        let sourceSize = try await VideoOrientationHelper.presentationSize(for: track)
        return sourceSize.width > sourceSize.height
            ? AppConstants.landscapeFinalRenderSize
            : AppConstants.finalRenderSize
    }

    private func makeVideoComposition(
        for composition: AVComposition,
        sourceVideoTrack: AVAssetTrack,
        renderSize: CGSize,
        scaling: VideoScaling
    ) async throws -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(AppConstants.finalRenderFPS))
        videoComposition.renderSize = renderSize

        // Compute an oriented rect for the source track.
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let sourceRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(width: abs(sourceRect.width), height: abs(sourceRect.height))

        // Normalize so oriented video starts at (0,0).
        let normalize = preferredTransform.concatenating(
            CGAffineTransform(translationX: -sourceRect.origin.x, y: -sourceRect.origin.y)
        )

        // Session masters preserve their recorded orientation and fill the matching canvas.
        // Recap slices stay portrait, fitting landscape sources so no content is lost.
        let isPortraitish = orientedSize.height >= orientedSize.width
        let scaleX = renderSize.width / max(orientedSize.width, 1)
        let scaleY = renderSize.height / max(orientedSize.height, 1)
        let scale: CGFloat
        switch scaling {
        case .fill:
            scale = max(scaleX, scaleY)
        case .portraitRecap:
            scale = isPortraitish ? max(scaleX, scaleY) : min(scaleX, scaleY)
        }

        let scaledSize = CGSize(width: orientedSize.width * scale, height: orientedSize.height * scale)
        let tx = (renderSize.width - scaledSize.width) / 2
        let ty = (renderSize.height - scaledSize.height) / 2

        let finalTransform = normalize
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

        guard let compVideoTrack = composition.tracks(withMediaType: .video).first else {
            return videoComposition
        }

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        return videoComposition
    }

    private func makeOverlayImage(
        renderSize: CGSize,
        overlay: WrappedVideoOverlay,
        template: WrapTemplate
    ) -> CGImage? {
        let sourceLayer = makeOverlayLayer(
            renderSize: renderSize,
            overlay: overlay,
            template: template
        )
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: renderSize, format: format).image { context in
            sourceLayer.render(in: context.cgContext)
        }
        return image.cgImage
    }

    private func makeOverlayLayer(
        renderSize: CGSize,
        overlay: WrappedVideoOverlay,
        template: WrapTemplate
    ) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: renderSize)
        layer.masksToBounds = true

        let unit = min(renderSize.width, renderSize.height)

        func gothic(_ size: CGFloat) -> UIFont {
            UIFont(name: "SpecialGothicExpandedOne-Regular", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .black)
        }

        func titleFont(_ size: CGFloat) -> UIFont {
            gothic(size)
        }

        func paragraphStyle(
            for font: UIFont,
            lineBreakMode: NSLineBreakMode,
            alignment: NSTextAlignment
        ) -> NSMutableParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.alignment = alignment
            style.lineBreakMode = lineBreakMode
            style.minimumLineHeight = font.pointSize * WrapOverlayLayout.lineHeightRatio
            style.maximumLineHeight = font.pointSize * WrapOverlayLayout.lineHeightRatio
            return style
        }

        func attributedText(
            _ text: String,
            font: UIFont,
            alpha: CGFloat,
            lineBreakMode: NSLineBreakMode,
            alignment: NSTextAlignment
        ) -> NSAttributedString {
            NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.white.withAlphaComponent(alpha),
                    .paragraphStyle: paragraphStyle(
                        for: font,
                        lineBreakMode: lineBreakMode,
                        alignment: alignment
                    )
                ]
            )
        }

        func fittedHeaderLayout(
            _ text: String,
            maxLines: Int,
            width: CGFloat,
            baseSize: CGFloat = 0,
            minimumSize: CGFloat = 0
        ) -> (font: UIFont, text: String, lineCount: Int) {
            let resolvedBaseSize = baseSize > 0
                ? baseSize
                : unit * WrapOverlayLayout.titleFontRatio
            let resolvedMinimumSize = minimumSize > 0 ? minimumSize : unit * 0.024
            var size = resolvedBaseSize

            while size > resolvedMinimumSize {
                let font = titleFont(size)
                let wrapped = WrapTextLayout.lines(
                    for: text,
                    font: font,
                    maxWidth: width,
                    maxLines: maxLines
                )
                if wrapped.didFit, !wrapped.lines.isEmpty {
                    return (font, wrapped.text, wrapped.lines.count)
                }
                size -= 2
            }

            let font = titleFont(resolvedMinimumSize)
            let wrapped = WrapTextLayout.lines(
                for: text,
                font: font,
                maxWidth: width,
                maxLines: maxLines,
                truncatesOverflow: true
            )
            let lines = wrapped.lines.isEmpty ? [text] : wrapped.lines
            return (font, lines.joined(separator: "\n"), lines.count)
        }

        func textLayer(
            _ text: String,
            font: UIFont,
            frame: CGRect,
            alpha: CGFloat = 1,
            lineBreakMode: NSLineBreakMode = .byWordWrapping,
            alignment: NSTextAlignment = .center
        ) -> CATextLayer {
            let t = CATextLayer()
            t.string = attributedText(
                text,
                font: font,
                alpha: alpha,
                lineBreakMode: lineBreakMode,
                alignment: alignment
            )
            switch alignment {
            case .left: t.alignmentMode = .left
            case .right: t.alignmentMode = .right
            default: t.alignmentMode = .center
            }
            t.isWrapped = true
            // Video coordinates are already output pixels; screen scale only creates oversized
            // backing surfaces and can exhaust IOSurface memory during landscape exports.
            t.contentsScale = 1
            t.truncationMode = .none
            t.font = font
            t.fontSize = font.pointSize
            t.frame = frame
            return t
        }

        func fittedDurationFont(maxWidth: CGFloat) -> UIFont {
            var size = unit * WrapOverlayLayout.durationFontRatio
            let minimumSize = unit * 0.09
            while size > minimumSize {
                let font = gothic(size)
                if WrapTextLayout.measuredWidth(overlay.duration, font: font) <= maxWidth {
                    return font
                }
                size -= 2
            }
            return gothic(minimumSize)
        }

        func addMetadata(startY: CGFloat) {
            let titleWidth = renderSize.width * WrapOverlayLayout.titleWidthRatio
            let titleLayout = fittedHeaderLayout(
                overlay.header,
                maxLines: 2,
                width: titleWidth
            )
            let titleHeight = titleLayout.font.pointSize
                * WrapOverlayLayout.lineHeightRatio
                * CGFloat(max(titleLayout.lineCount, 1))
            let titleX = (renderSize.width - titleWidth) / 2
            layer.addSublayer(textLayer(
                titleLayout.text,
                font: titleLayout.font,
                frame: CGRect(x: titleX, y: startY, width: titleWidth, height: titleHeight)
            ))

            let durationWidth = renderSize.width * WrapOverlayLayout.durationWidthRatio
            let durationFont = fittedDurationFont(maxWidth: durationWidth)
            let durationHeight = durationFont.pointSize * WrapOverlayLayout.lineHeightRatio
            let durationY = startY + titleHeight
                + unit * WrapOverlayLayout.contentSpacingRatio
            layer.addSublayer(textLayer(
                overlay.duration,
                font: durationFont,
                frame: CGRect(
                    x: (renderSize.width - durationWidth) / 2,
                    y: durationY,
                    width: durationWidth,
                    height: durationHeight
                )
            ))

            guard !overlay.subtitle.isEmpty else { return }
            let dateFont = UIFont.systemFont(
                ofSize: unit * WrapOverlayLayout.dateFontRatio,
                weight: .regular
            )
            let dateHeight = dateFont.pointSize * WrapOverlayLayout.lineHeightRatio
            layer.addSublayer(textLayer(
                overlay.subtitle,
                font: dateFont,
                frame: CGRect(
                    x: titleX,
                    y: durationY + durationHeight,
                    width: titleWidth,
                    height: dateHeight
                ),
                alpha: 0.70
            ))
        }

        switch template {
        case .clean:
            break

        case .styled:
            addMetadata(startY: renderSize.height * WrapOverlayLayout.styledTopRatio)

        case .transparent:
            let badgeWidth = unit * WrapOverlayLayout.transparentBadgeWidthRatio
            let badgeHeight = unit * WrapOverlayLayout.transparentBadgeHeightRatio
            let badgeFrame = CGRect(
                x: (renderSize.width - badgeWidth) / 2,
                y: renderSize.height * WrapOverlayLayout.transparentBadgeTopRatio,
                width: badgeWidth,
                height: badgeHeight
            )
            let badge = CALayer()
            badge.frame = badgeFrame
            badge.borderColor = UIColor.white.cgColor
            badge.borderWidth = max(unit * 0.0032, 1)
            badge.cornerRadius = badgeHeight / 2
            layer.addSublayer(badge)

            let badgeFont = UIFont.systemFont(
                ofSize: unit * WrapOverlayLayout.transparentBadgeFontRatio,
                weight: .bold
            )
            let badgeTextHeight = badgeFont.pointSize * WrapOverlayLayout.lineHeightRatio
            layer.addSublayer(textLayer(
                "TRANSPARENT",
                font: badgeFont,
                frame: CGRect(
                    x: badgeFrame.minX,
                    y: badgeFrame.midY - badgeTextHeight / 2,
                    width: badgeFrame.width,
                    height: badgeTextHeight
                )
            ))

            addMetadata(
                startY: badgeFrame.maxY
                    + unit * WrapOverlayLayout.transparentBadgeGapRatio
            )
        }

        return layer
    }
}
