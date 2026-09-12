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
| `Sources/Persistence/` | SwiftData layer: `AnalysisRecord`, `AnalysisLibrary`, `AnalysisStorage` |
| `Resources/Everkinetic/` | CC BY-SA 4.0 illustrations, **unmodified** — see the warning below |
| `supabase/schema.sql` | Postgres schema: subscriptions, metrics sync, coach tables + RPCs |
| `Tests/` | Unit tests |
| `docs/` | Technical notes (VideoOrientation, Troubleshooting, ContentLibrary, WebsiteCopy, SubscriptionExperiments) |
| `AGENTS.md` | This file |

## App navigation structure

```
TabView (default: Home)
├── Home        (HomeView)          — branding + quick-action cards; logo TBD
├── Workout     (ExerciseView)      — saved-video & live analysis
├── Progress    (WorkoutHistoryView)— real history, trends, CSV export
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

### Supabase auth date decoding (do not regress)

GoTrue `/auth/v1/token` JSON includes `created_at` with microseconds (e.g. `2026-08-27T06:46:52.624123Z`). Foundation’s built-in `.iso8601` strategy **rejects fractional seconds**. After a successful HTTP 200 the decoder throws and the app shows **NSCocoaErrorDomain 4864** (“The data couldn’t be read because it isn’t in the correct format”) — Sign in with Apple (and email/password) look broken even though Supabase already issued a session. Always decode auth JSON with **`ISO8601Timestamp.decodingStrategy`** via **`AuthResponseParser`** in `AuthService`. Covered by `AuthJSONDecodingTests`. Decode failures map to **`AUTH-DECODE`**, not the raw Cocoa string.

### Paywall loading gate (do not regress)

`ContentView` renders `loadingView` **instead of** `PaywallView` whenever `PurchaseService.isLoading` is true, so raising that flag unmounts the paywall and cancels its `.task`. Any status refresh that runs *from* the paywall (`recoverEntitlementsIfNeeded`, offer-code redemption) or from foregrounding must use **`refreshStatus(showsLoadingGate: false)`** — the default. A gated refresh started there tears down the view that started it; `isLoading` then clears, the paywall re-enters, its `.task` fires again, and the app flashes between the loading view and the paywall forever (cached `customerInfo()` makes each lap milliseconds). Only **`configure()`** (launch) and **`identify(appUserID:)`** (sign-in) may raise the gate — sign-in needs it so a subscriber doesn't flash past the paywall while `logIn` resolves.

### Share sheets present with `.sheet(item:)` (do not regress)

Present the post-recording/post-export share sheet with **`.sheet(item: $sharePayload)`** and the `SharePayload` wrapper, never `.sheet(isPresented:)` plus a separate optional URL read inside the closure. With the `isPresented` form the content closure can evaluate before the URL `@State` write lands, the `if let` fails, and the user gets a **blank white sheet** with no way to save the video.

Related: a `private func` on a SwiftUI `View` is **not** main-actor isolated. Calling it as `Task { await someAsyncFunc() }` from a button action hops off the main actor (SE-0338), so any `@State` writes inside race the view update. Mark such methods **`@MainActor`** — see `LiveAnalysisView.toggleRecording()`.

### Accounts, subscriptions, and offer codes

- Supabase Auth provides the stable user ID. After login, pass the Supabase UUID to RevenueCat as the app user ID.
- RevenueCat entitlement: the live one is **`Kinetriq Pro`** (with the space). `kinetriq_pro` and `pro` are also accepted, but nothing is configured under them — every subscriber today is unlocked by `Kinetriq Pro` alone. **Do not "clean up" `acceptedEntitlementIDs`**; dropping that string revokes Pro for every user on both platforms. Verified against live `CustomerInfo` 2026-09-02.
- App Store products: `com.kevinkjones.kinetriq.monthly` and `com.kevinkjones.kinetriq.annual`. The `kevink` spelling is correct — the bundle ID is `com.kevinjones.Kinetriq`, the products are not.
- **App-level Pro access in shipping builds is `active RevenueCat entitlement` only.** A local `developmentUnlocked` shortcut exists **only under `#if DEBUG`** (when no RevenueCat key is configured) and can never grant access in Release. Do not reintroduce any other unlock path.
- **In-app promo-code redemption was removed for App Store compliance (Guideline 3.1.1).** Free months, discounts, and comp access must be granted through **Apple App Store offer codes** (redeemed via `SKPaymentQueue.presentCodeRedemptionSheet()` in-app, or via the App Store) — never through app code, a text field, or a backend call that flips entitlement client-side.
- The Supabase `redeem-promo-code` Edge Function and `promo_codes` table remain in the repo for reference/history but are **not wired to in-app entitlement**. The former `PromoCodeView` and `PromoRedemptionService` were deleted; `SubscriptionAccessState` no longer has a `backendEntitlement` field.
- Setup references: `docs/Subscriptions.md` and `docs/WebBackend.md`.

