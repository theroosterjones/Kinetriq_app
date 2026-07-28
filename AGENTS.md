# Guidance for AI coding agents — Kinetriq

Use this file when picking up work on this repo. It summarizes architecture, conventions, and pitfalls **without replacing** the full [README](README.md).

> **Origin:** This codebase is KevLines 3.3.8 renamed to Kinetriq for public launch. KevLines development history lives at [KevLines2.0](https://github.com/theroosterjones/KevLines2.0).

## Product

**Kinetriq** — iOS 17+ SwiftUI app for **on-device** exercise form analysis and movement assessments: pose (MediaPipe), joint angles, rep counting, tempo, optional HUD/score, letter-graded assessments. Account login and subscription access use Supabase Auth + RevenueCat so Pro access can work across iOS, future Android, and a future web UI; the movement-analysis pipeline remains on-device.

## Current release metadata (source of truth)

| Field | Location |
|--------|-----------|
| Marketing version | `project.yml` → `MARKETING_VERSION` |
| Build number | `project.yml` → `CURRENT_PROJECT_VERSION` |
| Xcode project | Generated — run **`xcodegen generate`** after editing `project.yml` |

- Bundle id: `com.kevinjones.Kinetriq` (migrated off the KevLines testing identifier; new App Store Connect record, 3.5.x version lineage carried forward)
- Module name: `Kinetriq`
- Test imports: `@testable import Kinetriq`
- Xcode project: `Kinetriq.xcodeproj`

## Repo layout

| Path | Purpose |
|------|---------|
| `project.yml` | XcodeGen spec, versions, MediaPipe plist patch scripts, SPM `SwiftTasksVision` + RevenueCat |
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

All four tempo slots use a **0.6-second threshold**: fractional seconds below 0.6 round down, while 0.6 and above round up (2.5 s → 2, 2.6 s → 3).

### TempoTracker phase direction

`TempoTracker` has `invertPhases: Bool` (default `false`).

| Value | Angle ↓ (joint closes) | Angle ↑ (joint opens) | Use for |
|-------|------------------------|----------------------|---------|
| `false` | eccentric | concentric | Squat, Deadlift, Lunge, Hip Hinge, Dips, OHP |
| `true` | **concentric** | **eccentric** | Elbow Curl, Row, Lat Pulldown |

`pauseBottom` = end of eccentric (lengthened position); `pauseTop` = end of concentric (shortened/contracted).

### Custom exercise overlays

Saved-video and live exercise analysis support user-selected custom alignment overlays via `CustomOverlayOption`; assessments do not. Options default off and are appended after analyzer overlays so hardcoded analyzer lines should not duplicate them.

### Accounts, subscriptions, and offer codes

- Supabase Auth provides the stable user ID. After login, pass the Supabase UUID to RevenueCat as the app user ID.
- RevenueCat entitlement: `kinetriq_pro` (legacy accepted IDs during migration: `pro`, `Kinetriq Pro`).
- App Store products: `com.kevinjones.kinetriq.pro.monthly` and `com.kevinjones.kinetriq.pro.yearly`.
- **App-level Pro access in shipping builds is `active RevenueCat entitlement` only.** A local `developmentUnlocked` shortcut exists **only under `#if DEBUG`** (when no RevenueCat key is configured) and can never grant access in Release. Do not reintroduce any other unlock path.
- **In-app promo-code redemption was removed for App Store compliance (Guideline 3.1.1).** Free months, discounts, and comp access must be granted through **Apple App Store offer codes** (redeemed via `SKPaymentQueue.presentCodeRedemptionSheet()` in-app, or via the App Store) — never through app code, a text field, or a backend call that flips entitlement client-side.
- The Supabase `redeem-promo-code` Edge Function and `promo_codes` table remain in the repo for reference/history but are **not wired to in-app entitlement**. The former `PromoCodeView` and `PromoRedemptionService` were deleted; `SubscriptionAccessState` no longer has a `backendEntitlement` field.
- Setup references: `docs/Subscriptions.md` and `docs/WebBackend.md`.

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
| Row | `RowAnalyzer` | Side | Auto-side fallback; invertPhases: true |
| Dips | `DipsAnalyzer` | Side | Elbow reps; shoulder angle vs chest/torso |
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

Last updated: **Kinetriq 3.5.0** build **41** (App Review resubmission: removed in-app promo-code unlock per Guideline 3.1.1, removed Android reference on the login screen, added Terms of Use (EULA)/Privacy links + subscription disclosure to the RevenueCat paywall. Build 41 fixes the "stuck on paywall after purchase" bug (Guideline 2.1(b)) by gating the app with a plain conditional swap instead of a no-op `fullScreenCover` binding and observing `Purchases.customerInfoStream` so entitlement changes always dismiss the paywall. Builds 38 and 39 were rejected; build 40 was uploaded but superseded before submission.).
