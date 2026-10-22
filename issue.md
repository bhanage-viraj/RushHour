# UI implementation notes

## Recording and onboarding — PR #80
### Background and previous behavior
The compact/expanded recording screens used different camera and control geometry, and the paused glow could extend outside the camera frame. Onboarding used four progress segments, content-driven card heights, older illustration sizes, and a different background/button treatment from the supplied frames.

### Changes
1. Introduce `RecordingLayout` as the shared geometry for the existing HomePage camera, standalone recording camera, and recording controls. Compact and expanded states use the supplied Figma positions, including the paused badge and controls. Keep one live camera preview in the embedded flow and retain the existing pause, end, break, export, and persistence callbacks.
2. Replace the duplicated recording chrome with `RecordingControls` and the matching timer shell. Clip the paused glow and top shade inside the camera frame; bundle the Figma patterns and blur assets as Retina PNGs because the asset catalog did not preserve the SVG blur filters.
3. Match the onboarding card margins, title line spacing, illustration placement, three progress segments, and Continue button to Figma. Reuse the existing sample video and native Screen Time picker. Request notifications through the existing guarded system-permission helper on the first screen. Screen Time authorization remains on step 3 Continue, followed by the unchanged three-selection gate.
4. Keep Back on steps 2 and 3. Select 3 Apps has no Back button, as requested. Preserve the full-screen dotted background and the lock badge's source pattern.
5. Above the default Dynamic Type size, let onboarding titles wrap naturally and scroll the growing card while keeping Back/progress and Continue outside the scrolling region. Keep the default Figma geometry. Expose recording state, captured-frame count, and remaining time on the shared HomePage camera through the existing accessibility helper.

### Design references
- Compact recording: Figma `76:740`, `76:692`; expanded/paused recording: `76:824`, `76:868`.
- App selection: Figma `76:618`, `76:642`.
- Onboarding/notification prompt: Figma `78:1072`, `78:1075`, `78:1131`, `78:1203`.
- File: https://www.figma.com/design/WWMtHXoNzhu8kjOgyHc1RJ/Challenge-3
- Related issues: #57, #63, #65. These references do not close the issues automatically.

### Time complexity
Static smell scan: layout calculations are constant-time. Progress bars iterate over three items; the recording timer has three panels and two separators. The lock's pattern renders a fixed 71-by-69 grid (4,899 local image draws), independent of the selected apps and recording duration. No per-item external I/O, pagination, new dependency, or unbounded collection is introduced. This is not a measured performance optimization.

### Verify
```sh
xcodebuild -project lucky7.xcodeproj -scheme RushHourDev -configuration Dev -destination 'generic/platform=iOS' -allowProvisioningUpdates build
python3 scripts/check-camera-orientation.py
```
Signing requires access to the development team. For a simulator build, use destination `generic/platform=iOS Simulator` with `CODE_SIGNING_ALLOWED=NO`.

1. On a fresh onboarding flow, check steps 1–3 against the Figma references. Verify that Back returns from 3 to 2 and from 2 to 1, and that app selection has no Back.
2. Confirm Continue stays disabled below three selections and finishes onboarding with at least three selections. Relaunch normally to verify completion persists.
3. Start a recording; pause/resume and switch between compact and expanded modes. The timer/camera should remain aligned, the camera should stay live, and the paused glow should stay inside its frame.
4. Increase text size through accessibility sizes; verify headings remain readable, the card scrolls, and Continue remains reachable. With VoiceOver, focus the camera while recording and paused; verify its spoken state, frame count, and remaining time.

### Validation completed
- [x] Signed RushHourDev/Dev build with Xcode 27.1; simulator build passed.
- [x] The initial and accessibility-follow-up PR builds were installed and launched on iPhone (3), iOS 27.0.1.
- [x] User confirmed Continue works with at least three selections after the final normal launch.
- [x] Six existing camera orientation and real segment-stitching checks passed.
- [x] Isolated recording render/geometry checks covered four states at 402x874, 375x812, and 320x568; paused shading did not change pixels outside the compact camera frame.
- [x] Native-navigation onboarding captures verified the default-size card and button geometry, complete title lines, and lock badge pattern/icon dimensions against Figma. Permission services and picker data were isolated in the visual fixture; the real picker/Continue was checked on the phone.
- [x] Twelve break scenarios passed with a temporary fixture adding the missing `showResumeReminder` state. The unmodified repository check fails to compile on both develop and this branch because its fixture lacks that state; no repository test files were changed.
- [x] Accessibility follow-up: all three production onboarding screens captured at `.accessibility3` and `.accessibility5`, including programmatic scrolling to their bottoms; Continue stayed visible. Default-size card/button/title geometry checks still passed.
- [x] Assert-based checks passed for running, advancing frame count, paused, and idle spoken camera values; source wiring verified the shared camera reads live published state and uses `updatesFrequently`. Live VoiceOver gestures remain unchecked.
- [x] `git diff --check` passed.
- [ ] Full real-device recording/pause/expand/end and VoiceOver interaction matrix.