### Persistence, sync, and coaching (new in 3.6.0)

**SwiftData is the system of record.** Every finished analysis — saved-video *and* live — becomes one `AnalysisRecord` (`Sources/Persistence/`). One table with a `kind` discriminator covers exercises and assessments so Progress, CSV export, and sync each read a single timeline.

- The model's primary key is **`recordID`**, not `id`. `PersistentModel` already supplies `id` for SwiftUI identity, and shadowing it breaks `Identifiable`.
- Media lives in **Application Support/Kinetriq/Media** via `AnalysisStorage`, never `temporaryDirectory` — iOS purges temp and would orphan every video.
- Insert through **`AnalysisLibrary.insert(_:into:)`**, which saves and then kicks off a sync. Do not call `context.insert` directly. The one exception is `SyncService.restore`, which inserts in bulk and stamps `syncedAt` itself precisely because those rows must not be pushed back.
- `AnalysisPayload` holds the non-queryable parts (per-rep metrics, sub-grades, insights) as JSON and doubles as the sync wire format. Insights are stored **at analysis time** and replayed later, never regenerated — regenerating would silently rewrite history when a threshold changes.

**Metrics sync; video never does (do not regress).** `SyncService` uploads `analysis_records` / `analysis_reps` to PostgREST with the user's JWT. There is no video upload path anywhere, no storage bucket, and the privacy copy in `HelpView` and `ConnectCoachView` states this as a promise. Adding video upload is a product decision with legal weight, not a feature.

**Restore pulls measurements back, and only measurements.** `SyncService.restoreIfNeeded(context:)` runs on launch and foreground **before** `syncPending` — a fresh install has everything to receive and nothing to send. It pages `GET rest/v1/analysis_records?select=*,analysis_reps(*)`, dedupes on `recordID`, and stamps `syncedAt` so restored rows are never re-uploaded.

- It runs once per user (`kinetriq.sync.restored.<uuid>` in `UserDefaults`) **or** whenever the local store is empty, so a second reinstall still recovers.
- Decode with **`ISO8601Timestamp.decodingStrategy`**. Postgres `timestamptz` carries microseconds and Foundation's `.iso8601` rejects them — the same trap as the auth JSON above.
- `RemoteAnalysisRecord` is deliberately **separate from** `AnalysisRecordPayload` with every field optional. The upload side can assume a well-formed device model; the download side has to survive rows written by another build. Making one type do both jobs would make the upload side lenient too.
- **A restored record must never claim local media.** `videoFileName` and `thumbnailFileName` stay nil, and UI that plays or shares a clip gates on **`record.hasLocalVideo`** (file existence), not on the name being non-nil. `AnalysisRecordDetailView` shows a "Restored from your account" banner instead of a player. Covered by `SyncRestoreTests`.

**Coach tier.** `coach_roster()` and friends are SECURITY DEFINER RPCs in `supabase/schema.sql`; `CoachService` calls them. A coach reads a linked client's *measurements* only, and only while `coach_clients.status = 'active'`. Coach tooling is gated on **`hasCoachEntitlement`** and is deliberately **not** opened by the DEBUG `developmentUnlocked` path.

**Cross-session coaching.** `TrendInsights` (history) is separate from `CoachingInsights` (one set). Thresholds are blunt first-vs-last comparisons, not fitted slopes — with five to ten sessions a regression line would imply precision the data does not have.

