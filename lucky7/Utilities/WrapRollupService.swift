// Utilities/WrapRollupService.swift
// Rolls completed weeks/months up into recap videos, then prunes the bulky per-session
// source clips once they're no longer needed. Safe to call on every launch.

import Foundation
import SwiftData

@MainActor
enum WrapRollupService {

    /// Short text-free slice used only as a temporary input while building recaps.
    static let sliceSeconds: Double = 2.5

    /// Guards against overlapping runs (launch trigger + screen triggers).
    private static var isRunning = false

    /// Generate any due weekly/monthly recaps and prune source clips whose week AND month
    /// recaps both exist. No-op when nothing's due. Safe to call from multiple places.
    static func rollUpIfNeeded(context: ModelContext) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let calendar = Calendar.current
        let now = Date()

        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        let wraps = (try? context.fetch(FetchDescriptor<PeriodWrap>())) ?? []

        // --- Repair pass (must run before the safety net below ever counts references).
        // Older builds stored absolute paths; iOS rotates the container on every app
        // update, so those went stale even though the files survived. Re-link whatever
        // still resolves, rescue any wrap stuck in tmp, and drop recap rows whose video
        // is gone for good (they regenerate below if their sources survived).
        var repaired = false
        for s in sessions {
            if let stored = s.rawClipPath, let url = WrapStorage.resolveVideoURL(stored),
               stored != url.lastPathComponent {
                s.rawClipPath = url.lastPathComponent
                repaired = true
            }
            if let stored = s.wrappedVideoPath, let url = WrapStorage.resolveVideoURL(stored) {
                let name = url.lastPathComponent
                if url.deletingLastPathComponent().path != WrapStorage.finalsDir.path {
                    // pre-fix wrap still alive in tmp — move it somewhere durable before
                    // iOS purges it (keep the name so every row pointing at it re-links)
                    try? FileManager.default.moveItem(
                        at: url, to: WrapStorage.finalsDir.appendingPathComponent(name)
                    )
                }
                if stored != name {
                    s.wrappedVideoPath = name
                    repaired = true
                }
            }
        }
        var liveWraps: [PeriodWrap] = []
        for w in wraps {
            guard let url = WrapStorage.resolveVideoURL(w.videoPath) else {
                context.delete(w)   // recap row without its video → dead rewind button
                repaired = true
                continue
            }
            if w.videoPath != url.lastPathComponent {
                w.videoPath = url.lastPathComponent
                repaired = true
            }
            liveWraps.append(w)
        }
        if repaired { try? context.save() }

        var doneKeys = Set(liveWraps.map { "\($0.kind)/\($0.periodKey)" })

        let finalizedWithSources = sessions.filter {
            WrapStorage.exists($0.wrappedVideoPath) && WrapStorage.exists($0.rawClipPath)
        }