### Review findings resolved
1. **Larger text clipped onboarding headings:** removed fixed title-line heights above `.large`, let the card grow, and added a vertical scroll viewport with progress/Back and Continue outside it. Native captures verified all three screens at `.accessibility3` and `.accessibility5`; default-size Figma geometry remains unchanged.
2. **Embedded recording lost spoken capture progress:** the shared HomePage camera now reuses `AccessibilitySupport.cameraPreviewValue` with live recording/paused state, frame count, and countdown, matching the standalone camera. Focused value assertions and the signed build passed; live VoiceOver interaction remains a manual check.

### Review passes
Complexity: no repository complexity gate found; Lizard 1.24.0 reports complexity 10 for the new controls function, with existing recording-method maximum unchanged at 6. The follow-up card helper is complexity 4; HomePage methods have no complexity increase. SwiftUI computed-property bodies also received a manual control-flow check. Design/correctness: both reported accessibility findings are fixed and received focused verification; no additional finding in the follow-up diff. Designed-module/registry contract pass: not applicable; this diff changes SwiftUI layout/components, not a provider or module registry. Ponytail: the shared geometry and controls replace duplicated code; no additional lean-only finding. RAMA skipped at the user's request.

### Compatibility
No app identity, entitlement, data-model, storage migration, or new dependency change. Existing sessions and app selections remain intact. Notification-dialog text and appearance are owned by iOS. The combined application code was reviewed against develop after PR #81: simulator build, six camera/orientation checks, twelve break scenarios with the documented fixture correction, twelve recording layouts, and native onboarding/large-text captures passed. The documentation conflict was resolved by retaining both implementation notes.

## Reason drawer and direct sharing — PR #81
### Background and previous behavior
Issue #62 reports missing artwork above the reason drawer. `RecordingPage` presented `ReasonFormView` in a native large sheet, leaving no space above its clipped top edge. The card filled available height instead of matching the supplied empty, focused, and filled frames.

The wrap share panel had Save and Share, while Instagram Story and Messages were available only through existing destination handlers or the system activity sheet. The requested final behavior is four visible buttons directly on Rush Hour's panel.

### Changes
1. Present the reason form in a transparent full-screen modal. Draw the existing recording view through an 80% black dim, with the rounded drawer at the bottom and the Figma artwork behind its top edge. Keep the pending-prompt identity, Submit/Cancel callbacks, save-error alert, notification cancellation, and dismissal restriction.
2. Match the reason card, watermark, title, placeholder, buttons, and focused drawer geometry to Figma. Use exact local Retina exports for the header and watermark and reuse the existing dotted background. Focus raises the drawer; keyboard overlap reduces the editor's visible area so long reasons remain editable above the keyboard. The native Done action and VoiceOver escape dismiss the keyboard.
3. Add visible Instagram Story and Messages buttons alongside Save and Share in the shared portrait/landscape action row. Reuse the existing assets and `WrapShareViewModel` handlers, including capability checks, error messages, and attachment/export logic. Save still writes to Photos; Share still opens the native activity sheet.

### Design references
Figma file: https://www.figma.com/design/WWMtHXoNzhu8kjOgyHc1RJ/Challenge-3
- Empty: `97:1291`; typing: `97:1325`; filled: `97:1359`.
- Header export: `97:1295`; card watermark: `97:1317`.
- Related issue: #62.

### Review and complexity
No repository complexity gate was found. Lizard 1.24.0 reports the new reason-card helper at 4, the buttons helper at 2, and the existing pill helper unchanged at 2. Recording-method maximum remains 6, with the same 34 methods. Share-composer method complexities are unchanged (maximum 5). SwiftUI computed bodies also received a manual control-flow review.

The review corrected two layout issues: scale the reason buttons with a 44-point minimum target so they fit narrow phones, and use a dark presentation with a light editor appearance so the status bar remains legible while the keyboard stays light. Layout-budget assertions passed at 320x568, 375x812, and 402x874.

Design/correctness and Ponytail passes found no remaining blocker. Existing handlers/components/assets are reused; no dependency or speculative abstraction is added. Designed-module/registry pass is not applicable: this changes SwiftUI presentation/components, not a module contract or dispatch registry. RAMA was skipped at the user's request.