**Technique content is fault-triggered.** `TechniqueLibrary` only shows a lesson when the user's own set produced the measurement behind it (`TechniqueFaultDetector`). `rangeBelowPersonalBest` compares against the user's own deepest recorded angle, never a population norm — Kinetriq has no population data.

### Everkinetic illustrations are CC BY-SA — do not edit them (do not regress)

`Resources/Everkinetic/` holds nine exercise illustrations used **byte-for-byte unmodified** under CC BY-SA 4.0. Share-alike attaches to *adaptations*, so recolouring, cropping, compositing, tracing, or drawing over any of these would oblige Kinetriq to release the result under CC BY-SA. Scaling and framing for display are fine; editing the files is not. Need a different crop? That is a new illustration — commission it.

- Bundled as a **folder reference** in `project.yml`, not an asset catalog, so the originals stay verifiable. Loaded via `ExerciseIllustration.image(named:)`, never `UIImage(named:)`.
- **Every image renders with its credit line** (`ExerciseIllustration.creditLine`) next to it — attribution in a settings screen alone does not satisfy the license. `Settings → Credits & licenses` (`AttributionView`) carries the full attribution plus the bundled license text.
- Illustrations attach **only** to `TechniqueLesson.illustratableFaults` (`inconsistentDepth`, `rangeBelowPersonalBest`). An image cannot show tempo; do not widen this set.
- Full reasoning: **[docs/ContentLibrary.md](docs/ContentLibrary.md)**.

**CSV escaping.** `CSVExporter.escape` scans `unicodeScalars`, not `Characters`. Swift treats CRLF as a single grapheme cluster equal to neither `\r` nor `\n`, so a Character-wise check lets a Windows line break through unquoted and splits the row.

### Rep counting conventions

- Standard: **`RepCounter(extendedThreshold:flexedThreshold:)`** — larger angle = extended.
- `ElbowAnalyzer`: `extendedThreshold: 140` (not 155 — world-landmark arm extension reads 140–155°; 155 caused 0 reps).
- `RowAnalyzer`: `RepCounter(extendedThreshold: 140, flexedThreshold: 100)` — hang never reached 150°; squeeze often sits ~90–110° so 90 never entered `.flexed`.
- `HipHingeBackAnalyzer`: self-calibrating trunk-height signal; locks thresholds after 3 reps.
- Squat: `extendedThreshold: 150` (accommodates real-world camera angles).
- `LungeAnalyzer`: `RepCounter(extendedThreshold: 145, flexedThreshold: 100)`. The front knee in a split stance is never locked out at the top — a measured real rep peaked at **154°**, so the old 155° gate left the counter stuck in `.flexed` and silently dropped reps.
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
| Lunge | `LungeAnalyzer` | Side | Hip angle HUD; knee reps `RepCounter(145/100)` |
| Hip Hinge (Side) | `HipHingeSideAnalyzer` | Side | |
| Hip Hinge (Back) | `HipHingeBackAnalyzer` | Rear | Self-calibrating rep count |
| Row | `RowAnalyzer` | Side | Elbow reps `RepCounter(140/100)`; auto-side fallback; invertPhases: true |
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

## Releasing

`scripts/release.sh` does the whole TestFlight run from the command line — version bump, `xcodegen generate`, archive, distribution export, upload. No Xcode UI needed.

```
scripts/release.sh              # bump build number, keep marketing version
scripts/release.sh 3.5.7        # set marketing version, bump build
scripts/release.sh 3.5.7 55     # both explicit
scripts/release.sh --no-upload  # archive + export only
```

- Archives land in **Xcode's Organizer** (`~/Library/Developer/Xcode/Archives/<date>/`), not the repo.
- Signing is automatic via `-allowProvisioningUpdates`; it creates the App Store distribution profile on demand, so no manual certificate setup is required.
- `manageAppVersionAndBuildNumber` is **false** so App Store Connect can't silently auto-increment the build away from the committed one. The script also verifies the built archive's `CFBundleVersion` matches what was requested before exporting.
- `Upload Symbols Failed` warnings for `MediaPipeTasksVision` / `MediaPipeCommonGraphLibraries` are **expected** — those prebuilt frameworks ship without dSYMs and it does not block TestFlight.
- The script does not commit. Commit the version bump and update the release notes at the bottom of this file afterwards.

## What to avoid

