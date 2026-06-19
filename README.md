# Kinetriq 3.4.0 — On-Device Movement Intelligence

> **This is KevLines 3.0** — the public-launch evolution of the private [KevLines2.0](https://github.com/theroosterjones/KevLines2.0) research project. All core technology carries forward; this repo is the clean, user-facing branch.

Kinetriq is an iOS 17+ app that analyzes exercise form and movement quality using on-device AI pose estimation (MediaPipe). Analysis stays on-device, while account login and subscription access use Supabase Auth and RevenueCat so users can carry Pro access across iOS, future Android, and a future web UI. Point your camera at yourself, pick a saved video, or run a movement screen — and get instant biomechanical feedback: joint angles, skeleton overlay, rep counts, tempo phases, and letter-graded assessments.

---

## What's new vs KevLines

| Area | Change |
|------|--------|
| App name & bundle ID | Display name `KevLines` → `Kinetriq`. Bundle ID still `com.kevinjones.KevLines2-0` during testing; migrates to `com.kevinjones.Kinetriq` at launch (see Roadmap) |
| Version reset | Starts at `1.0.0` build `1` |
| Navigation | New **Home** tab (first, opens on launch); Workout → History → Settings |
| History tab | "Coming soon" placeholder — full history tracking in a future release |
| Module name | `Kinetriq` (tests import `@testable import Kinetriq`) |

---

## Documentation map

| Doc | Audience |
|-----|----------|
| **[AGENTS.md](AGENTS.md)** | AI assistants / developers — architecture, version pins, pitfalls |
| **[docs/README.md](docs/README.md)** | Index of technical notes in `docs/` |
| **[docs/VideoOrientation.md](docs/VideoOrientation.md)** | Required before editing `VideoReader` — orientation pipeline |
| **[docs/Troubleshooting.md](docs/Troubleshooting.md)** | Active bugs and investigation notes |
| **[docs/Subscriptions.md](docs/Subscriptions.md)** | RevenueCat, Supabase Auth, product IDs, promo codes, and sandbox checklist |
| **[docs/WebBackend.md](docs/WebBackend.md)** | Supabase backend, RevenueCat webhooks, promo redemption, and future web UI |

---

## Feature overview

### Exercise analysis
Film from the side (or front/back for bilateral exercises). The app overlays skeleton, joint angles, rep count, and a live 4-phase tempo string (`ecc-pauseBot-con-pauseTop`). Optional exercise-only alignment overlays can be enabled for center foot, forearm, lower leg, and back references. All four tempo phases round up only when the fractional seconds are at least 0.6.

| Exercise | View | Notes |
|----------|------|-------|
| Squat | Side | Hip angle on HUD (display-only) |
| Deadlift | Side | Film 15–30° off strict side to avoid bar occlusion |
| Lunge | Side | Hip angle on HUD (display-only) |
| Hip Hinge (Side) | Side | Plumb-line hip cue |
| Hip Hinge (Back) | Rear | Self-calibrating rep counter (first 3 reps set thresholds) |
| Row | Side | Auto-side fallback |
| Dips | Side | Elbow reps plus shoulder angle relative to chest/torso |
| Lat Pulldown/Chin Up (Side) | Side | |
| Lat Pulldown/Chin Up (Front) | Front/Back | Bilateral, no side select |
| Overhead Press | Front/Back | Bilateral |
| Elbow / Bicep / Tricep | Side | |

### Movement assessments
Letter-graded (A–F) sub-metrics with a "weakest-link" overall grade.

| Assessment | Planes |
|------------|--------|
| Shoulder Flexion | Frontal, Sagittal |
| Squat Assessment | Frontal, Sagittal (depth-aware torso lean grading) |
| Hip Hinge Assessment | Frontal, Sagittal |

### Key implementation notes

- **Pose:** MediaPipe Tasks Vision (on-device, no network) via SwiftTasksVision SPM package.
- **Video decode:** `AVMutableVideoComposition` + `AVAssetReaderVideoCompositionOutput` — do not change without reading `docs/VideoOrientation.md`.
- **Saved-video import:** keep the Photos-prepared file path first. `PickedMovie` should use `shouldAttemptToOpenInPlace: false` so Photos prepares/copies a compatible temporary video. Requesting the original in place (`true`) caused `CoreTransferable.TransferableSupportError 0` on videos that previously loaded. Direct `PHAsset` / `AVAsset` access and original-file access should remain fallback paths only.
- **Angles:** `worldLandmarks` + `AngleCalculator.angle3D`, 2D fallback; smoothed via `LandmarkSmoother` (1€ filter).
- **Tempo direction:** `TempoTracker(invertPhases: true)` for pull/curl exercises (Row, Lat Pulldown, Elbow Curl) so that the working phase is always labeled "concentric."
- **MediaPipe session reset:** `PoseLandmarkerService.resetForNewSession()` must be called before each saved-video analysis run to prevent 0% detection on second+ runs (timestamp monotonicity requirement).
- **Accounts/subscriptions:** Supabase Auth provides the cross-device user ID. RevenueCat maps App Store purchases to `kinetriq_pro`. Backend promo/comp entitlements are combined with RevenueCat in the app-level `hasProAccess` decision.

---

## Development setup

```bash
# Clone
git clone https://github.com/theroosterjones/Kinetriq_app.git
cd Kinetriq_app

# Download MediaPipe model (not committed — ~25 MB)
curl -L -o Sources/pose_landmarker_full.task \
  https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task

# Generate Xcode project
xcodegen generate

# Open and run on a physical iPhone (Metal required for live preview)
open Kinetriq.xcodeproj
```

---

## Changelog

### v3.4.3 — Exercise expansion and customizable overlays

- **Known-good fallback** — `3.4.2` build `26` was working well before this larger UX pass. If testers report regressions in exercise selection, overlays, saved-video playback, or Home screen layout, use `3.4.2 (26)` as the return point.
- **Dips exercise added** — side-profile Dips analyzer with working-side wrist, elbow, shoulder, hip, knee, and ankle landmarks; elbow reps; and shoulder angle relative to chest/torso.
- **Exercise naming updated** — `Barbell Row` is now displayed as `Row` so it fits barbell, dumbbell, machine, and cable variations.
- **Analyzed-video playback** — saved analyzed videos now include a full-screen playback option.
- **Home FAQ polish** — FAQ questions and answers are center-aligned for a cleaner Home screen.
- **Custom exercise overlays** — exercise analysis only, default off: Center Foot, Forearm Alignment, Lower Leg Alignment, and Back Alignment. Row forearm and Lunge lower-leg reference lines are now optional through this menu instead of always-on.
- **Tempo rounding updated** — tempo display now rounds up at fractional seconds ≥ 0.6 and rounds down below 0.6.
- **Marketing / build** — `3.4.3` (31).

### v3.4.2 — Hip Hinge (Side) rep counting for incline hip extension

- **Hip Hinge (Side) rep thresholds updated** — `extendedThreshold` 155° → 150°; `flexedThreshold` 65° → 105°. The old 65° floor was never reached on an incline hip extension machine (range ~165°–95°), causing 0 reps counted. 105° captures both machine stops at ~95° and deep free-weight hinges that pass through 105° on the way down.
- **Angle measurement clarified** — hip angle continues to use shoulder→hip→knee (spine-line vs femur-line, 3D world landmarks preferred). No calculation change; thresholds were the only issue.
- **Extended reference lines** — thin yellow lines now extend the spine vector and femur vector beyond the hip joint, visually confirming the measured angle on-screen. Vertical plumb line retained.
- **Saved-video import regression fixed** — restored Photos-prepared video import as the primary load path. Do not make `shouldAttemptToOpenInPlace: true` the first path again; it caused `TransferableSupportError 0` for multiple Photos videos that previously uploaded. The safe order is: Photos-prepared file import → direct `PHAsset` / `AVAsset` fallback → original-file-in-place fallback.
- **Marketing / build** — `3.4.2` (26).

### v3.4.1 — Video loading fix

- **Video loading error resolved** — `PickedMovie.transferRepresentation` now includes `.audiovisualContent`, `.movie`, `.quickTimeMovie`, and `.mpeg4Movie` representations to handle all video formats iOS exports (HEVC, MOV, MP4), eliminating `TransferableSupportError error 0`.
- **Marketing / build** — `3.4.1` (21).

### v3.4.0 — UI polish, rep counting fixes, extended line overlays

- **Removed Shoulder Assessment from Exercises list** — it remains available under Assessments only.
- **Elbow curl rep counting fix** — `flexedThreshold` raised from 55° → 85°. Real-world peak bicep curl flexion commonly reads 70–90°; the 55° threshold never triggered, causing 0 reps counted.
- **Extended reference lines** — Lunge now shows a shin reference line (ankle → knee extended, cyan). Deadlift now shows a spine reference line (hip → shoulder extended, cyan), matching the forearm lines on Row and Lat Pulldown.
- **Default overlay changed** — Full HUD is now the default mode; Simple is the alternative.
- **Home tagline** — updated to "Movement Intelligence."
- **Settings redesigned** — Pose Detection, Smoothing, and Tempo Tracking moved inside a collapsible "Advanced Settings" disclosure group. Disclaimer added at the bottom.
- **Marketing / build** — `3.4.0` (20).

### v3.3.9 — Public launch baseline (≡ KevLines 3.3.8 + Kinetriq rebrand)

- Renamed from KevLines to **Kinetriq**; bundle ID, module name, and display name updated throughout.
- **Home tab** added as the first tab (house icon); app opens to Home on every launch.
- **History tab** — "Coming soon" placeholder; full history tracking planned for a future release.
- All KevLines 3.3.x improvements carried forward:
  - Elbow curl 0-rep fix (extendedThreshold 155° → 140°)
  - Correct eccentric/concentric direction for Row, Lat Pulldown, Elbow Curl (`invertPhases: true`)
  - All four tempo phases floor-round (3.4 s → 3, 0.9 s → 0)
  - Hip Hinge (Back) self-calibrating rep counter
  - Lat Pulldown/Chin Up front-view bilateral analyzer
  - Depth-aware squat torso lean grading
  - Pose tracking rate diagnostic in results UI
  - MediaPipe session reset fix (0% detection on 2nd+ run)
  - Video decode via AVMutableVideoComposition (orientation stable)

---

## Roadmap

- [ ] **Bundle ID migration at launch** — the app currently ships under the existing KevLines identifier `com.kevinjones.KevLines2-0` so the already-registered App Store Connect app and RevenueCat project keep working through TestFlight testing. **At public launch, recreate everything as Kinetriq:** new App ID/bundle ID `com.kevinjones.Kinetriq`, new App Store Connect app record, new RevenueCat app, and re-point the entitlement/products. Until then, leave the bundle ID unchanged.
- [ ] Kinetriq logo & branding assets
- [ ] Full workout history persistence and session browser
- [ ] App Store submission prep (privacy policy, screenshots, metadata)
- [ ] Additional exercises (cable fly, pull-up, etc.)
- [ ] Export / share analysis summary as PDF or image