Time-complexity smell scan: constant-time geometry and four static action buttons; no new collection loop, pagination, concurrency primitive, or per-item external I/O. Existing reason trimming remains linear in the text length. No performance optimization is claimed.

### Verify
Requires Xcode and development-team signing access for a physical device.

```sh
xcodebuild -project lucky7.xcodeproj -scheme RushHourDev -configuration Dev -destination 'generic/platform=iOS' -allowProvisioningUpdates build
xcodebuild -project lucky7.xcodeproj -scheme RushHourDev -configuration Dev -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

1. During recording, request a break from a blocked app and return to Rush Hour. Verify the artwork peeks above the dimmed drawer and blank input disables Submit.
2. Focus the editor, enter a long reason, and scroll to the end. The cursor should stay above the keyboard. Done should return to the lowered drawer while preserving text.
3. Submit to save the reason before unlocking, or Cancel to return without unlocking. A failed save must keep the app blocked and retain the form for retry.
4. Open a portrait and a landscape wrap. Verify Save, Share, Instagram Story, and Messages all appear. Save writes to Photos; Share opens the native sheet; the two shortcuts use their respective app/composer or show the existing availability error.

### Validation completed
- [x] User validated #62 on iPhone (3) before the final review adjustments.
- [x] Final signed RushHourDev/Dev build and simulator build passed against `develop` with Xcode 27.1.
- [x] Native modal fixtures rendered empty, filled, focused/long-text, and `.accessibility3` states. The focused editor was the first responder, retained light appearance, and its ending cursor remained above the keyboard.
- [x] Native portrait/landscape share-panel fixtures showed all four buttons at 402- and 320-point widths. Action wiring was checked against the existing production handlers; fixture actions were stubbed to avoid external sharing.
- [x] Twelve production break-method scenarios passed using a temporary fixture adding the missing `showResumeReminder` field. The repository's unmodified script has the same fixture omission on develop; no repository test files were changed.
- [x] Local asset dimensions, Retina metadata, source call sites, and rendered slots checked; `git diff --check` passed.
- [ ] Live Instagram Story handoff and Messages attachment sending on a configured phone.
- [ ] Full VoiceOver gestures, iPad/floating keyboard, and rotation matrix.

### Compatibility and scope
No app identity, entitlements, data model, storage, or dependency changes. These notes preserve the reason-drawer and sharing changes already merged into develop through PR #81 alongside PR #80’s recording/onboarding work. Existing sessions and selected apps are preserved. Instagram/Messages capabilities still depend on the installed apps and device configuration; their direct buttons remain visible and use the existing errors when unavailable.

## End Session and Discard Session drawers — issue #66

### Background and changes
The End Session X occupied a full row below the drag indicator, pushing the content down. The completed-session Discard confirmation used a native sliding sheet with a separate layout and dim layer.

1. Match the shared `SessionConfirmSheet` to Figma: top-right X outside content flow, 12-point side margins, 16-point bottom inset, 24-point corners and spacing, 2-point black border, 50% black dim, and existing design color assets. Keep its 44-point close target and existing End/Cancel callbacks; let headings grow and keep action labels on one line at larger text sizes.
2. Reuse that component for the completed-session Discard drawer. Fade it over the Details screen, clear keyboard focus when Back opens it, hide the covered screen from accessibility, and support VoiceOver Escape through the shared cancel callback. Remove the superseded native-sheet configuration and duplicated card contents. Keep the existing save/delete/error-handling code.

### Design references
- End Session compact: https://www.figma.com/design/WWMtHXoNzhu8kjOgyHc1RJ/Challenge-3?node-id=114-1520
- End Session expanded: https://www.figma.com/design/WWMtHXoNzhu8kjOgyHc1RJ/Challenge-3?node-id=114-1536
- Discard Session: https://www.figma.com/design/WWMtHXoNzhu8kjOgyHc1RJ/Challenge-3?node-id=116-1566

### Verification
- [x] RushHourDev/Dev simulator and signed device builds passed with Xcode 27.1.
- [x] End drawer rendered at 402-, 375- and 320-point widths, compact/expanded, default and accessibility text sizes (12 combinations). Default-size geometry checks confirmed the 213-point card, side/bottom insets and X position.
- [x] Native iOS 26.5 and iOS 27 simulator captures verified both drawers and bottom safe-area placement. Discard captures confirmed the 50% dim and were exercised after focusing the title field and at accessibility text size.
- [x] Temporary completed-session fixture used production view/callback code and in-memory SwiftData: Cancel retained the title, description, session and break log; Discard removed the session and break log and invoked completion. Recording/media services were stubbed in this isolated check; the production deletion implementation is unchanged.
- [x] Both updates installed on iPhone (3); user confirmed they look good.
- [x] `git diff --check` passed.
- [ ] Live VoiceOver gestures and iPad layout.

```sh
xcodebuild -project lucky7.xcodeproj -scheme RushHourDev -configuration Dev -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project lucky7.xcodeproj -scheme RushHourDev -configuration Dev -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

