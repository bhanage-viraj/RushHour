// Utilities/WrapStorage.swift
// Persistent on-disk locations + period-key/label helpers for the recap system.
//
// Layout (Application Support, excluded from iCloud backup):
//   Wraps/sessions/<uuid>.mp4     — full per-session source clips for final exports + rollups
//   Wraps/finals/clean_<uuid>.mp4 — clean session masters, the only session playback source
//   Wraps/periods/<kind>_<key>.mp4 — stitched weekly/monthly recaps

import Foundation

enum WrapStorage {

    // MARK: - Directories

    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Wraps", isDirectory: true)
    }

    static var sessionsDir: URL { ensure(root.appendingPathComponent("sessions", isDirectory: true)) }
    static var periodsDir: URL { ensure(root.appendingPathComponent("periods", isDirectory: true)) }
    static var finalsDir: URL { ensure(root.appendingPathComponent("finals", isDirectory: true)) }

    @discardableResult
    private static func ensure(_ dir: URL) -> URL {
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var d = dir
            var values = URLResourceValues()
            values.isExcludedFromBackup = true   // don't bloat the user's iCloud backup
            try? d.setResourceValues(values)
        }
        return dir
    }

    // MARK: - File URLs

    /// A fresh, uniquely-named destination for a durable full session source.
    static func newSessionSourceURL() -> URL {
        sessionsDir.appendingPathComponent("\(UUID().uuidString).mp4")
    }

    /// A temporary, recap-only clean slice. Never store this on a Session.
    static func temporaryRollupSliceURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wrap_rollup_slice_\(UUID().uuidString).mp4")
    }

    /// A styled derivative used only for the active save/share action.
    static func temporaryShareURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wrap_share_\(UUID().uuidString).mp4")
    }

    /// Share the encoded PNG file, not a UIImage that an activity can flatten or re-encode.
    static func writeTemporarySharePNG(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RushHourWrap-\(UUID().uuidString).png")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// A fresh destination for a clean session master. Lives in Application Support,
    /// not tmp, because iOS is free to purge temporary files.
    static func newFinalURL() -> URL {
        finalsDir.appendingPathComponent("clean_\(UUID().uuidString).mp4")
    }

    static func sessionMasterContainsMetadata(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("wrapped_")
    }

    /// The destination for a period recap (deterministic per period so re-runs overwrite).
    static func periodURL(kind: String, key: String) -> URL {
        periodsDir.appendingPathComponent("\(kind)_\(key).mp4")
    }

    static func delete(path: String?) {
        guard let url = resolveVideoURL(path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func exists(_ path: String?) -> Bool {
        resolveVideoURL(path) != nil
    }

    // MARK: - Path resolution

    /// Stored video paths are bare filenames (new scheme) or absolute paths written by
    /// older builds. Absolute paths go stale on every app update — iOS rotates the
    /// container UUID and the old prefix dies, even though the files themselves are
    /// migrated. So resolve by filename against every place a wrap video can live;
    /// the UUID names make cross-directory collisions impossible.
    static func resolveVideoURL(_ stored: String?) -> URL? {
        guard let stored, !stored.isEmpty else { return nil }
        let name = URL(fileURLWithPath: stored).lastPathComponent
        let candidates = [
            finalsDir.appendingPathComponent(name),
            sessionsDir.appendingPathComponent(name),
            periodsDir.appendingPathComponent(name),
            FileManager.default.temporaryDirectory.appendingPathComponent(name),
            URL(fileURLWithPath: stored)   // same-container absolute path (pre-update rows)
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Period keys & labels (Calendar.current, matching the analytics screens)

    static func weekKey(for date: Date, calendar: Calendar = .current) -> String {
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }

    /// e.g. "5 – 11 JUNE 2026"
    static func weekLabel(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let last = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        func f(_ d: Date, _ fmt: String) -> String {
            let df = DateFormatter(); df.locale = .current; df.dateFormat = fmt
            return df.string(from: d)
        }
        let label: String
        if calendar.isDate(start, equalTo: last, toGranularity: .month) {
            label = "\(f(start, "d")) – \(f(last, "d MMMM yyyy"))"
        } else if calendar.isDate(start, equalTo: last, toGranularity: .year) {
            label = "\(f(start, "d MMM")) – \(f(last, "d MMM yyyy"))"
        } else {
            label = "\(f(start, "d MMM yyyy")) – \(f(last, "d MMM yyyy"))"
        }
        return label.uppercased()
    }

    /// e.g. "JUNE 2026"
    static func monthLabel(for date: Date) -> String {
        let df = DateFormatter(); df.locale = .current; df.dateFormat = "MMMM yyyy"
        return df.string(from: date).uppercased()
    }
}
