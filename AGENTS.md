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
- `LatPulldownAnalyzer` (Side): reps are driven by the **shoulder** angle (`hip→shoulder→elbow`), not elbow flexion — `RepCounter(extendedThreshold: 120, flexedThreshold: 70)`, `invertPhases: true`. Elbow flexion counted 0 reps because world-landmark arm extension tops out near 140–150° and never crossed the old 150° extended threshold.

### Sagittal joint-tip markers

`JointTip.position(vertex:toward:and:offset:)` (in `AngleCalculator.swift`) offsets a bent-joint marker onto the bony tip (olecranon / patella) — the convex side of the bend, opposite the interior bisector. Used **display-only** in side views for knee dots (Squat, Deadlift, Lunge) and elbow dots (Lat Pulldown Side, Elbow, Row, Dips); never used for angle or rep math. Falls back to the joint center when the limb is straight (so it's a no-op for the near-straight knee in a hip hinge, which is why Hip Hinge Side gets spike rejection but no tip marker).

### Landmark spike rejection

`LandmarkSmoother.smooth`/`smooth3D` take an optional `maxSpeed` (coordinate units/second) velocity limiter that clamps single-frame MediaPipe snaps while letting real motion through. Applied to every side-view analyzer: leg chains (Squat, Deadlift, Lunge, Hip Hinge Side) at **2D 2.5 / 3D 4.0**, and arm chains (Lat Pulldown Side, Elbow, Row, Dips) at **2D 3.0 / 3D 5.0**. Anchored landmarks (lunge ankle, dips wrist via `stabilizeAnchor`) are left as-is.

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
| Lat Pulldown/Chin Up (Side) | `LatPulldownAnalyzer` | Side | Reps driven by **shoulder** angle (hip→shoulder→elbow), thresholds 120/70; invertPhases: true |
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

Last updated: **Kinetriq 3.5.3** build **48** (same binary as 46; build-number bump so TestFlight “latest” is the complete 3.5.3). Changes vs 3.5.3/45:
1. **Custom overlay smoothing** — center-foot, forearm, lower-leg, and back alignment lines now share `CustomOverlayState` smoothing: planted points (foot, ankle) lock against MediaPipe jitter; moving joints use the 1€ filter plus the same 2D spike caps as the analyzers (leg 2.5, arm 3.0) so extended guide lines no longer snap.

History: **3.5.3** build **45** (feature/bugfix). Changes vs 3.5.2/43:
1. **Banded ROM consistency scoring** — peak-angle SD maps to discrete ROM scores: 0–1.5° → 100, 2–3° → 90, 4–5° → 80, 6–7° → 70, 8–10° → 50, 11–12° → 40, 12–13° → 30, 14–15° → 20, above 15° → 0.
2. **Fatigue is not a score penalty** — concentric duration is excluded from tempo consistency so a set that slows on the way up no longer loses points. Coaching still notes concentric slowing as fatigue and a challenging set.
3. **Fast-eccentric control caveat** — reps with an eccentric of 1.0 s or faster subtract up to 25 points (scaled by how many reps are rushed) and get a readout that the reps lack control.

History: **3.5.2** build **43** (feature/bugfix). Changes vs 3.5.1/42:
1. **Returning-subscriber paywall** — `PurchaseService.recoverEntitlementsIfNeeded()` runs when the gate paywall appears: a `customerInfo` refresh and, if still locked out, a one-time silent `restorePurchases()` that transfers an existing Apple-ID subscription onto the current app user ID so subscribers stop seeing the paywall on re-login. (Root cause of a persistent paywall is usually the RevenueCat dashboard "transfer purchases" behavior when a sub was bought under an anonymous/other app user ID — verify that setting too.)
2. **In-app plan management** — `PaywallView` gained an `isManagement` mode (dismissable, with close button; the mandatory gate still has none per 2.1(a)). Settings adds "Change or Upgrade Plan"/"View Plans" presenting it as a sheet, plus a footer explaining monthly↔yearly switching, Apple management, and Restore.
3. **Knee drift in deep flexion** — `LandmarkSmoother.smooth`/`smooth3D` gained an optional `maxSpeed` velocity limiter (spike rejection) applied to the squat hip/knee/ankle chain (2D `2.5` units/s, 3D `4.0` m/s) so single-frame MediaPipe snaps don't yank the landmark while real motion still tracks.
4. **Live exercise dropdown unresponsive (root cause)** — the real problem was that `LiveAnalysisViewModel` published per-frame state (`currentInstructions`, `repCount`, `currentPhase`, `trackingWarningVisible`, `currentScore`) ~30–60×/sec, invalidating the whole `LiveAnalysisView` body every frame so the `Menu`'s press gesture never completed. Fixed by moving that high-frequency state onto a separate `LiveFrameState: ObservableObject` (a plain `let` on the view model) consumed only by small leaf views (`LiveOverlayCanvas`, `LiveRepCountLabel`, `LivePhaseLabel`, `LiveTrackingWarning`). The top bar/menu/record button now observe only low-frequency control state and stay responsive. Also replaced the nested `Menu { Picker { Text.tag } }` with explicit `Button` rows (checkmark on selected) for exercise and assessment menus.
5. **Stay signed in across launches** — Supabase access tokens expire (~1h) and the stored `refreshToken` was never used, so users had to log in every launch. Added `AuthService.refreshSessionIfNeeded(force:)` (grant_type=refresh_token) called on launch (`bootstrap`) and on foreground; `isAuthenticated`/`restoreSession` now treat a session with a refresh token as still-authenticated and renew silently. Only a definitive 4xx rejection of the refresh token signs the user out (offline/5xx keep the session). `AuthSession.isRenewable` added.
6. **Lat pulldown (side) counted 0 reps** — switched `LatPulldownAnalyzer` rep counting + tempo from elbow flexion to **shoulder** angle (upper arm vs. torso line, `hip→shoulder→elbow`), `RepCounter(120/70)`, since world-landmark elbow extension never reached the old 150° extended threshold. Also applied the leg-chain spike-rejection `maxSpeed` limiter to the arm chain and drew the elbow marker on the olecranon tip via new `JointTip`. (Front/bilateral analyzer unchanged.)
7. **Sagittal tip markers + spike rejection (all side-view exercises)** — joint-tip dots (patella/olecranon) and the `maxSpeed` velocity limiter now apply across every side-view analyzer: Squat, Deadlift, Lunge (knee); Lat Pulldown Side, Elbow, Row, Dips (elbow); Hip Hinge Side gets spike rejection only (working joint is the hip; knee stays straight). Display-only tips; rep/angle math unchanged.
8. **Human-readable errors with screenshot codes** — `AuthService.friendlyMessage`/`userFacingMessage` and new `PurchaseService.userFacingMessage(for:)` map auth/StoreKit/RevenueCat/network failures to plain-language guidance plus a short reference code (e.g. `AUTH-400-invalid_credentials`, `IAP-2 (storeProblemError)`, `NET-…`) with a "screenshot this" prompt; user-cancelled purchases return `nil` and no longer show an error alert.

History: builds 38/39 rejected; 40 uploaded but superseded; 41 approved/released; 42 version-bump only. Prior App Review fixes retained: removed in-app promo-code unlock (3.1.1), removed Android reference on login (2.3.10), Terms of Use (EULA)/Privacy links + subscription disclosure on the paywall (3.1.2(c)), removed paywall close button on the gate (2.1(a)), conditional-swap gating + `Purchases.customerInfoStream` observation so the paywall dismisses reliably after purchase (2.1(b)), and App Store description labeling all features as requiring the Kinetriq Pro subscription (2.3.2).