        // --- Weekly recaps for completed weeks ---
        let byWeek = Dictionary(grouping: finalizedWithSources) { s in
            calendar.dateInterval(of: .weekOfYear, for: s.startTime)?.start ?? s.startTime
        }
        for (weekStart, weekSessions) in byWeek {
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart),
                  interval.end <= now else { continue }   // week must have ended
            let key = WrapStorage.weekKey(for: weekStart, calendar: calendar)
            guard !doneKeys.contains("weekly/\(key)") else { continue }
            let label = WrapStorage.weekLabel(start: interval.start, end: interval.end, calendar: calendar)
            if await generate(kind: "weekly", key: key, start: interval.start, end: interval.end,
                              sessions: weekSessions, label: label, context: context) {
                doneKeys.insert("weekly/\(key)")
            }
        }

        // --- Monthly recaps for completed months ---
        let byMonth = Dictionary(grouping: finalizedWithSources) { s in
            calendar.date(from: calendar.dateComponents([.year, .month], from: s.startTime)) ?? s.startTime
        }
        for (monthStart, monthSessions) in byMonth {
            guard let interval = calendar.dateInterval(of: .month, for: monthStart),
                  interval.end <= now else { continue }   // month must have ended
            let key = WrapStorage.monthKey(for: monthStart, calendar: calendar)
            guard !doneKeys.contains("monthly/\(key)") else { continue }
            let label = WrapStorage.monthLabel(for: monthStart)
            if await generate(kind: "monthly", key: key, start: interval.start, end: interval.end,
                              sessions: monthSessions, label: label, context: context) {
                doneKeys.insert("monthly/\(key)")
            }
        }

        // --- Prune: a finalized session's source clip can go once BOTH its week and month recaps exist.
        // (A month-straddling week's recap is built later than the month's, so we wait
        //  for both before deleting — never orphaning a recap of its source.)
        var pruned = false
        for s in finalizedWithSources {
            let wk = WrapStorage.weekKey(for: s.startTime, calendar: calendar)
            let mk = WrapStorage.monthKey(for: s.startTime, calendar: calendar)
            if doneKeys.contains("weekly/\(wk)"), doneKeys.contains("monthly/\(mk)") {
                WrapStorage.delete(path: s.rawClipPath)
                s.rawClipPath = nil
                pruned = true
            }
        }
        if pruned { try? context.save() }

        // Safety net: remove files no session references (e.g. a session that exited
        // before its path was recorded, or a re-titled export that got replaced).
        // Match by FILENAME — stored values can still be stale absolute paths, and
        // full-path matching after a container rotation would condemn every file.
        // Only touch files older than an hour so we never race an in-flight save.
        let cutoff = now.addingTimeInterval(-3600)
        sweepUnreferenced(
            dir: WrapStorage.sessionsDir,
            keeping: Set(sessions.compactMap { $0.rawClipPath }.map { URL(fileURLWithPath: $0).lastPathComponent }),
            cutoff: cutoff
        )
        sweepUnreferenced(
            dir: WrapStorage.finalsDir,
            keeping: Set(sessions.compactMap { $0.wrappedVideoPath }.map { URL(fileURLWithPath: $0).lastPathComponent }),
            cutoff: cutoff
        )
    }

    /// Deletes files in `dir` whose names nothing keeps, skipping anything newer than
    /// `cutoff` (could be an export that hasn't been persisted to its session yet).
    private static func sweepUnreferenced(dir: URL, keeping names: Set<String>, cutoff: Date) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        for file in files where !names.contains(file.lastPathComponent) {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// Builds one recap, verifies the file exists, then records the `PeriodWrap`.
    private static func generate(
        kind: String, key: String, start: Date, end: Date,
        sessions: [Session], label: String, context: ModelContext
    ) async -> Bool {
        let sources = sessions
            .sorted { $0.startTime < $1.startTime }
            .compactMap { session -> (session: Session, url: URL)? in
                guard let url = WrapStorage.resolveVideoURL(session.rawClipPath) else { return nil }
                return (session, url)
            }
        guard !sources.isEmpty else { return false }

        var clips: [(session: Session, url: URL)] = []
        var temporarySlices: [URL] = []
        defer {
            for url in temporarySlices {
                try? FileManager.default.removeItem(at: url)
            }
        }

        for source in sources {
            let sliceURL = WrapStorage.temporaryRollupSliceURL()
            let ok = await ExportEngine.shared.generateCleanSlice(
                rawVideoURL: source.url,
                sliceSeconds: sliceSeconds,
                outputURL: sliceURL
            )
            guard ok, FileManager.default.fileExists(atPath: sliceURL.path) else {
                try? FileManager.default.removeItem(at: sliceURL)
                continue
            }
            temporarySlices.append(sliceURL)
            clips.append((source.session, sliceURL))
        }
        guard !clips.isEmpty else { return false }

        let totalFocus = clips.reduce(0.0) { $0 + $1.session.focusDuration() }
        let count = clips.count

        // Header: weekly → the week's date range; monthly → "<Month> Rewind".
        let header: String
        if kind == "monthly" {
            let mf = DateFormatter()
            mf.locale = .current
            mf.dateFormat = "MMMM"
            header = "\(mf.string(from: start)) Rewind"
        } else {
            header = label
        }

        let overlay = ExportEngine.WrappedVideoOverlay(
            header: header,
            duration: TimeFormatter.shortDuration(totalFocus),
            subtitle: ""
        )

        let maxDuration: Double = (kind == "weekly") ? 45 : 60
        let outputURL = WrapStorage.periodURL(kind: kind, key: key)
        let ok = await ExportEngine.shared.generatePeriodWrap(
            clipURLs: clips.map { $0.url }, overlay: overlay, maxDurationSeconds: maxDuration, outputURL: outputURL
        )
        // Only record after verifying the output — never prune sources for a wrap that
        // didn't actually materialise.
        guard ok, FileManager.default.fileExists(atPath: outputURL.path) else { return false }

        context.insert(PeriodWrap(
            kind: kind, periodKey: key, periodStart: start, periodEnd: end,
            videoPath: outputURL.lastPathComponent, generatedAt: Date(),
            sourceSessionCount: count, totalFocusSeconds: totalFocus
        ))
        try? context.save()
        return true
    }
}
