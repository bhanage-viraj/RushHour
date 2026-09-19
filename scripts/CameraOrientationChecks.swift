// Compiled with the production transform helper and segment stitcher by check-camera-orientation.py.
@main struct CameraOrientationChecks {
    static func require(_ value: Bool, _ message: String) {
        if !value { fatalError(message) }
    }

    static func main() async throws {
        for size in [CGSize(width: 320, height: 180), CGSize(width: 180, height: 320)] {
            for angle: CGFloat in [0, 90, 180, 270] {
                let plain = VideoOrientationHelper.writerTransform(bufferWidth: Int(size.width), bufferHeight: Int(size.height), rotationAngle: angle, mirrored: false)
                let selfie = VideoOrientationHelper.writerTransform(bufferWidth: Int(size.width), bufferHeight: Int(size.height), rotationAngle: angle, mirrored: true)
                let bounds = CGRect(origin: .zero, size: size).applying(plain)
                let mirroredBounds = CGRect(origin: .zero, size: size).applying(selfie)
                require(abs(mirroredBounds.minX) < 0.001 && abs(mirroredBounds.minY) < 0.001, "Nonzero origin")
                require(abs(abs(selfie.a * selfie.d - selfie.b * selfie.c) - 1) < 0.001, "Unexpected scaling")
                for point in [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)] {
                    let a = point.applying(plain), b = point.applying(selfie)
                    require(abs(a.y - b.y) < 0.001, "Mirroring changed vertical direction")
                    require(abs(a.x + b.x - bounds.width) < 0.001, "Mirroring failed horizontal reflection")
                }
            }
        }
        print("PASS: all four rotations, both buffer shapes, horizontal mirroring and normalized bounds")
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let a = try await makeClip(directory.appendingPathComponent("a.mp4"), angle: 90)
        let b = try await makeClip(directory.appendingPathComponent("b.mp4"), angle: 270)
        let rear = try await makeClip(directory.appendingPathComponent("rear.mp4"), angle: 90, mirrored: false)
        let rearReverse = try await makeClip(directory.appendingPathComponent("rear-reverse.mp4"), angle: 270, mirrored: false)
        try await checkColors(rear, seconds: 0.1, expected: [2, 0, 3, 1])
        try await checkColors(rearReverse, seconds: 0.1, expected: [1, 3, 0, 2])
        print("PASS: rear camera recordings remain unmirrored at 90 and 270 degrees")
        let c = try await makeClip(directory.appendingPathComponent("c.mp4"), angle: 90, width: 640, height: 360)
        // Sensor quadrants: red, green / blue, yellow. These expected display colors
        // are independent of the transform implementation.
        try await checkColors(a, seconds: 0.1, expected: [0, 2, 1, 3])
        try await checkColors(b, seconds: 0.1, expected: [3, 1, 2, 0])
        for (name, clips, secondColors) in [("matching", [a, a], [0, 2, 1, 3]), ("mixed", [a, b], [3, 1, 2, 0]), ("resized", [a, c], [0, 2, 1, 3]), ("front/rear", [a, rear], [2, 0, 3, 1])] {
            guard let result = await ExportEngine().concatenateRawSegments(clips) else { fatalError("Stitch failed") }
            defer { try? FileManager.default.removeItem(at: result.url) }
            require(abs(result.durationSeconds - 1) < 0.03, "Stitch lost duration")
            try await checkColors(result.url, seconds: 0.1, expected: [0, 2, 1, 3])
            try await checkColors(result.url, seconds: 0.6, expected: secondColors)
            print("PASS: \(name) segment stitching preserves each segment's displayed quadrant positions")
        }
    }

    static func makeClip(_ url: URL, angle: CGFloat, width: Int = 320, height: Int = 180, mirrored: Bool = true) async throws -> URL {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.transform = VideoOrientationHelper.writerTransform(bufferWidth: width, bufferHeight: height, rotationAngle: angle, mirrored: mirrored)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        writer.add(input)
        require(writer.startWriting(), "Writer failed to start")
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        let buffer = pixelBuffer!
        CVPixelBufferLockBaseAddress(buffer, [])
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let colors: [[UInt8]] = [[0, 0, 255, 255], [0, 255, 0, 255], [255, 0, 0, 255], [0, 255, 255, 255]]
        for y in 0..<height { for x in 0..<width {
            let color = colors[(y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)]
            for channel in 0..<4 { bytes[y * stride + x * 4 + channel] = color[channel] }
        }}
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            require(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 60)), "Append failed")
        }
        writer.endSession(atSourceTime: CMTime(value: 30, timescale: 60))
        input.markAsFinished()
        await writer.finishWriting()
        require(writer.status == .completed, "Writing failed")
        return url
    }

    static func checkColors(_ url: URL, seconds: Double, expected: [Int]) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let result = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        let image = result.image
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let palette: [[Int]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]]
        bytes.withUnsafeMutableBytes { data in
            let context = CGContext(data: data.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        for (index, fraction) in [(0, (0.25, 0.25)), (1, (0.75, 0.25)), (2, (0.25, 0.75)), (3, (0.75, 0.75))] {
            let offset = (Int(Double(image.height) * fraction.1) * image.width + Int(Double(image.width) * fraction.0)) * 4
            let pixel = (0..<3).map { Int(bytes[offset + $0]) }
            let color = palette[expected[index]]
            // H.264/color-space conversion shifts channel values; classify the solid
            // quadrant by its nearest palette color instead of demanding exact bytes.
            let distances = palette.map { candidate in zip(pixel, candidate).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) } }
            let actual = distances.indices.min(by: { distances[$0] < distances[$1] })!
            require(actual == expected[index], "Wrong quadrant at \(seconds)s: \(index), got \(pixel), wanted \(color)")
        }
    }
}
