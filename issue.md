# Align recording and onboarding layouts with Figma

## Background and previous behavior
The compact/expanded recording screens used different camera and control geometry, and the paused glow could extend outside the camera frame. Onboarding used four progress segments, content-driven card heights, older illustration sizes, and a different background/button treatment from the supplied frames.

## Changes
1. Introduce `RecordingLayout` as the shared geometry for the existing HomePage camera, standalone recording camera, and recording controls. Compact and expanded states use the supplied Figma positions, including the paused badge and controls. Keep one live camera preview in the embedded flow and retain the existing pause, end, break, export, and persistence callbacks.
2. Replace the duplicated recording chrome with `RecordingControls` and the matching timer shell. Clip the paused glow and top shade inside the camera frame; bundle the Figma patterns and blur assets as Retina PNGs because the asset catalog did not preserve the SVG blur filters.
3. Match the onboarding card margins, title line spacing, illustration placement, three progress segments, and Continue button to Figma. Reuse the existing sample video and native Screen Time picker. Request notifications through the existing guarded system-permission helper on the first screen. Screen Time authorization remains on step 3 Continue, followed by the unchanged three-selection gate.
4. Keep Back on steps 2 and 3. Select 3 Apps has no Back button, as requested. Preserve the full-screen dotted background and the lock badge's source pattern.
5. Above the default Dynamic Type size, let onboarding titles wrap naturally and scroll the growing card while keeping Back/progress and Continue outside the scrolling region. Keep the default Figma geometry. Expose recording state, captured-frame count, and remaining time on the shared HomePage camera through the existing accessibility helper.

## Design references
- Compact recording: Figma `76:740`, `76:692`; expanded/paused recording: `76:824`, `76:868`.
- App selection: Figma `76:618`, `76:642`.
- Onboarding/notification prompt: Figma `78:1072`, `78:1075`, `78:1131`, `78:1203`.
- File: https://www.figma.com/design/WWMtHXoNzhu8kjOgyHc1RJ/Challenge-3
- Related issues: #57, #63, #65. These references do not close the issues automatically.

## Time complexity
Static smell scan: layout calculations are constant-time. Progress bars iterate over three items; the recording timer has three panels and two separators. The lock's pattern renders a fixed 71-by-69 grid (4,899 local image draws), independent of the selected apps and recording duration. No per-item external I/O, pagination, new dependency, or unbounded collection is introduced. This is not a measured performance optimization.

## Verify
```sh
xcodebuild -project lucky7.xcodeproj -scheme RushHourDev -configuration Dev -destination 'generic/platform=iOS' -allowProvisioningUpdates build
python3 scripts/check-camera-orientation.py
```
Signing requires access to the development team. For a simulator build, use destination `generic/platform=iOS Simulator` with `CODE_SIGNING_ALLOWED=NO`.

1. On a fresh onboarding flow, check steps 1–3 against the Figma references. Verify that Back returns from 3 to 2 and from 2 to 1, and that app selection has no Back.
2. Confirm Continue stays disabled below three selections and finishes onboarding with at least three selections. Relaunch normally to verify completion persists.
3. Start a recording; pause/resume and switch between compact and expanded modes. The timer/camera should remain aligned, the camera should stay live, and the paused glow should stay inside its frame.
4. Increase text size through accessibility sizes; verify headings remain readable, the card scrolls, and Continue remains reachable. With VoiceOver, focus the camera while recording and paused; verify its spoken state, frame count, and remaining time.

## Validation completed
- [x] Signed RushHourDev/Dev build with Xcode 27.1; simulator build passed.
- [x] The initial PR build was installed and launched on iPhone (3), iOS 27.0.1. The accessibility follow-up signed build passed; its installation is pending a USB reconnect after a developer disk image mount failure.
- [x] User confirmed Continue works with at least three selections after the final normal launch.
- [x] Six existing camera orientation and real segment-stitching checks passed.
- [x] Isolated recording render/geometry checks covered four states at 402x874, 375x812, and 320x568; paused shading did not change pixels outside the compact camera frame.
- [x] Native-navigation onboarding captures verified the default-size card and button geometry, complete title lines, and lock badge pattern/icon dimensions against Figma. Permission services and picker data were isolated in the visual fixture; the real picker/Continue was checked on the phone.
- [x] Twelve break scenarios passed with a temporary fixture adding the missing `showResumeReminder` state. The unmodified repository check fails to compile on both develop and this branch because its fixture lacks that state; no repository test files were changed.
- [x] Accessibility follow-up: all three production onboarding screens captured at `.accessibility3` and `.accessibility5`, including programmatic scrolling to their bottoms; Continue stayed visible. Default-size card/button/title geometry checks still passed.
- [x] Assert-based checks passed for running, advancing frame count, paused, and idle spoken camera values; source wiring verified the shared camera reads live published state and uses `updatesFrequently`. Live VoiceOver gestures remain unchecked.
- [x] `git diff --check` passed.
- [ ] Full real-device recording/pause/expand/end and VoiceOver interaction matrix.

## Review findings resolved
1. **Larger text clipped onboarding headings:** removed fixed title-line heights above `.large`, let the card grow, and added a vertical scroll viewport with progress/Back and Continue outside it. Native captures verified all three screens at `.accessibility3` and `.accessibility5`; default-size Figma geometry remains unchanged.
2. **Embedded recording lost spoken capture progress:** the shared HomePage camera now reuses `AccessibilitySupport.cameraPreviewValue` with live recording/paused state, frame count, and countdown, matching the standalone camera. Focused value assertions and the signed build passed; live VoiceOver interaction remains a manual check.

## Review passes
Complexity: no repository complexity gate found; Lizard 1.24.0 reports complexity 10 for the new controls function, with existing recording-method maximum unchanged at 6. The follow-up card helper is complexity 4; HomePage methods have no complexity increase. SwiftUI computed-property bodies also received a manual control-flow check. Design/correctness: both reported accessibility findings are fixed and received focused verification; no additional finding in the follow-up diff. Designed-module/registry contract pass: not applicable; this diff changes SwiftUI layout/components, not a provider or module registry. Ponytail: the shared geometry and controls replace duplicated code; no additional lean-only finding. RAMA skipped at the user's request.

## Compatibility
No app identity, entitlement, data-model, storage migration, or new dependency change. Existing sessions and app selections remain intact. Notification-dialog text and appearance are owned by iOS. The PR remains a draft for the final device check. No merge is included.
