# TestFlight and App Store Connect Setup Notes

This document tracks project changes made to get KevLines successfully uploadable to TestFlight and aligned with App Store Connect requirements.

## 2026-03-31

### Privacy and metadata
- Added `PRIVACY.md` for App Store Connect Privacy Policy URL.
- Set display name to `KevLines` via `INFOPLIST_KEY_CFBundleDisplayName` to avoid "Beta" naming in app display metadata.

### App icons
- Added `Sources/Assets.xcassets/`.
- Added `Sources/Assets.xcassets/AppIcon.appiconset/`.
- Added a non-placeholder `AppIcon-1024.png`.
- Set `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in `project.yml`.

### Device targeting
- Set `TARGETED_DEVICE_FAMILY: "1"` in `project.yml` to make the app iPhone-only (removes iPad screenshot requirement for App Store metadata).

### Framework validation workaround (MediaPipe binary framework)
- Added a pre-build script in `project.yml` to patch third-party framework plist values in Swift Package checkout.
- Added a post-build script in `project.yml` to patch the embedded `MediaPipeTasksVision.framework/Info.plist` in the app bundle before archive validation.
- Patched keys required by App Store validation:
  - `MinimumOSVersion`
  - `CFBundleShortVersionString`
  - `CFBundleVersion`
  - `CFBundlePackageType` (`FMWK`)
- Removed XCFramework-only keys from embedded framework plist when present:
  - `AvailableLibraries`
  - `XCFrameworkFormatVersion`

### Project generation
- Regenerated `KevLines2.0.xcodeproj` from `project.yml` after settings changes (`xcodegen generate`).

## Operational notes
- `Upload Symbols Failed` warnings for `MediaPipeTasksVision.framework` and `MediaPipeCommonGraphLibraries.framework` are expected with some prebuilt third-party binaries and are typically non-blocking for TestFlight availability.
- After any metadata/build-setting changes, archive and upload a fresh build number.
