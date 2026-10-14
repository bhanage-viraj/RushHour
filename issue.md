# Fix session details, analytics, navigation and screen backgrounds

## Background

The completed session flow needs the supplied Figma Details/discard designs, a return to My Sessions, and readable distraction reasons in saved-session analytics. Onboarding dots covered only the bottom of the screen, and the Home glow was offset from the timer.

## Previous behavior and causes

| Area | Cause | Result |
|---|---|---|
| Details | No back/discard confirmation flow | Users could not leave through the requested confirmation |
| Session exit | Root notification selected Home | Closing a completed session missed My Sessions |
| Analytics | Reasons had no display; token titles bypassed stored names | Individual reasons and reliable app names were unavailable |
| Onboarding | Pattern limited to a bottom strip, with an opaque footer | Incomplete dotted background |
| Home | Independent glow coordinates; complex preview-instrumented accessibility expression | Glow offset and Canvas compiler timeout |

## Changes

1. Apply the Details and saved-session analytics Figma layouts using existing card components and new static assets. The back arrow presents a native discard sheet while the underlying page darkens in place. Cancel keeps the draft; discard saves database deletion before removing media. An export generation guard prevents a late export from reviving a discarded session. Review the deletion and late-export paths carefully.
2. Route completed, early-ended and recovered session flows to My Sessions. Ordinary recording cancellation retains its existing route.
3. Show each distraction's reason and session-clamped duration in chronological order. The pencil edits saved title/reflection. Session deletion also removes its distraction records without touching other sessions.
4. Resolve app names centrally from the saved display name, legacy name, then six exact bundle-ID mappings: Instagram, TikTok, WhatsApp, YouTube, Facebook and X. No match leaves the name blank, as requested; native tokens still render icons. Both session and weekly analytics use this rule. Bundle IDs were checked against Apple's App Store lookup API.
5. Reuse a full-screen onboarding background for all four active steps. Derive the Home glow center from the timer in camera-local coordinates, and explicitly type accessibility strings to fix Canvas compilation. Add Idle/Ready previews with their required environment objects and in-memory model container.

## Time complexity

Static smell-scan: one session-filtered distraction fetch, then linear rendering/deletion in the fetched record count. Chronological sorting can cost O(records log records); storage query/index performance was not benchmarked. No per-row database/network fetch was added. The fixed six-entry name lookup is constant-sized; weekly grouping/sorting retains its existing shape.

## Verify

```sh
xcodebuild -project lucky7.xcodeproj -scheme RushHourDev -configuration Dev -destination 'generic/platform=iOS' -allowProvisioningUpdates build
python3 scripts/check-camera-orientation.py
python3 scripts/check-shield-breaks.py
python3 scripts/check-share-cards.py E8EE0633-8278-48A4-8F24-7321EAABBE1E /tmp/rushhour-share-evidence
```

The share check requires an already booted iOS 27 simulator; replace that UUID with a local simulator ID. The signed build requires the team's signing access.

- [x] Signed Dev build with the iOS 27 SDK.
- [x] Existing camera geometry/segment-export checks, break checks and share-card overflow checks.
- [x] Temporary routing self-check: live/history close and recovery save/discard select My Sessions.
- [x] Temporary real SwiftData analytics harness: session isolation, repeated apps, chronological reasons, clamped durations, empty sessions, valid/invalid editing and deletion isolation.
- [x] Name-resolution self-checks: saved/legacy/localized names, all six exact mappings, missing/unmapped IDs.
- [x] Glow center matches timer at four phone/tablet sizes; Home Canvas rendered Idle and Ready.
- [x] Earlier Dev builds installed and launched on iPhone (3); user accepted the Home appearance.
- [ ] Final deterministic-name display over real Screen Time tokens on iPhone (3).

## Compatibility and limits

No stored schema change, new dependency or production app identity change. Computed name resolution also applies to existing records, but a record without a name or recognized bundle ID intentionally stays blank. Reasons remain the user's original text; work/entertainment classification is not implemented. Device verification of native token icons remains necessary.

Related: #53, #56, #60. The existing Dev/TestFlight setup remains documented in `docs/development-builds.md`.