- Drive-by refactors unrelated to the task.
- Editing `*.task` model binaries in git.
- Changing `VideoReader` without reading **docs/VideoOrientation.md**.
- Forgetting **`xcodegen generate`** after `project.yml` changes.
- Skipping `resetForNewSession()` before a saved-video analysis run.
- Decoding Supabase auth JSON with Foundation `.iso8601` (fractional `created_at` → NSCocoaErrorDomain 4864).
- Calling `refreshStatus(showsLoadingGate: true)` from the paywall or from foregrounding (infinite loading ↔ paywall flash).
- Adding any video-upload path. Metrics sync; video stays on device. The app tells users this in writing.
- Editing, recolouring, cropping, or drawing over anything in `Resources/Everkinetic/` (CC BY-SA share-alike).
- Rendering an Everkinetic illustration without its credit line next to it.
- Renaming `AnalysisRecord.recordID` to `id` (collides with `PersistentModel`).
- Writing analysis media to `temporaryDirectory` instead of `AnalysisStorage`.
- Assuming `record.videoURL` points at a file that exists. Restored sessions have no clip — gate on `record.hasLocalVideo`.

## Open to-do (v1.x)

- [ ] Kinetriq logo asset → replace `HomeView` SF Symbol placeholder
- [ ] App Store submission (privacy policy, screenshots, metadata)
- [ ] Additional exercises
- [ ] Export analysis summary
- [x] ~~CC BY-SA illustrations~~ — **decided: nine Everkinetic illustrations bundled unmodified, with visible per-image attribution.** Never edit the files. See `docs/ContentLibrary.md`.
- [ ] Eventually replace them with commissioned art or diagrams rendered from stored pose data — only `ExerciseIllustration` and the folder contents would change
- [ ] Create the coach subscription products in App Store Connect (`com.kevinkjones.kinetriq.coach.*`) — full runbook in `docs/CoachSubscriptionSetup.md`; `CoachRosterView` shows a "not yet available" banner until they exist
- [ ] Apply `supabase/schema.sql` and redeploy `revenuecat-webhook` — `docs/SupabaseDeploy.md`
- [ ] Run the 14-day trial test in `docs/SubscriptionExperiments.md`
- [x] ~~Restore synced history on reinstall~~ — `SyncService.restoreIfNeeded` pulls measurements back on launch; test procedure in `docs/SupabaseDeploy.md` §5
- [ ] Web dashboard for coaches (the Postgres side is already transport-agnostic)

Last updated: **Kinetriq 3.6.0** (unreleased — bump `project.yml` before shipping). Changes vs 3.5.6/51:
1. **Analyses are saved.** New SwiftData layer (`AnalysisRecord`, `AnalysisLibrary`, `AnalysisStorage`) persists every exercise and assessment from both pipelines. Previously every measurement was discarded into `@State` the moment the view went away — the analysis engine was mature and nothing it produced survived. Video and thumbnails move from `temporaryDirectory` into Application Support so they stop disappearing.
2. **Progress tab is real.** `WorkoutHistoryView` replaces the "coming soon" placeholder: filterable session list, score and depth trends, 14-day activity, storage readout, per-session detail with playback, and delete.
3. **Cross-session coaching.** New `TrendInsights` compares a movement's history — score direction, personal bests, depth drift, eccentric control, asymmetry, and layoffs — and needs three sessions before it says anything.
4. **Live analysis produces a summary.** The live pipeline now accumulates session state under an `NSLock` shared with the capture queue and builds an `AnalysisSummary` on Stop, presented in `LiveSessionSummarySheet`. Before this, a live set produced no record at all.
5. **Metrics sync, both directions.** `SyncService` uploads measurements to new `analysis_records` / `analysis_reps` tables with full RLS, and `restoreIfNeeded` pulls them back on a fresh install or a second device, so a reinstall no longer shows an empty Progress tab. **Video never leaves the device** and therefore never comes back: restored sessions show their measurements plus a banner saying the clip stayed on the device that recorded it, and the share/play paths gate on `AnalysisRecord.hasLocalVideo` rather than assuming a file exists. `HelpView` says all of this precisely.
6. **CSV export.** Sessions and per-rep rows, RFC 4180 escaped with a UTF-8 BOM for Excel. Fixed a latent bug where a value containing CRLF went out unquoted, because Swift treats `\r\n` as one Character.
7. **Coach tier.** `coaches` / `coach_invites` / `coach_clients` plus `create_coach_invite`, `redeem_coach_invite`, and `coach_roster` RPCs; `CoachRosterView` orders clients by triage (never started → quiet → slipping → asymmetry) rather than as a feed of clips. Gated on a new `Kinetriq Coach` entitlement that the DEBUG unlock deliberately does not open. Products are not yet created in App Store Connect.
8. **Fault-triggered technique content.** `TechniqueLibrary` surfaces at most two lessons after a set, each triggered by a measurement rather than by the exercise name. Illustration assets deferred pending the CC BY-SA question in `docs/ContentLibrary.md`.
9. **Website copy** rewritten in `docs/WebsiteCopy.md` (paste-ready; the Squarespace site is not in this repo).
10. **RevenueCat webhook handles the coach tier.** It previously mirrored only `kinetriq_pro` and never wrote `coaches.client_limit`, so every coach would have landed on the column default of 15 regardless of tier — a Studio subscriber capped at 15, a Starter subscriber given 15. It now mirrors `Kinetriq Coach` as its own `subscriptions` row and writes the tier's roster cap. A lapse sets `client_limit = 0` rather than deleting the `coaches` row, because `coach_invites` and `coach_clients` cascade from it and a missed payment must not destroy a roster. Product-ID mapping pinned by `supabase/functions/_shared/utils.test.ts`.

