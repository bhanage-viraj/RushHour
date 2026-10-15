# Landscape wrap sharing

## Background and previous behavior
Landscape recordings already preserved their aspect ratio, but the share composer still used the portrait layout and metadata scale. The newer local implementation needs to ship separately from the earlier orientation fix.

## Changes
1. Select a vertical template carousel and compact share panel when the extracted poster is wider than it is tall. Reuse the existing card, selection binding, accessible template adjustment, and share-button components. Add the landscape design assets and native navigation header. Hide only the vertical carousel’s top scroll-edge effect: iOS otherwise blurs the upper card behind the header when Transparent is selected, whereas Figma node 47:1609 keeps it sharp at 50% opacity.
2. Use `WrapOverlayLayout` to share landscape unit/top-spacing calculations between SwiftUI preview and `ExportEngine`. Portrait values are retained. Review preview/export alignment together.
3. Add Save to Photo using `PhotoLibrarySaver` for the prepared video or transparent PNG, retaining permission denial and save-error reporting. Existing destination flows and output caching are reused. The native Back button is disabled while exporting/saving, preventing its cleanup from deleting a video that Photos is still consuming. Success banners are attached to the NavigationStack’s safe-area layout, below the navigation title in both landscape and portrait sharing.

## Time complexity
Static smell scan: at most three template cards; constant-time layout calculations. One existing Photos operation per save. No new per-record external I/O, unbounded collection, or pagination was added.

## Verify
```sh
xcodebuild -project lucky7.xcodeproj -scheme RushHourDev -configuration Dev -destination 'generic/platform=iOS' -allowProvisioningUpdates build
python3 scripts/check-camera-orientation.py
python3 scripts/check-share-cards.py E8EE0633-8278-48A4-8F24-7321EAABBE1E /private/tmp/rushhour-landscape-cards
```
The share check requires an already booted iOS 27 simulator. Signing requires team access.

- [x] Signed Dev build with iOS 27 SDK.
- [x] Existing share-card geometry/render checks: 18 passed, zero overflow failures.
- [x] Existing camera orientation and segment stitching checks: 6 passed.
- [x] Install and launch Rush Hour Dev on iPhone (3).
- [x] User confirmed horizontal centering, template selection, and successful Photos saving on iPhone (3) before the header correction.
- [x] Temporary iOS 27 production-composer render comparison: upper poster stripes remain sharp; pixels below the header are unchanged after disabling the top scroll-edge effect.
- [x] User confirmed the corrected upper-card/header appearance on the phone.
- [x] Review fix 1: temporary production-composer harness checks the native toolbar item is disabled while busy and enabled after completion.
- [x] Review fix 2: rendered Saved to Photos and Copied to Clipboard banners below the title; portrait copy banner also passes the position check.
- [ ] User confirmation of both review fixes in the newly installed phone build.
- [ ] Photos denial and individual video/PNG export variants; successful save confirmed by user.
- [ ] Actual Instagram, WhatsApp, and Messages handoff.

## Compatibility and limits
No data migration, new dependency, or app identity change. Instagram Messages and WhatsApp use the system share sheet, where the user selects the destination. Instagram Stories retains the existing story-format export. Other local shield/signing experiments are outside this change.
