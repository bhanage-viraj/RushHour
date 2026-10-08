#!/usr/bin/env python3
"""Exercise production break methods with persistence/Screen Time boundary doubles."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def method(text, signature):
    start = text.index(signature)
    end = text.index('\n    }', start) + len('\n    }')
    return text[start:end].replace('private func', 'func').replace('#if os(iOS)', '').replace('#endif', '')


recording = (ROOT / 'lucky7/Views/RecordingPage.swift').read_text()
focus = (ROOT / 'lucky7/ViewModels/FocusViewModel.swift').read_text()
shared = (ROOT / 'lucky7/Utilities/SharedJailbreakStore.swift').read_text()
event_type = shared[shared.index('struct PendingJailbreakEvent:'):shared.index('// each writer')]
source = r'''
import Foundation
final class Distraction {
    let id = UUID()
    var reason = "", reasonSubmitted = false
    var breakGrantedUntil: Date?, endTime: Date?
    init(sessionId: UUID = UUID(), appOpened: String = "", startTime: Date = .now,
         tokenData: Data? = nil, appBundleId: String? = nil, appDisplayName: String? = nil,
         sourceKind: String = "", actionTaken: String? = nil) {}
}
struct PendingPrompt: Identifiable {
    let id = UUID()
    let distraction: Distraction
    let tokenDataToClear: Data?
}
struct UnlockInfo { let timeText: String }
struct BreakBlockedInfo {}
enum SaveFailure: Error { case diskFull }
final class Context {
    var saves = 0, deletes = 0, inserts = 0, fails = false
    func save() throws { if fails { throw SaveFailure.diskFull }; saves += 1 }
    func insert(_ distraction: Distraction) { inserts += 1 }
    func delete(_ distraction: Distraction) { deletes += 1 }
}
final class SessionTimer { let sessionId = UUID() }
final class FocusViewModel {
    static let breakDuration: TimeInterval = 900
    var now = Date(), activeBreaks: [Distraction] = [], grants = 0, ends = 0, isEngaged = true
    func grantBreak(for distraction: Distraction) {
        grants += 1; distraction.breakGrantedUntil = Date().addingTimeInterval(Self.breakDuration)
        activeBreaks = [distraction]
    }
    func endBreakEarly(for distraction: Distraction) { ends += 1; activeBreaks = [] }
    func prefetchDisplayName(for distraction: Distraction) {}
''' + method(focus, 'func remainingSeconds(') + r'''
}
''' + event_type + r'''
enum SharedJailbreakStore {
    static var event: PendingJailbreakEvent?, handled: Date = .distantPast
    static func nextUnhandledBreak() -> (action: PendingJailbreakEvent, config: PendingJailbreakEvent?)? {
        guard let event, event.occurredAt > handled else { return nil }
        return (event, nil)
    }
    static func markBreakHandled(_ time: Date) { handled = time }
    static func lastShieldedAppName() -> String? { nil }
    static func lastShieldedBundleId() -> String? { nil }
}
final class Probe {
    var pendingPrompt: PendingPrompt?, unlock: UnlockInfo?, breakBlockedInfo: BreakBlockedInfo?
    var showBreakSaveError = false
    let modelContext = Context(), focusController = FocusViewModel(), sessionTimer = SessionTimer()
    func cancelShieldFallbackNotifications() {}
''' + '\n'.join(method(recording, x) for x in [
    'private func takeBreak(', 'private func cancelBreak(', 'private func checkPendingEvents()',
]) + r'''
}
var failures = 0
func expect(_ condition: Bool, _ message: String) {
    if condition { print("PASS: \(message)") } else { failures += 1; print("FAIL: \(message)") }
}
func prompt() -> PendingPrompt {
    PendingPrompt(distraction: Distraction(), tokenDataToClear: nil)
}
func event(_ time: Date = .now) {
    SharedJailbreakStore.handled = .distantPast
    SharedJailbreakStore.event = PendingJailbreakEvent(id: UUID().uuidString, displayName: "App",
        bundleId: nil, tokenData: nil, occurredAt: time, sourceKind: "shieldAction", actionTaken: "break")
}
let duplicate = Probe(), first = prompt()
event()
duplicate.pendingPrompt = first
duplicate.takeBreak("Pasted reason", for: first)
duplicate.takeBreak("Pasted reason", for: first)
expect(duplicate.focusController.grants == 1 && duplicate.modelContext.saves == 2
       && SharedJailbreakStore.nextUnhandledBreak() == nil,
       "repeated callback grants and saves once")
expect(first.distraction.reason == "Pasted reason" && first.distraction.reasonSubmitted,
       "pasted text saved on the accepted record")
duplicate.cancelBreak(for: first)
expect(duplicate.focusController.ends == 0 && duplicate.modelContext.deletes == 0,
       "stale cancel cannot revoke or delete an accepted break")

let blank = Probe(), blankPrompt = prompt()
blank.pendingPrompt = blankPrompt
blank.takeBreak(" \n\t ", for: blankPrompt)
expect(blank.focusController.grants == 0 && blank.pendingPrompt?.id == blankPrompt.id,
       "blank submission preserves restrictions and reason form")

let stale = Probe(), stalePrompt = prompt(), current = prompt()
stale.pendingPrompt = current
stale.takeBreak("Old reason", for: stalePrompt)
stale.cancelBreak(for: stalePrompt)
expect(stale.focusController.grants == 0 && stale.pendingPrompt?.id == current.id
       && stale.modelContext.deletes == 0, "stale callbacks cannot affect the current prompt")

let editing = Probe(), editingPrompt = prompt()
editing.pendingPrompt = editingPrompt
event(); editing.checkPendingEvents()
expect(editing.pendingPrompt?.id == editingPrompt.id && editing.modelContext.deletes == 0
       && SharedJailbreakStore.nextUnhandledBreak() == nil,
       "repeat shield events are consumed without replacing the reason form")

let failed = Probe(), failedPrompt = prompt()
failed.pendingPrompt = failedPrompt; failed.modelContext.fails = true
failed.takeBreak("Keep this text", for: failedPrompt)
expect(failed.focusController.grants == 0 && !failedPrompt.distraction.reasonSubmitted
       && failed.pendingPrompt?.id == failedPrompt.id && failed.showBreakSaveError,
       "failed persistence leaves the app blocked and allows retry")
failed.modelContext.fails = false; failed.takeBreak("Keep this text", for: failedPrompt)
expect(failed.focusController.grants == 1 && failed.modelContext.saves == 2,
       "retry saves and grants exactly once")

let expired = Probe(), oldBreak = Distraction()
oldBreak.breakGrantedUntil = Date().addingTimeInterval(-60)
expired.focusController.activeBreaks = [oldBreak]
expired.focusController.now = Date().addingTimeInterval(-1200)
event(); expired.checkPendingEvents()
expect(expired.breakBlockedInfo == nil && expired.pendingPrompt != nil,
       "expired break does not reject a fresh event before the timer ticks")

let active = Probe(), running = Distraction()
running.breakGrantedUntil = Date().addingTimeInterval(300)
active.focusController.activeBreaks = [running]
event(); active.checkPendingEvents()
expect(active.breakBlockedInfo != nil && active.pendingPrompt == nil
       && SharedJailbreakStore.nextUnhandledBreak() == nil,
       "a genuinely active break rejects and consumes a second request")

let stopped = Probe(); stopped.focusController.isEngaged = false
event(); stopped.checkPendingEvents()
expect(stopped.pendingPrompt == nil, "an ended session cannot show a stale break request")

let cancelled = Probe(), cancelledPrompt = prompt()
cancelled.pendingPrompt = cancelledPrompt; cancelled.cancelBreak(for: cancelledPrompt)
expect(cancelled.pendingPrompt == nil && cancelled.modelContext.deletes == 1
       && cancelled.focusController.grants == 0, "Cancel deletes only its pending record without unlocking")
if failures > 0 { exit(1) }
'''
with tempfile.TemporaryDirectory(prefix='rushhour-break-checks-') as directory:
    path = Path(directory)
    (path / 'checks.swift').write_text(source)
    compiler = ['xcrun', 'swiftc', '-module-cache-path', str(path / 'cache')]
    if len(sys.argv) > 1:
        sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
        compiler += ['-sdk', sdk, '-target', 'arm64-apple-ios27.0-simulator']
    subprocess.run(compiler + [str(path / 'checks.swift'), '-o', str(path / 'checks')], check=True)
    if len(sys.argv) > 1:
        subprocess.run(['codesign', '--force', '--sign', '-', str(path / 'checks')], check=True)
        subprocess.run(['xcrun', 'simctl', 'spawn', sys.argv[1], str(path / 'checks')], check=True)
    else:
        subprocess.run([str(path / 'checks')], check=True)
