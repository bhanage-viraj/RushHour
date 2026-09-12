# Add Rush Hour branding to wrap templates

## Background and previous behavior

The four supplied Figma screens add Rush Hour branding to session sharing. Previously, `WrapMetadataOverlay` and `ExportEngine` rendered only the session title, duration, and date.

## Changes

1. Import the exact Figma logo as a vector asset and place it above session metadata in the wrapped view, styled share preview, and transparent sticker preview.
2. Apply the same logo proportions to exported overlays. Rasterize the logo at output resolution and preserve transparency. The clean template remains free of overlays; the transparent preview badge stays out of exported stickers.
3. Adjust top spacing and date opacity and describe the branding in template accessibility labels.

## Time complexity

No new loop, collection, concurrency, or pagination shape. The added image rasterization uses time and memory proportional to the logo's output pixel area; no performance benchmark was run.

## Verification

- [x] Simulator Debug build passed.
- [x] Signed Debug build passed and was installed and launched on the user's iPhone.
- [x] Rendered portrait and landscape previews and export overlays in a separate simulator harness using the production rendering functions.
- [x] Checked that clean overlays contain no visible pixels and branded overlays preserve transparent backgrounds.
- [x] User completed phone testing and requested merge.
- [x] `git diff --check` passed.

Build command: `xcodebuild -project lucky7.xcodeproj -scheme lucky7 -configuration Debug -destination 'id=00008150-000C50C61A7A401C' -derivedDataPath /private/tmp/lucky7-onboarding-phone-build -allowProvisioningUpdates build`.

## Compatibility

Previously exported videos with baked metadata retain their original appearance. Newly rendered branded overlays include the logo. No signing or device-availability settings change.
