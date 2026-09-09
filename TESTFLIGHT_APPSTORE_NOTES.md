# TestFlight and App Store Connect Setup Notes

This document tracks project changes made to get KevLines successfully uploadable to TestFlight and aligned with App Store Connect requirements.

## 2026-09-02 — Kinetriq 3.5.5 (50)

### TestFlight / App Store Connect
- Marketing version `3.5.5`, build `50`. Includes everything listed under 3.5.4 (49) below.
- **Paywall ↔ loading flash loop (shipped bug, hit every non-subscriber).** Signing in without an active entitlement left the app cycling between the launch loading view and the paywall several times a second, with no way out — the account stayed signed in across relaunches, so only deleting the app escaped it.
  - `ContentView` renders `loadingView` *instead of* `PaywallView` whenever `PurchaseService.isLoading` is true. Raising that flag therefore unmounts the paywall and cancels its `.task` — and that task's `recoverEntitlementsIfNeeded()` was itself what raised the flag. The paywall tore down the work it had just started, `isLoading` cleared, the paywall re-entered, and its `.task` fired again. RevenueCat serving `customerInfo()` from cache is what made each lap only a few milliseconds.
  - `refreshStatus(showsLoadingGate:)` now defaults to **silent**. Only the launch lookup in `configure()` raises the gate; sign-in raises it through `identify(appUserID:)`, which keeps a subscriber from flashing past the paywall while `logIn` resolves. Paywall recovery, offer-code redemption, foregrounding, and the Settings/Account refreshes all update entitlements in place.
- What's New copy is in `docs/AppStoreListing.md` (section 5).
- Archive as **Any iOS Device (arm64)**, then Organizer → Distribute App → App Store Connect.

## 2026-08-27 — Kinetriq 3.5.4 (49)

### TestFlight / App Store Connect
- Marketing version `3.5.4`, build `49`.
- Sign in with Apple (and email/password) no longer fail after a successful Supabase `200` when `user.created_at` has fractional seconds (`NSCocoaErrorDomain 4864`). Auth JSON is decoded with `ISO8601Timestamp`; leftover decode errors use `AUTH-DECODE`.
- Row rep counting: elbow gates **140° / 100°** (was 150° / 90°) so the hang and squeeze actually cross the counter.
- What's New copy is in `docs/AppStoreListing.md` (section 5).
- Archive as **Any iOS Device (arm64)**, then Organizer → Distribute App → App Store Connect.

## 2026-08-17 — Kinetriq 3.5.3 (48)

### TestFlight
- Marketing version `3.5.3`, build `48`. Same code as build `46` (score bands + overlay smoothing).
- Build `47` was a re-upload of the older `45` archive and is missing overlay smoothing — testers should use `48` (or `46`), not `47`.

## 2026-08-15 — Kinetriq 3.5.3 (46)

### TestFlight
- Marketing version `3.5.3`, build `46`.
- Custom alignment overlays (center foot, forearm, lower leg, back) now use planted-anchor lock + 1€ / spike-rejection smoothing so guide lines no longer flicker on MediaPipe snaps.

## 2026-08-15 — Kinetriq 3.5.3 (45)

### TestFlight / App Store Connect
- Marketing version `3.5.3`, build `45`. Build `44` was already used by the 2026-08-14 upload of 3.5.2, so this release increments past it.
- Form-score refinements: banded ROM consistency, concentric fatigue excluded from the numeric score, fast-eccentric control penalty, and matching coaching notes.
- What's New copy is in `docs/AppStoreListing.md` (section 5).
- Archive as **Any iOS Device (arm64)**, then Organizer → Distribute App → App Store Connect. MediaPipe `Upload Symbols Failed` warnings are expected and non-blocking.

## 2026-06-09 — Kinetriq 3.4.3 (31)

### TestFlight build notes
- Bumped marketing version to `3.4.3` and build number to `31` for a new TestFlight upload.
- `3.4.2` build `26` was working well before this broader UX/exercise pass and should be treated as the known-good fallback if testers report regressions.
- Added Dips, renamed Barbell Row to Row, added full-screen analyzed-video playback, centered Home FAQ text, changed tempo rounding to the 0.6-second threshold, and added default-off custom exercise overlays for saved video and live analysis.

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
