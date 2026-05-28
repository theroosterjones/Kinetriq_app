# Kinetriq 3.4.0 — On-Device Movement Intelligence

> **This is KevLines 3.0** — the public-launch evolution of the private [KevLines2.0](https://github.com/theroosterjones/KevLines2.0) research project. All core technology carries forward; this repo is the clean, user-facing branch.

Kinetriq is a fully local iOS 17+ app that analyzes exercise form and movement quality using on-device AI pose estimation (MediaPipe). No server, no cloud, no subscription. Point your camera at yourself, pick a saved video, or run a movement screen — and get instant biomechanical feedback: joint angles, skeleton overlay, rep counts, tempo phases, and letter-graded assessments.

---

## What's new vs KevLines

| Area | Change |
|------|--------|
| App name & bundle ID | `KevLines` → `Kinetriq` (`com.kevinjones.Kinetriq`) |
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

---

## Feature overview

### Exercise analysis
Film from the side (or front/back for bilateral exercises). The app overlays skeleton, joint angles, rep count, and a live 4-phase tempo string (`ecc-pauseBot-con-pauseTop`). All four phases floor-round so durations are never overstated.

| Exercise | View | Notes |
|----------|------|-------|
| Squat | Side | Hip angle on HUD (display-only) |
| Deadlift | Side | Film 15–30° off strict side to avoid bar occlusion |
| Lunge | Side | Hip angle on HUD (display-only) |
| Hip Hinge (Side) | Side | Plumb-line hip cue |
| Hip Hinge (Back) | Rear | Self-calibrating rep counter (first 3 reps set thresholds) |
| Barbell Row | Side | Auto-side fallback |
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
- **Angles:** `worldLandmarks` + `AngleCalculator.angle3D`, 2D fallback; smoothed via `LandmarkSmoother` (1€ filter).
- **Tempo direction:** `TempoTracker(invertPhases: true)` for pull/curl exercises (Row, Lat Pulldown, Elbow Curl) so that the working phase is always labeled "concentric."
- **MediaPipe session reset:** `PoseLandmarkerService.resetForNewSession()` must be called before each saved-video analysis run to prevent 0% detection on second+ runs (timestamp monotonicity requirement).

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

- [ ] Kinetriq logo & branding assets
- [ ] Full workout history persistence and session browser
- [ ] App Store submission prep (privacy policy, screenshots, metadata)
- [ ] Additional exercises (cable fly, pull-up, etc.)
- [ ] Export / share analysis summary as PDF or image
