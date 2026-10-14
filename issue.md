# Add an isolated Rush Hour Dev build for TestFlight

The team needs beta builds on their phones alongside the App Store app. The existing scheme uses the production bundle ID and shared Screen Time App Group, so merely building a `develop` branch would replace that installed app.

## Changes

1. Reuse all five existing targets and add a release-based `Dev` configuration plus the `RushHourDev` scheme.
2. Select the app name, root bundle ID and App Group through project build settings. Extension identifiers retain their existing suffixes under the Dev app ID.
3. Resolve the App Group through each bundle's Info.plist and the matching entitlement setting. Production Debug/Release settings retain their original identity.

No new dependency, duplicated app target, schema migration or CI automation. Time-complexity scan: no new loop, collection, concurrency or pagination shape; the bundle metadata lookup is O(1).

## Verification

- [x] Dev device archive, distribution IPA export and simulator build pass with the iOS 27 SDK.
- [x] App and extension bundle IDs, group entitlements and signatures verified; production Debug/Release identities unchanged.
- [x] Dev installs beside production in the simulator with separate data containers; production container unchanged.
- [x] Existing 12 break-state checks and camera geometry/segment-export checks pass; whitespace check passes.
- [x] TestFlight upload: Apple accepted version 1.0 (3) on 14 October 2026 and reported package processing after the separate app record was created.
- [ ] Physical-device coexistence and TestFlight install/update behavior.

Run commands, identifiers and Apple account setup are documented in [development-builds.md](docs/development-builds.md). The Account Holder's capabilities must support the Dev identifiers; a development signature alone is insufficient for TestFlight. Distribution export was verified, but TestFlight processing and external Beta App Review are separate steps.
