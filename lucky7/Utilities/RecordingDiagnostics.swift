//
//  RecordingDiagnostics.swift
//  lucky7
//

import Foundation

enum RecordingDiagnostics {
    private static let queue = DispatchQueue(label: "com.lucky7.recording.diagnostics")
    private static let maxLogBytes: UInt64 = 512 * 1024

    static var logURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RushHourLogs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("recording-diagnostics.log")
    }

    static func log(_ message: String) {
        let line = "RH_REC \(message)"
        print(line)
        queue.async {
            rotateIfNeeded()
            guard let data = (line + "\n").data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }

    private static func rotateIfNeeded() {
        guard
            let values = try? logURL.resourceValues(forKeys: [.fileSizeKey]),
            let size = values.fileSize,
            UInt64(size) > maxLogBytes
        else { return }
        try? FileManager.default.removeItem(at: logURL)
    }
}
