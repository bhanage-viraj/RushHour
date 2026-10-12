# Rush Hour Dev / TestFlight

## Problem and agreed scope

The team needs beta builds alongside the App Store app. A Git branch alone does not change installed app identity. The user chose `develop` and TestFlight distribution.

Reuse the existing app, four extensions, release settings and app icon. Add one `Dev` configuration and the shared `RushHourDev` scheme. No duplicated app target, environment framework, CI automation, production data migration or redesign.

## Identity

| Setting | Production (Debug/Release) | Dev |
| --- | --- | --- |
| App name | Rush Hour | Rush Hour Dev |
| Bundle ID | com.andrianangg.Rush-Hour | com.andrianangg.Rush-Hour.dev |
| App Group | group.com.andrianangg.Traffic-Man | group.com.andrianangg.Traffic-Man.dev |

Each extension keeps its existing suffix under the selected app bundle ID. The app and three Screen Time extensions read `RushHourAppGroup` from their own Info.plist; entitlements resolve the same build setting. Separate app containers isolate SwiftData, preferences and media. The production scheme keeps its current identifiers. The Dev scheme uses release settings for representative beta testing.

## Verification plan / readiness

Ready for local implementation: inspect resolved build settings and built Info.plists/entitlements for the app and all four extensions; compare Debug/Release production identifiers; build and archive with the Dev scheme; run existing break and camera checks. Signed TestFlight upload is dependent on Apple account capabilities and App Store Connect setup, not just a successful unsigned archive.

## Build

```sh
xcodebuild -project lucky7.xcodeproj -scheme RushHourDev -destination 'generic/platform=iOS' -archivePath /private/tmp/RushHourDev.xcarchive archive
```

For a compilation/archive-layout check without provisioning, add `CODE_SIGNING_ALLOWED=NO`. An unsigned archive cannot be uploaded or installed as a TestFlight build.

## Apple setup before TestFlight

Register the Dev app and these extension bundle IDs on the production team's developer account:

- `com.andrianangg.Rush-Hour.dev`
- `com.andrianangg.Rush-Hour.dev.RushHourShieldConfig`
- `com.andrianangg.Rush-Hour.dev.RushHourShieldAction`
- `com.andrianangg.Rush-Hour.dev.RushHourJailBreakMonitor`
- `com.andrianangg.Rush-Hour.dev.RushHourWidget`

Register `group.com.andrianangg.Traffic-Man.dev` and attach it to the app plus the three Screen Time extensions. Enable Family Controls on those four identifiers and verify distribution approval; also verify the app-and-website-usage capability used by the app and shield configuration target. The widget needs its separate identifier but does not currently use the App Group.

Create a separate App Store Connect record for `Rush Hour Dev` with the Dev bundle ID. Archive the `RushHourDev` scheme, upload to this record, and select a TestFlight testing group. External testing may require Beta App Review. Keep the production App Store record and its builds unchanged.

Sources: [App identity](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [TestFlight distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases), [Family Controls approval](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement).

## Verified results

- Dev device archive and simulator build passed with the iOS 27 SDK.
- App Store Connect distribution export passed: `/private/tmp/RushHourDev-TestFlight/lucky7.ipa` (19,685,410 bytes).
- App plus four extensions have distinct Dev identifiers; the app and Screen Time extensions share only the Dev App Group. Distribution signatures and entitlements were verified.
- Debug and Release resolve the original production bundle IDs and App Group.
- Dev installed and launched on the iOS 27 simulator beside the production app; its data container differed and the production container path stayed unchanged.
- All 12 existing break checks and the camera geometry/segment-export checks passed.
- TestFlight upload is not complete: Apple rejected the upload because no App Store Connect app record exists for `com.andrianangg.Rush-Hour.dev`. Create that separate record, then retry upload.
- Physical-device coexistence and TestFlight install/update behavior have not been checked.