On a phone, open End Session in compact and expanded recording and cancel using X or Cancel. Finish a session, enter Details text, tap Back and confirm the drawer fades over a darker background. Cancel must preserve the text; Discard must exit through the existing deletion flow. Repeat with larger text.

### Time complexity and compatibility
Static smell scan: no new loop, query, concurrency or pagination shape. A fixed view hierarchy replaces duplicated presentation code; existing deletion and export work is unchanged. No data-model, app-identity, entitlement or dependency changes.


### PR #82 review follow-up: large-text overflow
Resolved the review finding at 320×568 with the largest accessibility text size. `ViewThatFits` retains the intrinsic card when it fits; otherwise the same card is available through a height-limited native `ScrollView`. The existing cancel/confirm callbacks and modal accessibility remain shared.

Verification: all six default-size End/Discard renders at 320-, 375- and 402-point widths are pixel-identical before/after the follow-up. The original 18 width/content/text-size combinations were rendered again; the scroll fallback was verified natively because `ImageRenderer` does not capture its native scrolling content. A 320×568 native host with a 20-point top safe area reported a viewport at y=20–552, 551-point content, and successful scrolling from offset −20 to −1 to expose the bottom buttons. Native captures confirmed the close button at the initial scroll position and complete action buttons after scrolling. All 17 fitting layouts were pixel-identical to their pre-fix renders. The final simulator build, signed device build and whitespace check passed; live VoiceOver gestures remain unchecked.

## Monthly rewind background — issue #70

### Background and changes
The monthly rewind row used the bright system red/yellow/green gradient and lacked the texture and border in Figma frame `121:1678`. Update only `RewindRow` to the supplied darker color stops, three local vector dot textures, 16-point corners, black border, and matching play-icon/content spacing. Scale the textures with the row width and allow titles to wrap when they need more space.

Design: https://www.figma.com/design/WWMtHXoNzhu8kjOgyHc1RJ/Challenge-3?node-id=121-1678&m=dev
Issue: https://github.com/bhanage-viraj/RushHour/issues/70

The existing My Sessions callsite still controls recap eligibility and monthly video navigation. No persistence, generation, playback, signing, or dependency changes. Native Canvas gradient interpolation was retained after comparing it with the Figma reference; the three texture images are the supplied SVGs, with no runtime download.

### Review and time complexity
- Correctness/design/Ponytail review: no blocking finding. One existing row callsite, one view implementation, three referenced assets; no new abstraction or dependency.
- No repository complexity gate found. Manual control-flow count for `RewindRow.body` is 1 before and after (no branches). Lizard 1.24.0 reports parsed function scores [1, 2, 3] before and after, but misattributes a SwiftUI function name after nested view closures; the computed view body therefore received manual review.
- Designed-module/registry check: not applicable; no module contract, factory, or registry changes. RAMA skipped at the user's request.
- Time-complexity smell scan: fixed-size presentation with three texture layers; no new collection loop, query, pagination, concurrency, or per-item external I/O. No performance optimization claimed.

### Verify
Requires Xcode; device builds also require development-team signing access.

```sh
xcodebuild -project lucky7.xcodeproj -scheme RushHourDev -configuration Dev -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project lucky7.xcodeproj -scheme RushHourDev -configuration Dev -destination 'generic/platform=iOS' -allowProvisioningUpdates build
git diff --check
```

Open My Sessions with an existing generated monthly recap. Check its Rewind row against the Figma frame, then tap it to open the existing monthly wrap. Try a long month name and larger text: the title should wrap and the row should grow without hiding its duration.

### Validation completed
- [x] Simulator and signed RushHourDev/Dev builds passed with Xcode 27.1 (27A9275).
- [x] Sixteen isolated production-row renders passed: widths 280/335/354/362, May/September, default/Accessibility 3 text. The default May row at width 354 is 59 points high. The fixture source matches production `RewindRow`.
- [x] Asset manifests and vector files validated; whitespace check passed.
- [x] Installed the signed Dev build on iPhone (3); user replied “done” and requested PR/review after testing.
- [ ] Live VoiceOver not tested. The existing combined title/duration label and playback hint are preserved; the background is hidden from accessibility.
