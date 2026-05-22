# Guidance for AI coding agents — Kinetriq

Use this file when picking up work on this repo. It summarizes architecture, conventions, and pitfalls **without replacing** the full [README](README.md).

> **Origin:** This codebase is KevLines 3.3.8 renamed to Kinetriq for public launch. KevLines development history lives at [KevLines2.0](https://github.com/theroosterjones/KevLines2.0).

## Product

**Kinetriq** — iOS 17+ SwiftUI app for **on-device** exercise form analysis and movement assessments: pose (MediaPipe), joint angles, rep counting, tempo, optional HUD/score, letter-graded assessments. **No backend** — camera + photo library only.

## Current release metadata (source of truth)

| Field | Location |
|--------|-----------|
| Marketing version | `project.yml` → `MARKETING_VERSION` |
| Build number | `project.yml` → `CURRENT_PROJECT_VERSION` |
| Xcode project | Generated — run **`xcodegen generate`** after editing `project.yml` |

- Bundle id: `com.kevinjones.Kinetriq`
- Module name: `Kinetriq`
- Test imports: `@testable import Kinetriq`
- Xcode project: `Kinetriq.xcodeproj`

## Repo layout

| Path | Purpose |
|------|---------|
| `project.yml` | XcodeGen spec, versions, MediaPipe plist patch scripts, SPM `SwiftTasksVision` |
| `Sources/` | All app code + `pose_landmarker_full.task` (gitignored — see README for curl) |
| `Tests/` | Unit tests |
| `docs/` | Technical notes (VideoOrientation, Troubleshooting) |
| `AGENTS.md` | This file |

## App navigation structure

```
TabView (default: Home)
├── Home        (HomeView)          — branding + quick-action cards; logo TBD
├── Workout     (ExerciseView)      — saved-video & live analysis
├── History     (WorkoutHistoryView)— "coming soon" placeholder
└── Settings    (SettingsView)
```

## Pipelines (two modes)

1. **Saved video:** `VideoReader` → `PoseLandmarkerService` → `FrameAnalyzerProtocol` → `OverlayRenderer` on pixel buffer → `VideoWriter`. Orchestrated by `VideoProcessor`.
2. **Live camera:** `CameraService` → same pose + analyzer → `MetalCameraRenderer` + SwiftUI `OverlayCanvas` for preview; when recording, `OverlayRenderer` + `LiveVideoRecorder`.

Analyzers implement **`ExerciseAnalyzer`** or **`AssessmentAnalyzer`** (both conform to **`FrameAnalyzerProtocol`**).

## Critical implementation notes

### Saved-video decode orientation (do not regress)

**Do** use **`AVMutableVideoComposition` + `AVAssetReaderVideoCompositionOutput`** as in `Sources/Core/Video/VideoReader.swift`. Full rationale: **[docs/VideoOrientation.md](docs/VideoOrientation.md)**.

### MediaPipe timestamp reset (critical — do not regress)

`PoseLandmarkerService` runs in `.video` mode requiring **strictly increasing timestamps**. `VideoProcessor` is a `@StateObject` that lives for the entire app session. Every new analysis must call **`poseLandmarker.resetForNewSession()`** before the read loop begins. Skipping this causes 0% detection on every analysis after the first.

### Angles and smoothing

- **Overlay:** normalized 2D `landmarks` for drawing.
- **Angles:** prefer **`worldLandmarks`** + `AngleCalculator.angle3D`, fallback to 2D `angle()`.
- **Smoothing:** `LandmarkSmoother` — separate **`smooth`** (2D) and **`smooth3D`** (3D); always pass **`landmarks.timestamp`** for correct Δt offline.

### Tempo rounding

All four tempo slots use **`.rounded(.down)`** so durations are never overstated (3.4 s → 3, 0.9 s → 0).

### TempoTracker phase direction

`TempoTracker` has `invertPhases: Bool` (default `false`).

| Value | Angle ↓ (joint closes) | Angle ↑ (joint opens) | Use for |
|-------|------------------------|----------------------|---------|
| `false` | eccentric | concentric | Squat, Deadlift, Lunge, Hip Hinge, OHP |
| `true` | **concentric** | **eccentric** | Elbow Curl, Row, Lat Pulldown |

`pauseBottom` = end of eccentric (lengthened position); `pauseTop` = end of concentric (shortened/contracted).

### Rep counting conventions

- Standard: **`RepCounter(extendedThreshold:flexedThreshold:)`** — larger angle = extended.
- `ElbowAnalyzer`: `extendedThreshold: 140` (not 155 — world-landmark arm extension reads 140–155°; 155 caused 0 reps).
- `HipHingeBackAnalyzer`: self-calibrating trunk-height signal; locks thresholds after 3 reps.
- Squat: `extendedThreshold: 150` (accommodates real-world camera angles).

### Exercise library

| Type | Analyzer | View | Notes |
|------|----------|------|-------|
| Squat | `SquatAnalyzer` | Side | Hip angle HUD; extendedThreshold 150° |
| Deadlift | `DeadliftAnalyzer` | Side | Film 15–30° off strict side |
| Lunge | `LungeAnalyzer` | Side | Hip angle HUD |
| Hip Hinge (Side) | `HipHingeSideAnalyzer` | Side | |
| Hip Hinge (Back) | `HipHingeBackAnalyzer` | Rear | Self-calibrating rep count |
| Barbell Row | `RowAnalyzer` | Side | Auto-side fallback; invertPhases: true |
| Lat Pulldown/Chin Up (Side) | `LatPulldownAnalyzer` | Side | invertPhases: true |
| Lat Pulldown/Chin Up (Front) | `LatPulldownFrontAnalyzer` | Front/Back | Bilateral; invertPhases: true |
| Overhead Press | `OverheadPressAnalyzer` | Front/Back | Bilateral |
| Elbow (Bicep/Tricep) | `ElbowAnalyzer` | Side | extendedThreshold 140°; invertPhases: true |

### Assessment library

| Type | Planes | Notes |
|------|--------|-------|
| Shoulder Flexion | Frontal, Sagittal | |
| Squat Assessment | Frontal, Sagittal | Depth-aware lean grading (< 90° knee = more forgiving) |
| Hip Hinge Assessment | Frontal, Sagittal | |

## Testing

- Target: **KinetriqTests**; physical iPhone for Metal live preview.
- `@testable import Kinetriq` in all test files.

## What to avoid

- Drive-by refactors unrelated to the task.
- Editing `*.task` model binaries in git.
- Changing `VideoReader` without reading **docs/VideoOrientation.md**.
- Forgetting **`xcodegen generate`** after `project.yml` changes.
- Skipping `resetForNewSession()` before a saved-video analysis run.

## Open to-do (v1.x)

- [ ] Kinetriq logo asset → replace `HomeView` SF Symbol placeholder
- [ ] Full workout history persistence (Core Data or SwiftData)
- [ ] App Store submission (privacy policy, screenshots, metadata)
- [ ] Additional exercises
- [ ] Export analysis summary

Last updated: **Kinetriq 1.0.0** build **1**.
