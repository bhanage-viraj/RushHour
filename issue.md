# Stabilize break submission and center share previews

## Background and previous behavior

Issues #39 and #43 report inconsistent unlock behavior after entering a reason and apparent share-card overlap. A repeat shield event could replace the reason prompt, repeat callbacks could grant or cancel an accepted break, and unlocking preceded successful reason persistence. Break eligibility also used a cached timer value.

Share posters could expand their layout before rounded clipping. The carousel always allocated a portrait card, even for landscape video, and capped its top inset at 10 points rather than centering it vertically.

## Changes

1. Retain the active reason prompt while consuming repeated shield requests. Accept submit/cancel only for that prompt, reject blank reasons, and save the reason before granting access. Failed persistence keeps restrictions and the form available for retry. **Review focus:** the first successful save must precede the unlock; stale cancel callbacks must not delete an accepted record.
2. Deliver shield-return notifications on the main queue, cancel pending fallback notifications once the reason form appears, and calculate break eligibility from the current deadline.
3. Make the allocated card surface own its image and metadata overlays before clipping. Fit every template to the transformed poster's aspect ratio and center it horizontally and vertically above the share panel. Export behavior is unchanged.
4. Remove the unused `PendingPrompt.actionOccurredAt` timestamp and its harness copy; prompt identity now owns callback validation.

## Observable behavior

A valid pasted reason grants one break; repeated submission cannot grant another or let a stale cancellation revoke it. Empty reasons and failed saves leave the app blocked. A 16:9 poster in a 402-point-wide carousel produces a 370 × 208.125-point card instead of a portrait card.

## Time complexity

The Part 1 smell scan found no new scaling bottleneck. Card fitting is O(1), and the carousel has at most three templates. The existing event lookup sorts action/config arrays: O(actionEvents log actionEvents + configEvents log configEvents), plus O(activeBreaks) eligibility scanning. Accepted submission now invokes that lookup once more to consume repeated requests. Event storage and sorting are unchanged; no performance benchmark or optimization is claimed.

## How to verify

Use the booted iOS 27 simulator `E8EE0633-8278-48A4-8F24-7321EAABBE1E`:

```sh
python3 scripts/check-shield-breaks.py E8EE0633-8278-48A4-8F24-7321EAABBE1E
python3 scripts/check-share-cards.py E8EE0633-8278-48A4-8F24-7321EAABBE1E /private/tmp/lucky7-pr-share-card-evidence
xcodebuild -project lucky7.xcodeproj -scheme lucky7 -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/lucky7-pr-build CODE_SIGNING_ALLOWED=NO build
git diff --check
```

- [x] Twelve production-method break-state checks pass, including repeated/stale callbacks, blank reasons, save failure/retry, prompt retention and deadline expiry. Persistence, Screen Time and shared event delivery are boundary doubles.
- [x] Six production card-fitting checks pass for portrait/landscape sources in 320, 402 and 1024-point containers.
- [x] Twelve simulator card renders show zero pixels outside their allocated bounds. They use synthetic posters and fallback fonts, so they prove containment rather than complete branded-screen fidelity.
- [x] Regression evidence: the original fitting method failed all three landscape orientation cases; the original card layout failed four containment cases.
- [x] An iOS 27 device build was signed, installed and launched on the user's iPhone. The user accepted #39 and #43, including the final centering update.
- [x] `git diff --check` passed.

Manual regression checks: start a focus session with two blocked apps; test typed/pasted reasons, rapid submission and cancellation, foreground/notification return paths, and reblocking after 15 minutes. Open both portrait and landscape sessions from the wrap and analytics entry points; swipe through templates and check containment, centering and selected-template sharing. User acceptance was reported in chat; the agent did not observe every manual scenario.

## Scope and compatibility

No schema, signing-setting or export changes. #38's unresolved shield layout/appearance work is excluded from this PR, and #42 remains deferred. Category/domain targeting findings are separate from this fix.

Closes #39. Closes #43.