**Deploying 3.6.0 needs two out-of-repo steps** — apply `supabase/schema.sql` and redeploy `revenuecat-webhook` (`docs/SupabaseDeploy.md`). The coach tier additionally needs six products created in App Store Connect (`docs/CoachSubscriptionSetup.md`).

History: **3.5.6** build **51**. Changes vs 3.5.5/50:
1. **Live analysis: blank screen instead of the share sheet after Stop** — `LiveAnalysisView.toggleRecording()` was a nonisolated `private func` invoked as `Task { await … }`, so its `@State` writes ran off the main actor; combined with `.sheet(isPresented:)` reading `savedVideoURL` separately inside the closure, the sheet presented before the URL landed and rendered an empty `if let` — a blank white sheet with no way to save the recording. Now `@MainActor` plus `.sheet(item: $sharePayload)`, so the sheet cannot present without its URL. A failed `stopRecording()` also surfaces an alert instead of silently discarding the take.
2. **Lunge dropped reps** — `LungeAnalyzer` extended gate lowered **155° → 145°**. The front knee in a split stance never locks out; a measured real rep peaked at 154°, so the counter stayed in `.flexed` and discarded reps. Covered by `LungeAnalyzerTests`.

History: **3.5.5** build **50**. Changes vs 3.5.4/49:
1. **Paywall ↔ loading flash loop** — `PaywallView`'s `.task` called `recoverEntitlementsIfNeeded()`, which raised `PurchaseService.isLoading`, which made `ContentView` swap the paywall out for `loadingView` and cancel that very task. Clearing the flag re-entered the paywall and re-fired the task, forever. `refreshStatus(showsLoadingGate:)` now defaults to silent; only `configure()` and `identify(appUserID:)` raise the gate. Hit every signed-in non-subscriber on the shipped build.

History: **3.5.4** build **49**. Changes vs 3.5.3/48:
1. **Sign in with Apple JSON decode (NSCocoaErrorDomain 4864)** — GoTrue `created_at` includes fractional seconds; Swift’s `.iso8601` decoder rejected them after HTTP 200 so the session was never stored. `AuthService` now uses `ISO8601Timestamp` (with and without fractional seconds) for token + refresh decode. Remaining decode failures surface as `AUTH-DECODE`.
2. **Row 0 reps** — `RowAnalyzer` elbow gates are now **140° extended / 100° flexed** (were 150 / 90). World-landmark hang never crossed 150°; a typical squeeze sits ~90–110° and never entered `.flexed`. Same 140° hang ceiling as `ElbowAnalyzer`.

History: **3.5.3** build **48** (same binary as 46; build-number bump so TestFlight “latest” is the complete 3.5.3). Changes vs 3.5.3/45:
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
