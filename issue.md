# Match the reason drawer to Figma and restore direct share shortcuts

## Background and previous behavior
Issue #62 reports missing artwork above the reason drawer. `RecordingPage` presented `ReasonFormView` in a native large sheet, leaving no space above its clipped top edge. The card filled available height instead of matching the supplied empty, focused, and filled frames.

The wrap share panel had Save and Share, while Instagram Story and Messages were available only through existing destination handlers or the system activity sheet. The requested final behavior is four visible buttons directly on Rush Hour's panel.

## Changes
1. Present the reason form in a transparent full-screen modal. Draw the existing recording view through an 80% black dim, with the rounded drawer at the bottom and the Figma artwork behind its top edge. Keep the pending-prompt identity, Submit/Cancel callbacks, save-error alert, notification cancellation, and dismissal restriction.
2. Match the reason card, watermark, title, placeholder, buttons, and focused drawer geometry to Figma. Use exact local Retina exports for the header and watermark and reuse the existing dotted background. Focus raises the drawer; keyboard overlap reduces the editor's visible area so long reasons remain editable above the keyboard. The native Done action and VoiceOver escape dismiss the keyboard.
3. Add visible Instagram Story and Messages buttons alongside Save and Share in the shared portrait/landscape action row. Reuse the existing assets and `WrapShareViewModel` handlers, including capability checks, error messages, and attachment/export logic. Save still writes to Photos; Share still opens the native activity sheet.

## Design references
Figma file: https://www.figma.com/design/WWMtHXoNzhu8kjOgyHc1RJ/Challenge-3
- Empty: `97:1291`; typing: `97:1325`; filled: `97:1359`.
- Header export: `97:1295`; card watermark: `97:1317`.
- Related issue: #62.

## Review and complexity
No repository complexity gate was found. Lizard 1.24.0 reports the new reason-card helper at 4, the buttons helper at 2, and the existing pill helper unchanged at 2. Recording-method maximum remains 6, with the same 34 methods. Share-composer method complexities are unchanged (maximum 5). SwiftUI computed bodies also received a manual control-flow review.

The review corrected two layout issues: scale the reason buttons with a 44-point minimum target so they fit narrow phones, and use a dark presentation with a light editor appearance so the status bar remains legible while the keyboard stays light. Layout-budget assertions passed at 320x568, 375x812, and 402x874.

Design/correctness and Ponytail passes found no remaining blocker. Existing handlers/components/assets are reused; no dependency or speculative abstraction is added. Designed-module/registry pass is not applicable: this changes SwiftUI presentation/components, not a module contract or dispatch registry. RAMA was skipped at the user's request.

Time-complexity smell scan: constant-time geometry and four static action buttons; no new collection loop, pagination, concurrency primitive, or per-item external I/O. Existing reason trimming remains linear in the text length. No performance optimization is claimed.

## Verify
Requires Xcode and development-team signing access for a physical device.

```sh
xcodebuild -project lucky7.xcodeproj -scheme RushHourDev -configuration Dev -destination 'generic/platform=iOS' -allowProvisioningUpdates build
xcodebuild -project lucky7.xcodeproj -scheme RushHourDev -configuration Dev -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

1. During recording, request a break from a blocked app and return to Rush Hour. Verify the artwork peeks above the dimmed drawer and blank input disables Submit.
2. Focus the editor, enter a long reason, and scroll to the end. The cursor should stay above the keyboard. Done should return to the lowered drawer while preserving text.
3. Submit to save the reason before unlocking, or Cancel to return without unlocking. A failed save must keep the app blocked and retain the form for retry.
4. Open a portrait and a landscape wrap. Verify Save, Share, Instagram Story, and Messages all appear. Save writes to Photos; Share opens the native sheet; the two shortcuts use their respective app/composer or show the existing availability error.

## Validation completed
- [x] User validated #62 on iPhone (3) before the final review adjustments.
- [x] Final signed RushHourDev/Dev build and simulator build passed against `develop` with Xcode 27.1.
- [x] Native modal fixtures rendered empty, filled, focused/long-text, and `.accessibility3` states. The focused editor was the first responder, retained light appearance, and its ending cursor remained above the keyboard.
- [x] Native portrait/landscape share-panel fixtures showed all four buttons at 402- and 320-point widths. Action wiring was checked against the existing production handlers; fixture actions were stubbed to avoid external sharing.
- [x] Twelve production break-method scenarios passed using a temporary fixture adding the missing `showResumeReminder` field. The repository's unmodified script has the same fixture omission on develop; no repository test files were changed.
- [x] Local asset dimensions, Retina metadata, source call sites, and rendered slots checked; `git diff --check` passed.
- [ ] Live Instagram Story handoff and Messages attachment sending on a configured phone.
- [ ] Full VoiceOver gestures, iPad/floating keyboard, and rotation matrix.

## Compatibility and scope
No app identity, entitlements, data model, storage, or dependency changes. This branch is based on develop and excludes the separate recording/onboarding work in PR #80. Existing sessions and selected apps are preserved. Instagram/Messages capabilities still depend on the installed apps and device configuration; their direct buttons remain visible and use the existing errors when unavailable.
